import 'package:flutter/widgets.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/escrow_contract.dart';
import '../../presentation/p2p_formats.dart';

/// The red alerts the confirmation of a maker seller's escrow says of the order's earlier escrows (#187, the owner's decision of 2026-11-19: no lock, an alert, the user free to pay), in the user's language: first the earlier escrows not back yet, what they took out of the wallet and what will be out with this one (the confirmed quotes' totals, fees included, the same sats as « Pay »), agreed in number; then each escrow the coordinator kept. Empty when nothing is to be said.
///
/// Written for #188's confirmation, which no screen shows before it: kept in the catalogue and composed by `escrow_contract_lines_test.dart`. [coordinator] is the coordinator's name as the panel words it (`bondPaymentCoordinator`); no other text of the coordinator.
List<String> earlierEscrowAlerts(
  BuildContext context,
  EscrowContract contract, {
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  String sats(BigInt value) => formats.bigSats(value);
  final lines = <String>[];
  if (contract.notBack.isNotEmpty) {
    final unknown = contract.notBackUnknown;
    final notBack = sats(contract.notBackSats.value);
    final total = sats(contract.outIfPaid.value);
    final all = contract.notBack.length;
    lines.add(switch (unknown) {
      0 => l10n.p2pEscrowEarlierOut(notBack, total, all),
      _ when unknown == all => l10n.p2pEscrowEarlierOutAllUnknown(total, all),
      _ => l10n.p2pEscrowEarlierOutUnknown(
        notBack,
        total,
        unknown,
        all - unknown,
      ),
    });
  }
  for (final kept in contract.kept) {
    final amount = kept.sats;
    lines.add(
      amount == null
          ? l10n.p2pEscrowEarlierKeptUnknown(coordinator)
          : l10n.p2pEscrowEarlierKept(sats(amount.value), coordinator),
    );
  }
  return lines;
}
