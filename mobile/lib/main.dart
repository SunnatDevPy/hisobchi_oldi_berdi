import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'custom_camera.dart';
import 'offline_sync.dart';
import 'platform_bridge.dart';
import 'theme.dart';
import 'version.dart';
import 'widgets.dart';
import 'widgets_3d.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  runApp(const HisobchiApp());
}

/// Computes safe bottom padding inside modal bottom sheets for soft keyboard clearance.
/// Callers already wrap sheet content in `SafeArea(top: false, maintainBottomViewPadding: true)`.
double sheetBottomPadding(BuildContext context, {double extra = 14}) {
  return MediaQuery.viewInsetsOf(context).bottom + extra;
}

/// Computes the maximum modal bottom-sheet height that stays above the device's
/// status bar, bottom system bar (3-button or gesture pill), soft keyboard,
/// and Material 3 drag handle across every phone form factor.
double sheetMaxHeight(BuildContext context, {double fraction = 0.88}) {
  final mq = MediaQuery.of(context);
  final available = mq.size.height -
      mq.viewPadding.top -
      mq.viewPadding.bottom -
      mq.viewInsets.bottom -
      kMinInteractiveDimension;
  if (available <= 120.0) {
    return available > 0 ? available : 120.0;
  }
  final target = mq.size.height * fraction;
  final capped = target < available ? target : available;
  final minBound = available < 240.0 ? available : 240.0;
  return capped < minBound ? minBound : capped;
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
          maintainBottomViewPadding: true,
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              bottom: sheetBottomPadding(ctx),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: sheetMaxHeight(ctx, fraction: 0.72),
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

class AppLockStorage {
  static const _kPin = 'hisobchi_pin_code';
  static const _kPinEnabled = 'hisobchi_pin_enabled';
  static const _kBioEnabled = 'hisobchi_bio_enabled';

  static Future<({bool enabled, String? pin, bool bioEnabled})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPinEnabled) == true;
    final pin = prefs.getString(_kPin);
    final bio = prefs.getBool(_kBioEnabled) == true;
    if (!enabled || pin == null || pin.length != 4) {
      return (enabled: false, pin: null, bioEnabled: false);
    }
    return (enabled: true, pin: pin, bioEnabled: bio);
  }

  static Future<void> savePin(String pin, {required bool biometricEnabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPin, pin);
    await prefs.setBool(_kPinEnabled, true);
    await prefs.setBool(_kBioEnabled, biometricEnabled);
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBioEnabled, enabled);
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPin);
    await prefs.setBool(_kPinEnabled, false);
    await prefs.setBool(_kBioEnabled, false);
  }
}

class HisobchiApp extends StatefulWidget {
  final HisobchiApiClient? apiOverride;

  const HisobchiApp({super.key, this.apiOverride});

  @override
  State<HisobchiApp> createState() => _HisobchiAppState();
}

class _HisobchiAppState extends State<HisobchiApp> with WidgetsBindingObserver {
  static const Duration _autoLockTimeout = Duration(minutes: 3);
  late final HisobchiApiClient _api;
  ThemeMode _themeMode = ThemeMode.system;
  bool _initializing = true;
  bool _pinLocked = false;
  bool _needsPinSetup = false;
  String? _savedPin;
  bool _bioEnabled = false;
  String? _webAuthError;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.apiOverride ??
        HisobchiApiClient(baseUrl: resolveDefaultApiBaseUrl());
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final bgAt = _backgroundedAt;
      _backgroundedAt = null;
      if (bgAt != null &&
          _api.isAuthenticated &&
          _savedPin != null &&
          !_pinLocked &&
          DateTime.now().difference(bgAt) >= _autoLockTimeout) {
        setState(() => _pinLocked = true);
      }
    }
  }

  Future<void> _bootstrap() async {
    if (widget.apiOverride == null) {
      if (kIsWeb) {
        // index.html #hisobchi-splash already played while JS loaded — do not
        // add a second artificial splash wait on Web.
        initTelegramWebApp();
        final scheme = getTelegramColorScheme();
        if (scheme == 'dark') {
          _themeMode = ThemeMode.dark;
        } else if (scheme == 'light') {
          _themeMode = ThemeMode.light;
        }
        syncTelegramChromeColors(isDark: _themeMode == ThemeMode.dark);

        final initData = getTelegramWebAppInitData();
        if (initData == null || initData.isEmpty) {
          _webAuthError =
              "Mini App faqat Telegram bot ichidan (@hisobchi_my_bot) ochiladi.";
        } else {
          try {
            await _api.loginWithTelegramWebApp(initData: initData);
            _webAuthError = null;
            await _api.prewarmHomeData();
          } catch (e) {
            _webAuthError = e.toString();
          }
        }
      } else {
        // Single 3.0s cosmic 3D splash on Android cold launch while session +
        // home data load in parallel so the second screen opens immediately.
        final minSplash =
            Future<void>.delayed(const Duration(milliseconds: 3000));
        Future<void> loadAndroidState() async {
          await _api.loadSavedSession();
          final lock = await AppLockStorage.load();
          _savedPin = lock.pin;
          _bioEnabled = lock.bioEnabled;
          if (_api.isAuthenticated && lock.enabled && lock.pin != null) {
            _pinLocked = true;
          }
          if (_api.isAuthenticated) {
            await _api.prewarmHomeData();
          }
        }

        await Future.wait([loadAndroidState(), minSplash]);
      }
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _playTransitionAndEnter({bool checkPinSetup = false}) async {
    if (!mounted) return;
    // Open immediately on the second step (no second loading screen!).
    setState(() {
      _pinLocked = false;
      if (checkPinSetup &&
          !kIsWeb &&
          widget.apiOverride == null &&
          _savedPin == null) {
        _needsPinSetup = true;
      }
    });
  }

  Future<void> _retryWebBootstrap() async {
    setState(() {
      _initializing = true;
      _webAuthError = null;
    });
    await _bootstrap();
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
    syncTelegramChromeColors(isDark: _themeMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (_initializing) {
      home = const Scaffold(
        key: ValueKey('app_init'),
        body: HisobchiAnimatedLoadingScreen(
          subtitle: 'Ilova tayyorlanmoqda...',
        ),
      );
    } else if (_api.isAuthenticated && _pinLocked && _savedPin != null) {
      home = PinLockScreen(
        key: const ValueKey('pin_unlock'),
        mode: PinScreenMode.unlock,
        expectedPin: _savedPin,
        biometricEnabled: _bioEnabled,
        onCanUseBiometric: canUseBiometric,
        onAuthenticateBiometric: () => authenticateBiometric(
          subtitle: "Hisobchi ilovasini ochish uchun barmoq izini bosing",
        ),
        onCompleted: (pin, bio) async {
          await _playTransitionAndEnter();
        },
        onLogout: () async {
          await _api.logout();
          await AppLockStorage.clearPin();
          if (!mounted) return;
          setState(() {
            _savedPin = null;
            _bioEnabled = false;
            _pinLocked = false;
            _needsPinSetup = false;
          });
        },
      );
    } else if (_api.isAuthenticated && _needsPinSetup) {
      home = PinLockScreen(
        key: const ValueKey('pin_setup'),
        mode: PinScreenMode.setup,
        onCanUseBiometric: canUseBiometric,
        onCompleted: (pin, enableBio) async {
          await AppLockStorage.savePin(pin, biometricEnabled: enableBio);
          if (!mounted) return;
          setState(() {
            _savedPin = pin;
            _bioEnabled = enableBio;
            _needsPinSetup = false;
          });
          await _playTransitionAndEnter();
        },
        onSkip: () {
          setState(() => _needsPinSetup = false);
        },
      );
    } else if (_api.isAuthenticated) {
      home = MainWorkspaceScreen(
        key: const ValueKey('main_workspace'),
        api: _api,
        onToggleTheme: _toggleTheme,
        onLoggedOut: () => setState(() {
          _pinLocked = false;
          _needsPinSetup = false;
        }),
        onLockChanged: () {
          AppLockStorage.load().then((lock) {
            if (!mounted) return;
            setState(() {
              _savedPin = lock.pin;
              _bioEnabled = lock.bioEnabled;
              if (!lock.enabled || lock.pin == null) {
                _pinLocked = false;
              }
            });
          });
        },
      );
    } else if (kIsWeb) {
      home = _WebAppLockedScreen(
        key: const ValueKey('webapp_locked'),
        message: _webAuthError ??
            "🔒 Mini App hozircha faqat asosiy admin uchun ochiq.",
        onRetry: _retryWebBootstrap,
      );
    } else {
      home = LoginScreen(
        key: const ValueKey('login_screen'),
        api: _api,
        onLoggedIn: () => _playTransitionAndEnter(checkPinSetup: true),
      );
    }

    final isDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp(
        title: 'Hisobchi',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: _themeMode,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 480),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: home,
        ),
      ),
    );
  }
}

