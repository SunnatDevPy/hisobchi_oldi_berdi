import 'package:flutter/material.dart';
import 'api_client.dart';
import 'theme.dart';

class HeroBalanceCard extends StatelessWidget {
  final StatusSummary summary;
  final VoidCallback? onAddCash;
  final VoidCallback? onKassaDebt;
  final VoidCallback? onKassaRepay;

  const HeroBalanceCard({
    super.key,
    required this.summary,
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
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
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
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 155),
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
            child: Text(
              formatUzs(summary.expectedCash, withCurrency: true),
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
                        label: "Qo'ldagi jami kirim",
                        value: formatUzs(summary.totalAvailableInflow),
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
                        label: 'Naqd nakladnoy rasxod',
                        value: formatUzs(summary.totalNakladnoySpent),
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
                        label: 'Kechadan qoldiq',
                        value: formatUzs(summary.openingBalance),
                      ),
                    ),
                    Expanded(
                      child: _HeroSubStat(
                        label: 'Bugun olingan',
                        value: '+${formatUzs(summary.mainCashIn)}',
                      ),
                    ),
                    Expanded(
                      child: _HeroSubStat(
                        label: 'Kassa qarz qoldiq',
                        value: formatUzs(summary.totalKassaDebtOutstanding),
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
  final String value;

  const _HeroSubStat({required this.label, required this.value});

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
          child: Text(
            value,
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
  final String value;
  final IconData icon;
  final Color color;

  const _HeroMetricTile({
    required this.label,
    required this.value,
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
          child: Text(
            value,
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
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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

/// Executive Dashboard Analytics Section:
/// 1) 2x2 Payment Method Breakdown Cards with count, sum, and % progress bar
/// 2) Top Suppliers Ranked Bar Chart
/// 3) Full Cash & Kassa Oldi-Berdi Timeline List (with exact date/time, type, note, edit/delete)
class DashboardAnalyticsSection extends StatelessWidget {
  final StatusSummary summary;
  final bool canWrite;
  final ValueChanged<String> onTapPaymentFilter;
  final VoidCallback onOpenNakladnoyTab;
  final ValueChanged<CashTxItem> onEditCashTx;
  final ValueChanged<CashTxItem> onDeleteCashTx;

  const DashboardAnalyticsSection({
    super.key,
    required this.summary,
    required this.canWrite,
    required this.onTapPaymentFilter,
    required this.onOpenNakladnoyTab,
    required this.onEditCashTx,
    required this.onDeleteCashTx,
  });

  @override
  Widget build(BuildContext context) {
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
        // 1. Payment Methods Breakdown (2x2 Bento Grid)
        Row(
          children: [
            const Icon(Icons.pie_chart_rounded,
                size: 19, color: AppTokens.brand),
            const SizedBox(width: 7),
            Text(
              "To'lov turlari bo'yicha (${naks.length} ta)",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textPrimaryOf(context),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onOpenNakladnoyTab,
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text('Ro\'yxat'),
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
                count: cashCnt,
                share: grandTotal > 0
                    ? summary.totalNakladnoySpent / grandTotal
                    : 0,
                icon: Icons.payments_rounded,
                color: AppTokens.cashGreen,
                onTap: () => onTapPaymentFilter('cash'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PaymentKpiCard(
                title: 'Karta (naqdsiz)',
                amount: summary.totalCardSpent,
                count: cardCnt,
                share:
                    grandTotal > 0 ? summary.totalCardSpent / grandTotal : 0,
                icon: Icons.credit_card_rounded,
                color: AppTokens.cardBlue,
                onTap: () => onTapPaymentFilter('card'),
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
                count: transferCnt,
                share: grandTotal > 0
                    ? summary.totalTransferSpent / grandTotal
                    : 0,
                icon: Icons.account_balance_rounded,
                color: AppTokens.transferPurple,
                onTap: () => onTapPaymentFilter('transfer'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PaymentKpiCard(
                title: 'Qarzga (bugun)',
                amount: summary.totalDebtNakladnoy,
                count: debtCnt,
                share: grandTotal > 0
                    ? summary.totalDebtNakladnoy / grandTotal
                    : 0,
                icon: Icons.push_pin_rounded,
                color: AppTokens.debtAmber,
                subtitle: summary.allUnpaidDebtCount > 0
                    ? 'Jami qarz: ${formatUzsCompact(summary.allUnpaidDebtTotal)}'
                    : null,
                onTap: () => onTapPaymentFilter('debt'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // 2. Pul oldi-berdi va Kassa qarz / qaytarish tarixi (Full Timeline Card)
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
                        color: AppTokens.cashGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.swap_vert_circle_rounded,
                          color: AppTokens.cashGreen, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pul oldi-berdi va Kassa amallari',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: textPrimaryOf(context),
                            ),
                          ),
                          Text(
                            'Bugungi kirim, kassadan qarz va qaytarishlar (${summary.cashTransactions.length} ta)',
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
                const SizedBox(height: 12),

                // Mini summary strip for Kassa
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          label: 'Qaytarildi',
                          value: '-${formatUzs(summary.kassaRepayToday)}',
                          color: AppTokens.debtAmber,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (summary.cashTransactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      "Bugun hali kassa amallari kiritilmagan. Yuqoridagi 'Pul oldim', 'Kassa qarz' yoki 'Qaytarish' tugmasidan qo'shing.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textSecondaryOf(context),
                      ),
                    ),
                  )
                else
                  ...summary.cashTransactions.reversed.map((tx) {
                    final spec = _txTypeSpec(context, tx.sourceType);
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: spec.bg,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: spec.border),
                      ),
                      child: Row(
                        children: [
                          Icon(spec.icon, color: spec.fg, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      spec.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: textPrimaryOf(context),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: spec.fg.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tx.timeHm,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: spec.fg,
                                          fontFeatures: AppTokens.tabularNums,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (tx.note.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Izoh: ${tx.note}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            '${spec.sign}${formatUzs(tx.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              color: spec.fg,
                              fontFeatures: AppTokens.tabularNums,
                            ),
                          ),
                          if (canWrite) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded,
                                  size: 18, color: textSecondaryOf(context)),
                              onSelected: (v) {
                                if (v == 'edit') onEditCashTx(tx);
                                if (v == 'delete') onDeleteCashTx(tx);
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
                                          style: TextStyle(
                                              color: AppTokens.dangerRed)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Top Postavshiklar (Ranked Visual Bars)
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
                          'Bugungi Top Postavshiklar',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: textPrimaryOf(context),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onOpenNakladnoyTab,
                        child: const Text('Barchasi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...topSuppliers.take(6).map((entry) {
                    final ratio =
                        (entry.value.sum / maxSupSum).clamp(0.06, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                            ],
                          ),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 7,
                              backgroundColor: AppTokens.brand
                                  .withValues(alpha: 0.12),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppTokens.brand),
                            ),
                          ),
                        ],
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

  ({
    String title,
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
          title: 'Kassadan qarz olindi',
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
          title: 'Kassaga qaytarildi',
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
          title: 'Asosiy pul olindi',
          sign: '+',
          icon: Icons.add_card_rounded,
          fg: fg,
          bg: bg,
          border: border,
        );
    }
  }
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
  final int count;
  final double share;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback onTap;

  const _PaymentKpiCard({
    required this.title,
    required this.amount,
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
    return Card(
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
                child: Text(
                  formatUzs(amount, withCurrency: true),
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
      'sub': "Qo'ldagi naqd puldan ayriladi (standart)",
      'color': AppTokens.cashGreen,
    },
    {
      'key': 'card',
      'label': 'Karta',
      'icon': Icons.credit_card_rounded,
      'sub': 'Naqddan ayrilmaydi — faqat statistikada',
      'color': AppTokens.cardBlue,
    },
    {
      'key': 'transfer',
      'label': "O'tkazma",
      'icon': Icons.account_balance_rounded,
      'sub': 'Perechesleniya — naqddan ayrilmaydi',
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
    final (activeFg, _, _) = AppTokens.semanticSurface(context, baseColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.85,
          children: modes.map((m) {
            final key = m['key'] as String;
            final isSelected = key == selectedMode;
            final c = m['color'] as Color;
            final (fg, bg, border) = AppTokens.semanticSurface(context, c);
            final ic = m['icon'] as IconData;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: isSelected
                      ? bg
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? border : Colors.transparent,
                    width: 1.8,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      ic,
                      size: 18,
                      color: isSelected ? fg : textSecondaryOf(context),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        m['label'] as String,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 13.5,
                          color: isSelected ? fg : textPrimaryOf(context),
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle_rounded, size: 15, color: fg),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: activeFg),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                current['sub'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: activeFg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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

    return Card(
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
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded,
                                size: 12.5, color: textSecondaryOf(context)),
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
                            const SizedBox(width: 8),
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
                            if (item.hasPhoto) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.image_rounded, size: 14, color: fg),
                            ],
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
                      minimumSize: const Size(80, 44),
                    ),
                    onPressed: onQuickPay,
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 18),
                    label: const Text("Qarzni to'lash (Naqd / Karta / O'tkazma)"),
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
