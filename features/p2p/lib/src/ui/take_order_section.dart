import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/taker_estimate.dart';
import '../domain/trade/make_price_check.dart';
import '../domain/trade/taken_price_check.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade/trade_tolerances.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import '../presentation/take_amount_input.dart';
import '../presentation/take_order_cubit.dart';
import '../presentation/trade_l10n.dart';
import 'order_details_screen.dart';
import 'widgets/amount_row.dart';
import 'widgets/detail_toggle.dart';
import 'widgets/garage_key_backup.dart';
import 'widgets/moved_tap_guard.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/price_check_lines.dart';
import 'widgets/store_token_dialog.dart';
import 'widgets/trade_button.dart';
import 'widgets/word_fit_text.dart';

/// « Take Order » at the foot of the order details, as the official client's take button (`components/OrderDetails/TakeButton.tsx` at commit ff1998c).
///
/// - A range order first asks its amount: « Amount {{currencyCode}} », « Too low » / « Too high » under the field, « Take Order » disabled with « You must specify an amount first » until the amount fits, then « You will receive {{satoshis}} Sats (Approx) » for a sell order, whose taker buys, or « You will send {{satoshis}} Sats (Approx) » for a buy order, whose taker sells (`TakeButton.tsx:289-292`: the same figure, only the words change).
/// - On press, the reference's order (#119, the owner's decision after the review of #133): « You do not have a Garage Key » without a key, else the take is prepared: the robot that will take the order reads it, while the button shows that it runs, a bar runs under it with a line that says each step (the order checked with the coordinator, the robot built, « Building your robot! » in the reference's words, the order read by the robot) and, after 30 s, that it still waits, as the robot panel of the Garage does.
/// - Once the order is read, the order details show that read ([TakeOrderDetailsCard]: the maker's description and the fresh figures, which the reference shows in « Order description » with « Go back » / « Continue »), and « Take Order » gives way to « Continue » and « Go back »; « Continue » sends the take (its wait says its steps too), at once for a robot of a key of the wallet's words, and for a robot of the external Garage Key through « Store your garage key » (#318), whose « Done » sends it and whose « Go back », or a tap outside, only closes it.
/// - « The order changed. » says, from its start, that a confirmation found the order changed and reads it again: the read the user saw stays shown meanwhile, the rows that differ are marked when the new one arrives, and it waits for « Continue » and « Done » again, never confirmed by itself. When the take was sent, [onTaken] opens its trade, the read shown until then. It is said too, with no stop, while a read of an order priced in sats shows a premium moved from the one shown before « Take Order », the row « Price and premium » marked ([TakenPriceCheck.premiumMovedFrom], #270), so that the mark is not a colour only.
/// - An order found gone is said so, and « Take Order » stays disabled.
/// - A take that did not happen says why under the button, as the reference shows the coordinator's message there, in words of the app.
/// - A password-protected order reached by its URL (#245, `TakeOrderCubit.unlisted` with `UnlistedOrder.hasPassword`; an order without a password reached so has no field): « Password » above the button, as the reference puts it above its take button (`components/OrderDetails/index.tsx:546-571`), typed hidden, with a short line above it that its description and location come with the take; its text stays in this field, and « Done » hands the cubit its hash only ([OrderPassword]); « Take Order » or « Continue » pressed with the field empty starts nothing and says so under the button, where the reference would send the take and be refused (error 1045); a wrong password is said there with the coordinator's message (« Wrong password », `api/errors.py:52`), the field kept to be corrected.
/// - The owner's payment rule before the take (#249, slice 4): « Continue » pressed while the Bull wallet's price is read waits for it, the button busy, then stops once, with « This page has changed » over it, when the order details now show a line of the comparison they did not show at the press (the red alert, « Price not checked » or « not quoted »), never when they show nothing new, as « Create order » stops (`MakePriceVerdict.stopsPressFor`); a press again goes on. « Continue » is never refused for what the comparison says, and a tap on it just after the comparison moved it is ignored for a moment ([MovedTapGuard]).
///
/// Without [canTake] (the feature was set up without the vault's handle, so it holds no robot) a press shows « You do not have a Garage Key », as the reference does without a robot.
class TakeOrderSection extends StatefulWidget {
  final PublicOrder order;

