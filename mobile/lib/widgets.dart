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
        gradient: const LinearGradient(
          colors: [AppTokens.navyDark, AppTokens.navyPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTokens.navyPrimary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Date & Telegram Group status pill
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 13, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      summary.reportDate,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: grp.bound
                      ? const Color(0xFF10B981).withValues(alpha: 0.22)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: grp.bound
                        ? const Color(0xFF34D399).withValues(alpha: 0.5)
                        : const Color(0xFFFBBF24).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      grp.bound
                          ? Icons.send_rounded
                          : Icons.warning_amber_rounded,
                      size: 13,
                      color: grp.bound
                          ? const Color(0xFF6EE7B7)
                          : const Color(0xFFFDE68A),
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 145),
                      child: Text(
                        grp.bound ? grp.title : 'Guruh ulanmagan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: grp.bound
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFFEF3C7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            "QO'LDA QOLISHI KERAK (NAQD)",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatUzs(summary.expectedCash, withCurrency: true),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w800,
                fontFeatures: AppTokens.tabularNums,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricMini(
                        label: 'Jami kirim',
                        value: formatUzs(summary.totalAvailableInflow),
                        icon: Icons.south_west_rounded,
                        color: const Color(0xFF34D399),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricMini(
                        label: 'Naqd rasxod',
                        value: formatUzs(summary.totalNakladnoySpent),
                        icon: Icons.north_east_rounded,
                        color: const Color(0xFFFCA5A5),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MetricMini(
                        label: '💳 Karta',
                        value: formatUzs(summary.totalCardSpent),
                        color: const Color(0xFF93C5FD),
                      ),
                    ),
                    Expanded(
                      child: _MetricMini(
                        label: "🏦 O'tkazma",
                        value: formatUzs(summary.totalTransferSpent),
                        color: const Color(0xFFC4B5FD),
                      ),
                    ),
                    Expanded(
                      child: _MetricMini(
                        label: '📌 Qarzlar',
                        value: formatUzs(summary.allUnpaidDebtTotal),
                        color: const Color(0xFFFCD34D),
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
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Pul oldim',
                    onTap: onAddCash!,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroActionBtn(
                    icon: Icons.account_balance_outlined,
                    label: 'Kassa qarz',
                    onTap: onKassaDebt!,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeroActionBtn(
                    icon: Icons.keyboard_return_rounded,
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

class _MetricMini extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color color;

  const _MetricMini({
    required this.label,
    required this.value,
    this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: AppTokens.tabularNums,
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
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.w600,
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

/// 4-way payment mode selector (`cash` | `card` | `transfer` | `debt`)
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
      'label': '💵 Naqd',
      'sub': "Qo'ldagi naqd puldan ayriladi",
      'color': AppTokens.cashGreen,
      'bg': AppTokens.cashGreenBg,
    },
    {
      'key': 'card',
      'label': '💳 Karta',
      'sub': 'Naqddan ayrilmaydi, faqat statistikada',
      'color': AppTokens.cardBlue,
      'bg': AppTokens.cardBlueBg,
    },
    {
      'key': 'transfer',
      'label': "🏦 O'tkazma",
      'sub': 'Perechesleniya — naqddan ayrilmaydi',
      'color': AppTokens.transferPurple,
      'bg': AppTokens.transferPurpleBg,
    },
    {
      'key': 'debt',
      'label': '📌 Qarzga',
      'sub': "Pul berilmadi — to'lanmagan qarzga yoziladi",
      'color': AppTokens.debtAmber,
      'bg': AppTokens.debtAmberBg,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final current = modes.firstWhere(
      (m) => m['key'] == selectedMode,
      orElse: () => modes.first,
    );
    final Color activeColor = current['color'] as Color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.9,
          children: modes.map((m) {
            final key = m['key'] as String;
            final isSelected = key == selectedMode;
            final c = m['color'] as Color;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: isSelected
                      ? c.withValues(alpha: 0.14)
                      : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? c : Colors.transparent,
                    width: 1.8,
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      Icon(Icons.check_circle_rounded, size: 17, color: c),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        m['label'] as String,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13.5,
                          color: isSelected ? c : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: activeColor),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                current['sub'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: activeColor,
                  fontWeight: FontWeight.w600,
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

  (String, Color, Color) _badgeSpec() {
    if (item.isDebt) {
      return ('📌 Qarzga', AppTokens.debtAmber, AppTokens.debtAmberBg);
    }
    switch (item.paymentMethod) {
      case 'card':
        return ('💳 Karta', AppTokens.cardBlue, AppTokens.cardBlueBg);
      case 'transfer':
        return (
          "🏦 O'tkazma",
          AppTokens.transferPurple,
          AppTokens.transferPurpleBg
        );
      default:
        return ('💵 Naqd', AppTokens.cashGreen, AppTokens.cashGreenBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeColor, badgeBg) = _badgeSpec();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.displayNum,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: AppTokens.tabularNums,
                        color: isDark
                            ? const Color(0xFF93C5FD)
                            : AppTokens.navyPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.supplierName,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              item.reportDate != null
                                  ? '${item.reportDate} • ${item.timeHm}'
                                  : item.timeHm,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              item.inGroup
                                  ? Icons.cloud_done_rounded
                                  : Icons.save_outlined,
                              size: 13.5,
                              color: item.inGroup
                                  ? AppTokens.cashGreen
                                  : Theme.of(context).hintColor,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.inGroup ? 'Guruhda' : 'Bazada',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: item.inGroup
                                    ? AppTokens.cashGreen
                                    : Theme.of(context).hintColor,
                              ),
                            ),
                            if (item.hasPhoto) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.photo_camera_rounded,
                                  size: 13.5, color: AppTokens.cardBlue),
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
                          fontWeight: FontWeight.w800,
                          fontFeatures: AppTokens.tabularNums,
                          color: item.isDebt ? AppTokens.debtAmber : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark
                              ? badgeColor.withValues(alpha: 0.18)
                              : badgeBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
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
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
              if (onQuickPay != null && item.isDebt) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
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