class _WebAppLockedScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _WebAppLockedScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: AppTokens.heroGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_person_rounded,
                                color: Colors.white, size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Hisobchi Mini App',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Qayta urinish'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _deviceCtrl =
      TextEditingController(text: 'Android APK');
  bool _loading = false;
  bool _openingTelegram = false;
  bool _waitingFromTelegram = false;
  String _botUsername = 'hisobchi_my_bot';
  String? _error;
  String? _infoBanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBotUsername();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingFromTelegram) {
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (mounted && _waitingFromTelegram) {
          _tryAutoFillFromClipboard(silent: true);
        }
      });
    }
  }

  Future<void> _loadBotUsername() async {
    final uname = await widget.api.fetchBotUsername(fallback: _botUsername);
    if (!mounted) return;
    if (uname.isNotEmpty && uname != _botUsername) {
      setState(() => _botUsername = uname);
    }
  }

  Future<void> _openTelegramForCode() async {
    if (_openingTelegram || _loading) return;
    setState(() {
      _openingTelegram = true;
      _error = null;
    });
    try {
      final uname = _botUsername.trim().replaceAll('@', '');
      final tgUri = 'tg://resolve?domain=$uname&start=apk_login';
      final httpsUri = 'https://t.me/$uname?start=apk_login';
      var opened = await openExternalTelegramUrl(tgUri);
      if (!opened) {
        opened = await openExternalTelegramUrl(httpsUri);
      }
      if (!mounted) return;
      if (opened) {
        setState(() {
          _waitingFromTelegram = true;
          _infoBanner =
              "Telegram (@$uname) ochildi. Botda START tugmasini bosing — 8 xonali kod chiqadi, nusxalab ilovaga qayting.";
        });
      } else {
        setState(() {
          _error =
              "Telegram ilovasini ochib bo'lmadi. Telegramda @$uname ga kirib /apk yuboring.";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _openingTelegram = false);
      }
    }
  }

  Future<void> _tryAutoFillFromClipboard({bool silent = false}) async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = (clip?.text ?? '').trim();
      String? extracted;
      final match = RegExp(r'(?<!\d)(\d{4}[-\s]?\d{4})(?!\d)').firstMatch(raw);
      if (match != null) {
        extracted = match.group(1)!.replaceAll(RegExp(r'\D+'), '');
      } else {
        final digitsOnly = raw.replaceAll(RegExp(r'\D+'), '');
        if (digitsOnly.length == 8) {
          extracted = digitsOnly;
        }
      }
      if (!mounted) return;
      if (extracted != null && extracted.length == 8) {
        setState(() {
          _codeCtrl.text = extracted!;
          _codeCtrl.selection =
              TextSelection.collapsed(offset: extracted.length);
          _error = null;
          _waitingFromTelegram = false;
          _infoBanner =
              "✅ 8 xonali kod joylandi! Endi 'Ilovaga kirish' tugmasini bosing.";
        });
      } else if (!silent) {
        setState(() {
          _error =
              "Buferda 8 xonali kod topilmadi. Telegram botdagi kod ustiga bosib nusxalang.";
        });
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() {
          _error = "Buferdan o'qib bo'lmadi. Kodni qo'lda kiriting.";
        });
      }
    }
  }

  Future<void> _submitLogin() async {
    final code = _codeCtrl.text.replaceAll(RegExp(r'\D+'), '');
    if (code.isEmpty) {
      await _openTelegramForCode();
      return;
    }
    if (code.length != 8) {
      setState(() => _error =
          "Telegram botdan olingan 8 xonali kodni kiriting yoki 'Telegramdan parol (kod) olish' tugmasini bosing.");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.login(
        serverUrl: widget.api.baseUrl,
        code: code,
        deviceName: _deviceCtrl.text,
      );
      await widget.api.prewarmHomeData();
      if (mounted) widget.onLoggedIn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final (errFg, errBg, errBorder) =
        AppTokens.semanticSurface(context, AppTokens.dangerRed);
    final (infoFg, infoBg, infoBorder) =
        AppTokens.semanticSurface(context, AppTokens.cardBlue);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.78),
                    radius: 0.95,
                    colors: [
                      AppTokens.brandViolet
                          .withValues(alpha: isDark ? 0.30 : 0.14),
                      const Color(0xFFEC4899)
                          .withValues(alpha: isDark ? 0.12 : 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          const Interactive3DFintechCube(
                            size: 158,
                            continuousSpin: false,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hisobchi Mobil',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kassa, AI nakladnoy skaneri va Telegram guruhlar bilan jonli sinxron tizim.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '8 xonali kirish kodi (/apk)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _codeCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                                decoration: InputDecoration(
                                  hintText: '1234-5678',
                                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: 'Buferdan kodni joylash',
                                    onPressed: _loading
                                        ? null
                                        : () => _tryAutoFillFromClipboard(),
                                    icon: const Icon(Icons.content_paste_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TactileScaleTap(
                                pressedScale: 0.97,
                                enabled: !_openingTelegram && !_loading,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 46),
                                    backgroundColor: const Color(0xFF229ED9),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: (_openingTelegram || _loading)
                                      ? null
                                      : _openTelegramForCode,
                                  icon: _openingTelegram
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.telegram),
                                  label: const Text('Telegramdan parol (kod) olish'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Qurilma nomi',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _deviceCtrl,
                                decoration: const InputDecoration(
                                  hintText: 'Masalan: Kassir Samsung',
                                  prefixIcon: Icon(Icons.phone_android_rounded),
                                ),
                              ),
                              if (_infoBanner != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: infoBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: infoBorder),
                                  ),
                                  child: Text(
                                    _infoBanner!,
                                    style: TextStyle(
                                      color: infoFg,
                                      fontSize: 12.8,
                                      height: 1.35,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
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
                              TactileScaleTap(
                                pressedScale: 0.96,
                                enabled: !_loading,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 50),
                                    backgroundColor: AppTokens.brandViolet,
                                  ),
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
                                    _loading ? 'Ulanmoqda...' : 'Ilovaga kirish',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Qanday ulanadi?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _stepRow('1',
                                  "Yuqoridagi 'Telegramdan parol (kod) olish' tugmasini bosing — Telegram (@$_botUsername) ochiladi va START bosganda 8 xonali kod chiqadi."),
                              const SizedBox(height: 6),
                              _stepRow('2',
                                  'Bot bergan kod ustiga bosib nusxalang va ilovaga qayting — kod avtomatik joylanadi.'),
                              const SizedBox(height: 6),
                              _stepRow('3',
                                  'Kirgach tezkor 4 xonali PIN kod va otpechatkani sozlashingiz mumkin.'),
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
        ],
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
  final VoidCallback? onLockChanged;

  const MainWorkspaceScreen({
    super.key,
    required this.api,
    required this.onToggleTheme,
    required this.onLoggedOut,
    this.onLockChanged,
  });

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  late final PageController _pageController;
  int? _programmaticTargetTab;
  StatusSummary? _summary;
  List<NakladnoyItem> _allDebts = [];
  bool _loading = true;
  String? _error;

  // Nakladnoylar tab filter & sort dropdown states
  String _filterMode = 'all'; // all | cash | card | transfer | debt
  String _sortMode = 'newest'; // newest | amount_desc | supplier_az
  String _searchQuery = '';

  // Ta'minotchilar / Qarzlar tab filter & sub-tab ('directory' | 'nakladnoy' | 'nasiya')
  String _debtSupplierFilter = 'all';
  String _debtSubTab = 'directory';

  // Dashboard Date / Session switcher & Trend Line Chart state
  List<HistorySessionItem> _historySessions = [];
  StatusSummary? _viewedSessionSummary;
  bool _switchingSession = false;
  List<Map<String, dynamic>> _dailySeries = [];
  String _seriesGranularity = 'daily';
  String _activePeriodKey = '7d';
  String _periodLabel = '7 kunlik';
  String? _customDateFrom;
  String? _customDateTo;

  ApkVersionInfo? _remoteVersion;
  bool _updatingApk = false;
  double _refreshTurns = 0.0;
  int _dataAnimSeed = 0;
  Timer? _outboxTimer;
  Timer? _liveSyncTimer;
  int _outboxCount = 0;
  bool _syncingOutbox = false;
  bool _isOfflineMode = false;
  bool _isForeground = true;
  bool _pollingSync = false;
  bool _refreshInFlight = false;
  String? _lastSyncRev;
  String? _initialWebVersion;
  bool _webUpdateAvailable = false;
  double? _voiceCountedCashPreset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _tabIndex);
    _refreshOutboxBadge();
    _outboxTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _trySyncOutbox(silent: true),
    );
    _liveSyncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollSyncVersion(),
    );
    final prewarmed = widget.api.consumePrewarmedData();
    if (prewarmed.status != null) {
      _summary = prewarmed.status;
      _allDebts = prewarmed.debts ?? [];
      _loading = false;
      _dataAnimSeed = 1;
      _refreshAll(silent: true);
    } else {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _outboxTimer?.cancel();
    _liveSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _trySyncOutbox(silent: true);
      _pollSyncVersion(force: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
    }
  }

  Future<void> _pollSyncVersion({bool force = false}) async {
    if (!mounted || (!_isForeground && !force) || _pollingSync || _refreshInFlight) {
      return;
    }
    _pollingSync = true;
    try {
      final info = await widget.api.getSyncVersion();
      if (!mounted) return;

      final recoveredFromOffline = _isOfflineMode;
      var stateChanged = false;

      if (!kIsWeb &&
          info.apkBuild > kAppBuildNumber &&
          (_remoteVersion == null || _remoteVersion!.build < info.apkBuild)) {
        _remoteVersion = ApkVersionInfo(
          version: info.apkVersion,
          build: info.apkBuild,
          full: '${info.apkVersion}+${info.apkBuild}',
          builtAt: '',
          sizeBytes: 0,
          available: true,
          downloadUrl: widget.api.apkDownloadUri.toString(),
        );
        stateChanged = true;
      }

      if (kIsWeb && info.webVersion.isNotEmpty) {
        if (_initialWebVersion == null) {
          _initialWebVersion = info.webVersion;
        } else if (_initialWebVersion != info.webVersion &&
            !_webUpdateAvailable) {
          _webUpdateAvailable = true;
          stateChanged = true;
        }
      }

      final revChanged = shouldTriggerRemoteSync(_lastSyncRev, info.rev);
      if (_lastSyncRev == null && info.rev.isNotEmpty) {
        _lastSyncRev = info.rev;
      }

      if (stateChanged && mounted) {
        setState(() {});
      }

      if (recoveredFromOffline) {
        await _trySyncOutbox(silent: true);
        await _refreshAll(silent: true, fromRemoteSync: true);
        _lastSyncRev = info.rev;
        SyncBus.notifyRemoteChange();
      } else if (revChanged) {
        _lastSyncRev = info.rev;
        if (mounted) {
          setState(() => _refreshTurns += 1.0);
        }
        await _refreshAll(silent: true, fromRemoteSync: true);
        SyncBus.notifyRemoteChange();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 && mounted) {
        await widget.api.clearSession();
        if (mounted) widget.onLoggedOut();
      }
    } catch (_) {
      if (!_isOfflineMode && mounted) {
        setState(() => _isOfflineMode = true);
      }
    } finally {
      _pollingSync = false;
    }
  }

  Future<void> _refreshOutboxBadge() async {
    final c = await OfflineOutboxStore.count();
    if (mounted && c != _outboxCount) {
      setState(() => _outboxCount = c);
    }
  }

  Future<void> _trySyncOutbox({bool silent = false}) async {
    if (_syncingOutbox) return;
    final pending = await OfflineOutboxStore.count();
    if (pending == 0) {
      if (mounted && _outboxCount != 0) setState(() => _outboxCount = 0);
      return;
    }
    if (mounted) setState(() => _syncingOutbox = true);
    try {
      final res = await OfflineOutboxStore.flushAll(widget.api);
      if (!mounted) return;
      setState(() => _outboxCount = res.remaining);
      if (res.sent > 0) {
        _showSnack("✅ Oflayn ${res.sent} ta amal yuborildi!");
        await _refreshAll();
      } else if (!silent && res.remaining > 0) {
        _showSnack("Internet ulanmagan (${res.remaining} ta navbatda)",
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _syncingOutbox = false);
    }
  }

  Future<void> _switchToTab(int index, {bool animate = true}) async {
    if (index < 0 || index > 3) return;
    if (mounted) {
      setState(() => _tabIndex = index);
    }
    if (!_pageController.hasClients) return;
    if (!animate) {
      _programmaticTargetTab = null;
      _pageController.jumpToPage(index);
      return;
    }
    _programmaticTargetTab = index;
    try {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (_programmaticTargetTab == index) {
        _programmaticTargetTab = null;
      }
    }
  }

  Future<Map<String, dynamic>> _fetchPeriodStatsForKey(String key) {
    if (key == 'today') {
      return widget.api.getPeriodStats(days: 1, preset: 'today');
    }
    if (key == 'yesterday') {
      return widget.api.getPeriodStats(days: 1, preset: 'yesterday');
    }
    if (key == '14d') {
      return widget.api.getPeriodStats(days: 14);
    }
    if (key == '30d') {
      return widget.api.getPeriodStats(days: 30);
    }
    if (key == 'custom' &&
        _customDateFrom != null &&
        _customDateTo != null) {
      return widget.api.getPeriodStats(
        days: 30,
        dateFrom: _customDateFrom,
        dateTo: _customDateTo,
      );
    }
    return widget.api.getPeriodStats(days: 7);
  }

  Future<void> _refreshAll({
    bool silent = false,
    bool fromRemoteSync = false,
  }) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    final showLoader = !silent || _summary == null;
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final prePending = await OfflineOutboxStore.count();
      if (prePending > 0) {
        await OfflineOutboxStore.flushAll(widget.api);
      }
      final postPending = await OfflineOutboxStore.count();
      final results = await Future.wait([
        widget.api.getStatus(),
        widget.api.getUnpaidDebts(),
      ]);
      final usedOffline = widget.api.lastFetchUsedOfflineCache;
      SyncVersionInfo? syncInfo;
      if (!usedOffline) {
        try {
          syncInfo = await widget.api.getSyncVersion();
        } catch (_) {}
      }
      ApkVersionInfo? ver;
      if (!kIsWeb && !usedOffline) {
        try {
          ver = await widget.api.checkApkVersion();
        } catch (_) {}
      }
      List<HistorySessionItem> hist = _historySessions;
      try {
        hist = await widget.api.getHistorySessions(limit: 30);
      } catch (_) {}
      List<Map<String, dynamic>> series = _dailySeries;
      String granularity = _seriesGranularity;
      if (!usedOffline) {
        try {
          final p = await _fetchPeriodStatsForKey(_activePeriodKey);
          series = ((p['daily_series'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          granularity = (p['granularity'] ?? 'daily').toString();
        } catch (_) {}
      }
      StatusSummary? refreshedViewed;
      if (_viewedSessionSummary != null && !usedOffline) {
        try {
          refreshedViewed = await widget.api
              .getHistorySessionDetail(_viewedSessionSummary!.sessionId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _summary = results[0] as StatusSummary;
          _allDebts = results[1] as List<NakladnoyItem>;
          _historySessions = hist;
          _dailySeries = series;
          _seriesGranularity = granularity;
          if (_viewedSessionSummary != null && refreshedViewed != null) {
            _viewedSessionSummary = refreshedViewed;
          }
          if (syncInfo != null) {
            if (syncInfo.rev.isNotEmpty) {
              _lastSyncRev = syncInfo.rev;
            }
            if (kIsWeb && syncInfo.webVersion.isNotEmpty) {
              if (_initialWebVersion == null) {
                _initialWebVersion = syncInfo.webVersion;
              } else if (_initialWebVersion != syncInfo.webVersion) {
                _webUpdateAvailable = true;
              }
            }
          }
          if (ver != null) _remoteVersion = ver;
          _outboxCount = postPending;
          _isOfflineMode = usedOffline;
          if (!silent) {
            _dataAnimSeed++;
          }
          _loading = false;
        });
      }
      if (!fromRemoteSync && !usedOffline) {
        SyncBus.notifyRemoteChange();
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await widget.api.clearSession();
        if (mounted) widget.onLoggedOut();
        return;
      }
      if (showLoader && mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (showLoader && mounted) {
        setState(() {
          _error = 'Aloqa xatosi: $e';
          _loading = false;
        });
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _selectDashboardSession(int? sessionId) async {
    if (sessionId == null || sessionId == _summary?.sessionId) {
      setState(() => _viewedSessionSummary = null);
      return;
    }
    setState(() => _switchingSession = true);
    try {
      final detail = await widget.api.getHistorySessionDetail(sessionId);
      if (mounted) {
        setState(() {
          _viewedSessionSummary = detail;
          _dataAnimSeed++;
        });
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _switchingSession = false);
    }
  }

  Future<void> _selectTrendPeriodKey(String key) async {
    final String label;
    switch (key) {
      case 'today':
        label = 'Bugun (soatlik)';
        break;
      case 'yesterday':
        label = 'Kecha (soatlik)';
        break;
      case '14d':
        label = '14 kunlik';
        break;
      case '30d':
        label = '30 kunlik';
        break;
      default:
        label = '7 kunlik';
    }
    setState(() {
      _activePeriodKey = key;
      _periodLabel = label;
    });
    try {
      final p = await _fetchPeriodStatsForKey(key);
      if (mounted) {
        setState(() {
          _dailySeries = ((p['daily_series'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _seriesGranularity = (p['granularity'] ??
                  ((key == 'today' || key == 'yesterday') ? 'hourly' : 'daily'))
              .toString();
        });
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _pickCustomTrendDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    final dFrom = DateFormat('yyyy-MM-dd').format(picked.start);
    final dTo = DateFormat('yyyy-MM-dd').format(picked.end);
    final isOneDay = dFrom == dTo;
    setState(() {
      _customDateFrom = dFrom;
      _customDateTo = dTo;
      _activePeriodKey = 'custom';
      _periodLabel =
          isOneDay ? '$dFrom • Soatlik dinamika' : '$dFrom — $dTo dinamikasi';
    });
    try {
      final p = await widget.api.getPeriodStats(
        days: 30,
        dateFrom: dFrom,
        dateTo: dTo,
      );
      if (mounted) {
        setState(() {
          _dailySeries = ((p['daily_series'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _seriesGranularity =
              (p['granularity'] ?? (isOneDay ? 'hourly' : 'daily')).toString();
        });
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (Overlay.maybeOf(context, rootOverlay: true) != null) {
      showActionFeedbackBanner(context, msg, isError: isError);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppTokens.dangerRed : AppTokens.navyDark,
      ),
    );
  }

  Future<void> _downloadAndShareApkUpdate({bool manualCheck = false}) async {
    if (kIsWeb || _updatingApk) return;
    setState(() => _updatingApk = true);
    try {
      final verInfo = await widget.api.checkApkVersion();
      if (mounted) {
        setState(() => _remoteVersion = verInfo);
      }
      if (manualCheck && verInfo.build <= kAppBuildNumber) {
        _showSnack(
            '✅ Sizda eng so\'nggi versiya o\'rnatilgan (v$kAppVersion #$kAppBuildNumber)');
        return;
      }
      if (!mounted) return;
      await showInAppApkUpdateDialog(
        context: context,
        downloadUri: widget.api.apkDownloadUri,
        version: verInfo.version,
        sizeBytes: verInfo.sizeBytes,
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
    double? presetAmount,
  }) async {
    final titles = {
      'main': existing != null ? 'Kirimni tahrirlash' : 'Pul oldim',
      'expense': existing != null ? 'Xarajatni tahrirlash' : 'Xarajat kiritish',
      'kassa_debt': existing != null
          ? 'Kassa qarzini tahrirlash'
          : 'Kassadan qarz oldim',
      'kassa_repay': existing != null
          ? 'Qaytarishni tahrirlash'
          : 'Kassaga qaytardim',
    };
    final icons = {
      'main': Icons.add_card_rounded,
      'expense': Icons.trending_down_rounded,
      'kassa_debt': Icons.account_balance_rounded,
      'kassa_repay': Icons.assignment_return_rounded,
    };
    final initialNum = existing?.amount ?? presetAmount;
    final amtCtrl = TextEditingController(
      text: (initialNum != null && initialNum > 0)
          ? UzsAmountInputFormatter.formatDigits(
              initialNum.round().toString())
          : '',
    );
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: sheetBottomPadding(ctx),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: sheetMaxHeight(ctx, fraction: 0.90),
            ),
            child: SingleChildScrollView(
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
                      labelText: 'Summa',
                      hintText: '5 000 000',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Izoh',
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
          _showSnack('✅ Yangilandi');
        } else {
          await widget.api.addCash(
            amount: val,
            sourceType: sourceType,
            note: noteCtrl.text,
          );
          _showSnack('✅ Saqlandi');
        }
        await _refreshAll();
      } catch (e) {
        if (existing == null && isNetworkOfflineError(e)) {
          final cnt = await OfflineOutboxStore.enqueueCash(
            amount: val,
            sourceType: sourceType,
            note: noteCtrl.text,
          );
          if (mounted) {
            setState(() {
              _outboxCount = cnt;
              _isOfflineMode = true;
            });
          }
          _showSnack("📥 Oflayn saqlandi — internet kelganda yuboriladi");
        } else {
          _showSnack(e.toString(), isError: true);
        }
      }
    }
  }

  Future<void> _openAddNakladnoySheet({
    PickedBytesFile? initialPhoto,
    String? initialSupplier,
    double? initialAmount,
    String? initialPaymentMode,
    String? initialNote,
  }) async {
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
        initialSupplier: initialSupplier,
        initialAmount: initialAmount,
        initialPaymentMode: initialPaymentMode,
        initialNote: initialNote,
        existingTodayNakladnoys: _summary?.nakladnoys ?? const [],
      ),
    );
    await _refreshOutboxBadge();
    if (saved == true) {
      await _refreshAll();
    }
  }

  Future<void> _openSupplierProfile(String supplierName) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SupplierProfileSheet(
        api: widget.api,
        supplierName: supplierName,
        onOpenNakladnoyDetail: _openNakladnoyDetail,
        onOpenSupplierProfile: _openSupplierProfile,
      ),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _openNakladnoyDetail(
    NakladnoyItem item, {
    bool readOnly = false,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => NakladnoyDetailSheet(
        api: widget.api,
        item: item,
        readOnly: readOnly || item.isClosedSession,
        onOpenSupplierProfile: _openSupplierProfile,
      ),
    );
    if (changed == true) {
      await _refreshAll();
    }
  }

  Future<void> _openPayDebtDialog(NakladnoyItem item) async {
    final amtCtrl = TextEditingController(
      text: UzsAmountInputFormatter.formatDigits(
        item.amount.round().toString(),
      ),
    );
    final chosen = await showModalBottomSheet<({String method, double amount})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final entered = parseUzsInput(amtCtrl.text);
          final valid =
              entered != null && entered > 0 && entered <= item.amount + 0.01;
          final isPartial = valid && entered < item.amount - 0.5;
          final rem = isPartial ? (item.amount - entered) : 0.0;
          final halfAmt = ((item.amount / 2) / 1000).round() * 1000.0;

          void submitWith(String m) {
            final v = parseUzsInput(amtCtrl.text);
            if (v == null || v <= 0 || v > item.amount + 0.01) return;
            Navigator.pop(ctx, (method: m, amount: v));
          }

          return SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, sheetBottomPadding(ctx)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: sheetMaxHeight(ctx, fraction: 0.90),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Qarzni to'lash (${item.displayNum})",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.supplierName} • Jami qarz: ${formatUzs(item.amount, withCurrency: true)}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amtCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [UzsAmountInputFormatter()],
                        onChanged: (_) => setSheetState(() {}),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontFeatures: AppTokens.tabularNums,
                        ),
                        decoration: InputDecoration(
                          labelText: "To'lanayotgan summa",
                          prefixIcon: const Icon(Icons.payments_outlined),
                          errorText: (!valid && amtCtrl.text.trim().isNotEmpty)
                              ? "Qarz summasidan oshmasligi kerak"
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text("To'liq"),
                            onPressed: () {
                              amtCtrl.text =
                                  UzsAmountInputFormatter.formatDigits(
                                item.amount.round().toString(),
                              );
                              setSheetState(() {});
                            },
                          ),
                          if (halfAmt > 0 && halfAmt < item.amount)
                            ActionChip(
                              label: Text('Yarmi (${formatUzs(halfAmt)})'),
                              onPressed: () {
                                amtCtrl.text =
                                    UzsAmountInputFormatter.formatDigits(
                                  halfAmt.round().toString(),
                                );
                                setSheetState(() {});
                              },
                            ),
                        ],
                      ),
                      if (isPartial) ...[
                        const SizedBox(height: 8),
                        Text(
                          "📌 Qisman to'lov — qoladigan qarz: ${formatUzs(rem, withCurrency: true)}",
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTokens.debtAmber,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.cashGreen),
                        onPressed: valid ? () => submitWith('cash') : null,
                        icon: const Icon(Icons.payments_rounded),
                        label: const Text('Naqd'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.cardBlue),
                        onPressed: valid ? () => submitWith('card') : null,
                        icon: const Icon(Icons.credit_card_rounded),
                        label: const Text('Karta'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.transferPurple),
                        onPressed: valid ? () => submitWith('transfer') : null,
                        icon: const Icon(Icons.account_balance_rounded),
                        label: const Text("O'tkazma"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (chosen != null) {
      final isPart = chosen.amount < item.amount - 0.5;
      try {
        await widget.api.payDebt(
          paymentId: item.id,
          paymentMethod: chosen.method,
          amount: isPart ? chosen.amount : null,
        );
        _showSnack(isPart
            ? "✅ ${formatUzs(chosen.amount)} to'landi (qoldiq: ${formatUzs(item.amount - chosen.amount)})"
            : "✅ Qarz to'liq yopildi");
        await _refreshAll();
      } catch (e) {
        if (isNetworkOfflineError(e)) {
          final cnt = await OfflineOutboxStore.enqueuePayDebt(
            paymentId: item.id,
            paymentMethod: chosen.method,
            supplierName: item.supplierName,
            amount: item.amount,
            partialAmount: isPart ? chosen.amount : null,
          );
          if (mounted) {
            setState(() {
              _outboxCount = cnt;
              _isOfflineMode = true;
            });
          }
          _showSnack("📥 Oflayn saqlandi — internet kelganda yuboriladi");
        } else {
          _showSnack(e.toString(), isError: true);
        }
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
          if (widget.api.canWrite)
            IconButton(
              tooltip: 'AI Ovozli buyruq',
              onPressed: _openVoiceCommandSheet,
              icon: const Icon(Icons.mic_rounded),
            ),
          IconButton(
            tooltip: _isOfflineMode
                ? 'Oflayn rejim (sinxron kutilmoqda)'
                : 'Jonli sinxronizatsiya faol — Yangilash',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _refreshTurns += 1.0);
              _refreshAll();
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedRotation(
                  turns: _refreshTurns,
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.refresh_rounded),
                ),
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isOfflineMode
                          ? AppTokens.debtAmber
                          : AppTokens.cashGreen,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mavzu (Kun/Tun)',
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onToggleTheme();
            },
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: Icon(
                isDarkCtx(context)
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                key: ValueKey<bool>(isDarkCtx(context)),
              ),
            ),
          ),
        ],
      ),
      // Compact animated "+" icon FAB (no "+ Nakladnoy" text label)
      floatingActionButton: widget.api.canWrite
          ? IgnorePointer(
              ignoring: _tabIndex > 2,
              child: AnimatedOpacity(
                opacity: _tabIndex <= 2 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedScale(
                  scale: _tabIndex <= 2 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: TactileScaleTap(
                    pressedScale: 0.92,
                    child: FloatingActionButton(
                      tooltip: 'Yangi Nakladnoy qo\'shish',
                      onPressed: () => _openAddNakladnoySheet(),
                      child: const Icon(Icons.add_rounded, size: 30),
                    ),
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDarkCtx(context)
                  ? const Color(0xFF151125).withValues(alpha: 0.96)
                  : Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkCtx(context)
                    ? const Color(0xFF342954)
                    : AppTokens.cardBorderLight,
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDarkCtx(context)
                      ? Colors.black.withValues(alpha: 0.48)
                      : AppTokens.brandViolet.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: _switchToTab,
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
                    label: 'Amallar',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: debtCount > 0,
                      label: Text('$debtCount'),
                      child: const Icon(Icons.storefront_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: debtCount > 0,
                      label: Text('$debtCount'),
                      child: const Icon(Icons.storefront_rounded),
                    ),
                    label: "Ta'minotchilar",
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.assessment_outlined),
                    selectedIcon: Icon(Icons.assessment_rounded),
                    label: 'Smena',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          if (isDarkCtx(context))
            Positioned(
              top: -90,
              left: 0,
              right: 0,
              height: 240,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.7),
                      radius: 1.05,
                      colors: [
                        AppTokens.brandViolet.withValues(alpha: 0.16),
                        AppTokens.brandOrchid.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: _loading && _summary == null
                ? const DashboardLoadingSkeleton()
                : _error != null && _summary == null
                    ? _buildErrorState()
                    : Column(
                  children: [
                    if (_isOfflineMode || _outboxCount > 0)
                      _buildOfflineStatusBanner(),
                    if (!kIsWeb &&
                        _remoteVersion != null &&
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
                    if (kIsWeb && _webUpdateAvailable)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          gradient: AppTokens.aiGradient,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '🚀 Yangi Web versiya tayyor — ilovani yangilang',
                                style: TextStyle(
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
                              onPressed: reloadWebApp,
                              child: const Text('Yangilash'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                          },
                        ),
                        child: PageView(
                          controller: _pageController,
                          physics: const PageScrollPhysics(),
                          onPageChanged: (index) {
                            if (_programmaticTargetTab != null) {
                              if (index == _programmaticTargetTab) {
                                _programmaticTargetTab = null;
                                if (_tabIndex != index) {
                                  setState(() => _tabIndex = index);
                                }
                              }
                              return;
                            }
                            if (_tabIndex != index) {
                              setState(() => _tabIndex = index);
                            }
                          },
                          children: [
                            _KeepAliveTabPage(child: _buildDashboardTab()),
                            _KeepAliveTabPage(child: _buildNakladnoylarTab()),
                            _KeepAliveTabPage(child: _buildDebtsTab()),
                            _KeepAliveTabPage(
                                child: _buildSmenaAndReportsTab()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineStatusBanner() {
    final (ambFg, ambBg, ambBorder) =
        AppTokens.semanticSurface(context, AppTokens.debtAmber);
    final label = _isOfflineMode && _outboxCount > 0
        ? '📡 Oflayn • Navbatda: $_outboxCount ta (ko\'rish)'
        : (_isOfflineMode
            ? '📡 Oflayn rejim (saqlangan ma\'lumotlar)'
            : '⏳ Navbatda: $_outboxCount ta amal (ko\'rish)');
    return InkWell(
      onTap: _outboxCount > 0 ? _openOfflineQueueSheet : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ambBg,
          border: Border(bottom: BorderSide(color: ambBorder)),
        ),
        child: Row(
          children: [
            Icon(
              _isOfflineMode
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_upload_rounded,
              size: 18,
              color: ambFg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: ambFg,
                ),
              ),
            ),
            if (_outboxCount > 0)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: ambFg,
                ),
                onPressed: _syncingOutbox ? null : () => _trySyncOutbox(),
                icon: _syncingOutbox
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ambFg,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                label: Text(_syncingOutbox ? 'Kuting...' : 'Yuborish'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfflineQueueSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => OfflineQueueSheet(
        api: widget.api,
        onSyncNow: () => _trySyncOutbox(),
      ),
    );
    await _refreshOutboxBadge();
  }

  Future<void> _openKassaDebtHistorySheet() async {
    final repayAmount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => KassaDebtHistorySheet(
        api: widget.api,
        canWrite: widget.api.canWrite,
      ),
    );
    if (repayAmount != null && mounted) {
      await _openCashDialog('kassa_repay', presetAmount: repayAmount);
    }
  }

  Future<void> _openVoiceCommandSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => VoiceCommandSheet(api: widget.api),
    );
    if (result == null || !mounted) return;
    final intent = (result['intent'] ?? '').toString();
    final amount = (result['amount'] as num?)?.toDouble();
    final supplier = result['supplier_name']?.toString();
    final transcript = (result['transcript'] ?? '').toString();

    if (intent == 'cash_in' ||
        intent == 'kassa_debt' ||
        intent == 'kassa_repay' ||
        intent == 'expense') {
      final src = intent == 'cash_in' ? 'main' : intent;
      if (amount != null && amount > 0) {
        try {
          await widget.api.addCash(
            amount: amount,
            sourceType: src,
            note: transcript,
          );
          _showSnack('✅ Saqlandi');
          await _refreshAll();
        } catch (e) {
          if (isNetworkOfflineError(e)) {
            final cnt = await OfflineOutboxStore.enqueueCash(
              amount: amount,
              sourceType: src,
              note: transcript,
            );
            if (mounted) {
              setState(() {
                _outboxCount = cnt;
                _isOfflineMode = true;
              });
            }
            _showSnack('📥 Oflayn saqlandi');
          } else {
            _showSnack(e.toString(), isError: true);
          }
        }
      } else {
        await _openCashDialog(src);
      }
      return;
    }

    if (intent == 'pay_supplier') {
      await _openAddNakladnoySheet(
        initialSupplier: supplier,
        initialAmount: amount,
        initialPaymentMode: 'cash',
        initialNote: transcript,
      );
      return;
    }

    if (intent == 'count_cash' && amount != null && amount >= 0) {
      setState(() => _voiceCountedCashPreset = amount);
      await _switchToTab(3);
      _showSnack('🧮 Sanalgan pul joylandi');
      return;
    }

    if (intent == 'status') {
      await _switchToTab(0);
      await _refreshAll();
    }
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
        onOpenSupplierProfile: _openSupplierProfile,
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

  Future<void> _openSupplierSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SupplierAndRoundingSettingsSheet(
        api: widget.api,
        showSnack: _showSnack,
      ),
    );
    await _refreshAll();
  }

  Future<void> _openTelegramHubSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => TelegramGroupsAndBotSettingsSheet(
        api: widget.api,
        showSnack: _showSnack,
      ),
    );
    await _refreshAll();
  }

  // --------------------------------------------------------------------------
  // TAB 1: HAQIQIY ANALITIK DASHBOARD & PUL OLDI-BERDI TARIXI
  // --------------------------------------------------------------------------

  Widget _buildDashboardTab() {
    final s = _viewedSessionSummary ?? _summary!;
    final isViewingPast = _viewedSessionSummary != null &&
        _viewedSessionSummary!.sessionId != _summary!.sessionId;

    final now = DateTime.now();
    final overdueDebts = _allDebts.where((d) {
      final raw = d.reportDate ?? d.createdAt;
      if (raw.length < 10) return false;
      final dt = DateTime.tryParse(raw.substring(0, 10));
      if (dt == null) return false;
      return now.difference(dt).inDays >= 3;
    }).toList();
    final overdueSum =
        overdueDebts.fold<double>(0, (acc, elem) => acc + elem.amount);
    final (overFg, overBg, overBorder) =
        AppTokens.semanticSurface(context, AppTokens.debtAmber);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          _buildDashboardDateSwitcherBar(s, isViewingPast),
          const SizedBox(height: 10),
          if (overdueDebts.isNotEmpty) ...[
            TactileScaleTap(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() => _debtSubTab = 'nakladnoy');
                  _switchToTab(2);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: overBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: overBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: overFg, size: 19),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '3+ kunlik qarz: ${overdueDebts.length} ta • ${formatUzs(overdueSum, withCurrency: true)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.8,
                            fontWeight: FontWeight.w800,
                            color: overFg,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: overFg, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          HeroBalanceCard(
            summary: s,
            animSeed: _dataAnimSeed,
            onTapKassaDebtHistory: _openKassaDebtHistorySheet,
            onAddCash: (!isViewingPast && widget.api.canWrite)
                ? () => _openCashDialog('main')
                : null,
            onExpense: (!isViewingPast && widget.api.canWrite)
                ? () => _openCashDialog('expense')
                : null,
            onKassaDebt: (!isViewingPast && widget.api.canWrite)
                ? () => _openCashDialog('kassa_debt')
                : null,
            onKassaRepay: (!isViewingPast && widget.api.canWrite)
                ? () => _openCashDialog('kassa_repay')
                : null,
          ),
          const SizedBox(height: 12),
          // Quick buttons for Stage 1 (History) & Stage 2 (Live Sverka & Stats)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  ),
                  onPressed: _openLiveSverkaSheet,
                  icon: const Icon(Icons.query_stats_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Sverka', maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                  ),
                  onPressed: _openHistorySessionsSheet,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Arxiv', maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DashboardAnalyticsSection(
            summary: s,
            animSeed: _dataAnimSeed,
            canWrite: !isViewingPast && widget.api.canWrite,
            dailySeries: _dailySeries,
            seriesGranularity: _seriesGranularity,
            periodLabel: _periodLabel,
            activePeriodKey: _activePeriodKey,
            onSelectPeriodKey: _selectTrendPeriodKey,
            onPickCustomDateRange: _pickCustomTrendDateRange,
            onTapPaymentFilter: (mode) {
              setState(() => _filterMode = mode);
              _switchToTab(1);
            },
            onOpenNakladnoyTab: () => _switchToTab(1),
            onTapSupplier: _openSupplierProfile,
            onTapNakladnoy: (item) => _openNakladnoyDetail(
              item,
              readOnly: isViewingPast ||
                  s.sessionStatus == 'closed' ||
                  item.isClosedSession,
            ),
            onEditCashTx: (tx) =>
                _openCashDialog(tx.sourceType, existing: tx),
            onDeleteCashTx: (tx) async {
              await widget.api.deleteCash(tx.id);
              await _refreshAll();
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 5),
                    content: const Text("Kassa amali o'chirildi"),
                    action: SnackBarAction(
                      label: 'Bekor qilish',
                      onPressed: () async {
                        try {
                          await widget.api.restoreCash(tx.id);
                          await _refreshAll();
                        } catch (_) {}
                      },
                    ),
                  ),
                );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardDateSwitcherBar(
      StatusSummary activeSummary, bool isViewingPast) {
    final sessions = _historySessions;
    final currentId = activeSummary.sessionId;
    final curIdx = sessions.indexWhere((e) => e.id == currentId);
    final hasPrev = curIdx >= 0 && curIdx + 1 < sessions.length;
    final hasNext = curIdx > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Oldingi smena / sana',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 34, height: 34),
                  onPressed: (_switchingSession || !hasPrev)
                      ? null
                      : () =>
                          _selectDashboardSession(sessions[curIdx + 1].id),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: sessions.isEmpty
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                        child: Text(
                          '📅 ${activeSummary.reportDate} • #${activeSummary.sessionId}${activeSummary.timeSpanLabel.isNotEmpty ? " (${activeSummary.timeSpanLabel})" : ""}',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : HisobchiCustomDropdown<int>(
                        value: sessions.any((e) => e.id == currentId)
                            ? currentId
                            : sessions.first.id,
                        compact: true,
                        searchable: sessions.length >= 8,
                        enabled: !_switchingSession,
                        sheetTitle: 'Smena / sanani tanlang',
                        options: sessions.map((s) {
                          final isCurOpen = s.id == _summary?.sessionId;
                          final span = s.timeRangeLabel;
                          final selText = span.isNotEmpty
                              ? '${s.reportDate} • ${s.shiftBadge} ($span)'
                              : '${s.reportDate} • ${s.shiftBadge}';
                          return CustomDropdownOption<int>(
                            value: s.id,
                            label: '${s.reportDate} • ${s.shiftBadge}',
                            selectedLabel: selText,
                            subtitle:
                                '🕐 ${span.isNotEmpty ? span : s.reportDate}  •  Naqd: ${formatUzs(s.expectedCash)}',
                            icon: isCurOpen
                                ? Icons.radio_button_checked_rounded
                                : Icons.schedule_rounded,
                            accentColor: isCurOpen
                                ? AppTokens.cashGreen
                                : AppTokens.brand,
                            badge: isCurOpen ? 'Faol' : s.shiftBadge,
                          );
                        }).toList(),
                        onChanged: (val) => _selectDashboardSession(val),
                      ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Keyingi smena / sana',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 34, height: 34),
                  onPressed: (_switchingSession || !hasNext)
                      ? null
                      : () =>
                          _selectDashboardSession(sessions[curIdx - 1].id),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            if (isViewingPast) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => _selectDashboardSession(null),
                  icon: const Icon(Icons.today_rounded, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "Bugungi smenaga qaytish (${_summary!.reportDate})",
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: DEDICATED NAKLADNOYLAR RO'YXATI (With Dropdown Filter & Sort)
  // --------------------------------------------------------------------------

  Widget _buildNakladnoylarTab() {
    final s = _viewedSessionSummary ?? _summary!;
    final isViewingPast = _viewedSessionSummary != null &&
        _viewedSessionSummary!.sessionId != _summary!.sessionId;
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          _buildDashboardDateSwitcherBar(s, isViewingPast),
          const SizedBox(height: 10),
          _buildNakladnoyMiniDashboard(s),
          const SizedBox(height: 12),
          // Header strip
          Row(
            children: [
              Expanded(
                child: Text(
                  'Amallar (${filtered.length} ta)',
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

          // Filter & Sort Custom Dropdown Row
          Builder(builder: (context) {
            final cashCnt = s.nakladnoys
                .where((n) => !n.isDebt && n.paymentMethod == 'cash')
                .length;
            final cardCnt = s.nakladnoys
                .where((n) => !n.isDebt && n.paymentMethod == 'card')
                .length;
            final transferCnt = s.nakladnoys
                .where((n) => !n.isDebt && n.paymentMethod == 'transfer')
                .length;
            final debtCnt = s.nakladnoys.where((n) => n.isDebt).length;

            return Row(
              children: [
                Expanded(
                  child: HisobchiCustomDropdown<String>(
                    value: _filterMode,
                    compact: true,
                    labelText: "To'lov turi",
                    sheetTitle: "To'lov turi bo'yicha filtrlash",
                    options: [
                      CustomDropdownOption<String>(
                        value: 'all',
                        label: 'Barchasi',
                        subtitle: "Hamma to'lov turlari",
                        icon: Icons.apps_rounded,
                        accentColor: AppTokens.brand,
                        badge: '${s.nakladnoys.length}',
                      ),
                      CustomDropdownOption<String>(
                        value: 'cash',
                        label: 'Naqd',
                        subtitle: "Qo'ldagi naqd puldan",
                        icon: Icons.payments_rounded,
                        accentColor: AppTokens.cashGreen,
                        badge: '$cashCnt',
                      ),
                      CustomDropdownOption<String>(
                        value: 'card',
                        label: 'Karta',
                        subtitle: "Plastik karta orqali",
                        icon: Icons.credit_card_rounded,
                        accentColor: AppTokens.cardBlue,
                        badge: '$cardCnt',
                      ),
                      CustomDropdownOption<String>(
                        value: 'transfer',
                        label: "O'tkazma",
                        subtitle: "Perechesleniya orqali",
                        icon: Icons.account_balance_rounded,
                        accentColor: AppTokens.transferPurple,
                        badge: '$transferCnt',
                      ),
                      CustomDropdownOption<String>(
                        value: 'debt',
                        label: 'Qarzga',
                        subtitle: "Hali to'lanmagan qarzlar",
                        icon: Icons.push_pin_rounded,
                        accentColor: AppTokens.debtAmber,
                        badge: '$debtCnt',
                      ),
                    ],
                    onChanged: (v) => setState(() => _filterMode = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: HisobchiCustomDropdown<String>(
                    value: _sortMode,
                    compact: true,
                    labelText: 'Saralash',
                    sheetTitle: 'Nakladnoylarni saralash',
                    options: const [
                      CustomDropdownOption<String>(
                        value: 'newest',
                        label: 'Yangilari tepada',
                        selectedLabel: 'Yangilari',
                        subtitle: "Oxirgi kiritilganlar birinchi",
                        icon: Icons.schedule_rounded,
                        accentColor: AppTokens.brand,
                      ),
                      CustomDropdownOption<String>(
                        value: 'amount_desc',
                        label: 'Summasi katta',
                        selectedLabel: 'Katta summa',
                        subtitle: "Eng yirik summadan kichigiga",
                        icon: Icons.trending_down_rounded,
                        accentColor: AppTokens.cashGreen,
                      ),
                      CustomDropdownOption<String>(
                        value: 'supplier_az',
                        label: 'Postavshik (A-Z)',
                        selectedLabel: 'A-Z',
                        subtitle: "Alifbo tartibida guruhlash",
                        icon: Icons.sort_by_alpha_rounded,
                        accentColor: AppTokens.cardBlue,
                      ),
                    ],
                    onChanged: (v) => setState(() => _sortMode = v),
                  ),
                ),
              ],
            );
          }),
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
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                ),
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
                child: SwipeableNakladnoyTile(
                  item: item,
                  onTap: () => _openNakladnoyDetail(
                    item,
                    readOnly: isViewingPast ||
                        s.sessionStatus == 'closed' ||
                        item.isClosedSession,
                  ),
                  onQuickPay: item.isDebt && widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                  onDuplicate: widget.api.canWrite
                      ? () => _openAddNakladnoySheet(
                            initialSupplier: item.supplierName,
                            initialAmount: item.amount,
                            initialPaymentMode:
                                item.isDebt ? 'debt' : item.paymentMethod,
                            initialNote: item.note,
                          )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNakladnoyMiniDashboard(StatusSummary s) {
    final naks = s.nakladnoys;
    final cashCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'cash').length;
    final cardCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'card').length;
    final transferCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'transfer').length;
    final debtCnt = naks.where((n) => n.isDebt).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _miniNakStatCard(
                label: 'Naqd',
                amount: s.totalNakladnoySpent,
                count: cashCnt,
                icon: Icons.payments_rounded,
                color: AppTokens.cashGreen,
                filterKey: 'cash',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniNakStatCard(
                label: 'Karta',
                amount: s.totalCardSpent,
                count: cardCnt,
                icon: Icons.credit_card_rounded,
                color: AppTokens.cardBlue,
                filterKey: 'card',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _miniNakStatCard(
                label: "O'tkazma",
                amount: s.totalTransferSpent,
                count: transferCnt,
                icon: Icons.account_balance_rounded,
                color: AppTokens.transferPurple,
                filterKey: 'transfer',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniNakStatCard(
                label: 'Qarzga',
                amount: s.totalDebtNakladnoy,
                count: debtCnt,
                icon: Icons.push_pin_rounded,
                color: AppTokens.debtAmber,
                filterKey: 'debt',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniNakStatCard({
    required String label,
    required double amount,
    required int count,
    required IconData icon,
    required Color color,
    required String filterKey,
  }) {
    final isSelected = _filterMode == filterKey;
    final (fg, bg, border) = AppTokens.semanticSurface(context, color);

    return Card(
      color: isSelected ? bg : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? fg : border.withValues(alpha: 0.45),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() {
          _filterMode = isSelected ? 'all' : filterKey;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: fg),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$label ($count)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? fg : textSecondaryOf(context),
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle_rounded, size: 14, color: fg),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatUzs(amount, withCurrency: true),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: textPrimaryOf(context),
                          fontFeatures: AppTokens.tabularNums,
                        ),
                      ),
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

  // --------------------------------------------------------------------------
  // TAB 3: TA'MINOTCHILAR BAZASI + QARZLAR + NASIYA DAFTARI
  // --------------------------------------------------------------------------

  Widget _buildDebtsTab() {
    if (_debtSubTab == 'directory') {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _buildDebtSectionSwitcher(),
          ),
          Expanded(
            child: SuppliersDirectoryView(
              api: widget.api,
              onOpenSupplierProfile: _openSupplierProfile,
              showSnack: _showSnack,
            ),
          ),
        ],
      );
    }
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
                        'Qarzlar (${visibleDebts.length} ta)',
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
            Builder(builder: (context) {
              final allDebtSum = _allDebts.fold<double>(
                  0, (prev, elem) => prev + elem.amount);
              final bySup = <String, ({int cnt, double sum})>{};
              for (final d in _allDebts) {
                final cur = bySup[d.supplierName];
                bySup[d.supplierName] = (
                  cnt: (cur?.cnt ?? 0) + 1,
                  sum: (cur?.sum ?? 0) + d.amount,
                );
              }
              return HisobchiCustomDropdown<String>(
                value: activeSupFilter,
                labelText: "Postavshik bo'yicha saralash",
                sheetTitle: 'Qarz postavshikni tanlang',
                searchable: debtSuppliers.length >= 6,
                options: [
                  CustomDropdownOption<String>(
                    value: 'all',
                    label: 'Barcha postavshiklar',
                    subtitle: formatUzs(allDebtSum, withCurrency: true),
                    icon: Icons.groups_rounded,
                    accentColor: AppTokens.debtAmber,
                    badge: '${_allDebts.length} ta',
                  ),
                  ...debtSuppliers.map((sup) {
                    final st = bySup[sup];
                    return CustomDropdownOption<String>(
                      value: sup,
                      label: sup,
                      subtitle: st != null
                          ? formatUzs(st.sum, withCurrency: true)
                          : null,
                      icon: Icons.storefront_rounded,
                      accentColor: AppTokens.brand,
                      badge: '${st?.cnt ?? 0} ta',
                    );
                  }),
                ],
                onChanged: (v) => setState(() => _debtSupplierFilter = v),
              );
            }),
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
                child: SwipeableNakladnoyTile(
                  item: item,
                  onTap: () => _openNakladnoyDetail(item),
                  onQuickPay: widget.api.canWrite
                      ? () => _openPayDebtDialog(item)
                      : null,
                  onDuplicate: widget.api.canWrite
                      ? () => _openAddNakladnoySheet(
                            initialSupplier: item.supplierName,
                            initialAmount: item.amount,
                            initialPaymentMode: 'debt',
                            initialNote: item.note,
                          )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDebtSectionSwitcher() {
    final filledCompact = FilledButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
    );
    final outlinedCompact = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
    );
    Widget tabBtn(String key, String label, IconData activeIc, IconData idleIc) {
      final sel = _debtSubTab == key;
      return Expanded(
        child: sel
            ? FilledButton.icon(
                style: filledCompact,
                onPressed: () {},
                icon: Icon(activeIc, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1),
                ),
              )
            : OutlinedButton.icon(
                style: outlinedCompact,
                onPressed: () => setState(() => _debtSubTab = key),
                icon: Icon(idleIc, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1),
                ),
              ),
      );
    }

    return Row(
      children: [
        tabBtn(
          'directory',
          'Barchasi',
          Icons.storefront_rounded,
          Icons.storefront_outlined,
        ),
        const SizedBox(width: 6),
        tabBtn(
          'nakladnoy',
          'Qarz (${_allDebts.length})',
          Icons.push_pin_rounded,
          Icons.push_pin_outlined,
        ),
        const SizedBox(width: 6),
        tabBtn(
          'nasiya',
          'Nasiya',
          Icons.menu_book_rounded,
          Icons.menu_book_outlined,
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
      presetCountedCash: _voiceCountedCashPreset,
      onClosed: _refreshAll,
      onLoggedOut: widget.onLoggedOut,
      onLockChanged: widget.onLockChanged,
      showSnack: _showSnack,
      onOpenHistorySessions: _openHistorySessionsSheet,
      onOpenLiveSverka: _openLiveSverkaSheet,
      onOpenPrixod: _openPrixodSheet,
      onOpenSupplierSettings: _openSupplierSettingsSheet,
      onOpenTelegramSettings: _openTelegramHubSheet,
      onCheckUpdate: () => _downloadAndShareApkUpdate(manualCheck: true),
    );
  }
}

class _SmenaAndReportsView extends StatefulWidget {
  final StatusSummary summary;
  final HisobchiApiClient api;
  final double? presetCountedCash;
  final Future<void> Function() onClosed;
  final VoidCallback onLoggedOut;
  final VoidCallback? onLockChanged;
  final void Function(String, {bool isError}) showSnack;
  final VoidCallback onOpenHistorySessions;
  final VoidCallback onOpenLiveSverka;
  final VoidCallback onOpenPrixod;
  final VoidCallback onOpenSupplierSettings;
  final VoidCallback onOpenTelegramSettings;
  final VoidCallback onCheckUpdate;

  const _SmenaAndReportsView({
    required this.summary,
    required this.api,
    this.presetCountedCash,
    required this.onClosed,
    required this.onLoggedOut,
    this.onLockChanged,
    required this.showSnack,
    required this.onOpenHistorySessions,
    required this.onOpenLiveSverka,
    required this.onOpenPrixod,
    required this.onOpenSupplierSettings,
    required this.onOpenTelegramSettings,
    required this.onCheckUpdate,
  });

  @override
  State<_SmenaAndReportsView> createState() => _SmenaAndReportsViewState();
}

class _SmenaAndReportsViewState extends State<_SmenaAndReportsView> {
  static const List<int> _uzsDenominations = [
    200000,
    100000,
    50000,
    20000,
    10000,
    5000,
    2000,
    1000,
  ];
  final TextEditingController _countedCtrl = TextEditingController();
  final Map<int, int> _denomCounts = {};
  bool _showDenomCalc = false;
  bool _closing = false;
  String _selectedReportType = 'today'; // today | week | month | custom | sverka
  bool _downloadingExcel = false;
  bool _sendingExcelTelegram = false;
  bool _lockLoaded = false;
  bool _pinEnabled = false;
  String? _savedPin;
  bool _bioEnabled = false;
  bool _bioSupported = false;

  @override
  void initState() {
    super.initState();
    if (widget.presetCountedCash != null) {
      _countedCtrl.text = UzsAmountInputFormatter.formatDigits(
        widget.presetCountedCash!.round().toString(),
      );
    }
    _loadSecurityLock();
  }

  @override
  void didUpdateWidget(covariant _SmenaAndReportsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.presetCountedCash != null &&
        widget.presetCountedCash != oldWidget.presetCountedCash) {
      _countedCtrl.text = UzsAmountInputFormatter.formatDigits(
        widget.presetCountedCash!.round().toString(),
      );
    }
  }

  void _updateDenomCount(int denom, int delta) {
    final cur = _denomCounts[denom] ?? 0;
    final next = (cur + delta).clamp(0, 9999);
    setState(() {
      if (next == 0) {
        _denomCounts.remove(denom);
      } else {
        _denomCounts[denom] = next;
      }
      final sum = _denomCounts.entries.fold<int>(
        0,
        (acc, e) => acc + e.key * e.value,
      );
      _countedCtrl.text = sum > 0
          ? UzsAmountInputFormatter.formatDigits(sum.toString())
          : '';
    });
  }

  void _clearDenoms() {
    setState(() {
      _denomCounts.clear();
      _countedCtrl.clear();
    });
  }

  Future<void> _loadSecurityLock() async {
    if (kIsWeb) return;
    final lock = await AppLockStorage.load();
    final bioAvail = await canUseBiometric();
    if (!mounted) return;
    setState(() {
      _lockLoaded = true;
      _pinEnabled = lock.enabled && lock.pin != null;
      _savedPin = lock.pin;
      _bioEnabled = lock.bioEnabled;
      _bioSupported = bioAvail;
    });
  }

  Future<void> _setupOrChangePin() async {
    final isChanging = _pinEnabled && _savedPin != null;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PinLockScreen(
          mode: isChanging ? PinScreenMode.change : PinScreenMode.setup,
          expectedPin: isChanging ? _savedPin : null,
          biometricEnabled: _bioEnabled,
          onCanUseBiometric: canUseBiometric,
          onCompleted: (pin, enableBio) async {
            await AppLockStorage.savePin(pin, biometricEnabled: enableBio);
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          onCancel: () => Navigator.of(ctx).pop(false),
        ),
      ),
    );
    if (saved == true && mounted) {
      await _loadSecurityLock();
      widget.onLockChanged?.call();
      widget.showSnack(
        isChanging
            ? "🔐 PIN kod muvaffaqiyatli yangilandi!"
            : "🔐 4 xonali PIN kod o'rnatildi!",
      );
    }
  }

  Future<void> _toggleBiometric(bool nextVal) async {
    if (!_pinEnabled || _savedPin == null) {
      widget.showSnack("Avval 4 xonali PIN kod o'rnating", isError: true);
      await _setupOrChangePin();
      return;
    }
    if (nextVal) {
      final ok = await authenticateBiometric(
        subtitle: "Otpechatka orqali kirishni yoqish uchun barmoq izini bosing",
      );
      if (!ok) {
        if (mounted) {
          widget.showSnack("Barmoq izi tasdiqlanmadi", isError: true);
        }
        return;
      }
    }
    await AppLockStorage.setBiometricEnabled(nextVal);
    if (!mounted) return;
    await _loadSecurityLock();
    widget.onLockChanged?.call();
    widget.showSnack(
      nextVal
          ? "✅ Otpechatka orqali kirish yoqildi!"
          : "🔕 Otpechatka orqali kirish o'chirildi",
    );
  }

  Future<void> _disablePin() async {
    if (!_pinEnabled || _savedPin == null) return;
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PinLockScreen(
          mode: PinScreenMode.unlock,
          expectedPin: _savedPin,
          biometricEnabled: _bioEnabled,
          onCanUseBiometric: canUseBiometric,
          onAuthenticateBiometric: () => authenticateBiometric(
            subtitle: "PIN kodni o'chirish uchun barmoq izini tasdiqlang",
          ),
          onCompleted: (pin, bio) async {
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          onCancel: () => Navigator.of(ctx).pop(false),
        ),
      ),
    );
    if (verified == true && mounted) {
      await AppLockStorage.clearPin();
      await _loadSecurityLock();
      widget.onLockChanged?.call();
      widget.showSnack("🔓 PIN kod va xavfsizlik qulfi o'chirildi");
    }
  }

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

  Future<({String endpoint, String filename, Map<String, String>? query, String reportType, int? sessionId, String? month})?>
      _resolveSelectedExcelConfig() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final weekAgo = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 6)));
    final monthStart = DateFormat('yyyy-MM-01').format(DateTime.now());

    if (_selectedReportType == 'week') {
      return (
        endpoint: '/export/range',
        filename: 'Hisobot_7kun_${weekAgo}_$today.xlsx',
        query: {'date_from': weekAgo, 'date_to': today},
        reportType: 'range',
        sessionId: null,
        month: null,
      );
    }
    if (_selectedReportType == 'month') {
      return (
        endpoint: '/export/range',
        filename: 'Hisobot_Oy_${monthStart}_$today.xlsx',
        query: {'date_from': monthStart, 'date_to': today},
        reportType: 'range',
        sessionId: null,
        month: null,
      );
    }
    if (_selectedReportType == 'sverka') {
      return (
        endpoint: '/export/sverka',
        filename: 'Sverka_$today.xlsx',
        query: null,
        reportType: 'sverka',
        sessionId: null,
        month: DateFormat('yyyy-MM').format(DateTime.now()),
      );
    }
    if (_selectedReportType == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024, 1, 1),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );
      if (picked == null) return null;
      final d1 = DateFormat('yyyy-MM-dd').format(picked.start);
      final d2 = DateFormat('yyyy-MM-dd').format(picked.end);
      return (
        endpoint: '/export/range',
        filename: 'Hisobot_${d1}_$d2.xlsx',
        query: {'date_from': d1, 'date_to': d2},
        reportType: 'range',
        sessionId: null,
        month: null,
      );
    }
    return (
      endpoint: '/export/session',
      filename: 'Hisobot_${widget.summary.reportDate}.xlsx',
      query: null,
      reportType: 'session',
      sessionId: widget.summary.sessionId,
      month: null,
    );
  }

  Future<void> _runSelectedExcelExport() async {
    final cfg = await _resolveSelectedExcelConfig();
    if (cfg == null) return;

    setState(() => _downloadingExcel = true);
    widget.showSnack('📥 Excel tayyorlanmoqda...');
    try {
      await saveAndShareExcel(
        fetchBytes: () =>
            widget.api.downloadExcelBytes(cfg.endpoint, query: cfg.query),
        filename: cfg.filename,
        authenticatedDownloadUrl: widget.api
            .buildAuthenticatedDownloadUrl(cfg.endpoint, query: cfg.query),
      );
    } catch (e) {
      widget.showSnack('Excel yuklashda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _downloadingExcel = false);
    }
  }

  Future<void> _sendSelectedExcelToTelegram() async {
    final cfg = await _resolveSelectedExcelConfig();
    if (cfg == null) return;

    setState(() => _sendingExcelTelegram = true);
    try {
      final msg = await widget.api.sendExcelToTelegram(
        reportType: cfg.reportType,
        sessionId: cfg.sessionId,
        dateFrom: cfg.query?['date_from'],
        dateTo: cfg.query?['date_to'],
        month: cfg.month,
      );
      widget.showSnack(msg);
    } catch (e) {
      widget.showSnack('Telegramga yuborishda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingExcelTelegram = false);
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
                Row(
                  children: [
                    const Icon(Icons.lock_clock_rounded, color: AppTokens.brand),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Smena yopish',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calculate_rounded, size: 16),
                      label: Text(_showDenomCalc ? 'Yopish' : 'Kupuralar'),
                      onPressed: () =>
                          setState(() => _showDenomCalc = !_showDenomCalc),
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
                        'Kutilgan kassa:',
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
                    labelText: 'Sanalgan naqd pul',
                    hintText: formatUzs(expected),
                    prefixIcon: const Icon(Icons.payments_outlined),
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
                if (_showDenomCalc) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDarkCtx(context)
                          ? AppTokens.surfaceDark.withValues(alpha: 0.6)
                          : AppTokens.surfaceLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDarkCtx(context)
                            ? AppTokens.cardBorderDark
                            : AppTokens.cardBorderLight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Kupuralar soni',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: textSecondaryOf(context),
                              ),
                            ),
                            if (_denomCounts.isNotEmpty)
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: _clearDenoms,
                                child: const Text('Tozalash'),
                              ),
                          ],
                        ),
                        ..._uzsDenominations.map((denom) {
                          final cnt = _denomCounts[denom] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 82,
                                  child: Text(
                                    formatUzs(denom),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: cnt > 0
                                      ? () => _updateDenomCount(denom, -1)
                                      : null,
                                  icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      size: 20),
                                ),
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '$cnt',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _updateDenomCount(denom, 1),
                                  icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 20),
                                ),
                                Expanded(
                                  child: Text(
                                    cnt > 0 ? formatUzs(denom * cnt) : '—',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: cnt > 0
                                          ? AppTokens.cashGreen
                                          : textSecondaryOf(context),
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
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
                          ? "✅ Farq: 0 so'm"
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
                  label: Text(_closing ? 'Yopilmoqda...' : 'Smenani yopish'),
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
                        'Excel hisobot',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                HisobchiCustomDropdown<String>(
                  value: _selectedReportType,
                  labelText: 'Hisobot turi',
                  sheetTitle: 'Excel hisobot',
                  options: [
                    CustomDropdownOption<String>(
                      value: 'today',
                      label: 'Bugun',
                      subtitle: widget.summary.reportDate,
                      icon: Icons.today_rounded,
                      accentColor: AppTokens.cashGreen,
                    ),
                    const CustomDropdownOption<String>(
                      value: 'week',
                      label: '7 kunlik',
                      icon: Icons.date_range_rounded,
                      accentColor: AppTokens.brand,
                    ),
                    const CustomDropdownOption<String>(
                      value: 'month',
                      label: 'Shu oy',
                      icon: Icons.calendar_month_rounded,
                      accentColor: AppTokens.cardBlue,
                    ),
                    const CustomDropdownOption<String>(
                      value: 'custom',
                      label: "Sana oralig'i...",
                      icon: Icons.edit_calendar_rounded,
                      accentColor: AppTokens.brandViolet,
                    ),
                    const CustomDropdownOption<String>(
                      value: 'sverka',
                      label: 'Postavshiklar sverkasi',
                      icon: Icons.account_balance_wallet_rounded,
                      accentColor: AppTokens.debtAmber,
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedReportType = v),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.cashGreen),
                  onPressed: _downloadingExcel || _sendingExcelTelegram
                      ? null
                      : _runSelectedExcelExport,
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
                      : 'Yuklab olish'),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _downloadingExcel || _sendingExcelTelegram
                      ? null
                      : _sendSelectedExcelToTelegram,
                  icon: _sendingExcelTelegram
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.telegram),
                  label: Text(_sendingExcelTelegram
                      ? 'Yuborilmoqda...'
                      : 'Telegramga yuborish'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenLiveSverka,
                  icon: const Icon(Icons.query_stats_rounded),
                  label: const Text('Jonli sverka'),
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
                        'Arxiv va Prixod',
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
                  label: const Text('Smenalar arxivi'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenPrixod,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Prixod (ITOG)'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onOpenSupplierSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Postavshik sozlamalari'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (!kIsWeb) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.fingerprint_rounded,
                          color: AppTokens.brand, size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Xavfsizlik',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoRow(
                    'PIN kod:',
                    !_lockLoaded
                        ? '...'
                        : (_pinEnabled ? '✅ Yoqilgan' : "🔕 O'chiq"),
                  ),
                  const SizedBox(height: 6),
                  _infoRow(
                    'Otpechatka:',
                    !_lockLoaded
                        ? '...'
                        : (!_bioSupported
                            ? '⚠️ Mavjud emas'
                            : (_bioEnabled ? '✅ Yoqilgan' : "🔕 O'chiq")),
                  ),
                  if (_bioSupported) ...[
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.fingerprint_rounded,
                        color: AppTokens.brand,
                      ),
                      title: const Text(
                        'Otpechatka',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _pinEnabled ? 'Avtomatik tekshirish' : "Avval PIN o'rnating",
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _pinEnabled && _bioEnabled,
                      onChanged: _lockLoaded ? _toggleBiometric : null,
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TactileScaleTap(
                      child: FilledButton.tonalIcon(
                        onPressed: _lockLoaded ? _setupOrChangePin : null,
                        icon: Icon(
                          _pinEnabled
                              ? Icons.edit_rounded
                              : Icons.pin_rounded,
                        ),
                        label: Text(
                          _pinEnabled ? "PIN o'zgartirish" : "PIN o'rnatish",
                        ),
                      ),
                    ),
                  ),
                  if (_pinEnabled) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TactileScaleTap(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTokens.dangerRed,
                          ),
                          onPressed: _lockLoaded ? _disablePin : null,
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text("PIN o'chirish"),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
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
                      'Telegram va Bot',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(
                  'Guruh:',
                  widget.summary.groupInfo.bound
                      ? '✅ ${widget.summary.groupInfo.title}'
                      : '⚠️ Ulanmagan',
                ),
                const SizedBox(height: 6),
                _infoRow(
                  'Avto-yuborish:',
                  widget.summary.groupInfo.apkPostToGroup
                      ? '✅ Yoqilgan'
                      : "🔕 O'chiq",
                ),
                const SizedBox(height: 6),
                _infoRow(
                  'Versiya:',
                  kIsWeb
                      ? 'v$kAppVersion (Web)'
                      : 'v$kAppVersion (#$kAppBuildNumber)',
                ),
                const SizedBox(height: 6),
                _infoRow('Rol:', widget.api.role.toUpperCase()),
                const Divider(height: 24),
                if (widget.api.isAdmin)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onOpenTelegramSettings,
                      icon: const Icon(Icons.hub_rounded),
                      label: const Text('Guruh va xodimlar'),
                    ),
                  ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.onCheckUpdate,
                      icon: const Icon(Icons.system_update_rounded),
                      label: const Text('Yangilanishni tekshirish'),
                    ),
                  ),
                  const SizedBox(height: 10),
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

Widget buildSupplierInputSuffix({
  required BuildContext context,
  required TextEditingController controller,
  required List<String> suppliers,
  required Future<void> Function(String picked) onPicked,
  VoidCallback? onCleared,
  bool enabled = true,
}) {
  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (_, val, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (val.text.isNotEmpty)
          IconButton(
            tooltip: 'Tozalash',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.clear_rounded, size: 18),
            onPressed: enabled
                ? () {
                    controller.clear();
                    onCleared?.call();
                  }
                : null,
          ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: AppTokens.brand.withValues(alpha: 0.12),
              foregroundColor: AppTokens.brand,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: enabled
                ? () async {
                    final picked = await showSupplierPickerDialog(
                      context,
                      suppliers,
                      current: controller.text,
                    );
                    if (picked != null && picked.trim().isNotEmpty) {
                      await onPicked(picked.trim());
                    }
                  }
                : null,
            icon: const Icon(Icons.list_alt_rounded, size: 16),
            label: const Text(
              "Ro'yxat",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

class AddNakladnoySheet extends StatefulWidget {
  final HisobchiApiClient api;
  final GroupInfo groupInfo;
  final PickedBytesFile? initialPhoto;
  final String? initialSupplier;
  final double? initialAmount;
  final String? initialPaymentMode;
  final String? initialNote;
  final List<NakladnoyItem> existingTodayNakladnoys;

  const AddNakladnoySheet({
    super.key,
    required this.api,
    required this.groupInfo,
    this.initialPhoto,
    this.initialSupplier,
    this.initialAmount,
    this.initialPaymentMode,
    this.initialNote,
    this.existingTodayNakladnoys = const [],
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
  PickedBytesFile? _photoFile;
  double? _originalAmount;
  String? _supplierSuggestion;
  List<String> _aiSimilarSuppliers = [];
  MathCheckResult? _mathCheck;
  bool _appliedCalculatedAmount = false;
  double? _writtenAmountBeforeFix;
  double? _writtenOriginalAmountBeforeFix;
  bool _aiLoading = false;
  String? _aiBadgeText;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sendToGroup = true;
    if (widget.initialSupplier != null &&
        widget.initialSupplier!.trim().isNotEmpty) {
      _supCtrl.text = widget.initialSupplier!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectSupplier(widget.initialSupplier!.trim());
      });
    }
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
        widget.initialAmount!.round().toString(),
      );
    }
    if (widget.initialPaymentMode != null &&
        widget.initialPaymentMode!.isNotEmpty) {
      _paymentMode = widget.initialPaymentMode!;
    }
    if (widget.initialNote != null && widget.initialNote!.trim().isNotEmpty) {
      _noteCtrl.text = widget.initialNote!.trim();
    }
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
  Future<void> _runAiExtract(PickedBytesFile file) async {
    setState(() {
      _aiLoading = true;
      _aiBadgeText = null;
      _mathCheck = null;
      _appliedCalculatedAmount = false;
      _writtenAmountBeforeFix = null;
      _writtenOriginalAmountBeforeFix = null;
      _error = null;
    });
    try {
      final res = await widget.api.extractFromPhoto(
        file.bytes,
        filename: file.filename,
      );
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
        _writtenAmountBeforeFix = res.amount;
        _writtenOriginalAmountBeforeFix = res.originalAmount;
        _supplierSuggestion = res.supplierSuggestion;
        _aiSimilarSuppliers = res.similarSuppliers;
        _mathCheck = res.mathCheck;
        if (res.recentAmounts.isNotEmpty) {
          _recentAmounts = res.recentAmounts;
        }
        if (_mathCheck != null && _mathCheck!.isMismatch) {
          _aiBadgeText =
              "⚠️ AI o'qidi, lekin nakladnoy summasida xatolik topildi!";
        } else if (_mathCheck != null && _mathCheck!.isComputed) {
          _aiBadgeText = "🧮 AI qatorlar yig'indisini hisoblab chiqdi!";
        } else if (res.ok) {
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
      PickedBytesFile? file;
      if (source == ImageSource.camera && !kIsWeb) {
        final res = await openCustomCamera(context);
        if (!mounted) return;
        if (res.file != null) {
          file = res.file;
        } else if (!res.fallbackToSystem) {
          return;
        }
      }
      if (file == null) {
        final xfile = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (xfile == null || !mounted) return;
        final bytes = await xfile.readAsBytes();
        file = PickedBytesFile(
          bytes: bytes,
          filename: xfile.name.isNotEmpty ? xfile.name : 'nakladnoy.jpg',
        );
      }
      if (mounted) {
        final picked = file;
        setState(() => _photoFile = picked);
        await _runAiExtract(picked);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Rasm tanlashda xatolik: $e');
      }
    }
  }

  List<NakladnoyItem> _findTodayDuplicates() {
    final sup = _supCtrl.text.trim().toLowerCase();
    final amt = parseUzsInput(_amtCtrl.text);
    if (sup.isEmpty || amt == null || amt <= 0) return const [];
    final roundedThousand = (amt ~/ 1000) * 1000;
    return widget.existingTodayNakladnoys.where((item) {
      if (item.supplierName.trim().toLowerCase() != sup) return false;
      if ((item.amount - amt).abs() < 1) return true;
      if (roundedThousand > 0 && (item.amount - roundedThousand).abs() < 1) {
        return true;
      }
      if (item.originalAmount != null && (item.originalAmount! - amt).abs() < 1) {
        return true;
      }
      return false;
    }).toList();
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
    final dups = _findTodayDuplicates();
    if (dups.isNotEmpty) {
      final dup = dups.first;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppTokens.debtAmber, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '⚠️ Dublikat nakladnoy!',
                  style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: Text(
            "Bugun soat ${dup.timeHm} da «${dup.supplierName}» uchun ${formatUzs(dup.amount, withCurrency: true)} allaqachon kiritilgan (${dup.displayNum}).\n\nBaribir yangi nakladnoy sifatida saqlansinmi?",
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.debtAmber,
                minimumSize: const Size(0, 42),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ha, saqlash'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
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
        photoBytes: _photoFile?.bytes,
        photoFilename: _photoFile?.filename ?? 'nakladnoy.jpg',
        originalAmount: _originalAmount,
      );
      if (mounted) {
        final grpMsg = res['group_message']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              grpMsg.isNotEmpty
                  ? '✅ Saqlandi ($grpMsg)'
                  : '✅ Nakladnoy saqlandi',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (isNetworkOfflineError(e)) {
        await OfflineOutboxStore.enqueueNakladnoy(
          supplierName: sup,
          amount: amt,
          paymentMode: _paymentMode,
          note: _noteCtrl.text,
          sendToGroup: _sendToGroup,
          originalAmount: _originalAmount,
          photoBytes: _photoFile?.bytes,
          photoFilename: _photoFile?.filename ?? 'nakladnoy.jpg',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "📥 Oflayn saqlandi — internet kelganda avtomatik yuboriladi",
              ),
            ),
          );
          Navigator.pop(context, true);
        }
      } else if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatQty(double? q) {
    if (q == null) return '?';
    if ((q - q.roundToDouble()).abs() < 1e-6) {
      return q.round().toString();
    }
    return q.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Widget _mathDetailRow(BuildContext context, String label, String val,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: textSecondaryOf(context),
              ),
            ),
          ),
          Text(
            val,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildMathCheckCard(BuildContext context) {
    final mc = _mathCheck;
    if (mc == null || !mc.hasDisplay) return null;

    if (mc.isMismatch) {
      final targetCalc = mc.roundedCalculatedTotal ?? mc.calculatedTotal;
      if (_appliedCalculatedAmount && targetCalc != null && targetCalc > 0) {
        final (okFg, okBg, okBorder) =
            AppTokens.semanticSurface(context, AppTokens.cashGreen);
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: okBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: okBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: okFg, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "To'g'ri summa qo'yildi (${formatUzs(targetCalc, withCurrency: true)})",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: okFg,
                  ),
                ),
              ),
              if (_writtenAmountBeforeFix != null &&
                  _writtenAmountBeforeFix! > 0)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
                          _writtenAmountBeforeFix!.round().toString());
                      _originalAmount = _writtenOriginalAmountBeforeFix;
                      _appliedCalculatedAmount = false;
                    });
                  },
                  child: const Text('Aslini qaytarish',
                      style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        );
      }

      final (fg, bg, border) =
          AppTokens.semanticSurface(context, AppTokens.dangerRed);
      final diff = mc.difference;
      final diffText = (diff != null && diff.abs() > 0)
          ? (diff > 0
              ? "+${formatUzs(diff.abs())} so'm ortiqcha"
              : "-${formatUzs(diff.abs())} so'm kam")
          : null;
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: fg, size: 19),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'HISOB-KITOBDA XATOLIK!',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (mc.writtenTotal != null)
              _mathDetailRow(
                context,
                'Rasmda yozilgan:',
                formatUzs(mc.writtenTotal, withCurrency: true),
              ),
            if (mc.calculatedTotal != null)
              _mathDetailRow(
                context,
                'Hisoblangan (${mc.itemsCount} ta qator):',
                formatUzs(mc.calculatedTotal, withCurrency: true),
                valueColor: fg,
                bold: true,
              ),
            if (diffText != null)
              _mathDetailRow(
                context,
                'Farq:',
                diffText,
                valueColor: fg,
                bold: true,
              ),
            if (mc.lineErrors.isNotEmpty) ...[
              const SizedBox(height: 5),
              ...mc.lineErrors.take(4).map(
                    (le) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        "• ${le.name}: ${_formatQty(le.qty)} × ${formatUzs(le.unitPrice)} = ${formatUzs(le.expected)} (yozilgan: ${formatUzs(le.written)})",
                        style: TextStyle(
                          fontSize: 11.5,
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
            ],
            if (targetCalc != null && targetCalc > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.dangerRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 40),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
                          targetCalc.round().toString());
                      _originalAmount = mc.calculatedTotal;
                      _appliedCalculatedAmount = true;
                    });
                  },
                  icon: const Icon(Icons.calculate_rounded, size: 17),
                  label: Text(
                    "To'g'ri summani (${formatUzs(targetCalc)} so'm) qo'yish",
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (mc.isOk) {
      final (fg, bg, border) =
          AppTokens.semanticSurface(context, AppTokens.cashGreen);
      final label = mc.status == 'vat_ok'
          ? "Tekshirildi: ${mc.itemsCount} ta qator + 12% QQS (НДС) mos"
          : "Tekshirildi: ${mc.itemsCount} ta qator yig'indisi mos (${formatUzs(mc.calculatedTotal, withCurrency: true)})";
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_rounded, color: fg, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (mc.isComputed) {
      final (fg, bg, border) =
          AppTokens.semanticSurface(context, AppTokens.brandViolet);
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.calculate_rounded, color: fg, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                "Rasmda jami yozilmagan — ${mc.itemsCount} ta qator yig'indisi hisoblandi: ${formatUzs(mc.calculatedTotal, withCurrency: true)}",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (mc.isAdjusted) {
      final (fg, bg, border) =
          AppTokens.semanticSurface(context, AppTokens.debtAmber);
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: fg, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                "Qatorlar yig'indisi: ${formatUzs(mc.calculatedTotal, withCurrency: true)} (chegirma/qaytarish/qoldiq bo'lishi mumkin)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return null;
  }

  Future<void> _openPreviewPhotoFullscreen() async {
    final pf = _photoFile;
    if (pf == null) return;
    final supLabel = _supCtrl.text.trim().isNotEmpty
        ? _supCtrl.text.trim()
        : 'Nakladnoy rasmi';
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
                    child: Image.memory(
                      pf.bytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Orqaga'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            supLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
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

    final showAiBox =
        _photoFile != null || _aiLoading || _aiBadgeText != null;
    final hasBottomInsets = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isDark = isDarkCtx(context);

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: sheetMaxHeight(context, fraction: 0.92),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sticky Top Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 6),
                child: Row(
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
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),

              // Scrollable Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showAiBox) ...[
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: AppTokens.brandViolet.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  AppTokens.brandViolet.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_photoFile != null)
                                GestureDetector(
                                  onTap: _openPreviewPhotoFullscreen,
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.memory(
                                          _photoFile!.bytes,
                                          height: 120,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      if (!_aiLoading)
                                        Positioned(
                                          left: 8,
                                          bottom: 8,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 9, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.65),
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.zoom_in_rounded,
                                                    color: Colors.white,
                                                    size: 15),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Kattalashtirish',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      if (_aiLoading)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.60),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
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
                                                  : () => _runAiExtract(
                                                      _photoFile!),
                                              icon: const Icon(
                                                  Icons.auto_awesome_rounded,
                                                  size: 17),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton.filled(
                                              onPressed: () => setState(() {
                                                _photoFile = null;
                                                _aiBadgeText = null;
                                                _mathCheck = null;
                                                _appliedCalculatedAmount =
                                                    false;
                                                _writtenAmountBeforeFix = null;
                                                _writtenOriginalAmountBeforeFix =
                                                    null;
                                              }),
                                              icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 17),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_aiBadgeText != null) ...[
                                if (_photoFile != null)
                                  const SizedBox(height: 8),
                                Text(
                                  _aiBadgeText!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: (_mathCheck?.isMismatch == true)
                                        ? AppTokens.dangerRed
                                        : (_mathCheck?.isComputed == true)
                                            ? AppTokens.brandViolet
                                            : _aiBadgeText!.startsWith('✨')
                                                ? AppTokens.cashGreen
                                                : AppTokens.debtAmber,
                                  ),
                                ),
                              ],
                              if (_buildMathCheckCard(context)
                                  case final mathCard?)
                                mathCard,
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Supplier field with embedded "Ro'yxat" corner button + horizontal chips
                      TextField(
                        controller: _supCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Postavshik nomi',
                          hintText: 'Tanlang yoki yozing...',
                          prefixIcon: const Icon(Icons.storefront_rounded),
                          suffixIcon: buildSupplierInputSuffix(
                            context: context,
                            controller: _supCtrl,
                            suppliers: _allSuppliers,
                            onPicked: _selectSupplier,
                            onCleared: () =>
                                setState(() => _recentAmounts = []),
                          ),
                        ),
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
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                  ),
                                  onPressed: (_submitting || _aiLoading)
                                      ? null
                                      : () {
                                          final p = parseUzsInput(_amtCtrl.text);
                                          if (p != null && p > 0) {
                                            _selectAndSubmitSupplier(
                                                topSimilar);
                                          } else {
                                            _selectSupplier(topSimilar);
                                          }
                                        },
                                  icon: const Icon(Icons.check_circle_rounded,
                                      size: 18),
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      parseUzsInput(_amtCtrl.text) != null &&
                                              parseUzsInput(_amtCtrl.text)! > 0
                                          ? "✅ «$topSimilar» qilib tasdiqlash"
                                          : "✨ «$topSimilar» ni tanlash",
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: similarCandidates
                                    .map(
                                      (s) => ActionChip(
                                        avatar: Icon(
                                            Icons.auto_fix_high_rounded,
                                            size: 15,
                                            color: simFg),
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
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: matchingSuppliers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 6),
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
                                    fontWeight: isSel
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                                onPressed: () => _selectSupplier(name),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 11),

                      // Space-formatted Amount field (auto-rounded on server)
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
                      Builder(builder: (ctx) {
                        final warn = computeSupplierAnomalyWarning(
                          parseUzsInput(_amtCtrl.text),
                          _recentAmounts,
                        );
                        if (warn == null) return const SizedBox.shrink();
                        final (ambFg, ambBg, ambBorder) =
                            AppTokens.semanticSurface(ctx, AppTokens.debtAmber);
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 8),
                          decoration: BoxDecoration(
                            color: ambBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ambBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.trending_up_rounded,
                                  color: ambFg, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠️ $warn',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: ambFg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      Builder(builder: (ctx) {
                        final dups = _findTodayDuplicates();
                        if (dups.isEmpty) return const SizedBox.shrink();
                        final dup = dups.first;
                        final (ambFg, ambBg, ambBorder) =
                            AppTokens.semanticSurface(ctx, AppTokens.debtAmber);
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            color: ambBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ambBorder),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: ambFg, size: 19),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "⚠️ Dublikat ehtimoli: Bugun soat ${dup.timeHm} da «${dup.supplierName}» uchun ${formatUzs(dup.amount, withCurrency: true)} (${dup.displayNum}) allaqachon kiritilgan!",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: ambFg,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
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
                                      avatar: const Icon(Icons.history_rounded,
                                          size: 15),
                                      label: Text(formatUzs(a)),
                                      onPressed: () {
                                        _amtCtrl.text = UzsAmountInputFormatter
                                            .formatDigits(
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
                      const SizedBox(height: 12),

                      // Sleek 4-segment Payment mode selector
                      const Text(
                        "To'lov usuli",
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 8),
                      PaymentModeSelector(
                        selectedMode: _paymentMode,
                        onChanged: (m) => setState(() => _paymentMode = m),
                      ),
                      const SizedBox(height: 10),

                      // Note
                      TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Izoh (ixtiyoriy)',
                          prefixIcon: Icon(Icons.notes_rounded),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Guruhga yuborish toggle
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          '📤 Guruhga yuborish',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14.5),
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
                    ],
                  ),
                ),
              ),

              // Sticky Bottom Action Dock: Save + Gallery + Camera AI (right thumb)
              Container(
                padding: EdgeInsets.fromLTRB(
                    16, 10, 16, hasBottomInsets ? 10 : 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? AppTokens.cardBorderDark
                          : AppTokens.cardBorderLight,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(
                        '⚠️ $_error',
                        style: const TextStyle(
                          color: AppTokens.dangerRed,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TactileScaleTap(
                            pressedScale: 0.96,
                            enabled: !(_submitting || _aiLoading),
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              onPressed:
                                  (_submitting || _aiLoading) ? null : _submit,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.check_circle_rounded,
                                      size: 19),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _submitting
                                      ? 'Saqlanmoqda...'
                                      : 'Tasdiqlash va saqlash',
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: "Galereyadan AI orqali o'qish",
                          child: TactileScaleTap(
                            pressedScale: 0.93,
                            enabled: !(_submitting || _aiLoading),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(46, 48),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: (_submitting || _aiLoading)
                                  ? null
                                  : () => _pickPhoto(ImageSource.gallery),
                              child: const Icon(Icons.photo_library_rounded,
                                  size: 19),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Tooltip(
                          message: "Kameradan AI orqali o'qish",
                          child: TactileScaleTap(
                            pressedScale: 0.93,
                            enabled: !(_submitting || _aiLoading),
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTokens.brandViolet
                                    .withValues(alpha: isDark ? 0.28 : 0.14),
                                foregroundColor: isDark
                                    ? const Color(0xFFD8B4FE)
                                    : AppTokens.brandViolet,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 12),
                              ),
                              onPressed: (_submitting || _aiLoading)
                                  ? null
                                  : () => _pickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_rounded,
                                  size: 19),
                              label: const Text('AI'),
                            ),
                          ),
                        ),
                      ],
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
  final bool readOnly;
  final Future<void> Function(String supplier)? onOpenSupplierProfile;

  const NakladnoyDetailSheet({
    super.key,
    required this.api,
    required this.item,
    this.readOnly = false,
    this.onOpenSupplierProfile,
  });

  @override
  State<NakladnoyDetailSheet> createState() => _NakladnoyDetailSheetState();
}

class _NakladnoyDetailSheetState extends State<NakladnoyDetailSheet> {
  late NakladnoyItem _cur;
  late TextEditingController _supCtrl;
  late TextEditingController _amtCtrl;
  late TextEditingController _noteCtrl;
  final ImagePicker _picker = ImagePicker();
  List<String> _suppliers = [];
  bool _busy = false;
  bool _changed = false;
  bool _hasUnsavedEdits = false;
  int _photoCacheBust = 0;

  bool get _isReadOnly =>
      widget.readOnly || !widget.api.canWrite || _cur.isClosedSession;

  @override
  void initState() {
    super.initState();
    _cur = widget.item;
    _supCtrl = TextEditingController(text: _cur.supplierName);
    _amtCtrl = TextEditingController(
      text: UzsAmountInputFormatter.formatDigits(
          _cur.amount.round().toString()),
    );
    _noteCtrl = TextEditingController(text: _cur.note);
    _supCtrl.addListener(_onEditFieldChanged);
    _amtCtrl.addListener(_onEditFieldChanged);
    _noteCtrl.addListener(_onEditFieldChanged);
    if (!_isReadOnly) {
      _loadSuppliers();
    }
  }

  void _onEditFieldChanged() {
    final dirty = hasNakladnoyEdits(
      originalSupplier: _cur.supplierName,
      originalAmount: _cur.amount,
      originalNote: _cur.note,
      currentSupplier: _supCtrl.text,
      currentAmountText: _amtCtrl.text,
      currentNote: _noteCtrl.text,
    );
    if (dirty != _hasUnsavedEdits && mounted) {
      setState(() => _hasUnsavedEdits = dirty);
    }
  }

  @override
  void dispose() {
    _supCtrl.removeListener(_onEditFieldChanged);
    _amtCtrl.removeListener(_onEditFieldChanged);
    _noteCtrl.removeListener(_onEditFieldChanged);
    _supCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
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
      PickedBytesFile? file;
      if (source == ImageSource.camera && !kIsWeb) {
        final res = await openCustomCamera(context);
        if (!mounted) return;
        if (res.file != null) {
          file = res.file;
        } else if (!res.fallbackToSystem) {
          return;
        }
      }
      if (file == null) {
        final xfile = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (xfile == null || !mounted) return;
        file = PickedBytesFile(
          bytes: await xfile.readAsBytes(),
          filename: xfile.name.isNotEmpty ? xfile.name : 'nakladnoy.jpg',
        );
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final updated = await widget.api.uploadNakladnoyPhoto(
        _cur.id,
        file.bytes,
        filename: file.filename,
      );
      if (mounted) {
        setState(() {
          _cur = updated;
          _photoCacheBust++;
          _changed = true;
        });
        showTopSlideNotification(
          context,
          title: 'Rasm biriktirildi',
          subtitle: '${updated.supplierName} nakladnoyiga yuklandi',
          tone: TopNotifyTone.success,
          icon: Icons.add_a_photo_rounded,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSlideNotification(
          context,
          title: 'Rasm yuklashda xatolik',
          subtitle: e.toString(),
          tone: TopNotifyTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAllChanges() async {
    final sup = _supCtrl.text.trim();
    if (sup.isEmpty) {
      showTopSlideNotification(
        context,
        title: 'Postavshik nomini kiriting',
        tone: TopNotifyTone.error,
      );
      return;
    }
    final parsed = parseUzsInput(_amtCtrl.text);
    if (parsed == null || parsed <= 0) {
      showTopSlideNotification(
        context,
        title: "Summani to'g'ri kiriting",
        tone: TopNotifyTone.error,
      );
      return;
    }
    final oldSup = _cur.supplierName;
    final oldAmt = _cur.amount;
    final oldNote = _cur.note;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.updateNakladnoy(
        paymentId: _cur.id,
        supplierName: sup,
        amount: parsed,
        note: _noteCtrl.text.trim(),
        roundAmount: true,
      );
      if (mounted) {
        setState(() {
          _cur = updated;
          _supCtrl.text = updated.supplierName;
          _amtCtrl.text = UzsAmountInputFormatter.formatDigits(
              updated.amount.round().toString());
          _noteCtrl.text = updated.note;
          _changed = true;
          _hasUnsavedEdits = false;
        });
        showTopSlideNotification(
          context,
          title: "Nakladnoy o'zgartirildi",
          subtitle: buildNakladnoyEditSummary(
            oldSupplier: oldSup,
            oldAmount: oldAmt,
            oldNote: oldNote,
            newSupplier: updated.supplierName,
            newAmount: updated.amount,
            newNote: updated.note,
          ),
          tone: TopNotifyTone.edit,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSlideNotification(
          context,
          title: 'Saqlashda xatolik',
          subtitle: e.toString(),
          tone: TopNotifyTone.error,
        );
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
        showTopSlideNotification(
          context,
          title: "To'lov holati yangilandi",
          subtitle: '${updated.supplierName} • ${_paymentMethodLabel(updated)}',
          tone: TopNotifyTone.edit,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSlideNotification(
          context,
          title: 'Xatolik',
          subtitle: e.toString(),
          tone: TopNotifyTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPhotoPreview() {
    return GestureDetector(
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
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
    );
  }

  String _paymentMethodLabel(NakladnoyItem n) {
    if (n.isDebt) return '📌 Qarzga';
    switch (n.paymentMethod) {
      case 'card':
        return '💳 Karta orqali';
      case 'transfer':
        return "🏦 Perechesleniya (O'tkazma)";
      default:
        return '💵 Naqd pul';
    }
  }

  Widget _readOnlyInfoRow(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: textSecondaryOf(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
                color: valueColor ?? textPrimaryOf(context),
                fontFeatures: AppTokens.tabularNums,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMode = _cur.isDebt ? 'debt' : _cur.paymentMethod;

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: sheetMaxHeight(context, fraction: 0.90),
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
                  if (widget.onOpenSupplierProfile != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      onPressed: () {
                        Navigator.pop(context, _changed);
                        widget.onOpenSupplierProfile!(_cur.supplierName);
                      },
                      icon: const Icon(Icons.storefront_rounded, size: 16),
                      label: const Text(
                        'Profil',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_isReadOnly) ...[
                if (_cur.hasPhoto) ...[
                  _buildPhotoPreview(),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      children: [
                        _readOnlyInfoRow('Postavshik:', _cur.supplierName,
                            bold: true),
                        const Divider(height: 10),
                        _readOnlyInfoRow(
                          'Summa:',
                          formatUzs(_cur.amount, withCurrency: true),
                          bold: true,
                          valueColor: AppTokens.brand,
                        ),
                        if (_cur.originalAmount != null &&
                            _cur.originalAmount!.round() !=
                                _cur.amount.round()) ...[
                          const Divider(height: 10),
                          _readOnlyInfoRow(
                            'Asl summa:',
                            formatUzs(_cur.originalAmount, withCurrency: true),
                          ),
                        ],
                        const Divider(height: 10),
                        _readOnlyInfoRow(
                            "To'lov turi:", _paymentMethodLabel(_cur)),
                        const Divider(height: 10),
                        _readOnlyInfoRow(
                          'Sana va vaqt:',
                          _cur.reportDate != null
                              ? '${_cur.reportDate} • ${_cur.timeHm}'
                              : _cur.createdAt,
                        ),
                        if (_cur.note.isNotEmpty) ...[
                          const Divider(height: 10),
                          _readOnlyInfoRow('Izoh:', _cur.note),
                        ],
                        const Divider(height: 10),
                        _readOnlyInfoRow(
                          'Guruh holati:',
                          _cur.inGroup ? '✅ Guruhga yuborilgan' : '📁 Bazada',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Yopish'),
                ),
              ] else ...[
                if (_cur.hasPhoto) ...[
                  _buildPhotoPreview(),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _pickAndUploadPhoto(ImageSource.camera),
                        icon: const Icon(Icons.add_a_photo_rounded, size: 17),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Kamera', maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _pickAndUploadPhoto(ImageSource.gallery),
                        icon:
                            const Icon(Icons.photo_library_rounded, size: 17),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Galereya', maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Supplier field with embedded "Ro'yxat" corner button
                TextField(
                  controller: _supCtrl,
                  decoration: InputDecoration(
                    labelText: 'Postavshik',
                    prefixIcon: const Icon(Icons.storefront_rounded),
                    isDense: true,
                    suffixIcon: buildSupplierInputSuffix(
                      context: context,
                      controller: _supCtrl,
                      suppliers: _suppliers,
                      enabled: !_busy,
                      onPicked: (picked) async {
                        setState(() => _supCtrl.text = picked);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Space-formatted Amount field (auto-rounded on save)
                TextField(
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
                ),
                const SizedBox(height: 12),

                // Note field (Izoh)
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Izoh (ixtiyoriy)',
                    prefixIcon: Icon(Icons.notes_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Consolidated Save button: shifts to vivid Amber/Orange glow when edited
                TactileScaleTap(
                  enabled: !_busy,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: _hasUnsavedEdits
                          ? const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: _hasUnsavedEdits
                          ? null
                          : AppTokens.brand.withValues(alpha: 0.12),
                      border: Border.all(
                        color: _hasUnsavedEdits
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.75)
                            : AppTokens.brand.withValues(alpha: 0.25),
                      ),
                      boxShadow: _hasUnsavedEdits
                          ? [
                              BoxShadow(
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.36),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : const [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _busy ? null : _saveAllChanges,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _hasUnsavedEdits
                                    ? Icons.edit_note_rounded
                                    : Icons.check_circle_rounded,
                                size: 20,
                                color: _hasUnsavedEdits
                                    ? Colors.white
                                    : AppTokens.brand,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _busy
                                      ? 'Saqlanmoqda...'
                                      : "O'zgarishlarni saqlash",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _hasUnsavedEdits
                                        ? Colors.white
                                        : AppTokens.brand,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              if (_hasUnsavedEdits && !_busy) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    "O'zgardi",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final msg = await widget.api
                                      .sendNakladnoyToGroup(_cur.id);
                                  _changed = true;
                                  if (context.mounted) {
                                    showTopSlideNotification(
                                      context,
                                      title: 'Telegram guruhga yuborildi',
                                      subtitle: msg,
                                      tone: TopNotifyTone.info,
                                      icon: Icons.send_rounded,
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showTopSlideNotification(
                                      context,
                                      title: 'Yuborishda xatolik',
                                      subtitle: e.toString(),
                                      tone: TopNotifyTone.error,
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: const Icon(Icons.send_rounded, size: 17),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _cur.inGroup ? 'Guruhda yangilash' : 'Guruhga',
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.dangerRed,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              final delId = _cur.id;
                              final api = widget.api;
                              final messenger =
                                  ScaffoldMessenger.maybeOf(context);
                              await api.deleteNakladnoy(delId);
                              if (context.mounted) {
                                Navigator.pop(context, true);
                              }
                              messenger
                                ?..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 5),
                                    content:
                                        const Text("Nakladnoy o'chirildi"),
                                    action: SnackBarAction(
                                      label: 'Bekor qilish',
                                      onPressed: () async {
                                        try {
                                          await api.restoreNakladnoy(delId);
                                        } catch (_) {}
                                      },
                                    ),
                                  ),
                                );
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text("O'chirish"),
                    ),
                  ],
                ),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STAGE 1: O'TGAN SMENALAR TARIXI, SMENA ICHINI KO'RISH (FAQAT KO'RISH)
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
  String _filterDate = '';
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
      final list = await widget.api.getHistorySessions(limit: 50);
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

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate.isNotEmpty
          ? (DateTime.tryParse(_filterDate) ?? now)
          : now,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _filterDate = DateFormat('yyyy-MM-dd').format(picked));
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

  Future<void> _exportSessionExcel(StatusSummary s) async {
    setState(() => _busy = true);
    try {
      final filename = 'Hisobot_${s.reportDate}_smena${s.sessionId}.xlsx';
      final q = {'session_id': '${s.sessionId}'};
      await saveAndShareExcel(
        fetchBytes: () =>
            widget.api.downloadExcelBytes('/export/session', query: q),
        filename: filename,
        authenticatedDownloadUrl: widget.api
            .buildAuthenticatedDownloadUrl('/export/session', query: q),
      );
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
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.80),
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
                          : 'Smenalar arxivi',
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
              if (_selectedDetail == null) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Barchasi'),
                        selected: _filterDate.isEmpty,
                        onSelected: (_) => setState(() => _filterDate = ''),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Bugun'),
                        selected: _filterDate ==
                            DateFormat('yyyy-MM-dd').format(DateTime.now()),
                        onSelected: (_) => setState(() => _filterDate =
                            DateFormat('yyyy-MM-dd').format(DateTime.now())),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Kecha'),
                        selected: _filterDate ==
                            DateFormat('yyyy-MM-dd').format(
                                DateTime.now().subtract(const Duration(days: 1))),
                        onSelected: (_) => setState(() => _filterDate =
                            DateFormat('yyyy-MM-dd').format(
                                DateTime.now().subtract(const Duration(days: 1)))),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                        label: Text(
                            _filterDate.isNotEmpty ? _filterDate : 'Sana tanlash'),
                        onPressed: _pickFilterDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else if (_selectedDetail != null)
                Expanded(child: _buildDetailView(_selectedDetail!))
              else
                Expanded(
                  child: Builder(builder: (context) {
                    final visible = _filterDate.isEmpty
                        ? _sessions
                        : _sessions
                            .where((s) => s.matchesDate(_filterDate))
                            .toList();
                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          'Tanlangan sanada smenalar topilmadi',
                          style: TextStyle(color: textSecondaryOf(context)),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final s = visible[i];
                        final isOpen = s.status == 'open';
                        final timeTxt = s.timeRangeLabel;
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
                              '${s.reportDate}  •  ${s.shiftBadge}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              "${timeTxt.isNotEmpty ? '🕐 $timeTxt\n' : ''}"
                              "Kutilgan: ${formatUzs(s.expectedCash, withCurrency: true)}"
                              "${s.actualCountedCash != null ? '\nSanalgan: ${formatUzs(s.actualCountedCash, withCurrency: true)} (Farq: ${formatUzs(s.difference)})' : ''}",
                              style: const TextStyle(fontSize: 12.5, height: 1.35),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                        );
                      },
                    );
                  }),
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
                if (!isClosed) ...[
                  const Text(
                    '🟢 Ochiq faol smena',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                ],
                if (d.openedAt.isNotEmpty || d.closedAt.isNotEmpty) ...[
                  Text(
                    "🕐 Ochildi: ${d.openedAt.isNotEmpty ? d.openedAt : d.reportDate}"
                    "${d.closedAt.isNotEmpty ? '\n🏁 Yopildi: ${d.closedAt}' : ''}",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textSecondaryOf(context),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        onPressed: _busy ? null : () => _exportSessionExcel(d),
                        icon: const Icon(Icons.table_view_rounded, size: 17),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Excel yuklash', maxLines: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final msg = await widget.api
                                      .sendExcelToTelegram(
                                    reportType: 'session',
                                    sessionId: d.sessionId,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: const Icon(Icons.telegram, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('📤 Telegramga', maxLines: 1),
                        ),
                      ),
                    ),
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
                if (!isClosed) _changed = true;
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
  List<CashTxItem> _cashResults = [];
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
      final all = await widget.api.searchHistoryAll(q);
      if (mounted) {
        setState(() {
          _results = all.nakladnoys;
          _cashResults = all.cashItems;
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

  String _cashSourceTitle(String src) {
    if (src == 'kassa_debt') return '🏦 Kassadan qarz';
    if (src == 'kassa_repay') return '↩️ Kassaga qaytarish';
    if (src == 'expense') return '💸 Xarajat';
    return '➕ Pul oldim';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Umumiy qidiruv',
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
                        hintText: 'Postavshik, summa, izoh yoki sana...',
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
              else if (_results.isEmpty && _cashResults.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      "Postavshik, summa yoki izoh yozib «Qidirish» ni bosing.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondaryOf(context)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (_cashResults.isNotEmpty) ...[
                        Text(
                          'Kassa amallari (${_cashResults.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ..._cashResults.map(
                          (tx) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                '${_cashSourceTitle(tx.sourceType)} — ${formatUzs(tx.amount, withCurrency: true)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                '${tx.createdAt}${tx.note.isNotEmpty ? " • ${tx.note}" : ""}',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_results.isNotEmpty) ...[
                        Text(
                          'Nakladnoylar (${_results.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ..._results.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: NakladnoyListCard(
                              item: item,
                              onTap: () async {
                                await widget.onOpenNakladnoyDetail(item);
                                await _runSearch(_qCtrl.text);
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
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
  final Future<void> Function(String supplier)? onOpenSupplierProfile;

  const LiveSverkaAndStatsSheet({
    super.key,
    required this.api,
    required this.showSnack,
    this.onOpenSupplierProfile,
  });

  @override
  State<LiveSverkaAndStatsSheet> createState() =>
      _LiveSverkaAndStatsSheetState();
}

class _LiveSverkaAndStatsSheetState extends State<LiveSverkaAndStatsSheet> {
  String _mode = 'sverka'; // sverka | 7d | 30d
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _sverkaData;
  Map<String, dynamic>? _periodData;
  bool _loading = true;
  bool _downloadingExcel = false;
  bool _sendingTelegram = false;
  String? _error;

  String get _monthStr => DateFormat('yyyy-MM').format(_selectedMonth);

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
        final d = await widget.api.getLiveSverka(month: _monthStr);
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

  Future<void> _downloadSverkaExcel() async {
    if (_downloadingExcel || _sendingTelegram) return;
    setState(() => _downloadingExcel = true);
    try {
      final filename = 'Sverka_$_monthStr.xlsx';
      final q = {'month': _monthStr};
      await saveAndShareExcel(
        fetchBytes: () =>
            widget.api.downloadExcelBytes('/export/sverka', query: q),
        filename: filename,
        authenticatedDownloadUrl: widget.api
            .buildAuthenticatedDownloadUrl('/export/sverka', query: q),
      );
    } catch (e) {
      widget.showSnack('Excel yuklashda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _downloadingExcel = false);
    }
  }

  Future<void> _sendSverkaTelegram() async {
    if (_downloadingExcel || _sendingTelegram) return;
    setState(() => _sendingTelegram = true);
    try {
      final msg = await widget.api.sendExcelToTelegram(
        reportType: 'sverka',
        month: _monthStr,
      );
      widget.showSnack(msg);
    } catch (e) {
      widget.showSnack('Telegramga yuborishda xatolik: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingTelegram = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.85),
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
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            )
          : OutlinedButton(
              onPressed: () {
                setState(() => _mode = key);
                _loadData();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
    );
  }

  Widget _buildSverkaView(Map<String, dynamic> d) {
    final sups = ((d['suppliers'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final grandTotal = ((d['grand_total'] as num?) ?? 0).toDouble();
    final now = DateTime.now();
    final canGoNext = _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month < now.month);
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Oldingi oy',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month - 1,
                          );
                        });
                        _loadData();
                      },
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        "🗓 $_monthStr (${sups.length} ta postavshik)",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Keyingi oy',
                      visualDensity: VisualDensity.compact,
                      onPressed: canGoNext
                          ? () {
                              setState(() {
                                _selectedMonth = DateTime(
                                  _selectedMonth.year,
                                  _selectedMonth.month + 1,
                                );
                              });
                              _loadData();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Oylik jami to'lov:",
                      style: TextStyle(fontWeight: FontWeight.w700),
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
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: (_downloadingExcel || _sendingTelegram)
                      ? null
                      : _downloadSverkaExcel,
                  icon: const Icon(Icons.table_view_rounded, size: 17),
                  label: Text(
                    _downloadingExcel
                        ? 'Tayyorlanmoqda...'
                        : '📥 $_monthStr Sverka Excel (.xlsx) yuklash',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_downloadingExcel || _sendingTelegram)
                      ? null
                      : _sendSverkaTelegram,
                  icon: _sendingTelegram
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.telegram, size: 18),
                  label: Text(
                    _sendingTelegram
                        ? 'Yuborilmoqda...'
                        : '📤 Telegram botga yuborish',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...sups.map((s) {
          final supName = s['supplier'].toString();
          final cash = ((s['cash_total'] as num?) ?? 0).toDouble();
          final card = ((s['card_total'] as num?) ?? 0).toDouble();
          final xfer = ((s['transfer_total'] as num?) ?? 0).toDouble();
          final tot = ((s['total'] as num?) ?? 0).toDouble();
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radius),
              onTap: widget.onOpenSupplierProfile != null
                  ? () => widget.onOpenSupplierProfile!(supName)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$supName (${s['count']} ta)',
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
                        if (widget.onOpenSupplierProfile != null) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: textSecondaryOf(context)),
                        ],
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
          (s) {
            final supName = s['supplier'].toString();
            return Card(
              child: ListTile(
                dense: true,
                onTap: widget.onOpenSupplierProfile != null
                    ? () => widget.onOpenSupplierProfile!(supName)
                    : null,
                title: Text(
                  '$supName (${s['count']} ta)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${formatUzs(s['total'] as num?, withCurrency: true)} (${((s['percent'] as num?) ?? 0).toStringAsFixed(0)}%)',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (widget.onOpenSupplierProfile != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded,
                          size: 17, color: textSecondaryOf(context)),
                    ],
                  ],
                ),
              ),
            );
          },
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
    SyncBus.remoteChangeTick.addListener(_onRemoteSync);
    _load();
  }

  @override
  void dispose() {
    SyncBus.remoteChangeTick.removeListener(_onRemoteSync);
    super.dispose();
  }

  void _onRemoteSync() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
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
      if (!silent) {
        widget.showSnack(e.toString(), isError: true);
      }
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
        maintainBottomViewPadding: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, sheetBottomPadding(ctx)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: sheetMaxHeight(ctx, fraction: 0.90),
            ),
            child: SingleChildScrollView(
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
                  TextField(
                    controller: supCtrl,
                    decoration: InputDecoration(
                      labelText: 'Postavshik nomi',
                      prefixIcon: const Icon(Icons.storefront_rounded),
                      suffixIcon: buildSupplierInputSuffix(
                        context: ctx,
                        controller: supCtrl,
                        suppliers: _suppliers,
                        onPicked: (picked) async {
                          supCtrl.text = picked;
                        },
                      ),
                    ),
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
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 11),
                            ),
                            onPressed: () => _openAddEntryDialog('debt'),
                            icon: const Icon(Icons.add_circle_outline_rounded,
                                size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Qarz yozish', maxLines: 1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 11),
                            ),
                            onPressed: () => _openAddEntryDialog('payment'),
                            icon: const Icon(Icons.task_alt_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text("Qarz to'lash", maxLines: 1),
                            ),
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

  Future<void> _pickAndUploadYesPosFile() async {
    setState(() => _submitting = true);
    try {
      final picked = await pickYesPosDocument();
      if (picked == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      final res = await widget.api.createPrixodFromFile(
        bytes: picked.bytes,
        filename: picked.filename,
        publishToGroup: _publishToGroup,
      );
      widget.showSnack(
        res['message']?.toString() ?? 'Fayldan ITOG 👑 yaratildi!',
      );
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
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.85),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickAndUploadYesPosFile,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text("📂 YesPOS fayl (.xlsx / .csv) yuklash"),
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

// ============================================================================
// SUPPLIERS, ALIASES & AI ROUNDING SETTINGS SHEET (/settings/...)
// ============================================================================

class SupplierAndRoundingSettingsSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final void Function(String, {bool isError}) showSnack;

  const SupplierAndRoundingSettingsSheet({
    super.key,
    required this.api,
    required this.showSnack,
  });

  @override
  State<SupplierAndRoundingSettingsSheet> createState() =>
      _SupplierAndRoundingSettingsSheetState();
}

class _SupplierAndRoundingSettingsSheetState
    extends State<SupplierAndRoundingSettingsSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _aliasCtrl = TextEditingController();
  List<Map<String, dynamic>> _configs = [];
  String _roundMode = 'floor_1000';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        widget.api.getSupplierConfigs(),
        widget.api.getRoundMode(),
      ]);
      if (mounted) {
        setState(() {
          _configs = res[0] as List<Map<String, dynamic>>;
          _roundMode = res[1] as String;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      widget.showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _changeRoundMode(String newMode) async {
    setState(() {
      _roundMode = newMode;
      _saving = true;
    });
    try {
      final saved = await widget.api.setRoundMode(newMode);
      if (mounted) setState(() => _roundMode = saved);
      widget.showSnack('✅ Yaxlitlash qoidasi saqlandi!');
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSupplier() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      widget.showSnack('Postavshik nomini kiriting', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveSupplierConfig(
        displayName: name,
        aliases: _aliasCtrl.text.trim(),
      );
      _nameCtrl.clear();
      _aliasCtrl.clear();
      widget.showSnack('✅ Postavshik va taxalluslar saqlandi!');
      await _load();
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSupplier(int id, String name) async {
    setState(() => _saving = true);
    try {
      await widget.api.deleteSupplierConfig(id);
      widget.showSnack("🗑 «$name» ro'yxatdan o'chirildi");
      await _load();
    } catch (e) {
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "🏢 Postavshiklar va Yaxlitlash",
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
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: ListView(
                    children: [
                      // 1. AI Summa Yaxlitlash (round_mode)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_fix_high_rounded,
                                      color: AppTokens.brand, size: 19),
                                  SizedBox(width: 8),
                                  Text(
                                    'AI Summa Yaxlitlash Qoidasi',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              HisobchiCustomDropdown<String>(
                                value: (_roundMode == 'nearest_1000' ||
                                        _roundMode == 'none')
                                    ? _roundMode
                                    : 'floor_1000',
                                labelText: 'Yaxlitlash turi',
                                sheetTitle: 'AI summa yaxlitlash qoidasi',
                                enabled: widget.api.canWrite && !_saving,
                                options: const [
                                  CustomDropdownOption<String>(
                                    value: 'floor_1000',
                                    label: "1 000 so'mga pastga",
                                    subtitle: 'Masalan: 192 640 → 192 000',
                                    icon: Icons.south_east_rounded,
                                    accentColor: AppTokens.brand,
                                  ),
                                  CustomDropdownOption<String>(
                                    value: 'nearest_1000',
                                    label: "1 000 so'mga yaqiniga",
                                    subtitle: 'Masalan: 192 640 → 193 000',
                                    icon: Icons.swap_vert_rounded,
                                    accentColor: AppTokens.cashGreen,
                                  ),
                                  CustomDropdownOption<String>(
                                    value: 'none',
                                    label: 'Yaxlitlanmasin',
                                    subtitle: 'Rasmdagi aniq summa saqlanadi',
                                    icon: Icons.adjust_rounded,
                                    accentColor: AppTokens.cardBlue,
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != _roundMode) {
                                    _changeRoundMode(v);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2. Postavshiklar va Taxalluslar (aliases)
                      if (widget.api.canWrite)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.storefront_rounded,
                                        color: AppTokens.cashGreen, size: 19),
                                    SizedBox(width: 8),
                                    Text(
                                      "Postavshik va Taxallus qo'shish",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Postavshik nomi',
                                    hintText: 'Masalan: Ummun',
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _aliasCtrl,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Taxalluslar (vergul bilan ajratib yozing)',
                                    hintText: 'UMMUN, ITTIN, ИТТИН, УММУН',
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _saveSupplier,
                                  icon: const Icon(Icons.save_rounded, size: 18),
                                  label: Text(_saving
                                      ? 'Saqlanmoqda...'
                                      : 'Saqlash / Yangilash'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),

                      Text(
                        "Saqlangan postavshiklar (${_configs.length} ta) — tahrirlash uchun ustiga bosing:",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._configs.map((c) {
                        final id = (c['id'] as num).toInt();
                        final name = (c['display_name'] ?? '').toString();
                        final aliases = (c['aliases'] ?? '').toString();
                        return Card(
                          child: ListTile(
                            onTap: widget.api.canWrite
                                ? () {
                                    setState(() {
                                      _nameCtrl.text = name;
                                      _aliasCtrl.text = aliases;
                                    });
                                  }
                                : null,
                            title: Text(
                              name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(
                              aliases.isNotEmpty
                                  ? 'Taxalluslar: $aliases'
                                  : 'Taxallus kiritilmagan',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: widget.api.canWrite
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 20,
                                      color: AppTokens.dangerRed,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => _deleteSupplier(id, name),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTabPage extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabPage({required this.child});

  @override
  State<_KeepAliveTabPage> createState() => _KeepAliveTabPageState();
}

class _KeepAliveTabPageState extends State<_KeepAliveTabPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ============================================================================
// SUPPLIERS DIRECTORY VIEW (/suppliers/directory) INSIDE TA'MINOTCHILAR TAB
// ============================================================================

class SuppliersDirectoryView extends StatefulWidget {
  final HisobchiApiClient api;
  final Future<void> Function(String supplier) onOpenSupplierProfile;
  final void Function(String, {bool isError}) showSnack;

  const SuppliersDirectoryView({
    super.key,
    required this.api,
    required this.onOpenSupplierProfile,
    required this.showSnack,
  });

  @override
  State<SuppliersDirectoryView> createState() => _SuppliersDirectoryViewState();
}

class _SuppliersDirectoryViewState extends State<SuppliersDirectoryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _mode = 'all'; // all | debt | active

  @override
  void initState() {
    super.initState();
    SyncBus.remoteChangeTick.addListener(_onRemoteSync);
    _load();
  }

  @override
  void dispose() {
    SyncBus.remoteChangeTick.removeListener(_onRemoteSync);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onRemoteSync() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.api.getSuppliersDirectory();
      if (mounted) {
        setState(() {
          _data = res;
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

  Widget _modeChip(String key, String label) {
    final sel = _mode == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      selected: sel,
      onSelected: (_) => setState(() => _mode = key),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    final d = _data ?? const <String, dynamic>{};
    final allSuppliers = ((d['suppliers'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final totalCount = ((d['suppliers_count'] as num?) ?? allSuppliers.length)
        .toInt();
    final grandTotal = ((d['grand_total'] as num?) ?? 0).toDouble();
    final totalDebt = ((d['total_unpaid_debt'] as num?) ?? 0).toDouble();
    final totalNasiya = ((d['total_nasiya_balance'] as num?) ?? 0).toDouble();

    final filtered = allSuppliers.where((s) {
      final name = (s['supplier_name'] ?? '').toString();
      if (_query.isNotEmpty &&
          !name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      final debtAmt = ((s['unpaid_debt_amount'] as num?) ?? 0).toDouble();
      final nasAmt = ((s['nasiya_balance'] as num?) ?? 0).toDouble();
      final cnt = ((s['total_count'] as num?) ?? 0).toInt();
      if (_mode == 'debt') return debtAmt > 0 || nasAmt > 0;
      if (_mode == 'active') return cnt > 0;
      return true;
    }).toList();

    final (amberFg, amberBg, amberBorder) =
        AppTokens.semanticSurface(context, AppTokens.debtAmber);
    final (cashFg, cashBg, _) =
        AppTokens.semanticSurface(context, AppTokens.cashGreen);
    final (cardFg, cardBg, _) =
        AppTokens.semanticSurface(context, AppTokens.cardBlue);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTokens.heroGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "BARCHA TA'MINOTCHILAR ($totalCount TA)",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatUzs(grandTotal, withCurrency: true),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      fontFeatures: AppTokens.tabularNums,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "To'lanmagan qarz: ${formatUzs(totalDebt, withCurrency: true)}"
                  "${totalNasiya > 0 ? ' • Nasiya: ${formatUzs(totalNasiya, withCurrency: true)}' : ''}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: "Ta'minotchi qidirish...",
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _modeChip('all', 'Barchasi ($totalCount)'),
                const SizedBox(width: 6),
                _modeChip('debt', 'Qarzi bor'),
                const SizedBox(width: 6),
                _modeChip('active', 'Oldi-berdi bor'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                "Mos ta'minotchi topilmadi.",
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondaryOf(context)),
              ),
            )
          else
            ...filtered.map((s) {
              final name = (s['supplier_name'] ?? '').toString();
              final cnt = ((s['total_count'] as num?) ?? 0).toInt();
              final tot = ((s['total_amount'] as num?) ?? 0).toDouble();
              final cash = ((s['cash_amount'] as num?) ?? 0).toDouble();
              final card = ((s['card_amount'] as num?) ?? 0).toDouble();
              final xfer = ((s['transfer_amount'] as num?) ?? 0).toDouble();
              final debtAmt =
                  ((s['unpaid_debt_amount'] as num?) ?? 0).toDouble();
              final nasBal = ((s['nasiya_balance'] as num?) ?? 0).toDouble();
              final lastDate = s['last_date']?.toString();

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: TactileScaleTap(
                  pressedScale: 0.985,
                  haptic: false,
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      onTap: () async {
                        await widget.onOpenSupplierProfile(name);
                        await _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      AppTokens.brand.withValues(alpha: 0.14),
                                  child: const Icon(Icons.storefront_rounded,
                                      size: 18, color: AppTokens.brand),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: textPrimaryOf(context),
                                        ),
                                      ),
                                      Text(
                                        cnt > 0
                                            ? '$cnt ta chek${lastDate != null ? ' • Oxirgi: $lastDate' : ''}'
                                            : "Hali nakladnoy yo'q",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatUzs(tot, withCurrency: true),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                        color: AppTokens.brand,
                                        fontFeatures: AppTokens.tabularNums,
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: textSecondaryOf(context),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (cash > 0 ||
                                card > 0 ||
                                xfer > 0 ||
                                debtAmt > 0 ||
                                nasBal > 0) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 5,
                                children: [
                                  if (cash > 0)
                                    _miniBadge(
                                      'Naqd: ${formatUzs(cash)}',
                                      cashFg,
                                      cashBg,
                                    ),
                                  if (card + xfer > 0)
                                    _miniBadge(
                                      'Karta/O\'tkazma: ${formatUzs(card + xfer)}',
                                      cardFg,
                                      cardBg,
                                    ),
                                  if (debtAmt > 0 || nasBal > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: amberBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: amberBorder),
                                      ),
                                      child: Text(
                                        'Qarz: ${formatUzs(debtAmt + (nasBal > 0 ? nasBal : 0))}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: amberFg,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _miniBadge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ============================================================================
// SUPPLIER PROFILE SHEET (/suppliers/profile)
// ============================================================================

class SupplierProfileSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final String supplierName;
  final Future<void> Function(NakladnoyItem) onOpenNakladnoyDetail;
  final Future<void> Function(String supplier)? onOpenSupplierProfile;

  const SupplierProfileSheet({
    super.key,
    required this.api,
    required this.supplierName,
    required this.onOpenNakladnoyDetail,
    this.onOpenSupplierProfile,
  });

  @override
  State<SupplierProfileSheet> createState() => _SupplierProfileSheetState();
}

class _SupplierProfileSheetState extends State<SupplierProfileSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _changed = false;
  String? _error;
  String _filter = 'all'; // all | cash | card | transfer | debt
  String _datePreset = 'all'; // all | today | 7d | month | custom
  String? _dateFrom;
  String? _dateTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.getSupplierProfile(
        widget.supplierName,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (mounted) {
        setState(() {
          _data = res;
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

  String _isoDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    String? dFrom;
    String? dTo;
    if (preset == 'today') {
      dFrom = dTo = _isoDate(now);
    } else if (preset == '7d') {
      dFrom = _isoDate(now.subtract(const Duration(days: 6)));
      dTo = _isoDate(now);
    } else if (preset == 'month') {
      dFrom = _isoDate(DateTime(now.year, now.month, 1));
      dTo = _isoDate(now);
    }
    setState(() {
      _datePreset = preset;
      _dateFrom = dFrom;
      _dateTo = dTo;
    });
    _load();
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final initialStart = _dateFrom != null
        ? (DateTime.tryParse(_dateFrom!) ??
            now.subtract(const Duration(days: 6)))
        : now.subtract(const Duration(days: 6));
    final initialEnd =
        _dateTo != null ? (DateTime.tryParse(_dateTo!) ?? now) : now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _datePreset = 'custom';
      _dateFrom = _isoDate(picked.start);
      _dateTo = _isoDate(picked.end);
    });
    _load();
  }

  Widget _dateChip(String key, String label) {
    final sel = _datePreset == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      selected: sel,
      onSelected: (_) {
        if (key == 'custom') {
          _pickCustomDateRange();
        } else {
          _applyDatePreset(key);
        }
      },
    );
  }

  Widget _statBox(
    BuildContext context, {
    required String label,
    required double amount,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    final (fg, bg, border) = AppTokens.semanticSurface(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '$label ($count ta)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatUzs(amount, withCurrency: true),
              maxLines: 1,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: textPrimaryOf(context),
                fontFeatures: AppTokens.tabularNums,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPill(String key, String label) {
    final sel = _filter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      selected: sel,
      onSelected: (_) => setState(() => _filter = key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final supTitle = (d?['supplier_name'] ?? widget.supplierName).toString();
    final totalCount = ((d?['total_count'] as num?) ?? 0).toInt();
    final totalAmount = ((d?['total_amount'] as num?) ?? 0).toDouble();
    final cashAmt = ((d?['cash_amount'] as num?) ?? 0).toDouble();
    final cashCnt = ((d?['cash_count'] as num?) ?? 0).toInt();
    final cardAmt = ((d?['card_amount'] as num?) ?? 0).toDouble();
    final cardCnt = ((d?['card_count'] as num?) ?? 0).toInt();
    final xferAmt = ((d?['transfer_amount'] as num?) ?? 0).toDouble();
    final xferCnt = ((d?['transfer_count'] as num?) ?? 0).toInt();
    final debtAmt = ((d?['unpaid_debt_amount'] as num?) ?? 0).toDouble();
    final debtCnt = ((d?['unpaid_debt_count'] as num?) ?? 0).toInt();
    final nasiyaBal = ((d?['nasiya_balance'] as num?) ?? 0).toDouble();
    final firstDate = d?['first_date']?.toString();
    final lastDate = d?['last_date']?.toString();

    final items = ((d?['items'] as List?) ?? const [])
        .map((e) => NakladnoyItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((n) {
      if (_filter == 'cash') return !n.isDebt && n.paymentMethod == 'cash';
      if (_filter == 'card') return !n.isDebt && n.paymentMethod == 'card';
      if (_filter == 'transfer') {
        return !n.isDebt && n.paymentMethod == 'transfer';
      }
      if (_filter == 'debt') return n.isDebt;
      return true;
    }).toList();

    final (amberFg, amberBg, amberBorder) =
        AppTokens.semanticSurface(context, AppTokens.debtAmber);

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          bottom: sheetBottomPadding(context),
        ),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppTokens.heroGradient,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (firstDate != null && lastDate != null)
                          Text(
                            '$firstDate — $lastDate ($totalCount ta chek)',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondaryOf(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _loading
                        ? null
                        : () async {
                            try {
                              final safe = supTitle.replaceAll(
                                  RegExp(r'[^A-Za-z0-9_-]'), '_');
                              final fname = 'Sverka_$safe.pdf';
                              final dlUrl = widget.api
                                  .buildAuthenticatedDownloadUrl(
                                '/suppliers/sverka-pdf',
                                query: {
                                  'supplier': supTitle,
                                  if (_dateFrom != null)
                                    'date_from': _dateFrom!,
                                  if (_dateTo != null) 'date_to': _dateTo!,
                                },
                              );
                              await saveAndShareBinaryFile(
                                fetchBytes: () =>
                                    widget.api.downloadSupplierSverkaPdf(
                                  supTitle,
                                  dateFrom: _dateFrom,
                                  dateTo: _dateTo,
                                ),
                                filename: fname,
                                authenticatedDownloadUrl: dlUrl,
                                shareText: 'Akt-Sverka: $supTitle',
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('PDF'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _dateChip('all', 'Barchasi'),
                    const SizedBox(width: 6),
                    _dateChip('today', 'Bugun'),
                    const SizedBox(width: 6),
                    _dateChip('7d', '7 kun'),
                    const SizedBox(width: 6),
                    _dateChip('month', 'Shu oy'),
                    const SizedBox(width: 6),
                    _dateChip(
                      'custom',
                      _datePreset == 'custom' &&
                              _dateFrom != null &&
                              _dateTo != null
                          ? '📅 $_dateFrom .. $_dateTo'
                          : '📅 Sana tanlash',
                    ),
                  ],
                ),
              ),
              if (_dateFrom != null && _dateTo != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🗓 Davr: $_dateFrom — $_dateTo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textSecondaryOf(context),
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _applyDatePreset('all'),
                      child: const Text('Tozalash'),
                    ),
                  ],
                ),
              ],
              if (_loading && _data != null) ...[
                const SizedBox(height: 4),
                const LinearProgressIndicator(minHeight: 2.5),
              ],
              const SizedBox(height: 8),
              if (_loading && _data == null)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null && _data == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: AppTokens.heroGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'JAMI AYLANMA',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                formatUzs(totalAmount, withCurrency: true),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Jami $totalCount ta nakladnoy',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _statBox(
                              context,
                              label: 'Naqd',
                              amount: cashAmt,
                              count: cashCnt,
                              color: AppTokens.cashGreen,
                              icon: Icons.payments_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statBox(
                              context,
                              label: 'Karta',
                              amount: cardAmt,
                              count: cardCnt,
                              color: AppTokens.cardBlue,
                              icon: Icons.credit_card_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _statBox(
                              context,
                              label: "O'tkazma",
                              amount: xferAmt,
                              count: xferCnt,
                              color: AppTokens.transferPurple,
                              icon: Icons.account_balance_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statBox(
                              context,
                              label: 'Qarzga',
                              amount: debtAmt,
                              count: debtCnt,
                              color: AppTokens.debtAmber,
                              icon: Icons.push_pin_rounded,
                            ),
                          ),
                        ],
                      ),
                      if (nasiyaBal != 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: amberBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: amberBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.menu_book_rounded,
                                  size: 17, color: amberFg),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Nasiya daftari qoldig\'i:',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: amberFg,
                                  ),
                                ),
                              ),
                              Text(
                                formatUzs(nasiyaBal, withCurrency: true),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: amberFg,
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterPill('all', 'Barchasi ($totalCount)'),
                            const SizedBox(width: 6),
                            _filterPill('cash', 'Naqd ($cashCnt)'),
                            const SizedBox(width: 6),
                            _filterPill('card', 'Karta ($cardCnt)'),
                            const SizedBox(width: 6),
                            _filterPill('transfer', "O'tkazma ($xferCnt)"),
                            const SizedBox(width: 6),
                            _filterPill('debt', 'Qarzga ($debtCnt)'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            "Bu bo'limda nakladnoylar topilmadi.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textSecondaryOf(context)),
                          ),
                        )
                      else
                        ...items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: NakladnoyListCard(
                              item: item,
                              onTap: () async {
                                await widget.onOpenNakladnoyDetail(item);
                                _changed = true;
                                await _load();
                              },
                            ),
                          ),
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
}

// ============================================================================
// TELEGRAM GROUPS, BOT PREFS, RBAC ROLES & BACKUP HUB SHEET
// ============================================================================

class TelegramGroupsAndBotSettingsSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final void Function(String, {bool isError}) showSnack;

  const TelegramGroupsAndBotSettingsSheet({
    super.key,
    required this.api,
    required this.showSnack,
  });

  @override
  State<TelegramGroupsAndBotSettingsSheet> createState() =>
      _TelegramGroupsAndBotSettingsSheetState();
}

class _TelegramGroupsAndBotSettingsSheetState
    extends State<TelegramGroupsAndBotSettingsSheet> {
  Map<String, dynamic>? _hub;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getTelegramHubSettings();
      if (!mounted) return;
      setState(() {
        _hub = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _runAction(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final msg = await action();
      if (!mounted) return;
      widget.showSnack(msg);
      await _load();
    } catch (e) {
      if (!mounted) return;
      widget.showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTelegramGroupPicker(Map<String, dynamic> grp) async {
    final bindUrl = (grp['bind_url'] ?? '').toString();
    if (bindUrl.isEmpty) {
      widget.showSnack("Telegram havolasi topilmadi", isError: true);
      return;
    }
    final opened = await openExternalTelegramUrl(bindUrl);
    if (!mounted) return;
    if (opened) {
      widget.showSnack(
        "Telegram ochildi. Guruhni tanlagach, shu yerdan Yangilash tugmasini bosing.",
      );
    } else {
      widget.showSnack(
        "Telegramni ochib bo'lmadi. Qo'lda Chat ID orqali ulashingiz mumkin.",
        isError: true,
      );
    }
  }

  Future<void> _openManualBindDialog(Map<String, dynamic> grp) async {
    final role = (grp['role'] ?? 'nakladnoy').toString();
    final roleTitle = (grp['role_title'] ?? role).toString();
    final idCtrl = TextEditingController(
      text: grp['chat_id'] != null ? grp['chat_id'].toString() : '-100',
    );
    final titleCtrl = TextEditingController(
      text: (grp['title'] ?? '').toString(),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('$roleTitle — Chat ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Guruh ichida botga /group_id yozsangiz aniq Chat ID chiqadi (masalan: -1001234567890).",
              style: TextStyle(fontSize: 12.5, color: textSecondaryOf(dlgCtx)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(
                labelText: 'Guruh Chat ID (-100...)',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Guruh nomi (ixtiyoriy)',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final parsedId = int.tryParse(idCtrl.text.trim());
    if (parsedId == null) {
      widget.showSnack("To'g'ri Chat ID kiriting (masalan -100...)", isError: true);
      return;
    }
    await _runAction(
      () => widget.api.bindTelegramGroup(
        role: role,
        chatId: parsedId,
        title: titleCtrl.text.trim(),
      ),
    );
  }

  Future<void> _confirmUnbindGroup(Map<String, dynamic> grp) async {
    final role = (grp['role'] ?? '').toString();
    final roleTitle = (grp['role_title'] ?? role).toString();
    final title = (grp['title'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('$roleTitle uzilsinmi?'),
        content: Text('«$title» guruhini ushbu vazifadan uzmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTokens.dangerRed),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: const Text('Ha, uzilsin'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(() => widget.api.unbindTelegramGroup(role));
  }

  Future<void> _openAddRoleDialog() async {
    final uidCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    var pickedRole = 'kassir';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (stCtx, setDlgState) => AlertDialog(
          title: const Text("Xodim qo'shish (RBAC)"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: uidCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Telegram User ID',
                  hintText: 'Botga /start yozganda ko\'rinadi',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Xodim ismi',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Rolni tanlang:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in const [
                    ('kassir', '💼 Kassir'),
                    ('admin', '👑 Admin'),
                    ('viewer', '👁 Kuzatuvchi'),
                  ])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: pickedRole == item.$1,
                      onSelected: (_) =>
                          setDlgState(() => pickedRole = item.$1),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: const Text('Saqlash'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final parsedUid = int.tryParse(uidCtrl.text.trim());
    if (parsedUid == null || parsedUid <= 0) {
      widget.showSnack("To'g'ri Telegram User ID kiriting", isError: true);
      return;
    }
    await _runAction(
      () => widget.api.saveUserRole(
        userId: parsedUid,
        role: pickedRole,
        label: labelCtrl.text.trim(),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> grp) {
    final bound = grp['bound'] == true;
    final role = (grp['role'] ?? '').toString();
    final roleTitle = (grp['role_title'] ?? role).toString();
    final title = (grp['title'] ?? '').toString();
    final chatId = grp['chat_id'];
    final accent = bound ? AppTokens.cashGreen : AppTokens.debtAmber;
    final (fg, bg, border) = AppTokens.semanticSurface(context, accent);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  roleTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: fg,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  bound ? '✅ Ulangan' : "⚠️ Bog'lanmagan",
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            bound
                ? '$title (ID: $chatId)'
                : "Hali Telegram guruhi tanlanmagan.",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: bound ? null : textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed:
                    _busy ? null : () => _openTelegramGroupPicker(grp),
                icon: const Icon(Icons.telegram, size: 17),
                label: Text(bound ? 'Almashtirish' : 'Telegramda tanlash'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _busy ? null : () => _openManualBindDialog(grp),
                icon: const Icon(Icons.tag_rounded, size: 16),
                label: const Text('Chat ID'),
              ),
              if (bound) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _runAction(
                            () => widget.api.testTelegramGroup(role),
                          ),
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: const Text('Test'),
                ),
                IconButton(
                  tooltip: 'Uzish',
                  onPressed:
                      _busy ? null : () => _confirmUnbindGroup(grp),
                  icon: const Icon(
                    Icons.link_off_rounded,
                    color: AppTokens.dangerRed,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrefsSection(
    Map<String, dynamic> prefs,
    Map<String, dynamic> aiStats,
  ) {
    final apkPost = prefs['apk_post_to_group'] != false;
    final autoConfirm = prefs['auto_confirm'] != false;
    final arEnabled = prefs['auto_report_enabled'] == true;
    final arTime = (prefs['auto_report_time'] ?? '23:00').toString();
    final calls = (aiStats['calls'] as num?)?.toInt() ?? 0;
    final monthTokens = (aiStats['month_tokens'] as num?)?.toInt() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '⚙️ Bot, Avto-hisobot va Backup',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'APK/Mini App dan guruhga yuborish',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Saqlangan nakladnoylar Nakladnoy guruhiga ham tushadi',
                style: TextStyle(fontSize: 12),
              ),
              value: apkPost,
              onChanged: _busy
                  ? null
                  : (v) => _runAction(
                        () => widget.api.updateBotPrefs(apkPostToGroup: v),
                      ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Botda tez rejim (Avto-tasdiqlash)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                "AI aniq o'qigan nakladnoyni kutmasdan tasdiqlash",
                style: TextStyle(fontSize: 12),
              ),
              value: autoConfirm,
              onChanged: _busy
                  ? null
                  : (v) => _runAction(
                        () => widget.api.updateBotPrefs(autoConfirm: v),
                      ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Kunlik avto-hisobot',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Kassa / Admin guruhiga soat $arTime da yuboriladi',
                style: const TextStyle(fontSize: 12),
              ),
              value: arEnabled,
              onChanged: _busy
                  ? null
                  : (v) => _runAction(
                        () => widget.api.updateBotPrefs(autoReportEnabled: v),
                      ),
            ),
            if (arEnabled) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in const ['21:00', '22:00', '23:00'])
                    ChoiceChip(
                      label: Text(t),
                      selected: arTime == t,
                      onSelected: _busy
                          ? null
                          : (_) => _runAction(
                                () => widget.api.updateBotPrefs(
                                  autoReportTime: t,
                                ),
                              ),
                    ),
                ],
              ),
            ],
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '🤖 Bugun AI: $calls ta | Oy token: ${formatUzs(monthTokens)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => _runAction(() => widget.api.triggerManualBackup()),
              icon: const Icon(Icons.backup_rounded),
              label: const Text('💾 Hozir backup olish (Telegram botga)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolesSection(List<Map<String, dynamic>> users) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '👥 Xodimlar va Rollar',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _busy ? null : _openAddRoleDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                  label: const Text("Qo'shish"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...users.map((u) {
              final isSuper = u['is_super_admin'] == true;
              final uid = (u['user_id'] as num).toInt();
              final label = (u['label'] ?? '$uid').toString();
              final roleLbl = (u['role_label'] ?? u['role'] ?? '').toString();
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor: AppTokens.brand.withValues(alpha: 0.14),
                  child: Icon(
                    isSuper ? Icons.verified_user_rounded : Icons.person_rounded,
                    size: 18,
                    color: AppTokens.brand,
                  ),
                ),
                title: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('$roleLbl • ID: $uid'),
                trailing: isSuper
                    ? null
                    : IconButton(
                        tooltip: "O'chirish",
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppTokens.dangerRed,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _runAction(
                                  () => widget.api.deleteUserRole(uid),
                                ),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = ((_hub?['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final prefs = _hub?['prefs'] is Map
        ? Map<String, dynamic>.from(_hub!['prefs'] as Map)
        : <String, dynamic>{};
    final aiStats = _hub?['ai_stats'] is Map
        ? Map<String, dynamic>.from(_hub!['ai_stats'] as Map)
        : <String, dynamic>{};
    final users = ((_hub?['users'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final botUsername = (_hub?['bot_username'] ?? 'hisobchi_my_bot').toString();

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, sheetBottomPadding(context)),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_rounded, color: AppTokens.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Telegram Guruhlar va Boshqaruv',
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '@$botUsername bilan sinxron',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yangilash',
                    onPressed: _loading || _busy ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTokens.dangerRed),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      const Text(
                        '🔗 Telegram Guruhlar',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...groups.map(_buildGroupCard),
                      const SizedBox(height: 6),
                      _buildPrefsSection(prefs, aiStats),
                      const SizedBox(height: 10),
                      _buildRolesSection(users),
                      const SizedBox(height: 14),
                    ],
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
// AI VOICE & QUICK COMMAND SHEET
// ============================================================================

class VoiceCommandSheet extends StatefulWidget {
  final HisobchiApiClient api;

  const VoiceCommandSheet({super.key, required this.api});

  @override
  State<VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends State<VoiceCommandSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  bool _recording = false;
  bool _parsing = false;
  int _elapsedSec = 0;
  Timer? _recTimer;
  Map<String, dynamic>? _parsed;
  String? _error;

  @override
  void dispose() {
    _recTimer?.cancel();
    if (_recording) {
      cancelVoiceRecording();
    }
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_parsing) return;
    if (!_recording) {
      setState(() {
        _error = null;
        _parsed = null;
      });
      try {
        final status = await startVoiceRecording();
        if (!mounted) return;
        if (status == 'PERMISSION_REQUESTED') {
          setState(() =>
              _error = "Mikrofon ruxsatini tasdiqlab, yana bir marta bosing");
          return;
        }
        if (status != 'STARTED') {
          setState(() => _error = "Ushbu qurilmada matn bilan yozing");
          return;
        }
        HapticFeedback.mediumImpact();
        setState(() {
          _recording = true;
          _elapsedSec = 0;
        });
        _recTimer?.cancel();
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _elapsedSec++);
          if (_elapsedSec >= 58) {
            _toggleRecord();
          }
        });
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    } else {
      _recTimer?.cancel();
      HapticFeedback.lightImpact();
      setState(() {
        _recording = false;
        _parsing = true;
      });
      try {
        final audio = await stopVoiceRecording();
        if (audio == null) {
          if (mounted) {
            setState(() {
              _parsing = false;
              _error = "Ovoz juda qisqa bo'ldi, qaytadan ayting";
            });
          }
          return;
        }
        final res = await widget.api.parseVoiceCommand(
          audioBytes: audio.bytes,
          filename: audio.filename,
        );
        if (!mounted) return;
        _applyParsedResponse(res);
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _parsing = false);
      }
    }
  }

  Future<void> _parseText() async {
    final txt = _textCtrl.text.trim();
    if (txt.isEmpty || _parsing) return;
    setState(() {
      _parsing = true;
      _error = null;
      _parsed = null;
    });
    try {
      final res = await widget.api.parseVoiceCommand(text: txt);
      if (!mounted) return;
      _applyParsedResponse(res);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _applyParsedResponse(Map<String, dynamic> res) {
    final intent = (res['intent'] ?? 'unknown').toString();
    if (intent == 'unknown') {
      final msg = (res['message'] ?? '').toString();
      setState(() {
        _error = msg.isNotEmpty
            ? msg
            : 'Buyruq tushunilmadi (masalan: "Cola 450 ming" yoki "Kassaga 2 mln oldim")';
      });
      return;
    }
    setState(() => _parsed = res);
  }

  String _intentSummary(Map<String, dynamic> p) {
    final intent = (p['intent'] ?? '').toString();
    final amt = (p['amount'] as num?)?.toDouble();
    final sup = (p['supplier_name'] ?? '').toString();
    final amtStr = amt != null ? formatUzs(amt, withCurrency: true) : '';
    switch (intent) {
      case 'cash_in':
        return '➕ Kirim: $amtStr';
      case 'kassa_debt':
        return '🏦 Kassadan qarz: $amtStr';
      case 'kassa_repay':
        return '↩️ Qarz qaytdi: $amtStr';
      case 'pay_supplier':
        return '🧾 Nakladnoy: ${sup.isNotEmpty ? sup : "Postavshik"} • $amtStr';
      case 'count_cash':
        return '🧮 Sanalgan pul: $amtStr';
      case 'status':
        return '📊 Kassa holatini yangilash';
      default:
        return intent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (okFg, okBg, okBorder) =
        AppTokens.semanticSurface(context, AppTokens.cashGreen);
    final (errFg, errBg, errBorder) =
        AppTokens.semanticSurface(context, AppTokens.dangerRed);

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 6, 20, sheetBottomPadding(context)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: sheetMaxHeight(context, fraction: 0.85),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic_rounded, color: AppTokens.brandViolet),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'AI Ovozli buyruq',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Masalan: «Cola 450 ming» yoki «Kassaga 2 million oldim»',
                  style: TextStyle(
                      fontSize: 12.5, color: textSecondaryOf(context)),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TactileScaleTap(
                      child: GestureDetector(
                        onTap: _toggleRecord,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: _recording ? 84 : 74,
                          height: _recording ? 84 : 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _recording
                                ? AppTokens.dangerRed
                                : AppTokens.brandViolet,
                            boxShadow: [
                              BoxShadow(
                                color: (_recording
                                        ? AppTokens.dangerRed
                                        : AppTokens.brandViolet)
                                    .withValues(alpha: 0.38),
                                blurRadius: _recording ? 26 : 16,
                                spreadRadius: _recording ? 4 : 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            _recording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _recording
                        ? '🔴 Yozilmoqda (${_elapsedSec}s) — to\'xtatish uchun bosing'
                        : (_parsing
                            ? '✨ AI tahlil qilmoqda...'
                            : 'Gapirish uchun mikrofonni bosing'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _recording
                          ? AppTokens.dangerRed
                          : textSecondaryOf(context),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        onSubmitted: (_) => _parseText(),
                        decoration: const InputDecoration(
                          hintText: 'Yoki qisqa buyruq yozing...',
                          prefixIcon: Icon(Icons.bolt_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _parsing ? null : _parseText,
                      icon: _parsing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: errBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: errBorder),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: errFg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (_parsed != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: okBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: okBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((_parsed!['transcript'] ?? '')
                            .toString()
                            .isNotEmpty)
                          Text(
                            '«${_parsed!['transcript']}»',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondaryOf(context),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _intentSummary(_parsed!),
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: okFg,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.cashGreen,
                          ),
                          onPressed: () => Navigator.pop(context, _parsed),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Bajarish'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// KASSA DEBT LEDGER HISTORY SHEET
// ============================================================================

class KassaDebtHistorySheet extends StatefulWidget {
  final HisobchiApiClient api;
  final bool canWrite;

  const KassaDebtHistorySheet({
    super.key,
    required this.api,
    required this.canWrite,
  });

  @override
  State<KassaDebtHistorySheet> createState() => _KassaDebtHistorySheetState();
}

class _KassaDebtHistorySheetState extends State<KassaDebtHistorySheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.getKassaDebtHistory();
      if (mounted) {
        setState(() {
          _data = res;
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
    final borrowed = ((_data?['total_borrowed'] as num?) ?? 0).toDouble();
    final repaid = ((_data?['total_repaid'] as num?) ?? 0).toDouble();
    final outstanding = ((_data?['outstanding'] as num?) ?? 0).toDouble();
    final items = ((_data?['items'] as List?) ?? const [])
        .map((e) => CashTxItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 6, 18, sheetBottomPadding(context)),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded,
                      color: AppTokens.debtAmber),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Kassa qarz tarixi',
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
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Hozirgi qarz:',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              formatUzs(outstanding, withCurrency: true),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: outstanding > 0
                                    ? AppTokens.debtAmber
                                    : AppTokens.cashGreen,
                                fontFeatures: AppTokens.tabularNums,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Jami olingan: ${formatUzs(borrowed)}  •  Qaytarilgan: ${formatUzs(repaid)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: textSecondaryOf(context),
                          ),
                        ),
                        if (widget.canWrite && outstanding > 0) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTokens.cashGreen),
                            onPressed: () =>
                                Navigator.pop(context, outstanding),
                            icon: const Icon(Icons.assignment_return_rounded),
                            label: const Text('Kassaga qaytarish'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Kassa qarzi tarixi bo\'sh',
                            style: TextStyle(color: textSecondaryOf(context)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (ctx, i) {
                            final tx = items[i];
                            final isBorrow = tx.sourceType == 'kassa_debt';
                            return Card(
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  isBorrow
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  color: isBorrow
                                      ? AppTokens.debtAmber
                                      : AppTokens.cashGreen,
                                ),
                                title: Text(
                                  '${isBorrow ? "Olingan" : "Qaytarilgan"} • ${formatUzs(tx.amount, withCurrency: true)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  '${tx.createdAt} (Smena #${tx.sessionId})${tx.note.isNotEmpty ? "\n${tx.note}" : ""}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OFFLINE QUEUE MANAGEMENT SHEET
// ============================================================================

class OfflineQueueSheet extends StatefulWidget {
  final HisobchiApiClient api;
  final Future<void> Function() onSyncNow;

  const OfflineQueueSheet({
    super.key,
    required this.api,
    required this.onSyncNow,
  });

  @override
  State<OfflineQueueSheet> createState() => _OfflineQueueSheetState();
}

class _OfflineQueueSheetState extends State<OfflineQueueSheet> {
  List<OfflineOutboxItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await OfflineOutboxStore.loadAll();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  String _titleFor(OfflineOutboxItem it) {
    final p = it.payload;
    if (it.type == 'cash') {
      return 'Kassa: ${formatUzs(p['amount'] as num?, withCurrency: true)}';
    }
    if (it.type == 'pay_debt') {
      final sup = (p['supplier_name'] ?? '').toString();
      final amt = (p['partial_amount'] ?? p['amount']) as num?;
      return "Qarz to'lovi: $sup (${formatUzs(amt, withCurrency: true)})";
    }
    final sup = (p['supplier_name'] ?? '').toString();
    return 'Nakladnoy: $sup (${formatUzs(p['amount'] as num?, withCurrency: true)})';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 6, 18, sheetBottomPadding(context)),
        child: SizedBox(
          height: sheetMaxHeight(context, fraction: 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_upload_rounded,
                      color: AppTokens.debtAmber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Oflayn navbat (${_items.length})',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_items.isEmpty)
                const Expanded(
                  child: Center(child: Text("Navbat bo'sh — barchasi yuborilgan")),
                )
              else ...[
                Expanded(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) {
                      final it = _items[i];
                      return Card(
                        child: ListTile(
                          dense: true,
                          title: Text(
                            _titleFor(it),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            it.createdAtIso.length >= 16
                                ? it.createdAtIso
                                    .substring(0, 16)
                                    .replaceFirst('T', ' ')
                                : it.createdAtIso,
                          ),
                          trailing: IconButton(
                            tooltip: "Navbatdan o'chirish",
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: AppTokens.dangerRed),
                            onPressed: () async {
                              await OfflineOutboxStore.removeById(it.id);
                              await _reload();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () async {
                    await widget.onSyncNow();
                    await _reload();
                  },
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Hozir yuborish'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
