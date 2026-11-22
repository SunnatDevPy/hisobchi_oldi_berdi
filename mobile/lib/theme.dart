import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Design tokens for Hisobchi — modern fintech palette (indigo/violet + semantic money colors).
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

  // Semantic money colors
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

  static const Color surfaceLight = Color(0xFFF4F6FB);
  static const Color cardBorderLight = Color(0xFFE6E9F2);
  static const Color surfaceDark = Color(0xFF0B1020);
  static const Color cardDark = Color(0xFF141A2E);
  static const Color cardBorderDark = Color(0xFF232B45);

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF312E81), Color(0xFF4F46E5), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];

  // Spacing scale (4pt grid)
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 20, s6 = 24;
  static const double radius = 18;
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

bool isDarkCtx(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppTokens.brand,
    brightness: brightness,
    primary: isDark ? const Color(0xFF818CF8) : AppTokens.brand,
    secondary: AppTokens.brandViolet,
    error: AppTokens.dangerRed,
    surface: isDark ? AppTokens.cardDark : Colors.white,
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
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: isDark ? Colors.white : AppTokens.navyDark,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: isDark ? AppTokens.cardDark : Colors.white,
      indicatorColor: AppTokens.brand.withValues(alpha: isDark ? 0.35 : 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight:
              s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(
        color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
      ),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1A2138) : const Color(0xFFF7F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(88, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