  /// The taker fee the coordinator announces, 0 while it is not known, as the reference counts it (`info?.taker_fee ?? 0`).
  final double takerFee;
  final bool canTake;
  final VoidCallback? onOpenGarage;
  final ValueChanged<TradeRecord> onTaken;

  const TakeOrderSection({
    super.key,
    required this.order,
    required this.takerFee,
    required this.canTake,
    required this.onOpenGarage,
    required this.onTaken,
  });

  /// « Continue », once the read is shown.
  static const continueButton = ValueKey('take-continue');

  /// « This page has changed » over « Continue ».
  static const pageChangedBlock = ValueKey('take-page-changed');

  @override
  State<TakeOrderSection> createState() => _TakeOrderSectionState();
}

class _TakeOrderSectionState extends State<TakeOrderSection> {
  final _amount = TextEditingController();

  /// « Password » of a protected order (#245): its text lives here only.
  final _password = TextEditingController();

  /// Whether « Take Order » or « Continue » was pressed with « Password » empty: said under the button until the field changes.
  bool _passwordMissing = false;

  /// Whether a dialog of the take is open: a second press meanwhile opens nothing more.
  bool _asking = false;

  /// Whether « Continue » waits for the Bull wallet's price being read (#249).
  bool _waitingPrice = false;

  /// The read for which « Continue » stopped because the order details came to show a line of the comparison while it waited: « This page has changed » is said while that read is shown.
  PreparedTake? _stoppedFor;

