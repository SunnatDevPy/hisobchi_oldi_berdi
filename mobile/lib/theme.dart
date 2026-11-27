import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Design tokens for Hisobchi — 1-to-1 Figma "Finance & Banking 3D" atmosphere:
/// Matte Obsidian-Graphite + Luminous Mint-Emerald (#0CCE42) + Metallic Gold + Soft Clay.
class AppTokens {
  // Figma Finance & Banking 3D primary tokens
  static const Color brand = Color(0xFF0CCE42); // Figma Style color 2: #0CCE42
  static const Color brandDeep = Color(0xFF064E28); // deep forest emerald
  static const Color brandViolet = Color(0xFF22D666); // luminous mint-emerald ("3D ICONS")
  static const Color brandOrchid = Color(0xFFF5C443); // metallic 3D gold coin accent
  static const Color brandSky = Color(0xFF34D399); // frosted emerald-teal highlight

  // Legacy names kept for compatibility
  static const Color navyDark = Color(0xFF161817);
  static const Color navyPrimary = brand;
  static const Color navyAccent = Color(0xFF22D666);

  // Semantic money colors (base)
  static const Color cashGreen = Color(0xFF10CE52);
  static const Color cashGreenBg = Color(0xFFECFDF3);
  static const Color cardBlue = Color(0xFF0EA5E9);
  static const Color cardBlueBg = Color(0xFFF0F9FF);
  static const Color transferPurple = Color(0xFF8B95A1); // frosted silver-clay bank tone
  static const Color transferPurpleBg = Color(0xFFF4F6F8);
  static const Color debtAmber = Color(0xFFF59E0B);
  static const Color debtAmberBg = Color(0xFFFFFBEB);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color dangerRedBg = Color(0xFFFEF2F2);

  // Light surfaces (crisp frosted silver-mint clay)
  static const Color surfaceLight = Color(0xFFF2F5F3);
  static const Color cardBorderLight = Color(0xFFDCE4DF);
  static const Color textPrimaryLight = Color(0xFF141A17);
  static const Color textSecondaryLight = Color(0xFF526059);

  // Dark surfaces (1-to-1 Figma Cover Matte Obsidian #1E1E1E / #161817 + Charcoal #262626 + Clay #A7A6A7)
  static const Color surfaceDark = Color(0xFF161817);
  static const Color cardDark = Color(0xFF202322);
  static const Color cardElevatedDark = Color(0xFF282C2B);
  static const Color cardBorderDark = Color(0xFF363C3A);
  static const Color textPrimaryDark = Color(0xFFF8FAF9);
  static const Color textSecondaryDark = Color(0xFFA7B0AC);

  static const LinearGradient heroGradient = LinearGradient(
    colors: [
      Color(0xFF1B1F1D),
      Color(0xFF182A21),
      Color(0xFF0D4427),
      Color(0xFF0E6436),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFF0AA838), Color(0xFF18D259), Color(0xFFD99B26)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];

  static const double radius = 18;

  /// Returns high-contrast (foreground, background, border) for any semantic color
  /// so text is always crisp in both Light and Dark mode.
  static (Color fg, Color bg, Color border) semanticSurface(
    BuildContext context,
    Color base,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      final hsl = HSLColor.fromColor(base);
      final brightFg =
          hsl.withLightness((hsl.lightness + 0.24).clamp(0.72, 0.90)).toColor();
      return (
        brightFg,
        base.withValues(alpha: 0.20),
        base.withValues(alpha: 0.45),
      );
    } else {
      final hsl = HSLColor.fromColor(base);
      final deepFg =
          hsl.withLightness((hsl.lightness - 0.08).clamp(0.24, 0.42)).toColor();
      return (
        deepFg,
        base.withValues(alpha: 0.11),
        base.withValues(alpha: 0.35),
      );
    }
  }
}

final NumberFormat _uzsFmt = NumberFormat('#,##0', 'en_US');

/// Format numeric amount as Uzbek soum with spaces: `1 554 000`.
String formatUzs(num? value, {bool withCurrency = false}) {
  if (value == null) return withCurrency ? "0 so'm" : '0';
  final rounded = value.round();
  final formatted = _uzsFmt.format(rounded).replaceAll(',', ' ');
  return withCurrency ? "$formatted so'm" : formatted;
}

/// Compact format: 1 554 000 -> "1.55 mln", 250 000 -> "250 ming".
String formatUzsCompact(num? value) {
  final v = (value ?? 0).toDouble();
  final a = v.abs();
  if (a >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} mlrd';
  if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(2)} mln';
  if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(0)} ming';
  return v.toStringAsFixed(0);
}

