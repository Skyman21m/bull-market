import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../domain/trade/bond_payment.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_tolerances.dart';
import '../../domain/trade/wallet_payment.dart';
import '../../domain/trade/wallet_rate_check.dart';
import '../../domain/trade_record.dart';
import '../../presentation/bond_payment_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_cubit.dart';
import '../widgets/trade_button.dart';
import 'wallet_payment_section.dart';

/// « Pay with this wallet », the slot of the bond panel at status 3 (#100, W4) and of the escrow panel at 6 and 7 (#97): the Instant payments balance, the button, the swap's quote and its confirmation, the payment and where it stands, in the reference's words and the wallet's for the swap (#135).
///
/// The same panel and the same steps for both; the escrow's differ only in its texts (« collateral », the reference's line on the escrow's hold invoice) and in one line of the project's in its confirmation, which says that the sats stay with the swap service until the trade ends and what a cancelled trade costs.
///
/// The quote is asked only on the tap of « Pay with this wallet », never when the panel opens; the payment is made only on the tap of its confirmation, « Pay {total} sats ». Every wait says what it waits for (the fees, the sending, the coordinator's lock), and the line of the payment is brought into view when it changes.
/// While this wallet pays, or once its payment may have moved funds, « Pay with another wallet » closes and offers neither the QR code nor the copy of the same invoice. A refusal that moved nothing opens it, and « Pay with this wallet » stays offered.
/// It reads and drives one [BondPaymentCubit], the bond's or the escrow's ([EscrowPaymentCubit]) as the request's step says; it names neither the wallet's port nor its payment.
class BondPaymentPanel extends StatefulWidget {
  final WalletPaymentRequest request;

  const BondPaymentPanel({super.key, required this.request});

  /// The slot for [request], as the trade screen's [WalletPaymentBuilder]: nothing when the wallet has nothing to offer or say (no Instant payments wallet, the invoice past its end with no payment), so that « Pay with another wallet » opens at once.
  static WalletPaymentSlot? slotFor(
    BuildContext context,
    WalletPaymentRequest request,
  ) {
    final BondPaymentCubit cubit = switch (request.step) {
      InvoiceStep.bond => context.watch<BondPaymentCubit>(),
      InvoiceStep.escrow => context.watch<EscrowPaymentCubit>(),
    };
    // A cubit wired to another step's use case offers nothing: the wallet is never offered for an invoice its use case does not pay.
    if (cubit.step != request.step) return null;
    final state = cubit.state;
    // The panel and its lines read the cubit of the request's step.
    final panel = BlocProvider<BondPaymentCubit>.value(
      value: cubit,
      child: BondPaymentPanel(request: request),
    );
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
        othersBehindTap: !paymentMayExist,
      ),
      // Not known yet whether this wallet paid the invoice: the other way only after a tap.
      BondPayLooking() => WalletPaymentSlot(panel, othersBehindTap: true),
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
    Widget panel,
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

  /// Where the payments of the bond and of the escrow stand, for « Cancel »: either being sent, or each sent (its funds may have left the wallet). The escrow's is read only where the page provides its cubit.
  static WalletBondState bondOf(BuildContext context) {
    final (bondSending, bondSent) = _stateOf(
      context.watch<BondPaymentCubit>().state.step,
    );
    final (escrowSending, escrowSent) = switch (context
        .watch<EscrowPaymentCubit?>()) {
      final escrow? => _stateOf(escrow.state.step),
      null => (false, false),
    };
    return WalletBondState(
      sending: bondSending || escrowSending,
      sent: bondSent,
      escrowSent: escrowSent,
    );
  }

