import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Returns true for connectivity / timeout / DNS / socket errors (never for HTTP 4xx/5xx ApiException).
bool isNetworkOfflineError(Object error) {
  return error is! ApiException &&
      error is! FormatException &&
      error is! ArgumentError;
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

  const OfflineOutboxItem({
    required this.id,
    required this.type,
    required this.createdAtIso,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'created_at': createdAtIso,
        'payload': payload,
      };

  factory OfflineOutboxItem.fromJson(Map<String, dynamic> j) =>
      OfflineOutboxItem(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        createdAtIso: (j['created_at'] ?? '').toString(),
        payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? const {}),
      );
}

class OfflineOutboxStore {
  static const String _storageKey = 'hisobchi_offline_outbox_v1';
  static bool _flushing = false;

  static String _makeId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().hashCode.abs() % 9999}';

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
  }) async {
    final items = await loadAll();
    items.add(
      OfflineOutboxItem(
        id: _makeId(),
        type: 'cash',
        createdAtIso: DateTime.now().toIso8601String(),
        payload: {
          'amount': amount,
          'source_type': sourceType,
          'note': note,
        },
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
  }) async {
    final items = await loadAll();
    String? photoB64;
    if (photoBytes != null &&
        photoBytes.isNotEmpty &&
        photoBytes.length <= 3 * 1024 * 1024) {
      photoB64 = base64Encode(photoBytes);
    }
    items.add(
      OfflineOutboxItem(
        id: _makeId(),
        type: 'nakladnoy',
        createdAtIso: DateTime.now().toIso8601String(),
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
  }) async {
    final items = await loadAll();
    items.add(
      OfflineOutboxItem(
        id: _makeId(),
        type: 'pay_debt',
        createdAtIso: DateTime.now().toIso8601String(),
        payload: {
          'payment_id': paymentId,
          'payment_method': paymentMethod,
          'supplier_name': supplierName,
          'amount': amount,
          if (partialAmount != null) 'partial_amount': partialAmount,
        },
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
      for (final item in queue) {
        try {
          await _executeSingle(api, item);
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
        );
        break;
      case 'pay_debt':
        await api.payDebt(
          paymentId: (p['payment_id'] as num).toInt(),
          paymentMethod: (p['payment_method'] ?? 'cash').toString(),
          amount: (p['partial_amount'] as num?)?.toDouble(),
        );
        break;
      default:
        break;
    }
  }
}
