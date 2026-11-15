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
import '../../presentation/trade_cubit.dart';
import '../widgets/trade_button.dart';
import 'wallet_payment_section.dart';

/// « Pay with this wallet », the slot of the bond panel at status 3 (#100, W4): the Instant payments balance, the button, the swap's quote and its confirmation, the payment and where it stands, in the reference's words and the wallet's for the swap (#135).
///
/// The quote is asked only on the tap of « Pay with this wallet », never when the panel opens; the payment is made only on the tap of its confirmation, « Pay {total} sats ». Every wait says what it waits for (the fees, the sending, the coordinator's lock), and the line of the payment is brought into view when it changes.
/// While this wallet pays, or once its payment may have moved funds, « Pay with another wallet » closes and offers neither the QR code nor the copy of the same invoice. A refusal that moved nothing opens it, and « Pay with this wallet » stays offered.
/// It reads and drives one [BondPaymentCubit]; it names neither the wallet's port nor its payment.
class BondPaymentPanel extends StatefulWidget {
  final WalletPaymentRequest request;

  const BondPaymentPanel({super.key, required this.request});

  /// The slot for [request], as the trade screen's [WalletPaymentBuilder]: nothing when the wallet has nothing to offer or say (no Instant payments wallet, the invoice past its end with no payment), so that « Pay with another wallet » opens at once.
  static WalletPaymentSlot? slotFor(
    BuildContext context,
    WalletPaymentRequest request,
  ) {
    final state = context.watch<BondPaymentCubit>().state;
    final panel = BondPaymentPanel(request: request);
    final step = state.step;
    final offering = switch (step) {
      BondPayLooking() || BondPayIdle() || BondPayQuoting() => true,
      BondPayConfirming() => true,
      _ => false,
    };
    // No Instant payments wallet, or the invoice past its end: the wallet offers nothing more, but a payment it made or is making is still said.
    if (offering &&
        (request.invoiceExpired ||
            state.balance is Err<Sats, P2pWalletRefusal>)) {
      return null;
    }
    return switch (step) {
      // A payment may exist: the line says the panel cannot tell where it stands, and nothing invites paying again, the other way not opened.
      BondPayUnreadable(:final paymentMayExist) => WalletPaymentSlot(
        panel,
        othersHidden: paymentMayExist,
      ),
      // The user chose this wallet: the other way closes while the quote is asked and confirmed, and while the payment is sent.
      BondPayQuoting() ||
      BondPayConfirming() ||
      BondPaySending() => WalletPaymentSlot(panel, othersHidden: true),
      BondPayFollowing(:final progress) => _following(panel, progress),
      BondPayPaidElsewhere(:final progress) =>
        progress.fundsMayHaveLeft
            ? WalletPaymentSlot(panel, othersHidden: true)
            : WalletPaymentSlot(panel, othersOpen: true),
      BondPayIdle(:final refused?) => WalletPaymentSlot(
        panel,
        othersOpen: !refused.fundsMayHaveMoved,
      ),
      // Checked and not offered: the reason, and the other way open.
      BondPayIdle() when state.offer is Err => WalletPaymentSlot(
        panel,
        othersOpen: true,
      ),
      _ => WalletPaymentSlot(panel),
    };
  }

  static WalletPaymentSlot _following(
    BondPaymentPanel panel,
    P2pWalletPaymentProgress progress,
  ) => switch (progress) {
    // Nothing left the wallet, or the swap service is refunding it without having paid: the other way is the one left.
    P2pWalletPaymentSigned() ||
    P2pWalletPaymentRefundPending() ||
    P2pWalletPaymentRefunded() => WalletPaymentSlot(panel, othersOpen: true),
    _ when !progress.fundsMayHaveLeft => WalletPaymentSlot(
      panel,
      othersOpen: true,
    ),
    _ => WalletPaymentSlot(panel, othersHidden: true),
  };