  @override
  void dispose() {
    _amount.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Whether the order is protected by a password (#245).
  bool get _protected =>
      widget.canTake &&
      (context.read<TakeOrderCubit>().unlisted?.hasPassword ?? false);

  /// For a protected order, whether « Password » holds a password; otherwise says so under the button and starts nothing.
  bool _passwordGiven() {
    if (!_protected || _password.text.isNotEmpty) return true;
    setState(() => _passwordMissing = true);
    return false;
  }

  /// « You do not have a Garage Key » ([NoRobotDialog], a dialog's content since #121) in a dialog.
  Future<void> _showNoRobot() => BullDialog.show<void>(
    context: context,
    builder: (_) => NoRobotDialog(onOpenGarage: widget.onOpenGarage),
  );

  /// « Take Order »: without a Garage Key « You do not have a Garage Key », else the take is prepared, the robot that will take the order reading it.
  ///
  /// The amount field is locked from the press, and the amount is read from it just before the preparation starts, which locks it for good: the amount prepared is the one shown (security review of #133).
  Future<void> _press() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      if (!widget.canTake) {
        await _showNoRobot();
        return;
      }
      if (!_passwordGiven()) return;
      final cubit = context.read<TakeOrderCubit>();
      if (!await cubit.hasGarageKey()) {
        if (!mounted) return;
        await _showNoRobot();
        return;
      }
      if (!mounted) return;
      final order = widget.order;
      final TakeAmount? amount;
      if (order.amount is RangeOrderAmount) {
        if (TakeAmountInput.read(_amount.text, order) case TakeAmountValid(
          amount: final valid,
        )) {
          amount = valid;
        } else {
          return;
        }
      } else {
        amount = null;
      }
      unawaited(cubit.take(amount: amount));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// « Continue »: for a robot of the external Garage Key, « Store your garage key », whose « Done » sends the take; for a robot of a key of the wallet's words, the take at once (#318). The dialog's « Go back », or a tap outside, only closes it, as the reference's does (`TakeButton.tsx:380-382`): the order as read stays on the page with its take prepared, and « Go back » of the page is what abandons it.
  ///
  /// For a protected order, nothing opens while « Password » is empty; « Done » hands the cubit the hash of the password the field holds then (#245).
  ///
  /// Pressed while the Bull wallet's price is read for the read shown (#249), it waits for that read, then stops once, saying « This page has changed », when the order details now show a line of the comparison they did not show at the press; it goes on when they show nothing, or the line they showed (« Price not checked » read again and still not checked). A press again goes on.
  Future<void> _continue() async {
    if (_asking) return;
    if (!_passwordGiven()) return;
    _asking = true;
    try {
      final cubit = context.read<TakeOrderCubit>();
      final atPress = cubit.state;
      if (atPress is! TakeReady) return;
      if (_stoppedFor != null) setState(() => _stoppedFor = null);
      if (atPress.price is TakePriceReading) {
        final shown = cubit.priceShown;
        setState(() => _waitingPrice = true);
        try {
          await cubit.priceSettled();
        } finally {
          // Even if the wait itself ever threw: « Continue » never stays busy for good (security review of #249's slice 4, R3). A read of the price that throws is caught and reported by the cubit since #270, and settles as « Price not checked ».
          if (mounted) setState(() => _waitingPrice = false);
        }
        if (!mounted) return;
        final now = cubit.state;
        // Gone back, or the read moved on meanwhile: nothing goes on.
        if (now is! TakeReady || !identical(now.prepared, atPress.prepared)) {
          return;
        }
        // A line the press was not made on: the red alert, « Price not checked » or « not quoted ». Nothing shown now is nothing new to read.
        final after = cubit.priceShown;
        if (after != TakenPriceShown.nothing && after != shown) {
          setState(() => _stoppedFor = now.prepared);
          return;
        }
      }
      if (!mounted) return;
      // « Store your garage key » only when the robot of the take is of the external Garage Key, which nothing else backs up (#318, decided on 2026-11-28): with a key of the wallet's words, which comes back with the words, the take is sent at once.
      final prepared = atPress.prepared;
      if (prepared.externalKey) {
        final done = await StoreTokenDialog.show(
          context,
          copy: GarageKeyBackupScope.of(context)?.ofTake(prepared),
        );
        if (!mounted || !done) return;
      }
      if (!_protected) {
        unawaited(cubit.confirm());
      } else if (OrderPassword.tryCreate(_password.text) case final password?) {
        unawaited(cubit.confirm(password: password));
      } else {
        setState(() => _passwordMissing = true);
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final order = widget.order;
    final state = widget.canTake
        ? context.watch<TakeOrderCubit>().state
        : const TakeIdle();
    final isRange = order.amount is RangeOrderAmount;
    final input = isRange
        ? TakeAmountInput.read(_amount.text, order)
        : const TakeAmountEmpty();
    final ready = !isRange || input is TakeAmountValid;
    final cubit = widget.canTake ? context.read<TakeOrderCubit>() : null;
    final protected = cubit?.unlisted?.hasPassword ?? false;
    final wrongPassword = switch (state) {
      TakeIdle(problem: TakeWasNotMade(refusal: OrderWrongPassword())) => true,
      _ => false,
    };
    final above = <Widget>[
      if (protected)
        _PasswordField(
          controller: _password,
          enabled: state is TakeIdle || state is TakeReady,
          error: _passwordMissing || wrongPassword,
          onChanged: () {
            if (_passwordMissing) setState(() => _passwordMissing = false);
          },
        ),
    ];
    // The read the order details show: while it is there, « Continue » and « Go back » stand in place of « Take Order », down to the trade's screen.
    final read = TakeOrderDetailsCard.readOf(state);
    // The order found changed at a confirmation, or, for an order priced in sats, its premium read moved from the one the page showed before « Take Order », which marks « Price and premium » (#249): said in words too, once (#270).
    final changed = switch (state) {
      TakePreparing(changed: true) => true,
      TakeReady(changed: true) => true,
      _ =>
        read != null &&
            TakenPriceCheck.premiumMovedFrom(read.terms, order.premium),
    };
    final stopped = switch (state) {
      TakeReady(:final prepared) => identical(prepared, _stoppedFor),
      _ => false,
    };
    final Widget button = read != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (changed) ...[
                _Line(l10n.p2pTakeOrderChangedRead, live: true),
                const Gap(BullSpacing.xs),
              ],
              if (stopped) ...[
                const _PageChanged(key: TakeOrderSection.pageChangedBlock),
                const Gap(BullSpacing.xs),
              ],
              // A tap aimed at what stood here before the comparison's line came or went is ignored for a moment (#249); « Continue » stays enabled and goes on at the next tap.
              MovedTapGuard(
                key: TakeOrderSection.continueButton,
                // Shown once the read the user waited for has come, where « Take Order » stood busy and took the taps meanwhile: no delay when it appears, nor when it is shown again from under a dialog (security review of #291, B1; #294). A tap repeated after the read can reach it at some sizes (320 × 640, text ×3; second security pass of #291), which opens « Store your garage key » for the external Garage Key and, since #318, sends the take for a key of the wallet's words: no money moves at that tap (the bond is paid at its own step; a take cancelled before the bond costs no money, the coordinator giving the taker's robot, used for that take only, a short wait, `PENALTY_TIMEOUT` of the reference).
                armsWhenShown: false,
                builder: (context, guard) => TradeButton(
                  label: l10n.p2pCommonContinue,
                  busy: state is! TakeReady || _waitingPrice,
                  onPressed: guard(() => unawaited(_continue())),
                ),
              ),
              const Gap(BullSpacing.sm),
              TradeButton(
                label: l10n.p2pCommonGoBack,
                outlined: true,
                onPressed: state is TakeReady ? () => cubit?.back() : null,
              ),
            ],
          )
        : TradeButton(
            label: l10n.p2pTakeOrder,
            busy: state is TakePreparing || state is TakeSent,
            onPressed: ready && !(state is TakeIdle && state.orderGone)
                ? () => unawaited(_press())
                : null,
          );
    final coordinator = CoordinatorText.of(
      order.coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    final (bool running, bool slow, TakeStep? step) = switch (state) {
      TakePreparing(:final slow, :final step) => (true, slow, step),
      TakeConfirming(:final slow, :final step) => (true, slow, step),
      _ => (false, false, null),
    };
    final under = <Widget>[
      if (running) ...[
        // What a screen reader says of the step while it runs: the button pressed, in progress.
        Semantics(
          container: true,
          liveRegion: true,
          child: LinearProgressIndicator(
            color: context.bull.primary,
            semanticsLabel: read == null
                ? l10n.p2pTakeOrder
                : l10n.p2pCommonContinue,
          ),
        ),
        // What the step that runs is doing, read out when it changes.
        if (step != null)
          _Line(step.toText(context, coordinator: coordinator), live: true),
        if (slow) _Line(l10n.p2pRobotStillWaiting(coordinator), live: true),
      ],
      if (protected && _passwordMissing)
        _Line(
          l10n.p2pTakePasswordMissing,
          color: context.bull.error,
          live: true,
        )
      else if (state case TakeIdle(:final problem?))
        _Line(
          problem.toText(context, coordinator: coordinator),
          color: context.bull.error,
          live: true,
        ),
    ];
    final content = isRange
        ? _RangeTake(
            leading: above,
            order: order,
            read: read,
            controller: _amount,
            input: input,
            takerFee: widget.takerFee,
            enabled: state is TakeIdle && !_asking,
            onChanged: () => setState(() {}),
            button: ready
                ? button
                : Tooltip(
                    message: l10n.p2pTakeSpecifyAmountFirst,
                    // Opened by a tap, as the reference opens it on touch (`enterTouchDelay={0}`).
                    triggerMode: TooltipTriggerMode.tap,
                    child: button,
                  ),
            under: under,
          )
        : _Column(above: above, button: button, under: under);
    if (!widget.canTake) return content;
    return BlocListener<TakeOrderCubit, TakeOrderState>(
      listenWhen: (_, current) => current is TakeSent,
      listener: (_, state) {
        if (state is TakeSent) widget.onTaken(state.record);
      },
      child: content,
    );
  }
}

/// [PublicOrderDetailsCard] of the order, with the robot's read once the take is prepared (#119): with [canTake], a `TakeOrderCubit` is above it, the one of the [TakeOrderSection] under it.
///
/// The read is shown from its arrival to the trade's screen, and stays shown while the order is read again because it changed, the rows that differ marked once the new read arrives; the card is scrolled into view when a read arrives, so that its description and figures are seen before « Continue ».
///
/// Under « Price and premium » of a read, the owner's payment rule before the take (#249, slice 4, option B decided by the owner on 2026-11-24, the alert only; [TakenPriceShown]): nothing while the coordinator's price, without the premium, is within the threshold of the Bull wallet's or while it is read; beyond it on the taker's side, the red alert in two lines; « Price not checked » in orange with « Retry » and its second line when the Bull wallet's price could not be read; the explanation of either behind « Show details » under its lines (#270); the grey « not quoted » line for a currency the Bull wallet does not price.
class TakeOrderDetailsCard extends StatelessWidget {
  final PublicOrder order;
  final TakerEstimate? estimate;
  final DateTime now;
  final bool canTake;

  const TakeOrderDetailsCard({
    super.key,
    required this.order,
    required this.estimate,
    required this.now,
    required this.canTake,
  });

  /// The comparison's lines under « Price and premium », when there are any.
  static const priceAlert = ValueKey('take-price-alert');

  /// « Show details » / « Hide details » of the alert's explanation, just under its lines (#270).
  static const priceDetailToggle = ValueKey('take-price-detail-toggle');

  /// The read of [state] the order details show, if any.
  static PreparedTake? readOf(TakeOrderState state) => switch (state) {
    TakeReady(:final prepared) || TakeConfirming(:final prepared) => prepared,
    TakePreparing(:final previous) => previous,
    TakeSent(:final prepared) => prepared,
    TakeIdle() => null,
  };

  @override
  Widget build(BuildContext context) {
    if (!canTake) {
      return PublicOrderDetailsCard(order: order, estimate: estimate, now: now);
    }
    final state = context.watch<TakeOrderCubit>().state;
    final read = readOf(state);
    final shown = read == null
        ? TakenPriceShown.nothing
        : TakenPriceCheck.shownOf(state.price.shownCheck, read.terms.role);
    return BlocListener<TakeOrderCubit, TakeOrderState>(
      // A read that arrives, not its comparison: the page is not scrolled again when an alert comes.
      listenWhen: (previous, current) =>
          current is TakeReady &&
          !(previous is TakeReady &&
              identical(previous.prepared, current.prepared)),
      listener: (context, _) => unawaited(
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
        ),
      ),
      child: PublicOrderDetailsCard(
        order: order,
        estimate: estimate,
        now: now,
        read: read,
        previous: switch (state) {
          TakeReady(:final previous) => previous,
          _ => null,
        },
        priceAlert: read == null || shown == TakenPriceShown.nothing
            ? null
            : _TakePriceLines(
                key: priceAlert,
                shown: shown,
                check: state.price.shownCheck,
                currency: read.terms.currency.code,
                retrying:
                    state is! TakeReady || state.price is TakePriceReading,
              ),
      ),
    );
  }
}

/// The comparison of the read's price with the Bull wallet's, when it says something ([TakenPriceShown] other than nothing), in the lines of #250 ([PriceCheckLines]) with the order page's own bold lines; never a reassuring line.
///
/// The alert's lines are drawn without a tap: the bold line and the two prices of the red alert, the bold line with « Retry » and its second line of « Price not checked ». Its explanation is behind « Show details » just under them, in the same frame, opening under the link as in the invoice's breakdown (the owner's decision of 2026-11-25, #270); the grey « not quoted » line has none, and no link. A new alert arrives folded, and the detail never opens by itself.
class _TakePriceLines extends StatefulWidget {
  final TakenPriceShown shown;
  final MakePriceCheck? check;
  final String currency;

  /// Whether « Retry » is shown but not offered: the price read again, or « Continue » moved on.
  final bool retrying;

  const _TakePriceLines({
    super.key,
    required this.shown,
    required this.check,
    required this.currency,
    required this.retrying,
  });

  @override
  State<_TakePriceLines> createState() => _TakePriceLinesState();
}

class _TakePriceLinesState extends State<_TakePriceLines> {
  /// Whether the alert's explanation is shown; folded at first.
  var _open = false;

  @override
  void didUpdateWidget(covariant _TakePriceLines old) {
    super.didUpdateWidget(old);
    // A new alert arrives folded: another line, or a new comparison (a read compared anew, « Retry » answered). The same comparison, still drawn while « Retry » reads again, keeps its detail as the user left it.
    if (old.shown != widget.shown || !identical(old.check, widget.check)) {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final colors = context.bull;
    final check = widget.check;
    final shown = widget.shown;
    final (Widget lines, String? explanation, Color tone) = switch (shown) {
      TakenPriceShown.against ||
      TakenPriceShown.farBelow when check is MakePriceCompared => (
        PriceCheckLines.against(
          formats.gap(check.gapHundredths),
          label: shown == TakenPriceShown.farBelow
              ? l10n.p2pTakePriceFarBelow
              : l10n.p2pTakePriceAgainst,
          figures: l10n.p2pTakePriceFigures(
            formats.orderRate(check.walletPrice),
            widget.currency,
            formats.orderRate(check.coordinatorPrice),
          ),
        ),
        l10n.p2pTakePriceDetail(
          formats.threshold(TradeTolerances.walletRateGap),
        ),
        colors.error,
      ),
      TakenPriceShown.unverified => (
        PriceCheckLines.unverified(
          label: l10n.p2pTakePriceUnverified,
          retrying: widget.retrying,
          onRetry: () => unawaited(context.read<TakeOrderCubit>().retryPrice()),
        ),
        l10n.p2pTakePriceUnverifiedDetail,
        colors.warning,
      ),
      TakenPriceShown.notPriced => (
        const PriceCheckLines.notPriced(),
        null,
        colors.textMuted,
      ),
      TakenPriceShown.against ||
      TakenPriceShown.farBelow ||
      TakenPriceShown.nothing => (
        const SizedBox.shrink(),
        null,
        colors.textMuted,
      ),
    };
    if (explanation == null) return lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        lines,
        // One node for a screen reader, the button with its state: « Show details » folded, « Hide details » open.
        MergeSemantics(
          child: Semantics(
            expanded: _open,
            child: DetailToggle(
              key: TakeOrderDetailsCard.priceDetailToggle,
              open: _open,
              onPressed: () => setState(() => _open = !_open),
            ),
          ),
        ),
        if (_open)
          Semantics(
            container: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: BullSpacing.xxs / 2),
              child: WordFitText(
                explanation,
                key: PriceCheckLines.explanationLine,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tone),
              ),
            ),
          ),
      ],
    );
  }
}

