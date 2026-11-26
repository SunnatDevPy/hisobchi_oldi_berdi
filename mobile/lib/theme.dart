import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Design tokens for Hisobchi — unified obsidian, electric-violet, orchid & cyan fintech palette.
class AppTokens {
  // Brand (Electric Violet + Royal Amethyst + Orchid Pink + Luminous Cyan)
  static const Color brand = Color(0xFF8B5CF6); // electric violet-500
  static const Color brandDeep = Color(0xFF3B0764); // royal amethyst-950
  static const Color brandViolet = Color(0xFFA855F7); // luminous purple-500
  static const Color brandOrchid = Color(0xFFEC4899); // neon orchid-pink-500
  static const Color brandSky = Color(0xFF38BDF8); // luminous cyan-400

  // Legacy names kept for compatibility
  static const Color navyDark = Color(0xFF090712);
  static const Color navyPrimary = brand;
  static const Color navyAccent = Color(0xFFA855F7);

  // Semantic money colors (base)
  static const Color cashGreen = Color(0xFF10B981);
  static const Color cashGreenBg = Color(0xFFECFDF5);
  static const Color cardBlue = Color(0xFF0284C7);
  static const Color cardBlueBg = Color(0xFFF0F9FF);
  static const Color transferPurple = Color(0xFFA855F7);
  static const Color transferPurpleBg = Color(0xFFFAF5FF);
  static const Color debtAmber = Color(0xFFF59E0B);
  static const Color debtAmberBg = Color(0xFFFFFBEB);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color dangerRedBg = Color(0xFFFEF2F2);

  // Light surfaces (crisp pearl-lavender)
  static const Color surfaceLight = Color(0xFFF6F4FB);
  static const Color cardBorderLight = Color(0xFFE5DFF3);
  static const Color textPrimaryLight = Color(0xFF140F26);
  static const Color textSecondaryLight = Color(0xFF5A5275);

  // Dark surfaces (deep obsidian-plum matching 3D cosmic splash)
  static const Color surfaceDark = Color(0xFF090712);
  static const Color cardDark = Color(0xFF130F21);
  static const Color cardElevatedDark = Color(0xFF1B162D);
  static const Color cardBorderDark = Color(0xFF2D2448);
  static const Color textPrimaryDark = Color(0xFFFAF8FF);
  static const Color textSecondaryDark = Color(0xFFB8B0D0);

  static const LinearGradient heroGradient = LinearGradient(
    colors: [
      Color(0xFF170B30),
      Color(0xFF3B0F70),
      Color(0xFF7E22CE),
      Color(0xFFA21CAF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF), Color(0xFFEC4899)],
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

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final primaryText =
      isDark ? AppTokens.textPrimaryDark : AppTokens.textPrimaryLight;
  final secondaryText =
      isDark ? AppTokens.textSecondaryDark : AppTokens.textSecondaryLight;
  final primaryColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.brand,
    brightness: brightness,
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: AppTokens.brandOrchid,
    onSecondary: Colors.white,
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
      backgroundColor: isDark ? const Color(0xFF120E20) : Colors.white,
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
          AppTokens.brandViolet.withValues(alpha: isDark ? 0.30 : 0.15),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? (isDark ? Colors.white : const Color(0xFF7C3AED))
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
          isDark ? AppTokens.cardElevatedDark : const Color(0xFFF2EEFA),
      selectedColor:
          AppTokens.brandViolet.withValues(alpha: isDark ? 0.34 : 0.16),
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
        color: isDark ? Colors.white : const Color(0xFF7C3AED),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppTokens.cardElevatedDark : const Color(0xFFFAF8FE),
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
        backgroundColor: const Color(0xFF8B5CF6),
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
      backgroundColor: const Color(0xFF9333EA),
      foregroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? AppTokens.cardElevatedDark : const Color(0xFF1F1638),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
