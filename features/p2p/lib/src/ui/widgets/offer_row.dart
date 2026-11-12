import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/bond_warning.dart';
import '../../presentation/p2p_formats.dart';
import 'expiry_ring.dart';
import 'maker_avatar.dart';

/// One offer of the book: the maker's robot and nickname, its role, payment methods, premium and bond, then the amount and the expiry ring.
///
/// The payment methods are maker text: they are shown as plain text only.
class OfferRow extends StatelessWidget {
  final PublicOrder order;
  final DateTime now;
  final VoidCallback onTap;

  const OfferRow({
    super.key,
    required this.order,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final muted = text.labelLarge?.copyWith(color: colors.textMuted);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BullSpacing.md,
          vertical: BullSpacing.sm,
        ),
        child: Row(
          children: [
            MakerAvatar(order: order),
            const Gap(BullSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.maker.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineLarge?.copyWith(color: colors.text),
                  ),
                  const Gap(BullSpacing.xxs),
                  Row(
                    children: [
                      RolePill(type: order.type),
                      const Gap(BullSpacing.xs),
                      Expanded(
                        child: Text(
                          paymentMethodsLine(order.paymentMethods, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                  const Gap(BullSpacing.xxs),
                  _PremiumAndBond(order: order, style: muted),
                ],
              ),
            ),
            const Gap(BullSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // A wide range or a large text size shrinks the amount rather than the robot's line.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formats.orderAmount(order.amount),
                            style: text.headlineLarge?.copyWith(
                              color: colors.text,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          TextSpan(
                            text: ' ${order.currency.code}',
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Gap(BullSpacing.xs),
                ExpiryRing(expiresAt: order.expiresAt, now: now),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The recognised payment methods joined by a middle dot, with « Others » when the maker wrote more, as the official client shows its icons.
  static String paymentMethodsLine(
    PaymentMethods methods,
    P2pLocalizations l10n,
  ) => [
    for (final method in methods.recognized) method.name,
    if (methods.hasOtherText)
      methods.recognized.isEmpty ? methods.text : l10n.p2pBookOthers,
  ].join(' · ');
}

/// « Premium +2.0% · Bond 3% »: a bond below the default is orange, bolder the lower it is, and explained by a tooltip, as in the official client.
class _PremiumAndBond extends StatelessWidget {
  final PublicOrder order;
  final TextStyle? style;

  const _PremiumAndBond({required this.order, required this.style});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final bond = order.bondSize;
    final line = Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${l10n.p2pBookColumnPremium} '),
          TextSpan(
            text: formats.premium(order.premium),
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · ${l10n.p2pBookColumnBond} '),
          TextSpan(
            text: formats.bond(bond),
            style: bond.isLow
                ? TextStyle(
                    color: colors.warning,
                    fontWeight: lowBondWeight(bond.warningIntensity),
                  )
                : null,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!bond.isLow) return line;
    return Tooltip(
      message: l10n.p2pBookLowBond(formats.number(BondWarning.defaultPercent)),
      child: line,
    );
  }

  /// The weight the official client gives a low bond: 600, plus up to 300 as the bond falls.
  static FontWeight lowBondWeight(double intensity) {
    final weight = 600 + (intensity * 300).round();
    return FontWeight.values[(weight / 100).round().clamp(1, 9) - 1];
  }
}

/// The role of the maker of an order: « Seller » on the primary colour, « Buyer » inverted.
class RolePill extends StatelessWidget {
  final OrderType type;

  const RolePill({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return switch (type) {
      OrderType.sell => BullBadge(
        label: l10n.p2pBookRoleSeller,
        background: colors.primary,
        foreground: colors.onPrimary,
      ),
      OrderType.buy => BullBadge(
        label: l10n.p2pBookRoleBuyer,
        background: colors.secondary,
        foreground: colors.onSecondary,
      ),
    };
  }
}
