import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';
import 'theme.dart';
import 'version.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HisobchiApp());
}

/// Computes safe bottom padding inside modal bottom sheets so buttons NEVER slip
/// behind Android's 3-button or gesture navigation bar OR the soft keyboard.
double sheetBottomPadding(BuildContext context) {
  final insets = MediaQuery.viewInsetsOf(context).bottom;
  final navBar = MediaQuery.viewPaddingOf(context).bottom;
  return (insets > navBar ? insets : navBar) + 24;
}

const Map<String, String> _kCyrToLat = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'ғ': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'yo',
  'ж': 'j',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'қ': 'q',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ў': 'o',
  'ф': 'f',
  'х': 'x',
  'ҳ': 'h',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': '',
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
};

const Map<String, String> _kCursiveSkeletonMap = {
  'и': 'u',
  'й': 'u',
  'у': 'u',
  'ы': 'u',
  'ю': 'u',
  'i': 'u',
  'u': 'u',
  'y': 'u',
  'т': 'm',
  'м': 'm',
  'п': 'm',
  'н': 'm',
  'ш': 'm',
  'щ': 'm',
  't': 'm',
  'm': 'm',
  'n': 'm',
  'а': 'a',
  'о': 'a',
  'ў': 'a',
  'я': 'a',
  'a': 'a',
  'o': 'a',
  'е': 'e',
  'э': 'e',
  'ё': 'e',
  'e': 'e',
  'р': 'p',
  'p': 'p',
  'r': 'p',
  'с': 'c',
  's': 'c',
  'c': 'c',
  'х': 'x',
  'ҳ': 'x',
  'x': 'x',
  'h': 'x',
  'в': 'b',
  'б': 'b',
  'v': 'b',
  'b': 'b',
  'к': 'k',
  'қ': 'k',
  'k': 'k',
  'q': 'k',
  'г': 'g',
  'ғ': 'g',
  'д': 'g',
  'g': 'g',
  'd': 'g',
  'л': 'l',
  'l': 'l',
  'з': 'z',
  'z': 'z',
  'ж': 'j',
  'j': 'j',
  'ч': 'r',
  'ф': 'f',
  'f': 'f',
};

String _toLatPhonetic(String s) {
  final low = s.trim().toLowerCase();
  final sb = StringBuffer();
  for (var i = 0; i < low.length; i++) {
    final ch = low[i];
    sb.write(_kCyrToLat[ch] ?? ch);
  }
  return sb.toString();
}

String _toCursiveSkeleton(String s) {
  final low = s.trim().toLowerCase();
  final sb = StringBuffer();
  for (var i = 0; i < low.length; i++) {
    final ch = low[i];
    sb.write(_kCursiveSkeletonMap[ch] ?? ch);
  }
  return sb.toString();
}

double _charBigramSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
  if (a.length < 2 || b.length < 2) {
    return a[0] == b[0] ? 0.6 : 0.0;
  }
  final aGrams = <String>[];
  for (var i = 0; i < a.length - 1; i++) {
    aGrams.add(a.substring(i, i + 2));
  }
  final bGrams = <String>[];
  for (var i = 0; i < b.length - 1; i++) {
    bGrams.add(b.substring(i, i + 2));
  }
  var matches = 0;
  final used = List<bool>.filled(bGrams.length, false);
  for (final ag in aGrams) {
    for (var j = 0; j < bGrams.length; j++) {
      if (!used[j] && ag == bGrams[j]) {
        used[j] = true;
        matches++;
        break;
      }
    }
  }
  return (2.0 * matches) / (aGrams.length + bGrams.length);
}

double crossScriptSupplierScore(String query, String candidate) {
  final q = query.trim().toLowerCase();
  final c = candidate.trim().toLowerCase();
  if (q.isEmpty || c.isEmpty) return 0.0;
  if (q == c) return 1.0;
  if (c.contains(q) || q.contains(c)) return 0.88;

  final direct = _charBigramSimilarity(q, c);
  final qLat = _toLatPhonetic(q);
  final cLat = _toLatPhonetic(c);
  final phonetic = qLat == cLat ? 0.98 : _charBigramSimilarity(qLat, cLat);

  final qCur = _toCursiveSkeleton(q);
  final cCur = _toCursiveSkeleton(c);
  var cursive = 0.0;
  if (qCur.length >= 3 && cCur.length >= 3) {
    final raw = qCur == cCur ? 1.0 : _charBigramSimilarity(qCur, cCur);
    final lenRatio =
        (qCur.length < cCur.length ? qCur.length : cCur.length) /
            (qCur.length > cCur.length ? qCur.length : cCur.length);
    cursive = raw * (0.74 + 0.21 * lenRatio);
  }
  var best = direct > phonetic ? direct : phonetic;
  if (cursive > best) best = cursive;
  return best;
}

