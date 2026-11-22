import 'package:flutter/material.dart';
import 'api_client.dart';
import 'theme.dart';

class HeroBalanceCard extends StatelessWidget {
  final StatusSummary summary;
  final VoidCallback? onAddCash;
  final VoidCallback? onKassaDebt;
  final VoidCallback? onKassaRepay;
  final VoidCallback? onQuickAiCamera;
  final VoidCallback? onQuickAiGallery;

  const HeroBalanceCard({
    super.key,
    required this.summary,
    this.onAddCash,
    this.onKassaDebt,
    this.onKassaRepay,
    this.onQuickAiCamera,
    this.onQuickAiGallery,
  });

  @override
  Widget build(BuildContext context) {
    final grp = summary.groupInfo;
    final totalOut = summary.totalNakladnoySpent +
        summary.totalCardSpent +
        summary.totalTransferSpent +
        summary.totalDebtNakladnoy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
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
              // Top header: Session date + Group badge
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
                          ? const Color(0xFF10B981).withValues(alpha: 0.22)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: grp.bound
                            ? const Color(0xFF6EE7B7).withValues(alpha: 0.5)
                            : const Color(0xFFFCD34D).withValues(alpha: 0.5),
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
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            grp.bound ? grp.title : 'Guruh ulanmagan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: grp.bound
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEF3C7),
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

