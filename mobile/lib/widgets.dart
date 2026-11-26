import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'security.dart';
import 'theme.dart';
import 'widgets_3d.dart';

class FloatingNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Computes bottom scroll clearance for main tab ListViews so the final item
/// always stops comfortably above the floating glass nav capsule, Android
/// 3-button/gesture system bar, and (on tabs 0–2) the floating "+" FAB.
double mainTabScrollBottomPadding(
  BuildContext context, {
  bool hasFab = true,
}) {
  final mq = MediaQuery.of(context);
  final sysBottom = math.max(mq.padding.bottom, mq.viewPadding.bottom);
  // FloatingGlassBottomNav height (64) + vertical padding (8 top + 12 bottom = 20)
  // + comfortable breathing space above capsule (28) = 112.
  // When FAB (56 + 16 margin) is shown on the tab, add 68px extra so bottom cards
  // and buttons scroll cleanly past the "+" button too.
  return sysBottom + (hasFab ? 180.0 : 112.0);
}

/// Floating frosted-glass bottom navigation capsule with animated neon pill indicator.
class FloatingGlassBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavDestination> destinations;

  const FloatingGlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final count = destinations.length.clamp(1, 8);
    final activeIdx = selectedIndex.clamp(0, count - 1);

    final glassBg = isDark
        ? const Color(0xFF120E20).withValues(alpha: 0.84)
        : Colors.white.withValues(alpha: 0.88);
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : AppTokens.brandViolet.withValues(alpha: 0.16);

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.45)
                      : AppTokens.brandViolet.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                if (isDark)
                  BoxShadow(
                    color: AppTokens.brandViolet.withValues(alpha: 0.14),
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: glassBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: rimColor, width: 1.1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemW = constraints.maxWidth / count;
                        return Stack(
                          children: [
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              left: itemW * activeIdx,
                              top: 0,
                              bottom: 0,
                              width: itemW,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isDark
                                        ? [
                                            AppTokens.brandViolet
                                                .withValues(alpha: 0.28),
                                            AppTokens.brandOrchid
                                                .withValues(alpha: 0.18),
                                          ]
                                        : [
                                            AppTokens.brandViolet
                                                .withValues(alpha: 0.16),
                                            AppTokens.brandOrchid
                                                .withValues(alpha: 0.08),
                                          ],
                                  ),
                                  border: Border.all(
                                    color: AppTokens.brandViolet.withValues(
                                      alpha: isDark ? 0.36 : 0.24,
                                    ),
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: 22,
                                    height: 2.5,
                                    margin: const EdgeInsets.only(top: 1),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTokens.brandViolet,
                                          AppTokens.brandOrchid,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTokens.brandOrchid
                                              .withValues(alpha: 0.65),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: List.generate(destinations.length, (i) {
                                final d = destinations[i];
                                final isSelected = i == activeIdx;
                                final iconColor = isSelected
                                    ? (isDark
                                        ? Colors.white
                                        : const Color(0xFF6D28D9))
                                    : textSecondaryOf(context);
                                final badgeText = d.badgeCount > 99
                                    ? '99+'
                                    : '${d.badgeCount}';

                                return Expanded(
                                  child: Semantics(
                                    button: true,
                                    selected: isSelected,
                                    label: d.label,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(22),
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          onDestinationSelected(i);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  AnimatedScale(
                                                    scale:
                                                        isSelected ? 1.12 : 1.0,
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    curve: Curves.easeOutBack,
                                                    child: Icon(
                                                      isSelected
                                                          ? d.selectedIcon
                                                          : d.icon,
                                                      size: 21,
                                                      color: iconColor,
                                                    ),
                                                  ),
                                                  if (d.badgeCount > 0)
                                                    Positioned(
                                                      right: -12,
                                                      top: -5,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 5,
                                                          vertical: 1,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          gradient:
                                                              const LinearGradient(
                                                            colors: [
                                                              AppTokens
                                                                  .brandOrchid,
                                                              AppTokens
                                                                  .dangerRed,
                                                            ],
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(99),
                                                          border: Border.all(
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF120E20)
                                                                : Colors.white,
                                                            width: 1.2,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          badgeText,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            fontFeatures: AppTokens
                                                                .tabularNums,
                                                            height: 1.1,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                d.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  color: iconColor,
                                                  letterSpacing: -0.1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        );
                      },
                    ),
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

class HeroBalanceCard extends StatelessWidget {
  final StatusSummary summary;
  final int animSeed;
  final VoidCallback? onAddCash;
  final VoidCallback? onExpense;
  final VoidCallback? onKassaDebt;
  final VoidCallback? onKassaRepay;
  final VoidCallback? onTapKassaDebtHistory;

  const HeroBalanceCard({
    super.key,
    required this.summary,
    this.animSeed = 0,
    this.onAddCash,
    this.onExpense,
    this.onKassaDebt,
    this.onKassaRepay,
    this.onTapKassaDebtHistory,
  });

  @override
  Widget build(BuildContext context) {
    final grp = summary.groupInfo;
    return Container(
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE879F9).withValues(alpha: 0.36),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTokens.brandViolet.withValues(alpha: 0.34),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppTokens.brandOrchid.withValues(alpha: 0.14),
            blurRadius: 40,
            spreadRadius: -6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Static top-left specular orchid/cyan radial bloom
            Positioned(
              top: -65,
              left: -45,
              width: 230,
              height: 200,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFF0ABFC).withValues(alpha: 0.24),
                        AppTokens.brandSky.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -50,
              bottom: -70,
              width: 210,
              height: 190,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        AppTokens.brandOrchid.withValues(alpha: 0.20),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Session date & Telegram group pill
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                summary.timeSpanLabel.isNotEmpty
                                    ? '${summary.reportDate} • ${summary.timeSpanLabel}'
                                    : summary.reportDate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: grp.bound
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.24)
                                  : const Color(0xFFF59E0B)
                                      .withValues(alpha: 0.24),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: grp.bound
                                    ? const Color(0xFF6EE7B7)
                                        .withValues(alpha: 0.55)
                                    : const Color(0xFFFCD34D)
                                        .withValues(alpha: 0.55),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  grp.bound
                                      ? Icons.mark_chat_read_rounded
                                      : Icons.warning_amber_rounded,
                                  size: 13.5,
                                  color: grp.bound
                                      ? const Color(0xFF6EE7B7)
                                      : const Color(0xFFFDE68A),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    grp.bound ? grp.title : 'Guruh ulanmagan',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded,
                            size: 15, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "QO'LDA QOLISHI KERAK (NAQD)",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedUzsNumber(
                      value: summary.expectedCash,
                      withCurrency: true,
                      animSeed: animSeed,
                      duration: const Duration(milliseconds: 700),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 33,
                        fontWeight: FontWeight.w900,
                        fontFeatures: AppTokens.tabularNums,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Detailed Cash Flow Glass Panel
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0614).withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFF5D0FE).withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _HeroMetricTile(
                                label: 'Jami kirim',
                                numericValue: summary.totalAvailableInflow,
                                animSeed: animSeed,
                                icon: Icons.south_west_rounded,
                                color: const Color(0xFF6EE7B7),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HeroMetricTile(
                                label: 'Naqd rasxod',
                                numericValue: summary.totalNakladnoySpent +
                                    summary.expenseToday,
                                animSeed: animSeed,
                                icon: Icons.north_east_rounded,
                                color: const Color(0xFFFDA4AF),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white12, height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _HeroSubStat(
                                label: 'Kechadan',
                                numericValue: summary.openingBalance,
                                animSeed: animSeed,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Builder(
                                builder: (_) {
                                  final netMainIn = summary.mainCashIn -
                                      summary.mainReturnToday;
                                  return _HeroSubStat(
                                    label: 'Pul oldim',
                                    numericValue: netMainIn.abs(),
                                    prefix: netMainIn < 0 ? '−' : '+',
                                    animSeed: animSeed,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _HeroSubStat(
                                label: 'Xarajat',
                                numericValue: summary.expenseToday,
                                prefix: summary.expenseToday > 0 ? '−' : '',
                                animSeed: animSeed,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: onTapKassaDebtHistory,
                                child: _HeroSubStat(
                                  label: onTapKassaDebtHistory != null
                                      ? 'Kassa qarz ›'
                                      : 'Kassa qarz',
                                  numericValue:
                                      summary.totalKassaDebtOutstanding,
                                  animSeed: animSeed,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (onAddCash != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroActionBtn(
                            icon: Icons.add_card_rounded,
                            label: 'Pul oldim',
                            accentColor: AppTokens.cashGreen,
                            onTap: onAddCash!,
                          ),
                        ),
                        if (onExpense != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _HeroActionBtn(
                              icon: Icons.trending_down_rounded,
                              label: 'Xarajat',
                              accentColor: AppTokens.dangerRed,
                              onTap: onExpense!,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroActionBtn(
                            icon: Icons.account_balance_rounded,
                            label: 'Kassa qarz',
                            accentColor: AppTokens.brandSky,
                            onTap: onKassaDebt!,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HeroActionBtn(
                            icon: Icons.assignment_return_rounded,
                            label: 'Qaytarish',
                            accentColor: AppTokens.debtAmber,
                            onTap: onKassaRepay!,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSubStat extends StatelessWidget {
  final String label;
  final double numericValue;
  final String prefix;
  final int animSeed;

  const _HeroSubStat({
    required this.label,
    required this.numericValue,
    this.prefix = '',
    this.animSeed = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedUzsNumber(
            value: numericValue,
            prefix: prefix,
            animSeed: animSeed,
            duration: const Duration(milliseconds: 620),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: AppTokens.tabularNums,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroMetricTile extends StatelessWidget {
  final String label;
  final double numericValue;
  final int animSeed;
  final IconData icon;
  final Color color;

  const _HeroMetricTile({
    required this.label,
    required this.numericValue,
    this.animSeed = 0,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13.5, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AnimatedUzsNumber(
            value: numericValue,
            animSeed: animSeed,
            duration: const Duration(milliseconds: 650),
            style: TextStyle(
              color: color,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              fontFeatures: AppTokens.tabularNums,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  const _HeroActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Colors.white;
    return TactileScaleTap(
      pressedScale: 0.94,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0E091D).withValues(alpha: 0.42),
                accent.withValues(alpha: 0.16),
              ],
            ),
            border: Border.all(
              color: accentColor != null
                  ? accent.withValues(alpha: 0.40)
                  : Colors.white.withValues(alpha: 0.22),
              width: 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 17, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
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
}

/// Executive Dashboard Analytics Section:
/// 1) Dumaloq Statistika (Interactive Custom-Painted Donut Chart)
/// 2) Chiziqli Statistika (Interactive Smooth Bezier Trend Line & Area Chart with Date Selector)
/// 3) 2x2 Payment Method Breakdown Cards with count, sum, and % progress bar
/// 4) Unified Chronological Timeline ("Qachon nima oldi va kimga pul berilgani")
/// 5) Top Suppliers Ranked Bar Chart
class DashboardAnalyticsSection extends StatefulWidget {
  final StatusSummary summary;
  final bool canWrite;
  final int animSeed;
  final List<Map<String, dynamic>> dailySeries;
  final String seriesGranularity; // 'daily' | 'hourly'
  final String periodLabel;
  final String activePeriodKey; // 'today' | 'yesterday' | '7d' | '14d' | '30d' | 'custom'
  final ValueChanged<String> onSelectPeriodKey;
  final VoidCallback onPickCustomDateRange;
  final ValueChanged<String> onTapPaymentFilter;
  final VoidCallback onOpenNakladnoyTab;
  final ValueChanged<NakladnoyItem> onTapNakladnoy;
  final ValueChanged<String>? onTapSupplier;
  final ValueChanged<CashTxItem> onEditCashTx;
  final ValueChanged<CashTxItem> onDeleteCashTx;

  const DashboardAnalyticsSection({
    super.key,
    required this.summary,
    required this.canWrite,
    this.animSeed = 0,
    this.dailySeries = const [],
    this.seriesGranularity = 'daily',
    this.periodLabel = 'Oxirgi 7 kun',
    this.activePeriodKey = '7d',
    required this.onSelectPeriodKey,
    required this.onPickCustomDateRange,
    required this.onTapPaymentFilter,
    required this.onOpenNakladnoyTab,
    required this.onTapNakladnoy,
    this.onTapSupplier,
    required this.onEditCashTx,
    required this.onDeleteCashTx,
  });

  @override
  State<DashboardAnalyticsSection> createState() =>
      _DashboardAnalyticsSectionState();
}

class _DashboardAnalyticsSectionState extends State<DashboardAnalyticsSection> {
  int? _selectedTrendIdx;
  bool _showAllCashEvents = false;
  bool _trendBarMode = true;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final naks = summary.nakladnoys;
    final cashCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'cash').length;
    final cardCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'card').length;
    final transferCnt =
        naks.where((n) => !n.isDebt && n.paymentMethod == 'transfer').length;
    final debtCnt = naks.where((n) => n.isDebt).length;

    final grandTotal = summary.totalNakladnoySpent +
        summary.totalCardSpent +
        summary.totalTransferSpent +
        summary.totalDebtNakladnoy;

    // Highlight the single payment mode with the largest positive volume.
    String? featuredKey;
    double bestAmt = 0;
    for (final e in [
      ('cash', summary.totalNakladnoySpent),
      ('card', summary.totalCardSpent),
      ('transfer', summary.totalTransferSpent),
      ('debt', summary.totalDebtNakladnoy),
    ]) {
      if (e.$2 > bestAmt) {
        bestAmt = e.$2;
        featuredKey = e.$1;
      }
    }

    // Group today's nakladnoys by supplier for Top Postavshiklar chart
    final supTotals = <String, ({double sum, int count})>{};
    for (final n in naks) {
      final prev = supTotals[n.supplierName];
      supTotals[n.supplierName] = (
        sum: (prev?.sum ?? 0) + n.amount,
        count: (prev?.count ?? 0) + 1,
      );
    }
    final topSuppliers = supTotals.entries.toList()
      ..sort((a, b) => b.value.sum.compareTo(a.value.sum));
    final maxSupSum =
        topSuppliers.isNotEmpty ? topSuppliers.first.value.sum : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. XARAJATLAR TAQSIMOTI (Glowing Multi-Segment Horizontal Distribution Card)
        _GlowingDistributionCard(
          cashAmount: summary.totalNakladnoySpent,
          cardAmount: summary.totalCardSpent,
          transferAmount: summary.totalTransferSpent,
          debtAmount: summary.totalDebtNakladnoy,
          cashCount: cashCnt,
          cardCount: cardCnt,
          transferCount: transferCnt,
          debtCount: debtCnt,
          reportDate: summary.reportDate,
          onTapMode: widget.onTapPaymentFilter,
        ),
        const SizedBox(height: 16),

        // 2. DINAMIKA (Glowing Paired Bar / Smooth Spline Chart with Date Range Selector)
        _TrendLineStatisticsCard(
          dailySeries: widget.dailySeries,
          seriesGranularity: widget.seriesGranularity,
          periodLabel: widget.periodLabel,
          activePeriodKey: widget.activePeriodKey,
          selectedIdx: _selectedTrendIdx,
          isBarMode: _trendBarMode,
          onToggleBarMode: (v) => setState(() => _trendBarMode = v),
          onSelectIdx: (i) => setState(() => _selectedTrendIdx = i),
          onSelectPeriodKey: (k) {
            setState(() => _selectedTrendIdx = null);
            widget.onSelectPeriodKey(k);
          },
          onPickCustomDateRange: () {
            setState(() => _selectedTrendIdx = null);
            widget.onPickCustomDateRange();
          },
        ),
        const SizedBox(height: 18),

        // 3. Payment Methods Breakdown (2x2 Neon Top-Glow Bento Grid)
        Row(
          children: [
            const Icon(Icons.grid_view_rounded,
                size: 19, color: AppTokens.brand),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                "To'lov turlari kesimida (${naks.length} ta)",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: textPrimaryOf(context),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onOpenNakladnoyTab,
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text("Ro'yxat"),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PaymentKpiCard(
                title: "NAQD TO'LOV",
                amount: summary.totalNakladnoySpent,
                animSeed: widget.animSeed,
                count: cashCnt,
                share: grandTotal > 0
                    ? summary.totalNakladnoySpent / grandTotal
                    : 0,
                icon: Icons.payments_rounded,
                color: AppTokens.cashGreen,
                isFeatured: featuredKey == 'cash',
                onTap: () => widget.onTapPaymentFilter('cash'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PaymentKpiCard(
                title: 'KARTA (NAQDSIZ)',
                amount: summary.totalCardSpent,
                animSeed: widget.animSeed,
                count: cardCnt,
                share:
                    grandTotal > 0 ? summary.totalCardSpent / grandTotal : 0,
                icon: Icons.credit_card_rounded,
                color: AppTokens.cardBlue,
                isFeatured: featuredKey == 'card',
                onTap: () => widget.onTapPaymentFilter('card'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PaymentKpiCard(
                title: 'PERECHESLENIYA',
                amount: summary.totalTransferSpent,
                animSeed: widget.animSeed,
                count: transferCnt,
                share: grandTotal > 0
                    ? summary.totalTransferSpent / grandTotal
                    : 0,
                icon: Icons.account_balance_rounded,
                color: AppTokens.transferPurple,
                isFeatured: featuredKey == 'transfer',
                onTap: () => widget.onTapPaymentFilter('transfer'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PaymentKpiCard(
                title: 'QARZGA (SMENA)',
                amount: summary.totalDebtNakladnoy,
                animSeed: widget.animSeed,
                count: debtCnt,
                share: grandTotal > 0
                    ? summary.totalDebtNakladnoy / grandTotal
                    : 0,
                icon: Icons.push_pin_rounded,
                color: AppTokens.debtAmber,
                isFeatured: featuredKey == 'debt',
                subtitle: summary.allUnpaidDebtCount > 0
                    ? 'Jami qarz: ${formatUzsCompact(summary.allUnpaidDebtTotal)}'
                    : null,
                onTap: () => widget.onTapPaymentFilter('debt'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 4. QACHON NIMA OLDI VA KIMGA PUL BERILGANI (Unified Chronological Cash-Flow Journal)
        _buildUnifiedTimelineCard(context, summary),
        const SizedBox(height: 16),

        // 5. Top Postavshiklar (Ranked Visual Bars with Luminous Gradient)
        if (topSuppliers.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTokens.brand.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.leaderboard_rounded,
                            color: AppTokens.brand, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Top Postavshiklar (${summary.reportDate})',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: textPrimaryOf(context),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onOpenNakladnoyTab,
                        child: const Text('Barchasi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...topSuppliers.take(6).map((entry) {
                    final ratio =
                        (entry.value.sum / maxSupSum).clamp(0.06, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: widget.onTapSupplier != null
                            ? () => widget.onTapSupplier!(entry.key)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${entry.value.count} ta • ${formatUzs(entry.value.sum, withCurrency: true)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: textPrimaryOf(context),
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                  if (widget.onTapSupplier != null) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right_rounded,
                                        size: 17,
                                        color: textSecondaryOf(context)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              LayoutBuilder(
                                builder: (context, barBox) => Container(
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color:
                                        AppTokens.brand.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: barBox.maxWidth * ratio,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTokens.brand,
                                          AppTokens.brandOrchid,
                                          AppTokens.brandSky,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTokens.brandViolet
                                              .withValues(alpha: 0.35),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUnifiedTimelineCard(
      BuildContext context, StatusSummary summary) {
    // Clean Kassa-only transactions list (nakladnoys live in the dedicated Nakladnoylar tab).
    final events = <_TimelineEvent>[];

    for (final tx in summary.cashTransactions) {
      final spec = _txTypeSpec(context, tx.sourceType);
      final isOut = tx.sourceType == 'kassa_repay' ||
          tx.sourceType == 'expense' ||
          tx.sourceType == 'main_return';
      events.add(
        _TimelineEvent(
          kind: isOut ? 'out' : 'in',
          timeHm: tx.timeHm,
          createdAt: tx.createdAt,
          badgeText: spec.badge,
          title: tx.note.isNotEmpty ? tx.note : spec.title,
          subtitle: spec.title,
          amount: tx.amount,
          sign: spec.sign,
          icon: spec.icon,
          fg: spec.fg,
          bg: spec.bg,
          border: spec.border,
          cashTx: tx,
        ),
      );
    }

    // Sort newest first by createdAt / timeHm
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visibleEvents =
        _showAllCashEvents ? events : events.take(4).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppTokens.heroGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 16),
                ),
                const SizedBox(width: 9),
                Text(
                  'Amallar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textPrimaryOf(context),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTokens.brandViolet.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${events.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.brandViolet,
                      fontFeatures: AppTokens.tabularNums,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onOpenNakladnoyTab,
                  icon: const Icon(Icons.receipt_long_rounded, size: 14),
                  label: Text(
                    'Nakladnoylar (${summary.nakladnoys.length})',
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  "Hozircha amallar yo'q.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: textSecondaryOf(context),
                  ),
                ),
              )
            else ...[
              ...visibleEvents.map((ev) => _buildTimelineRow(context, ev)),
              if (events.length > 4)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(
                      () => _showAllCashEvents = !_showAllCashEvents,
                    ),
                    child: Text(
                      _showAllCashEvents
                          ? 'Qisqartirish'
                          : "Yana ${events.length - 4} ta ko'rish",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
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

  Widget _buildTimelineRow(BuildContext context, _TimelineEvent ev) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: ev.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ev.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (ev.cashTx != null && widget.canWrite)
            ? () => widget.onEditCashTx(ev.cashTx!)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ev.fg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(ev.icon, color: ev.fg, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ev.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      ev.title == ev.subtitle
                          ? ev.timeHm
                          : '${ev.timeHm} • ${ev.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textSecondaryOf(context),
                        fontFeatures: AppTokens.tabularNums,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${ev.sign}${formatUzs(ev.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: ev.fg,
                  fontFeatures: AppTokens.tabularNums,
                ),
              ),
              if (ev.cashTx != null && widget.canWrite) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  icon: Icon(Icons.more_vert_rounded,
                      size: 17, color: textSecondaryOf(context)),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEditCashTx(ev.cashTx!);
                    if (v == 'delete') widget.onDeleteCashTx(ev.cashTx!);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 17),
                          SizedBox(width: 8),
                          Text('Tahrirlash'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 17, color: AppTokens.dangerRed),
                          SizedBox(width: 8),
                          Text("O'chirish",
                              style: TextStyle(color: AppTokens.dangerRed)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ({
    String title,
    String badge,
    String sign,
    IconData icon,
    Color fg,
    Color bg,
    Color border
  }) _txTypeSpec(BuildContext context, String sourceType) {
    switch (sourceType) {
      case 'kassa_debt':
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.cardBlue);
        return (
          title: 'Kassadan qarz',
          badge: 'Kassa qarz',
          sign: '+',
          icon: Icons.account_balance_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      case 'main_return':
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.brandViolet);
        return (
          title: 'Pul oldim qaytarish',
          badge: 'Qaytarish',
          sign: '−',
          icon: Icons.undo_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      case 'kassa_repay':
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.debtAmber);
        return (
          title: 'Kassaga qaytarish',
          badge: 'Qaytarish',
          sign: '−',
          icon: Icons.assignment_return_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      case 'expense':
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.dangerRed);
        return (
          title: 'Xarajat',
          badge: 'Xarajat',
          sign: '−',
          icon: Icons.trending_down_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      default:
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.cashGreen);
        return (
          title: 'Pul oldim',
          badge: 'Pul oldim',
          sign: '+',
          icon: Icons.add_card_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
    }
  }
}

class _TimelineEvent {
  final String kind; // in | out | debt
  final String timeHm;
  final String createdAt;
  final String badgeText;
  final String title;
  final String subtitle;
  final double amount;
  final String sign;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;
  final CashTxItem? cashTx;

  const _TimelineEvent({
    required this.kind,
    required this.timeHm,
    required this.createdAt,
    required this.badgeText,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.sign,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
    this.cashTx,
  });
}

// ============================================================================
// XARAJATLAR TAQSIMOTI (Glowing Multi-Segment Horizontal Distribution Card)
// ============================================================================

class _GlowingDistributionCard extends StatelessWidget {
  final double cashAmount;
  final double cardAmount;
  final double transferAmount;
  final double debtAmount;
  final int cashCount;
  final int cardCount;
  final int transferCount;
  final int debtCount;
  final String reportDate;
  final ValueChanged<String> onTapMode;

  const _GlowingDistributionCard({
    required this.cashAmount,
    required this.cardAmount,
    required this.transferAmount,
    required this.debtAmount,
    required this.cashCount,
    required this.cardCount,
    required this.transferCount,
    required this.debtCount,
    required this.reportDate,
    required this.onTapMode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final total = cashAmount + cardAmount + transferAmount + debtAmount;
    final totalCount = cashCount + cardCount + transferCount + debtCount;

    final segments = <_DistSeg>[
      _DistSeg('cash', 'Naqd', cashAmount, cashCount, AppTokens.cashGreen,
          const Color(0xFF6EE7B7)),
      _DistSeg('card', 'Karta', cardAmount, cardCount, AppTokens.cardBlue,
          AppTokens.brandSky),
      _DistSeg('transfer', "O'tkazma", transferAmount, transferCount,
          AppTokens.brandViolet, AppTokens.brandOrchid),
      _DistSeg('debt', 'Qarzga', debtAmount, debtCount, AppTokens.debtAmber,
          const Color(0xFFFDE68A)),
    ];

    final nonZero = segments.where((s) => s.value > 0).toList();
    final trackBg = isDark
        ? const Color(0xFF1D1730)
        : const Color(0xFFEDE8F8);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF130F21) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2549) : AppTokens.cardBorderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.30)
                : AppTokens.brandViolet.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTokens.brandViolet.withValues(alpha: 0.22),
                      AppTokens.brandSky.withValues(alpha: 0.16),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppTokens.brandViolet.withValues(alpha: 0.30),
                  ),
                ),
                child: const Icon(Icons.equalizer_rounded,
                    color: AppTokens.brandViolet, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xarajatlar taqsimoti',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      '$reportDate • $totalCount ta chek',
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTokens.brandViolet.withValues(alpha: isDark ? 0.20 : 0.11),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTokens.brandViolet.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  'Jami: ${formatUzsCompact(total)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: isDark ? const Color(0xFFE9D5FF) : AppTokens.brandDeep,
                    fontFeatures: AppTokens.tabularNums,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Signature Glowing Segmented Horizontal Bar
          SizedBox(
            height: 22,
            child: total <= 0 || nonZero.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: trackBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Hozircha xarajat kiritilmagan',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: textSecondaryOf(context),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      for (var i = 0; i < nonZero.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          flex: (nonZero[i].value / total * 1000)
                              .round()
                              .clamp(45, 1000),
                          child: Semantics(
                            button: true,
                            label: nonZero[i].label,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onTapMode(nonZero[i].key);
                              },
                              child: Container(
                                height: 20,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      nonZero[i].color,
                                      nonZero[i].glowEnd,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: nonZero[i].color.withValues(
                                        alpha: isDark ? 0.42 : 0.22,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    height: 2.5,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.36),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 14),

          // Compact 2x2 interactive breakdown tiles
          Row(
            children: [
              Expanded(
                child: _DistributionLegendTile(
                  seg: segments[0],
                  total: total,
                  onTap: () => onTapMode(segments[0].key),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DistributionLegendTile(
                  seg: segments[1],
                  total: total,
                  onTap: () => onTapMode(segments[1].key),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DistributionLegendTile(
                  seg: segments[2],
                  total: total,
                  onTap: () => onTapMode(segments[2].key),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DistributionLegendTile(
                  seg: segments[3],
                  total: total,
                  onTap: () => onTapMode(segments[3].key),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistSeg {
  final String key;
  final String label;
  final double value;
  final int count;
  final Color color;
  final Color glowEnd;

  const _DistSeg(
    this.key,
    this.label,
    this.value,
    this.count,
    this.color,
    this.glowEnd,
  );
}

class _DistributionLegendTile extends StatelessWidget {
  final _DistSeg seg;
  final double total;
  final VoidCallback onTap;

  const _DistributionLegendTile({
    required this.seg,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final pct = total > 0 ? ((seg.value / total) * 100).round() : 0;
    final (fg, bg, border) = AppTokens.semanticSurface(context, seg.color);

    return Material(
      color: isDark
          ? const Color(0xFF1A152C).withValues(alpha: 0.72)
          : const Color(0xFFF8F6FD),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: seg.value > 0
                  ? border
                  : (isDark
                      ? AppTokens.cardBorderDark
                      : AppTokens.cardBorderLight),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: seg.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: seg.color.withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      seg.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: fg,
                        fontFeatures: AppTokens.tabularNums,
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
                  '${formatUzs(seg.value)} • ${seg.count} ta',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: textSecondaryOf(context),
                    fontFeatures: AppTokens.tabularNums,
                  ),
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
// DINAMIKA (Glowing Paired Bar & Smooth Bezier Line/Area Chart Card)
// ============================================================================

class _TrendLineStatisticsCard extends StatelessWidget {
  final List<Map<String, dynamic>> dailySeries;
  final String seriesGranularity;
  final String periodLabel;
  final String activePeriodKey;
  final int? selectedIdx;
  final bool isBarMode;
  final ValueChanged<bool> onToggleBarMode;
  final ValueChanged<int> onSelectIdx;
  final ValueChanged<String> onSelectPeriodKey;
  final VoidCallback onPickCustomDateRange;

  const _TrendLineStatisticsCard({
    required this.dailySeries,
    this.seriesGranularity = 'daily',
    required this.periodLabel,
    required this.activePeriodKey,
    required this.selectedIdx,
    this.isBarMode = true,
    required this.onToggleBarMode,
    required this.onSelectIdx,
    required this.onSelectPeriodKey,
    required this.onPickCustomDateRange,
  });

  int? _defaultActiveIdx(List<Map<String, dynamic>> pts, bool isHourly) {
    if (pts.isEmpty) return null;
    if (isHourly) {
      for (var i = pts.length - 1; i >= 0; i--) {
        final sp = ((pts[i]['spent'] as num?) ?? 0).toDouble();
        final ci = ((pts[i]['cash_in'] as num?) ?? 0).toDouble();
        if (sp > 0 || ci > 0) return i;
      }
    }
    for (var i = pts.length - 1; i >= 0; i--) {
      final sp = ((pts[i]['spent'] as num?) ?? 0).toDouble();
      final ci = ((pts[i]['cash_in'] as num?) ?? 0).toDouble();
      if (sp > 0 || ci > 0) return i;
    }
    return pts.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final pts = dailySeries;
    final isHourly = seriesGranularity == 'hourly' ||
        (pts.isNotEmpty && pts.first['date'].toString().contains(':'));
    final activeIdx = (selectedIdx != null &&
            selectedIdx! >= 0 &&
            selectedIdx! < pts.length)
        ? selectedIdx!
        : _defaultActiveIdx(pts, isHourly);
    final selectedPt = activeIdx != null ? pts[activeIdx] : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCustom = activePeriodKey == 'custom';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF130F21) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2E2549) : AppTokens.cardBorderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.30)
                : AppTokens.brandViolet.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTokens.brandViolet.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: AppTokens.brandViolet.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  isBarMode
                      ? Icons.bar_chart_rounded
                      : Icons.show_chart_rounded,
                  color: AppTokens.brandViolet,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dinamika',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      periodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Compact Ustun / Chiziq toggle pill
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C1631)
                      : const Color(0xFFF3EEFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? AppTokens.cardBorderDark
                        : AppTokens.cardBorderLight,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ChartModeChip(
                      label: 'Ustun',
                      selected: isBarMode,
                      onTap: () {
                        if (!isBarMode) {
                          HapticFeedback.selectionClick();
                          onToggleBarMode(true);
                        }
                      },
                    ),
                    _ChartModeChip(
                      label: 'Chiziq',
                      selected: !isBarMode,
                      onTap: () {
                        if (isBarMode) {
                          HapticFeedback.selectionClick();
                          onToggleBarMode(false);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: isCustom
                    ? AppTokens.brand
                    : (isDark
                        ? const Color(0xFF1C1631)
                        : AppTokens.surfaceLight),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onPickCustomDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 6.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCustom
                            ? AppTokens.brand
                            : (isDark
                                ? AppTokens.cardBorderDark
                                : AppTokens.cardBorderLight),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          size: 14.5,
                          color: isCustom
                              ? Colors.white
                              : textSecondaryOf(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Sana',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: isCustom
                                ? Colors.white
                                : textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Horizontally scrollable Period Presets (Bugun | Kecha | 7 kun | 14 kun | 30 kun)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _periodPill(context, 'today', 'Bugun', Icons.today_rounded),
                const SizedBox(width: 8),
                _periodPill(context, 'yesterday', 'Kecha',
                    Icons.history_toggle_off_rounded),
                const SizedBox(width: 8),
                _periodPill(context, '7d', '7 kun', null),
                const SizedBox(width: 8),
                _periodPill(context, '14d', '14 kun', null),
                const SizedBox(width: 8),
                _periodPill(context, '30d', '30 kun', null),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (selectedPt != null) ...[
            Builder(builder: (context) {
              final ptLabel =
                  (selectedPt['label'] ?? selectedPt['date']).toString();
              final spentVal = ((selectedPt['spent'] as num?) ?? 0).toDouble();
              final cashInVal =
                  ((selectedPt['cash_in'] as num?) ?? 0).toDouble();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            const Color(0xFF211A3A),
                            const Color(0xFF19132D),
                          ]
                        : [
                            const Color(0xFFF6F1FE),
                            const Color(0xFFFAF8FF),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTokens.brandViolet.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTokens.brandViolet
                            .withValues(alpha: isDark ? 0.26 : 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isHourly
                                ? Icons.schedule_rounded
                                : Icons.calendar_today_rounded,
                            size: 13,
                            color: isDark
                                ? const Color(0xFFE9D5FF)
                                : AppTokens.brandDeep,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            ptLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white
                                  : AppTokens.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppTokens.brandOrchid,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  "Rasxod: ${formatUzs(spentVal)} (${selectedPt['count']} ta)",
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    color: isDark
                                        ? const Color(0xFFF5D0FE)
                                        : AppTokens.brandDeep,
                                    fontFeatures: AppTokens.tabularNums,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (cashInVal > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: AppTokens.brandSky,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      "Kirim: +${formatUzs(cashInVal)} so'm",
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5,
                                        color: isDark
                                            ? AppTokens.brandSky
                                            : AppTokens.cardBlue,
                                        fontFeatures: AppTokens.tabularNums,
                                      ),
                                    ),
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
            }),
          ],
          const SizedBox(height: 12),

          if (pts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                "Tanlangan sanalar oralig'ida ma'lumot topilmadi",
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondaryOf(context)),
              ),
            )
          else
            RepaintBoundary(
              child: SizedBox(
                height: 170,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    void handleDx(double dx) {
                      if (pts.isEmpty) return;
                      if (pts.length == 1) {
                        onSelectIdx(0);
                        return;
                      }
                      const hPad = 14.0;
                      final chartW = (constraints.maxWidth - hPad * 2)
                          .clamp(1.0, double.infinity);
                      final rel = ((dx - hPad) / chartW).clamp(0.0, 1.0);
                      final idx = (rel * (pts.length - 1))
                          .round()
                          .clamp(0, pts.length - 1);
                      onSelectIdx(idx);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => handleDx(d.localPosition.dx),
                      onHorizontalDragStart: (d) =>
                          handleDx(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) =>
                          handleDx(d.localPosition.dx),
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, 170),
                        painter: isBarMode
                            ? _GlowingCashFlowBarPainter(
                                points: pts,
                                selectedIdx: activeIdx ?? 0,
                                isDark: isDark,
                                gridColor: textSecondaryOf(context)
                                    .withValues(alpha: 0.16),
                                labelColor: textSecondaryOf(context),
                              )
                            : _SmoothLineChartPainter(
                                points: pts,
                                selectedIdx: activeIdx ?? 0,
                                lineColor: AppTokens.brandViolet,
                                inflowColor: AppTokens.brandSky,
                                gridColor: textSecondaryOf(context)
                                    .withValues(alpha: 0.16),
                                labelColor: textSecondaryOf(context),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTokens.brandViolet, AppTokens.brandOrchid],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.brandOrchid.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isHourly
                    ? 'Soatlik nakladnoy rasxod'
                    : 'Kunlik nakladnoy rasxod',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondaryOf(context),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTokens.cardBlue, AppTokens.brandSky],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTokens.brandSky.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Olingan pul (Kirim)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _periodPill(
      BuildContext context, String key, String label, IconData? icon) {
    final sel = activePeriodKey == key;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        gradient: sel
            ? const LinearGradient(
                colors: [AppTokens.brand, AppTokens.brandOrchid],
              )
            : null,
        color: sel
            ? null
            : (isDark
                ? const Color(0xFF1C1631)
                : AppTokens.surfaceLight),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: sel
              ? AppTokens.brandViolet
              : (isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight),
        ),
        boxShadow: sel
            ? [
                BoxShadow(
                  color: AppTokens.brandViolet.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: sel
            ? null
            : () {
                HapticFeedback.selectionClick();
                onSelectPeriodKey(key);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: sel ? Colors.white : textSecondaryOf(context),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: sel ? Colors.white : textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChartModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTokens.brand, AppTokens.brandViolet],
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected
                ? Colors.white
                : (isDark
                    ? AppTokens.textSecondaryDark
                    : AppTokens.textSecondaryLight),
          ),
        ),
      ),
    );
  }
}

class _GlowingCashFlowBarPainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final int selectedIdx;
  final bool isDark;
  final Color gridColor;
  final Color labelColor;

  const _GlowingCashFlowBarPainter({
    required this.points,
    required this.selectedIdx,
    required this.isDark,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 14.0;
    const bottomPad = 24.0;
    const hPad = 14.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width - hPad * 2;
    final baselineY = topPad + chartH;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + (chartH / 3) * i;
      canvas.drawLine(Offset(hPad, y), Offset(size.width - hPad, y), gridPaint);
    }

    double maxVal = 1.0;
    for (final p in points) {
      final s = ((p['spent'] as num?) ?? 0).toDouble();
      final c = ((p['cash_in'] as num?) ?? 0).toDouble();
      if (s > maxVal) maxVal = s;
      if (c > maxVal) maxVal = c;
    }

    final count = points.length;
    final slotW = count <= 1 ? chartW : chartW / count;
    final pairW = (slotW * 0.70).clamp(8.0, 32.0);
    final gap = count > 18 ? 1.5 : 3.0;
    final barW = ((pairW - gap) / 2).clamp(3.0, 14.0);
    final radius = Radius.circular((barW / 2).clamp(3.0, 6.0));
    final step = math.max(1, (count / 5).ceil());

    final unselectedSpentPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.13)
          : AppTokens.brandViolet.withValues(alpha: 0.16);
    final unselectedInPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : AppTokens.cardBlue.withValues(alpha: 0.12);

    for (var i = 0; i < count; i++) {
      final centerX = count <= 1
          ? size.width / 2
          : hPad + slotW * i + slotW / 2;
      final spent = ((points[i]['spent'] as num?) ?? 0).toDouble();
      final cashIn = ((points[i]['cash_in'] as num?) ?? 0).toDouble();
      final isSel = i == selectedIdx;

      final spentH = spent > 0
          ? ((spent / maxVal).clamp(0.0, 1.0) * chartH).clamp(6.0, chartH)
          : 4.0;
      final inH = cashIn > 0
          ? ((cashIn / maxVal).clamp(0.0, 1.0) * chartH).clamp(6.0, chartH)
          : 4.0;

      final spentRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          centerX - barW - gap / 2,
          baselineY - spentH,
          barW,
          spentH,
        ),
        topLeft: radius,
        topRight: radius,
      );
      final inRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(
          centerX + gap / 2,
          baselineY - inH,
          barW,
          inH,
        ),
        topLeft: radius,
        topRight: radius,
      );

      if (isSel) {
        if (spent > 0) {
          canvas.drawRRect(
            spentRect,
            Paint()
              ..color = AppTokens.brandOrchid.withValues(alpha: 0.42)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
          );
        }
        canvas.drawRRect(
          spentRect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF9333EA), Color(0xFFE879F9)],
            ).createShader(spentRect.outerRect),
        );

        if (cashIn > 0) {
          canvas.drawRRect(
            inRect,
            Paint()
              ..color = AppTokens.brandSky.withValues(alpha: 0.40)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
          );
        }
        canvas.drawRRect(
          inRect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
            ).createShader(inRect.outerRect),
        );
      } else {
        canvas.drawRRect(spentRect, unselectedSpentPaint);
        canvas.drawRRect(inRect, unselectedInPaint);
      }

      if (i % step == 0 || i == count - 1) {
        final rawDate = points[i]['date'].toString();
        final shortDate =
            rawDate.length >= 10 ? rawDate.substring(5, 10) : rawDate;
        final tp = TextPainter(
          text: TextSpan(
            text: shortDate,
            style: TextStyle(
              color: isSel
                  ? (isDark ? Colors.white : AppTokens.brandDeep)
                  : labelColor,
              fontSize: 10,
              fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (centerX - tp.width / 2).clamp(0.0, size.width - tp.width),
            baselineY + 6,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GlowingCashFlowBarPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIdx != selectedIdx ||
      oldDelegate.isDark != isDark ||
      oldDelegate.labelColor != labelColor;
}

class _SmoothLineChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  final int selectedIdx;
  final Color lineColor;
  final Color inflowColor;
  final Color gridColor;
  final Color labelColor;

  const _SmoothLineChartPainter({
    required this.points,
    required this.selectedIdx,
    required this.lineColor,
    required this.inflowColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 14.0;
    const bottomPad = 24.0;
    const hPad = 14.0;
    final chartH = size.height - topPad - bottomPad;
    final chartW = size.width - hPad * 2;

    // Horizontal grid lines
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + (chartH / 3) * i;
      canvas.drawLine(Offset(hPad, y), Offset(size.width - hPad, y), gridPaint);
    }

    double maxVal = 1.0;
    for (final p in points) {
      final s = ((p['spent'] as num?) ?? 0).toDouble();
      final c = ((p['cash_in'] as num?) ?? 0).toDouble();
      if (s > maxVal) maxVal = s;
      if (c > maxVal) maxVal = c;
    }

    Offset ptFor(int idx, double val) {
      final x = points.length <= 1
          ? size.width / 2
          : hPad + (chartW * idx / (points.length - 1));
      final ratio = (val / maxVal).clamp(0.0, 1.0);
      final y = topPad + chartH * (1.0 - ratio);
      return Offset(x, y);
    }

    final spentOffsets = <Offset>[];
    final inflowOffsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      spentOffsets
          .add(ptFor(i, ((points[i]['spent'] as num?) ?? 0).toDouble()));
      inflowOffsets
          .add(ptFor(i, ((points[i]['cash_in'] as num?) ?? 0).toDouble()));
    }

    // Subtle vertical dashed guide at selectedIdx
    if (selectedIdx >= 0 && selectedIdx < spentOffsets.length) {
      final gx = spentOffsets[selectedIdx].dx;
      final guidePaint = Paint()
        ..color = lineColor.withValues(alpha: 0.34)
        ..strokeWidth = 1.2;
      for (var y = topPad; y < topPad + chartH; y += 6) {
        canvas.drawLine(
          Offset(gx, y),
          Offset(gx, math.min(y + 3, topPad + chartH)),
          guidePaint,
        );
      }
    }

    // Draw inflow curve
    if (inflowOffsets.length >= 2) {
      final inPath = _buildSmoothPath(inflowOffsets);
      final inPaint = Paint()
        ..color = inflowColor.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(inPath, inPaint);
    }

    // Draw spent smooth curve + neon halo + gradient area
    if (spentOffsets.isNotEmpty) {
      final linePath = _buildSmoothPath(spentOffsets);
      if (spentOffsets.length >= 2) {
        final areaPath = Path.from(linePath)
          ..lineTo(spentOffsets.last.dx, topPad + chartH)
          ..lineTo(spentOffsets.first.dx, topPad + chartH)
          ..close();
        final areaPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.34),
              AppTokens.brandOrchid.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH));
        canvas.drawPath(areaPath, areaPaint);
      }

      // Soft neon glow behind the main Bezier curve
      canvas.drawPath(
        linePath,
        Paint()
          ..color = lineColor.withValues(alpha: 0.36)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      final strokePaint = Paint()
        ..shader = const LinearGradient(
          colors: [AppTokens.brandViolet, AppTokens.brandOrchid],
        ).createShader(Rect.fromLTWH(hPad, topPad, chartW, chartH))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(linePath, strokePaint);

      for (var i = 0; i < spentOffsets.length; i++) {
        final o = spentOffsets[i];
        final isSel = i == selectedIdx;
        if (isSel) {
          canvas.drawCircle(
            o,
            10.0,
            Paint()..color = AppTokens.brandOrchid.withValues(alpha: 0.25),
          );
        }
        canvas.drawCircle(
          o,
          isSel ? 5.8 : 3.6,
          Paint()..color = isSel ? AppTokens.brandOrchid : Colors.white,
        );
        canvas.drawCircle(
          o,
          isSel ? 5.8 : 3.6,
          Paint()
            ..color = isSel ? Colors.white : lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSel ? 2.2 : 2.0,
        );

        final step = math.max(1, (points.length / 5).ceil());
        if (i % step == 0 || i == points.length - 1) {
          final rawDate = points[i]['date'].toString();
          final shortDate =
              rawDate.length >= 10 ? rawDate.substring(5, 10) : rawDate;
          final tp = TextPainter(
            text: TextSpan(
              text: shortDate,
              style: TextStyle(
                color: isSel ? lineColor : labelColor,
                fontSize: 10,
                fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              (o.dx - tp.width / 2).clamp(0.0, size.width - tp.width),
              topPad + chartH + 6,
            ),
          );
        }
      }
    }
  }

  Path _buildSmoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) {
      path.lineTo(pts.first.dx + 1, pts.first.dy);
      return path;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _SmoothLineChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIdx != selectedIdx ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelColor != labelColor;
}

class _PaymentKpiCard extends StatelessWidget {
  final String title;
  final double amount;
  final int animSeed;
  final int count;
  final double share;
  final IconData icon;
  final Color color;
  final bool isFeatured;
  final String? subtitle;
  final VoidCallback onTap;

  const _PaymentKpiCard({
    required this.title,
    required this.amount,
    this.animSeed = 0,
    required this.count,
    required this.share,
    required this.icon,
    required this.color,
    this.isFeatured = false,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final (fg, bg, border) = AppTokens.semanticSurface(context, color);
    final pct = (share.clamp(0.0, 1.0) * 100).round();

    return TactileScaleTap(
      pressedScale: 0.985,
      haptic: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF130F21) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isFeatured
                ? color.withValues(alpha: isDark ? 0.56 : 0.42)
                : (isDark
                    ? const Color(0xFF2B2344)
                    : AppTokens.cardBorderLight),
            width: isFeatured ? 1.2 : 1.0,
          ),
          boxShadow: [
            if (isFeatured)
              BoxShadow(
                color: color.withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Top inner neon wash (prominent on featured KPI card)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: isFeatured ? 46 : 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(
                            alpha: isFeatured
                                ? (isDark ? 0.34 : 0.16)
                                : (isDark ? 0.10 : 0.05),
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Bright top hairline accent bar
              Positioned(
                top: 0,
                left: 16,
                right: 16,
                height: isFeatured ? 2.6 : 1.8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(4)),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        color.withValues(alpha: isFeatured ? 0.95 : 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 14, 13, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.65),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: textSecondaryOf(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                    color: border.withValues(alpha: 0.6)),
                              ),
                              child: Text(
                                '$count ta • $pct%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: fg,
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AnimatedUzsNumber(
                            value: amount,
                            withCurrency: true,
                            animSeed: animSeed,
                            duration: const Duration(milliseconds: 650),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: textPrimaryOf(context),
                              fontFeatures: AppTokens.tabularNums,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        LayoutBuilder(
                          builder: (context, barBox) => Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: barBox.maxWidth *
                                  share.clamp(0.0, 1.0),
                              height: 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: LinearGradient(
                                  colors: [color, fg],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4-way payment mode selector (`cash` | `card` | `transfer` | `debt`) with high-contrast Light/Dark styling.
class PaymentModeSelector extends StatelessWidget {
  final String selectedMode;
  final ValueChanged<String> onChanged;

  const PaymentModeSelector({
    super.key,
    required this.selectedMode,
    required this.onChanged,
  });

  static const List<Map<String, dynamic>> modes = [
    {
      'key': 'cash',
      'label': 'Naqd',
      'icon': Icons.payments_rounded,
      'sub': 'Kassadan ayriladi',
      'color': AppTokens.cashGreen,
    },
    {
      'key': 'card',
      'label': 'Karta',
      'icon': Icons.credit_card_rounded,
      'sub': 'Statistikada',
      'color': AppTokens.cardBlue,
    },
    {
      'key': 'transfer',
      'label': "O'tkazma",
      'icon': Icons.account_balance_rounded,
      'sub': 'Perechesleniya',
      'color': AppTokens.transferPurple,
    },
    {
      'key': 'debt',
      'label': 'Qarzga',
      'icon': Icons.push_pin_rounded,
      'sub': "Pul berilmadi — to'lanmagan qarzga yoziladi",
      'color': AppTokens.debtAmber,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final current = modes.firstWhere(
      (m) => m['key'] == selectedMode,
      orElse: () => modes.first,
    );
    final Color baseColor = current['color'] as Color;
    final (activeFg, activeBg, activeBorder) =
        AppTokens.semanticSurface(context, baseColor);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isDark
                ? AppTokens.surfaceDark.withValues(alpha: 0.7)
                : Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
            ),
          ),
          child: Row(
            children: List.generate(modes.length, (i) {
              final m = modes[i];
              final key = m['key'] as String;
              final isSelected = key == selectedMode;
              final c = m['color'] as Color;
              final (fg, bg, border) = AppTokens.semanticSurface(context, c);
              final ic = m['icon'] as IconData;

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < modes.length - 1 ? 6 : 0),
                  child: TactileScaleTap(
                    pressedScale: 0.95,
                    haptic: false,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(key);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              vertical: 9, horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? bg : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? border : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    scale: isSelected ? 1.12 : 1.0,
                                    duration:
                                        const Duration(milliseconds: 180),
                                    curve: Curves.easeOutBack,
                                    child: Icon(
                                      ic,
                                      size: 18,
                                      color: isSelected
                                          ? fg
                                          : textSecondaryOf(context),
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 3),
                                    Icon(Icons.check_circle_rounded,
                                        size: 12, color: fg),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  m['label'] as String,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    fontSize: 12.5,
                                    color:
                                        isSelected ? fg : textPrimaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: activeBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: activeBorder.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: activeFg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  current['sub'] as String,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: activeFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NakladnoyListCard extends StatelessWidget {
  final NakladnoyItem item;
  final VoidCallback onTap;
  final VoidCallback? onQuickPay;

  const NakladnoyListCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onQuickPay,
  });

  (String, IconData, Color) _badgeSpec() {
    if (item.isDebt) {
      return ('Qarzga', Icons.push_pin_rounded, AppTokens.debtAmber);
    }
    switch (item.paymentMethod) {
      case 'card':
        return ('Karta', Icons.credit_card_rounded, AppTokens.cardBlue);
      case 'transfer':
        return (
          "O'tkazma",
          Icons.account_balance_rounded,
          AppTokens.transferPurple
        );
      default:
        return ('Naqd', Icons.payments_rounded, AppTokens.cashGreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final (badgeText, badgeIcon, baseColor) = _badgeSpec();
    final (fg, bg, border) = AppTokens.semanticSurface(context, baseColor);
    final (grpFg, _, _) =
        AppTokens.semanticSurface(context, AppTokens.cashGreen);

    return TactileScaleTap(
      pressedScale: 0.985,
      haptic: false,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF130F21) : Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(
            color: item.isDebt
                ? border.withValues(alpha: 0.72)
                : (isDark
                    ? const Color(0xFF2D2448)
                    : AppTokens.cardBorderLight),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.24)
                  : baseColor.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 10,
                bottom: 10,
                width: 3.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [baseColor, fg],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.50),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTokens.radius),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 15, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: border),
                              ),
                              child: Text(
                                item.displayNum,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: AppTokens.tabularNums,
                                  color: fg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.supplierName,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 3,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.schedule_rounded,
                                              size: 12.5,
                                              color: textSecondaryOf(context)),
                                          const SizedBox(width: 3),
                                          Text(
                                            item.reportDate != null
                                                ? '${item.reportDate} • ${item.timeHm}'
                                                : item.timeHm,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: textSecondaryOf(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            item.inGroup
                                                ? Icons.cloud_done_rounded
                                                : Icons.storage_rounded,
                                            size: 13.5,
                                            color: item.inGroup
                                                ? grpFg
                                                : textSecondaryOf(context),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            item.inGroup ? 'Guruhda' : 'Bazada',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: item.inGroup
                                                  ? grpFg
                                                  : textSecondaryOf(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.hasPhoto)
                                        Icon(Icons.image_rounded,
                                            size: 14, color: fg),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatUzs(item.amount, withCurrency: true),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: AppTokens.tabularNums,
                                    color: item.isDebt
                                        ? fg
                                        : textPrimaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(badgeIcon, size: 12, color: fg),
                                      const SizedBox(width: 4),
                                      Text(
                                        badgeText,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: fg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (item.note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '💬 ${item.note}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: textSecondaryOf(context),
                            ),
                          ),
                        ],
                        if (onQuickPay != null && item.isDebt) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              onPressed: onQuickPay,
                              icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 18),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "Qarzni to'lash (Naqd / Karta / O'tkazma)",
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
// HISOBCHI CUSTOM DROPDOWN PICKER (Modern Rounded Modal Sheet Selector)
// ============================================================================

class CustomDropdownOption<T> {
  final T value;
  final String label;
  final String? selectedLabel;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final String? badge;

  const CustomDropdownOption({
    required this.value,
    required this.label,
    this.selectedLabel,
    this.subtitle,
    this.icon,
    this.accentColor,
    this.badge,
  });
}

class HisobchiCustomDropdown<T> extends StatelessWidget {
  final T value;
  final List<CustomDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? labelText;
  final String? sheetTitle;
  final String? placeholder;
  final bool compact;
  final bool enabled;
  final bool searchable;

  const HisobchiCustomDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelText,
    this.sheetTitle,
    this.placeholder,
    this.compact = false,
    this.enabled = true,
    this.searchable = false,
  });

  CustomDropdownOption<T>? get _selectedOption {
    for (final opt in options) {
      if (opt.value == value) return opt;
    }
    return options.isNotEmpty ? options.first : null;
  }

  Future<void> _openPickerSheet(BuildContext context) async {
    if (!enabled || options.isEmpty) return;
    HapticFeedback.selectionClick();
    final showSearch = searchable || options.length >= 8;
    final result = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustomDropdownSheet<T>(
        title: sheetTitle ?? labelText ?? 'Tanlang',
        currentValue: value,
        options: options,
        searchable: showSearch,
      ),
    );
    if (result != null) {
      HapticFeedback.selectionClick();
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sel = _selectedOption;
    final accent = sel?.accentColor ?? AppTokens.brand;
    final (fg, bg, border) = AppTokens.semanticSurface(context, accent);
    final surfaceBg = isDark ? AppTokens.cardDark : Colors.white;
    final defaultBorder =
        isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelText != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 5),
            child: Text(
              labelText!,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: textSecondaryOf(context),
              ),
            ),
          ),
        ],
        AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: enabled ? 1.0 : 0.55,
          child: Material(
            color: surfaceBg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? () => _openPickerSheet(context) : null,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 12,
                  vertical: compact ? 7.5 : 10.5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sel != null
                        ? accent.withValues(alpha: isDark ? 0.34 : 0.24)
                        : defaultBorder,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    if (sel?.icon != null) ...[
                      Container(
                        width: compact ? 24 : 30,
                        height: compact ? 24 : 30,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(compact ? 7 : 8),
                          border: Border.all(color: border),
                        ),
                        child: Icon(
                          sel!.icon,
                          size: compact ? 14 : 17,
                          color: fg,
                        ),
                      ),
                      SizedBox(width: compact ? 6 : 9),
                    ],
                    Expanded(
                      child: Text(
                        sel?.selectedLabel ??
                            sel?.label ??
                            placeholder ??
                            'Tanlang',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 13 : 13.5,
                          fontWeight: FontWeight.w800,
                          color: textPrimaryOf(context),
                        ),
                      ),
                    ),
                    if (sel?.badge != null && sel!.badge!.isNotEmpty) ...[
                      SizedBox(width: compact ? 4 : 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 6 : 7,
                          vertical: compact ? 2 : 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: border),
                        ),
                        child: Text(
                          sel.badge!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: fg,
                            fontFeatures: AppTokens.tabularNums,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(width: compact ? 3 : 6),
                    if (compact)
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 17,
                        color: textSecondaryOf(context),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTokens.surfaceDark.withValues(alpha: 0.7)
                              : AppTokens.surfaceLight,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: textSecondaryOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomDropdownSheet<T> extends StatefulWidget {
  final String title;
  final T currentValue;
  final List<CustomDropdownOption<T>> options;
  final bool searchable;

  const _CustomDropdownSheet({
    required this.title,
    required this.currentValue,
    required this.options,
    required this.searchable,
  });

  @override
  State<_CustomDropdownSheet<T>> createState() =>
      _CustomDropdownSheetState<T>();
}

class _CustomDropdownSheetState<T> extends State<_CustomDropdownSheet<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppTokens.cardDark : Colors.white;
    final mq = MediaQuery.of(context);
    final available = (mq.size.height -
            mq.viewPadding.top -
            mq.viewPadding.bottom -
            mq.viewInsets.bottom)
        .clamp(120.0, mq.size.height);
    final target = mq.size.height * 0.74;
    final maxH = (target < available ? target : available)
        .clamp(available < 240.0 ? available : 240.0, mq.size.height);
    final insets = mq.viewInsets.bottom;
    final bottomPad = (insets > 0 ? insets : 0.0) + 18.0;

    final filtered = _query.isEmpty
        ? widget.options
        : widget.options.where((o) {
            final q = _query.toLowerCase();
            return o.label.toLowerCase().contains(q) ||
                (o.subtitle?.toLowerCase().contains(q) ?? false);
          }).toList();

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? AppTokens.cardBorderDark
                  : AppTokens.cardBorderLight,
            ),
          ),
        ),
        padding: EdgeInsets.fromLTRB(18, 10, 18, bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textSecondaryOf(context).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: textPrimaryOf(context),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (widget.searchable) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Qidirish...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  "Mos variant topilmadi",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondaryOf(context)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (ctx, i) {
                    final opt = filtered[i];
                    final isSel = opt.value == widget.currentValue;
                    final accent = opt.accentColor ?? AppTokens.brand;
                    final (fg, bg, border) =
                        AppTokens.semanticSurface(ctx, accent);
                    final idleBg = isDark
                        ? AppTokens.surfaceDark.withValues(alpha: 0.55)
                        : AppTokens.surfaceLight;
                    final idleBorder = isDark
                        ? AppTokens.cardBorderDark
                        : AppTokens.cardBorderLight;

                    return Material(
                      color: isSel ? bg : idleBg,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, opt.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSel ? border : idleBorder,
                              width: isSel ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (opt.icon != null) ...[
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(opt.icon, size: 18, color: fg),
                                ),
                                const SizedBox(width: 11),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opt.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSel
                                            ? FontWeight.w900
                                            : FontWeight.w700,
                                        color: isSel
                                            ? fg
                                            : textPrimaryOf(ctx),
                                      ),
                                    ),
                                    if (opt.subtitle != null &&
                                        opt.subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        opt.subtitle!,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: textSecondaryOf(ctx),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (opt.badge != null &&
                                  opt.badge!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: border),
                                  ),
                                  child: Text(
                                    opt.badge!,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      color: fg,
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                ),
                              ],
                              if (isSel) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle_rounded,
                                    color: fg, size: 20),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ANIMATED GLOWING LOGO SPLASH & DASHBOARD LOADING SKELETON
// ============================================================================

class HisobchiAnimatedLoadingScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const HisobchiAnimatedLoadingScreen({
    super.key,
    this.title = 'Hisobchi',
    this.subtitle = 'Ilova tayyorlanmoqda...',
  });

  @override
  Widget build(BuildContext context) {
    return HisobchiSplash(
      title: title,
      subtitle: subtitle,
    );
  }
}

class DashboardLoadingSkeleton extends StatefulWidget {
  const DashboardLoadingSkeleton({super.key});

  @override
  State<DashboardLoadingSkeleton> createState() =>
      _DashboardLoadingSkeletonState();
}

class _DashboardLoadingSkeletonState extends State<DashboardLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _shimmerBox({
    required double height,
    double? width,
    double radius = 12,
    required double phase,
    required Color baseColor,
    required Color highlightColor,
  }) {
    final slide = -1.2 + 2.4 * phase;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(slide - 0.7, -0.3),
          end: Alignment(slide + 0.7, 0.3),
          colors: [baseColor, highlightColor, baseColor],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final baseBg =
        isDark ? const Color(0xFF1A142B) : const Color(0xFFECE7F7);
    final hiBg =
        isDark ? const Color(0xFF2C2248) : const Color(0xFFF7F4FD);
    final heroBase = Colors.white.withValues(alpha: 0.14);
    final heroHi = Colors.white.withValues(alpha: 0.30);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;

        Widget box(double h, {double? w, double r = 10, bool onHero = false}) =>
            _shimmerBox(
              height: h,
              width: w,
              radius: r,
              phase: t,
              baseColor: onHero ? heroBase : baseBg,
              highlightColor: onHero ? heroHi : hiBg,
            );

        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            mainTabScrollBottomPadding(context, hasFab: true),
          ),
          children: [
            // Date switcher capsule placeholder
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF130F21) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? AppTokens.brandViolet.withValues(alpha: 0.24)
                      : AppTokens.cardBorderLight,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  box(28, w: 34, r: 9),
                  box(18, w: 150, r: 9),
                  box(28, w: 34, r: 9),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Mirror HeroBalanceCard
            Container(
              decoration: BoxDecoration(
                gradient: AppTokens.heroGradient,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFE879F9).withValues(alpha: 0.30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTokens.brandViolet.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      box(26, w: 102, r: 20, onHero: true),
                      box(26, w: 132, r: 20, onHero: true),
                    ],
                  ),
                  const SizedBox(height: 18),
                  box(14, w: 185, r: 6, onHero: true),
                  const SizedBox(height: 10),
                  box(36, w: 220, r: 10, onHero: true),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0614).withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFF5D0FE).withValues(alpha: 0.16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: box(36, r: 8, onHero: true)),
                            const SizedBox(width: 14),
                            Expanded(child: box(36, r: 8, onHero: true)),
                          ],
                        ),
                        const Divider(color: Colors.white12, height: 18),
                        Row(
                          children: [
                            Expanded(child: box(26, r: 8, onHero: true)),
                            const SizedBox(width: 10),
                            Expanded(child: box(26, r: 8, onHero: true)),
                            const SizedBox(width: 10),
                            Expanded(child: box(26, r: 8, onHero: true)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: box(52, r: 14, onHero: true)),
                      const SizedBox(width: 12),
                      Expanded(child: box(52, r: 14, onHero: true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: box(52, r: 14, onHero: true)),
                      const SizedBox(width: 12),
                      Expanded(child: box(52, r: 14, onHero: true)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Mirror Quick action glass pills (Sverka / Arxiv)
            Row(
              children: [
                Expanded(child: box(46, r: 16)),
                const SizedBox(width: 10),
                Expanded(child: box(46, r: 16)),
              ],
            ),
            const SizedBox(height: 14),

            // Mirror Xarajatlar taqsimoti card
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF130F21) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2D2448)
                      : AppTokens.cardBorderLight,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      box(20, w: 170, r: 8),
                      box(24, w: 86, r: 10),
                    ],
                  ),
                  const SizedBox(height: 14),
                  box(20, r: 8),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: box(48, r: 12)),
                      const SizedBox(width: 8),
                      Expanded(child: box(48, r: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: box(48, r: 12)),
                      const SizedBox(width: 8),
                      Expanded(child: box(48, r: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Mirror 2x2 Neon KPI Bento Cards
            Row(
              children: [
                Expanded(child: box(92, r: 18)),
                const SizedBox(width: 10),
                Expanded(child: box(92, r: 18)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: box(92, r: 18)),
                const SizedBox(width: 10),
                Expanded(child: box(92, r: 18)),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// TACTILE BUTTON PRESS & FLOATING ACTION-COMPLETION FEEDBACK ANIMATIONS
// ============================================================================

/// Adds a springy scale-down press micro-interaction and optional haptic feedback
/// without interfering with child InkWell / Button / Scroll gestures.
class TactileScaleTap extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final bool enabled;
  final bool haptic;

  const TactileScaleTap({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
    this.enabled = true,
    this.haptic = true,
  });

  @override
  State<TactileScaleTap> createState() => _TactileScaleTapState();
}

class _TactileScaleTapState extends State<TactileScaleTap> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    if (value && widget.enabled && widget.haptic) {
      HapticFeedback.lightImpact();
    }
    if (mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: (_pressed && widget.enabled) ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 90 : 150),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

OverlayEntry? _activeFeedbackEntry;

/// Shows a sleek spring-animated floating confirmation / error pill at the top
/// of the screen with haptic feedback.
void showActionFeedbackBanner(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  if (isError) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.mediumImpact();
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeFeedbackEntry?.remove();
  _activeFeedbackEntry = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _ActionFeedbackOverlayWidget(
      message: message,
      isError: isError,
      duration: duration,
      onDismissed: () {
        if (_activeFeedbackEntry == entry) {
          _activeFeedbackEntry = null;
        }
        if (entry.mounted) {
          entry.remove();
        }
      },
    ),
  );
  _activeFeedbackEntry = entry;
  overlay.insert(entry);
}

class _ActionFeedbackOverlayWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback onDismissed;

  const _ActionFeedbackOverlayWidget({
    required this.message,
    required this.isError,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_ActionFeedbackOverlayWidget> createState() =>
      _ActionFeedbackOverlayWidgetState();
}

class _ActionFeedbackOverlayWidgetState
    extends State<_ActionFeedbackOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _ctrl.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bgColor =
        widget.isError ? AppTokens.dangerRed : const Color(0xFF065F46);
    final accentColor =
        widget.isError ? const Color(0xFFFCA5A5) : const Color(0xFF34D399);

    return Positioned(
      top: topPad + 10,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: GestureDetector(
                    onTap: _dismiss,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.55),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isError
                                ? Icons.error_rounded
                                : Icons.check_circle_rounded,
                            color: accentColor,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Visual tone for [showTopSlideNotification].
enum TopNotifyTone { success, edit, info, error }

/// Returns true when the user edited supplier, amount, or note relative to saved values.
bool hasNakladnoyEdits({
  required String originalSupplier,
  required double originalAmount,
  required String originalNote,
  required String currentSupplier,
  required String currentAmountText,
  required String currentNote,
}) {
  if (currentSupplier.trim() != originalSupplier.trim()) return true;
  if (currentNote.trim() != originalNote.trim()) return true;
  final parsed = parseUzsInput(currentAmountText);
  if (parsed == null) return currentAmountText.trim().isNotEmpty;
  return parsed.round() != originalAmount.round();
}

/// Builds a concise single-line human-readable diff for edited nakladnoy fields.
String buildNakladnoyEditSummary({
  required String oldSupplier,
  required double oldAmount,
  required String oldNote,
  required String newSupplier,
  required double newAmount,
  required String newNote,
}) {
  final parts = <String>[];
  if (oldSupplier.trim() != newSupplier.trim()) {
    parts.add('${oldSupplier.trim()} → ${newSupplier.trim()}');
  }
  if (oldAmount.round() != newAmount.round()) {
    parts.add(
      '${formatUzs(oldAmount)} → ${formatUzs(newAmount, withCurrency: true)}',
    );
  }
  if (oldNote.trim() != newNote.trim()) {
    parts.add(
      newNote.trim().isEmpty ? 'Izoh olib tashlandi' : 'Izoh: ${newNote.trim()}',
    );
  }
  if (parts.isEmpty) {
    return '${newSupplier.trim()} • ${formatUzs(newAmount, withCurrency: true)}';
  }
  return parts.join(' • ');
}

OverlayEntry? _activeTopNotifyEntry;

/// Shows a rich custom notification card that slides down smoothly from the top
/// of the screen (above bottom sheets and dialogs) with an animated progress bar.
void showTopSlideNotification(
  BuildContext context, {
  required String title,
  String? subtitle,
  TopNotifyTone tone = TopNotifyTone.success,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 3200),
}) {
  if (tone == TopNotifyTone.error) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.mediumImpact();
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _activeFeedbackEntry?.remove();
  _activeFeedbackEntry = null;
  _activeTopNotifyEntry?.remove();
  _activeTopNotifyEntry = null;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TopSlideNotificationOverlay(
      title: title,
      subtitle: subtitle,
      tone: tone,
      icon: icon,
      duration: duration,
      onDismissed: () {
        if (_activeTopNotifyEntry == entry) {
          _activeTopNotifyEntry = null;
        }
        if (entry.mounted) {
          entry.remove();
        }
      },
    ),
  );
  _activeTopNotifyEntry = entry;
  overlay.insert(entry);
}

class _TopSlideNotificationOverlay extends StatefulWidget {
  final String title;
  final String? subtitle;
  final TopNotifyTone tone;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TopSlideNotificationOverlay({
    required this.title,
    this.subtitle,
    required this.tone,
    this.icon,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TopSlideNotificationOverlay> createState() =>
      _TopSlideNotificationOverlayState();
}

class _TopSlideNotificationOverlayState
    extends State<_TopSlideNotificationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final AnimationController _barCtrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _barCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _slideCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _opacity = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );

    _slideCtrl.forward();
    _barCtrl.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _slideCtrl.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  void _dismissImmediately() {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slideCtrl.dispose();
    _barCtrl.dispose();
    super.dispose();
  }

  (Color accent, IconData defaultIcon) _toneStyle() {
    switch (widget.tone) {
      case TopNotifyTone.edit:
        return (const Color(0xFFF59E0B), Icons.edit_note_rounded);
      case TopNotifyTone.info:
        return (AppTokens.brand, Icons.info_rounded);
      case TopNotifyTone.error:
        return (AppTokens.dangerRed, Icons.error_rounded);
      case TopNotifyTone.success:
        return (AppTokens.cashGreen, Icons.check_circle_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final (accent, defaultIcon) = _toneStyle();
    final topPad = MediaQuery.paddingOf(context).top;
    final cardBg = isDark
        ? const Color(0xFF161128).withValues(alpha: 0.97)
        : Colors.white.withValues(alpha: 0.98);
    final titleColor = isDark ? AppTokens.textPrimaryDark : AppTokens.textPrimaryLight;
    final subColor =
        isDark ? AppTokens.textSecondaryDark : AppTokens.textSecondaryLight;

    return Positioned(
      top: topPad + 10,
      left: 14,
      right: 14,
      child: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Dismissible(
                  key: ValueKey('top_notify_${widget.hashCode}'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => _dismissImmediately(),
                  child: GestureDetector(
                    onTap: _dismiss,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.50),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: isDark ? 0.24 : 0.16),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: widget.subtitle != null &&
                                            widget.subtitle!.trim().isNotEmpty
                                        ? 36
                                        : 26,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      widget.icon ?? defaultIcon,
                                      color: accent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: titleColor,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (widget.subtitle != null &&
                                            widget.subtitle!.trim().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            widget.subtitle!.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: subColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    onPressed: _dismiss,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 17,
                                      color: subColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _barCtrl,
                              builder: (context, _) {
                                final remaining =
                                    (1.0 - _barCtrl.value).clamp(0.0, 1.0);
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: remaining,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            accent,
                                            accent.withValues(alpha: 0.55),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
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
// ANIMATED ROLL-UP UZS NUMBER & 4-DIGIT PIN + BIOMETRIC LOCK SCREEN
// ============================================================================

/// Rolls numeric UZS balances smoothly upward from 0 whenever first built or
/// whenever [animSeed] changes (e.g. on pull-to-refresh / data reload).
class AnimatedUzsNumber extends StatelessWidget {
  final double value;
  final bool withCurrency;
  final String prefix;
  final TextStyle? style;
  final int animSeed;
  final Duration duration;

  const AnimatedUzsNumber({
    super.key,
    required this.value,
    this.withCurrency = false,
    this.prefix = '',
    this.style,
    this.animSeed = 0,
    this.duration = const Duration(milliseconds: 650),
  });

  @override
  Widget build(BuildContext context) {
    final startVal = value > 1 ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(animSeed),
      tween: Tween<double>(begin: startVal, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Text(
        '$prefix${formatUzs(animated, withCurrency: withCurrency)}',
        maxLines: 1,
        style: style,
      ),
    );
  }
}

enum PinScreenMode { setup, unlock, change }

/// Stylized 4-digit PIN & Fingerprint (Otpechatka) screen matching the glowing
/// violet/indigo fintech theme.
class PinLockScreen extends StatefulWidget {
  final PinScreenMode mode;
  final String? expectedPin;
  final bool biometricEnabled;
  final Future<bool> Function()? onCanUseBiometric;
  final Future<bool> Function()? onAuthenticateBiometric;
  final Future<void> Function(String pin, bool enableBiometric)? onCompleted;
  final VoidCallback? onSkip;
  final VoidCallback? onCancel;
  final VoidCallback? onLogout;

  const PinLockScreen({
    super.key,
    required this.mode,
    this.expectedPin,
    this.biometricEnabled = false,
    this.onCanUseBiometric,
    this.onAuthenticateBiometric,
    this.onCompleted,
    this.onSkip,
    this.onCancel,
    this.onLogout,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeCtrl;
  late int _step; // 0: verify current, 1: enter new, 2: confirm new
  String? _firstPin;
  String _entered = '';
  String? _error;
  bool _canBio = false;
  bool _bioChecked = false;
  bool _bioBusy = false;
  bool _success = false;
  bool _submitting = false;
  int _failCount = 0;
  int _lockedUntilMs = 0;
  int _remainingLockSecs = 0;
  Timer? _lockTimer;

  static const String _kPinFails = 'hisobchi_pin_fails';
  static const String _kPinLockUntil = 'hisobchi_pin_lock_until';

  bool get _isLockedOut => _remainingLockSecs > 0;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _step = widget.mode == PinScreenMode.setup ? 1 : 0;
    _bioChecked = widget.biometricEnabled;
    _loadLockoutState();
    _initBiometric();
  }

  Future<void> _loadLockoutState() async {
    if (widget.mode == PinScreenMode.setup) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fails = prefs.getInt(_kPinFails) ?? 0;
      final until = prefs.getInt(_kPinLockUntil) ?? 0;
      if (!mounted) return;
      _failCount = fails;
      _lockedUntilMs = until;
      _syncLockoutCountdown();
    } catch (_) {}
  }

  void _syncLockoutCountdown() {
    _lockTimer?.cancel();
    _lockTimer = null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final diffMs = _lockedUntilMs - nowMs;
    if (diffMs <= 0) {
      if (_remainingLockSecs != 0 && mounted) {
        setState(() {
          _remainingLockSecs = 0;
          _error = null;
        });
      }
      return;
    }
    final secs = (diffMs / 1000).ceil();
    if (mounted) {
      setState(() {
        _remainingLockSecs = secs;
        _error = "Juda ko'p xato urinish. $secs soniyadan keyin urinib ko'ring.";
      });
    }
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final leftMs = _lockedUntilMs - DateTime.now().millisecondsSinceEpoch;
      if (leftMs <= 0) {
        t.cancel();
        _lockTimer = null;
        setState(() {
          _remainingLockSecs = 0;
          _lockedUntilMs = 0;
          _error = null;
        });
      } else {
        final left = (leftMs / 1000).ceil();
        setState(() {
          _remainingLockSecs = left;
          _error = "Juda ko'p xato urinish. $left soniyadan keyin urinib ko'ring.";
        });
      }
    });
  }

  Future<void> _recordFailedAttempt(String baseMessage) async {
    _failCount += 1;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var msg = baseMessage;
    if (_failCount >= 10) {
      _lockedUntilMs = nowMs + 5 * 60 * 1000;
      msg = "10 marta xato PIN. 5 daqiqa kuting.";
    } else if (_failCount >= 5) {
      _lockedUntilMs = nowMs + 30 * 1000;
      msg = "5 marta xato PIN. 30 soniya kuting.";
    }
    _triggerShake(msg);
    if (_lockedUntilMs > nowMs) {
      _syncLockoutCountdown();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPinFails, _failCount);
      if (_lockedUntilMs > nowMs) {
        await prefs.setInt(_kPinLockUntil, _lockedUntilMs);
      }
    } catch (_) {}
  }

  Future<void> _resetLockout() async {
    _lockTimer?.cancel();
    _lockTimer = null;
    _failCount = 0;
    _lockedUntilMs = 0;
    _remainingLockSecs = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPinFails);
      await prefs.remove(_kPinLockUntil);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant PinLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _step = widget.mode == PinScreenMode.setup ? 1 : 0;
      _entered = '';
      _firstPin = null;
      _error = null;
      _success = false;
      _submitting = false;
      _bioChecked = widget.biometricEnabled;
      _initBiometric();
    }
  }

  Future<void> _initBiometric() async {
    if (widget.onCanUseBiometric != null) {
      try {
        final ok = await widget.onCanUseBiometric!();
        if (mounted) {
          setState(() {
            _canBio = ok;
            if (widget.mode == PinScreenMode.setup && ok) {
              _bioChecked = true;
            }
          });
        }
      } catch (_) {}
    } else if (widget.biometricEnabled && widget.onAuthenticateBiometric != null) {
      if (mounted) setState(() => _canBio = true);
    }

    if (widget.mode == PinScreenMode.unlock &&
        widget.biometricEnabled &&
        widget.onAuthenticateBiometric != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerBiometric();
      });
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerBiometric() async {
    if (_bioBusy || _submitting || _isLockedOut || widget.onAuthenticateBiometric == null) {
      return;
    }
    setState(() {
      _bioBusy = true;
      _error = null;
    });
    try {
      final ok = await widget.onAuthenticateBiometric!();
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        await _resetLockout();
        if (!mounted) return;
        setState(() {
          _entered = '••••';
          _success = true;
          _submitting = true;
        });
        await widget.onCompleted?.call(widget.expectedPin ?? '', true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _bioBusy = false;
          _submitting = false;
        });
      }
    }
  }

  void _triggerShake(String message) {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    setState(() {
      _error = message;
      _entered = '';
    });
  }

  Future<void> _onDigitTap(String d) async {
    if (_submitting || _isLockedOut || _entered.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      _entered += d;
    });
    if (_entered.length == 4) {
      await _handleFourDigits(_entered);
    }
  }

  void _onBackspace() {
    if (_submitting || _isLockedOut || _entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _entered = _entered.substring(0, _entered.length - 1);
    });
  }

  Future<void> _handleFourDigits(String pin) async {
    if (widget.mode == PinScreenMode.unlock) {
      if (AppPinHasher.verifyPin(pin, widget.expectedPin ?? '')) {
        HapticFeedback.mediumImpact();
        unawaited(_resetLockout());
        setState(() {
          _success = true;
          _submitting = true;
        });
        try {
          await widget.onCompleted?.call(pin, widget.biometricEnabled);
        } finally {
          if (mounted) {
            setState(() => _submitting = false);
          }
        }
      } else {
        await _recordFailedAttempt("PIN kod noto'g'ri. Qaytadan urinib ko'ring.");
      }
      return;
    }

    if (widget.mode == PinScreenMode.change && _step == 0) {
      if (AppPinHasher.verifyPin(pin, widget.expectedPin ?? '')) {
        HapticFeedback.lightImpact();
        unawaited(_resetLockout());
        setState(() {
          _step = 1;
          _entered = '';
          _error = null;
        });
      } else {
        await _recordFailedAttempt("Joriy PIN kod noto'g'ri.");
      }
      return;
    }

    // Setup or Change: Step 1 -> capture first PIN, Step 2 -> confirm match
    if (_step == 1) {
      HapticFeedback.lightImpact();
      setState(() {
        _firstPin = pin;
        _step = 2;
        _entered = '';
        _error = null;
      });
      return;
    }

    if (_step == 2) {
      if (pin == _firstPin) {
        HapticFeedback.mediumImpact();
        setState(() {
          _success = true;
          _submitting = true;
        });
        try {
          await widget.onCompleted?.call(pin, _bioChecked);
        } finally {
          if (mounted) {
            setState(() => _submitting = false);
          }
        }
      } else {
        setState(() {
          _step = 1;
          _firstPin = null;
        });
        _triggerShake("PIN kodlar mos kelmadi. Boshidan kiriting.");
      }
    }
  }

  String _titleText() {
    if (widget.mode == PinScreenMode.unlock) return 'Hisobchi — Kirish';
    if (widget.mode == PinScreenMode.change && _step == 0) {
      return 'Joriy PIN kod';
    }
    return _step == 1 ? "PIN kod o'rnating" : 'PIN kodni tasdiqlang';
  }

  String _subtitleText() {
    if (widget.mode == PinScreenMode.unlock) {
      return widget.biometricEnabled && _canBio
          ? 'Barmoq izi yoki 4 xonali PIN kodni kiriting'
          : '4 xonali PIN kodni kiriting';
    }
    if (widget.mode == PinScreenMode.change && _step == 0) {
      return "O'zgartirish uchun avval joriy PIN kodni kiriting";
    }
    return _step == 1
        ? "Tezkor kirish uchun 4 xonali kod o'ylab toping (1/2)"
        : "Saqlash uchun xuddi shu PIN kodni qayta kiriting (2/2)";
  }

  Widget _buildKeyButton({
    required Widget child,
    VoidCallback? onTap,
    bool accent = false,
  }) {
    final isDark = isDarkCtx(context);
    final bg = accent
        ? AppTokens.brandViolet.withValues(alpha: isDark ? 0.24 : 0.14)
        : (isDark
            ? const Color(0xFF17122A).withValues(alpha: 0.90)
            : Colors.white);
    final border = accent
        ? AppTokens.brandViolet.withValues(alpha: 0.52)
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : AppTokens.cardBorderLight);

    return TactileScaleTap(
      pressedScale: 0.90,
      haptic: false,
      enabled: onTap != null && !_submitting && !_isLockedOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent
                  ? AppTokens.brandViolet.withValues(alpha: isDark ? 0.28 : 0.14)
                  : (isDark
                      ? Colors.black.withValues(alpha: 0.30)
                      : AppTokens.brandViolet.withValues(alpha: 0.06)),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: bg,
          shape: CircleBorder(side: BorderSide(color: border, width: 1.1)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: (onTap != null && !_submitting && !_isLockedOut) ? onTap : null,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final bg = isDark ? AppTokens.surfaceDark : AppTokens.surfaceLight;
    final showBioBtn = widget.mode == PinScreenMode.unlock &&
        widget.biometricEnabled &&
        _canBio &&
        widget.onAuthenticateBiometric != null;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 0.95,
                    colors: [
                      AppTokens.brandViolet
                          .withValues(alpha: isDark ? 0.26 : 0.14),
                      const Color(0xFFEC4899)
                          .withValues(alpha: isDark ? 0.10 : 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isDark)
            const Positioned.fill(
              child: IgnorePointer(
                child: HisobchiBottomHorizonArc(),
              ),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onCancel != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: widget.onCancel,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      const Hisobchi3DEmblem(size: 68, showOrbitRings: true),
                      const SizedBox(height: 10),
                      Text(
                        _titleText(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitleText(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Animated shaking 4 PIN dots
                      AnimatedBuilder(
                        animation: _shakeCtrl,
                        builder: (ctx, child) {
                          final dx = math.sin(_shakeCtrl.value * math.pi * 6) *
                              (1.0 - _shakeCtrl.value) *
                              12.0;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            final filled = i < _entered.length;
                            final dotColor = _success
                                ? AppTokens.cashGreen
                                : (_error != null
                                    ? AppTokens.dangerRed
                                    : (filled
                                        ? AppTokens.brandViolet
                                        : Colors.transparent));
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              margin: const EdgeInsets.symmetric(horizontal: 9),
                              width: filled ? 18 : 16,
                              height: filled ? 18 : 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                                border: Border.all(
                                  color: _success
                                      ? AppTokens.cashGreen
                                      : (_error != null
                                          ? AppTokens.dangerRed
                                          : (filled
                                              ? AppTokens.brandViolet
                                              : textSecondaryOf(context)
                                                  .withValues(alpha: 0.45))),
                                  width: 2,
                                ),
                                boxShadow: filled
                                    ? [
                                        BoxShadow(
                                          color:
                                              dotColor.withValues(alpha: 0.55),
                                          blurRadius: 10,
                                        ),
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 20,
                        child: _error != null
                            ? Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTokens.dangerRed,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),

                      if ((widget.mode == PinScreenMode.setup ||
                              widget.mode == PinScreenMode.change) &&
                          _canBio) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? AppTokens.cardDark : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? AppTokens.cardBorderDark
                                  : AppTokens.cardBorderLight,
                            ),
                          ),
                          child: SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            secondary: const Icon(
                              Icons.fingerprint_rounded,
                              color: AppTokens.brandViolet,
                            ),
                            title: const Text(
                              'Otpechatka bilan kirish',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            value: _bioChecked,
                            onChanged: (v) => setState(() => _bioChecked = v),
                          ),
                        ),
                      ],

                      // Numeric Keypad (1..9, bio/empty, 0, backspace)
                      for (final row in const [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                      ]) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: row
                              .map(
                                (d) => _buildKeyButton(
                                  onTap: () => _onDigitTap(d),
                                  child: Text(
                                    d,
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimaryOf(context),
                                      fontFeatures: AppTokens.tabularNums,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (showBioBtn)
                            _buildKeyButton(
                              accent: true,
                              onTap: _triggerBiometric,
                              child: const Icon(
                                Icons.fingerprint_rounded,
                                size: 32,
                                color: AppTokens.brandViolet,
                              ),
                            )
                          else
                            const SizedBox(width: 72, height: 72),
                          _buildKeyButton(
                            onTap: () => _onDigitTap('0'),
                            child: Text(
                              '0',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                color: textPrimaryOf(context),
                                fontFeatures: AppTokens.tabularNums,
                              ),
                            ),
                          ),
                          _buildKeyButton(
                            onTap: _entered.isEmpty ? null : _onBackspace,
                            child: Icon(
                              Icons.backspace_outlined,
                              size: 24,
                              color: _entered.isEmpty
                                  ? textSecondaryOf(context)
                                      .withValues(alpha: 0.4)
                                  : textPrimaryOf(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (widget.onSkip != null)
                        TextButton(
                          onPressed: widget.onSkip,
                          child: const Text('Keyinroq sozlayman'),
                        )
                      else if (widget.onLogout != null)
                        TextButton(
                          onPressed: widget.onLogout,
                          child: const Text(
                            "PIN esdan chiqdimi? Hisobdan chiqish",
                            style: TextStyle(color: AppTokens.dangerRed),
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
}

/// Computes a concise Uzbek warning if [enteredAmount] spikes >=1.75x above [recentAmounts] average.
String? computeSupplierAnomalyWarning(
  double? enteredAmount,
  List<double> recentAmounts,
) {
  if (enteredAmount == null || enteredAmount <= 0 || recentAmounts.length < 2) {
    return null;
  }
  final valid = recentAmounts.where((e) => e > 0).toList();
  if (valid.length < 2) return null;
  final avg = valid.fold<double>(0, (a, b) => a + b) / valid.length;
  if (avg <= 0) return null;
  if (enteredAmount >= avg * 1.75 && (enteredAmount - avg) >= 150000) {
    final pct = ((enteredAmount / avg - 1.0) * 100).round();
    return "Odatdagidan +$pct% ko'p (o'rtacha ${formatUzs(avg)} so'm)";
  }
  return null;
}

/// Wraps [NakladnoyListCard] with spring-back swipe actions:
/// - Swipe Right (`startToEnd`): quick pay debt ("To'landi")
/// - Swipe Left (`endToStart`): duplicate ("Nusxa")
class SwipeableNakladnoyTile extends StatelessWidget {
  final NakladnoyItem item;
  final VoidCallback onTap;
  final VoidCallback? onQuickPay;
  final VoidCallback? onDuplicate;

  const SwipeableNakladnoyTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onQuickPay,
    this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final canPay = item.isDebt && onQuickPay != null;
    final canDup = onDuplicate != null;
    final card = NakladnoyListCard(
      item: item,
      onTap: onTap,
      onQuickPay: onQuickPay,
    );
    if (!canPay && !canDup) {
      return card;
    }

    final direction = (canPay && canDup)
        ? DismissDirection.horizontal
        : (canPay ? DismissDirection.startToEnd : DismissDirection.endToStart);

    return Dismissible(
      key: ValueKey<String>('swipe_nak_${item.id}_${item.isDebt}'),
      direction: direction,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
        DismissDirection.endToStart: 0.28,
      },
      confirmDismiss: (dir) async {
        HapticFeedback.mediumImpact();
        if (dir == DismissDirection.startToEnd && canPay) {
          onQuickPay?.call();
        } else if (dir == DismissDirection.endToStart && canDup) {
          onDuplicate?.call();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTokens.cashGreen.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTokens.cashGreen.withValues(alpha: 0.45),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppTokens.cashGreen),
            SizedBox(width: 8),
            Text(
              "To'landi",
              style: TextStyle(
                color: AppTokens.cashGreen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppTokens.brandViolet.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTokens.brandViolet.withValues(alpha: 0.45),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nusxa',
              style: TextStyle(
                color: AppTokens.brandViolet,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.copy_rounded, color: AppTokens.brandViolet),
          ],
        ),
      ),
      child: card,
    );
  }
}