List<String> findLocalSimilarSuppliers(
  String raw,
  List<String> allSuppliers, {
  int limit = 4,
  double cutoff = 0.58,
}) {
  final q = raw.trim();
  if (q.isEmpty) return const [];
  final qLow = q.toLowerCase();
  final scored = <({String name, double score})>[];
  for (final s in allSuppliers) {
    if (s.trim().toLowerCase() == qLow) continue;
    var sc = crossScriptSupplierScore(qLow, s);
    final firstWord = s.trim().split(' ').first;
    if (firstWord.length >= 4 && !qLow.contains(' ')) {
      final wSc = crossScriptSupplierScore(qLow, firstWord) * 0.93;
      if (wSc > sc) sc = wSc;
    }
    if (sc >= cutoff) {
      scored.add((name: s, score: sc));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).map((e) => e.name).toList();
}

/// Opens a searchable bottom picker of all known suppliers.
Future<String?> showSupplierPickerDialog(
  BuildContext context,
  List<String> suppliers, {
  String current = '',
}) async {
  var query = '';
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final filtered = suppliers
            .where((s) =>
                query.isEmpty ||
                s.toLowerCase().contains(query.toLowerCase()) ||
                crossScriptSupplierScore(query, s) >= 0.62)
            .toList();
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              bottom: sheetBottomPadding(ctx),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.68,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded,
                          color: AppTokens.brand),
                      const SizedBox(width: 8),
                      Text(
                        'Postavshik tanlash (${suppliers.length} ta)',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setModalState(() => query = v.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Postavshik nomini qidiring...',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (query.isNotEmpty &&
                      !suppliers.any(
                          (s) => s.toLowerCase() == query.toLowerCase()))
                    ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor: AppTokens.brand.withValues(alpha: 0.12),
                      leading: const Icon(Icons.add_business_rounded,
                          color: AppTokens.brand),
                      title: Text(
                        'Yangi qo\'shish: "$query"',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => Navigator.pop(ctx, query),
                    ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Postavshik topilmadi',
                              style: TextStyle(color: textSecondaryOf(ctx)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final name = filtered[i];
                              final isCur = name.toLowerCase() ==
                                  current.trim().toLowerCase();
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isCur
                                      ? Icons.check_circle_rounded
                                      : Icons.apartment_rounded,
                                  color: isCur
                                      ? AppTokens.cashGreen
                                      : textSecondaryOf(ctx),
                                  size: 20,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isCur
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                                onTap: () => Navigator.pop(ctx, name),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class HisobchiApp extends StatefulWidget {
  final HisobchiApiClient? apiOverride;

  const HisobchiApp({super.key, this.apiOverride});

  @override
  State<HisobchiApp> createState() => _HisobchiAppState();
}

class _HisobchiAppState extends State<HisobchiApp> {
  late final HisobchiApiClient _api;
  ThemeMode _themeMode = ThemeMode.system;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? HisobchiApiClient();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.apiOverride == null) {
      await _api.loadSavedSession();
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisobchi',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _initializing
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _api.isAuthenticated
              ? MainWorkspaceScreen(
                  api: _api,
                  onToggleTheme: _toggleTheme,
                  onLoggedOut: () => setState(() {}),
                )
              : LoginScreen(
                  api: _api,
                  onLoggedIn: () => setState(() {}),
                ),
    );
  }
}

// ============================================================================
// LOGIN SCREEN
// ============================================================================

class LoginScreen extends StatefulWidget {
  final HisobchiApiClient api;
  final VoidCallback onLoggedIn;

  const LoginScreen({
    super.key,
    required this.api,
    required this.onLoggedIn,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _urlCtrl;
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _deviceCtrl =
      TextEditingController(text: 'Android APK');
  bool _loading = false;
  bool _testingUrl = false;
  String? _error;
  String? _urlOkMessage;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.api.baseUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _codeCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingUrl = true;
      _error = null;
      _urlOkMessage = null;
    });
    try {
      final ok = await widget.api.checkHealth(_urlCtrl.text);
      if (mounted) {
        setState(() {
          _urlOkMessage = ok
              ? 'Server bilan aloqa muvaffaqiyatli!'
              : 'Server javob bermadi';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Serverga ulanib bo\'lmadi: $e');
      }
    } finally {
      if (mounted) setState(() => _testingUrl = false);
    }
  }

  Future<void> _submitLogin() async {
    final code = _codeCtrl.text.replaceAll(RegExp(r'\D+'), '');
    if (code.length != 8) {
      setState(() =>
          _error = 'Telegram botdan (/apk) olingan 8 xonali kodni kiriting.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.login(
        serverUrl: _urlCtrl.text,
        code: code,
        deviceName: _deviceCtrl.text,
      );
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (errFg, errBg, errBorder) =
        AppTokens.semanticSurface(context, AppTokens.dangerRed);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: AppTokens.heroGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTokens.brand.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.asset(
                                'assets/app_icon.png',
                                width: 46,
                                height: 46,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: Colors.white,
                                    size: 32),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Hisobchi Mobil',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Telegram bot, AI nakladnoy skaneri va Nakladnoy guruhi bilan bevosita sinxron ishlovchi rasmiy kassa ilovasi.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Qanday ulanadi?',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _stepRow('1',
                              'Telegramda @hisobchi_my_bot ga kiring va /apk buyrug\'ini yuboring.'),
                          const SizedBox(height: 6),
                          _stepRow('2',
                              'Bot bergan 8 xonali bir martalik kodni quyiga kiriting.'),
                          const SizedBox(height: 6),
                          _stepRow('3',
                              'Nakladnoy qaysi guruhga tushishini botning o\'zida (/apk yoki Sozlamalar) boshqarasiz.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Server manzili (Domen / HTTPS)',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _urlCtrl,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    hintText: 'https://hisobchi.okaposai.uz',
                                    prefixIcon: Icon(Icons.dns_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed:
                                    _testingUrl ? null : _testConnection,
                                child: _testingUrl
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('Tekshirish'),
                              ),
                            ],
                          ),
                          if (_urlOkMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              '✅ $_urlOkMessage',
                              style: const TextStyle(
                                color: AppTokens.cashGreen,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          const Text(
                            '8 xonali kirish kodi (/apk)',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _codeCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontFeatures: AppTokens.tabularNums,
                            ),
                            decoration: const InputDecoration(
                              hintText: '1234-5678',
                              prefixIcon: Icon(Icons.vpn_key_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Qurilma nomi',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _deviceCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Masalan: Kassir Samsung',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: errBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: errBorder),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: errFg,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submitLogin,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(
                                _loading ? 'Ulanmoqda...' : 'Ilovaga kirish'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(String numStr, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTokens.brand.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(
            numStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTokens.brand,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// MAIN 4-TAB WORKSPACE:
// 0: Dashboard (Haqiqiy Analitik Dashboard + Pul Oldi-Berdi Tarixi)
// 1: Nakladnoylar (Bugungi Nakladnoylar Ro'yxati + Dropdown Filter/Saralash)
// 2: Qarzlar (To'lanmagan Qarzlar + Postavshik Dropdown Filter)
// 3: Smena & Excel (Kunni Yakunlash + Excel Hisobotlar Dropdown + Sozlamalar)
// ============================================================================

class MainWorkspaceScreen extends StatefulWidget {
  final HisobchiApiClient api;
  final VoidCallback onToggleTheme;
  final VoidCallback onLoggedOut;

  const MainWorkspaceScreen({
    super.key,
    required this.api,
    required this.onToggleTheme,
    required this.onLoggedOut,
  });

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen> {
  int _tabIndex = 0;
  StatusSummary? _summary;
  List<NakladnoyItem> _allDebts = [];
  bool _loading = true;
  String? _error;

  // Nakladnoylar tab filter & sort dropdown states
  String _filterMode = 'all'; // all | cash | card | transfer | debt
  String _sortMode = 'newest'; // newest | amount_desc | supplier_az
  String _searchQuery = '';

  // Qarzlar tab supplier dropdown filter & sub-tab ('nakladnoy' | 'nasiya')
  String _debtSupplierFilter = 'all';
  String _debtSubTab = 'nakladnoy';

  ApkVersionInfo? _remoteVersion;
  bool _updatingApk = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getStatus(),
        widget.api.getUnpaidDebts(),
      ]);
      ApkVersionInfo? ver;
      try {
        ver = await widget.api.checkApkVersion();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _summary = results[0] as StatusSummary;
          _allDebts = results[1] as List<NakladnoyItem>;
          if (ver != null) _remoteVersion = ver;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await widget.api.clearSession();
        if (mounted) widget.onLoggedOut();
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Aloqa xatosi: $e';
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTokens.dangerRed : AppTokens.navyDark,
      ),
    );
  }

  Future<void> _downloadAndShareApkUpdate() async {
    if (_updatingApk) return;
    final ver = _remoteVersion?.version ?? kAppVersion;
    setState(() => _updatingApk = true);
    _showSnack('📥 Yangi versiya (v$ver) yuklab olinmoqda...');
    try {
      final bytes = await widget.api.downloadLatestApkBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Hisobchi_v$ver.apk');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "Hisobchi v$ver yangi versiyasi — ustiga bosib o'rnating",
      );
    } catch (e) {
      _showSnack('Yangilashda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingApk = false);
    }
  }

  Future<void> _openCashDialog(
    String sourceType, {
    CashTxItem? existing,
  }) async {
    final titles = {
      'main': existing != null
          ? 'Olingan pulni tahrirlash'
          : 'Pul oldim (Asosiy kirim)',
      'kassa_debt': existing != null
          ? 'Kassa qarzini tahrirlash'
          : 'Kassadan qarz oldim',
      'kassa_repay': existing != null
          ? 'Qaytarilgan pulni tahrirlash'
          : 'Kassaga qaytardim',
    };
    final icons = {
      'main': Icons.add_card_rounded,
      'kassa_debt': Icons.account_balance_rounded,
      'kassa_repay': Icons.assignment_return_rounded,
    };
    final amtCtrl = TextEditingController(
      text: existing != null
          ? UzsAmountInputFormatter.formatDigits(
              existing.amount.round().toString())
          : '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: sheetBottomPadding(ctx),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icons[sourceType] ?? Icons.payments_rounded,
                      color: AppTokens.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titles[sourceType] ?? 'Kassa amali',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amtCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: const [UzsAmountInputFormatter()],
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  fontFeatures: AppTokens.tabularNums,
                ),
                decoration: const InputDecoration(
                  labelText: "Summa (so'm)",
                  hintText: '5 000 000',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Izoh (kimdan / nima uchun)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check_rounded),
                label: Text(existing != null ? 'Yangilash' : 'Saqlash'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final val = parseUzsInput(amtCtrl.text);
      if (val == null || val <= 0) {
        _showSnack('Summani to\'g\'ri kiriting', isError: true);
        return;
      }
      try {
        if (existing != null) {
          await widget.api.updateCash(
            txId: existing.id,
            amount: val,
            note: noteCtrl.text,
          );
          _showSnack('✅ Kassa amali yangilandi!');
        } else {
          await widget.api.addCash(
            amount: val,
            sourceType: sourceType,
            note: noteCtrl.text,
          );
          _showSnack('✅ Kassa amali saqlandi!');
        }
        await _refreshAll();
      } catch (e) {
        _showSnack(e.toString(), isError: true);
      }
    }
  }

  Future<void> _openAddNakladnoySheet({File? initialPhoto}) async {
    final grpInfo = _summary?.groupInfo ??
        const GroupInfo(bound: false, title: '', apkPostToGroup: true);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => AddNakladnoySheet(
        api: widget.api,
        groupInfo: grpInfo,
        initialPhoto: initialPhoto,
      ),
    );
    if (saved == true) {
      await _refreshAll();
    }
  }

  Future<void> _openNakladnoyDetail(NakladnoyItem item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => NakladnoyDetailSheet(
        api: widget.api,
        item: item,
      ),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _openPayDebtDialog(NakladnoyItem item) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, sheetBottomPadding(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Qarzni to'lash (${item.displayNum})",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.supplierName} — ${formatUzs(item.amount, withCurrency: true)}',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.cashGreen),
                onPressed: () => Navigator.pop(ctx, 'cash'),
                icon: const Icon(Icons.payments_rounded),
                label: const Text("Naqd to'landi (kassadan ayriladi)"),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTokens.cardBlue),
                onPressed: () => Navigator.pop(ctx, 'card'),
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text("Karta orqali (naqddan ayrilmaydi)"),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.transferPurple),
                onPressed: () => Navigator.pop(ctx, 'transfer'),
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text("Perechesleniya / O'tkazma"),
              ),
            ],
          ),
        ),
      ),
    );

    if (method != null) {
      try {
        await widget.api.payDebt(paymentId: item.id, paymentMethod: method);
        _showSnack("✅ Qarz to'landi va guruh xabari yangilandi!");
        await _refreshAll();
      } catch (e) {
        _showSnack(e.toString(), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final debtCount = _summary?.allUnpaidDebtCount ?? _allDebts.length;
    final nakCount = _summary?.nakladnoys.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                'assets/app_icon.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppTokens.heroGradient,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 19, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Hisobchi'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppTokens.brand.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'v$kAppVersion',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.brand,
                  fontFeatures: AppTokens.tabularNums,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Mavzu (Kun/Tun)',
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.brightness_6_rounded),
          ),
        ],
      ),
      // Compact "+" icon FAB (no "+ Nakladnoy" text label)
      floatingActionButton: _tabIndex <= 2 && widget.api.canWrite
          ? FloatingActionButton(
              tooltip: 'Yangi Nakladnoy qo\'shish',
              onPressed: () => _openAddNakladnoySheet(),
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (i) => setState(() => _tabIndex = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: nakCount > 0,
                label: Text('$nakCount'),
                child: const Icon(Icons.receipt_long_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: nakCount > 0,
                label: Text('$nakCount'),
                child: const Icon(Icons.receipt_long_rounded),
              ),
              label: 'Nakladnoylar',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: debtCount > 0,
                label: Text('$debtCount'),
                child: const Icon(Icons.push_pin_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: debtCount > 0,
                label: Text('$debtCount'),
                child: const Icon(Icons.push_pin_rounded),
              ),
              label: 'Qarzlar',
            ),
            const NavigationDestination(
              icon: Icon(Icons.assessment_outlined),
              selectedIcon: Icon(Icons.assessment_rounded),
              label: 'Smena & Excel',
            ),
          ],
        ),
      ),
      body: _loading && _summary == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _summary == null
              ? _buildErrorState()
              : Column(
                  children: [
                    if (_remoteVersion != null &&
                        _remoteVersion!.build > kAppBuildNumber)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          gradient: AppTokens.aiGradient,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.system_update_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '🚀 Yangi versiya chiqdi: v${_remoteVersion!.version} (sizda v$kAppVersion)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTokens.brandDeep,
                                minimumSize: const Size(70, 36),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: _updatingApk
                                  ? null
                                  : _downloadAndShareApkUpdate,
                              child: Text(_updatingApk
                                  ? 'Yuklanmoqda...'
                                  : 'Yangilash'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: _tabIndex,
                        children: [
                          _buildDashboardTab(),
                          _buildNakladnoylarTab(),
                          _buildDebtsTab(),
                          _buildSmenaAndReportsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 52, color: AppTokens.dangerRed),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Xatolik',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openHistorySessionsSheet() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => HistorySessionsSheet(
        api: widget.api,
        onOpenNakladnoyDetail: _openNakladnoyDetail,
      ),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _openGlobalSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => GlobalHistorySearchSheet(
        api: widget.api,
        onOpenNakladnoyDetail: _openNakladnoyDetail,
      ),
    );
    await _refreshAll();
  }

  Future<void> _openLiveSverkaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => LiveSverkaAndStatsSheet(
        api: widget.api,
        showSnack: _showSnack,
      ),
    );
  }

  Future<void> _openPrixodSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => PrixodItogSheet(
        api: widget.api,
        showSnack: _showSnack,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: HAQIQIY ANALITIK DASHBOARD & PUL OLDI-BERDI TARIXI
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab() {
    final s = _summary!;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          HeroBalanceCard(
            summary: s,
            onAddCash:
                widget.api.canWrite ? () => _openCashDialog('main') : null,
            onKassaDebt: widget.api.canWrite
                ? () => _openCashDialog('kassa_debt')
                : null,
            onKassaRepay: widget.api.canWrite
                ? () => _openCashDialog('kassa_repay')
                : null,
          ),
          const SizedBox(height: 12),
          // Quick buttons for Stage 1 (History) & Stage 2 (Live Sverka & Stats)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openLiveSverkaSheet,
                  icon: const Icon(Icons.query_stats_rounded, size: 18),
                  label: const Text('Jonli Sverka & 7/30 kun'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openHistorySessionsSheet,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text("O'tgan smenalar"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DashboardAnalyticsSection(
            summary: s,
            canWrite: widget.api.canWrite,
            onTapPaymentFilter: (mode) {
              setState(() {
                _filterMode = mode;
                _tabIndex = 1;
              });
            },
            onOpenNakladnoyTab: () => setState(() => _tabIndex = 1),
            onEditCashTx: (tx) =>
                _openCashDialog(tx.sourceType, existing: tx),
            onDeleteCashTx: (tx) async {
              await widget.api.deleteCash(tx.id);
              _showSnack("Kassa amali o'chirildi");
              await _refreshAll();
            },
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: DEDICATED NAKLADNOYLAR RO'YXATI (With Dropdown Filter & Sort)
  // --------------------------------------------------------------------------

  Widget _buildNakladnoylarTab() {
    final s = _summary!;
    final filtered = s.nakladnoys.where((n) {
      if (_filterMode == 'cash' && (n.isDebt || n.paymentMethod != 'cash')) {
        return false;
      }
      if (_filterMode == 'card' && (n.isDebt || n.paymentMethod != 'card')) {
        return false;
      }
      if (_filterMode == 'transfer' &&
          (n.isDebt || n.paymentMethod != 'transfer')) {
        return false;
      }
      if (_filterMode == 'debt' && !n.isDebt) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return n.supplierName.toLowerCase().contains(q) ||
            n.displayNum.toLowerCase().contains(q) ||
            n.amount.toStringAsFixed(0).contains(q);
      }
      return true;
    }).toList();

    if (_sortMode == 'amount_desc') {
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (_sortMode == 'supplier_az') {
      filtered.sort((a, b) =>
          a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase()));
    } else {
      filtered.sort((a, b) => b.id.compareTo(a.id));
    }

    final filteredSum =
        filtered.fold<double>(0, (prev, elem) => prev + elem.amount);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        children: [
          // Header strip
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nakladnoylar (${filtered.length} ta)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                formatUzs(filteredSum, withCurrency: true),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.brand,
                  fontFeatures: AppTokens.tabularNums,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Filter & Sort Dropdown Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filterMode,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: "To'lov turi",
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Barchasi (${s.nakladnoys.length})'),
                    ),
                    const DropdownMenuItem(
                      value: 'cash',
                      child: Text('💵 Naqd to\'lov'),
                    ),
                    const DropdownMenuItem(
                      value: 'card',
                      child: Text('💳 Karta orqali'),
                    ),
                    const DropdownMenuItem(
                      value: 'transfer',
                      child: Text("🏦 O'tkazma"),
                    ),
                    const DropdownMenuItem(
                      value: 'debt',
                      child: Text('📌 Qarzga'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _filterMode = v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sortMode,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Saralash',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Yangilari tepada'),
                    ),
                    DropdownMenuItem(
                      value: 'amount_desc',
                      child: Text('Summasi katta'),
                    ),
                    DropdownMenuItem(
                      value: 'supplier_az',
                      child: Text('Postavshik (A-Z)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortMode = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Box + Global Search across all past days
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Bugungi nakladnoylardan qidirish...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openGlobalSearchSheet,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Arxiv'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 44, color: textSecondaryOf(context)),
                    const SizedBox(height: 10),
                    const Text(
                      'Nakladnoylar topilmadi',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "O'ng pastdagi '+' tugmasini bosib yangi nakladnoy qo'shing.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: textSecondaryOf(context)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NakladnoyListCard(
                  item: item,
                  onTap: () => _openNakladnoyDetail(item),
                  onQuickPay: item.isDebt && widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: UNPAID DEBTS + NASIYA DAFTARI (/nasiya)
  // --------------------------------------------------------------------------

  Widget _buildDebtsTab() {
    if (_debtSubTab == 'nasiya') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _buildDebtSectionSwitcher(),
          ),
          Expanded(
            child: NasiyaLedgerView(
              api: widget.api,
              showSnack: _showSnack,
            ),
          ),
        ],
      );
    }

    final debtSuppliers = _allDebts
        .map((e) => e.supplierName)
        .toSet()
        .toList()
      ..sort();
    final activeSupFilter =
        (_debtSupplierFilter == 'all' || debtSuppliers.contains(_debtSupplierFilter))
            ? _debtSupplierFilter
            : 'all';

    final visibleDebts = activeSupFilter == 'all'
        ? _allDebts
        : _allDebts.where((d) => d.supplierName == activeSupFilter).toList();

    final totalDebt =
        visibleDebts.fold<double>(0, (acc, item) => acc + item.amount);
    final (amberFg, amberBg, amberBorder) =
        AppTokens.semanticSurface(context, AppTokens.debtAmber);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          _buildDebtSectionSwitcher(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: amberBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: amberBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, color: amberFg, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "To'lanmagan nakladnoy qarzlari (${visibleDebts.length} ta)",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatUzs(totalDebt, withCurrency: true),
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: amberFg,
                          fontFeatures: AppTokens.tabularNums,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (debtSuppliers.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: activeSupFilter,
              decoration: const InputDecoration(
                labelText: 'Postavshik bo\'yicha saralash',
                prefixIcon: Icon(Icons.filter_list_rounded),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('Barcha postavshiklar (${_allDebts.length} ta)'),
                ),
                ...debtSuppliers.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s),
                  ),
                ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _debtSupplierFilter = v);
              },
            ),
          ],
          const SizedBox(height: 14),
          if (visibleDebts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 46, color: AppTokens.cashGreen),
                    SizedBox(height: 10),
                    Text(
                      "To'lanmagan nakladnoy qarzlari yo'q!",
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ],
                ),
              ),
            )
          else
            ...visibleDebts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NakladnoyListCard(
                  item: item,
                  onTap: () => _openNakladnoyDetail(item),
                  onQuickPay: widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDebtSectionSwitcher() {
    return Row(
      children: [
        Expanded(
          child: _debtSubTab == 'nakladnoy'
              ? FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.push_pin_rounded, size: 17),
                  label: Text('Nakladnoy qarz (${_allDebts.length})'),
                )
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _debtSubTab = 'nakladnoy'),
                  icon: const Icon(Icons.push_pin_outlined, size: 17),
                  label: Text('Nakladnoy qarz (${_allDebts.length})'),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _debtSubTab == 'nasiya'
              ? FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.menu_book_rounded, size: 17),
                  label: const Text('Nasiya daftari'),
                )
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _debtSubTab = 'nasiya'),
                  icon: const Icon(Icons.menu_book_outlined, size: 17),
                  label: const Text('Nasiya daftari'),
                ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // TAB 4: SMENA YOPISH + EXCEL HISOBOTLAR + ARXIV & PRIXOD
  // --------------------------------------------------------------------------

  Widget _buildSmenaAndReportsTab() {
    final s = _summary!;
    return _SmenaAndReportsView(
      summary: s,
      api: widget.api,
      onClosed: _refreshAll,
      onLoggedOut: widget.onLoggedOut,
      showSnack: _showSnack,
      onOpenHistorySessions: _openHistorySessionsSheet,
      onOpenLiveSverka: _openLiveSverkaSheet,
      onOpenPrixod: _openPrixodSheet,
    );
  }
}