              // Kirim vs Naqd Rasxod glass panel
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
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
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _HeroMetricTile(
                            label: 'Naqd nakladnoy',
                            value: formatUzs(summary.totalNakladnoySpent),
                            icon: Icons.north_east_rounded,
                            color: const Color(0xFFFDA4AF),
                          ),
                        ),
                      ],
                    ),
                    if (totalOut > 0) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              if (summary.totalNakladnoySpent > 0)
                                Expanded(
                                  flex: (summary.totalNakladnoySpent * 100 ~/
                                          totalOut)
                                      .clamp(1, 100),
                                  child: Container(
                                      color: const Color(0xFF34D399)),
                                ),
                              if (summary.totalCardSpent > 0)
                                Expanded(
                                  flex: (summary.totalCardSpent * 100 ~/
                                          totalOut)
                                      .clamp(1, 100),
                                  child: Container(
                                      color: const Color(0xFF60A5FA)),
                                ),
                              if (summary.totalTransferSpent > 0)
                                Expanded(
                                  flex: (summary.totalTransferSpent * 100 ~/
                                          totalOut)
                                      .clamp(1, 100),
                                  child: Container(
                                      color: const Color(0xFFC084FC)),
                                ),
                              if (summary.totalDebtNakladnoy > 0)
                                Expanded(
                                  flex: (summary.totalDebtNakladnoy * 100 ~/
                                          totalOut)
                                      .clamp(1, 100),
                                  child: Container(
                                      color: const Color(0xFFFBBF24)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
        ),
        const SizedBox(height: 12),

        // 4 KPI Bento Mini-Cards (Karta, O'tkazma, Qarzlar, Kechadan qoldiq)
        Row(
          children: [
            Expanded(
              child: _BentoStatCard(
                icon: Icons.credit_card_rounded,
                label: 'Karta orqali',
                value: formatUzs(summary.totalCardSpent),
                color: AppTokens.cardBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoStatCard(
                icon: Icons.swap_horiz_rounded,
                label: "O'tkazma",
                value: formatUzs(summary.totalTransferSpent),
                color: AppTokens.transferPurple,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoStatCard(
                icon: Icons.push_pin_rounded,
                label: 'Jami qarzlar',
                value: formatUzs(summary.allUnpaidDebtTotal),
                badge: summary.allUnpaidDebtCount > 0
                    ? '${summary.allUnpaidDebtCount} ta'
                    : null,
                color: AppTokens.debtAmber,
              ),
            ),
          ],
        ),

        // 1-Tap Instant AI Scan Bar right on Dashboard!
        if (onQuickAiCamera != null && onQuickAiGallery != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTokens.brandViolet.withValues(alpha: 0.12),
                  AppTokens.brand.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTokens.brandViolet.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTokens.aiGradient,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tezkor AI Skaner',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Rasmga oling — AI o'zi to'ldiradi",
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onQuickAiCamera,
                  icon: const Icon(Icons.photo_camera_rounded, size: 17),
                  label: const Text('Kamera', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Galereyadan AI skan',
                  onPressed: onQuickAiGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BentoStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? badge;
  final Color color;

  const _BentoStatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.badge,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkCtx(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTokens.cardBorderDark : AppTokens.cardBorderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: AppTokens.tabularNums,
              ),
            ),
          ),
        ],
      ),
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
      color: Colors.white.withValues(alpha: 0.15),
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

/// 4-way payment mode selector (`cash` | `card` | `transfer` | `debt`) with modern Material icons.
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
      'sub': "Qo'ldagi naqd puldan ayriladi",
      'color': AppTokens.cashGreen,
      'bg': AppTokens.cashGreenBg,
    },
    {
      'key': 'card',
      'label': 'Karta',
      'icon': Icons.credit_card_rounded,
      'sub': 'Naqddan ayrilmaydi — faqat statistikada',
      'color': AppTokens.cardBlue,
      'bg': AppTokens.cardBlueBg,
    },
    {
      'key': 'transfer',
      'label': "O'tkazma",
      'icon': Icons.account_balance_rounded,
      'sub': 'Perechesleniya — naqddan ayrilmaydi',
      'color': AppTokens.transferPurple,
      'bg': AppTokens.transferPurpleBg,
    },
    {
      'key': 'debt',
      'label': 'Qarzga',
      'icon': Icons.push_pin_rounded,
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
          childAspectRatio: 2.85,
          children: modes.map((m) {
            final key = m['key'] as String;
            final isSelected = key == selectedMode;
            final c = m['color'] as Color;
            final ic = m['icon'] as IconData;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: isSelected
                      ? c.withValues(alpha: 0.14)
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
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
                    Icon(
                      ic,
                      size: 18,
                      color: isSelected ? c : Theme.of(context).hintColor,
                    ),
                    const SizedBox(width: 7),
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
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle_rounded, size: 15, color: c),
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

  (String, IconData, Color, Color) _badgeSpec() {
    if (item.isDebt) {
      return (
        'Qarzga',
        Icons.push_pin_rounded,
        AppTokens.debtAmber,
        AppTokens.debtAmberBg
      );
    }
    switch (item.paymentMethod) {
      case 'card':
        return (
          'Karta',
          Icons.credit_card_rounded,
          AppTokens.cardBlue,
          AppTokens.cardBlueBg
        );
      case 'transfer':
        return (
          "O'tkazma",
          Icons.account_balance_rounded,
          AppTokens.transferPurple,
          AppTokens.transferPurpleBg
        );
      default:
        return (
          'Naqd',
          Icons.payments_rounded,
          AppTokens.cashGreen,
          AppTokens.cashGreenBg
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (badgeText, badgeIcon, badgeColor, badgeBg) = _badgeSpec();
    final isDark = isDarkCtx(context);

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
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.displayNum,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        fontFeatures: AppTokens.tabularNums,
                        color: badgeColor,
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
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded,
                                size: 12.5,
                                color: Theme.of(context).hintColor),
                            const SizedBox(width: 3),
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
                                  : Icons.storage_rounded,
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
                                fontWeight: FontWeight.w700,
                                color: item.inGroup
                                    ? AppTokens.cashGreen
                                    : Theme.of(context).hintColor,
                              ),
                            ),
                            if (item.hasPhoto) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.image_rounded,
                                  size: 14, color: AppTokens.cardBlue),
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
                          color: item.isDebt ? AppTokens.debtAmber : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? badgeColor.withValues(alpha: 0.18)
                              : badgeBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 12, color: badgeColor),
                            const SizedBox(width: 4),
                            Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
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
                    color: Theme.of(context).hintColor,
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