  /// Where the payment of the bond stands, for « Cancel »: being sent, or sent (its funds may have left the wallet).
  static WalletBondState bondOf(BuildContext context) => switch (context
      .watch<BondPaymentCubit>()
      .state
      .step) {
    BondPaySending() => const WalletBondState(sending: true, sent: false),
    BondPayFollowing(:final progress) || BondPayPaidElsewhere(:final progress)
        when _onItsWay(progress) =>
      const WalletBondState(sending: false, sent: true),
    BondPayUnreadable(paymentMayExist: true) => const WalletBondState(
      sending: false,
      sent: true,
    ),
    _ => WalletBondState.none,
  };

  /// A payment on its way to the coordinator: sent, held, or not yet known; not refunded, being refunded, or settled.
  static bool _onItsWay(P2pWalletPaymentProgress progress) =>
      switch (progress) {
        P2pWalletPaymentSent() ||
        P2pWalletPaymentPending() ||
        P2pWalletPaymentBroadcastUnknown() ||
        P2pWalletPaymentUnderReview() => true,
        _ => false,
      };

  @override
  State<BondPaymentPanel> createState() => _BondPaymentPanelState();
}

class _BondPaymentPanelState extends State<BondPaymentPanel> {
  /// The line of the payment, and the confirmation's « Pay » button, brought into view when they appear.
  final _lineKey = GlobalKey();
  final _payKey = GlobalKey();

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

  /// Brings [key]'s widget into view after the frame: the line of a payment being sent or sent, the « Pay » button of a confirmation.
  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (mounted && target != null && target.mounted) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      }
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
    // A cancel of the order holds its lock: the payment waits for it, so the button waits too.
    final cancelling = context.select<TradeCubit, bool>(
      (trade) => trade.state.cancel is CancelRunning,
    );
    final balance = switch (state.balance) {
      Ok(:final value) => value,
      _ => null,
    };
    final offer = state.offer;
    final offered = offer is Ok && !widget.request.invoiceExpired;
    final notOffered = switch (offer) {
      Err(:final failure) => failure,
      _ => null,
    };
    final showsBalance =
        balance != null &&
        switch (step) {
          BondPayLooking() || BondPayQuoting() || BondPayConfirming() => true,
          BondPayIdle(:final refused) => refused != null || notOffered == null,
          _ => false,
        };
    Widget line(String value, {Color? color}) => KeyedSubtree(
      key: _lineKey,
      child: BondPaymentLine.text(value, color: color),
    );
    final children = <Widget>[
      if (showsBalance)
        Text(
          l10n.p2pPayBalance(formats.sats(balance.value.toInt())),
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
      ...switch (step) {
        BondPayLooking() => const <Widget>[],
        BondPayIdle(:final refused) => [
          if (refused != null)
            line(
              bondPayRefusalText(context, refused, coordinator: coordinator),
              color: colors.error,
            )
          else if (notOffered != null)
            // Not offered for this invoice: why, in the panel's words.
            line(
              bondPayRefusalText(context, notOffered, coordinator: coordinator),
              color: colors.textMuted,
            ),
          if (offered && balance != null)
            TradeButton(
              label: l10n.p2pPayWithThisWallet,
              onPressed: cancelling
                  ? null
                  : () => unawaited(cubit.ask(widget.request.seen)),
            ),
        ],
        BondPayQuoting() => [
          TradeButton(
            label: l10n.p2pPayWithThisWallet,
            busy: true,
            onPressed: () {},
          ),
          line(l10n.p2pPayQuoting),
        ],
        BondPayConfirming(:final walletQuote) => [
          _Confirmation(
            walletQuote: walletQuote,
            payKey: _payKey,
            onCancel: cubit.dismiss,
            onPay: () => unawaited(cubit.confirm()),
          ),
        ],
        BondPaySending(:final slow) => [
          TradeButton(
            label: l10n.p2pPayWithThisWallet,
            busy: true,
            onPressed: () {},
          ),
          line(l10n.p2pPaySending),
          if (slow) BondPaymentLine.text(l10n.p2pPayStillSending),
        ],
        BondPayFollowing(:final progress) => [
          line(
            bondPaymentProgressText(
              context,
              progress,
              coordinator: coordinator,
            ),
          ),
        ],
        BondPayPaidElsewhere(:final progress) => [
          line(
            progress.fundsMayHaveLeft
                ? l10n.p2pPayAlreadyPaid
                : l10n.p2pPayInterrupted,
          ),
        ],
        BondPayUnreadable() => [line(l10n.p2pPayUnreadable)],
      },
    ];
    return BlocListener<BondPaymentCubit, BondPaymentState>(
      listenWhen: (previous, current) =>
          previous.step.runtimeType != current.step.runtimeType,
      listener: (context, state) => switch (state.step) {
        BondPayConfirming() => _reveal(_payKey),
        BondPaySending() ||
        BondPayFollowing() ||
        BondPayPaidElsewhere() => _reveal(_lineKey),
        _ => null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const Gap(BullSpacing.sm),
            child,
          ],
        ],
      ),
    );
  }
}