/// « This page has changed » over « Continue », in orange, on the model of « The amounts have changed » (#250): « Continue » stopped once because a line of the comparison came while it waited for it (#249).
class _PageChanged extends StatelessWidget {
  const _PageChanged({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountRow(
            label: l10n.p2pTakePageChangedTitle,
            tone: AmountRowTone.warning,
          ),
          WordFitText(
            l10n.p2pTakePageChangedLine,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.warning),
          ),
        ],
      ),
    );
  }
}

/// [OrderFeeRow] of the order's coordinator, with the taker fee of the terms once the take is prepared (#119): the fee the take is checked against (security review of #133).
class TakeOrderFeeRow extends StatelessWidget {
  final CoordinatorInfo? info;
  final bool canTake;

  const TakeOrderFeeRow({super.key, required this.info, required this.canTake});

  @override
  Widget build(BuildContext context) {
    final state = canTake ? context.watch<TakeOrderCubit>().state : null;
    final read = state == null ? null : TakeOrderDetailsCard.readOf(state);
    final before = switch (state) {
      TakeReady(:final previous) => previous,
      _ => null,
    };
    return OrderFeeRow(
      info: info,
      takerFee: read?.terms.takerFee,
      takerFeeChanged:
          read != null &&
          before != null &&
          before.terms.takerFee != read.terms.takerFee,
    );
  }
}

