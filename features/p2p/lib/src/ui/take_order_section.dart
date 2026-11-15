import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/taker_estimate.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import '../presentation/take_amount_input.dart';
import '../presentation/take_order_cubit.dart';
import '../presentation/trade_l10n.dart';
import 'order_details_screen.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/store_token_dialog.dart';
import 'widgets/trade_button.dart';

/// « Take Order » at the foot of the order details, as the official client's take button (`components/OrderDetails/TakeButton.tsx` at commit ff1998c).
///
/// - A range order first asks its amount: « Amount {{currencyCode}} », « Too low » / « Too high » under the field, « Take Order » disabled with « You must specify an amount first » until the amount fits, then « You will receive {{satoshis}} Sats (Approx) ».
/// - On press, the reference's order (#119, the owner's decision after the review of #133): « You do not have a Garage Key » without a key, else the take is prepared: the robot that will take the order reads it, while the button shows that it runs, a bar runs under it with a line that says each step (the order checked with the coordinator, the robot built, « Building your robot! » in the reference's words, the order read by the robot) and, after 30 s, that it still waits, as the robot panel of the Garage does.
/// - Once the order is read, the order details show that read ([TakeOrderDetailsCard]: the maker's description and the fresh figures, which the reference shows in « Order description » with « Go back » / « Continue »), and « Take Order » gives way to « Continue » and « Go back »; « Continue » opens « Store your garage key », whose « Done » sends the take (its wait says its steps too) and whose « Go back », or a tap outside, abandons it as « Go back » does.
/// - « The order changed. » says, from its start, that a confirmation found the order changed and reads it again: the read the user saw stays shown meanwhile, the rows that differ are marked when the new one arrives, and it waits for « Continue » and « Done » again, never confirmed by itself. When the take was sent, [onTaken] opens its trade, the read shown until then.
/// - An order found gone is said so, and « Take Order » stays disabled.
/// - A take that did not happen says why under the button, as the reference shows the coordinator's message there, in words of the app.
/// - A buy order, whose taker sells, is a later version: the button is shown disabled with a short line (#96).
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

  @override
  State<TakeOrderSection> createState() => _TakeOrderSectionState();
}

class _TakeOrderSectionState extends State<TakeOrderSection> {
  final _amount = TextEditingController();

  /// Whether a dialog of the take is open: a second press meanwhile opens nothing more.
  bool _asking = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
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

  /// « Continue »: « Store your garage key », whose « Done » sends the take and whose « Go back », or a tap outside, abandons it, as « Go back » does.
  Future<void> _continue() async {
    if (_asking) return;
    _asking = true;
    try {
      final cubit = context.read<TakeOrderCubit>();
      final done = await StoreTokenDialog.show(context);
      if (!mounted) return;
      if (done) {
        unawaited(cubit.confirm());
      } else {
        cubit.back();
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final order = widget.order;
    if (order.type == OrderType.buy) {
      return _Column(
        button: TradeButton(label: l10n.p2pTakeOrder, onPressed: null),
        under: [_Line(l10n.p2pTakeSellingLater)],
      );
    }
    final state = widget.canTake
        ? context.watch<TakeOrderCubit>().state
        : const TakeIdle();
    final isRange = order.amount is RangeOrderAmount;
    final input = isRange
        ? TakeAmountInput.read(_amount.text, order)
        : const TakeAmountEmpty();
    final ready = !isRange || input is TakeAmountValid;
    final cubit = widget.canTake ? context.read<TakeOrderCubit>() : null;
    // The read the order details show: while it is there, « Continue » and « Go back » stand in place of « Take Order », down to the trade's screen.
    final read = TakeOrderDetailsCard.readOf(state);
    final changed = switch (state) {
      TakePreparing(changed: true) => true,
      TakeReady(changed: true) => true,
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
              TradeButton(
                label: l10n.p2pCommonContinue,
                busy: state is! TakeReady,
                onPressed: () => unawaited(_continue()),
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
      if (state case TakeIdle(:final problem?))
        _Line(
          problem.toText(context, coordinator: coordinator),
          color: context.bull.error,
          live: true,
        ),
    ];
    final content = isRange
        ? _RangeTake(
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
        : _Column(button: button, under: under);
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
    return BlocListener<TakeOrderCubit, TakeOrderState>(
      listenWhen: (_, current) => current is TakeReady,
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
        read: readOf(state),
        previous: switch (state) {
          TakeReady(:final previous) => previous,
          _ => null,
        },
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
    final read = canTake
        ? TakeOrderDetailsCard.readOf(context.watch<TakeOrderCubit>().state)
        : null;
    return OrderFeeRow(info: info, takerFee: read?.terms.takerFee);
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
            l10n.p2pTakeYouWillReceive(formats.sats(sats)),
            color: colors.textMuted,
          ),
        ...under,
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
