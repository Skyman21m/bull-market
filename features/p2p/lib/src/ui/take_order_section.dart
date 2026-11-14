import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/taker_estimate.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import '../presentation/take_amount_input.dart';
import '../presentation/take_order_cubit.dart';
import '../presentation/trade_l10n.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/store_token_dialog.dart';
import 'widgets/trade_button.dart';

/// « Take Order » at the foot of the order details, as the official client's take button (`components/OrderDetails/TakeButton.tsx` at commit ff1998c).
///
/// - A range order first asks its amount: « Amount {{currencyCode}} », « Too low » / « Too high » under the field, « Take Order » disabled with « You must specify an amount first » until the amount fits, then « You will receive {{satoshis}} Sats (Approx) ».
/// - On press: « You do not have a Garage Key » without a key, else « Store your garage key »; its « Done » takes. The reference shows the order's description first when it has one: the book read gives none, so there is none here.
/// - While the take runs, the button shows that it runs and cannot be pressed again, a bar runs under it and, after 30 s, the panel says it still waits, as the robot panel of the Garage does; when the take was sent, [onTaken] opens its trade. A take that did not happen says why under the button, as the reference shows the coordinator's message there, in words of the app.
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

  /// Whether the dialogs before the take are open: a second press meanwhile opens nothing more.
  bool _asking = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _press(TakeAmountInput input) async {
    if (_asking) return;
    _asking = true;
    try {
      if (!widget.canTake) {
        await NoRobotDialog.show(context, onOpenGarage: widget.onOpenGarage);
        return;
      }
      final cubit = context.read<TakeOrderCubit>();
      if (!await cubit.hasGarageKey()) {
        if (!mounted) return;
        await NoRobotDialog.show(context, onOpenGarage: widget.onOpenGarage);
        return;
      }
      if (!mounted) return;
      if (!await StoreTokenDialog.show(context)) return;
      unawaited(
        cubit.take(
          amount: switch (input) {
            TakeAmountValid(:final amount) => amount,
            _ => null,
          },
        ),
      );
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
    final running = state is TakeRunning || state is TakeSent;
    final isRange = order.amount is RangeOrderAmount;
    final input = isRange
        ? TakeAmountInput.read(_amount.text, order)
        : const TakeAmountEmpty();
    final ready = !isRange || input is TakeAmountValid;
    final button = TradeButton(
      label: l10n.p2pTakeOrder,
      busy: running,
      onPressed: ready ? () => unawaited(_press(input)) : null,
    );
    final coordinator = CoordinatorText.of(
      order.coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    final under = <Widget>[
      if (state is TakeRunning) ...[
        // What a screen reader says of the take while it runs: « Take Order », in progress.
        Semantics(
          container: true,
          liveRegion: true,
          child: LinearProgressIndicator(
            color: context.bull.primary,
            semanticsLabel: l10n.p2pTakeOrder,
          ),
        ),
        if (state.slow)
          _Line(l10n.p2pRobotStillWaiting(coordinator), live: true),
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
            controller: _amount,
            input: input,
            takerFee: widget.takerFee,
            enabled: !running,
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

/// The amount field of a range order, its estimate under it, then the button.
class _RangeTake extends StatelessWidget {
  final PublicOrder order;
  final TextEditingController controller;
  final TakeAmountInput input;
  final double takerFee;
  final bool enabled;
  final VoidCallback onChanged;
  final Widget button;
  final List<Widget> under;

  const _RangeTake({
    required this.order,
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
    final sats = switch (input) {
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
