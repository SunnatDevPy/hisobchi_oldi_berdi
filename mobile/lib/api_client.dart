import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_sync.dart';
import 'platform_bridge.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, {this.statusCode = 0});

  @override
  String toString() => message;
}

class GroupInfo {
  final bool bound;
  final int? chatId;
  final String title;
  final bool apkPostToGroup;

  const GroupInfo({
    required this.bound,
    this.chatId,
    required this.title,
    required this.apkPostToGroup,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> j) => GroupInfo(
        bound: j['bound'] == true,
        chatId: (j['chat_id'] as num?)?.toInt(),
        title: (j['title'] ?? '').toString(),
        apkPostToGroup: j['apk_post_to_group'] != false,
      );
}

class CashTxItem {
  final int id;
  final int sessionId;
  final double amount;
  final String sourceType; // main | main_return | kassa_debt | kassa_repay | expense
  final String note;
  final String createdAt;
  final String timeHm;

  const CashTxItem({
    required this.id,
    required this.sessionId,
    required this.amount,
    required this.sourceType,
    required this.note,
    required this.createdAt,
    required this.timeHm,
  });

  factory CashTxItem.fromJson(Map<String, dynamic> j) => CashTxItem(
        id: (j['id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        amount: (j['amount'] as num).toDouble(),
        sourceType: (j['source_type'] ?? 'main').toString(),
        note: (j['note'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        timeHm: (j['time_hm'] ?? '').toString(),
      );
}

class NakladnoyItem {
  final int id;
  final int sessionId;
  final int? sessionSeq;
  final String displayNum;
  final String supplierName;
  final double amount;
  final double? originalAmount;
  final String paymentMethod; // cash | card | transfer
  final bool isDebt;
  final String note;
  final bool hasPhoto;
  final bool inGroup;
  final int? groupChatId;
  final int? groupMessageId;
  final String createdAt;
  final String timeHm;
  final String? reportDate;
  final String sessionStatus;

  bool get isClosedSession => sessionStatus == 'closed';

  const NakladnoyItem({
    required this.id,
    required this.sessionId,
    this.sessionSeq,
    required this.displayNum,
    required this.supplierName,
    required this.amount,
    this.originalAmount,
    required this.paymentMethod,
    required this.isDebt,
    required this.note,
    required this.hasPhoto,
    required this.inGroup,
    this.groupChatId,
    this.groupMessageId,
    required this.createdAt,
    required this.timeHm,
    this.reportDate,
    this.sessionStatus = 'open',
  });

  factory NakladnoyItem.fromJson(Map<String, dynamic> j) => NakladnoyItem(
        id: (j['id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        sessionSeq: (j['session_seq'] as num?)?.toInt(),
        displayNum: (j['display_num'] ?? '#${j['id']}').toString(),
        supplierName: (j['supplier_name'] ?? '').toString(),
        amount: (j['amount'] as num).toDouble(),
        originalAmount: (j['original_amount'] as num?)?.toDouble(),
        paymentMethod: (j['payment_method'] ?? 'cash').toString(),
        isDebt: j['is_debt'] == true,
        note: (j['note'] ?? '').toString(),
        hasPhoto: j['has_photo'] == true,
        inGroup: j['in_group'] == true,
        groupChatId: (j['group_chat_id'] as num?)?.toInt(),
        groupMessageId: (j['group_message_id'] as num?)?.toInt(),
        createdAt: (j['created_at'] ?? '').toString(),
        timeHm: (j['time_hm'] ?? '').toString(),
        reportDate: j['report_date']?.toString(),
        sessionStatus: (j['session_status'] ?? 'open').toString(),
      );
}

String formatSessionTimeSpan({
  required String reportDate,
  required String status,
  required String openedAt,
  String? closedAt,
}) {
  final openClean = openedAt.trim();
  final closeClean = (closedAt ?? '').trim();
  if (openClean.length < 16) {
    if (status == 'open') return 'ochiq';
    if (closeClean.length >= 16) return '${closeClean.substring(11, 16)} da yopilgan';
    return '';
  }
  final openDate = openClean.substring(0, 10);
  final openHm = openClean.substring(11, 16);
  if (status == 'open' || closeClean.length < 16) {
    if (openDate != reportDate) {
      return '${openDate.substring(5)} $openHm dan ochiq';
    }
    return '$openHm dan ochiq';
  }
  final closeDate = closeClean.substring(0, 10);
  final closeHm = closeClean.substring(11, 16);
  if (openDate != closeDate) {
    return '${openDate.substring(5)} $openHm → ${closeDate.substring(5)} $closeHm';
  }
  return '$openHm–$closeHm';
}

class StatusSummary {
  final int sessionId;
  final String reportDate;
  final String sessionStatus;
  final String openedAt;
  final String closedAt;
  final double openingBalance;
  final double mainCashIn;
  final double mainReturnToday;
  final double kassaDebtToday;
  final double kassaRepayToday;
  final double expenseToday;
  final double totalAvailableInflow;
  final double totalNakladnoySpent;
  final double totalCardSpent;
  final double totalTransferSpent;
  final double totalDebtNakladnoy;
  final double expectedCash;
  final double totalKassaDebtOutstanding;
  final int allUnpaidDebtCount;
  final double allUnpaidDebtTotal;
  final GroupInfo groupInfo;
  final List<CashTxItem> cashTransactions;
  final List<NakladnoyItem> nakladnoys;

  String get timeSpanLabel => formatSessionTimeSpan(
        reportDate: reportDate,
        status: sessionStatus,
        openedAt: openedAt,
        closedAt: closedAt,
      );

  const StatusSummary({
    required this.sessionId,
    required this.reportDate,
    required this.sessionStatus,
    this.openedAt = '',
    this.closedAt = '',
    required this.openingBalance,
    required this.mainCashIn,
    this.mainReturnToday = 0.0,
    required this.kassaDebtToday,
    required this.kassaRepayToday,
    this.expenseToday = 0.0,
    required this.totalAvailableInflow,
    required this.totalNakladnoySpent,
    required this.totalCardSpent,
    required this.totalTransferSpent,
    required this.totalDebtNakladnoy,
    required this.expectedCash,
    required this.totalKassaDebtOutstanding,
    required this.allUnpaidDebtCount,
    required this.allUnpaidDebtTotal,
    required this.groupInfo,
    required this.cashTransactions,
    required this.nakladnoys,
  });

  factory StatusSummary.fromJson(Map<String, dynamic> j) => StatusSummary(
        sessionId: (j['session_id'] as num).toInt(),
        reportDate: (j['report_date'] ?? '').toString(),
        sessionStatus: (j['session_status'] ?? 'open').toString(),
        openedAt: (j['opened_at'] ?? '').toString(),
        closedAt: (j['closed_at'] ?? '').toString(),
        openingBalance: (j['opening_balance'] as num).toDouble(),
        mainCashIn: (j['main_cash_in'] as num).toDouble(),
        mainReturnToday: ((j['main_return_today'] as num?) ?? 0).toDouble(),
        kassaDebtToday: (j['kassa_debt_today'] as num).toDouble(),
        kassaRepayToday: (j['kassa_repay_today'] as num).toDouble(),
        expenseToday: ((j['expense_today'] as num?) ?? 0).toDouble(),
        totalAvailableInflow: (j['total_available_inflow'] as num).toDouble(),
        totalNakladnoySpent: (j['total_nakladnoy_spent'] as num).toDouble(),
        totalCardSpent: (j['total_card_spent'] as num).toDouble(),
        totalTransferSpent: (j['total_transfer_spent'] as num).toDouble(),
        totalDebtNakladnoy: (j['total_debt_nakladnoy'] as num).toDouble(),
        expectedCash: (j['expected_cash'] as num).toDouble(),
        totalKassaDebtOutstanding:
            (j['total_kassa_debt_outstanding'] as num).toDouble(),
        allUnpaidDebtCount: (j['all_unpaid_debt_count'] as num).toInt(),
        allUnpaidDebtTotal: (j['all_unpaid_debt_total'] as num).toDouble(),
        groupInfo: GroupInfo.fromJson(
            (j['group_info'] as Map<String, dynamic>?) ?? const {}),
        cashTransactions: ((j['cash_transactions'] as List?) ?? const [])
            .map((e) => CashTxItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        nakladnoys: ((j['nakladnoys'] as List?) ?? const [])
            .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HisobchiApiClient {
  static const String _prefBaseUrl = 'hisobchi_base_url';
  static const String _prefToken = 'hisobchi_access_token';
  static const String _prefRole = 'hisobchi_role';
  static const String _prefUserId = 'hisobchi_user_id';
  static const String defaultBaseUrl = 'https://hisobchi.okaposai.uz';

  String baseUrl;
  String? accessToken;
  String role;
  int? userId;
  bool lastFetchUsedOfflineCache = false;
  StatusSummary? _prewarmedStatus;
  List<NakladnoyItem>? _prewarmedDebts;
  final http.Client _http;

  Future<void> prewarmHomeData() async {
    if (!isAuthenticated) return;
    try {
      final res = await Future.wait([getStatus(), getUnpaidDebts()]);
      _prewarmedStatus = res[0] as StatusSummary;
      _prewarmedDebts = res[1] as List<NakladnoyItem>;
    } catch (_) {}
  }

  ({StatusSummary? status, List<NakladnoyItem>? debts}) consumePrewarmedData() {
    final s = _prewarmedStatus;
    final d = _prewarmedDebts;
    _prewarmedStatus = null;
    _prewarmedDebts = null;
    return (status: s, debts: d);
  }

  HisobchiApiClient({
    this.baseUrl = defaultBaseUrl,
    this.accessToken,
    this.role = 'admin',
    this.userId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;
  bool get canWrite => role == 'admin' || role == 'kassir';
  bool get isAdmin => role == 'admin';

  static String normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null &&
        parsed.scheme == 'http' &&
        parsed.host != 'localhost' &&
        parsed.host != '127.0.0.1' &&
        parsed.host != '::1') {
      trimmed = parsed.replace(scheme: 'https').toString();
    }
    return trimmed;
  }

  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = normalizeBaseUrl(prefs.getString(_prefBaseUrl) ?? defaultBaseUrl);
    final vaultToken = await secureStorageRead(_prefToken);
    if (vaultToken != null && vaultToken.isNotEmpty) {
      accessToken = vaultToken;
      await prefs.remove(_prefToken);
    } else {
      final legacyToken = prefs.getString(_prefToken);
      accessToken = legacyToken;
      if (legacyToken != null && legacyToken.isNotEmpty) {
        final migrated = await secureStorageWrite(_prefToken, legacyToken);
        if (migrated) {
          await prefs.remove(_prefToken);
        }
      }
    }
    role = prefs.getString(_prefRole) ?? 'admin';
    userId = prefs.getInt(_prefUserId);
  }

  Future<void> _saveSession({
    required String url,
    required String token,
    required String userRole,
    required int uid,
  }) async {
    baseUrl = normalizeBaseUrl(url);
    accessToken = token;
    role = userRole;
    userId = uid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBaseUrl, baseUrl);
    final storedInVault = await secureStorageWrite(_prefToken, token);
    if (storedInVault) {
      await prefs.remove(_prefToken);
    } else {
      await prefs.setString(_prefToken, token);
    }
    await prefs.setString(_prefRole, userRole);
    await prefs.setInt(_prefUserId, uid);
  }

  Future<void> clearSession() async {
    accessToken = null;
    await secureStorageDelete(_prefToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefToken);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: query);
  }

  Map<String, String> _headers({
    bool jsonBody = true,
    String? idempotencyKey,
  }) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      h['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
      h['X-Idempotency-Key'] = idempotencyKey.trim();
    }
    return h;
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    String bodyText;
    try {
      bodyText = utf8.decode(res.bodyBytes);
    } catch (_) {
      bodyText = res.body;
    }
    Map<String, dynamic> data = {};
    if (bodyText.isNotEmpty) {
      try {
        final decoded = jsonDecode(bodyText);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }
    final detail = data['detail']?.toString() ??
        'Server xatosi (HTTP ${res.statusCode})';
    throw ApiException(detail, statusCode: res.statusCode);
  }

  Future<bool> checkHealth(String targetUrl) async {
    final clean = normalizeBaseUrl(targetUrl);
    final res = await _http
        .get(Uri.parse('$clean/health'))
        .timeout(const Duration(seconds: 8));
    final data = _decodeJson(res);
    return data['status'] == 'ok';
  }

  Future<String> fetchBotUsername({String fallback = 'hisobchi_my_bot'}) async {
    try {
      final clean = normalizeBaseUrl(baseUrl);
      final res = await _http
          .get(Uri.parse('$clean/health'))
          .timeout(const Duration(seconds: 5));
      final data = _decodeJson(res);
      final raw = (data['bot_username'] ?? '').toString().trim().replaceAll('@', '');
      return raw.isNotEmpty ? raw : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> login({
    required String serverUrl,
    required String code,
    String deviceName = 'Android APK',
  }) async {
    final cleanUrl = normalizeBaseUrl(serverUrl);
    final res = await _http
        .post(
          Uri.parse('$cleanUrl/auth/login'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'code': code.trim(),
            'device_name': deviceName.trim().isEmpty ? 'Android' : deviceName.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    await _saveSession(
      url: cleanUrl,
      token: data['access_token'].toString(),
      userRole: (data['role'] ?? 'admin').toString(),
      uid: (data['user_id'] as num).toInt(),
    );
  }

  /// Authenticate a Telegram Mini App owner session in memory via initData HMAC.
  Future<void> loginWithTelegramWebApp({
    required String initData,
    String? serverUrl,
  }) async {
    final cleanUrl = normalizeBaseUrl(serverUrl ?? baseUrl);
    final res = await _http
        .post(
          Uri.parse('$cleanUrl/auth/telegram-webapp'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'init_data': initData}),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    baseUrl = cleanUrl;
    accessToken = data['access_token'].toString();
    role = (data['role'] ?? 'admin').toString();
    userId = (data['user_id'] as num).toInt();
  }

  Future<void> logout() async {
    try {
      if (isAuthenticated) {
        await _http
            .post(_uri('/auth/logout'), headers: _headers())
            .timeout(const Duration(seconds: 6));
      }
    } catch (_) {
    } finally {
      await clearSession();
    }
  }

  Future<StatusSummary> getStatus() async {
    try {
      final res = await _http
          .get(_uri('/status'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      final json = _decodeJson(res);
      lastFetchUsedOfflineCache = false;
      await OfflineCacheStore.saveJson(OfflineCacheStore.slotStatus, json);
      return StatusSummary.fromJson(json);
    } catch (e) {
      if (isNetworkOfflineError(e)) {
        final cached =
            await OfflineCacheStore.loadJson(OfflineCacheStore.slotStatus);
        if (cached != null) {
          lastFetchUsedOfflineCache = true;
          return StatusSummary.fromJson(cached);
        }
      }
      rethrow;
    }
  }

  Future<CashTxItem> addCash({
    required double amount,
    required String sourceType,
    String note = '',
    String? idempotencyKey,
  }) async {
    final res = await _http
        .post(
          _uri('/cash'),
          headers: _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode({
            'amount': amount,
            'source_type': sourceType,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return CashTxItem.fromJson(_decodeJson(res));
  }

  Future<CashTxItem> updateCash({
    required int txId,
    double? amount,
    String? note,
  }) async {
    final res = await _http
        .patch(
          _uri('/cash/$txId'),
          headers: _headers(),
          body: jsonEncode({
            if (amount != null) 'amount': amount,
            if (note != null) 'note': note,
          }),
        )
        .timeout(const Duration(seconds: 12));
    return CashTxItem.fromJson(_decodeJson(res));
  }

  Future<void> deleteCash(int txId) async {
    final res = await _http
        .delete(_uri('/cash/$txId'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    _decodeJson(res);
  }

  Future<CashTxItem> restoreCash(int txId) async {
    final res = await _http
        .post(_uri('/cash/$txId/restore'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    return CashTxItem.fromJson(_decodeJson(res));
  }

  Future<List<String>> getSuppliers({String query = ''}) async {
    try {
      final res = await _http
          .get(_uri('/suppliers', query.isEmpty ? null : {'q': query}),
              headers: _headers())
          .timeout(const Duration(seconds: 10));
      final data = _decodeJson(res);
      if (query.isEmpty) {
        await OfflineCacheStore.saveJson(OfflineCacheStore.slotSuppliers, data);
      }
      return ((data['suppliers'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
    } catch (e) {
      if (isNetworkOfflineError(e)) {
        final cached =
            await OfflineCacheStore.loadJson(OfflineCacheStore.slotSuppliers);
        if (cached != null) {
          final all = ((cached['suppliers'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
          if (query.isEmpty) return all;
          final q = query.toLowerCase();
          return all.where((s) => s.toLowerCase().contains(q)).toList();
        }
      }
      rethrow;
    }
  }

  Future<List<double>> getSupplierAmounts(String supplier) async {
    final res = await _http
        .get(_uri('/suppliers/amounts', {'supplier': supplier}),
            headers: _headers())
        .timeout(const Duration(seconds: 10));
    final data = _decodeJson(res);
    return ((data['amounts'] as List?) ?? const [])
        .map((e) => (e as num).toDouble())
        .toList();
  }

  Future<Map<String, dynamic>> createNakladnoy({
    required String supplierName,
    required double amount,
    required String paymentMode, // cash | card | transfer | debt
    String note = '',
    bool sendToGroup = true,
    Uint8List? photoBytes,
    String photoFilename = 'nakladnoy.jpg',
    double? originalAmount,
    String? idempotencyKey,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/nakladnoy'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
      final cleanKey = idempotencyKey.trim();
      req.headers['X-Idempotency-Key'] = cleanKey;
      req.fields['client_request_id'] = cleanKey;
    }
    req.fields['supplier_name'] = supplierName.trim();
    req.fields['amount'] = amount.toStringAsFixed(0);
    req.fields['payment_mode'] = paymentMode;
    req.fields['note'] = note.trim();
    req.fields['send_to_group'] = sendToGroup ? 'true' : 'false';
    if (originalAmount != null) {
      req.fields['original_amount'] = originalAmount.toStringAsFixed(0);
    }

    if (photoBytes != null && photoBytes.isNotEmpty) {
      req.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoFilename.isNotEmpty ? photoFilename : 'nakladnoy.jpg',
        ),
      );
    }

    final streamed = await _http.send(req).timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    return _decodeJson(res);
  }

  Future<NakladnoyItem> updateNakladnoy({
    required int paymentId,
    String? supplierName,
    double? amount,
    String? note,
    bool roundAmount = false,
  }) async {
    final res = await _http
        .patch(
          _uri('/nakladnoy/$paymentId'),
          headers: _headers(),
          body: jsonEncode({
            if (supplierName != null) 'supplier_name': supplierName,
            if (amount != null) 'amount': amount,
            if (note != null) 'note': note,
            'round_amount': roundAmount,
          }),
        )
        .timeout(const Duration(seconds: 12));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<NakladnoyItem> setPaymentMethod({
    required int paymentId,
    required String paymentMethod, // cash | card | transfer
  }) async {
    final res = await _http
        .post(
          _uri('/nakladnoy/$paymentId/payment-method'),
          headers: _headers(),
          body: jsonEncode({'payment_method': paymentMethod}),
        )
        .timeout(const Duration(seconds: 12));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<NakladnoyItem> markAsDebt(int paymentId) async {
    final res = await _http
        .post(_uri('/nakladnoy/$paymentId/debt'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<NakladnoyItem> payDebt({
    required int paymentId,
    required String paymentMethod, // cash | card | transfer
    double? amount,
    String? idempotencyKey,
  }) async {
    final res = await _http
        .post(
          _uri('/nakladnoy/$paymentId/paid'),
          headers: _headers(idempotencyKey: idempotencyKey),
          body: jsonEncode({
            'payment_method': paymentMethod,
            if (amount != null && amount > 0) 'amount': amount,
          }),
        )
        .timeout(const Duration(seconds: 25));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<String> sendNakladnoyToGroup(
    int paymentId, {
    String? idempotencyKey,
  }) async {
    final res = await _http
        .post(
          _uri('/nakladnoy/$paymentId/group'),
          headers: _headers(idempotencyKey: idempotencyKey),
        )
        .timeout(const Duration(seconds: 20));
    final data = _decodeJson(res);
    return (data['message'] ?? 'Guruhga yuborildi').toString();
  }

  Future<void> deleteNakladnoy(int paymentId) async {
    final res = await _http
        .delete(_uri('/nakladnoy/$paymentId'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    _decodeJson(res);
  }

  Future<NakladnoyItem> restoreNakladnoy(int paymentId) async {
    final res = await _http
        .post(_uri('/nakladnoy/$paymentId/restore'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<Map<String, dynamic>> getKassaDebtHistory({int limit = 40}) async {
    final res = await _http
        .get(_uri('/kassa-debt/history', {'limit': '$limit'}),
            headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<List<NakladnoyItem>> getUnpaidDebts() async {
    try {
      final res = await _http
          .get(_uri('/debts'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      final data = _decodeJson(res);
      await OfflineCacheStore.saveJson(OfflineCacheStore.slotDebts, data);
      return ((data['items'] as List?) ?? const [])
          .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (isNetworkOfflineError(e)) {
        final cached =
            await OfflineCacheStore.loadJson(OfflineCacheStore.slotDebts);
        if (cached != null) {
          lastFetchUsedOfflineCache = true;
          return ((cached['items'] as List?) ?? const [])
              .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> closeDay(
    double actualCountedCash, {
    String note = '',
  }) async {
    final res = await _http
        .post(
          _uri('/day/close'),
          headers: _headers(),
          body: jsonEncode({
            'actual_counted_cash': actualCountedCash,
            'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<({List<CashReconciliationItem> items, CashReconciliationSummary summary})>
      getCashReconciliationsWithSummary({
    int? sessionId,
    String? kind,
    int limit = 80,
  }) async {
    final q = <String, String>{'limit': '$limit'};
    if (sessionId != null) q['session_id'] = '$sessionId';
    if (kind != null && kind.isNotEmpty) q['kind'] = kind;
    final res = await _http
        .get(_uri('/cash/reconciliations', q), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    final raw = (data['items'] as List?) ?? const [];
    final items = raw
        .map((e) =>
            CashReconciliationItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final sumMap = data['summary'] is Map
        ? Map<String, dynamic>.from(data['summary'] as Map)
        : const <String, dynamic>{};
    return (
      items: items,
      summary: CashReconciliationSummary.fromJson(sumMap),
    );
  }

  Future<List<CashReconciliationItem>> getCashReconciliations({
    int? sessionId,
    String? kind,
    int limit = 60,
  }) async {
    final res = await getCashReconciliationsWithSummary(
      sessionId: sessionId,
      kind: kind,
      limit: limit,
    );
    return res.items;
  }

  Future<CashReconciliationItem> createInterimReconciliation({
    required double countedCash,
    String note = '',
  }) async {
    final res = await _http
        .post(
          _uri('/cash/reconciliations'),
          headers: _headers(),
          body: jsonEncode({
            'counted_cash': countedCash,
            'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    return CashReconciliationItem.fromJson(_decodeJson(res));
  }

  Future<void> deleteInterimReconciliation(int id) async {
    final res = await _http
        .delete(_uri('/cash/reconciliations/$id'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    _decodeJson(res);
  }

  Future<Uint8List> downloadExcelBytes(
    String endpointPath, {
    Map<String, String>? query,
  }) async {
    final res = await _http
        .get(_uri(endpointPath, query), headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    _decodeJson(res);
    throw const ApiException('Excel yuklashda xatolik');
  }

  String buildAuthenticatedDownloadUrl(
    String endpointPath, {
    Map<String, String>? query,
  }) {
    final q = <String, String>{...?query};
    if (accessToken != null && accessToken!.isNotEmpty) {
      q['token'] = accessToken!;
    }
    return _uri(endpointPath, q).toString();
  }

  String photoUrlFor(int paymentId) =>
      '$baseUrl/nakladnoy/$paymentId/photo?token=${Uri.encodeComponent(accessToken ?? '')}';

  /// Send nakladnoy photo to server-side Gemini Vision; returns supplier & amount guess.
  Future<AiExtractResult> extractFromPhoto(
    Uint8List photoBytes, {
    String filename = 'nakladnoy.jpg',
  }) async {
    final req = http.MultipartRequest('POST', _uri('/ai/extract'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        photoBytes,
        filename: filename.isNotEmpty ? filename : 'nakladnoy.jpg',
      ),
    );
    final streamed = await _http.send(req).timeout(const Duration(seconds: 45));
    final res = await http.Response.fromStream(streamed);
    return AiExtractResult.fromJson(_decodeJson(res));
  }

  Future<Map<String, dynamic>> parseVoiceCommand({
    Uint8List? audioBytes,
    String filename = 'voice.m4a',
    String text = '',
  }) async {
    final req = http.MultipartRequest('POST', _uri('/ai/voice'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (text.trim().isNotEmpty) {
      req.fields['text'] = text.trim();
    }
    if (audioBytes != null && audioBytes.isNotEmpty) {
      req.files.add(
        http.MultipartFile.fromBytes(
          'audio',
          audioBytes,
          filename: filename.isNotEmpty ? filename : 'voice.m4a',
        ),
      );
    }
    final streamed = await _http.send(req).timeout(const Duration(seconds: 40));
    final res = await http.Response.fromStream(streamed);
    return _decodeJson(res);
  }

  Future<Uint8List> downloadSupplierSverkaPdf(
    String supplier, {
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, String>{
      'supplier': supplier.trim(),
      if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
    };
    final res = await _http
        .get(_uri('/suppliers/sverka-pdf', query),
            headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    _decodeJson(res);
    throw const ApiException('PDF Sverka yuklashda xatolik');
  }

  Uri get apkDownloadUri => _uri('/download/hisobchi.apk');

  Future<ApkVersionInfo> checkApkVersion() async {
    final res = await _http
        .get(_uri('/apk/version'))
        .timeout(const Duration(seconds: 10));
    return ApkVersionInfo.fromJson(_decodeJson(res), baseUrl);
  }

  Future<SyncVersionInfo> getSyncVersion() async {
    final res = await _http
        .get(_uri('/sync/version'), headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 6));
    return SyncVersionInfo.fromJson(_decodeJson(res));
  }

  Future<Uint8List> downloadLatestApkBytes() async {
    final res = await _http
        .get(_uri('/download/hisobchi.apk'))
        .timeout(const Duration(seconds: 120));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    throw const ApiException('APK yuklab olishda xatolik');
  }

  // Stage 1: History sessions, detail, reopen & global search
  Future<List<HistorySessionItem>> getHistorySessions({int limit = 25}) async {
    try {
      final res = await _http
          .get(_uri('/history/sessions', {'limit': '$limit'}),
              headers: _headers())
          .timeout(const Duration(seconds: 15));
      final data = _decodeJson(res);
      await OfflineCacheStore.saveJson(OfflineCacheStore.slotHistory, data);
      return ((data['sessions'] as List?) ?? const [])
          .map((e) => HistorySessionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (isNetworkOfflineError(e)) {
        final cached =
            await OfflineCacheStore.loadJson(OfflineCacheStore.slotHistory);
        if (cached != null) {
          return ((cached['sessions'] as List?) ?? const [])
              .map((e) => HistorySessionItem.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      rethrow;
    }
  }

  Future<StatusSummary> getHistorySessionDetail(int sessionId) async {
    final res = await _http
        .get(_uri('/history/sessions/$sessionId'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return StatusSummary.fromJson(_decodeJson(res));
  }

  Future<Map<String, dynamic>> reopenSession(int sessionId) async {
    final res = await _http
        .post(_uri('/history/sessions/$sessionId/reopen'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    return _decodeJson(res);
  }

  Future<List<NakladnoyItem>> searchHistoryNakladnoys(String query) async {
    final all = await searchHistoryAll(query);
    return all.nakladnoys;
  }

  Future<({List<NakladnoyItem> nakladnoys, List<CashTxItem> cashItems})>
      searchHistoryAll(String query) async {
    final res = await _http
        .get(_uri('/history/search', {'q': query.trim()}), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    final naks = ((data['items'] as List?) ?? const [])
        .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final cash = ((data['cash_items'] as List?) ?? const [])
        .map((e) => CashTxItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return (nakladnoys: naks, cashItems: cash);
  }

  // Stage 2: Period statistics & Live Sverka
  Future<Map<String, dynamic>> getPeriodStats({
    int days = 7,
    String? dateFrom,
    String? dateTo,
    String? preset,
  }) async {
    final q = <String, String>{'days': '$days'};
    if (dateFrom != null && dateFrom.isNotEmpty) q['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) q['date_to'] = dateTo;
    if (preset != null && preset.isNotEmpty) q['preset'] = preset;
    final res = await _http
        .get(_uri('/stats/period', q), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> getLiveSverka({String? month}) async {
    final q = (month != null && month.isNotEmpty) ? {'month': month} : null;
    final res = await _http
        .get(_uri('/sverka', q), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  // Stage 3: Attach / Replace photo on existing nakladnoy
  Future<NakladnoyItem> uploadNakladnoyPhoto(
    int paymentId,
    Uint8List photoBytes, {
    String filename = 'nakladnoy.jpg',
    bool sendToGroup = true,
  }) async {
    final req =
        http.MultipartRequest('POST', _uri('/nakladnoy/$paymentId/photo'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['send_to_group'] = sendToGroup ? 'true' : 'false';
    req.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        photoBytes,
        filename: filename.isNotEmpty ? filename : 'nakladnoy.jpg',
      ),
    );
    final streamed = await _http.send(req).timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  // Stage 4: Nasiya Ledger & Prixod (ITOG 👑)
  Future<Map<String, dynamic>> getNasiya({String? supplier}) async {
    final q = (supplier != null && supplier.isNotEmpty)
        ? {'supplier': supplier}
        : null;
    final res = await _http
        .get(_uri('/nasiya', q), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> addNasiya({
    required String supplierName,
    required String entryType, // debt | payment
    required double amount,
    String note = '',
  }) async {
    final res = await _http
        .post(
          _uri('/nasiya'),
          headers: _headers(),
          body: jsonEncode({
            'supplier_name': supplierName.trim(),
            'entry_type': entryType,
            'amount': amount,
            'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    return _decodeJson(res);
  }

  Future<void> deleteNasiya(int entryId) async {
    final res = await _http
        .delete(_uri('/nasiya/$entryId'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    _decodeJson(res);
  }

  Future<List<Map<String, dynamic>>> getPrixodList() async {
    final res = await _http
        .get(_uri('/prixod'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return ((data['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createPrixodFromText({
    required String text,
    bool publishToGroup = false,
  }) async {
    final res = await _http
        .post(
          _uri('/prixod/text'),
          headers: _headers(),
          body: jsonEncode({
            'text': text.trim(),
            'publish_to_group': publishToGroup,
          }),
        )
        .timeout(const Duration(seconds: 20));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> publishPrixod(int reportId) async {
    final res = await _http
        .post(_uri('/prixod/$reportId/publish'), headers: _headers())
        .timeout(const Duration(seconds: 20));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> createPrixodFromFile({
    required Uint8List bytes,
    required String filename,
    bool publishToGroup = false,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/prixod/file'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['publish_to_group'] = publishToGroup ? 'true' : 'false';
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename.isNotEmpty ? filename : 'yespos_report.xlsx',
      ),
    );
    final streamed = await _http.send(req).timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    return _decodeJson(res);
  }

  // Supplier Configs & AI Rounding Settings
  Future<List<Map<String, dynamic>>> getSupplierConfigs() async {
    final res = await _http
        .get(_uri('/settings/suppliers'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    return ((data['configs'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> saveSupplierConfig({
    required String displayName,
    required String aliases,
    String defaultCategory = 'qarz',
  }) async {
    final res = await _http
        .post(
          _uri('/settings/suppliers'),
          headers: _headers(),
          body: jsonEncode({
            'display_name': displayName.trim(),
            'aliases': aliases.trim(),
            'default_category': defaultCategory,
          }),
        )
        .timeout(const Duration(seconds: 12));
    return _decodeJson(res);
  }

  Future<void> deleteSupplierConfig(int supplierId) async {
    final res = await _http
        .delete(_uri('/settings/suppliers/$supplierId'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    _decodeJson(res);
  }

  Future<String> getRoundMode() async {
    final res = await _http
        .get(_uri('/settings/round-mode'), headers: _headers())
        .timeout(const Duration(seconds: 10));
    final data = _decodeJson(res);
    return (data['round_mode'] ?? 'floor_1000').toString();
  }

  Future<String> setRoundMode(String roundMode) async {
    final res = await _http
        .post(
          _uri('/settings/round-mode'),
          headers: _headers(),
          body: jsonEncode({'round_mode': roundMode}),
        )
        .timeout(const Duration(seconds: 10));
    final data = _decodeJson(res);
    return (data['round_mode'] ?? roundMode).toString();
  }

  Future<Map<String, dynamic>> getSuppliersDirectory() async {
    final res = await _http
        .get(_uri('/suppliers/directory'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<List<Map<String, dynamic>>> getSupplierDuplicates() async {
    final res = await _http
        .get(_uri('/suppliers/duplicates'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return ((data['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> mergeSuppliers({
    required String targetName,
    required List<String> sourceNames,
    List<String> extraAliases = const [],
  }) async {
    final res = await _http
        .post(
          _uri('/suppliers/merge'),
          headers: _headers(),
          body: jsonEncode({
            'target_name': targetName.trim(),
            'source_names': sourceNames.map((e) => e.trim()).toList(),
            'extra_aliases': extraAliases.map((e) => e.trim()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 25));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> updateSupplierAliases({
    required String supplierName,
    required List<String> aliases,
  }) async {
    final res = await _http
        .post(
          _uri('/suppliers/aliases'),
          headers: _headers(),
          body: jsonEncode({
            'supplier_name': supplierName.trim(),
            'aliases': aliases.map((e) => e.trim()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> getSupplierProfile(
    String supplier, {
    int limit = 60,
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await _http
        .get(
          _uri('/suppliers/profile', {
            'supplier': supplier.trim(),
            'limit': '$limit',
            if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
            if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          }),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<String> sendExcelToTelegram({
    required String reportType, // session | range | sverka
    int? sessionId,
    String? dateFrom,
    String? dateTo,
    String? month,
  }) async {
    final res = await _http
        .post(
          _uri('/export/send-telegram'),
          headers: _headers(),
          body: jsonEncode({
            'report_type': reportType,
            if (sessionId != null) 'session_id': sessionId,
            if (dateFrom != null) 'date_from': dateFrom,
            if (dateTo != null) 'date_to': dateTo,
            if (month != null) 'month': month,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(res);
    return (data['message'] ?? '📤 Telegram botga yuborildi!').toString();
  }

  Future<Map<String, dynamic>> getTelegramHubSettings() async {
    final res = await _http
        .get(_uri('/settings/telegram-hub'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
  }

  Future<String> bindTelegramGroup({
    required String role,
    required int chatId,
    String title = '',
  }) async {
    final res = await _http
        .post(
          _uri('/settings/groups'),
          headers: _headers(),
          body: jsonEncode({
            'role': role,
            'chat_id': chatId,
            'title': title.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return (data['message'] ?? '✅ Guruh ulandi!').toString();
  }

  Future<String> unbindTelegramGroup(String role) async {
    final res = await _http
        .delete(_uri('/settings/groups/$role'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    return (data['message'] ?? 'Guruh uzildi').toString();
  }

  Future<String> testTelegramGroup(String role) async {
    final res = await _http
        .post(_uri('/settings/groups/$role/test'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return (data['message'] ?? '✅ Test xabar yuborildi!').toString();
  }

  Future<String> updateBotPrefs({
    bool? apkPostToGroup,
    bool? autoConfirm,
    bool? autoReportEnabled,
    String? autoReportTime,
  }) async {
    final res = await _http
        .post(
          _uri('/settings/bot-prefs'),
          headers: _headers(),
          body: jsonEncode({
            if (apkPostToGroup != null) 'apk_post_to_group': apkPostToGroup,
            if (autoConfirm != null) 'auto_confirm': autoConfirm,
            if (autoReportEnabled != null)
              'auto_report_enabled': autoReportEnabled,
            if (autoReportTime != null) 'auto_report_time': autoReportTime,
          }),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    return (data['message'] ?? '✅ Saqlandi').toString();
  }

  Future<String> saveUserRole({
    required int userId,
    required String role,
    String label = '',
  }) async {
    final res = await _http
        .post(
          _uri('/settings/roles'),
          headers: _headers(),
          body: jsonEncode({
            'user_id': userId,
            'role': role,
            'label': label.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    return (data['message'] ?? '✅ Saqlandi').toString();
  }

  Future<String> deleteUserRole(int userId) async {
    final res = await _http
        .delete(_uri('/settings/roles/$userId'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    final data = _decodeJson(res);
    return (data['message'] ?? "O'chirildi").toString();
  }

  Future<String> triggerManualBackup() async {
    final res = await _http
        .post(_uri('/settings/backup-now'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    final data = _decodeJson(res);
    return (data['message'] ?? '💾 Backup yuborildi!').toString();
  }
}

class HistorySessionItem {
  final int id;
  final String reportDate;
  final String status; // open | closed
  final double openingBalance;
  final double expectedCash;
  final double? actualCountedCash;
  final double? difference;
  final String createdAt;
  final String? closedAt;
  final int shiftSeq;
  final int shiftTotal;

  const HistorySessionItem({
    required this.id,
    required this.reportDate,
    required this.status,
    required this.openingBalance,
    required this.expectedCash,
    this.actualCountedCash,
    this.difference,
    required this.createdAt,
    this.closedAt,
    this.shiftSeq = 1,
    this.shiftTotal = 1,
  });

  String get shiftBadge => shiftTotal > 1 ? '$shiftSeq-smena (#$id)' : '#$id';

  String get timeRangeLabel => formatSessionTimeSpan(
        reportDate: reportDate,
        status: status,
        openedAt: createdAt,
        closedAt: closedAt,
      );

  bool matchesDate(String isoDate) {
    if (isoDate.isEmpty) return true;
    if (reportDate == isoDate) return true;
    final openD = createdAt.length >= 10 ? createdAt.substring(0, 10) : '';
    final closeD =
        (closedAt != null && closedAt!.length >= 10) ? closedAt!.substring(0, 10) : '';
    if (openD == isoDate || closeD == isoDate) return true;
    if (openD.isNotEmpty && closeD.isNotEmpty && openD.compareTo(isoDate) <= 0 && isoDate.compareTo(closeD) <= 0) {
      return true;
    }
    if (status == 'open' && openD.isNotEmpty && openD.compareTo(isoDate) <= 0) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (isoDate.compareTo(today) <= 0) return true;
    }
    return false;
  }

  factory HistorySessionItem.fromJson(Map<String, dynamic> j) =>
      HistorySessionItem(
        id: (j['id'] as num).toInt(),
        reportDate: (j['report_date'] ?? '').toString(),
        status: (j['status'] ?? 'open').toString(),
        openingBalance: ((j['opening_balance'] as num?) ?? 0).toDouble(),
        expectedCash: ((j['expected_cash'] as num?) ?? 0).toDouble(),
        actualCountedCash: (j['actual_counted_cash'] as num?)?.toDouble(),
        difference: (j['difference'] as num?)?.toDouble(),
        createdAt: (j['created_at'] ?? '').toString(),
        closedAt: j['closed_at']?.toString(),
        shiftSeq: ((j['shift_seq'] as num?) ?? 1).toInt(),
        shiftTotal: ((j['shift_total'] as num?) ?? 1).toInt(),
      );
}

class CashReconciliationItem {
  final int id;
  final int sessionId;
  final String reportDate;
  final String kind; // 'interim' | 'closing'
  final double openingBalance;
  final double cashInTotal;
  final double cashOutTotal;
  final double expectedCash;
  final double countedCash;
  final double difference;
  final String note;
  final String createdAt;
  final String timeHm;

  const CashReconciliationItem({
    required this.id,
    required this.sessionId,
    required this.reportDate,
    required this.kind,
    this.openingBalance = 0.0,
    this.cashInTotal = 0.0,
    this.cashOutTotal = 0.0,
    required this.expectedCash,
    required this.countedCash,
    required this.difference,
    required this.note,
    required this.createdAt,
    required this.timeHm,
  });

  bool get isClosing => kind == 'closing';

  factory CashReconciliationItem.fromJson(Map<String, dynamic> j) =>
      CashReconciliationItem(
        id: (j['id'] as num).toInt(),
        sessionId: (j['session_id'] as num).toInt(),
        reportDate: (j['report_date'] ?? '').toString(),
        kind: (j['kind'] ?? 'interim').toString(),
        openingBalance: ((j['opening_balance'] as num?) ?? 0).toDouble(),
        cashInTotal: ((j['cash_in_total'] as num?) ?? 0).toDouble(),
        cashOutTotal: ((j['cash_out_total'] as num?) ?? 0).toDouble(),
        expectedCash: ((j['expected_cash'] as num?) ?? 0).toDouble(),
        countedCash: ((j['counted_cash'] as num?) ?? 0).toDouble(),
        difference: ((j['difference'] as num?) ?? 0).toDouble(),
        note: (j['note'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        timeHm: (j['time_hm'] ?? '').toString(),
      );
}

class CashReconciliationSummary {
  final int closingCount;
  final double closingTotalPlus;
  final double closingTotalMinus;
  final double closingNetDiff;
  final int closingExactCount;
  final double closingTotalCashIn;
  final double closingTotalCashOut;
  final int interimCount;
  final double interimTotalPlus;
  final double interimTotalMinus;
  final double interimNetDiff;
  final int interimExactCount;

  const CashReconciliationSummary({
    this.closingCount = 0,
    this.closingTotalPlus = 0.0,
    this.closingTotalMinus = 0.0,
    this.closingNetDiff = 0.0,
    this.closingExactCount = 0,
    this.closingTotalCashIn = 0.0,
    this.closingTotalCashOut = 0.0,
    this.interimCount = 0,
    this.interimTotalPlus = 0.0,
    this.interimTotalMinus = 0.0,
    this.interimNetDiff = 0.0,
    this.interimExactCount = 0,
  });

  factory CashReconciliationSummary.fromJson(Map<String, dynamic> j) =>
      CashReconciliationSummary(
        closingCount: ((j['closing_count'] as num?) ?? 0).toInt(),
        closingTotalPlus: ((j['closing_total_plus'] as num?) ?? 0).toDouble(),
        closingTotalMinus: ((j['closing_total_minus'] as num?) ?? 0).toDouble(),
        closingNetDiff: ((j['closing_net_diff'] as num?) ?? 0).toDouble(),
        closingExactCount: ((j['closing_exact_count'] as num?) ?? 0).toInt(),
        closingTotalCashIn:
            ((j['closing_total_cash_in'] as num?) ?? 0).toDouble(),
        closingTotalCashOut:
            ((j['closing_total_cash_out'] as num?) ?? 0).toDouble(),
        interimCount: ((j['interim_count'] as num?) ?? 0).toInt(),
        interimTotalPlus: ((j['interim_total_plus'] as num?) ?? 0).toDouble(),
        interimTotalMinus: ((j['interim_total_minus'] as num?) ?? 0).toDouble(),
        interimNetDiff: ((j['interim_net_diff'] as num?) ?? 0).toDouble(),
        interimExactCount: ((j['interim_exact_count'] as num?) ?? 0).toInt(),
      );
}

class SyncVersionInfo {
  final String rev;
  final int seq;
  final String lastEvent;
  final String updatedAt;
  final String apkVersion;
  final int apkBuild;
  final String webVersion;

  const SyncVersionInfo({
    required this.rev,
    required this.seq,
    required this.lastEvent,
    required this.updatedAt,
    required this.apkVersion,
    required this.apkBuild,
    required this.webVersion,
  });

  factory SyncVersionInfo.fromJson(Map<String, dynamic> j) => SyncVersionInfo(
        rev: (j['rev'] ?? '').toString(),
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        lastEvent: (j['last_event'] ?? '').toString(),
        updatedAt: (j['updated_at'] ?? '').toString(),
        apkVersion: (j['apk_version'] ?? '1.0.0').toString(),
        apkBuild: (j['apk_build'] as num?)?.toInt() ?? 1,
        webVersion: (j['web_version'] ?? '').toString(),
      );
}

class ApkVersionInfo {
  final String version;
  final int build;
  final String full;
  final String builtAt;
  final int sizeBytes;
  final bool available;
  final String downloadUrl;

  const ApkVersionInfo({
    required this.version,
    required this.build,
    required this.full,
    required this.builtAt,
    required this.sizeBytes,
    required this.available,
    required this.downloadUrl,
  });

  factory ApkVersionInfo.fromJson(Map<String, dynamic> j, String baseUrl) =>
      ApkVersionInfo(
        version: (j['version'] ?? '1.0.0').toString(),
        build: (j['build'] as num?)?.toInt() ?? 1,
        full: (j['full'] ?? '1.0.0+1').toString(),
        builtAt: (j['built_at'] ?? '').toString(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        available: j['available'] == true,
        downloadUrl: '$baseUrl${j['download_path'] ?? '/download/hisobchi.apk'}',
      );
}

class MathLineError {
  final String name;
  final double? qty;
  final double? unitPrice;
  final double expected;
  final double written;
  final double difference;

  const MathLineError({
    required this.name,
    this.qty,
    this.unitPrice,
    required this.expected,
    required this.written,
    required this.difference,
  });

  factory MathLineError.fromJson(Map<String, dynamic> j) => MathLineError(
        name: (j['name'] ?? 'Mahsulot').toString(),
        qty: (j['qty'] as num?)?.toDouble(),
        unitPrice: (j['unit_price'] as num?)?.toDouble(),
        expected: (j['expected'] as num?)?.toDouble() ?? 0.0,
        written: (j['written'] as num?)?.toDouble() ?? 0.0,
        difference: (j['difference'] as num?)?.toDouble() ?? 0.0,
      );
}

class MathCheckResult {
  final String status; // ok | vat_ok | computed | adjusted | mismatch | skipped
  final int itemsCount;
  final double? writtenTotal;
  final double? calculatedTotal;
  final double? roundedCalculatedTotal;
  final double? difference;
  final List<MathLineError> lineErrors;
  final String warningText;

  const MathCheckResult({
    required this.status,
    required this.itemsCount,
    this.writtenTotal,
    this.calculatedTotal,
    this.roundedCalculatedTotal,
    this.difference,
    this.lineErrors = const [],
    this.warningText = '',
  });

  bool get isMismatch => status == 'mismatch';
  bool get isOk => status == 'ok' || status == 'vat_ok';
  bool get isComputed => status == 'computed';
  bool get isAdjusted => status == 'adjusted';
  bool get hasDisplay => status != 'skipped' && itemsCount > 0;

  factory MathCheckResult.fromJson(Map<String, dynamic> j) => MathCheckResult(
        status: (j['status'] ?? 'skipped').toString(),
        itemsCount: (j['items_count'] as num?)?.toInt() ?? 0,
        writtenTotal: (j['written_total'] as num?)?.toDouble(),
        calculatedTotal: (j['calculated_total'] as num?)?.toDouble(),
        roundedCalculatedTotal:
            (j['rounded_calculated_total'] as num?)?.toDouble(),
        difference: (j['difference'] as num?)?.toDouble(),
        lineErrors: ((j['line_errors'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MathLineError.fromJson)
            .toList(),
        warningText: (j['warning_text'] ?? '').toString(),
      );
}

class AiExtractResult {
  final bool ok;
  final String? supplierName;
  final String? supplierSuggestion;
  final List<String> similarSuppliers;
  final double? amount;
  final double? originalAmount;
  final bool isClear;
  final List<double> recentAmounts;
  final String? anomalyWarning;
  final MathCheckResult? mathCheck;
  final String? errorCode;
  final String message;

  const AiExtractResult({
    required this.ok,
    this.supplierName,
    this.supplierSuggestion,
    this.similarSuppliers = const [],
    this.amount,
    this.originalAmount,
    required this.isClear,
    required this.recentAmounts,
    this.anomalyWarning,
    this.mathCheck,
    this.errorCode,
    required this.message,
  });

  factory AiExtractResult.fromJson(Map<String, dynamic> j) => AiExtractResult(
        ok: j['ok'] == true,
        supplierName: j['supplier_name']?.toString(),
        supplierSuggestion: j['supplier_suggestion']?.toString(),
        similarSuppliers: ((j['similar_suppliers'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        amount: (j['amount'] as num?)?.toDouble(),
        originalAmount: (j['original_amount'] as num?)?.toDouble(),
        isClear: j['is_clear'] == true,
        recentAmounts: ((j['recent_amounts'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        anomalyWarning: j['anomaly_warning']?.toString(),
        mathCheck: j['math_check'] is Map<String, dynamic>
            ? MathCheckResult.fromJson(j['math_check'] as Map<String, dynamic>)
            : null,
        errorCode: j['error_code']?.toString(),
        message: (j['message'] ?? '').toString(),
      );
}
