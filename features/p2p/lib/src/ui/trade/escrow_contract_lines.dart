import 'package:flutter/widgets.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/escrow_contract.dart';
import '../../presentation/p2p_formats.dart';

/// A red alert the confirmation of a maker seller's escrow says of the order's earlier escrows: in two lines when the owner validated its words ([title], bold, then [line] with the figures, the explanation [detail] in the confirmation's detail, #250), else one bold [line] in the words of #187 ([title] and [detail] `null`).
@immutable
final class EarlierEscrowAlert {
  final String? title;
  final String line;
  final String? detail;

  const EarlierEscrowAlert(this.line, {this.title, this.detail});

  @override
  bool operator ==(Object other) =>
      other is EarlierEscrowAlert &&
      other.title == title &&
      other.line == line &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(title, line, detail);

  @override
  String toString() => [?title, line, ?detail].join(' | ');
}

/// The red alerts the confirmation of a maker seller's escrow says of the order's earlier escrows (#187, the owner's decision of 2026-11-19: no lock, an alert, the user free to pay), in the user's language: first the earlier escrows not back yet, what they took out of the wallet and what will be out with this one (the confirmed quotes' totals, fees included, the same sats as « Pay »), agreed in number; then each escrow the coordinator kept. Empty when nothing is to be said.
///
/// One earlier escrow not back, of a known amount, takes the two lines the owner validated on 2026-11-24 (#250): « A previous collateral has not come back », « With this one, {total} sats will be out of this wallet. », its explanation in the detail. Several, an amount not known, and an escrow kept keep the words of #187, one line each: the validated page does not cover them.
///
/// Shown in red above the buttons of a maker seller's confirmation (#188, `pay_confirmation_card.dart`), tested by `escrow_contract_lines_test.dart`. [coordinator] is the coordinator's name as the panel words it (`bondPaymentCoordinator`); no other text of the coordinator.
List<EarlierEscrowAlert> earlierEscrowAlerts(
  BuildContext context,
  EscrowContract contract, {
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  String sats(BigInt value) => formats.bigSats(value);
  final alerts = <EarlierEscrowAlert>[];
  if (contract.notBack.isNotEmpty) {
    final unknown = contract.notBackUnknown;
    final notBack = sats(contract.notBackSats.value);
    final total = sats(contract.outIfPaid.value);
    final all = contract.notBack.length;
    alerts.add(switch (unknown) {
      0 when all == 1 => EarlierEscrowAlert(
        l10n.p2pPayEarlierOutTotal(total),
        title: l10n.p2pPayEarlierNotBack,
        detail: l10n.p2pPayEarlierNotBackDetail(notBack),
      ),
      0 => EarlierEscrowAlert(l10n.p2pEscrowEarlierOut(notBack, total, all)),
      _ when unknown == all => EarlierEscrowAlert(
        l10n.p2pEscrowEarlierOutAllUnknown(total, all),
      ),
      _ => EarlierEscrowAlert(
        l10n.p2pEscrowEarlierOutUnknown(notBack, total, unknown, all - unknown),
      ),
    });
  }
  for (final kept in contract.kept) {
    final amount = kept.sats;
    alerts.add(
      EarlierEscrowAlert(
        amount == null
            ? l10n.p2pEscrowEarlierKeptUnknown(coordinator)
            : l10n.p2pEscrowEarlierKept(sats(amount.value), coordinator),
      ),
    );
  }
  return alerts;
}
