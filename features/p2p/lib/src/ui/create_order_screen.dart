import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/option_search.dart';
import '../domain/trade/make_price_check.dart';
import '../domain/trade/maker_form.dart';
import '../domain/trade/trade_tolerances.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/make_order_cubit.dart';
import '../presentation/make_order_l10n.dart';
import '../presentation/p2p_formats.dart';
import 'garage/select_host_sheet.dart';
import 'widgets/add_payment_method_dialog.dart';
import 'widgets/coordinator_avatar.dart';
import 'widgets/filter_choice.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/store_token_dialog.dart';
import 'widgets/testnet_banner.dart';
import 'widgets/trade_button.dart';

/// The « Create » page: the official client's basic form (`components/MakerForm/MakerForm.tsx`, `basic/MakerPage/index.tsx`, commit ff1998c; design note `docs/design/phase-3-making-an-order.md` § 1.11, § 2.1), in the wallet's look (#181).
///
/// Field by field, as the reference lays them out: « Enable advanced options », shown disabled with « Coming in a later version. » (the defaults apply: 23:59 public, 3 hours for each step, a bond of 3 %, a fixed amount); « Buy or Sell Bitcoin? * » with « Buy », and « Sell » disabled with « Selling as maker is coming in a later version. »; « Amount * » and the currency; « Fiat Payment Method(s) * » with « Add custom payment method »; « Premium over Market (%) * »; the coordinator, drawn by the reference's lottery and chosen with « Select Host »; the summary and « Estimated Bond »; « Create order », disabled with the reference's reason; « Order current rate », then the Bull wallet's indicative price for comparison (the owner's decision of 2026-11-17).
///
/// What is typed stays here; it is judged by [MakerFormCheck] at each build, and the request « Create order » sends is the one the summary shows, taken at the press. From the press the fields are locked: « You do not have a Garage Key » without a key, else « Store your garage key », whose « Done » sends the make once ([MakeOrderCubit.make]), its « Go back » sending nothing. A made order opens its trade ([onMade]); a make refused or not made says why; a make whose outcome is unknown locks the form.
class CreateOrderScreen extends StatefulWidget {
  /// « Buy » chosen when the form opens, as the reference starts from the book's choice (`fav.type`); `null` for none.
  final OrderType? initialType;

  /// Builds the cubit of a coordinator's dialog, from « Select Host ».
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// The coordinators the book of the tab could not reach, said in « Select Host ».
  final Set<String> offline;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  /// Opens the trade of the order made.
  final ValueChanged<TradeRecord> onMade;

  const CreateOrderScreen({
    super.key,
    required this.coordinatorDetails,
    required this.onMade,
    this.initialType,
    this.offline = const {},
    this.onOpenGarage,
  });

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _amount = TextEditingController();
  final _premium = TextEditingController();
  late OrderType? _type = widget.initialType == OrderType.buy
      ? OrderType.buy
      : null;
  final List<String> _methods = [];

  /// Whether a dialog of the press is open, or the make is being handed to the cubit: a second press opens nothing more and the fields stay locked.
  bool _asking = false;

  /// Why the last press stopped before its dialogs, the form showing something else than at the press: a line says so until the next press.
  _PressStopped? _stopped;

  /// Completes when the screen goes away: « Select Host » and the coordinator dialog it opened close then.
  final _gone = Completer<void>();

  @override
  void dispose() {
    _amount.dispose();
    _premium.dispose();
    if (!_gone.isCompleted) _gone.complete();
    super.dispose();
  }

  MakerFormCheck _check(MakeOrderState state) => MakerFormCheck.of(
    MakerFormInput(
      type: _type,
      currency: state.currency,
      amount: _amount.text,
      paymentMethods: _methods,
      premium: _premium.text,
    ),
    coordinatorsLoaded: state.coordinatorsLoaded,
    market: state.formLimits,
    sizeLimitSats: state.sizeLimitSats,
  );

