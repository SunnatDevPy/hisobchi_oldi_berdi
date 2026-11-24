import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_client.dart';
import 'theme.dart';

class HeroBalanceCard extends StatelessWidget {
  final StatusSummary summary;
  final int animSeed;
  final VoidCallback? onAddCash;
  final VoidCallback? onKassaDebt;
  final VoidCallback? onKassaRepay;

  const HeroBalanceCard({
    super.key,
    required this.summary,
    this.animSeed = 0,
    this.onAddCash,
    this.onKassaDebt,
    this.onKassaRepay,
  });

  @override
  Widget build(BuildContext context) {
    final grp = summary.groupInfo;
    return Container(
      decoration: BoxDecoration(
        gradient: AppTokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTokens.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Session date & Telegram group pill
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      summary.reportDate,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
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
                          ? const Color(0xFF10B981).withValues(alpha: 0.24)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: grp.bound
                            ? const Color(0xFF6EE7B7).withValues(alpha: 0.55)
                            : const Color(0xFFFCD34D).withValues(alpha: 0.55),
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
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
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
                        numericValue: summary.totalNakladnoySpent,
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
                    Expanded(
                      child: _HeroSubStat(
                        label: 'Bugun kirim',
                        numericValue: summary.mainCashIn,
                        prefix: '+',
                        animSeed: animSeed,
                      ),
                    ),
                    Expanded(
                      child: _HeroSubStat(
                        label: 'Kassa qarzi',
                        numericValue: summary.totalKassaDebtOutstanding,
                        animSeed: animSeed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (onAddCash != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroActionBtn(
                    icon: Icons.add_card_rounded,
                    label: 'Pul oldim',
                    onTap: onAddCash!,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroActionBtn(
                    icon: Icons.account_balance_rounded,
                    label: 'Kassa qarz',
                    onTap: onKassaDebt!,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroActionBtn(
                    icon: Icons.assignment_return_rounded,
                    label: 'Qaytarish',
                    onTap: onKassaRepay!,
                  ),
                ),
              ],
            ),
          ],
        ],
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

  const _HeroActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TactileScaleTap(
      pressedScale: 0.94,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(height: 4),
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
        // 1. DUMALOQ STATISTIKA (Interactive Donut Chart Card)
        _DonutStatisticsCard(
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

        // 2. CHIZIQLI STATISTIKA (Smooth Bezier Line & Area Trend Chart with Date Range Selector)
        _TrendLineStatisticsCard(
          dailySeries: widget.dailySeries,
          seriesGranularity: widget.seriesGranularity,
          periodLabel: widget.periodLabel,
          activePeriodKey: widget.activePeriodKey,
          selectedIdx: _selectedTrendIdx,
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

        // 3. Payment Methods Breakdown (2x2 Bento Grid)
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
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _PaymentKpiCard(
                title: 'Naqd to\'lov',
                amount: summary.totalNakladnoySpent,
                animSeed: widget.animSeed,
                count: cashCnt,
                share: grandTotal > 0
                    ? summary.totalNakladnoySpent / grandTotal
                    : 0,
                icon: Icons.payments_rounded,
                color: AppTokens.cashGreen,
                onTap: () => widget.onTapPaymentFilter('cash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PaymentKpiCard(
                title: 'Karta (naqdsiz)',
                amount: summary.totalCardSpent,
                animSeed: widget.animSeed,
                count: cardCnt,
                share:
                    grandTotal > 0 ? summary.totalCardSpent / grandTotal : 0,
                icon: Icons.credit_card_rounded,
                color: AppTokens.cardBlue,
                onTap: () => widget.onTapPaymentFilter('card'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _PaymentKpiCard(
                title: "Perechesleniya",
                amount: summary.totalTransferSpent,
                animSeed: widget.animSeed,
                count: transferCnt,
                share: grandTotal > 0
                    ? summary.totalTransferSpent / grandTotal
                    : 0,
                icon: Icons.account_balance_rounded,
                color: AppTokens.transferPurple,
                onTap: () => widget.onTapPaymentFilter('transfer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PaymentKpiCard(
                title: 'Qarzga (smena)',
                amount: summary.totalDebtNakladnoy,
                animSeed: widget.animSeed,
                count: debtCnt,
                share: grandTotal > 0
                    ? summary.totalDebtNakladnoy / grandTotal
                    : 0,
                icon: Icons.push_pin_rounded,
                color: AppTokens.debtAmber,
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

        // 5. Top Postavshiklar (Ranked Visual Bars)
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
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 7,
                                  backgroundColor:
                                      AppTokens.brand.withValues(alpha: 0.12),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          AppTokens.brand),
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
      final isOut = tx.sourceType == 'kassa_repay';
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

    return Card(
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
                    gradient: AppTokens.heroGradient,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kassa kirim va qarz amallari',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        '${summary.reportDate} sanadagi kassa harakatlari (${events.length} ta)',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onPressed: widget.onOpenNakladnoyTab,
                  icon: const Icon(Icons.receipt_long_rounded, size: 15),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Amallar (${summary.nakladnoys.length})',
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mini Kassa Summary Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MiniKassaCol(
                      label: 'Pul olindi',
                      value: '+${formatUzs(summary.mainCashIn)}',
                      color: AppTokens.cashGreen,
                    ),
                  ),
                  Expanded(
                    child: _MiniKassaCol(
                      label: 'Kassadan qarz',
                      value: '+${formatUzs(summary.kassaDebtToday)}',
                      color: AppTokens.cardBlue,
                    ),
                  ),
                  Expanded(
                    child: _MiniKassaCol(
                      label: 'Kassaga qaytdi',
                      value: '−${formatUzs(summary.kassaRepayToday)}',
                      color: AppTokens.debtAmber,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "Bu smenada kassa kirim-qarz amallari yo'q.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondaryOf(context),
                  ),
                ),
              )
            else
              ...events.map((ev) => _buildTimelineRow(context, ev)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow(BuildContext context, _TimelineEvent ev) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: ev.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ev.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: (ev.cashTx != null && widget.canWrite)
            ? () => widget.onEditCashTx(ev.cashTx!)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ev.fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(ev.icon, color: ev.fg, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: ev.fg.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '⏰ ${ev.timeHm}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: ev.fg,
                              fontFeatures: AppTokens.tabularNums,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: ev.fg.withValues(alpha: 0.11),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ev.badgeText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: ev.fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      ev.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ev.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                    '${ev.sign}${formatUzs(ev.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: ev.fg,
                      fontFeatures: AppTokens.tabularNums,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "so'm",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
              if (ev.cashTx != null && widget.canWrite) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  icon: Icon(Icons.more_vert_rounded,
                      size: 18, color: textSecondaryOf(context)),
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
          title: 'Kassadan vaqtincha qarz olindi',
          badge: '🏦 KASSADAN QARZ',
          sign: '+',
          icon: Icons.account_balance_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      case 'kassa_repay':
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.debtAmber);
        return (
          title: 'Kassaga qarz qaytarildi',
          badge: '↩️ KASSAGA QAYTARILDI',
          sign: '−',
          icon: Icons.assignment_return_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
      default:
        final (fg, bg, border) =
            AppTokens.semanticSurface(context, AppTokens.cashGreen);
        return (
          title: 'Asosiy pul olindi (Kirim)',
          badge: '🟢 PUL OLINDI',
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
// DUMALOQ STATISTIKA (Custom-Painted Multi-Segment Donut Chart)
// ============================================================================

class _DonutStatisticsCard extends StatelessWidget {
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

  const _DonutStatisticsCard({
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
    final total = cashAmount + cardAmount + transferAmount + debtAmount;
    final totalCount = cashCount + cardCount + transferCount + debtCount;

    final segments = <_DonutSeg>[
      _DonutSeg('cash', 'Naqd', cashAmount, cashCount, AppTokens.cashGreen),
      _DonutSeg('card', 'Karta', cardAmount, cardCount, AppTokens.cardBlue),
      _DonutSeg('transfer', "O'tkazma", transferAmount, transferCount,
          AppTokens.transferPurple),
      _DonutSeg('debt', 'Qarzga', debtAmount, debtCount, AppTokens.debtAmber),
    ];

    return Card(
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
                  child: const Icon(Icons.donut_large_rounded,
                      color: AppTokens.brand, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistika',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        'Xarajatlar taqsimoti • $reportDate',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(124, 124),
                        painter: _DonutRingPainter(
                          segments: segments,
                          total: total,
                          trackColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'JAMI',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: textSecondaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                formatUzsCompact(total),
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                  color: textPrimaryOf(context),
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                              ),
                            ),
                            Text(
                              '$totalCount ta chek',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: segments.map((s) {
                      final pct = total > 0
                          ? ((s.value / total) * 100).round()
                          : 0;
                      final (fg, bg, _) =
                          AppTokens.semanticSurface(context, s.color);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onTapMode(s.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 5, horizontal: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: s.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: textPrimaryOf(context),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: bg,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$pct%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: fg,
                                              fontFeatures:
                                                  AppTokens.tabularNums,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${formatUzs(s.value)} (${s.count} ta)',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: textSecondaryOf(context),
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
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutSeg {
  final String key;
  final String label;
  final double value;
  final int count;
  final Color color;

  const _DonutSeg(this.key, this.label, this.value, this.count, this.color);
}

class _DonutRingPainter extends CustomPainter {
  final List<_DonutSeg> segments;
  final double total;
  final Color trackColor;

  const _DonutRingPainter({
    required this.segments,
    required this.total,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 17.0;
    final rect = Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (total <= 0) return;

    final nonZero = segments.where((s) => s.value > 0).toList();
    final gap = nonZero.length > 1 ? 0.08 : 0.0;
    var startAngle = -math.pi / 2;

    for (final s in nonZero) {
      final sweep = (s.value / total) * (math.pi * 2 - gap * nonZero.length);
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, math.max(sweep, 0.04), false, paint);
      startAngle += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) =>
      oldDelegate.total != total || oldDelegate.segments != segments;
}

// ============================================================================
// CHIZIQLI STATISTIKA (Custom-Painted Smooth Bezier Line & Area Trend Chart)
// ============================================================================

class _TrendLineStatisticsCard extends StatelessWidget {
  final List<Map<String, dynamic>> dailySeries;
  final String seriesGranularity;
  final String periodLabel;
  final String activePeriodKey;
  final int? selectedIdx;
  final ValueChanged<int> onSelectIdx;
  final ValueChanged<String> onSelectPeriodKey;
  final VoidCallback onPickCustomDateRange;

  const _TrendLineStatisticsCard({
    required this.dailySeries,
    this.seriesGranularity = 'daily',
    required this.periodLabel,
    required this.activePeriodKey,
    required this.selectedIdx,
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

    return Card(
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
                    color: AppTokens.brandViolet.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.show_chart_rounded,
                      color: AppTokens.brandViolet, size: 20),
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
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: isCustom
                      ? AppTokens.brand
                      : (isDark
                          ? AppTokens.surfaceDark.withValues(alpha: 0.7)
                          : AppTokens.surfaceLight),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onPickCustomDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
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
                            size: 15,
                            color: isCustom
                                ? Colors.white
                                : textSecondaryOf(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Sana',
                            style: TextStyle(
                              fontSize: 12,
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
                  const SizedBox(width: 6),
                  _periodPill(context, 'yesterday', 'Kecha',
                      Icons.history_toggle_off_rounded),
                  const SizedBox(width: 6),
                  _periodPill(context, '7d', '7 kun', null),
                  const SizedBox(width: 6),
                  _periodPill(context, '14d', '14 kun', null),
                  const SizedBox(width: 6),
                  _periodPill(context, '30d', '30 kun', null),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (selectedPt != null) ...[
              Builder(builder: (context) {
                final ptLabel =
                    (selectedPt['label'] ?? selectedPt['date']).toString();
                final cashInVal =
                    ((selectedPt['cash_in'] as num?) ?? 0).toDouble();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppTokens.brand.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isHourly
                            ? Icons.schedule_rounded
                            : Icons.calendar_today_rounded,
                        size: 15,
                        color: AppTokens.brand,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        ptLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
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
                              child: Text(
                                "Rasxod: ${formatUzs(selectedPt['spent'] as num?)} (${selectedPt['count']} ta)",
                                maxLines: 1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color: AppTokens.brand,
                                  fontFeatures: AppTokens.tabularNums,
                                ),
                              ),
                            ),
                            if (cashInVal > 0)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  "Kirim: +${formatUzs(cashInVal)} so'm",
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: AppTokens.cashGreen,
                                    fontFeatures: AppTokens.tabularNums,
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
              SizedBox(
                height: 165,
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
                        size: Size(constraints.maxWidth, 165),
                        painter: _SmoothLineChartPainter(
                          points: pts,
                          selectedIdx: activeIdx ?? 0,
                          lineColor: AppTokens.brand,
                          inflowColor: AppTokens.cashGreen,
                          gridColor:
                              textSecondaryOf(context).withValues(alpha: 0.18),
                          labelColor: textSecondaryOf(context),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppTokens.brand,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
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
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppTokens.cashGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
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
        color: sel
            ? AppTokens.brand
            : (isDark
                ? AppTokens.surfaceDark.withValues(alpha: 0.65)
                : AppTokens.surfaceLight),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: sel
              ? AppTokens.brand
              : (isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight),
        ),
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

    // Draw inflow dashed/secondary curve
    if (inflowOffsets.length >= 2) {
      final inPath = _buildSmoothPath(inflowOffsets);
      final inPaint = Paint()
        ..color = inflowColor.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawPath(inPath, inPaint);
    }

    // Draw spent smooth curve + gradient area
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
              lineColor.withValues(alpha: 0.30),
              lineColor.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(0, topPad, size.width, chartH));
        canvas.drawPath(areaPath, areaPaint);
      }

      final strokePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(linePath, strokePaint);

      for (var i = 0; i < spentOffsets.length; i++) {
        final o = spentOffsets[i];
        final isSel = i == selectedIdx;
        canvas.drawCircle(
          o,
          isSel ? 6.0 : 3.8,
          Paint()..color = isSel ? lineColor : Colors.white,
        );
        canvas.drawCircle(
          o,
          isSel ? 6.0 : 3.8,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSel ? 2.5 : 2.0,
        );

        // Date label on X-axis (show up to 6 labels evenly spaced)
        final step = math.max(1, (points.length / 5).ceil());
        if (i % step == 0 || i == points.length - 1) {
          final rawDate = points[i]['date'].toString();
          final shortDate =
              rawDate.length >= 10 ? rawDate.substring(5, 10) : rawDate;
          final tp = TextPainter(
            text: TextSpan(
              text: shortDate,
              style: TextStyle(
                color: labelColor,
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

class _MiniKassaCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniKassaCol({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final (fg, _, _) = AppTokens.semanticSurface(context, color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: fg,
              fontFeatures: AppTokens.tabularNums,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentKpiCard extends StatelessWidget {
  final String title;
  final double amount;
  final int animSeed;
  final int count;
  final double share;
  final IconData icon;
  final Color color;
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
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = AppTokens.semanticSurface(context, color);
    return TactileScaleTap(
      pressedScale: 0.985,
      haptic: false,
      child: Card(
        child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Icon(icon, size: 16, color: fg),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count ta',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 3),
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
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
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
          padding: const EdgeInsets.all(4),
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
                  padding: EdgeInsets.only(right: i < modes.length - 1 ? 4 : 0),
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
    final (badgeText, badgeIcon, baseColor) = _badgeSpec();
    final (fg, bg, border) = AppTokens.semanticSurface(context, baseColor);
    final (grpFg, _, _) =
        AppTokens.semanticSurface(context, AppTokens.cashGreen);

    return TactileScaleTap(
      pressedScale: 0.985,
      haptic: false,
      child: Card(
        child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
                          crossAxisAlignment: WrapCrossAlignment.center,
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
                              Icon(Icons.image_rounded, size: 14, color: fg),
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
                          color: item.isDebt ? fg : textPrimaryOf(context),
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
                    icon: const Icon(Icons.check_circle_outline_rounded,
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

class HisobchiAnimatedLoadingScreen extends StatefulWidget {
  final String title;
  final String subtitle;

  const HisobchiAnimatedLoadingScreen({
    super.key,
    this.title = 'Hisobchi',
    this.subtitle = 'Ilova yuklanmoqda...',
  });

  @override
  State<HisobchiAnimatedLoadingScreen> createState() =>
      _HisobchiAnimatedLoadingScreenState();
}

class _HisobchiAnimatedLoadingScreenState
    extends State<HisobchiAnimatedLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    final bgBase = isDark ? AppTokens.surfaceDark : AppTokens.surfaceLight;
    final cardSurface = isDark ? AppTokens.cardDark : Colors.white;
    final titleColor = textPrimaryOf(context);
    final subColor = textSecondaryOf(context);
    final glowViolet = AppTokens.brandViolet;
    final glowIndigo = AppTokens.brand;
    const glowPink = Color(0xFFEC4899);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final pulse = 0.5 - 0.5 * math.cos(t * 2 * math.pi); // 0..1 smooth
        final logoScale = 0.97 + 0.06 * pulse;
        final haloOpacity = (isDark ? 0.36 : 0.20) + 0.16 * pulse;

        return Container(
          color: bgBase,
          child: Stack(
            children: [
              // Vertical ambient fintech beam behind logo
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.06),
                        radius: 0.78 + 0.08 * pulse,
                        colors: [
                          glowViolet.withValues(alpha: haloOpacity),
                          glowPink.withValues(alpha: haloOpacity * 0.45),
                          glowIndigo.withValues(alpha: haloOpacity * 0.25),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 0.62, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Subtle vertical light pillar
              Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: Container(
                    width: 150,
                    height: 360,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          glowViolet.withValues(alpha: isDark ? 0.16 : 0.09),
                          glowPink.withValues(alpha: isDark ? 0.14 : 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom horizon purple glow arc
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 110,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, 1.25),
                        radius: 1.15,
                        colors: [
                          glowViolet.withValues(
                              alpha: (isDark ? 0.34 : 0.18) + 0.08 * pulse),
                          glowPink.withValues(alpha: isDark ? 0.14 : 0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Center animated squircle logo + text + glowing progress pill
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: logoScale,
                        child: SizedBox(
                          width: 118,
                          height: 118,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Rotating orbital neon ring
                              Transform.rotate(
                                angle: t * 2 * math.pi,
                                child: Container(
                                  width: 114,
                                  height: 114,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(31),
                                    gradient: SweepGradient(
                                      colors: [
                                        glowIndigo,
                                        glowViolet,
                                        glowPink,
                                        glowViolet.withValues(alpha: 0.15),
                                        glowIndigo,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: glowViolet.withValues(
                                            alpha: isDark ? 0.55 : 0.28),
                                        blurRadius: 28,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Inner frosted glass squircle holding logo
                              Container(
                                width: 106,
                                height: 106,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardSurface,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: Colors.white.withValues(
                                        alpha: isDark ? 0.14 : 0.8),
                                    width: 1.2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.asset(
                                    'assets/app_icon.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      decoration: const BoxDecoration(
                                        gradient: AppTokens.aiGradient,
                                      ),
                                      child: const Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: Colors.white,
                                        size: 42,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Glowing sliding progress pill
                      Container(
                        width: 152,
                        height: 5,
                        decoration: BoxDecoration(
                          color: glowViolet.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: LayoutBuilder(
                          builder: (ctx, box) {
                            final barW = box.maxWidth * 0.42;
                            final travel = box.maxWidth - barW;
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: Offset(travel * pulse, 0),
                                child: Container(
                                  width: barW,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    gradient: AppTokens.aiGradient,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: glowPink.withValues(alpha: 0.55),
                                        blurRadius: 10,
                                      ),
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
              ),
            ],
          ),
        );
      },
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
        isDark ? const Color(0xFF1F2742) : const Color(0xFFE6EAF3);
    final hiBg =
        isDark ? const Color(0xFF2D3860) : const Color(0xFFF3F6FC);
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            // Date switcher bar placeholder
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppTokens.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? AppTokens.cardBorderDark
                      : AppTokens.cardBorderLight,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  box(28, w: 34, r: 8),
                  box(18, w: 140, r: 8),
                  box(28, w: 34, r: 8),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Mirror HeroBalanceCard
            Container(
              decoration: BoxDecoration(
                gradient: AppTokens.heroGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTokens.brand.withValues(alpha: 0.24),
                    blurRadius: 22,
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
                      color: Colors.black.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: box(52, r: 13, onHero: true)),
                      const SizedBox(width: 8),
                      Expanded(child: box(52, r: 13, onHero: true)),
                      const SizedBox(width: 8),
                      Expanded(child: box(52, r: 13, onHero: true)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Mirror Quick action row (Jonli Sverka / Smena Tarixi)
            Row(
              children: [
                Expanded(child: box(44, r: 14)),
                const SizedBox(width: 8),
                Expanded(child: box(44, r: 14)),
              ],
            ),
            const SizedBox(height: 14),

            // Mirror Analytics Card with chart bars
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        box(18, w: 160, r: 8),
                        box(24, w: 80, r: 10),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 68,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final h in const [
                            36.0,
                            54.0,
                            42.0,
                            64.0,
                            48.0,
                            58.0,
                          ]) ...[
                            Expanded(child: box(h, r: 8)),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: box(32, r: 8)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: box(40, r: 10)),
                        const SizedBox(width: 8),
                        Expanded(child: box(40, r: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Mirror Kassa Timeline Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        box(18, w: 185, r: 8),
                        box(24, w: 72, r: 8),
                      ],
                    ),
                    const SizedBox(height: 12),
                    box(58, r: 14),
                    const SizedBox(height: 8),
                    box(58, r: 14),
                    const SizedBox(height: 8),
                    box(58, r: 14),
                  ],
                ),
              ),
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

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _step = widget.mode == PinScreenMode.setup ? 1 : 0;
    _bioChecked = widget.biometricEnabled;
    _initBiometric();
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
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerBiometric() async {
    if (_bioBusy || _submitting || widget.onAuthenticateBiometric == null) {
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
    if (_submitting || _entered.length >= 4) return;
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
    if (_submitting || _entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _error = null;
      _entered = _entered.substring(0, _entered.length - 1);
    });
  }

  Future<void> _handleFourDigits(String pin) async {
    if (widget.mode == PinScreenMode.unlock) {
      if (pin == widget.expectedPin) {
        HapticFeedback.mediumImpact();
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
        _triggerShake("PIN kod noto'g'ri. Qaytadan urinib ko'ring.");
      }
      return;
    }

    if (widget.mode == PinScreenMode.change && _step == 0) {
      if (pin == widget.expectedPin) {
        HapticFeedback.lightImpact();
        setState(() {
          _step = 1;
          _entered = '';
          _error = null;
        });
      } else {
        _triggerShake("Joriy PIN kod noto'g'ri.");
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
            ? const Color(0xFF1A223A)
            : Colors.white);
    final border = accent
        ? AppTokens.brandViolet.withValues(alpha: 0.45)
        : (isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight);

    return TactileScaleTap(
      pressedScale: 0.90,
      haptic: false,
      enabled: onTap != null && !_submitting,
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: (onTap != null && !_submitting) ? onTap : null,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(child: child),
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
                      Container(
                        width: 74,
                        height: 74,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: isDark ? AppTokens.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: AppTokens.brandViolet.withValues(alpha: 0.45),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTokens.brandViolet
                                  .withValues(alpha: isDark ? 0.35 : 0.18),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset(
                            'assets/app_icon.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.lock_rounded,
                              color: AppTokens.brand,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