class _SmenaAndReportsView extends StatefulWidget {
  final StatusSummary summary;
  final HisobchiApiClient api;
  final Future<void> Function() onClosed;
  final VoidCallback onLoggedOut;
  final void Function(String, {bool isError}) showSnack;
  final VoidCallback onOpenHistorySessions;
  final VoidCallback onOpenLiveSverka;
  final VoidCallback onOpenPrixod;

  const _SmenaAndReportsView({
    required this.summary,
    required this.api,
    required this.onClosed,
    required this.onLoggedOut,
    required this.showSnack,
    required this.onOpenHistorySessions,
    required this.onOpenLiveSverka,
    required this.onOpenPrixod,
  });

  @override
  State<_SmenaAndReportsView> createState() => _SmenaAndReportsViewState();
}

class _SmenaAndReportsViewState extends State<_SmenaAndReportsView> {
  final TextEditingController _countedCtrl = TextEditingController();
  bool _closing = false;
  String _selectedReportType = 'today'; // today | week | month | custom | sverka
  bool _downloadingExcel = false;

  @override
  void dispose() {
    _countedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCloseDay() async {
    final counted = parseUzsInput(_countedCtrl.text);
    if (counted == null || counted < 0) {
      widget.showSnack("Qo'lda sanalgan haqiqiy pulni kiriting", isError: true);
      return;
    }
    setState(() => _closing = true);
    try {
      final res = await widget.api.closeDay(counted);
      _countedCtrl.clear();
      widget.showSnack(
        "🏁 Kun yakunlandi! Keyingi kunga qoldiq: ${formatUzs(res['next_opening_balance'] as num?, withCurrency: true)}",
      );
      await widget.onClosed();
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _runSelectedExcelExport() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekAgo = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));
    final monthStart = DateFormat('yyyy-MM-01').format(DateTime.now());

    String endpoint = '/export/session';
    String filename = 'Hisobot_${widget.summary.reportDate}.xlsx';
    Map<String, String>? query;

    if (_selectedReportType == 'week') {
      endpoint = '/export/range';
      query = {'date_from': weekAgo, 'date_to': today};
      filename = 'Hisobot_7kun_${weekAgo}_$today.xlsx';
    } else if (_selectedReportType == 'month') {
      endpoint = '/export/range';
      query = {'date_from': monthStart, 'date_to': today};
      filename = 'Hisobot_Oy_${monthStart}_$today.xlsx';
    } else if (_selectedReportType == 'sverka') {
      endpoint = '/export/sverka';
      filename = 'Sverka_$today.xlsx';
    } else if (_selectedReportType == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024, 1, 1),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (picked == null) return;
      final d1 = DateFormat('yyyy-MM-dd').format(picked.start);
      final d2 = DateFormat('yyyy-MM-dd').format(picked.end);
      endpoint = '/export/range';
      query = {'date_from': d1, 'date_to': d2};
      filename = 'Hisobot_${d1}_$d2.xlsx';
    }

