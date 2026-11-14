import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../domain/trade/bond_payment.dart';
import '../../domain/trade/wallet_payment.dart';
import '../../domain/trade_record.dart';
import '../../presentation/bond_payment_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../widgets/trade_button.dart';
import 'wallet_payment_section.dart';

/// « Pay with this wallet », the slot of the bond panel at status 3 (#100, W4): the Instant payments balance, the button, the swap service's quote and its confirmation, the payment and where it stands, as the study of #100 (§ 4) words them.
///
/// The quote is asked only on the tap of « Pay with this wallet », never when the panel opens; the payment is made only on the tap of its confirmation, « Pay {total} sats ». A refusal opens « Pay with another wallet », and « Pay with this wallet » stays offered while nothing left the wallet.
/// It reads and drives one [BondPaymentCubit]; it names neither the wallet's port nor its payment.
class BondPaymentPanel extends StatefulWidget {
  final WalletPaymentRequest request;

  const BondPaymentPanel({super.key, required this.request});

  /// The slot for [request], as the trade screen's [WalletPaymentBuilder]: nothing when the wallet has nothing to offer (no Instant payments wallet, an invoice it is not offered for, records it cannot read), so that « Pay with another wallet » opens at once.
  static WalletPaymentSlot? slotFor(
    BuildContext context,
    WalletPaymentRequest request,
  ) {
    final state = context.watch<BondPaymentCubit>().state;
    final panel = BondPaymentPanel(request: request);
    final step = state.step;
    if (step is BondPayUnreadable) return null;
    if (state.balance case Err()) {
      // No Instant payments wallet to pay from; a payment made earlier is still shown.
      return step is BondPayFollowing ? WalletPaymentSlot(panel) : null;
    }
    return switch (step) {
      BondPayFollowing(:final progress) => WalletPaymentSlot(
        panel,
        othersOpen: progress is P2pWalletPaymentSigned,
      ),
      BondPayIdle(:final refused?) => WalletPaymentSlot(
        panel,
        othersOpen: !refused.fundsMayHaveMoved,
      ),
      // Checked and not offered: nothing in the slot, but the panel is kept so that it checks again for the next status.
      BondPayIdle() when state.offer is Err => WalletPaymentSlot(
        BondPaymentPanel(request: request),
        othersOpen: true,
      ),
      _ => WalletPaymentSlot(panel),
    };
  }

  @override
  State<BondPaymentPanel> createState() => _BondPaymentPanelState();
}

class _BondPaymentPanelState extends State<BondPaymentPanel> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(BondPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request.seen, widget.request.seen)) _check();
  }

  /// Asks whether the wallet is offered for the status shown, without the swap service, after the frame: the cubit checks once per status.
  void _check() {
    final seen = widget.request.seen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<BondPaymentCubit>().offerFor(seen));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final cubit = context.read<BondPaymentCubit>();
    final state = context.watch<BondPaymentCubit>().state;
    final step = state.step;
    final coordinator = bondPaymentCoordinator(widget.request.record);
    final balance = switch (state.balance) {
      Ok(:final value) => value,
      _ => null,
    };
    final offered = state.offer is Ok;
    final children = <Widget>[
      if (balance != null && step is! BondPayFollowing)
        Text(
          l10n.p2pPayBalance(formats.sats(balance.value.toInt())),
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      ...switch (step) {
        BondPayLooking() => const <Widget>[],
        BondPayIdle(:final refused) => [
          if (refused != null)
            BondPaymentLine.text(
              bondPayRefusalText(context, refused),
              color: colors.error,
            ),
          if (offered && balance != null)
            TradeButton(
              label: l10n.p2pPayWithThisWallet,
              onPressed: () => unawaited(cubit.ask(widget.request.seen)),
            ),
        ],
        BondPayQuoting() => [
          TradeButton(
            label: l10n.p2pPayWithThisWallet,
            busy: true,
            onPressed: () {},
          ),
          BondPaymentLine.text(l10n.p2pPayQuoting),
        ],
        BondPayConfirming(:final walletQuote) => [
          _Confirmation(
            walletQuote: walletQuote,
            onCancel: cubit.dismiss,
            onPay: () => unawaited(cubit.confirm()),
          ),
        ],
        BondPaySending() => [
          TradeButton(
            label: l10n.p2pPayWithThisWallet,
            busy: true,
            onPressed: () {},
          ),
          BondPaymentLine.text(l10n.p2pPaySending),
        ],
        BondPayFollowing(:final progress) => [
          BondPaymentLine.text(
            bondPaymentProgressText(
              context,
              progress,
              atBondStep: true,
              coordinator: coordinator,
            ),
          ),
        ],
        BondPayUnreadable() => [
          BondPaymentLine.text(l10n.p2pPayWalletUnavailable),
        ],
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Gap(BullSpacing.sm),
          child,
        ],
      ],
    );
  }
}

