import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../domain/trade/bond_payment.dart';
import '../../domain/trade/escrow_contract.dart';
import '../../presentation/bond_payment_cubit.dart';
import '../../presentation/trade_cubit.dart';
import 'bond_payment_panel.dart' show bondPaymentCoordinator;

/// Where the escrows of a maker seller's order paid or attempted with this wallet for its other contracts stand (#188, design note § 2.3, § 4.3; security review of #187, C2, R6): one line per contract, « Take {n}: {state} », in the words of the three cases of the confirmation ([EarlierEscrowCase]: back, not back yet, kept) with what the wallet's records say, « state unknown » for a payment whose records cannot be read or whose recorded wallet id the wallet does not hold; and above them, in red, each escrow whose refund was pending and which the wallet's records now show held again or kept.
///
/// It reads the trade's [EscrowPaymentCubit] (`followEscrows`, listened to again at each contract and after each payment), whatever the view, a wait included, after the trade's end too, as the line of the current escrow (`BondPaymentLine`); the escrow of the contract the trade stands at is that line's, never here. Nothing to tap: it pays nothing and offers nothing.
class EarlierEscrowLines extends StatelessWidget {
  const EarlierEscrowLines({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EscrowPaymentCubit?>();
    if (cubit == null) return const SizedBox.shrink();
    final state = cubit.state;
    // The contract the trade stands at, from the trail the screen holds whatever it shows (a wait before the first read included, security review of #188, R3), else the one the panel follows.
    final current =
        context.select<TradeCubit, int?>(
          (trade) => trade.state.seen?.status.trail.take,
        ) ??
        state.followedTake;
    final escrows = switch (state.escrows) {
      EscrowPaymentsFollowed(:final escrows) => [
        for (final escrow in escrows)
          if (escrow.take != current) escrow,
      ],
      _ => const <EscrowPaymentOfContract>[],
    };
    final undone = state.refundsUndone;
    if (escrows.isEmpty && undone.isEmpty) return const SizedBox.shrink();
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final coordinator = bondPaymentCoordinator(cubit.record);
    final lines = <Widget>[
      for (final MapEntry(key: take, value: now) in undone.entries)
        _Alert(
          now is P2pWalletPaymentPaid
              ? l10n.p2pEscrowRefundUndoneKept('${take + 1}', coordinator)
              : l10n.p2pEscrowRefundUndoneHeld('${take + 1}', coordinator),
        ),
      if (escrows.isNotEmpty) ...[
        Text(
          l10n.p2pEscrowsEarlierTitle,
          style: text.bodyMedium?.copyWith(
            color: colors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        for (final escrow in escrows)
          Text(
            l10n.p2pEscrowsEarlierLine(
              '${escrow.take + 1}',
              stateText(context, escrow, coordinator: coordinator),
            ),
            style: text.bodyMedium?.copyWith(
              color: switch (caseOf(escrow)) {
                EarlierEscrowCase.back => colors.textMuted,
                EarlierEscrowCase.notBack => colors.warning,
                EarlierEscrowCase.kept => colors.error,
              },
            ),
          ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, line) in lines.indexed) ...[
              if (index > 0) const Gap(BullSpacing.xs),
              line,
            ],
          ],
        ),
      ),
    );
  }

  /// The case of [escrow] as the confirmation counts it: back when nothing of it is out (refunded, nothing sent, or no payment of this feature for a record with no wallet id), kept when settled, not back yet otherwise, a state that cannot be told included.
  static EarlierEscrowCase caseOf(EscrowPaymentOfContract escrow) {
    if (escrow.stateUnknown) return EarlierEscrowCase.notBack;
    return switch (escrow.watch) {
      BondPaymentFollowed(:final progress) => earlierEscrowCaseOf(progress),
      BondPaymentNone() => EarlierEscrowCase.back,
      BondPaymentUnreadable() => EarlierEscrowCase.notBack,
    };
  }

  /// What the line says of [escrow], in its case's words.
  @visibleForTesting
  static String stateText(
    BuildContext context,
    EscrowPaymentOfContract escrow, {
    required String coordinator,
  }) {
    final l10n = P2pLocalizations.of(context);
    if (escrow.stateUnknown) return l10n.p2pEscrowStateUnknown;
    return switch (escrow.watch) {
      BondPaymentNone() => l10n.p2pEscrowStateNothingSent,
      BondPaymentUnreadable() => l10n.p2pEscrowStateUnknown,
      BondPaymentFollowed(:final progress) => switch (progress) {
        P2pWalletPaymentRefunded() => l10n.p2pEscrowStateRefunded,
        P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) ||
        P2pWalletPaymentExpired(
          funds: P2pWalletFunds.notSent,
        ) => l10n.p2pEscrowStateNothingSent,
        P2pWalletPaymentPaid() => l10n.p2pEscrowStateKept(coordinator),
        P2pWalletPaymentRefundPending() => l10n.p2pEscrowStateRefundPending,
        P2pWalletPaymentPreparing() ||
        P2pWalletPaymentSigned() => l10n.p2pEscrowStatePreparing,
        P2pWalletPaymentBroadcastUnknown() => l10n.p2pEscrowStateMaybeSent,
        P2pWalletPaymentSent() => l10n.p2pEscrowStateWithService,
        P2pWalletPaymentPending() => l10n.p2pEscrowStateHeld(coordinator),
        P2pWalletPaymentUnderReview() => l10n.p2pEscrowStateUnderReview,
        P2pWalletPaymentFailed() ||
        P2pWalletPaymentExpired() => l10n.p2pEscrowStateAskSupport,
      },
    };
  }
}

/// A red line with its icon, read out when it appears.
class _Alert extends StatelessWidget {
  final String text;

  const _Alert(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: colors.error,
          ),
        ),
        const Gap(BullSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