  /// Whether a payment at [step] is being sent, and whether it is on its way.
  static (bool, bool) _stateOf(BondPayStep step) => switch (step) {
    BondPaySending() => (true, false),
    BondPayFollowing(:final progress) || BondPayPaidElsewhere(:final progress)
        when _onItsWay(progress) =>
      (false, true),
    BondPayUnreadable(paymentMayExist: true) => (false, true),
    _ => (false, false),
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
    final paid = widget.request.step;
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
              bondPayRefusalText(
                context,
                refused,
                coordinator: coordinator,
                step: paid,
              ),
              color: colors.error,
            )
          else if (notOffered != null)
            // Not offered for this invoice: why, in the panel's words.
            line(
              bondPayRefusalText(
                context,
                notOffered,
                coordinator: coordinator,
                step: paid,
              ),
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
        BondPayConfirming(:final walletQuote, :final rate) => [
          _Confirmation(
            walletQuote: walletQuote,
            rate: rate,
            coordinator: coordinator,
            request: widget.request,
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
              step: paid,
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

/// The confirmation: the invoice's amount, the swap fees, the network fee, the total and what stays, for an order made here how the bond compares with the wallet's own price (#180), the reference's sentence on a hold invoice, « Go back » and « Pay {total} sats », the only tap that pays.
class _Confirmation extends StatelessWidget {
  final P2pWalletQuote walletQuote;

  /// For an order made here, the bond quoted against the wallet's own price (the owner's payment rule of 2026-11-17): a line, and a red warning beyond the owner's threshold; `null` for a take, which shows none.
  final WalletRateCheck? rate;

  /// The trade's coordinator, named when the price of the creation is the reference.
  final String coordinator;
  final WalletPaymentRequest request;
  final GlobalKey payKey;
  final VoidCallback onCancel;
  final VoidCallback onPay;

  const _Confirmation({
    required this.walletQuote,
    required this.rate,
    required this.coordinator,
    required this.request,
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
    final escrow = request.step == InvoiceStep.escrow;
    final currency = request.currency;
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
                escrow
                    ? l10n.p2pPayEscrowConfirmTitle(sats(walletQuote.amount))
                    : l10n.p2pPayConfirmTitle(sats(walletQuote.amount)),
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
            // The owner's payment rule (#180): the bond against the wallet's own price, its gap shown, a red warning beyond the threshold; the user may still pay.
            if (rate case final rate?) ...[
              _RateLines(rate: rate, coordinator: coordinator),
              const Gap(BullSpacing.sm),
            ],
            // The escrow's facts (#97), the project's line: the whole trade stays with the swap service until it ends, and what a cancelled trade costs. Informed, not stopped.
            if (escrow) ...[
              Text(l10n.p2pPayEscrowHeld, style: body),
              const Gap(BullSpacing.sm),
            ],
            // The reference's sentence on a hold invoice, word for word (the owner's decision, #135): here while the confirmation is open, the other wallet's section (the escrow panel's own line) then not showing it.
            Text(
              escrow && currency != null
                  ? l10n.p2pTradeHoldInvoiceEscrow(currency.code)
                  : l10n.p2pTradeHoldInvoiceBond,
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

/// How the bond quoted compares with the sats expected (the owner's payment rule of 2026-11-17, #180): the reference's price and the bond it gives with the gap of the invoice, said weaker when the price is the coordinator's of the creation, and beyond the owner's threshold a red warning with both amounts; it stops nothing.
class _RateLines extends StatelessWidget {
  final WalletRateCheck rate;
  final String coordinator;

  const _RateLines({required this.rate, required this.coordinator});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final price = formats.price(rate.price);
    final code = rate.currency.code;
    final expected = formats.bigSats(rate.expected.value);
    final gap = formats.gap(rate.gapHundredths);
    final line = switch (rate.reference) {
      WalletRateReference.wallet => l10n.p2pPayRateWallet(
        price,
        code,
        expected,
        gap,
      ),
      WalletRateReference.createdNotPriced => l10n.p2pPayRateNotPriced(
        code,
        coordinator,
        price,
        expected,
        gap,
      ),
      WalletRateReference.createdUnreadable => l10n.p2pPayRateUnreadable(
        coordinator,
        price,
        code,
        expected,
        gap,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(line, style: text.bodyMedium?.copyWith(color: colors.text)),
        if (rate.warns) ...[
          const Gap(BullSpacing.sm),
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
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
                    l10n.p2pPayRateWarning(
                      formats.threshold(TradeTolerances.walletRateGap),
                      formats.bigSats(rate.asked.value),
                      expected,
                    ),
                    style: text.bodyMedium?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A line of the wallet's payment of the bond, which wraps at any text size and is read out when it changes.
///
/// [BondPaymentLine.new], after status 3: where the payment of a bond paid by this wallet stands, from the trade's [BondPaymentCubit]: nothing while the bond is locked ([bondHeld], the reference's bond line says it), « Your swap is in progress. » for a payment sent elsewhere, the refund, the bond kept or the review; nothing when the bond was not paid by this wallet, or nothing left the wallet.
class BondPaymentLine extends StatelessWidget {
  final String? _text;
  final Color? color;

  /// Whether the trade goes on after the bond's lock (status 6 until before its end): only then is the bond said locked. For the escrow, whether its lock is said by the reference's title (« The trade collateral is locked! », « Chat with the buyer »).
  final bool bondHeld;

  /// Whether the line is the escrow's (#97), from the trade's [EscrowPaymentCubit], rather than the bond's.
  final bool escrow;

  const BondPaymentLine({super.key, this.bondHeld = false, this.escrow = false})
    : _text = null,
      color = null;

  const BondPaymentLine.text(String this._text, {super.key, this.color})
    : bondHeld = false,
      escrow = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final BondPaymentCubit? cubit = _text != null
        ? null
        : escrow
        ? context.watch<EscrowPaymentCubit?>()
        : context.watch<BondPaymentCubit>();
    final line =
        _text ??
        switch (cubit?.state.step) {
          BondPayFollowing(:final progress) => bondPaymentAfterText(
            context,
            progress,
            bondHeld: bondHeld,
            coordinator: bondPaymentCoordinator(
              cubit?.record ?? (throw StateError('no cubit')),
            ),
            step: escrow ? InvoiceStep.escrow : InvoiceStep.bond,
            // Said whose payment it is: always for the escrow, and for the bond while a payment of the escrow is followed too, so that two lines are never the same (a buyer, who pays no escrow, sees the bond's line as before).
            named:
                escrow ||
                context.watch<EscrowPaymentCubit?>()?.state.step
                    is BondPayFollowing,
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
  InvoiceStep step = InvoiceStep.bond,
}) {
  final l10n = P2pLocalizations.of(context);
  final escrow = step == InvoiceStep.escrow;
  return switch (progress) {
    P2pWalletPaymentPreparing() => l10n.p2pPaySending,
    P2pWalletPaymentSigned() => l10n.p2pPayInterrupted,
    P2pWalletPaymentBroadcastUnknown() => l10n.p2pPayMaybeSent,
    P2pWalletPaymentSent() || P2pWalletPaymentPending() =>
      escrow
          ? l10n.p2pPayEscrowSent(coordinator)
          : l10n.p2pPaySent(coordinator),
    P2pWalletPaymentUnderReview() => l10n.p2pPayUnderReview,
    P2pWalletPaymentPaid() =>
      escrow
          ? l10n.p2pPayEscrowSettled(coordinator)
          : l10n.p2pPaySettled(coordinator),
    // At 3 the bond, or at 6 and 7 the escrow, was never locked: the invoice was not paid, and the payin is being refunded, or was.
    P2pWalletPaymentRefundPending() => l10n.p2pPayServiceCouldNotPay,
    P2pWalletPaymentRefunded() => l10n.p2pPayServiceRefunded,
    P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) ||
    P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) =>
      escrow
          ? l10n.p2pPayEscrowWalletUnavailable
          : l10n.p2pPayWalletUnavailable,
    P2pWalletPaymentExpired(:final funds) => _askSupport(
      l10n,
      escrow: escrow,
      expired: true,
      sent: funds == P2pWalletFunds.sent,
    ),
    P2pWalletPaymentFailed(:final funds) => _askSupport(
      l10n,
      escrow: escrow,
      expired: false,
      sent: funds == P2pWalletFunds.sent,
    ),
  };
}

/// What to tell of a swap that [expired] or failed while its funds left the wallet ([sent]) or may have.
String _askSupport(
  P2pLocalizations l10n, {
  required bool escrow,
  required bool expired,
  required bool sent,
}) => switch ((escrow, expired, sent)) {
  (false, true, true) => l10n.p2pPayAskSupportExpiredSent,
  (false, true, false) => l10n.p2pPayAskSupportExpired,
  (false, false, true) => l10n.p2pPayAskSupportSent,
  (false, false, false) => l10n.p2pPayAskSupport,
  (true, true, true) => l10n.p2pPayEscrowAskSupportExpiredSent,
  (true, true, false) => l10n.p2pPayEscrowAskSupportExpired,
  (true, false, true) => l10n.p2pPayEscrowAskSupportSent,
  (true, false, false) => l10n.p2pPayEscrowAskSupport,
};

/// What the line after status 3 says of a payment of the bond at [progress], `null` when nothing left the wallet: locked only when [bondHeld].
String? bondPaymentAfterText(
  BuildContext context,
  P2pWalletPaymentProgress progress, {
  required bool bondHeld,
  required String coordinator,
  InvoiceStep step = InvoiceStep.bond,
  bool named = false,
}) {
  final l10n = P2pLocalizations.of(context);
  final escrow = step == InvoiceStep.escrow;
  // The swap's words, which name no payment: prefixed with the payment's name when [named].
  String of(String line) => !named
      ? line
      : escrow
      ? l10n.p2pPayLineEscrow(line)
      : l10n.p2pPayLineBond(line);
  return switch (progress) {
    P2pWalletPaymentPreparing() || P2pWalletPaymentSigned() => null,
    P2pWalletPaymentBroadcastUnknown() => of(l10n.p2pPayMaybeSent),
    P2pWalletPaymentSent() || P2pWalletPaymentPending() =>
      // While the bond, or the escrow, is locked the reference's own line or title says so: nothing of ours is added (#135).
      bondHeld ? null : of(l10n.p2pPayWithSwapService),
    P2pWalletPaymentUnderReview() => of(l10n.p2pPayUnderReview),
    // An escrow charged is the trade's normal end, or a dispute's start: the reference's own texts say each.
    P2pWalletPaymentPaid() => escrow ? null : l10n.p2pPaySettled(coordinator),
    P2pWalletPaymentRefundPending() => of(l10n.p2pPayRefundPending),
    P2pWalletPaymentRefunded() => of(l10n.p2pPayRefunded),
    P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) ||
    P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) => null,
    P2pWalletPaymentExpired(:final funds) => _askSupport(
      l10n,
      escrow: escrow,
      expired: true,
      sent: funds == P2pWalletFunds.sent,
    ),
    P2pWalletPaymentFailed(:final funds) => _askSupport(
      l10n,
      escrow: escrow,
      expired: false,
      sent: funds == P2pWalletFunds.sent,
    ),
  };
}

/// Why the wallet did not quote or pay the bond, in the panel's words.
String bondPayRefusalText(
  BuildContext context,
  BondPayRefusal refusal, {
  required String coordinator,
  InvoiceStep step = InvoiceStep.bond,
}) {
  final unavailable = step == InvoiceStep.escrow
      ? P2pLocalizations.of(context).p2pPayEscrowWalletUnavailable
      : P2pLocalizations.of(context).p2pPayWalletUnavailable;
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  String sats(Sats amount) => formats.sats(amount.value.toInt());
  return switch (refusal) {
    BondPayNotAtBondStep() || BondPayInvoiceChanged() => l10n.p2pPayOrderMoved,
    BondPayNotOffered(reason: WalletPaymentRefusal.tooLate) =>
      l10n.p2pPayTooLate,
    BondPayTradeUnavailable() => l10n.p2pPayCoordinatorUnreachable(coordinator),
    BondPayReadSuperseded() => l10n.p2pPayReadSuperseded(coordinator),
    BondPayNotOffered() => unavailable,
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
      P2pWalletAnotherInvoiceWaiting() ||
      P2pWalletUnavailable() ||
      P2pWalletWrongNetwork() ||
      P2pWalletInvoiceUnreadable() ||
      P2pWalletServiceRefused() ||
      P2pWalletQuoteStale() => unavailable,
    },
  };
}