/// The confirmation: the invoice's amount, the swap service's fee, the network fee, the total and what stays, the swap service's custody, « Cancel » and « Pay {total} sats », the only tap that pays.
class _Confirmation extends StatelessWidget {
  final P2pWalletQuote walletQuote;
  final VoidCallback onCancel;
  final VoidCallback onPay;

  const _Confirmation({
    required this.walletQuote,
    required this.onCancel,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String sats(Sats amount) => formats.sats(amount.value.toInt());
    final body = text.bodyMedium?.copyWith(color: colors.text);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              header: true,
              liveRegion: true,
              child: Text(
                l10n.p2pPayConfirmTitle(sats(walletQuote.amount)),
                style: text.headlineMedium?.copyWith(color: colors.text),
              ),
            ),
            const Gap(BullSpacing.sm),
            Text(
              l10n.p2pPayServiceFee(sats(walletQuote.serviceFee)),
              style: body,
            ),
            Text(
              l10n.p2pPayNetworkFee(sats(walletQuote.networkFee)),
              style: body,
            ),
            const Gap(BullSpacing.xs),
            Text(
              l10n.p2pPayTotal(
                sats(walletQuote.total),
                sats(walletQuote.remaining),
              ),
              style: body,
            ),
            const Gap(BullSpacing.sm),
            Text(
              l10n.p2pPayCustody,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const Gap(BullSpacing.md),
            TradeButton(
              label: l10n.p2pCommonCancel,
              outlined: true,
              onPressed: onCancel,
            ),
            const Gap(BullSpacing.sm),
            TradeButton(
              label: l10n.p2pPayConfirm(sats(walletQuote.total)),
              onPressed: onPay,
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of the wallet's payment of the bond, which wraps at any text size and is read out when it changes.
///
/// [BondPaymentLine.new], after status 3: where the payment of a bond paid by this wallet stands (held by the swap service, refund pending, refunded, kept), from the trade's [BondPaymentCubit]; nothing when the bond was not paid by this wallet.
class BondPaymentLine extends StatelessWidget {
  final String? _text;
  final Color? color;

  const BondPaymentLine({super.key}) : _text = null, color = null;

  const BondPaymentLine.text(String this._text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final line =
        _text ??
        switch (context.watch<BondPaymentCubit>().state.step) {
          BondPayFollowing(:final progress) => bondPaymentProgressText(
            context,
            progress,
            atBondStep: false,
            coordinator: bondPaymentCoordinator(
              context.read<BondPaymentCubit>().record,
            ),
          ),
          _ => null,
        };
    if (line == null) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      child: Text(
        line,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: color ?? colors.text),
      ),
    );
  }
}

/// The name of [record]'s coordinator for the panel's texts, cleaned as every coordinator name is.
String bondPaymentCoordinator(TradeRecord record) => CoordinatorText.of(
  Federation.robosats.byAlias(record.coordinatorAlias)?.longAlias ??
      record.coordinatorAlias,
  maxCodePoints: CoordinatorText.name,
);

/// What the panel says of a payment of the bond at [progress]: at status 3 ([atBondStep]) until the coordinator sees the bond locked, after it while the trade goes on or once it ended.
String bondPaymentProgressText(
  BuildContext context,
  P2pWalletPaymentProgress progress, {
  required bool atBondStep,
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  return switch (progress) {
    P2pWalletPaymentPreparing() => l10n.p2pPaySending,
    P2pWalletPaymentSigned() => l10n.p2pPayInterrupted,
    P2pWalletPaymentBroadcastUnknown() => l10n.p2pPayMaybeSent,
    P2pWalletPaymentSent() || P2pWalletPaymentPending() =>
      atBondStep ? l10n.p2pPaySent(coordinator) : l10n.p2pPayHeld,
    P2pWalletPaymentUnderReview() => l10n.p2pPayUnderReview,
    P2pWalletPaymentPaid() => l10n.p2pPaySettled(coordinator),
    P2pWalletPaymentRefundPending() => l10n.p2pPayRefundPending,
    P2pWalletPaymentRefunded() => l10n.p2pPayRefunded,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) ||
    P2pWalletPaymentFailed(
      funds: P2pWalletFunds.notSent,
    ) => l10n.p2pPayWalletUnavailable,
    P2pWalletPaymentExpired() ||
    P2pWalletPaymentFailed() => l10n.p2pPayAskSupport,
  };
}

/// Why the wallet did not quote or pay the bond, in the panel's words.
String bondPayRefusalText(BuildContext context, BondPayRefusal refusal) {
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  String sats(Sats amount) => formats.sats(amount.value.toInt());
  return switch (refusal) {
    BondPayNotAtBondStep() || BondPayInvoiceChanged() => l10n.p2pPayOrderMoved,
    BondPayNotOffered(reason: WalletPaymentRefusal.tooLate) =>
      l10n.p2pPayTooLate,
    BondPayNotOffered() ||
    BondPayTradeUnavailable() => l10n.p2pPayWalletUnavailable,
    BondPayNotRecorded() => l10n.p2pPayNotRecorded,
    BondPayWalletRefused(:final refusal) => switch (refusal) {
      P2pWalletUnderMinimum(minimum: final minimum?) => l10n.p2pPayUnderMinimum(
        sats(minimum),
      ),
      P2pWalletUnderMinimum() => l10n.p2pPayUnderMinimumUnknown,
      P2pWalletOverMaximum(maximum: final maximum?) => l10n.p2pPayOverMaximum(
        sats(maximum),
      ),
      P2pWalletOverMaximum() ||
      P2pWalletOutsideServiceLimits() => l10n.p2pPayOutsideLimits,
      P2pWalletNotEnoughBalance(:final available, :final needed) =>
        l10n.p2pPayNotEnough(sats(available), sats(needed)),
      P2pWalletServiceUnreachable() => l10n.p2pPayUnreachable,
      P2pWalletServiceBusy() => l10n.p2pPayBusy,
      P2pWalletInvoiceExpiresTooSoon() ||
      P2pWalletOrderExpiresTooSoon() ||
      P2pWalletInvoiceExpired() => l10n.p2pPayTooLate,
      P2pWalletQuoteChanged() => l10n.p2pPayFeesChanged,
      P2pWalletPaymentExists() => l10n.p2pPayAlreadyPaid,
      P2pWalletBroadcastUnknown() => l10n.p2pPayMaybeSent,
      P2pWalletPaymentInterrupted() => l10n.p2pPayInterrupted,
      P2pWalletNeedsConsolidation() ||
      P2pWalletNoInstantWallet() ||
      P2pWalletUnavailable() ||
      P2pWalletWrongNetwork() ||
      P2pWalletInvoiceUnreadable() ||
      P2pWalletServiceRefused() ||
      P2pWalletQuoteStale() => l10n.p2pPayWalletUnavailable,
    },
  };
}