/// Parse user-entered amount string ("1 554 000", "260000", "1.554.000") into double.
double? parseUzsInput(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Live TextInputFormatter that formats numbers with spaces as the user types:
/// `1554000` -> `1 554 000`.
class UzsAmountInputFormatter extends TextInputFormatter {
  const UzsAmountInputFormatter();

  static String formatDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final parsed = int.tryParse(digits);
    if (parsed == null) return digits;
    return _uzsFmt.format(parsed).replaceAll(',', ' ');
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Count how many digits were before the cursor in newValue
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    var digitsBeforeCursor = 0;
    for (var i = 0; i < cursor; i++) {
      final code = newValue.text.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        digitsBeforeCursor++;
      }
    }

    final formatted = formatDigits(digitsOnly);

    // Map digitsBeforeCursor back into formatted string position
    var newCursor = formatted.length;
    if (digitsBeforeCursor <= 0) {
      newCursor = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        final code = formatted.codeUnitAt(i);
        if (code >= 48 && code <= 57) {
          seen++;
          if (seen == digitsBeforeCursor) {
            newCursor = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}

bool isDarkCtx(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color textPrimaryOf(BuildContext context) =>
    isDarkCtx(context) ? AppTokens.textPrimaryDark : AppTokens.textPrimaryLight;

Color textSecondaryOf(BuildContext context) => isDarkCtx(context)
    ? AppTokens.textSecondaryDark
    : AppTokens.textSecondaryLight;

/// Bundled 3D icon asset paths exported directly from Figma "Finance & Banking 3D Icons".
class Figma3DIcons {
  static const String agreement = 'assets/icons3d/agreement.png';
  static const String atm = 'assets/icons3d/atm.png';
  static const String bag = 'assets/icons3d/bag.png';
  static const String bank = 'assets/icons3d/bank.png';
  static const String briefcase = 'assets/icons3d/briefcase.png';
  static const String calculator = 'assets/icons3d/calculator.png';
  static const String cards = 'assets/icons3d/cards.png';
  static const String charts = 'assets/icons3d/charts.png';
  static const String exchange = 'assets/icons3d/exchange.png';
  static const String hourglass = 'assets/icons3d/hourglass.png';
  static const String lock = 'assets/icons3d/lock.png';
  static const String money = 'assets/icons3d/money.png';
  static const String qr = 'assets/icons3d/qr.png';
  static const String shield = 'assets/icons3d/shield.png';
}

/// Renders a 3D Finance & Banking icon from Figma inside a rounded squircle tile
/// matching the Figma `rounded-[44px]` (`44/300`) icon geometry with subtle depth glow.
class Figma3DIconBadge extends StatelessWidget {
  final String asset;
  final double size;
  final IconData fallbackIcon;
  final Color? glowColor;

  const Figma3DIconBadge({
    super.key,
    required this.asset,
    this.size = 34,
    this.fallbackIcon = Icons.auto_awesome_rounded,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    final glow = glowColor ?? AppTokens.brandViolet;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.24),
            blurRadius: size * 0.32,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            color: glow.withValues(alpha: 0.18),
            alignment: Alignment.center,
            child: Icon(fallbackIcon, size: size * 0.56, color: glow),
          ),
        ),
      ),
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final primaryText =
      isDark ? AppTokens.textPrimaryDark : AppTokens.textPrimaryLight;
  final secondaryText =
      isDark ? AppTokens.textSecondaryDark : AppTokens.textSecondaryLight;
  final primaryColor = isDark ? const Color(0xFF28E070) : const Color(0xFF0A9E36);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.brand,
    brightness: brightness,
    primary: primaryColor,
    onPrimary: isDark ? const Color(0xFF062914) : Colors.white,
    secondary: AppTokens.brandOrchid,
    onSecondary: const Color(0xFF1F1600),
    tertiary: AppTokens.brandSky,
    error: AppTokens.dangerRed,
    surface: isDark ? AppTokens.cardDark : Colors.white,
    onSurface: primaryText,
    onSurfaceVariant: secondaryText,
  );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? AppTokens.surfaceDark : AppTokens.surfaceLight,
    hintColor: secondaryText,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isDark ? AppTokens.surfaceDark : Colors.white,
      foregroundColor: primaryText,
      iconTheme: IconThemeData(color: primaryText),
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w900,
        color: primaryText,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      color: isDark ? AppTokens.cardDark : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: BorderSide(
          color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1C1F1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: isDark
          ? AppTokens.brandViolet.withValues(alpha: 0.55)
          : secondaryText.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      indicatorColor:
          AppTokens.brandViolet.withValues(alpha: isDark ? 0.24 : 0.14),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? (isDark ? Colors.white : const Color(0xFF0A8F30))
              : secondaryText,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11.5,
          color: s.contains(WidgetState.selected) ? primaryText : secondaryText,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor:
          isDark ? AppTokens.cardElevatedDark : const Color(0xFFEAF0EC),
      selectedColor:
          AppTokens.brandViolet.withValues(alpha: isDark ? 0.28 : 0.16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(
        color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: primaryText,
      ),
      secondaryLabelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: isDark ? Colors.white : const Color(0xFF0A8F30),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppTokens.cardElevatedDark : const Color(0xFFF8FAF9),
      labelStyle: TextStyle(
        color: secondaryText,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: primaryColor,
        fontWeight: FontWeight.w800,
      ),
      hintStyle: TextStyle(
        color: secondaryText.withValues(alpha: 0.75),
        fontWeight: FontWeight.w500,
      ),
      helperStyle: TextStyle(
        color: primaryColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIconColor: secondaryText,
      suffixIconColor: secondaryText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: primaryText,
      iconColor: secondaryText,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0FA940),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryText,
        side: BorderSide(
          color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
        ),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: const Color(0xFF0CCE42),
      foregroundColor: const Color(0xFF072110),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? AppTokens.cardElevatedDark : const Color(0xFF1C211F),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
