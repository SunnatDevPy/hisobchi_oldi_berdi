import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Design tokens and semantic colors for Hisobchi fintech UI.
class AppTokens {
  static const Color navyDark = Color(0xFF0F172A);
  static const Color navyPrimary = Color(0xFF1E3A8A);
  static const Color navyAccent = Color(0xFF2563EB);

  static const Color cashGreen = Color(0xFF059669);
  static const Color cashGreenBg = Color(0xFFECFDF5);

  static const Color cardBlue = Color(0xFF2563EB);
  static const Color cardBlueBg = Color(0xFFEFF6FF);

  static const Color transferPurple = Color(0xFF7C3AED);
  static const Color transferPurpleBg = Color(0xFFF5F3FF);

  static const Color debtAmber = Color(0xFFD97706);
  static const Color debtAmberBg = Color(0xFFFFFBEB);

  static const Color dangerRed = Color(0xFFDC2626);
  static const Color dangerRedBg = Color(0xFFFEF2F2);

  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color cardBorderLight = Color(0xFFE2E8F0);

  static const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];
}

final NumberFormat _uzsFmt = NumberFormat('#,##0', 'en_US');

/// Format numeric amount as Uzbek soum with spaces: `1 554 000`.
String formatUzs(num? value, {bool withCurrency = false}) {
  if (value == null) return withCurrency ? "0 so'm" : '0';
  final rounded = value.round();
  final formatted = _uzsFmt.format(rounded).replaceAll(',', ' ');
  return withCurrency ? "$formatted so'm" : formatted;
}

/// Parse user-entered amount string ("1 554 000", "260000", "1.554.000") into double.
double? parseUzsInput(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.navyPrimary,
    brightness: brightness,
    primary: isDark ? const Color(0xFF60A5FA) : AppTokens.navyPrimary,
    secondary: AppTokens.cashGreen,
    error: AppTokens.dangerRed,
    surface: isDark ? const Color(0xFF0F172A) : Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF090D16) : AppTokens.surfaceLight,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      foregroundColor: isDark ? Colors.white : AppTokens.navyDark,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : AppTokens.navyDark,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF151C2C) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF263046) : AppTokens.cardBorderLight,
          width: 1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 2,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(88, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(80, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}