/// [OrderMakerRow] of the order, with the maker and its activity as the robot's read gives them once the take is prepared (#119).
class TakeOrderMakerRow extends StatelessWidget {
  final PublicOrder order;
  final bool canTake;

  const TakeOrderMakerRow({
    super.key,
    required this.order,
    required this.canTake,
  });

  @override
  Widget build(BuildContext context) {
    final read = canTake
        ? TakeOrderDetailsCard.readOf(context.watch<TakeOrderCubit>().state)
        : null;
    return OrderMakerRow(
      maker: read?.order.maker ?? order.maker,
      activity: read?.order.makerActivity ?? order.makerActivity,
    );
  }
}

/// The amount field of a range order, its estimate under it, then the button.
class _RangeTake extends StatelessWidget {
  /// What comes above the amount: « Password » of a protected order (#245).
  final List<Widget> leading;
  final PublicOrder order;

  /// The robot's read, once the take is prepared: the estimate under the amount is its own.
  final PreparedTake? read;
  final TextEditingController controller;
  final TakeAmountInput input;
  final double takerFee;
  final bool enabled;
  final VoidCallback onChanged;
  final Widget button;
  final List<Widget> under;

  const _RangeTake({
    required this.leading,
    required this.order,
    required this.read,
    required this.controller,
    required this.input,
    required this.takerFee,
    required this.enabled,
    required this.onChanged,
    required this.button,
    required this.under,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final code = order.currency.isBitcoin
        ? l10n.p2pSatsUnit
        : order.currency.code;
    final error = switch (input) {
      TakeAmountTooLow() => l10n.p2pTakeTooLow,
      TakeAmountTooHigh() => l10n.p2pTakeTooHigh,
      _ => null,
    };
    final read = this.read;
    final prepared = read?.amount;
    final sats = switch (input) {
      // Once read, the amount prepared at the read's rate, with its terms' taker fee: what the take sends.
      _ when read != null && prepared != null => TakerEstimate.takeSatsOfRead(
        read.order,
        prepared.amount.value,
        takerFee: read.terms.takerFee,
      ),
      TakeAmountValid(:final value) => TakerEstimate.takeSats(
        order,
        value,
        takerFee: takerFee,
      ),
      _ => null,
    };
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      borderSide: BorderSide(color: color),
    );
    final edge = error == null ? colors.outline : colors.error;
    return _Column(
      above: [
        ...leading,
        // The label above the field rather than inside its border: a floating label is kept on one line, which three times the text size would cut on a phone of 320 points.
        // A screen reader hears it as the field's label.
        ExcludeSemantics(
          child: Text(
            l10n.p2pTakeAmountLabel(code),
            style: text.labelLarge?.copyWith(
              color: error == null ? colors.textMuted : colors.error,
            ),
          ),
        ),
        Tooltip(
          message: l10n.p2pTakeAmountHint,
          child: Semantics(
            container: true,
            label: l10n.p2pTakeAmountLabel(code),
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // An amount, not words: no suggestion, correction or learning by the keyboard.
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(20),
              ],
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: colors.text),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                errorText: error,
                errorMaxLines: 3,
                filled: true,
                fillColor: colors.surface,
                enabledBorder: border(edge),
                focusedBorder: border(error == null ? colors.primary : edge),
                errorBorder: border(colors.error),
                focusedErrorBorder: border(colors.error),
              ),
            ),
          ),
        ),
      ],
      button: button,
      under: [
        if (sats != null && sats != 0)
          _Line(
            order.type == OrderType.buy
                ? l10n.p2pTakeYouWillSend(formats.sats(sats))
                : l10n.p2pTakeYouWillReceive(formats.sats(sats)),
            color: colors.textMuted,
          ),
        ...under,
      ],
    );
  }
}