  /// « Create order »: the request of the form as shown, then « You do not have a Garage Key » or « Store your garage key », whose « Done » sends it with the coordinator and the price check shown at the press.
  ///
  /// Limits and a price read more than a few minutes ago are read again first: when the form then shows another request or another price check (not only another red warning: a comparison gone « rate not checked » too, security review of #181, C2), nothing goes on and the user sees the fresh form, said by a line.
  Future<void> _press() async {
    if (_asking) return;
    final cubit = context.read<MakeOrderCubit>();
    // The request, the coordinator and the price check are those the form shows now: the fields are locked from here.
    final request = _check(cubit.state).request;
    final coordinator = cubit.state.coordinator;
    var seen = cubit.seen();
    if (request == null ||
        coordinator == null ||
        seen == null ||
        cubit.state.locked) {
      return;
    }
    setState(() {
      _asking = true;
      _stopped = null;
    });
    try {
      // A press while the Bull wallet's price is being read: its end awaited, the button busy (the shell bounds a read to 15 s), then the line it shows is the one the press is for (second security review of #181, R8).
      if (cubit.state.price is MakeFormPriceReading) {
        await cubit.priceSettled();
        if (!mounted) return;
        final settled = cubit.seen();
        if (_check(cubit.state).request != request ||
            settled == null ||
            !settled.sameLineAs(seen)) {
          setState(() => _stopped = _PressStopped.priceRead);
          return;
        }
        seen = settled;
      }
      if (await cubit.refreshIfStale()) {
        if (!mounted) return;
        final fresh = cubit.seen();
        if (_check(cubit.state).request != request ||
            fresh == null ||
            !fresh.sameLineAs(seen)) {
          setState(() => _stopped = _PressStopped.readAgain);
          return;
        }
        seen = fresh;
      }
      if (!await cubit.hasGarageKey()) {
        if (!mounted) return;
        await BullDialog.show<void>(
          context: context,
          builder: (_) => NoRobotDialog(onOpenGarage: widget.onOpenGarage),
        );
        return;
      }
      if (!mounted) return;
      final done = await StoreTokenDialog.show(context);
      if (!mounted || !done) return;
      unawaited(cubit.make(request, coordinator: coordinator, seen: seen));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// The amount typed: the Bull wallet's price is compared only once an amount above zero is typed (security review of #181).
  void _amountChanged() {
    setState(() {});
    final value = FormNumber.read(
      _amount.text,
      maxDecimals: MakerFormCheck.amountDecimals,
    ).value;
    unawaited(
      context.read<MakeOrderCubit>().wantPrice(value != null && value > 0),
    );
  }

  /// « Clear form » (`clearMaker`, `MakerForm.tsx:485-492`): no side chosen, the currency back to USD (`fav.currency` 0, which the form reads as USD), the amount, the payment methods and the premium emptied. The coordinator chosen stays: the reference puts back `defaultMaker.coordinator`, an alias drawn at random when its page loads, not its lottery's.
  void _clear() {
    setState(() {
      _type = null;
      _amount.clear();
      _premium.clear();
      _methods.clear();
      _stopped = null;
    });
    final cubit = context.read<MakeOrderCubit>();
    unawaited(cubit.wantPrice(false));
    final usd = RobosatsCurrency.fromCode('USD');
    if (usd != null) {
      unawaited(cubit.showCurrency(usd));
    }
  }

  Future<void> _chooseCurrency(MakeOrderState state) async {
    final l10n = P2pLocalizations.of(context);
    final currency = await FilterPickerSheet.show<RobosatsCurrency>(
      context,
      title: l10n.p2pBookFilterSelectCurrency,
      options: [
        for (final currency in RobosatsCurrency.all)
          if (!currency.isBitcoin) currency,
      ],
      selected: state.currency,
      label: (currency) => currency.code,
    );
    if (currency == null || !mounted) return;
    unawaited(context.read<MakeOrderCubit>().showCurrency(currency));
  }

  Future<void> _chooseMethods() async {
    final l10n = P2pLocalizations.of(context);
    final listed = [for (final method in PaymentMethods.fiat) method.name];
    await FilterSheet.show<String>(
      context,
      title: l10n.p2pBookFilterSelectMethod,
      anyLabel: null,
      options: const [],
      groups: [
        FilterSheetGroup(options: List.of(_methods)),
        FilterSheetGroup(
          options: [
            for (final method in listed)
              if (!_methods.contains(method)) method,
          ],
        ),
      ],
      selected: _methods,
      label: (method) => method,
      search: FilterSheetSearch(
        hint: l10n.p2pCommonSearch,
        clear: l10n.p2pCommonClear,
        noMatch: l10n.p2pBookFilterNoMethodFound,
        matches: matchesOptionSearch,
      ),
      onChanged: (methods) {
        if (!mounted) return;
        setState(
          () => _methods
            ..clear()
            ..addAll(methods),
        );
      },
    );
  }

  Future<void> _addMethod() async {
    final method = await AddPaymentMethodDialog.show(context);
    if (method == null || !mounted) return;
    setState(() {
      if (!_methods.any(
        (chosen) => CustomPaymentMethod.sameMethod(chosen, method.text),
      )) {
        _methods.add(method.text);
      }
    });
  }

  Future<void> _chooseHost(MakeOrderState state) async {
    final coordinator = await SelectHostSheet.show(
      context,
      hosts: state.hosts,
      offline: widget.offline,
      network: state.network,
      coordinatorDetails: widget.coordinatorDetails,
      closeWhen: _gone.future,
    );
    if (coordinator == null || !mounted) return;
    unawaited(context.read<MakeOrderCubit>().choose(coordinator));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<MakeOrderCubit>().state;
    final check = _check(state);
    final locked = state.locked || _asking;
    final coordinator = state.coordinator;
    final coordinatorName = coordinator == null
        ? ''
        : CoordinatorText.of(
            coordinator.longAlias,
            maxCodePoints: CoordinatorText.name,
          );
    return BlocListener<MakeOrderCubit, MakeOrderState>(
      listenWhen: (previous, current) =>
          current.progress is MakeMade && previous.progress is! MakeMade,
      listener: (_, current) {
        if (current.progress case MakeMade(:final record)) {
          widget.onMade(record);
        }
      },
      child: Material(
        color: colors.background,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (state.network == RobosatsNetwork.testnet)
                const TestnetBanner(),
              const Gap(BullSpacing.xs),
              BullTopBar(
                title: l10n.p2pNavCreate,
                onBack: () {
                  if (context.canPop()) context.pop();
                },
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(BullSpacing.md),
                  children: [
                    _AdvancedOptions(onClear: locked ? null : _clear),
                    const Gap(BullSpacing.md),
                    _Side(
                      type: _type,
                      enabled: !locked,
                      // As the reference's « Buy », a choice, never a toggle (`MakerForm.tsx:766-775`).
                      onBuy: () => setState(() => _type = OrderType.buy),
                    ),
                    const Gap(BullSpacing.md),
                    _Amount(
                      controller: _amount,
                      currency: state.currency,
                      problem: check.amountProblem,
                      enabled: !locked,
                      onChanged: _amountChanged,
                      onCurrency: () => unawaited(_chooseCurrency(state)),
                    ),
                    const Gap(BullSpacing.md),
                    _Methods(
                      methods: _methods,
                      tooLong: check.badPaymentMethod,
                      enabled: !locked,
                      onChoose: () => unawaited(_chooseMethods()),
                      onAdd: () => unawaited(_addMethod()),
                      onRemove: (method) =>
                          setState(() => _methods.remove(method)),
                    ),
                    const Gap(BullSpacing.md),
                    _PremiumField(
                      controller: _premium,
                      problem: check.premiumProblem,
                      enabled: !locked,
                      onChanged: () => setState(() {}),
                    ),
                    const Gap(BullSpacing.md),
                    _Coordinator(
                      state: state,
                      name: coordinatorName,
                      enabled: !locked && state.coordinatorsLoaded,
                      onTap: () => unawaited(_chooseHost(state)),
                    ),
                    const Gap(BullSpacing.md),
                    _Summary(type: _type, check: check, state: state),
                    const Gap(BullSpacing.md),
                    _CreateButton(
                      check: check,
                      state: state,
                      asking: _asking,
                      stopped: _stopped,
                      coordinator: coordinatorName,
                      onPressed: () => unawaited(_press()),
                    ),
                    const Gap(BullSpacing.md),
                    _Rate(
                      check: check,
                      state: state,
                      coordinator: coordinatorName,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reference's first row (`MakerForm.tsx:674-723`): « Clear form » at the left, a bin with its tooltip, then « Enable advanced options », disabled, with « Coming in a later version. ».
class _AdvancedOptions extends StatelessWidget {
  /// « Clear form »; `null` while the form is locked.
  final VoidCallback? onClear;

  const _AdvancedOptions({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: l10n.p2pMakeClearForm,
          onPressed: onClear,
          color: colors.textMuted,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        const Gap(BullSpacing.xs),
        Expanded(
          child: MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.p2pMakeEnableAdvanced,
                        style: text.bodyLarge?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      Text(
                        l10n.p2pMakeComingLater,
                        style: text.labelMedium?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Switch(value: false, onChanged: null),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// « Buy or Sell Bitcoin? * », « Buy » and « Sell », the latter disabled with its line.
class _Side extends StatelessWidget {
  final OrderType? type;
  final bool enabled;
  final VoidCallback onBuy;

  const _Side({required this.type, required this.enabled, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l10n.p2pMakeBuyOrSell} *',
          textAlign: TextAlign.center,
          style: text.labelLarge?.copyWith(color: colors.textMuted),
        ),
        const Gap(BullSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Semantics(
                selected: type == OrderType.buy,
                child: TradeButton(
                  label: l10n.p2pMakeBuy,
                  outlined: type != OrderType.buy,
                  onPressed: enabled ? onBuy : null,
                ),
              ),
            ),
            const Gap(BullSpacing.sm),
            Expanded(
              child: TradeButton(
                label: l10n.p2pMakeSell,
                outlined: true,
                onPressed: null,
              ),
            ),
          ],
        ),
        const Gap(BullSpacing.xs),
        Text(
          l10n.p2pMakeSellComingLater,
          textAlign: TextAlign.center,
          style: text.labelMedium?.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// Keeps a number field to its decimals: an edit that would give more is not taken, so the field never shows a value the form would read otherwise.
final class _DecimalsFormatter extends TextInputFormatter {
  final int decimals;

  const _DecimalsFormatter(this.decimals);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final separator = text.lastIndexOf(RegExp('[.,\u066b\uff0e\uff0c]'));
    if (separator >= 0 && text.length - separator - 1 > decimals) {
      return oldValue;
    }
    // A number a double cannot hold as typed is not taken either: the field never shows a number the form would read otherwise.
    if (FormNumber.beyondPrecision(text, maxDecimals: decimals)) {
      return oldValue;
    }
    return newValue;
  }
}

OutlineInputBorder _border(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(BullRadius.xxs),
  borderSide: BorderSide(color: color),
);

/// A number field of the form: its label above it (a floating label is kept on one line, which large text would cut), the reference's line under it when there is one.
class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final bool signed;
  final int decimals;
  final VoidCallback onChanged;
  final String? tooltip;

  const _NumberField({
    required this.label,
    required this.controller,
    required this.error,
    required this.enabled,
    required this.signed,
    required this.decimals,
    required this.onChanged,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final error = this.error;
    final edge = error == null ? colors.outline : colors.error;
    final field = Semantics(
      container: true,
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: signed,
        ),
        // A number, not words: no suggestion, correction or learning by the keyboard.
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        inputFormatters: [
          LengthLimitingTextInputFormatter(FormNumber.maxLength),
          _DecimalsFormatter(decimals),
        ],
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: colors.text),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          errorText: error,
          errorMaxLines: 3,
          filled: true,
          fillColor: colors.surface,
          enabledBorder: _border(edge),
          disabledBorder: _border(colors.outline),
          focusedBorder: _border(error == null ? colors.primary : edge),
          errorBorder: _border(colors.error),
          focusedErrorBorder: _border(colors.error),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: error == null ? colors.textMuted : colors.error,
            ),
          ),
        ),
        const Gap(BullSpacing.xxs),
        if (tooltip == null) field else Tooltip(message: tooltip, child: field),
      ],
    );
  }
}

/// « Amount * » and its currency, as the reference puts them side by side (`MakerForm.tsx:861-938`).
class _Amount extends StatelessWidget {
  final TextEditingController controller;
  final RobosatsCurrency currency;
  final MakerAmountProblem? problem;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onCurrency;

  const _Amount({
    required this.controller,
    required this.currency,
    required this.problem,
    required this.enabled,
    required this.onChanged,
    required this.onCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final error = switch (problem) {
      MakerAmountTooLow(:final shown) => l10n.p2pMakeMoreThan(
        formats.typedNumber(shown),
      ),
      MakerAmountTooHigh(:final shown) => l10n.p2pMakeLessThan(
        formats.typedNumber(shown),
      ),
      null => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _NumberField(
            label: '${l10n.p2pMakeAmount} *',
            controller: controller,
            error: error,
            enabled: enabled,
            signed: false,
            decimals: MakerFormCheck.amountDecimals,
            onChanged: onChanged,
            tooltip: l10n.p2pMakeAmountHint,
          ),
        ),
        const Gap(BullSpacing.sm),
        Padding(
          // Level with the field, under its label.
          padding: const EdgeInsets.only(top: BullSpacing.lg + BullSpacing.xs),
          child: FilterChoice(
            label: currency.code,
            semanticsLabel:
                '${l10n.p2pBookFilterSubjectCurrency}: ${currency.code}',
            onTap: enabled ? onCurrency : () {},
          ),
        ),
      ],
    );
  }
}

/// « Fiat Payment Method(s) * », the methods chosen with a cross each, the list that chooses them, and « Add custom payment method ».
class _Methods extends StatelessWidget {
  final List<String> methods;
  final bool tooLong;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _Methods({
    required this.methods,
    required this.tooLong,
    required this.enabled,
    required this.onChoose,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l10n.p2pMakePaymentMethods} *',
          style: text.labelLarge?.copyWith(
            color: tooLong ? colors.error : colors.textMuted,
          ),
        ),
        const Gap(BullSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Tooltip(
                message: l10n.p2pMakePaymentMethodsHint,
                child: Material(
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BullRadius.xxs),
                    side: BorderSide(
                      color: tooLong ? colors.error : colors.outline,
                    ),
                  ),
                  child: InkWell(
                    onTap: enabled ? onChoose : null,
                    borderRadius: BorderRadius.circular(BullRadius.xxs),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.all(BullSpacing.xs),
                        child: Wrap(
                          spacing: BullSpacing.xs,
                          runSpacing: BullSpacing.xs,
                          children: [
                            for (final method in methods)
                              InputChip(
                                label: Text(
                                  method,
                                  style: text.bodyMedium?.copyWith(
                                    color: colors.text,
                                  ),
                                ),
                                backgroundColor: colors.surfaceContainer,
                                isEnabled: enabled,
                                deleteButtonTooltipMessage: l10n
                                    .p2pMakeRemoveMethod(method),
                                onDeleted: enabled
                                    ? () => onRemove(method)
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Gap(BullSpacing.sm),
            Tooltip(
              message: l10n.p2pMakeAddCustomMethod,
              child: IconButton(
                onPressed: enabled ? onAdd : null,
                color: colors.textMuted,
                icon: const Icon(Icons.dashboard_customize_outlined),
              ),
            ),
          ],
        ),
        if (tooLong) ...[
          const Gap(BullSpacing.xxs),
          Text(
            l10n.p2pMakeMustBeShorter('${CustomPaymentMethod.maxLength}'),
            style: text.labelMedium?.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}

/// « Premium over Market (%) * » with the reference's line under it when it is out of bounds.
class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final MakerPremiumProblem? problem;
  final bool enabled;
  final VoidCallback onChanged;

  const _PremiumField({
    required this.controller,
    required this.problem,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return _NumberField(
      label: '${l10n.p2pMakePremium} *',
      controller: controller,
      error: switch (problem) {
        MakerPremiumProblem.tooHigh => l10n.p2pMakePremiumTooHigh(
          formats.typedNumber(MakerFormCheck.maxPremium),
        ),
        MakerPremiumProblem.tooLow => l10n.p2pMakePremiumTooLow(
          formats.typedNumber(MakerFormCheck.minPremium),
        ),
        null => null,
      },
      enabled: enabled,
      signed: true,
      decimals: MakerFormCheck.premiumDecimals,
      onChanged: onChanged,
    );
  }
}

/// The coordinator of the order, as the reference's `SelectCoordinator`: its image, its name and its fees; « Loading... » while the lottery runs; a tap opens « Select Host ».
class _Coordinator extends StatelessWidget {
  final MakeOrderState state;
  final String name;
  final bool enabled;
  final VoidCallback onTap;

  const _Coordinator({
    required this.state,
    required this.name,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final coordinator = state.coordinator;
    if (state.noHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pMakeNoHost, color: colors.warning, live: true),
          const Gap(BullSpacing.xs),
          TradeButton(
            label: l10n.p2pCommonRetry,
            outlined: true,
            onPressed: enabled
                ? () => unawaited(context.read<MakeOrderCubit>().retryHosts())
                : null,
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.p2pMakeChooseHost,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BullRadius.xxs),
          side: BorderSide(color: colors.outline),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(BullRadius.xxs),
          child: Padding(
            padding: const EdgeInsets.all(BullSpacing.sm),
            child: Row(
              children: [
                if (coordinator == null)
                  const SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                else
                  CoordinatorAvatar(coordinator: coordinator, size: 40),
                const Gap(BullSpacing.sm),
                Expanded(
                  child: coordinator == null
                      ? Text(
                          l10n.p2pMakeLoading,
                          style: text.bodyLarge?.copyWith(
                            color: colors.textMuted,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: text.headlineSmall?.copyWith(
                                color: colors.text,
                              ),
                            ),
                            OrderFeeRow(
                              info: state.infos[coordinator.shortAlias],
                            ),
                          ],
                        ),
                ),
                Icon(Icons.arrow_drop_down, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The summary, « Buy BTC for 100 EUR at market price », then « Estimated Bond: … Sats » (`MakerForm.tsx:576-625`), from the very values the request sends.
class _Summary extends StatelessWidget {
  final OrderType? type;
  final MakerFormCheck check;
  final MakeOrderState state;

  const _Summary({
    required this.type,
    required this.check,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final premium = check.premiumPercent;
    final start = switch (type) {
      null => l10n.p2pMakeOrderFor,
      OrderType.buy => l10n.p2pMakeBuyBtcFor,
      // Never chosen in this version.
      OrderType.sell => l10n.p2pMakeOrderFor,
    };
    final price = premium == 0
        ? l10n.p2pMakeAtMarketPrice
        : premium > 0
        ? l10n.p2pMakeAtPremium(formats.number(premium))
        : l10n.p2pMakeAtDiscount(formats.number(-premium));
    final bond = check.estimatedBond;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        children: [
          Text(
            '$start${formats.typedNumber(check.amount)} ${state.currency.code}$price',
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(
              color: check.block == null ? colors.text : colors.textMuted,
            ),
          ),
          if (bond != null) ...[
            const Gap(BullSpacing.xxs),
            Text(
              l10n.p2pMakeEstimatedBond(formats.sats(bond)),
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Why a press of « Create order » stopped before its dialogs.
enum _PressStopped {
  /// The limits and the price, more than 3 minutes old, were read again and the form shows another request or another price check (security review of #181, C2).
  readAgain,

  /// The Bull wallet's price was being read at the press; read, it shows another line than at the press (second security review of #181, R8).
  priceRead,
}

/// « Create order », disabled with the reference's reason (a tooltip opened by a tap, as the reference opens it on touch, and the same line under it), then what the make is doing or why it did not happen.
class _CreateButton extends StatelessWidget {
  final MakerFormCheck check;
  final MakeOrderState state;
  final bool asking;

  /// Why the last press stopped, the form showing something else.
  final _PressStopped? stopped;
  final String coordinator;
  final VoidCallback onPressed;

  const _CreateButton({
    required this.check,
    required this.state,
    required this.asking,
    required this.stopped,
    required this.coordinator,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final progress = state.progress;
    final block = check.block;
    final ready = block == null && progress is MakeIdle;
    final button = TradeButton(
      label: l10n.p2pMakeCreateOrder,
      busy: asking || progress is MakeSending,
      onPressed: ready ? onPressed : null,
    );
    final lines = <Widget>[
      if (block != null && progress is MakeIdle)
        _Line(block.toText(context), live: true),
      if (stopped case final stopped? when progress is MakeIdle)
        _Line(
          switch (stopped) {
            _PressStopped.readAgain => l10n.p2pMakePricesReadAgain,
            _PressStopped.priceRead => l10n.p2pMakePriceReadAtPress,
          },
          color: colors.warning,
          live: true,
        ),
      if (progress is MakeSending) _Line(l10n.p2pMakeCreating, live: true),
      if (progress is MakeUncertain) ...[
        _Line(l10n.p2pMakeCreating, live: true),
        _Line(l10n.p2pMakePending(coordinator), live: true),
      ],
      if (progress case MakeIdle(:final problem?))
        _Line(
          problem.toText(context, coordinator: coordinator),
          color: colors.error,
          live: true,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block == null)
          button
        else
          Tooltip(
            message: block.toText(context),
            triggerMode: TooltipTriggerMode.tap,
            child: button,
          ),
        for (final line in lines) ...[const Gap(BullSpacing.xs), line],
      ],
    );
  }
}

/// « Order current rate: … {{currencyCode}}/BTC » with its tooltip (`MakerForm.tsx:1340-1363`), then the Bull wallet's indicative price for comparison and, beyond the owner's threshold either way, a red warning; for a currency the Bull wallet does not price, or a price it could not read, a line in the warning colour (with « Retry » for the latter). None of it stops « Create order ».
class _Rate extends StatelessWidget {
  final MakerFormCheck check;
  final MakeOrderState state;
  final String coordinator;

  const _Rate({
    required this.check,
    required this.state,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final rate = check.rate;
    final code = state.currency.code;
    final children = <Widget>[
      Tooltip(
        message: l10n.p2pMakeCurrentRateHint,
        child: rate != null
            ? _Line(l10n.p2pMakeCurrentRate(formats.orderRate(rate), code))
            : _RateWaiting(code: code),
      ),
    ];
    final price = check.price;
    switch (state.price) {
      case MakeFormPriceNone():
        break;
      case MakeFormPriceReading():
        if (price != null) children.add(_Line(l10n.p2pMakeRateReading));
      case MakeFormPriceChecked(:final check)
          when check.currency == state.currency && price != null:
        switch (check) {
          case MakePriceCompared():
            final line = l10n.p2pMakeRateCompare(
              formats.orderRate(check.walletPrice),
              code,
              coordinator,
              formats.orderRate(check.coordinatorPrice),
              formats.gap(check.gapHundredths),
            );
            final threshold = formats.threshold(TradeTolerances.walletRateGap);
            children.add(_Line(line, color: check.warns ? colors.error : null));
            switch (check.side) {
              case MakePriceSide.within:
                break;
              case MakePriceSide.below:
                children.add(
                  _Alert(
                    l10n.p2pMakeRateBelow(coordinator, threshold),
                    colors.error,
                  ),
                );
              case MakePriceSide.above:
                children.add(
                  _Alert(
                    l10n.p2pMakeRateAbove(coordinator, threshold),
                    colors.error,
                  ),
                );
            }
          case MakePriceNotPriced():
            children.add(
              _Alert(
                l10n.p2pMakeRateNotPriced(code, coordinator),
                colors.warning,
              ),
            );
          case MakePriceUnverified():
            children
              ..add(_Alert(l10n.p2pMakeRateUnverified(code), colors.warning))
              ..add(
                TradeButton(
                  label: l10n.p2pCommonRetry,
                  outlined: true,
                  onPressed: () =>
                      unawaited(context.read<MakeOrderCubit>().retryPrice()),
                ),
              );
        }
      case MakeFormPriceChecked():
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const Gap(BullSpacing.xs),
          child,
        ],
      ],
    );
  }
}

/// « Order current rate: » while the rate is not known: the line stays, a placeholder in place of the figure, as the reference draws a skeleton there (`MakerForm.tsx:1351-1361`).
class _RateWaiting extends StatelessWidget {
  final String code;

  const _RateWaiting({required this.code});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textMuted);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: BullSpacing.xs,
      children: [
        Text(l10n.p2pMakeCurrentRateLabel, style: style),
        ExcludeSemantics(
          child: Container(
            width: 64,
            height: 12,
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(BullRadius.xxs),
            ),
          ),
        ),
        Text(l10n.p2pMakeCurrentRateUnit(code), style: style),
      ],
    );
  }
}

/// A line of the form, centred, which wraps at any text size; a [live] one is read out when it appears.
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

/// A line of the price check in [color], bold, with a warning sign, read out when it appears.
class _Alert extends StatelessWidget {
  final String text;
  final Color color;

  const _Alert(this.text, this.color);

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