/// The confirmation: the invoice's amount, the swap fees, the network fee, the total and what stays, the reference's sentence on a hold invoice, « Go back » and « Pay {total} sats », the only tap that pays.
class _Confirmation extends StatelessWidget {
  final P2pWalletQuote walletQuote;
  final GlobalKey payKey;
  final VoidCallback onCancel;
  final VoidCallback onPay;

  const _Confirmation({
    required this.walletQuote,
    required this.payKey,
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
            // The reference's sentence on a hold invoice, word for word (the owner's decision, #135): here while the confirmation is open, the other wallet's section then not showing it.
            Text(
              l10n.p2pTradeHoldInvoiceBond,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const Gap(BullSpacing.md),
            // The reference's word for stepping back in its dialogs (#134): never the trade's « Cancel », a few rows below.
            TradeButton(
              label: l10n.p2pCommonGoBack,
              outlined: true,
              onPressed: onCancel,
            ),
            const Gap(BullSpacing.sm),
            KeyedSubtree(
              key: payKey,
              child: TradeButton(
                label: l10n.p2pPayConfirm(sats(walletQuote.total)),
                onPressed: onPay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of the wallet's payment of the bond, which wraps at any text size and is read out when it changes.
///
/// [BondPaymentLine.new], after status 3: where the payment of a bond paid by this wallet stands, from the trade's [BondPaymentCubit]: nothing while the bond is locked ([bondHeld], the reference's bond line says it), « Your swap is in progress. » for a payment sent elsewhere, the refund, the bond kept or the review; nothing when the bond was not paid by this wallet, or nothing left the wallet.
class BondPaymentLine extends StatelessWidget {
  final String? _text;
  final Color? color;

  /// Whether the trade goes on after the bond's lock (status 6 until before its end): only then is the bond said locked.
  final bool bondHeld;

  const BondPaymentLine({super.key, this.bondHeld = false})
    : _text = null,
      color = null;

  const BondPaymentLine.text(String this._text, {super.key, this.color})
    : bondHeld = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final line =
        _text ??
        switch (context.watch<BondPaymentCubit>().state.step) {
          BondPayFollowing(:final progress) => bondPaymentAfterText(
            context,
            progress,
            bondHeld: bondHeld,
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

/// What the panel says, at status 3, of a payment of the bond at [progress].
String bondPaymentProgressText(
  BuildContext context,
  P2pWalletPaymentProgress progress, {
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  return switch (progress) {
    P2pWalletPaymentPreparing() => l10n.p2pPaySending,
    P2pWalletPaymentSigned() => l10n.p2pPayInterrupted,
    P2pWalletPaymentBroadcastUnknown() => l10n.p2pPayMaybeSent,
    P2pWalletPaymentSent() ||
    P2pWalletPaymentPending() => l10n.p2pPaySent(coordinator),
    P2pWalletPaymentUnderReview() => l10n.p2pPayUnderReview,
    P2pWalletPaymentPaid() => l10n.p2pPaySettled(coordinator),
    // At 3 the bond was never locked: the invoice was not paid, and the payin is being refunded, or was.
    P2pWalletPaymentRefundPending() => l10n.p2pPayServiceCouldNotPay,
    P2pWalletPaymentRefunded() => l10n.p2pPayServiceRefunded,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) ||
    P2pWalletPaymentFailed(
      funds: P2pWalletFunds.notSent,
    ) => l10n.p2pPayWalletUnavailable,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.sent) =>
      l10n.p2pPayAskSupportExpiredSent,
    P2pWalletPaymentFailed(funds: P2pWalletFunds.sent) =>
      l10n.p2pPayAskSupportSent,
    P2pWalletPaymentExpired() => l10n.p2pPayAskSupportExpired,
    P2pWalletPaymentFailed() => l10n.p2pPayAskSupport,
  };
}

/// What the line after status 3 says of a payment of the bond at [progress], `null` when nothing left the wallet: locked only when [bondHeld].
String? bondPaymentAfterText(
  BuildContext context,
  P2pWalletPaymentProgress progress, {
  required bool bondHeld,
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  return switch (progress) {
    P2pWalletPaymentPreparing() || P2pWalletPaymentSigned() => null,
    P2pWalletPaymentBroadcastUnknown() => l10n.p2pPayMaybeSent,
    P2pWalletPaymentSent() || P2pWalletPaymentPending() =>
      // While the bond is locked the reference's own bond line says so: nothing of ours is added (#135).
      bondHeld ? null : l10n.p2pPayWithSwapService,
    P2pWalletPaymentUnderReview() => l10n.p2pPayUnderReview,
    P2pWalletPaymentPaid() => l10n.p2pPaySettled(coordinator),
    P2pWalletPaymentRefundPending() => l10n.p2pPayRefundPending,
    P2pWalletPaymentRefunded() => l10n.p2pPayRefunded,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) ||
    P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) => null,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.sent) =>
      l10n.p2pPayAskSupportExpiredSent,
    P2pWalletPaymentFailed(funds: P2pWalletFunds.sent) =>
      l10n.p2pPayAskSupportSent,
    P2pWalletPaymentExpired() => l10n.p2pPayAskSupportExpired,
    P2pWalletPaymentFailed() => l10n.p2pPayAskSupport,
  };
}

/// Why the wallet did not quote or pay the bond, in the panel's words.
String bondPayRefusalText(
  BuildContext context,
  BondPayRefusal refusal, {
  required String coordinator,
}) {
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  String sats(Sats amount) => formats.sats(amount.value.toInt());
  return switch (refusal) {
    BondPayNotAtBondStep() || BondPayInvoiceChanged() => l10n.p2pPayOrderMoved,
    BondPayNotOffered(reason: WalletPaymentRefusal.tooLate) =>
      l10n.p2pPayTooLate,
    BondPayTradeUnavailable() => l10n.p2pPayCoordinatorUnreachable(coordinator),
    BondPayReadSuperseded() => l10n.p2pPayReadSuperseded(coordinator),
    BondPayNotOffered() => l10n.p2pPayWalletUnavailable,
    BondPayNotRecorded() => l10n.p2pPayNotRecorded,
    BondPayRecordsUnreadable() => l10n.p2pRobotRecordsUnreadable,
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
      P2pWalletNoBitcoinWallet() ||
      P2pWalletUnavailable() ||
      P2pWalletWrongNetwork() ||
      P2pWalletInvoiceUnreadable() ||
      P2pWalletServiceRefused() ||
      P2pWalletQuoteStale() => l10n.p2pPayWalletUnavailable,
    },
  };
}
