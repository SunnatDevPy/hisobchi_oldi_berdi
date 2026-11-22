import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Design tokens for Hisobchi — high-contrast fintech palette for Light & Dark modes.
class AppTokens {
  // Brand
  static const Color brand = Color(0xFF4F46E5); // indigo-600
  static const Color brandDeep = Color(0xFF312E81); // indigo-900
  static const Color brandViolet = Color(0xFF7C3AED); // violet-600
  static const Color brandSky = Color(0xFF0EA5E9);

  // Legacy names kept for compatibility
  static const Color navyDark = Color(0xFF0F172A);
  static const Color navyPrimary = brand;
  static const Color navyAccent = Color(0xFF6366F1);

  // Semantic money colors (base)
  static const Color cashGreen = Color(0xFF059669);
  static const Color cashGreenBg = Color(0xFFECFDF5);
  static const Color cardBlue = Color(0xFF2563EB);
  static const Color cardBlueBg = Color(0xFFEFF6FF);
  static const Color transferPurple = Color(0xFF9333EA);
  static const Color transferPurpleBg = Color(0xFFFAF5FF);
  static const Color debtAmber = Color(0xFFD97706);
  static const Color debtAmberBg = Color(0xFFFFFBEB);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color dangerRedBg = Color(0xFFFEF2F2);

  static const Color surfaceLight = Color(0xFFF3F5FA);
  static const Color cardBorderLight = Color(0xFFE2E8F0);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);

  static const Color surfaceDark = Color(0xFF090D18);
  static const Color cardDark = Color(0xFF13192B);
  static const Color cardBorderDark = Color(0xFF26304D);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
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
  final primaryColor = isDark ? const Color(0xFF818CF8) : AppTokens.brand;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.brand,
    brightness: brightness,
    primary: primaryColor,
    onPrimary: Colors.white,
    secondary: AppTokens.brandViolet,
    onSecondary: Colors.white,
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
      scrolledUnderElevation: 1,
      backgroundColor: isDark ? AppTokens.cardDark : Colors.white,
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
      backgroundColor: isDark ? AppTokens.cardDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: secondaryText.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: isDark ? AppTokens.cardDark : Colors.white,
      indicatorColor:
          primaryColor.withValues(alpha: isDark ? 0.28 : 0.14),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? (isDark ? Colors.white : AppTokens.brand)
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
          isDark ? const Color(0xFF1D253D) : const Color(0xFFF1F5F9),
      selectedColor:
          primaryColor.withValues(alpha: isDark ? 0.32 : 0.16),
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
        color: isDark ? Colors.white : AppTokens.brand,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1B233A) : const Color(0xFFF8FAFC),
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
        backgroundColor: AppTokens.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryText,
        side: BorderSide(
          color: isDark ? AppTokens.cardBorderDark : const Color(0xFFCBD5E1),
        ),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppTokens.brand,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