    setState(() => _downloadingExcel = true);
    widget.showSnack('📥 Excel tayyorlanmoqda...');
    try {
      final bytes =
          await widget.api.downloadExcelBytes(endpoint, query: query);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Hisobchi Excel hisobot: $filename',
      );
    } catch (e) {
      widget.showSnack('Excel yuklashda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _downloadingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expected = widget.summary.expectedCash;
    final counted = parseUzsInput(_countedCtrl.text);
    final diff = counted != null ? counted - expected : null;

    Color diffBase = AppTokens.cashGreen;
    if (diff != null) {
      if (diff > 0) diffBase = AppTokens.cardBlue;
      if (diff < 0) diffBase = AppTokens.dangerRed;
    }
    final (diffFg, diffBg, diffBorder) =
        AppTokens.semanticSurface(context, diffBase);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        // 1. SMENA YOPISH CARD
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_clock_rounded, color: AppTokens.brand),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kunni yakunlash (Smena yopish)',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTokens.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Qo'lda bo'lishi kerak:",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        formatUzs(expected, withCurrency: true),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          fontFeatures: AppTokens.tabularNums,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _countedCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [UzsAmountInputFormatter()],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFeatures: AppTokens.tabularNums,
                  ),
                  decoration: InputDecoration(
                    labelText: "Qo'lda sanalgan haqiqiy pul (so'm)",
                    hintText: formatUzs(expected),
                    prefixIcon: const Icon(Icons.calculate_outlined),
                    suffixIcon: TextButton(
                      onPressed: () {
                        _countedCtrl.text =
                            UzsAmountInputFormatter.formatDigits(
                                expected.round().toString());
                        setState(() {});
                      },
                      child: const Text('Teng'),
                    ),
                  ),
                ),
                if (diff != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: diffBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: diffBorder),
                    ),
                    child: Text(
                      diff == 0
                          ? "✅ Farq: 0 so'm (Kassa 100% to'g'ri!)"
                          : (diff > 0
                              ? "➕ Ortiqcha: +${formatUzs(diff, withCurrency: true)}"
                              : "⚠️ Kamomad: ${formatUzs(diff, withCurrency: true)}"),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: diffFg,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      widget.api.canWrite && !_closing ? _submitCloseDay : null,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: Text(_closing
                      ? 'Yopilmoqda...'
                      : 'Kunni yakunlash va yangi kun ochish'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. EXCEL HISOBOTLAR & SVERKA (With Dropdown Selector)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.table_view_rounded, color: AppTokens.cashGreen),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Excel Hisobot va Sverka yuklash',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Kerakli davrni tanlab, tayyor Excel (.xlsx) faylni yuklab oling yoki Telegramga ulashing.",
                  style: TextStyle(
                      fontSize: 12.5, color: textSecondaryOf(context)),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReportType,
                  decoration: const InputDecoration(
                    labelText: 'Hisobot turini tanlang',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'today',
                      child: Text(
                          '📊 Bugungi kunlik hisobot (${widget.summary.reportDate})'),
                    ),
                    const DropdownMenuItem(
                      value: 'week',
                      child: Text('📅 Oxirgi 7 kunlik hisobot'),
                    ),
                    const DropdownMenuItem(
                      value: 'month',
                      child: Text('🗓 Joriy oy hisoboti'),
                    ),
                    const DropdownMenuItem(
                      value: 'custom',
                      child: Text("📆 Ixtiyoriy sana oralig'i..."),
                    ),
                    const DropdownMenuItem(
                      value: 'sverka',
                      child: Text('🏢 Postavshiklar Sverkasi'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedReportType = v);
                  },
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.cashGreen),
                  onPressed:
                      _downloadingExcel ? null : _runSelectedExcelExport,
                  icon: _downloadingExcel
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(_downloadingExcel
                      ? 'Tayyorlanmoqda...'
                      : 'Excel yuklab olish va ulashish'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenLiveSverka,
                  icon: const Icon(Icons.query_stats_rounded),
                  label: const Text("Ilova ichida Jonli Sverka va 7/30 kun ko'rish"),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2B. SMENALAR TARIXI & PRIXOD (ITOG 👑)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_edu_rounded,
                        color: AppTokens.brandViolet),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Smenalar Arxivi va Prixod (ITOG 👑)",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: widget.onOpenHistorySessions,
                  icon: const Icon(Icons.history_rounded),
                  label: const Text("📜 O'tgan smenalar tarixi va Qayta ochish"),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenPrixod,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text("👑 Prixod (ITOG) hisobotlari"),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 3. TELEGRAM GROUP & ACCOUNT SETTINGS
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.telegram, color: AppTokens.cardBlue, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Telegram guruh va Bot sozlamalari',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(
                  'Nakladnoy guruhi:',
                  widget.summary.groupInfo.bound
                      ? '✅ ${widget.summary.groupInfo.title}'
                      : '⚠️ Bog\'lanmagan',
                ),
                const SizedBox(height: 6),
                _infoRow(
                  'APK dan guruhga yuborish:',
                  widget.summary.groupInfo.apkPostToGroup
                      ? '✅ Yoqilgan'
                      : '🔕 O\'chirilgan (/apk)',
                ),
                const SizedBox(height: 6),
                _infoRow('Server:', widget.api.baseUrl),
                const SizedBox(height: 6),
                _infoRow('Ilova versiyasi:', 'v$kAppVersion (build #$kAppBuildNumber)'),
                const SizedBox(height: 6),
                _infoRow('Rol:', widget.api.role.toUpperCase()),
                const Divider(height: 24),
                Text(
                  "💡 Nakladnoylar yuboriladigan guruhni o'zgartirish uchun Telegram botda (@hisobchi_my_bot) /apk yoki ⚙️ Sozlamalar -> 🔗 Guruhlarni sozlash bo'limiga kiring.",
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: textSecondaryOf(context)),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTokens.dangerRed,
                    ),
                    onPressed: () async {
                      await widget.api.logout();
                      widget.onLoggedOut();
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Hisobdan chiqish'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String val) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(fontSize: 13.5, color: textSecondaryOf(context))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            val,
            textAlign: TextAlign.end,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// ADD NAKLADNOY SHEET:
// - Auto-AI OCR on photo pick
// - Space-formatted amount input (UzsAmountInputFormatter)
// - NO -10 000 / +10 000 buttons
// - Searchable Supplier Dropdown/Picker + Quick Chips
// - "Guruhga yuborish" switch default ON right above "Tasdiqlash va saqlash"
// ============================================================================

class AddNakladnoySheet extends StatefulWidget {
  final HisobchiApiClient api;
  final GroupInfo groupInfo;
  final File? initialPhoto;

  const AddNakladnoySheet({
    super.key,
    required this.api,
    required this.groupInfo,
    this.initialPhoto,
  });

  @override
  State<AddNakladnoySheet> createState() => _AddNakladnoySheetState();
}

class _AddNakladnoySheetState extends State<AddNakladnoySheet> {
  final TextEditingController _supCtrl = TextEditingController();
  final TextEditingController _amtCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  List<String> _allSuppliers = [];
  List<double> _recentAmounts = [];
  String _paymentMode = 'cash'; // cash | card | transfer | debt
  bool _sendToGroup = true; // Default ON as requested
  File? _photoFile;
  double? _originalAmount;
  String? _supplierSuggestion;
  List<String> _aiSimilarSuppliers = [];
  bool _aiLoading = false;
  String? _aiBadgeText;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sendToGroup = true;
    _loadSuppliers();
    if (widget.initialPhoto != null) {
      _photoFile = widget.initialPhoto;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runAiExtract(widget.initialPhoto!);
      });
    }
  }

  @override
  void dispose() {
    _supCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final list = await widget.api.getSuppliers();
      if (mounted) setState(() => _allSuppliers = list);
    } catch (_) {}
  }

  Future<void> _selectSupplier(String name) async {
    _supCtrl.text = name;
    _supplierSuggestion = null;
    _aiSimilarSuppliers = [];
    setState(() {});
    try {
      final amts = await widget.api.getSupplierAmounts(name);
      if (mounted) setState(() => _recentAmounts = amts);
    } catch (_) {}
  }

  Future<void> _selectAndSubmitSupplier(String name) async {
    _supCtrl.text = name;
    _supplierSuggestion = null;
    _aiSimilarSuppliers = [];
    setState(() {});
    await _submit();
  }

  /// Automatically calls server Gemini Vision OCR the moment a photo is picked!
  Future<void> _runAiExtract(File file) async {
    setState(() {
      _aiLoading = true;
      _aiBadgeText = null;
      _error = null;
    });
    try {
      final res = await widget.api.extractFromPhoto(file);
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        if (res.supplierName != null && res.supplierName!.trim().isNotEmpty) {
          _supCtrl.text = res.supplierName!.trim();
        }
        if (res.amount != null && res.amount! > 0) {
          _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
              res.amount!.round().toString());
        }
        _originalAmount = res.originalAmount;
        _supplierSuggestion = res.supplierSuggestion;
        _aiSimilarSuppliers = res.similarSuppliers;
        if (res.recentAmounts.isNotEmpty) {
          _recentAmounts = res.recentAmounts;
        }
        if (res.ok) {
          final roundedNote = (res.originalAmount != null &&
                  res.amount != null &&
                  res.originalAmount!.round() != res.amount!.round())
              ? " (Asli: ${formatUzs(res.originalAmount)} → ${formatUzs(res.amount)})"
              : '';
          _aiBadgeText = "✨ AI avtomatik to'ldirdi!$roundedNote";
        } else if (res.message.isNotEmpty) {
          _aiBadgeText = "⚠️ ${res.message}";
        } else {
          _aiBadgeText =
              "ℹ️ Rasmdan yozuv aniq ko'rinmadi — quyida tanlang yoki kiriting";
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _aiBadgeText = "⚠️ AI tahlil qila olmadi ($e)";
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (xfile != null && mounted) {
        final file = File(xfile.path);
        setState(() => _photoFile = file);
        await _runAiExtract(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rasm tanlashda xatolik: $e');
      }
    }
  }

  Future<void> _submit() async {
    final sup = _supCtrl.text.trim();
    final amt = parseUzsInput(_amtCtrl.text);
    if (sup.isEmpty) {
      setState(() => _error = 'Postavshik nomini tanlang yoki yozing');
      return;
    }
    if (amt == null || amt <= 0) {
      setState(() => _error = 'Summani kiriting');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.createNakladnoy(
        supplierName: sup,
        amount: amt,
        paymentMode: _paymentMode,
        note: _noteCtrl.text,
        sendToGroup: _sendToGroup,
        photoFile: _photoFile,
        originalAmount: _originalAmount,
      );
      if (mounted) {
        final grpMsg = res['group_message']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Nakladnoy saqlandi! ($grpMsg)'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _supCtrl.text.trim().toLowerCase();
    final matchingSuppliers = _allSuppliers
        .where((s) => q.isEmpty || s.toLowerCase().contains(q))
        .take(20)
        .toList();

    // Combine server AI similar suppliers + local cross-script/cursive matches (e.g. "Иттин" -> "Ummun")
    final similarCandidates = <String>[];
    if (_supplierSuggestion != null &&
        _supplierSuggestion!.trim().isNotEmpty &&
        _supplierSuggestion!.trim().toLowerCase() != q) {
      similarCandidates.add(_supplierSuggestion!.trim());
    }
    for (final s in _aiSimilarSuppliers) {
      if (s.trim().isNotEmpty &&
          s.trim().toLowerCase() != q &&
          !similarCandidates
              .any((e) => e.toLowerCase() == s.trim().toLowerCase())) {
        similarCandidates.add(s.trim());
      }
    }
    if (q.length >= 2) {
      for (final s in findLocalSimilarSuppliers(q, _allSuppliers, limit: 4)) {
        if (!similarCandidates
            .any((e) => e.toLowerCase() == s.toLowerCase())) {
          similarCandidates.add(s);
        }
      }
    }
    final topSimilar =
        similarCandidates.isNotEmpty ? similarCandidates.first : null;
    final (simFg, simBg, simBorder) =
        AppTokens.semanticSurface(context, AppTokens.cashGreen);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTokens.aiGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Yangi Nakladnoy',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. TOP AI PHOTO SCANNER BOX
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTokens.brandViolet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTokens.brandViolet.withValues(alpha: 0.28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTokens.brandViolet,
                              minimumSize: const Size(80, 46),
                            ),
                            onPressed: _aiLoading
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_rounded,
                                size: 18),
                            label: const Text('Kamera (AI)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(80, 46),
                            ),
                            onPressed: _aiLoading
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded,
                                size: 18),
                            label: const Text('Galereya (AI)'),
                          ),
                        ),
                      ],
                    ),
                    if (_photoFile != null) ...[
                      const SizedBox(height: 10),
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _photoFile!,
                              height: 125,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (_aiLoading)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.60),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.3,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      "✨ AI nakladnoyni o'qimoqda...",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  tooltip: "AI qayta o'qish",
                                  onPressed: _aiLoading
                                      ? null
                                      : () => _runAiExtract(_photoFile!),
                                  icon: const Icon(Icons.auto_awesome_rounded,
                                      size: 17),
                                ),
                                const SizedBox(width: 4),
                                IconButton.filled(
                                  onPressed: () => setState(() {
                                    _photoFile = null;
                                    _aiBadgeText = null;
                                  }),
                                  icon:
                                      const Icon(Icons.close_rounded, size: 17),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_aiBadgeText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _aiBadgeText!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: _aiBadgeText!.startsWith('✨')
                              ? AppTokens.cashGreen
                              : AppTokens.debtAmber,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Supplier field + Dropdown Picker Button + horizontal chips
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _supCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Postavshik nomi',
                        hintText: 'Tanlang yoki yozing...',
                        prefixIcon: const Icon(Icons.storefront_rounded),
                        suffixIcon: _supCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _supCtrl.clear();
                                  setState(() => _recentAmounts = []);
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 52),
                    ),
                    onPressed: () async {
                      final picked = await showSupplierPickerDialog(
                        context,
                        _allSuppliers,
                        current: _supCtrl.text,
                      );
                      if (picked != null && picked.trim().isNotEmpty) {
                        await _selectSupplier(picked.trim());
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 19),
                    label: const Text("Ro'yxat"),
                  ),
                ],
              ),
              if (similarCandidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: simBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: simBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.translate_rounded,
                              size: 16, color: simFg),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "O'xshash postavshik (Kirill / O'zbek mosligi):",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: simFg,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (topSimilar != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.cashGreen,
                            minimumSize: const Size(80, 44),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          onPressed: (_submitting || _aiLoading)
                              ? null
                              : () {
                                  if (parseUzsInput(_amtCtrl.text) != null &&
                                      parseUzsInput(_amtCtrl.text)! > 0) {
                                    _selectAndSubmitSupplier(topSimilar);
                                  } else {
                                    _selectSupplier(topSimilar);
                                  }
                                },
                          icon: const Icon(Icons.check_circle_rounded,
                              size: 18),
                          label: Text(
                            parseUzsInput(_amtCtrl.text) != null &&
                                    parseUzsInput(_amtCtrl.text)! > 0
                                ? "✅ «$topSimilar» qilib darhol tasdiqlash"
                                : "✨ «$topSimilar» ni tanlash",
                          ),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: similarCandidates
                            .map(
                              (s) => ActionChip(
                                avatar: Icon(Icons.auto_fix_high_rounded,
                                    size: 15, color: simFg),
                                label: Text(
                                  s,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                onPressed: () => _selectSupplier(s),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
              if (matchingSuppliers.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: matchingSuppliers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) {
                      final name = matchingSuppliers[i];
                      final isSel = name.toLowerCase() ==
                          _supCtrl.text.trim().toLowerCase();
                      return ActionChip(
                        backgroundColor: isSel
                            ? AppTokens.brand.withValues(alpha: 0.22)
                            : null,
                        label: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                isSel ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                        onPressed: () => _selectSupplier(name),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 3. Space-formatted Amount field (NO -10 000 / +10 000 buttons!)
              TextField(
                controller: _amtCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [UzsAmountInputFormatter()],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  fontFeatures: AppTokens.tabularNums,
                ),
                decoration: const InputDecoration(
                  labelText: "Summa (so'm)",
                  hintText: '1 554 000',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              if (_recentAmounts.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _recentAmounts
                        .map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              avatar:
                                  const Icon(Icons.history_rounded, size: 15),
                              label: Text(formatUzs(a)),
                              onPressed: () {
                                _amtCtrl.text =
                                    UzsAmountInputFormatter.formatDigits(
                                        a.round().toString());
                                setState(() {});
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 4. Payment mode selector
              const Text(
                "To'lov usuli",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              PaymentModeSelector(
                selectedMode: _paymentMode,
                onChanged: (m) => setState(() => _paymentMode = m),
              ),
              const SizedBox(height: 12),

              // 5. Note
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Izoh (ixtiyoriy)',
                  prefixIcon: Icon(Icons.notes_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),

              // 6. Guruhga yuborish toggle (Default ON, always toggleable right above Confirm)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '📤 Guruhga yuborish',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                subtitle: Text(
                  widget.groupInfo.bound
                      ? 'Telegram guruh: ${widget.groupInfo.title}'
                      : 'Guruh bog\'langan bo\'lsa avtomatik yuboriladi',
                  style: TextStyle(
                      fontSize: 12, color: textSecondaryOf(context)),
                ),
                value: _sendToGroup,
                onChanged: (v) => setState(() => _sendToGroup = v),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠️ $_error',
                  style: const TextStyle(
                    color: AppTokens.dangerRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (_submitting || _aiLoading) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                    _submitting ? 'Saqlanmoqda...' : 'Tasdiqlash va saqlash'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// NAKLADNOY DETAIL & EDIT SHEET:
// - Space-formatted amount input (UzsAmountInputFormatter)
// - NO -10 000 / +10 000 buttons (only clean direct typing + Yaxlitlash)
// - Searchable Supplier Picker Modal
// ============================================================================

class NakladnoyDetailSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final NakladnoyItem item;

  const NakladnoyDetailSheet({
    super.key,
    required this.api,
    required this.item,
  });

  @override
  State<NakladnoyDetailSheet> createState() => _NakladnoyDetailSheetState();
}

class _NakladnoyDetailSheetState extends State<NakladnoyDetailSheet> {
  late NakladnoyItem _cur;
  late TextEditingController _supCtrl;
  late TextEditingController _amtCtrl;
  final ImagePicker _picker = ImagePicker();
  List<String> _suppliers = [];
  bool _busy = false;
  bool _changed = false;
  int _photoCacheBust = 0;

  @override
  void initState() {
    super.initState();
    _cur = widget.item;
    _supCtrl = TextEditingController(text: _cur.supplierName);
    _amtCtrl = TextEditingController(
      text: UzsAmountInputFormatter.formatDigits(
          _cur.amount.round().toString()),
    );
    _loadSuppliers();
  }

  @override
  void dispose() {
    _supCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final s = await widget.api.getSuppliers();
      if (mounted) setState(() => _suppliers = s);
    } catch (_) {}
  }

  String _currentPhotoUrl() =>
      '${widget.api.photoUrlFor(_cur.id)}&v=$_photoCacheBust';

  Future<void> _openFullScreenPhoto() async {
    final url = _currentPhotoUrl();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_cur.displayNum} • ${_cur.supplierName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (xfile == null || !mounted) return;
      setState(() => _busy = true);
      final updated = await widget.api
          .uploadNakladnoyPhoto(_cur.id, File(xfile.path));
      if (mounted) {
        setState(() {
          _cur = updated;
          _photoCacheBust++;
          _changed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📷 Rasm biriktirildi!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyUpdate({
    String? supplier,
    double? amount,
    bool roundAmount = false,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.api.updateNakladnoy(
        paymentId: _cur.id,
        supplierName: supplier,
        amount: amount,
        roundAmount: roundAmount,
      );
      if (mounted) {
        setState(() {
          _cur = updated;
          _supCtrl.text = updated.supplierName;
          _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
              updated.amount.round().toString());
          _changed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchMethod(String mode) async {
    setState(() => _busy = true);
    try {
      NakladnoyItem updated;
      if (mode == 'debt') {
        updated = await widget.api.markAsDebt(_cur.id);
      } else if (_cur.isDebt) {
        updated =
            await widget.api.payDebt(paymentId: _cur.id, paymentMethod: mode);
      } else {
        updated = await widget.api
            .setPaymentMethod(paymentId: _cur.id, paymentMethod: mode);
      }
      if (mounted) {
        setState(() {
          _cur = updated;
          _changed = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = _cur.isDebt ? 'debt' : _cur.paymentMethod;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nakladnoy ${_cur.displayNum}${_cur.reportDate != null ? ' (${_cur.reportDate})' : ''}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_cur.hasPhoto) ...[
                GestureDetector(
                  onTap: _openFullScreenPhoto,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          _currentPhotoUrl(),
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Kattalashtirish',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (widget.api.canWrite) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickAndUploadPhoto(ImageSource.camera),
                        icon: const Icon(Icons.add_a_photo_rounded, size: 17),
                        label: Text(
                            _cur.hasPhoto ? 'Kameradan yangilash' : 'Kameradan rasm'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickAndUploadPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, size: 17),
                        label: const Text('Galereyadan'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Supplier field + Searchable Dropdown Modal Picker
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _supCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Postavshik',
                        prefixIcon: Icon(Icons.storefront_rounded),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          _applyUpdate(supplier: v.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showSupplierPickerDialog(
                        context,
                        _suppliers,
                        current: _supCtrl.text,
                      );
                      if (picked != null && picked.trim().isNotEmpty) {
                        await _applyUpdate(supplier: picked.trim());
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 18),
                    label: const Text("Ro'yxat"),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_supCtrl.text.trim().isNotEmpty) {
                              _applyUpdate(supplier: _supCtrl.text.trim());
                            }
                          },
                    child: const Text('Saqlash'),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Space-formatted Amount field + Yaxlitlash + Yangilash
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [UzsAmountInputFormatter()],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontFeatures: AppTokens.tabularNums,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Summa (so'm)",
                        prefixIcon: Icon(Icons.payments_outlined),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final parsed = parseUzsInput(v);
                        if (parsed != null && parsed > 0) {
                          _applyUpdate(amount: parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _applyUpdate(roundAmount: true),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                    label: const Text('Yaxlit'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final parsed = parseUzsInput(_amtCtrl.text);
                            if (parsed != null && parsed > 0) {
                              _applyUpdate(amount: parsed);
                            }
                          },
                    child: const Text('Saqlash'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                "To'lov turi va holati:",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              PaymentModeSelector(
                selectedMode: activeMode,
                onChanged: (m) {
                  if (!_busy && m != activeMode) {
                    _switchMethod(m);
                  }
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                final msg = await widget.api
                                    .sendNakladnoyToGroup(_cur.id);
                                _changed = true;
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('📤 $msg')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: Text(_cur.inGroup
                          ? 'Guruhda yangilash'
                          : 'Guruhga yuborish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.dangerRed),
                    onPressed: _busy
                        ? null
                        : () async {
                            await widget.api.deleteNakladnoy(_cur.id);
                            if (context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text("O'chirish"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STAGE 1: O'TGAN SMENALAR TARIXI, SMENA ICHINI KO'RISH VA QAYTA OCHISH
// ============================================================================

class HistorySessionsSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final Future<void> Function(NakladnoyItem) onOpenNakladnoyDetail;

  const HistorySessionsSheet({
    super.key,
    required this.api,
    required this.onOpenNakladnoyDetail,
  });

  @override
  State<HistorySessionsSheet> createState() => _HistorySessionsSheetState();
}

class _HistorySessionsSheetState extends State<HistorySessionsSheet> {
  List<HistorySessionItem> _sessions = [];
  StatusSummary? _selectedDetail;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api.getHistorySessions(limit: 30);
      if (mounted) {
        setState(() {
          _sessions = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSessionDetail(int sessionId) async {
    setState(() => _busy = true);
    try {
      final detail = await widget.api.getHistorySessionDetail(sessionId);
      if (mounted) setState(() => _selectedDetail = detail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopenSession(int sessionId) async {
    setState(() => _busy = true);
    try {
      await widget.api.reopenSession(sessionId);
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("🔄 Smena qayta ochildi va faol holatga o'tdi!")),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSessionExcel(StatusSummary s) async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.api.downloadExcelBytes(
        '/export/session',
        query: {'session_id': '${s.sessionId}'},
      );
      final dir = await getTemporaryDirectory();
      final filename = 'Hisobot_${s.reportDate}_smena${s.sessionId}.xlsx';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_selectedDetail != null)
                    IconButton(
                      onPressed: () => setState(() => _selectedDetail = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: Text(
                      _selectedDetail != null
                          ? "Smena #${_selectedDetail!.sessionId} (${_selectedDetail!.reportDate})"
                          : "📜 O'tgan smenalar tarixi",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else if (_selectedDetail != null)
                Expanded(child: _buildDetailView(_selectedDetail!))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final s = _sessions[i];
                      final isOpen = s.status == 'open';
                      return Card(
                        child: ListTile(
                          onTap: _busy ? null : () => _openSessionDetail(s.id),
                          leading: CircleAvatar(
                            backgroundColor: isOpen
                                ? AppTokens.cashGreen.withValues(alpha: 0.16)
                                : AppTokens.brand.withValues(alpha: 0.14),
                            child: Icon(
                              isOpen
                                  ? Icons.lock_open_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: isOpen
                                  ? AppTokens.cashGreen
                                  : AppTokens.brand,
                            ),
                          ),
                          title: Text(
                            '${s.reportDate}  •  Smena #${s.id}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            "Kutilgan naqd: ${formatUzs(s.expectedCash, withCurrency: true)}"
                            "${s.actualCountedCash != null ? '\nSanalgan: ${formatUzs(s.actualCountedCash, withCurrency: true)} (Farq: ${formatUzs(s.difference)})' : ''}",
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView(StatusSummary d) {
    final isClosed = d.sessionStatus == 'closed';
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Holati: ${isClosed ? '🔒 Yopilgan' : '🟢 Ochiq smena'}",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  "Boshlang'ich qoldiq: ${formatUzs(d.openingBalance, withCurrency: true)}\n"
                  "Jami kirim: ${formatUzs(d.mainCashIn, withCurrency: true)}\n"
                  "Naqd nakladnoy: ${formatUzs(d.totalNakladnoySpent, withCurrency: true)}\n"
                  "Karta / O'tkazma: ${formatUzs(d.totalCardSpent + d.totalTransferSpent, withCurrency: true)}\n"
                  "Qo'lda qolishi kerak: ${formatUzs(d.expectedCash, withCurrency: true)}",
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _exportSessionExcel(d),
                        icon: const Icon(Icons.table_view_rounded, size: 17),
                        label: const Text('Excel yuklash'),
                      ),
                    ),
                    if (isClosed && widget.api.canWrite) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _busy ? null : () => _reopenSession(d.sessionId),
                          icon: const Icon(Icons.lock_open_rounded, size: 17),
                          label: const Text('Qayta ochish'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Nakladnoylar (${d.nakladnoys.length} ta):',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...d.nakladnoys.map(
          (n) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NakladnoyListCard(
              item: n,
              onTap: () async {
                await widget.onOpenNakladnoyDetail(n);
                await _openSessionDetail(d.sessionId);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// STAGE 1B: GLOBAL SEARCH ACROSS ALL PAST DAYS (/history/search)
// ============================================================================

class GlobalHistorySearchSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final Future<void> Function(NakladnoyItem) onOpenNakladnoyDetail;

  const GlobalHistorySearchSheet({
    super.key,
    required this.api,
    required this.onOpenNakladnoyDetail,
  });

  @override
  State<GlobalHistorySearchSheet> createState() =>
      _GlobalHistorySearchSheetState();
}

class _GlobalHistorySearchSheetState extends State<GlobalHistorySearchSheet> {
  final TextEditingController _qCtrl = TextEditingController();
  List<NakladnoyItem> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.searchHistoryNakladnoys(q);
      if (mounted) {
        setState(() {
          _results = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "🌍 Barcha kunlardan qidirish",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qCtrl,
                      autofocus: true,
                      onSubmitted: _runSearch,
                      decoration: const InputDecoration(
                        hintText: 'Postavshik, izoh yoki sana (2026-11)...',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _loading ? null : () => _runSearch(_qCtrl.text),
                    child: const Text('Qidirish'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else if (_results.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      "Postavshik nomi yoki sanani yozib «Qidirish» tugmasini bosing.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondaryOf(context)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final item = _results[i];
                      return NakladnoyListCard(
                        item: item,
                        onTap: () async {
                          await widget.onOpenNakladnoyDetail(item);
                          await _runSearch(_qCtrl.text);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STAGE 2: ILOVA ICHIDA JONLI SVERKA VA 7 / 30 KUNLIK STATISTIKA
// ============================================================================

class LiveSverkaAndStatsSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final void Function(String, {bool isError}) showSnack;

  const LiveSverkaAndStatsSheet({
    super.key,
    required this.api,
    required this.showSnack,
  });

  @override
  State<LiveSverkaAndStatsSheet> createState() =>
      _LiveSverkaAndStatsSheetState();
}

class _LiveSverkaAndStatsSheetState extends State<LiveSverkaAndStatsSheet> {
  String _mode = 'sverka'; // sverka | 7d | 30d
  Map<String, dynamic>? _sverkaData;
  Map<String, dynamic>? _periodData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_mode == 'sverka') {
        final d = await widget.api.getLiveSverka();
        if (mounted) setState(() => _sverkaData = d);
      } else {
        final days = _mode == '7d' ? 7 : 30;
        final d = await widget.api.getPeriodStats(days: days);
        if (mounted) setState(() => _periodData = d);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "📊 Jonli Sverka va Statistika",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _modeChip('sverka', '🏢 Oylik Sverka'),
                  const SizedBox(width: 6),
                  _modeChip('7d', '📅 7 kunlik'),
                  const SizedBox(width: 6),
                  _modeChip('30d', '🗓 30 kunlik'),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else if (_mode == 'sverka' && _sverkaData != null)
                Expanded(child: _buildSverkaView(_sverkaData!))
              else if (_periodData != null)
                Expanded(child: _buildPeriodView(_periodData!)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeChip(String key, String label) {
    final sel = _mode == key;
    return Expanded(
      child: sel
          ? FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(label, style: const TextStyle(fontSize: 12.5)),
            )
          : OutlinedButton(
              onPressed: () {
                setState(() => _mode = key);
                _loadData();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(label, style: const TextStyle(fontSize: 12.5)),
            ),
    );
  }

  Widget _buildSverkaView(Map<String, dynamic> d) {
    final sups = ((d['suppliers'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final grandTotal = ((d['grand_total'] as num?) ?? 0).toDouble();
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Oy: ${d['month']} (${sups.length} ta postavshik)",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  formatUzs(grandTotal, withCurrency: true),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppTokens.brand,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...sups.map((s) {
          final cash = ((s['cash_total'] as num?) ?? 0).toDouble();
          final card = ((s['card_total'] as num?) ?? 0).toDouble();
          final xfer = ((s['transfer_total'] as num?) ?? 0).toDouble();
          final tot = ((s['total'] as num?) ?? 0).toDouble();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${s['supplier']} (${s['count']} ta)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14.5),
                        ),
                      ),
                      Text(
                        formatUzs(tot, withCurrency: true),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppTokens.brand,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (cash > 0)
                        Text('💵 Naqd: ${formatUzs(cash)}',
                            style: const TextStyle(fontSize: 12.5)),
                      if (card > 0)
                        Text('💳 Karta: ${formatUzs(card)}',
                            style: const TextStyle(fontSize: 12.5)),
                      if (xfer > 0)
                        Text("🏦 O'tkazma: ${formatUzs(xfer)}",
                            style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPeriodView(Map<String, dynamic> d) {
    final topSups = ((d['top_suppliers'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Davr: ${d['date_from']} — ${d['date_to']} (${d['active_days']} faol kun)",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  "Jami xarajat: ${formatUzs(d['total_spent'] as num?, withCurrency: true)}",
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.brand,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "💵 Naqd: ${formatUzs(d['cash_spent'] as num?, withCurrency: true)} (${d['cash_count']} ta)\n"
                  "💳 Karta: ${formatUzs(d['card_spent'] as num?, withCurrency: true)} (${d['card_count']} ta)\n"
                  "🏦 O'tkazma: ${formatUzs(d['transfer_spent'] as num?, withCurrency: true)} (${d['transfer_count']} ta)\n"
                  "📈 Kunlik o'rtacha: ${formatUzs(d['avg_daily_spend'] as num?, withCurrency: true)}",
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
                if (d['busiest_day_date'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    "🔥 Eng ko'p to'lov kuni: ${d['busiest_day_date']} (${formatUzs(d['busiest_day_total'] as num?, withCurrency: true)})",
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Top postavshiklar:',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 6),
        ...topSups.map(
          (s) => Card(
            child: ListTile(
              dense: true,
              title: Text(
                '${s['supplier']} (${s['count']} ta)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Text(
                '${formatUzs(s['total'] as num?, withCurrency: true)} (${((s['percent'] as num?) ?? 0).toStringAsFixed(0)}%)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// STAGE 4A: NASIYA DAFTARI (/nasiya) VIEW INSIDE QARZLAR TAB
// ============================================================================

class NasiyaLedgerView extends StatefulWidget {
  final HisobchiApiClient api;
  final void Function(String, {bool isError}) showSnack;

  const NasiyaLedgerView({
    super.key,
    required this.api,
    required this.showSnack,
  });

  @override
  State<NasiyaLedgerView> createState() => _NasiyaLedgerViewState();
}

class _NasiyaLedgerViewState extends State<NasiyaLedgerView> {
  Map<String, dynamic>? _data;
  List<String> _suppliers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        widget.api.getNasiya(),
        widget.api.getSuppliers(),
      ]);
      if (mounted) {
        setState(() {
          _data = res[0] as Map<String, dynamic>;
          _suppliers = res[1] as List<String>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      widget.showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openAddEntryDialog(String entryType, {String? presetSup}) async {
    final supCtrl = TextEditingController(text: presetSup ?? '');
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final isDebt = entryType == 'debt';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, sheetBottomPadding(ctx)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isDebt
                    ? '➕ Qarzga mol olindi (Nasiya)'
                    : '➖ Qarz uzildi (To\'lov)',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: supCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Postavshik nomi',
                        prefixIcon: Icon(Icons.storefront_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showSupplierPickerDialog(
                        ctx,
                        _suppliers,
                        current: supCtrl.text,
                      );
                      if (picked != null) supCtrl.text = picked;
                    },
                    child: const Text("Ro'yxat"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [UzsAmountInputFormatter()],
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900),
                decoration: const InputDecoration(
                  labelText: "Summa (so'm)",
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Izoh (ixtiyoriy)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Saqlash'),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      final sup = supCtrl.text.trim();
      final amt = parseUzsInput(amtCtrl.text);
      if (sup.isEmpty || amt == null || amt <= 0) {
        widget.showSnack('Postavshik va summani kiriting', isError: true);
        return;
      }
      try {
        await widget.api.addNasiya(
          supplierName: sup,
          entryType: entryType,
          amount: amt,
          note: noteCtrl.text,
        );
        widget.showSnack('✅ Nasiya daftariga yozildi!');
        await _load();
      } catch (e) {
        widget.showSnack(e.toString(), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final balances = ((_data?['balances'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final entries = ((_data?['entries'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final totalBalance = ((_data?['total_balance'] as num?) ?? 0).toDouble();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Jami Nasiya Qoldig'i (${balances.length} ta postavshik):",
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatUzs(totalBalance, withCurrency: true),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.debtAmber,
                    ),
                  ),
                  if (widget.api.canWrite) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _openAddEntryDialog('debt'),
                            icon: const Icon(Icons.add_circle_outline_rounded,
                                size: 18),
                            label: const Text('Qarz yozish'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openAddEntryDialog('payment'),
                            icon: const Icon(Icons.task_alt_rounded, size: 18),
                            label: const Text("Qarz to'lash"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (balances.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Postavshiklar kesimida qoldiq:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 6),
            ...balances.map(
              (b) => Card(
                child: ListTile(
                  title: Text(
                    b['supplier'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    "Olingan: ${formatUzs(b['debt'] as num?)} • To'langan: ${formatUzs(b['paid'] as num?)}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    formatUzs(b['balance'] as num?, withCurrency: true),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppTokens.debtAmber,
                    ),
                  ),
                  onTap: widget.api.canWrite
                      ? () => _openAddEntryDialog('payment',
                          presetSup: b['supplier'].toString())
                      : null,
                ),
              ),
            ),
          ],
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Oxirgi yozuvlar:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 6),
            ...entries.map((e) {
              final isDebt = e['entry_type'] == 'debt';
              return Card(
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    isDebt
                        ? Icons.arrow_upward_rounded
                        : Icons.check_circle_rounded,
                    color: isDebt ? AppTokens.debtAmber : AppTokens.cashGreen,
                  ),
                  title: Text(
                    '${e['supplier_name']} • ${formatUzs(e['amount'] as num?, withCurrency: true)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${e['created_at']}${e['note'].toString().isNotEmpty ? ' • ${e['note']}' : ''}',
                  ),
                  trailing: widget.api.canWrite
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 19, color: AppTokens.dangerRed),
                          onPressed: () async {
                            await widget.api
                                .deleteNasiya((e['id'] as num).toInt());
                            await _load();
                          },
                        )
                      : null,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// STAGE 4B: PRIXOD (ITOG 👑) HISOBOTLARI SHEET
// ============================================================================

class PrixodItogSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final void Function(String, {bool isError}) showSnack;

  const PrixodItogSheet({
    super.key,
    required this.api,
    required this.showSnack,
  });

  @override
  State<PrixodItogSheet> createState() => _PrixodItogSheetState();
}

class _PrixodItogSheetState extends State<PrixodItogSheet> {
  final TextEditingController _txtCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _publishToGroup = false;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _txtCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.getPrixodList();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      widget.showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _createFromText() async {
    if (_txtCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final res = await widget.api.createPrixodFromText(
        text: _txtCtrl.text,
        publishToGroup: _publishToGroup,
      );
      _txtCtrl.clear();
      widget.showSnack(res['message']?.toString() ?? 'ITOG 👑 yaratildi!');
      await _load();
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "👑 Prixod (ITOG) Hisobotlari",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (widget.api.canWrite) ...[
                TextField(
                  controller: _txtCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Matndan yangi ITOG 👑 yaratish',
                    hintText: 'Masalan:\nNafis 500 000\nCoca Cola 1 200 000',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Prixod guruhiga ham yuborish',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  value: _publishToGroup,
                  onChanged: (v) => setState(() => _publishToGroup = v),
                ),
                FilledButton.icon(
                  onPressed: _submitting ? null : _createFromText,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                      _submitting ? 'Yaratilmoqda...' : 'ITOG 👑 hisobot tuzish'),
                ),
                const Divider(height: 20),
              ],
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text("Hozircha Prixod hisobotlari yo'q"),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final r = _items[i];
                      final txt = (r['formatted_text'] ?? '').toString();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "👑 ${r['report_date']} (#${r['id']})",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    formatUzs(r['total_cost'] as num?,
                                        withCurrency: true),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppTokens.brand,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  txt,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(
                                            ClipboardData(text: txt));
                                        widget.showSnack(
                                            '📋 ITOG matni nusxalandi!');
                                      },
                                      icon: const Icon(Icons.copy_rounded,
                                          size: 16),
                                      label: const Text('Nusxalash'),
                                    ),
                                  ),
                                  if (widget.api.canWrite) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: () async {
                                          try {
                                            final pub = await widget.api
                                                .publishPrixod(
                                                    (r['id'] as num).toInt());
                                            widget.showSnack(
                                              pub['message']?.toString() ??
                                                  'Guruhga yuborildi!',
                                            );
                                            await _load();
                                          } catch (e) {
                                            widget.showSnack(e.toString(),
                                                isError: true);
                                          }
                                        },
                                        icon: const Icon(Icons.send_rounded,
                                            size: 16),
                                        label: const Text('Guruhga'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