/// « Password » of a protected order (#245): the reference's label (`t('Password')`, `components/OrderDetails/index.tsx:550`) above the field, as the amount's, a short line above it, the field typed hidden, and nothing learnt, suggested or corrected by the keyboard.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool error;
  final VoidCallback onChanged;

  const _PasswordField({
    required this.controller,
    required this.enabled,
    required this.error,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      borderSide: BorderSide(color: color),
    );
    final edge = error ? colors.error : colors.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.p2pTakeProtectedHidden,
          style: text.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        const Gap(BullSpacing.sm),
        // A screen reader hears it as the field's label.
        ExcludeSemantics(
          child: Text(
            l10n.p2pMakePassword,
            style: text.labelLarge?.copyWith(
              color: error ? colors.error : colors.textMuted,
            ),
          ),
        ),
        const Gap(BullSpacing.xs),
        Semantics(
          container: true,
          label: l10n.p2pMakePassword,
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.text),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              filled: true,
              fillColor: colors.surface,
              enabledBorder: border(edge),
              disabledBorder: border(colors.outline),
              focusedBorder: border(error ? colors.error : colors.primary),
            ),
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  final List<Widget> above;
  final Widget button;
  final List<Widget> under;

  const _Column({
    this.above = const [],
    required this.button,
    this.under = const [],
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final widget in above) ...[widget, const Gap(BullSpacing.sm)],
      button,
      for (final widget in under) ...[const Gap(BullSpacing.xs), widget],
    ],
  );
}

/// A line under the button, which wraps at any text size; a [live] one, what the take gave, is read out when it appears, while the estimate under the amount is not read at each keystroke.
class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final bool live;

  const _Line(this.text, {this.color, this.live = false});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: live,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color ?? context.bull.textMuted),
    ),
  );
}
