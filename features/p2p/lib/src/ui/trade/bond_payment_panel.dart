import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../domain/trade/bond_payment.dart';
import '../../domain/trade/escrow_contract.dart';
import '../../domain/trade/shown_alerts.dart';
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
import 'escrow_contract_lines.dart';
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

  /// For the escrow, whether the order's bond was paid with this wallet ([paidHereOf] of the bond's payment): a maker seller's confirmation says it beside the alert of the earlier escrows, whose total leaves it out (#188, security review of #187, C5).
  final WalletPaidHere bondPaidHere;

  const BondPaymentPanel({
    super.key,
    required this.request,
    this.bondPaidHere = WalletPaidHere.no,
  });

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
    // The bond's payment, read here where the page's cubit of the bond is the one provided: a maker seller's confirmation says whether the order's bond was paid with this wallet (#188).
    final bondPaidHere = request.step == InvoiceStep.escrow
        ? paidHereOf(context.watch<BondPaymentCubit>().state.step)
        : WalletPaidHere.no;
    // The panel and its lines read the cubit of the request's step.
    final panel = BlocProvider<BondPaymentCubit>.value(
      value: cubit,
      child: BondPaymentPanel(request: request, bondPaidHere: bondPaidHere),
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

  /// Where the payments of the bond and of the escrow stand, for « Cancel »: either being sent, or each sent (its funds may have left the wallet); and whether each was paid with this wallet, for the line under a bond or collateral returned (#207). The escrow's is read only where the page provides its cubit.
  static WalletBondState bondOf(BuildContext context) {
    final bond = context.watch<BondPaymentCubit>().state.step;
    final escrow = context.watch<EscrowPaymentCubit?>()?.state.step;
    final (bondSending, bondSent) = _stateOf(bond);
    final (escrowSending, escrowSent) = escrow == null
        ? (false, false)
        : _stateOf(escrow);
    return WalletBondState(
      sending: bondSending || escrowSending,
      sent: bondSent,
      escrowSent: escrowSent,
      bondPaid: paidHereOf(bond),
      escrowPaid: escrow == null ? WalletPaidHere.no : paidHereOf(escrow),
    );
  }

  /// Whether the payment at [step] says the invoice was paid with this wallet ([WalletPaidHere]), for the line under a bond or collateral returned (#207).
  @visibleForTesting
  static WalletPaidHere paidHereOf(BondPayStep step) => switch (step) {
    BondPayFollowing(:final progress) ||
    BondPayPaidElsewhere(:final progress) => switch (progress) {
      // The only states the port establishes as this wallet's swap paying the invoice: « pending », a hold invoice the coordinator holds, and « paid », one settled (`p2p_wallet_port.dart`).
      P2pWalletPaymentPending() || P2pWalletPaymentPaid() => WalletPaidHere.yes,
      // Funds that may have left without the invoice established as paid by them: sent but not yet received by the service (the bond perhaps locked by another wallet meanwhile, security review of #208, R1), a broadcast not known, a review, an expiry or failure after sending, a refund (which does not tell a hold invoice cancelled after its lock from the service failing to pay it, functional review of #208, C1).
      _ when progress.fundsMayHaveLeft => WalletPaidHere.cannotTell,
      _ => WalletPaidHere.no,
    },
    BondPayUnreadable() || BondPaySending() => WalletPaidHere.cannotTell,
    BondPayLooking() ||
    BondPayIdle() ||
    BondPayQuoting() ||
    BondPayConfirming() => WalletPaidHere.no,
  };

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
        // A maker seller's escrow (#188): its own confirmation, with the contract it states.
        final BondPayConfirming confirming &&
            BondPayConfirming(contract: final contract?) =>
          [
            _EscrowConfirmation(
              confirming: confirming,
              contract: contract,
              bondPaidHere: widget.bondPaidHere,
              onRetry: () => unawaited(cubit.retryRate()),
              coordinator: coordinator,
              request: widget.request,
              payKey: _payKey,
              onCancel: cubit.dismiss,
              onPay: () => unawaited(cubit.confirm(shown: confirming)),
            ),
          ],
        BondPayConfirming(:final walletQuote, :final rate, :final retrying) => [
          _Confirmation(
            walletQuote: walletQuote,
            rate: rate,
            retrying: retrying,
            onRetry: () => unawaited(cubit.retryRate()),
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

/// The confirmation: the invoice's amount, the swap fees, the network fee, the total and what stays, how the bond or the escrow compares with the wallet's own price (for the maker bond, #180; for a taker's bond and a taker seller's escrow, #249), the reference's sentence on a hold invoice, « Go back » and « Pay {total} sats », the only tap that pays.
class _Confirmation extends StatelessWidget {
  final P2pWalletQuote walletQuote;

  /// The bond or the escrow quoted against the wallet's own price (the owner's payment rule of 2026-11-17, for the maker bond and, since #249, for a take): a line, and a red warning beyond the owner's threshold; `null` where nothing is compared.
  final WalletRateCheck? rate;

  /// The trade's coordinator, named when the wallet has no price for the order's currency and the user trusts the coordinator's.
  final String coordinator;
  final WalletPaymentRequest request;
  final GlobalKey payKey;
  final VoidCallback onCancel;
  final VoidCallback onPay;

  /// Whether the wallet's price is being read again, and how to ask it again when it could not be read.
  final bool retrying;
  final VoidCallback onRetry;

  const _Confirmation({
    required this.walletQuote,
    required this.rate,
    required this.coordinator,
    required this.request,
    required this.payKey,
    required this.onCancel,
    required this.onPay,
    required this.retrying,
    required this.onRetry,
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
            // The owner's payment rule (#180; for a take, #249): the bond or the escrow against the wallet's own price, its gap shown, a red warning beyond the threshold; the user may still pay. Beside an alert the screen shows (`ShownAlerts`: the state machine's, the trace of terms shown otherwise), only a comparison within the threshold is left out; a red one, « rate not checked » and « not priced » stay, an alert never silencing another (security review of #249, C1, C5): the confirmation stays open, and « Pay » with it, when a read brings an alert.
            if (rate case final rate?
                when !ShownAlerts.reassuresBeside(request.seen, rate)) ...[
              _RateLines(
                rate: rate,
                coordinator: coordinator,
                retrying: retrying,
                onRetry: onRetry,
                escrow: escrow,
              ),
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

/// The confirmation of a maker seller's escrow (#188), one idea per block, from the top: the title (« Pay {amount} sats to lock the collateral? »); when asked again, why ([BondPayConfirmAgain]); when the order was taken again meanwhile, that this confirmation pays nothing; that this is a new contract, from the order's second take on; the sats, aligned (the invoice, the swap fees, the network fee, the total that leaves this wallet, what stays); the comparison with the Bull wallet's price (the owner's payment rule of 2026-11-17: the contract's amount at that price with the order's premium, the gap including the coordinator's fee, red beyond the threshold), and without a comparison the gap from the rate at the creation; the swap service's facts; the reference's sentence on the escrow's hold invoice; then, in red just above the buttons, the earlier escrows of the order not back yet with the total out, those the coordinator kept, and the order's bond when this wallet paid it (the owner's decision of 2026-11-19: an alert, never a lock); « Go back » and « Pay {total} sats », the only tap that pays, given the confirmation it was drawn for.
///
/// Everything stated is from the quote this « Pay » pays and the contract built from that very quote ([EscrowContract.escrow] is its total). Nothing blocks the payment but a stale confirmation, whose « Pay » would pay nothing ([BondPayContractNotConfirmed]).
class _EscrowConfirmation extends StatelessWidget {
  final BondPayConfirming confirming;
  final EscrowContract contract;
  final WalletPaidHere bondPaidHere;
  final String coordinator;
  final WalletPaymentRequest request;
  final GlobalKey payKey;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onRetry;

  const _EscrowConfirmation({
    required this.confirming,
    required this.contract,
    required this.bondPaidHere,
    required this.coordinator,
    required this.request,
    required this.payKey,
    required this.onCancel,
    required this.onPay,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String sats(Sats amount) =>
        l10n.p2pAmountSats(formats.bigSats(amount.value));
    final walletQuote = confirming.walletQuote;
    final body = text.bodyMedium?.copyWith(color: colors.text);
    final currency = request.currency;
    final seen = request.seen;
    final rate = confirming.rate;
    // The contract's amount the comparison was made for, as asked here (the trail's, `WalletRateCheck.ofMakerEscrow`), never the amount of a read: the line names it even while the order read shows another, when the line is itself an alert (functional review of #188, C1; security review of #249, C5: an alert never silences another).

    // The alerts of this confirmation itself (earlier escrows not back or kept, the order's bond held too, a confirmation stale or asked again): beside them, as beside an alert of the screen (`ShownAlerts`), no comparison within the threshold is drawn (security review of #249, C1).
    final earlierAlerts = [
      ...earlierEscrowAlerts(context, contract, coordinator: coordinator),
      // The order's bond, which the alert's total leaves out (security review of #187, C5): beside the alert of the escrows not back.
      if (contract.notBack.isNotEmpty)
        ?switch (bondPaidHere) {
          WalletPaidHere.yes => l10n.p2pPayEscrowBondHeldToo,
          WalletPaidHere.cannotTell => l10n.p2pPayEscrowBondMaybeHeldToo,
          WalletPaidHere.no => null,
        },
    ];
    final besideOwnAlert =
        earlierAlerts.isNotEmpty || confirming.stale || confirming.again;
    // The comparison with the Bull wallet's price: in place, beside the amounts, within the threshold; beyond it, the line and its warning one red alert with the others above the buttons (functional review of #188, C2), never a neutral line beside it. A currency the Bull wallet does not price, or a price it could not read: its line alone, in the warning colour, with the alerts above the buttons (« Retry » for the latter), and no figure of the creation's price nor any gap from it (the owner's decisions of 2026-11-17; security review of #188, C1; R11).
    Widget? rateLines;
    final rateAlerts = <Widget>[];
    {
      switch (rate) {
        case null:
          break;
        // A maker seller's escrow check always carries its contract's amount (`WalletRateCheck.ofMakerEscrow`).
        case WalletRateCompared(amount: null):
          break;
        case WalletRateCompared(amount: final amount?) && final compared:
          final expected = formats.bigSats(compared.expected.value);
          final line = l10n.p2pPayRateWalletEscrow(
            formats.orderRate(compared.price),
            compared.currency.code,
            formats.amount(amount),
            expected,
            formats.gap(compared.gapHundredths),
          );
          if (compared.warns) {
            final warning = l10n.p2pPayRateWarningEscrow(
              formats.threshold(TradeTolerances.walletRateGap),
              formats.bigSats(compared.asked.value),
              expected,
            );
            rateAlerts.add(_AlertLine('$line $warning', color: colors.error));
          } else if (!ShownAlerts.reassuresBeside(
            seen,
            compared,
            besides: besideOwnAlert,
          )) {
            rateLines = Text(line, style: body);
          }
        case WalletRateNotPriced() || WalletRateUnverified():
          rateAlerts.add(
            _RateLines(
              rate: rate,
              coordinator: coordinator,
              retrying: confirming.retrying,
              onRetry: onRetry,
            ),
          );
      }
    }
    final alerts = <Widget>[
      ...rateAlerts,
      for (final alert in earlierAlerts) _AlertLine(alert, color: colors.error),
    ];
    final blocks = <Widget>[
      Semantics(
        container: true,
        header: true,
        liveRegion: true,
        child: Text(
          l10n.p2pPayEscrowConfirmTitle(
            formats.sats(walletQuote.amount.value.toInt()),
          ),
          style: text.headlineMedium?.copyWith(color: colors.text),
        ),
      ),
      if (confirming.stale)
        _AlertLine(l10n.p2pPayConfirmStale, color: colors.error)
      else if (confirming.again)
        _AlertLine(l10n.p2pPayConfirmAgain, color: colors.warning),
      if (contract.isNew)
        _InfoLine(l10n.p2pPayEscrowNewContract('${contract.take + 1}')),
      _AmountRows(
        rows: [
          (l10n.p2pPayRowCollateral, sats(walletQuote.amount), false),
          (l10n.p2pPayRowSwapFees, sats(walletQuote.serviceFee), false),
          (l10n.p2pPayRowNetworkFee, sats(walletQuote.networkFee), false),
          (l10n.p2pPayRowTotal, sats(walletQuote.total), true),
          (l10n.p2pPayRowLeft, sats(walletQuote.remaining), false),
        ],
      ),
      ?rateLines,
      Text(l10n.p2pPayEscrowHeld, style: body),
      // The reference's sentence on the escrow's hold invoice, word for word (#135).
      if (currency != null)
        Text(
          l10n.p2pTradeHoldInvoiceEscrow(currency.code),
          style: text.bodySmall?.copyWith(color: colors.textMuted),
        ),
      // The alerts together, just above the buttons: the price's first (red beyond the threshold, or the warning colour of a rate not checked), then the earlier escrows', then the bond's, in red (the owner's decision of 2026-11-19; functional review of #188, C2; security review, R11).
      if (alerts.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, alert) in alerts.indexed) ...[
              if (index > 0) const Gap(BullSpacing.sm),
              alert,
            ],
          ],
        ),
    ];
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
            for (final (index, block) in blocks.indexed) ...[
              if (index > 0) const Gap(BullSpacing.md),
              block,
            ],
            const Gap(BullSpacing.md),
            TradeButton(
              label: l10n.p2pCommonGoBack,
              outlined: true,
              onPressed: onCancel,
            ),
            const Gap(BullSpacing.sm),
            KeyedSubtree(
              key: payKey,
              child: TradeButton(
                label: l10n.p2pPayConfirm(
                  formats.sats(walletQuote.total.value.toInt()),
                ),
                // A confirmation of a contract the order moved on from pays nothing: not offered.
                onPressed: confirming.stale ? null : onPay,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rows of a label and an amount, the amounts aligned at the right in tabular figures; the [bold] one stands out (the total).
class _AmountRows extends StatelessWidget {
  final List<(String, String, bool)> rows;

  const _AmountRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value, bold) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: bold ? colors.text : colors.textMuted,
                        fontWeight: bold ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                  const Gap(BullSpacing.sm),
                  Text(
                    value,
                    textAlign: TextAlign.end,
                    style: text.bodyMedium?.copyWith(
                      color: colors.text,
                      fontWeight: bold ? FontWeight.bold : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A line of the confirmation with its icon, in [color], bold, read out when it appears: an alert.
class _AlertLine extends StatelessWidget {
  final String text;
  final Color color;

  const _AlertLine(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.warning_amber_rounded, size: 18, color: color),
        ),
        const Gap(BullSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A line of the confirmation with an information icon, in the text colour.
class _InfoLine extends StatelessWidget {
  final String text;

  const _InfoLine(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.info_outline, size: 18, color: colors.text),
        ),
        const Gap(BullSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.text),
          ),
        ),
      ],
    );
  }
}

/// How the bond quoted compares with the sats expected (the owner's payment rule of 2026-11-17, #180): the wallet's price and the bond it gives with the gap of the invoice, and beyond the owner's threshold a red warning with both amounts; for a taker seller's escrow ([escrow], #249), the escrow's words of a maker seller's confirmation, the amount taken and the sats it is worth, the coordinator's fee included in the gap (`p2pPayRateWalletEscrow`, `p2pPayRateWarningEscrow`). For a currency the wallet does not price, no figure at all: one line in the warning colour says that the rate is not checked and that the user trusts the coordinator's price, with no « Retry », since there is nothing to read again (the owner's decision of 2026-11-17 in the evening). When the wallet's price could not be read, nothing is compared and no price is cited: a line in the warning colour says « rate not checked » (the owner's decision of 2026-11-17), with « Retry », which reads the price again. It stops nothing: « Pay » stays offered.
class _RateLines extends StatelessWidget {
  final WalletRateCheck rate;
  final String coordinator;
  final bool retrying;
  final VoidCallback onRetry;

  /// Whether the amount compared is an escrow rather than a bond: the lines then take the escrow's words.
  final bool escrow;

  const _RateLines({
    required this.rate,
    required this.coordinator,
    required this.retrying,
    required this.onRetry,
    this.escrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final rate = this.rate;
    Widget alert(String line, Color color) => Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.warning_amber_rounded, size: 18, color: color),
          ),
          const Gap(BullSpacing.xs),
          Expanded(
            child: Text(
              line,
              style: text.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    switch (rate) {
      case WalletRateNotPriced(:final currency):
        return alert(
          l10n.p2pPayRateNotPriced(currency.code, coordinator),
          colors.warning,
        );
      case WalletRateUnverified(:final currency):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            alert(l10n.p2pPayRateUnverified(currency.code), colors.warning),
            const Gap(BullSpacing.sm),
            TradeButton(
              label: l10n.p2pCommonRetry,
              outlined: true,
              busy: retrying,
              onPressed: retrying ? null : onRetry,
            ),
          ],
        );
      case WalletRateCompared(
        :final currency,
        :final expected,
        :final gapHundredths,
        :final asked,
      ):
        final price = formats.orderRate(rate.price);
        final code = currency.code;
        final expectedText = formats.bigSats(expected.value);
        final gap = formats.gap(gapHundredths);
        final threshold = formats.threshold(TradeTolerances.walletRateGap);
        final askedText = formats.bigSats(asked.value);
        final amount = rate.amount;
        // An escrow's line names the amount whose sats are expected; an escrow check always carries it (`WalletRateCheck.ofTakerEscrow`).
        if (escrow && amount == null) return const SizedBox.shrink();
        final line = escrow && amount != null
            ? l10n.p2pPayRateWalletEscrow(
                price,
                code,
                formats.amount(amount),
                expectedText,
                gap,
              )
            : l10n.p2pPayRateWallet(price, code, expectedText, gap);
        // An escrow beyond the threshold: the line and its warning one red alert, never a neutral line beside it, as a maker seller's escrow confirmation draws them (functional review of #188, C2).
        if (escrow && rate.warns) {
          final warning = l10n.p2pPayRateWarningEscrow(
            threshold,
            askedText,
            expectedText,
          );
          return alert('$line $warning', colors.error);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(line, style: text.bodyMedium?.copyWith(color: colors.text)),
            if (rate.warns) ...[
              const Gap(BullSpacing.sm),
              alert(
                l10n.p2pPayRateWarning(threshold, askedText, expectedText),
                colors.error,
              ),
            ],
          ],
        );
    }
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
    // A maker seller's escrow (#187, #188): its confirmation always carries its contract, so a contract not confirmed is the order taken again since (security review of #187, R2).
    BondPayContractNotConfirmed() => l10n.p2pPayContractMoved,
    // Shown as the confirmation again by the cubit (#188); said so if ever left idle.
    BondPayConfirmAgain() => l10n.p2pPayConfirmAgain,
    BondPayEscrowSeenBefore() => l10n.p2pPayEscrowShownBefore,
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
