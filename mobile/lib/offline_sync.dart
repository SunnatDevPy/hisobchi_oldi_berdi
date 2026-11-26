import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

final math.Random _idemRng = math.Random.secure();

/// Generates a collision-free idempotency key for at-most-once REST mutations.
String generateIdempotencyKey([String prefix = 'req']) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sb = StringBuffer();
  for (var i = 0; i < 8; i++) {
    sb.write(_idemRng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return '${prefix}_${ts}_${sb.toString()}';
}

/// Pure check for whether a newly polled revision token indicates remote changes.
bool shouldTriggerRemoteSync(String? lastRev, String nextRev) {
  return lastRev != null &&
      lastRev.isNotEmpty &&
      nextRev.isNotEmpty &&
      lastRev != nextRev;
}

/// Broadcasts remote database changes to open views/tabs so they reload silently.
class SyncBus {
  static final ValueNotifier<int> remoteChangeTick = ValueNotifier<int>(0);

  static void notifyRemoteChange() {
    remoteChangeTick.value++;
  }
}

/// Returns true for connectivity / timeout / DNS / socket errors (never for HTTP 4xx/5xx ApiException).
bool isNetworkOfflineError(Object error) {
  return error is! ApiException &&
      error is! FormatException &&
      error is! ArgumentError;
}

/// Returns true when the error could mean the request ALREADY reached the server
/// before the response dropped (timeout, connection reset, EOF), vs pre-connect offline.
bool isUncertainNetworkError(Object error) {
  if (!isNetworkOfflineError(error)) return false;
  if (error is TimeoutException) return true;
  final msg = error.toString().toLowerCase();
  if (msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('no address associated with hostname')) {
    return false;
  }
  return msg.contains('timeoutexception') ||
      msg.contains('timed out') ||
      msg.contains('connection closed') ||
      msg.contains('connection reset') ||
      msg.contains('broken pipe') ||
      msg.contains('software caused connection abort') ||
      msg.contains('eof') ||
      msg.contains('handshake') ||
      msg.contains('clientexception');
}

/// Checks if an uncertain queued outbox item already exists on the live server status
/// so offline->online flush never duplicates an already-saved cash or nakladnoy entry.
bool matchesExistingServerItem(OfflineOutboxItem item, StatusSummary status) {
  final p = item.payload;
  final itemDt = DateTime.tryParse(item.createdAtIso);
  if (item.type == 'cash') {
    final src = (p['source_type'] ?? 'main').toString();
    final amt = (p['amount'] as num?)?.toDouble();
    if (amt == null) return false;
    final note = (p['note'] ?? '').toString().trim();
    for (final tx in status.cashTransactions) {
      if (tx.sourceType != src) continue;
      if ((tx.amount - amt).abs() >= 0.5) continue;
      if (tx.note.trim() != note) continue;
      final txDt = DateTime.tryParse(tx.createdAt.replaceFirst(' ', 'T'));
      if (itemDt == null || txDt == null) continue;
      if (txDt.difference(itemDt).inSeconds.abs() <= 300) {
        return true;
      }
    }
  } else if (item.type == 'nakladnoy') {
    final sup = (p['supplier_name'] ?? '').toString().trim().toLowerCase();
    final amt = (p['amount'] as num?)?.toDouble();
    if (sup.isEmpty || amt == null) return false;
    final note = (p['note'] ?? '').toString().trim();
    for (final n in status.nakladnoys) {
      if (n.supplierName.trim().toLowerCase() != sup) continue;
      if ((n.amount - amt).abs() >= 0.5) continue;
      if (n.note.trim() != note) continue;
      final nDt = DateTime.tryParse(n.createdAt.replaceFirst(' ', 'T'));
      if (itemDt == null || nDt == null) continue;
      if (nDt.difference(itemDt).inSeconds.abs() <= 300) {
        return true;
      }
    }
  }
  return false;
}

class OfflineCacheStore {
  static const String slotStatus = 'status';
  static const String slotDebts = 'debts';
  static const String slotSuppliers = 'suppliers';
  static const String slotHistory = 'history';

  static String _key(String slot) => 'hisobchi_offline_cache_v1_$slot';
  static const String _updatedKey = 'hisobchi_offline_cache_v1_updated_at';

  static Future<void> saveJson(String slot, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(slot), jsonEncode(data));
      await prefs.setString(_updatedKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadJson(String slot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(slot));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }
}

class OfflineOutboxItem {
  final String id;
  final String type; // cash | nakladnoy | pay_debt
  final String createdAtIso;
  final Map<String, dynamic> payload;
  final bool uncertain;

  const OfflineOutboxItem({
    required this.id,
    required this.type,
    required this.createdAtIso,
    required this.payload,
    this.uncertain = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'created_at': createdAtIso,
        'payload': payload,
        if (uncertain) 'uncertain': true,
      };

  factory OfflineOutboxItem.fromJson(Map<String, dynamic> j) =>
      OfflineOutboxItem(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        createdAtIso: (j['created_at'] ?? '').toString(),
        payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? const {}),
        uncertain: j['uncertain'] == true,
      );
}

class OfflineOutboxStore {
  static const String _storageKey = 'hisobchi_offline_outbox_v1';
  static bool _flushing = false;

  static Future<List<OfflineOutboxItem>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .map((e) => OfflineOutboxItem.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<OfflineOutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(
        _storageKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    }
  }

  static Future<int> count() async => (await loadAll()).length;

  static Future<int> removeById(String id) async {
    final items = await loadAll();
    items.removeWhere((e) => e.id == id);
    await _saveAll(items);
    return items.length;
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static Future<int> enqueueCash({
    required double amount,
    required String sourceType,
    String note = '',
    String? idempotencyKey,
    bool uncertain = false,
  }) async {
    final itemId = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : generateIdempotencyKey('cash');
    final items = await loadAll();
    if (items.any((e) => e.id == itemId)) {
      return items.length;
    }
    final now = DateTime.now();
    final trimmedNote = note.trim();
    final hasRapidDup = items.any((e) {
      if (e.type != 'cash') return false;
      final ep = e.payload;
      final prevAmt = (ep['amount'] as num?)?.toDouble();
      if (prevAmt == null || (prevAmt - amount).abs() >= 0.5) return false;
      if ((ep['source_type'] ?? 'main').toString() != sourceType) return false;
      if ((ep['note'] ?? '').toString().trim() != trimmedNote) return false;
      final dt = DateTime.tryParse(e.createdAtIso);
      return dt != null && now.difference(dt).inSeconds.abs() <= 30;
    });
    if (hasRapidDup) {
      return items.length;
    }
    items.add(
      OfflineOutboxItem(
        id: itemId,
        type: 'cash',
        createdAtIso: now.toIso8601String(),
        payload: {
          'amount': amount,
          'source_type': sourceType,
          'note': note,
        },
        uncertain: uncertain,
      ),
    );
    await _saveAll(items);
    return items.length;
  }

  static Future<int> enqueueNakladnoy({
    required String supplierName,
    required double amount,
    required String paymentMode,
    String note = '',
    bool sendToGroup = true,
    double? originalAmount,
    Uint8List? photoBytes,
    String photoFilename = 'nakladnoy.jpg',
    String? idempotencyKey,
    bool uncertain = false,
  }) async {
    final itemId = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : generateIdempotencyKey('nak');
    final items = await loadAll();
    if (items.any((e) => e.id == itemId)) {
      return items.length;
    }
    final now = DateTime.now();
    final lowSup = supplierName.trim().toLowerCase();
    final trimmedNote = note.trim();
    final hasRapidDup = items.any((e) {
      if (e.type != 'nakladnoy') return false;
      final ep = e.payload;
      final prevAmt = (ep['amount'] as num?)?.toDouble();
      if (prevAmt == null || (prevAmt - amount).abs() >= 0.5) return false;
      if ((ep['supplier_name'] ?? '').toString().trim().toLowerCase() !=
          lowSup) {
        return false;
      }
      if ((ep['payment_mode'] ?? 'cash').toString() != paymentMode) {
        return false;
      }
      if ((ep['note'] ?? '').toString().trim() != trimmedNote) return false;
      final dt = DateTime.tryParse(e.createdAtIso);
      return dt != null && now.difference(dt).inSeconds.abs() <= 30;
    });
    if (hasRapidDup) {
      return items.length;
    }
    String? photoB64;
    if (photoBytes != null &&
        photoBytes.isNotEmpty &&
        photoBytes.length <= 3 * 1024 * 1024) {
      photoB64 = base64Encode(photoBytes);
    }
    items.add(
      OfflineOutboxItem(
        id: itemId,
        type: 'nakladnoy',
        createdAtIso: now.toIso8601String(),
        payload: {
          'supplier_name': supplierName,
          'amount': amount,
          'payment_mode': paymentMode,
          'note': note,
          'send_to_group': sendToGroup,
          if (originalAmount != null) 'original_amount': originalAmount,
          if (photoB64 != null) 'photo_b64': photoB64,
          'photo_filename': photoFilename,
        },
        uncertain: uncertain,
      ),
    );
    await _saveAll(items);
    return items.length;
  }

  static Future<int> enqueuePayDebt({
    required int paymentId,
    required String paymentMethod,
    String supplierName = '',
    double amount = 0,
    double? partialAmount,
    String? idempotencyKey,
    bool uncertain = false,
  }) async {
    final itemId = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : generateIdempotencyKey('debt');
    final items = await loadAll();
    if (items.any((e) => e.id == itemId)) {
      return items.length;
    }
    items.add(
      OfflineOutboxItem(
        id: itemId,
        type: 'pay_debt',
        createdAtIso: DateTime.now().toIso8601String(),
        payload: {
          'payment_id': paymentId,
          'payment_method': paymentMethod,
          'supplier_name': supplierName,
          'amount': amount,
          if (partialAmount != null) 'partial_amount': partialAmount,
        },
        uncertain: uncertain,
      ),
    );
    await _saveAll(items);
    return items.length;
  }

  static Future<({int sent, int remaining, int dropped})> flushAll(
    HisobchiApiClient api,
  ) async {
    if (_flushing) {
      final cur = await count();
      return (sent: 0, remaining: cur, dropped: 0);
    }
    _flushing = true;
    var sent = 0;
    var dropped = 0;
    try {
      final queue = await loadAll();
      if (queue.isEmpty) {
        return (sent: 0, remaining: 0, dropped: 0);
      }
      final remaining = List<OfflineOutboxItem>.from(queue);
      StatusSummary? cachedStatus;
      for (final item in queue) {
        try {
          if (item.uncertain &&
              (item.type == 'cash' || item.type == 'nakladnoy')) {
            cachedStatus ??= await api.getStatus();
            if (api.lastFetchUsedOfflineCache) {
              break;
            }
            if (matchesExistingServerItem(item, cachedStatus)) {
              remaining.removeWhere((e) => e.id == item.id);
              sent++;
              await _saveAll(remaining);
              continue;
            }
          }
          await _executeSingle(api, item);
          cachedStatus = null;
          remaining.removeWhere((e) => e.id == item.id);
          sent++;
          await _saveAll(remaining);
        } on ApiException catch (e) {
          if (e.statusCode == 401) {
            break;
          }
          if (e.statusCode >= 400 &&
              e.statusCode < 500 &&
              e.statusCode != 408 &&
              e.statusCode != 429) {
            remaining.removeWhere((x) => x.id == item.id);
            dropped++;
            await _saveAll(remaining);
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      return (sent: sent, remaining: remaining.length, dropped: dropped);
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _executeSingle(
    HisobchiApiClient api,
    OfflineOutboxItem item,
  ) async {
    final p = item.payload;
    switch (item.type) {
      case 'cash':
        await api.addCash(
          amount: (p['amount'] as num).toDouble(),
          sourceType: (p['source_type'] ?? 'main').toString(),
          note: (p['note'] ?? '').toString(),
          idempotencyKey: item.id,
        );
        break;
      case 'nakladnoy':
        Uint8List? bytes;
        final b64 = p['photo_b64']?.toString();
        if (b64 != null && b64.isNotEmpty) {
          try {
            bytes = base64Decode(b64);
          } catch (_) {}
        }
        await api.createNakladnoy(
          supplierName: (p['supplier_name'] ?? '').toString(),
          amount: (p['amount'] as num).toDouble(),
          paymentMode: (p['payment_mode'] ?? 'cash').toString(),
          note: (p['note'] ?? '').toString(),
          sendToGroup: p['send_to_group'] != false,
          originalAmount: (p['original_amount'] as num?)?.toDouble(),
          photoBytes: bytes,
          photoFilename: (p['photo_filename'] ?? 'nakladnoy.jpg').toString(),
          idempotencyKey: item.id,
        );
        break;
      case 'pay_debt':
        await api.payDebt(
          paymentId: (p['payment_id'] as num).toInt(),
          paymentMethod: (p['payment_method'] ?? 'cash').toString(),
          amount: (p['partial_amount'] as num?)?.toDouble(),
          idempotencyKey: item.id,
        );
        break;
      default:
        break;
    }
  }
}
