import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  final String sourceType; // main | kassa_debt | kassa_repay
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

class StatusSummary {
  final int sessionId;
  final String reportDate;
  final String sessionStatus;
  final double openingBalance;
  final double mainCashIn;
  final double kassaDebtToday;
  final double kassaRepayToday;
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

  const StatusSummary({
    required this.sessionId,
    required this.reportDate,
    required this.sessionStatus,
    required this.openingBalance,
    required this.mainCashIn,
    required this.kassaDebtToday,
    required this.kassaRepayToday,
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
        openingBalance: (j['opening_balance'] as num).toDouble(),
        mainCashIn: (j['main_cash_in'] as num).toDouble(),
        kassaDebtToday: (j['kassa_debt_today'] as num).toDouble(),
        kassaRepayToday: (j['kassa_repay_today'] as num).toDouble(),
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
  final http.Client _http;

  HisobchiApiClient({
    this.baseUrl = defaultBaseUrl,
    this.accessToken,
    this.role = 'admin',
    this.userId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  bool get isAuthenticated => accessToken != null && accessToken!.isNotEmpty;
  bool get canWrite => role == 'admin' || role == 'kassir';

  static String normalizeBaseUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = normalizeBaseUrl(prefs.getString(_prefBaseUrl) ?? defaultBaseUrl);
    accessToken = prefs.getString(_prefToken);
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
    await prefs.setString(_prefToken, token);
    await prefs.setString(_prefRole, userRole);
    await prefs.setInt(_prefUserId, uid);
  }

  Future<void> clearSession() async {
    accessToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefToken);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return u;
    return u.replace(queryParameters: query);
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    final h = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      h['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $accessToken';
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
    final res = await _http
        .get(_uri('/status'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    return StatusSummary.fromJson(_decodeJson(res));
  }

  Future<CashTxItem> addCash({
    required double amount,
    required String sourceType,
    String note = '',
  }) async {
    final res = await _http
        .post(
          _uri('/cash'),
          headers: _headers(),
          body: jsonEncode({
            'amount': amount,
            'source_type': sourceType,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 12));
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

  Future<List<String>> getSuppliers({String query = ''}) async {
    final res = await _http
        .get(_uri('/suppliers', query.isEmpty ? null : {'q': query}),
            headers: _headers())
        .timeout(const Duration(seconds: 10));
    final data = _decodeJson(res);
    return ((data['suppliers'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
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
    File? photoFile,
    double? originalAmount,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/nakladnoy'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['supplier_name'] = supplierName.trim();
    req.fields['amount'] = amount.toStringAsFixed(0);
    req.fields['payment_mode'] = paymentMode;
    req.fields['note'] = note.trim();
    req.fields['send_to_group'] = sendToGroup ? 'true' : 'false';
    if (originalAmount != null) {
      req.fields['original_amount'] = originalAmount.toStringAsFixed(0);
    }

    if (photoFile != null && await photoFile.exists()) {
      req.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path),
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
  }) async {
    final res = await _http
        .post(
          _uri('/nakladnoy/$paymentId/paid'),
          headers: _headers(),
          body: jsonEncode({'payment_method': paymentMethod}),
        )
        .timeout(const Duration(seconds: 12));
    return NakladnoyItem.fromJson(_decodeJson(res));
  }

  Future<String> sendNakladnoyToGroup(int paymentId) async {
    final res = await _http
        .post(_uri('/nakladnoy/$paymentId/group'), headers: _headers())
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

  Future<List<NakladnoyItem>> getUnpaidDebts() async {
    final res = await _http
        .get(_uri('/debts'), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return ((data['items'] as List?) ?? const [])
        .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> closeDay(double actualCountedCash) async {
    final res = await _http
        .post(
          _uri('/day/close'),
          headers: _headers(),
          body: jsonEncode({'actual_counted_cash': actualCountedCash}),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeJson(res);
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

  String photoUrlFor(int paymentId) =>
      '$baseUrl/nakladnoy/$paymentId/photo?token=${Uri.encodeComponent(accessToken ?? '')}';

  /// Send nakladnoy photo to server-side Gemini Vision; returns supplier & amount guess.
  Future<AiExtractResult> extractFromPhoto(File photoFile) async {
    final req = http.MultipartRequest('POST', _uri('/ai/extract'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.files.add(await http.MultipartFile.fromPath('photo', photoFile.path));
    final streamed = await _http.send(req).timeout(const Duration(seconds: 45));
    final res = await http.Response.fromStream(streamed);
    return AiExtractResult.fromJson(_decodeJson(res));
  }

  Future<ApkVersionInfo> checkApkVersion() async {
    final res = await _http
        .get(_uri('/apk/version'))
        .timeout(const Duration(seconds: 10));
    return ApkVersionInfo.fromJson(_decodeJson(res), baseUrl);
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

  Future<File> downloadApkToFileWithProgress({
    required File targetFile,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    int fallbackTotalBytes = 0,
  }) async {
    final req = http.Request('GET', _uri('/download/hisobchi.apk'));
    final streamed =
        await _http.send(req).timeout(const Duration(seconds: 180));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(
        'APK yuklab olishda xatolik (HTTP ${streamed.statusCode})',
        statusCode: streamed.statusCode,
      );
    }
    final total = (streamed.contentLength != null && streamed.contentLength! > 0)
        ? streamed.contentLength!
        : fallbackTotalBytes;
    final sink = targetFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received < 100 * 1024) {
      throw const ApiException('Yuklangan APK fayl to\'liq emas');
    }
    return targetFile;
  }

  // Stage 1: History sessions, detail, reopen & global search
  Future<List<HistorySessionItem>> getHistorySessions({int limit = 25}) async {
    final res = await _http
        .get(_uri('/history/sessions', {'limit': '$limit'}), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return ((data['sessions'] as List?) ?? const [])
        .map((e) => HistorySessionItem.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final res = await _http
        .get(_uri('/history/search', {'q': query.trim()}), headers: _headers())
        .timeout(const Duration(seconds: 15));
    final data = _decodeJson(res);
    return ((data['items'] as List?) ?? const [])
        .map((e) => NakladnoyItem.fromJson(e as Map<String, dynamic>))
        .toList();
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
    File photoFile, {
    bool sendToGroup = true,
  }) async {
    final req =
        http.MultipartRequest('POST', _uri('/nakladnoy/$paymentId/photo'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['send_to_group'] = sendToGroup ? 'true' : 'false';
    req.files.add(await http.MultipartFile.fromPath('photo', photoFile.path));
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
    required File file,
    bool publishToGroup = false,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/prixod/file'));
    if (accessToken != null) {
      req.headers['Authorization'] = 'Bearer $accessToken';
    }
    req.fields['publish_to_group'] = publishToGroup ? 'true' : 'false';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
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
  });

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
        mathCheck: j['math_check'] is Map<String, dynamic>
            ? MathCheckResult.fromJson(j['math_check'] as Map<String, dynamic>)
            : null,
        errorCode: j['error_code']?.toString(),
        message: (j['message'] ?? '').toString(),
      );
}
