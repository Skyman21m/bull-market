import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/map_tiles.dart';
import '../domain/matching_orders.dart';
import '../domain/meeting_point.dart';
import '../domain/option_search.dart';
import '../domain/trade/make_price_check.dart';
import '../domain/trade/maker_form.dart';
import '../domain/trade/trade_make.dart';
import '../domain/trade/trade_renewal.dart';
import '../domain/trade/trade_tolerances.dart';
import '../domain/trade_record.dart';
import '../presentation/active_trades_cubit.dart';
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/make_order_cubit.dart';
import '../presentation/make_order_l10n.dart';
import '../presentation/p2p_formats.dart';
import '../presentation/pending_makes_cubit.dart';
import 'garage/select_host_sheet.dart';
import 'location_map_dialog.dart';
import 'map_tile_layer.dart';
import 'trade/pending_make_lines.dart';
import 'widgets/add_payment_method_dialog.dart';
import 'widgets/coordinator_avatar.dart';
import 'widgets/filter_choice.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/offer_row.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/store_token_dialog.dart';
import 'widgets/testnet_banner.dart';
import 'widgets/trade_button.dart';

/// The « Create » page: the official client's basic form (`components/MakerForm/MakerForm.tsx`, `basic/MakerPage/index.tsx`, commit ff1998c; design note `docs/design/phase-3-making-an-order.md` § 1.11, § 2.1), in the wallet's look (#181).
///
/// Field by field, as the reference lays them out: « Enable advanced options » (#183); « Buy or Sell Bitcoin? * » with « Buy » and « Sell » (« Sell » since #188); with the advanced options, « Amount Range » or « Exact Amount »; « Amount * » and the currency, or for a range « From » … « to », the currency and the reference's slider; « Fiat Payment Method(s) * » with « Add custom payment method »; « Face to Face Location » (#189), its map opened by itself when the last method chosen is face to face; « Premium over Market (%) * »; with the advanced options, « Description », « Password » (#189), « Public Duration (HH:mm) », « Escrow/Invoice Timer (HH:mm) » and « Fidelity Bond Size »; the coordinator, drawn by the reference's lottery and chosen with « Select Host »; the summary and « Estimated Bond »; « Create order », disabled with the reference's reason; « Order current rate », then the Bull wallet's indicative price for comparison (the owner's decision of 2026-11-17).
///
/// What is typed stays here; it is judged by [MakerFormCheck] at each build, and the request « Create order » sends is the one the summary shows, taken at the press. From the press the fields are locked: « You do not have a Garage Key » without a key, else « Store your garage key », whose « Done » sends the make once ([MakeOrderCubit.make]), its « Go back » sending nothing. A made order opens its trade ([onMade]); a make refused or not made says why; a make whose outcome is unknown locks the form.
///
/// « Existing orders match yours! » (#186, `basic/MakerPage/index.tsx`): while orders of the [book] on the other side resemble the one being made ([MatchingOrders]), the button reads « Submit » and only shows them, above the form, the form's fields folded away as the reference collapses them; the button then reads « Create order », and « Edit order » (a pencil) unfolds the fields. A tap on one of those orders opens it ([onOpenOrder]). Nothing is asked of anyone for this: the search runs on the book the tab received.
///
/// A renewal (#185, [MakeOrderState.renewing]) is the same page titled « Renew Order », its fields filled with the terms this device kept of the order renewed and locked, on that order's coordinator: the same summary, « Estimated Bond », rate and Bull wallet's comparison, the same press and the same make; « Create order » sends only when the form judges its fields into exactly the kept request, and with no « Store your garage key », as the reference's renewal sends at once (`TradeBox/index.tsx:146-200`). Going back sends nothing.
/// An order renewed that had a password asks for it again (#189, `Prompts/Expired.tsx:42-92`): « Password » is then the only field open, and nothing is sent while it is empty, said under it and under the button; its SHA-256 is what leaves, where the reference sends the text typed (`TradeBox/index.tsx:180`), a defect of the reference (design note § 1.8). The meeting point kept is sent again as it is, as the reference sends the order's own (`:176-177`).
///
/// The explanations are shown on demand (the owner's rule of 2026-11-20): under « Password » and « Face to Face Location » a short line, and « See details » unfolds the rest; an alert stays shown in one line.
class CreateOrderScreen extends StatefulWidget {
  /// « Buy » or « Sell » chosen when the form opens, as the reference starts from the book's choice (`fav.type`); `null` for none.
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

  /// The orders the book of the tab received, searched for « Existing orders match yours! » (#186); `null` for none, and for a renewal, which the reference makes without its create page.
  final List<PublicOrder>? book;

  /// The device's trades of the network, so that an order this device holds is never offered (#186); the search waits for them to be listed.
  final ActiveTradesState? activeTrades;

  /// Opens an order of « Existing orders match yours! », to take it instead (`MakerPage/index.tsx:61-79`).
  final ValueChanged<PublicOrder>? onOpenOrder;

  /// The time of the orders' expiry rings.
  final DateTime Function() now;

  /// The draws that move a meeting point pinned (#189, [MeetingPoint.randomized]).
  final double Function() locationDraws;

  /// Opens the tiles of the meeting point's map, once its « Show tiles » is on and its dialog acknowledged (#246).
  final MapTileSession Function() openTiles;

  const CreateOrderScreen({
    super.key,
    required this.coordinatorDetails,
    required this.onMade,
    required this.locationDraws,
    required this.openTiles,
    this.initialType,
    this.offline = const {},
    this.onOpenGarage,
    this.book,
    this.activeTrades,
    this.onOpenOrder,
    this.now = DateTime.now,
  });

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  /// « Show tiles » of the meeting point's map and its acknowledgment, for the life of this form, as the reference's `F2fMapDialog` stays mounted in `MakerForm` (#246): a new form starts off.
  final _locationTiles = MapTilesChoice();

  final _amount = TextEditingController();
  final _premium = TextEditingController();

  /// « From », « to » and « Description » of the advanced options (#183).
  final _minAmount = TextEditingController();
  final _maxAmount = TextEditingController();
  final _description = TextEditingController();

  /// « Password » (#189): its text stays in this field only; the request carries its SHA-256.
  final _password = TextEditingController();

  /// « Face to Face Location »: the meeting point saved, as the order sends it, or `null` (#189).
  OrderLocation? _location;

  /// « Enable advanced options » and « Amount Range » (`maker.advancedOptions`, `amountRangeEnabled`, `MakerForm.tsx:90`), and the values of the options, the reference's defaults (`models/Maker.model.ts:29-56`).
  bool _advanced = false;
  bool _rangeEnabled = true;
  Duration _publicDuration = MakerFormCheck.publicDurationDefault;
  Duration _escrowDuration = MakerFormCheck.escrowDurationDefault;
  double _bondSize = MakerFormCheck.bondSizeDefault;
  late OrderType? _type = widget.initialType;
  final List<String> _methods = [];

  /// Whether a dialog of the press is open, or the make is being handed to the cubit: a second press opens nothing more and the fields stay locked.
  bool _asking = false;

  /// Why the last press stopped before its dialogs, the form showing something else than at the press: a line says so until the next press.
  _PressStopped? _stopped;

  /// Whether going back was tried while the make is sent: a line says to wait (#182).
  bool _leaveTried = false;

  /// Completes when the screen goes away: « Select Host » and the coordinator dialog it opened close then.
  final _gone = Completer<void>();

  /// The renewal whose kept terms fill the fields (#185), once filled.
  OrderRenewal? _filled;

  /// Whether « Submit » showed « Existing orders match yours! » (`showMatches`, `MakerPage/index.tsx:27`): the fields are folded away until « Edit order » (#186).
  bool _showMatches = false;

  /// The page's list, brought back to its top when « Submit » shows the orders above the form.
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (context.read<MakeOrderCubit>().state.renewal case MakeRenewalReady(
      :final renewal,
    )) {
      _fill(renewal);
    }
  }

  /// The fields of a renewal (#185): the kept request written in them as the form reads it back, the advanced options open when it has a range or an option that differs from the defaults, so that each is seen.
  void _fill(OrderRenewal renewal) {
    if (_filled != null) return;
    final request = renewal.request;
    _filled = renewal;
    _type = request.type;
    _methods
      ..clear()
      ..add(request.paymentMethod);
    _premium.text = _plain(request.premium.percent);
    _description.text = request.description ?? '';
    _publicDuration = request.publicDuration;
    _escrowDuration = request.escrowDuration;
    _bondSize = request.bondSize.percent;
    // The meeting point kept, sent again as it is; the password never kept, typed again (#189).
    _location = request.location;
    _password.clear();
    switch (request.amount) {
      case FixedOrderAmount(:final amount):
        _amount.text = _plain(amount.value);
        _rangeEnabled = false;
      case RangeOrderAmount(:final min, :final max):
        _minAmount.text = _plain(min.value);
        _maxAmount.text = _plain(max.value);
        _rangeEnabled = true;
    }
    _advanced =
        request.amount is RangeOrderAmount ||
        request.description != null ||
        request.publicDuration != MakerFormCheck.publicDurationDefault ||
        request.escrowDuration != MakerFormCheck.escrowDurationDefault ||
        request.bondSize.percent != MakerFormCheck.bondSizeDefault ||
        request.hasPassword;
  }

  @override
  void dispose() {
    _amount.dispose();
    _premium.dispose();
    _minAmount.dispose();
    _maxAmount.dispose();
    _description.dispose();
    _password.dispose();
    _scroll.dispose();
    if (!_gone.isCompleted) _gone.complete();
    super.dispose();
  }

  MakerFormInput _input(MakeOrderState state, {RobosatsCurrency? currency}) =>
      MakerFormInput(
        type: _type,
        currency: currency ?? state.currency,
        amount: _amount.text,
        paymentMethods: _methods,
        premium: _premium.text,
        advanced: _advanced,
        rangeEnabled: _rangeEnabled,
        minAmount: _minAmount.text,
        maxAmount: _maxAmount.text,
        description: _description.text,
        publicDuration: _publicDuration,
        escrowDuration: _escrowDuration,
        bondSizePercent: _bondSize,
        password: _password.text,
        location: _location,
      );

  /// The form as typed, judged in [currency] when given, else in the currency shown.
  MakerFormCheck _check(MakeOrderState state, {RobosatsCurrency? currency}) =>
      MakerFormCheck.of(
        _input(state, currency: currency),
        coordinatorsLoaded: state.coordinatorsLoaded,
        market: state.formLimits,
        sizeLimitSats: state.sizeLimitSats,
      );

  /// « Existing orders match yours! » (#186): the orders of the book that resemble the form ([MatchingOrders]), never one this device holds a trade of; none for a renewal, without a book, or while the device's trades are not listed (an order of this device could not be told apart).
  List<PublicOrder> _matchesOf(MakeOrderState state, MakerFormCheck check) {
    final book = widget.book;
    final active = widget.activeTrades;
    if (book == null || state.renewing || active is! ActiveTradesListed) {
      return const [];
    }
    return MatchingOrders.of(
      _input(state),
      check,
    ).apply(book, isOwn: (order) => active.holds(order, state.network));
  }

  /// « Submit » (`onSubmit`, `MakerPage/index.tsx:139-141`): the orders that match shown above the form, its fields folded away; nothing is sent and nothing is read.
  void _submit() {
    setState(() => _showMatches = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

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
        cubit.state.locked ||
        context.read<PendingMakesCubit>().state.blocksMaking ||
        _renewalMismatch(cubit.state, request) ||
        _renewalNeedsPassword(cubit.state)) {
      return;
    }
    setState(() {
      _asking = true;
      _stopped = null;
    });
    try {
      // A press while the Bull wallet's price is being read: its end awaited, the button busy (the shell bounds a read to 15 s), then the line it shows is the one the press is for (second security review of #181, R8). The press goes on when that line shows no warning, and stops only when it warns, is not priced or could not be read, and was not on screen at the press (third functional pass of #181, #182).
      if (cubit.state.price is MakeFormPriceReading) {
        await cubit.priceSettled();
        if (!mounted) return;
        final settled = cubit.seen();
        if (_check(cubit.state).request != request ||
            settled == null ||
            (!settled.sameLineAs(seen) &&
                settled.verdict.stopsPressFor(request.type))) {
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
      // A renewal sends at once, as the reference's (`TradeBox/index.tsx:146-200`): the page itself, with its summary, is what the user confirms (#185).
      if (!cubit.state.renewing) {
        final done = await StoreTokenDialog.show(context);
        if (!mounted || !done) return;
      }
      unawaited(cubit.make(request, coordinator: coordinator, seen: seen));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// Whether the form renews an order that had a password and « Password » is empty (#189): nothing is sent, said under the field and the button (`Prompts/Expired.tsx:84-89`).
  bool _renewalNeedsPassword(MakeOrderState state) =>
      switch (state.renewal) {
        MakeRenewalReady(:final renewal) => renewal.request.hasPassword,
        _ => false,
      } &&
      _password.text.isEmpty;

  /// Whether the form renews an order (#185) and [request], what the form judges its fields into, is not exactly the request kept of that order, or the kept terms are not filled yet: nothing is sent then, and the button says why.
  ///
  /// Requests are equal whatever the password's hash (`MakeOrderRequest ==`), which this device never kept: an order that had a password matches only with a password typed again (#189).
  bool _renewalMismatch(MakeOrderState state, MakeOrderRequest? request) {
    if (!state.renewing) return false;
    final filled = _filled;
    final shown = switch (state.renewal) {
      MakeRenewalReady(:final renewal) => renewal,
      _ => null,
    };
    return filled == null ||
        shown != filled ||
        (request != null && request != filled.request);
  }

  /// The amount typed: the Bull wallet's price is compared only once an amount above zero is typed (security review of #181), the range's maximum for a range (#183).
  void _amountChanged() {
    setState(() {});
    final value = FormNumber.read(
      _advanced && _rangeEnabled ? _maxAmount.text : _amount.text,
      maxDecimals: MakerFormCheck.amountDecimals,
    ).value;
    unawaited(
      context.read<MakeOrderCubit>().wantPrice(value != null && value > 0),
    );
  }

  /// The limit the chosen coordinator gives for [currency], when its limits are read.
  CurrencyLimit? _limitOf(MakeOrderState state, RobosatsCurrency currency) =>
      switch (state.limits) {
        MakerFormLimitsRead(:final limits) => limits[currency],
        _ => null,
      };

  /// [range] written in « From » and « to », as plain decimal numbers the fields read back as they are.
  void _setRange(MakerRange range) {
    _minAmount.text = _plain(range.min);
    _maxAmount.text = _plain(range.max);
  }

  /// « Enable advanced options » (`handleClickAdvanced`, `MakerForm.tsx:381-387`): closed, the range no longer applies and the other options keep their values, as the reference keeps and sends them; opened, the range set as the reference's `resetRange` sets it (`:394-411`), within the form's own limits so that it is never refused at once (#225).
  void _toggleAdvanced(MakeOrderState state) {
    setState(() {
      if (_advanced) {
        _advanced = false;
        return;
      }
      _advanced = true;
      final range = MakerRange.opening(
        amount: FormNumber.read(
          _amount.text,
          maxDecimals: MakerFormCheck.amountDecimals,
        ).value,
        limit: _limitOf(state, state.currency),
        limits: _check(state).limits,
      );
      if (range != null) _setRange(range);
    });
    _amountChanged();
  }

  /// « Amount Range » / « Exact Amount » (`handleClickAmountRangeEnabled`, `MakerForm.tsx:413-418`).
  void _toggleRange(bool range) {
    setState(() => _rangeEnabled = range);
    _amountChanged();
  }

  /// A thumb of the range's slider moved (`handleRangeAmountChange`, `AmountRange.tsx:79-117`).
  ///
  /// [previous] is what the slider showed (the bounds typed, held within the form's limits), so that the thumb moved is told from the one that stayed ([MakerRange.movedThumb]).
  void _slide(MakerRange previous, MakerRange next, MakerAmountLimits limits) {
    setState(
      () => _setRange(
        MakerRange.slid(
          moved: MakerRange.movedThumb(previous, next),
          next: next,
          limits: limits,
        ),
      ),
    );
    _amountChanged();
  }

  /// « Clear form » (`clearMaker`, `MakerForm.tsx:485-492`): no side chosen, the currency back to USD (`fav.currency` 0, which the form reads as USD), the amount, the payment methods and the premium emptied. The coordinator chosen stays: the reference puts back `defaultMaker.coordinator`, an alias drawn at random when its page loads, not its lottery's.
  void _clear() {
    setState(() {
      _type = null;
      _amount.clear();
      _premium.clear();
      _methods.clear();
      _stopped = null;
      // The advanced options back to the reference's defaults (`setMaker(defaultMaker)`, `:489`); « Amount Range » stays as it was, a state of its own there (`amountRangeEnabled`).
      _advanced = false;
      _minAmount.clear();
      _maxAmount.clear();
      _description.clear();
      // The password back to none (`defaultMaker`), the meeting point gone with the methods (`handlePaymentMethodChange([])`, `MakerForm.tsx:491`), #189.
      _password.clear();
      _location = null;
      _publicDuration = MakerFormCheck.publicDurationDefault;
      _escrowDuration = MakerFormCheck.escrowDurationDefault;
      _bondSize = MakerFormCheck.bondSizeDefault;
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
    // The currency shown chosen again is no change of currency: the range typed stays as it is (independent review of #226, C2).
    if (currency == state.currency) return;
    // A range out of the new currency's orders set again, as the reference does (`handleCurrencyChange`, `MakerForm.tsx:184-199`), and never left as one the form refuses in the new currency (#225).
    if (_advanced && _rangeEnabled) {
      final check = _check(state);
      final range = MakerRange.afterCurrency(
        min: check.rangeMin,
        max: check.rangeMax,
        limit: _limitOf(state, currency),
        limits: _check(state, currency: currency).limits,
      );
      if (range != null) setState(() => _setRange(range));
    }
    unawaited(context.read<MakeOrderCubit>().showCurrency(currency));
    _amountChanged();
  }

  Future<void> _chooseMethods() async {
    final l10n = P2pLocalizations.of(context);
    final before = List.of(_methods);
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
    if (mounted) _methodsChanged(before);
  }

  /// The methods chosen changed from [before] (`handlePaymentMethodChange`, `MakerForm.tsx:206-232`, #189): the meeting point stays only with a face-to-face method, and the map opens by itself when the last method is one, once the list that chooses them is closed.
  void _methodsChanged(List<String> before) {
    if (_sameMethods(before, _methods)) return;
    if (_location != null && !MeetingPoint.keptWith(_methods)) {
      setState(() => _location = null);
    }
    if (MeetingPoint.opensMap(_methods)) unawaited(_openMap());
  }

  static bool _sameMethods(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  /// « Face to Face Location » (`MakerForm.tsx:1002-1027`): the map, opened on the point saved; « Save » keeps the place pinned moved as the reference moves it, and puts « Cash F2F » first among the methods, as the reference does (`handleAddLocation`, `:494-513`).
  Future<void> _openMap() async {
    final point = await LocationMapDialog.show(
      context,
      initial: _location,
      primary: _type == OrderType.buy,
      draw: widget.locationDraws,
      openTiles: widget.openTiles,
      tiles: _locationTiles,
    );
    if (point == null || !mounted) return;
    setState(() {
      _location = point;
      final methods = MeetingPoint.methodsWithPoint(_methods);
      _methods
        ..clear()
        ..addAll(methods);
    });
  }

  Future<void> _addMethod() async {
    final method = await AddPaymentMethodDialog.show(context);
    if (method == null || !mounted) return;
    final before = List.of(_methods);
    setState(() {
      if (!_methods.any(
        (chosen) => CustomPaymentMethod.sameMethod(chosen, method.text),
      )) {
        _methods.add(method.text);
      }
    });
    _methodsChanged(before);
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
    final pending = context.watch<PendingMakesCubit>().state;
    final check = _check(state);
    final matches = _matchesOf(state, check);
    // The button reads « Submit » and only shows the orders that match while there are some and they are not shown (`MakerPage/index.tsx:137`, `:145`).
    final submits = matches.isNotEmpty && !_showMatches;
    final locked = state.locked || _asking;
    // A renewal's fields, currency and coordinator are its order's, never changed (#185).
    final renewing = state.renewing;
    final fieldsLocked = locked || renewing;
    final sending = state.progress is MakeSending;
    final coordinator = state.coordinator;
    final coordinatorName = coordinator == null
        ? ''
        : CoordinatorText.of(
            coordinator.longAlias,
            maxCodePoints: CoordinatorText.name,
          );
    // What the version of the chosen coordinator says of a protected order (#189).
    final exposure = switch (coordinator) {
      final host? => PasswordExposure.of(state.infos[host.shortAlias]),
      null => null,
    };
    // « Password » is in the form while the advanced options are open and the fields are not folded away; a password typed is sent either way (`buildOrderAttributes`, `MakerForm.tsx:273`).
    final passwordField = _advanced && !_showMatches;
    return MultiBlocListener(
      listeners: [
        BlocListener<MakeOrderCubit, MakeOrderState>(
          listenWhen: (previous, current) =>
              current.progress is MakeMade && previous.progress is! MakeMade,
          listener: (_, current) {
            if (current.progress case MakeMade(:final record)) {
              widget.onMade(record);
            }
          },
        ),
        // A new make sent: the line of the last make a resolution closed goes, so that it is never read as the new make's outcome (seen in a real trial); a press stopped before the make starts keeps it.
        BlocListener<MakeOrderCubit, MakeOrderState>(
          listenWhen: (previous, current) =>
              current.progress is MakeSending &&
              previous.progress is! MakeSending,
          listener: (context, _) =>
              context.read<PendingMakesCubit>().forgetClosed(),
        ),
        // The last pending make of the network resolved or set aside: a form locked by an outcome unknown is free again (#182, functional review C1).
        BlocListener<PendingMakesCubit, PendingMakesState>(
          listenWhen: (previous, current) =>
              (previous.makes?.isNotEmpty ?? false) &&
              !current.unreadable &&
              (current.makes?.isEmpty ?? false),
          listener: (context, _) =>
              context.read<MakeOrderCubit>().pendingCleared(),
        ),
        // A renewal's kept terms read: written in the fields (#185).
        BlocListener<MakeOrderCubit, MakeOrderState>(
          listenWhen: (previous, current) =>
              previous.renewal is! MakeRenewalReady &&
              current.renewal is MakeRenewalReady,
          listener: (_, current) {
            if (current.renewal case MakeRenewalReady(:final renewal)) {
              setState(() => _fill(renewal));
            }
          },
        ),
        // A renewal's own make ended without an order, closed by a resolution or set aside: its page free again (security review of #220, N1).
        BlocListener<PendingMakesCubit, PendingMakesState>(
          listenWhen: (previous, current) =>
              current.ended != null && previous.ended != current.ended,
          listener: (context, current) {
            if (current.ended case final robot?) {
              context.read<MakeOrderCubit>().pendingEnded(robot);
            }
          },
        ),
        // A pending make a resolution confirmed: its trade, as an order made (#182); on a renewal's page, only the renewal's own make, which the cubit tells (#217, security review of #185, R3).
        BlocListener<PendingMakesCubit, PendingMakesState>(
          listenWhen: (previous, current) =>
              current.started != null && previous.started != current.started,
          listener: (context, current) {
            if (current.started case final record?) {
              final cubit = context.read<MakeOrderCubit>();
              if (cubit.state.renewing) {
                unawaited(cubit.pendingStarted(record));
              } else {
                widget.onMade(record);
              }
            }
          },
        ),
      ],
      // While the make is sent, the page stays: going back would leave the order made without the user being taken to it (security review of #181, S1; #182); a line says why.
      child: PopScope(
        canPop: !sending,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && sending) setState(() => _leaveTried = true);
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
                  title: renewing ? l10n.p2pRenewOrder : l10n.p2pNavCreate,
                  onBack: () {
                    if (sending) {
                      setState(() => _leaveTried = true);
                    } else if (context.canPop()) {
                      context.pop();
                    }
                  },
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(BullSpacing.md),
                    children: switch (state.renewal) {
                      // A renewal whose kept terms are being read, or cannot be (#185): nothing else is shown, nothing can be sent.
                      MakeRenewalReading() => [
                        const Center(child: CircularProgressIndicator()),
                      ],
                      MakeRenewalRefused(:final refusal) => [
                        _Line(
                          refusal.toText(context),
                          color: colors.warning,
                          live: true,
                        ),
                      ],
                      MakeRenewalNone() || MakeRenewalReady() => [
                        if (state.renewal case MakeRenewalReady(
                          :final renewal,
                        )) ...[
                          _Line(l10n.p2pRenewIntro(renewal.orderId.toString())),
                          const Gap(BullSpacing.md),
                        ],
                        // Above the form, as the reference's (`MakerPage/index.tsx:105-125`), while « Submit » showed them and some match.
                        if (_showMatches && matches.isNotEmpty) ...[
                          _Matches(
                            orders: matches,
                            now: widget.now(),
                            onOpen: switch (widget.onOpenOrder) {
                              final open? when !locked => open,
                              _ => null,
                            },
                          ),
                          const Gap(BullSpacing.md),
                        ],
                        // The network's pending makes, resolved when the form opens: the form makes nothing while one is listed (#182).
                        if (pending.unreadable ||
                            (pending.makes?.isNotEmpty ?? false)) ...[
                          _Line(
                            l10n.p2pMakePendingFirst,
                            color: colors.warning,
                          ),
                          const PendingMakeLines(),
                          const Gap(BullSpacing.md),
                        ] else if (pending.closed != null) ...[
                          // The last pending make found not made: said once, the form free again (functional review C1).
                          const PendingMakeLines(),
                          const Gap(BullSpacing.md),
                        ],
                        // The fields folded away while the orders that match are shown (`collapseAll`, `MakerForm.tsx:674-723`, `:725-1261`); the coordinator, the summary, the button and the rate stay, as in the reference.
                        if (!_showMatches) ...[
                          _AdvancedOptions(
                            onClear: fieldsLocked ? null : _clear,
                            advanced: _advanced,
                            loading:
                                !state.coordinatorsLoaded ||
                                state.limits is MakerFormLimitsLoading,
                            // Opened only once the coordinator's limits are read, as the reference's switch (`MakerForm.tsx:710`); closed at any time.
                            onToggle:
                                fieldsLocked ||
                                    (!_advanced &&
                                        (!state.coordinatorsLoaded ||
                                            state.limits
                                                is! MakerFormLimitsRead))
                                ? null
                                : () => _toggleAdvanced(state),
                          ),
                          const Gap(BullSpacing.md),
                          _Side(
                            type: _type,
                            enabled: !fieldsLocked,
                            // As the reference's « Buy » and « Sell », a choice, never a toggle (`MakerForm.tsx:766-775`, `:800-809`).
                            onChoose: (side) => setState(() => _type = side),
                          ),
                          const Gap(BullSpacing.md),
                          if (_advanced) ...[
                            _RangeSwitch(
                              range: _rangeEnabled,
                              onChanged: fieldsLocked ? null : _toggleRange,
                            ),
                            const Gap(BullSpacing.xs),
                          ],
                          if (check.hasRange)
                            _AmountRange(
                              min: _minAmount,
                              max: _maxAmount,
                              check: check,
                              coordinator: coordinatorName,
                              currency: state.currency,
                              enabled: !fieldsLocked,
                              onChanged: _amountChanged,
                              onCurrency: () =>
                                  unawaited(_chooseCurrency(state)),
                              onSlide: _slide,
                            )
                          else
                            _Amount(
                              controller: _amount,
                              currency: state.currency,
                              problem: check.amountProblem,
                              enabled: !fieldsLocked,
                              onChanged: _amountChanged,
                              onCurrency: () =>
                                  unawaited(_chooseCurrency(state)),
                            ),
                          const Gap(BullSpacing.md),
                          _Methods(
                            methods: _methods,
                            tooLong: check.badPaymentMethod,
                            enabled: !fieldsLocked,
                            onChoose: () => unawaited(_chooseMethods()),
                            onAdd: () => unawaited(_addMethod()),
                            onRemove: (method) {
                              final before = List.of(_methods);
                              setState(() => _methods.remove(method));
                              _methodsChanged(before);
                            },
                          ),
                          const Gap(BullSpacing.md),
                          _Location(
                            location: _location,
                            enabled: !fieldsLocked,
                            onOpen: () => unawaited(_openMap()),
                            onRemove: () => setState(() => _location = null),
                          ),
                          const Gap(BullSpacing.md),
                          _PremiumField(
                            controller: _premium,
                            problem: check.premiumProblem,
                            enabled: !fieldsLocked,
                            onChanged: () => setState(() {}),
                          ),
                          const Gap(BullSpacing.md),
                          if (_advanced) ...[
                            _Description(
                              controller: _description,
                              check: check,
                              enabled: !fieldsLocked,
                              onChanged: () => setState(() {}),
                            ),
                            const Gap(BullSpacing.md),
                            _Password(
                              controller: _password,
                              // The only field of a renewal that can be typed, for an order that had a password (#189).
                              enabled: renewing
                                  ? !locked &&
                                        switch (state.renewal) {
                                          MakeRenewalReady(:final renewal) =>
                                            renewal.request.hasPassword,
                                          _ => false,
                                        }
                                  : !fieldsLocked,
                              renewing: renewing,
                              needed: _renewalNeedsPassword(state),
                              exposure: exposure,
                              coordinator: coordinatorName,
                              onChanged: () => setState(() {}),
                            ),
                            const Gap(BullSpacing.md),
                            _DurationField(
                              label: l10n.p2pMakePublicDuration,
                              title: l10n.p2pMakePublicDurationTitle,
                              value: _publicDuration,
                              enabled: !fieldsLocked,
                              onPicked: (picked) => setState(
                                () => _publicDuration =
                                    MakerFormCheck.publicDurationOf(picked),
                              ),
                            ),
                            const Gap(BullSpacing.md),
                            _DurationField(
                              label: l10n.p2pMakeEscrowDuration,
                              title: l10n.p2pMakeEscrowDurationTitle,
                              value: _escrowDuration,
                              enabled: !fieldsLocked,
                              onPicked: (picked) => setState(
                                () => _escrowDuration =
                                    MakerFormCheck.escrowDurationOf(picked),
                              ),
                            ),
                            const Gap(BullSpacing.md),
                            _BondSizeSlider(
                              value: _bondSize,
                              onChanged: fieldsLocked
                                  ? null
                                  : (value) => setState(
                                      () => _bondSize =
                                          MakerFormCheck.bondSizeOf(value),
                                    ),
                            ),
                            const Gap(BullSpacing.md),
                          ],
                        ],
                        _Coordinator(
                          state: state,
                          name: coordinatorName,
                          enabled: !locked && state.coordinatorsLoaded,
                          // A renewal goes to its order's coordinator, with no « Select Host » (#185); « Retry » stays.
                          chooses: !renewing,
                          onTap: () => unawaited(_chooseHost(state)),
                        ),
                        const Gap(BullSpacing.md),
                        _Summary(
                          type: _type,
                          check: check,
                          state: state,
                          advanced: _advanced,
                        ),
                        // The alert of a coordinator older than 0.8.7, or of unknown version, while a password is sent and its field is not in the form: options closed, or fields folded away by « Existing orders match yours! » (independent review of #189, C1); under the field otherwise, never both.
                        if (!passwordField &&
                            _password.text.isNotEmpty &&
                            exposure != null) ...[
                          const Gap(BullSpacing.xs),
                          _ExposureAlert(
                            exposure: exposure,
                            coordinator: coordinatorName,
                          ),
                        ],
                        const Gap(BullSpacing.md),
                        _CreateButton(
                          check: check,
                          state: state,
                          pendingFirst: pending.blocksMaking,
                          pendingShown:
                              pending.unreadable ||
                              (pending.makes?.isNotEmpty ?? false),
                          leaveTried: sending && _leaveTried,
                          asking: _asking,
                          stopped: _stopped,
                          renewalMismatch: _renewalMismatch(
                            state,
                            check.request,
                          ),
                          renewalNeedsPassword: _renewalNeedsPassword(state),
                          renewing: renewing,
                          coordinator: coordinatorName,
                          submits: submits,
                          onPressed: submits
                              ? _submit
                              : () => unawaited(_press()),
                          onEdit: _showMatches
                              ? () => setState(() => _showMatches = false)
                              : null,
                        ),
                        const Gap(BullSpacing.md),
                        _Rate(
                          check: check,
                          state: state,
                          coordinator: coordinatorName,
                          type: _type,
                        ),
                      ],
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The reference's first row (`MakerForm.tsx:674-723`): « Clear form » at the left, a bin with its tooltip, then « Enable advanced options » with its switch, a wait shown while the coordinators or the limits are being read, as the reference's spinner (`:714-718`).
class _AdvancedOptions extends StatelessWidget {
  /// « Clear form »; `null` while the form is locked.
  final VoidCallback? onClear;

  /// Whether the options are open, and the switch; `null` while it cannot be used.
  final bool advanced;
  final bool loading;
  final VoidCallback? onToggle;

  const _AdvancedOptions({
    required this.onClear,
    required this.advanced,
    required this.loading,
    required this.onToggle,
  });

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
                  child: Text(
                    l10n.p2pMakeEnableAdvanced,
                    style: text.bodyLarge?.copyWith(
                      color: onToggle == null ? colors.textMuted : colors.text,
                    ),
                  ),
                ),
                if (loading && !advanced)
                  const Padding(
                    padding: EdgeInsets.only(right: BullSpacing.xs),
                    child: SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Switch(
                  value: advanced,
                  onChanged: switch (onToggle) {
                    final toggle? => (_) => toggle(),
                    null => null,
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// « Buy or Sell Bitcoin? * », « Buy » and « Sell » (`MakerForm.tsx:750-827`), each a choice, never a toggle (#188: « Sell » enabled).
class _Side extends StatelessWidget {
  final OrderType? type;
  final bool enabled;
  final ValueChanged<OrderType> onChoose;

  const _Side({
    required this.type,
    required this.enabled,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    Widget choice(OrderType side, String label) => Expanded(
      child: Semantics(
        selected: type == side,
        child: TradeButton(
          label: label,
          outlined: type != side,
          onPressed: enabled ? () => onChoose(side) : null,
        ),
      ),
    );
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
            choice(OrderType.buy, l10n.p2pMakeBuy),
            const Gap(BullSpacing.sm),
            choice(OrderType.sell, l10n.p2pMakeSell),
          ],
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

  /// Whether « Select Host » can be opened: not for a renewal (#185).
  final bool chooses;
  final VoidCallback onTap;

  const _Coordinator({
    required this.state,
    required this.name,
    required this.enabled,
    required this.chooses,
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
    final opens = enabled && chooses;
    return Semantics(
      button: true,
      enabled: opens,
      label: l10n.p2pMakeChooseHost,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BullRadius.xxs),
          side: BorderSide(color: colors.outline),
        ),
        child: InkWell(
          onTap: opens ? onTap : null,
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
                if (chooses)
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

  /// Whether the advanced options are open: the line of the options sent is information then, in the warning colour while they are closed, where they are seen nowhere else.
  final bool advanced;

  const _Summary({
    required this.type,
    required this.check,
    required this.state,
    required this.advanced,
  });

  /// The line that names the advanced options sent that differ from the defaults (security review of #183, C1), or `null` when all are at their defaults: that a description is attached (never its text), the public duration, the escrow timer and the bond size.
  static String? optionsLine(
    BuildContext context,
    MakerOptionsSent sent, {
    required bool advanced,
  }) {
    if (!sent.any) return null;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final options = [
      if (sent.description) l10n.p2pMakeOptionSentDescription,
      if (sent.password) l10n.p2pMakeOptionSentPassword,
      if (sent.publicDuration case final duration?)
        l10n.p2pMakeOptionSentPublicDuration(_DurationField.hhmm(duration)),
      if (sent.escrowDuration case final duration?)
        l10n.p2pMakeOptionSentEscrowDuration(_DurationField.hhmm(duration)),
      if (sent.bondSizePercent case final percent?)
        l10n.p2pMakeOptionSentBondSize(
          l10n.p2pMakeBondSizeValue(formats.number(percent)),
        ),
    ].join(', ');
    return advanced
        ? l10n.p2pMakeOptionsSentOpen(options)
        : l10n.p2pMakeOptionsSentClosed(options);
  }

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
      OrderType.sell => l10n.p2pMakeSellBtcFor,
    };
    final price = premium == 0
        ? l10n.p2pMakeAtMarketPrice
        : premium > 0
        ? l10n.p2pMakeAtPremium(formats.number(premium))
        : l10n.p2pMakeAtDiscount(formats.number(-premium));
    final bond = check.estimatedBond;
    // A range as the reference writes it, « min-max » (`amountToString`, `utils/prettyNumbers.ts:13-28`), each bound with all the decimals sent.
    final amount = check.hasRange
        ? '${formats.typedNumber(check.rangeMin)}-${formats.typedNumber(check.rangeMax)}'
        : formats.typedNumber(check.amount);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        children: [
          Text(
            '$start$amount ${state.currency.code}$price',
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
          if (optionsLine(context, check.optionsSent, advanced: advanced)
              case final line?) ...[
            const Gap(BullSpacing.xxs),
            Text(
              line,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                color: advanced ? colors.textMuted : colors.warning,
              ),
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
///
/// « Submit » in its place while orders match and are not shown (#186, `MakerPage/index.tsx:145`), with the same reason when disabled; « Edit order », a pencil beside it, while they are shown (`MakerForm.tsx:1314-1330`).
class _CreateButton extends StatelessWidget {
  final MakerFormCheck check;
  final MakeOrderState state;
  final bool asking;

  /// Whether a pending make of the network is listed, or the records cannot tell (#182): nothing is made beside it.
  final bool pendingFirst;

  /// Whether one is known to be listed, or the records are known unreadable: only then is the reason said (while they are being read, the button is off and nothing is said, functional review R6).
  final bool pendingShown;

  /// Whether going back was tried while the make is sent: the line that says to wait is under the button, where the user is (functional review R7).
  final bool leaveTried;

  /// Why the last press stopped, the form showing something else.
  final _PressStopped? stopped;

  /// Whether a renewal's fields are not judged into exactly its kept request (#185): nothing can be sent, and a line says so.
  final bool renewalMismatch;

  /// Whether a renewal of an order that had a password waits for it to be typed again (#189): the line says so, in place of [renewalMismatch]'s.
  final bool renewalNeedsPassword;

  /// Whether the form renews an order (#185): its fields cannot be changed, so a refusal the user could correct in a creation says what to do instead (functional review of #185, R3).
  final bool renewing;
  final String coordinator;

  /// Whether the button reads « Submit », which only shows the orders that match (#186).
  final bool submits;
  final VoidCallback onPressed;

  /// « Edit order », while the orders that match are shown; `null` otherwise.
  final VoidCallback? onEdit;

  const _CreateButton({
    required this.check,
    required this.state,
    required this.pendingFirst,
    required this.pendingShown,
    required this.leaveTried,
    required this.asking,
    required this.stopped,
    required this.renewalMismatch,
    required this.renewalNeedsPassword,
    required this.renewing,
    required this.coordinator,
    required this.submits,
    required this.onPressed,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final progress = state.progress;
    final block = check.block;
    final ready =
        block == null &&
        progress is MakeIdle &&
        !pendingFirst &&
        !renewalMismatch &&
        !renewalNeedsPassword;
    final button = TradeButton(
      label: submits ? l10n.p2pMakeSubmit : l10n.p2pMakeCreateOrder,
      busy: asking || progress is MakeSending,
      onPressed: ready ? onPressed : null,
    );
    final formats = P2pFormats.of(context);
    // A range refused says why, as its box does (#225); every other reason in the reference's words.
    final why = switch ((block, check.rangeProblem)) {
      (MakerFormBlock.amountRangeInvalid, final problem?) when !renewing =>
        problem.toText(
          context,
          coordinator: coordinator,
          amountOf: (amount) =>
              '${formats.typedNumber(amount)} ${state.currency.code}',
        ),
      (final block?, _) => block.toText(context),
      (null, _) => null,
    };
    final lines = <Widget>[
      if (why != null && progress is MakeIdle) _Line(why, live: true),
      if (block == null && renewalNeedsPassword && progress is MakeIdle)
        _Line(l10n.p2pRenewPasswordAgain, color: colors.error, live: true)
      else if (block == null && renewalMismatch && progress is MakeIdle)
        _Line(l10n.p2pRenewNotAsKept, color: colors.warning, live: true),
      // A renewal the form or the make refuses for its kept terms, which cannot be changed here: what to do (functional review of #185, R3).
      if (renewing &&
          progress is MakeIdle &&
          _renewalStuck(
            block,
            progress,
            limitsRead: state.limits is MakerFormLimitsRead,
          ))
        _Line(l10n.p2pRenewNoLongerAsKept, color: colors.warning, live: true),
      // A renewal whose coordinator's limits could not be read: « Select Host » is not offered, so « Retry » reads them again.
      if (renewing &&
          progress is MakeIdle &&
          block == MakerFormBlock.limitsUnavailable &&
          state.coordinator != null)
        TradeButton(
          label: l10n.p2pCommonRetry,
          outlined: true,
          onPressed: () =>
              unawaited(context.read<MakeOrderCubit>().retryLimits()),
        ),
      // A pending make of the network first (#182): said under the button too, where the reason of a disabled button is.
      if (block == null && pendingShown && progress is MakeIdle)
        _Line(l10n.p2pMakePendingFirst, live: true),
      if (leaveTried && progress is MakeSending)
        _Line(
          l10n.p2pMakeSendingStay(coordinator),
          color: colors.warning,
          live: true,
        ),
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
      // An order confirmed on a renewal's page that could not be told this renewal's: nothing more from here, and how to go on (security review of #220, R1, N1).
      if (progress case MakeUncertain(unverified: true))
        _Line(l10n.p2pRenewUnverified, color: colors.warning, live: true)
      else if (progress is MakeUncertain) ...[
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
    final shown = why == null
        ? button
        : Tooltip(
            message: why,
            triggerMode: TooltipTriggerMode.tap,
            child: button,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (onEdit) {
          final edit? => Row(
            children: [
              Expanded(child: shown),
              const Gap(BullSpacing.xs),
              IconButton(
                tooltip: l10n.p2pMakeEditOrder,
                onPressed: edit,
                color: colors.textMuted,
                icon: const Icon(Icons.edit),
              ),
            ],
          ),
          null => shown,
        },
        for (final line in lines) ...[const Gap(BullSpacing.xs), line],
      ],
    );
  }
}

/// Whether a renewal is refused for its kept terms, which the user cannot change on its page (functional review of #185, R3): every reason of the form ([block]) but a wait or the coordinator's limits not read, and « The Bitcoin price is not synchronized. » once the limits were read ([limitsRead]: the coordinator gives no usable price for the order's currency); or a make refused for its terms ([progress]: the amount outside the limits, no price for the currency, terms the make refuses).
bool _renewalStuck(
  MakerFormBlock? block,
  MakeIdle progress, {
  required bool limitsRead,
}) {
  if (block != null) {
    return switch (block) {
      MakerFormBlock.loadingCoordinators ||
      MakerFormBlock.limitsUnavailable => false,
      MakerFormBlock.priceNotSynchronized => limitsRead,
      _ => true,
    };
  }
  return switch (progress.problem) {
    MakeWasRefused(
      refusal: MakeAmountOutsideLimits() ||
          MakePriceUnknown() ||
          MakeTermsRefused(),
    ) =>
      true,
    _ => false,
  };
}

/// « Existing orders match yours! » and the orders that match (#186, `MakerPage/index.tsx:105-125`): the reference's title, then every order that matches, as the book shows its offers ([OfferRow]), in the reference's order; a tap opens the order, to take it instead.
///
/// The rows scroll in a box at most [heightShare] of the screen high, as the reference's table scrolls in a box at most 68 % of its window (`MakerPage/index.tsx:82`, its `Paper` with `overflow: 'auto'`, `BookTable/index.tsx:991-1013`), so that however many match, the page goes on below it with the coordinator, the summary, « Create order » and « Edit order ». The reference's table shows as many rows as it counts in its height and lets the others be reached by sorting a column (its header is kept); here every row that matches is listed, the list bounded by the book's own read bounds (`read_bounds.dart`, 1,000 orders per coordinator).
class _Matches extends StatelessWidget {
  /// The highest share of the screen the rows take (`windowSize.height * 0.68`, `MakerPage/index.tsx:82`).
  static const double heightShare = 0.68;

  final List<PublicOrder> orders;
  final DateTime now;

  /// Opens an order; `null` while the form is locked, a make running or run.
  final ValueChanged<PublicOrder>? onOpen;

  const _Matches({required this.orders, required this.now, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final open = onOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            l10n.p2pMakeMatchesFound,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: colors.text),
          ),
        ),
        const Gap(BullSpacing.xs),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * heightShare,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return OfferRow(
                key: ValueKey((order.coordinator.shortAlias, order.id)),
                order: order,
                now: now,
                onTap: open == null ? null : () => open(order),
              );
            },
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colors.outlineVariant),
          ),
        ),
      ],
    );
  }
}

/// « Order current rate: … {{currencyCode}}/BTC » with its tooltip (`MakerForm.tsx:1340-1363`), then the Bull wallet's indicative price for comparison and, beyond the owner's threshold on the side that costs the maker of the side chosen ([MakePriceCheck.warnsFor]: either way for a buyer or no side, below only for a seller, #188), a red warning in that maker's words; for a currency the Bull wallet does not price, or a price it could not read, a line in the warning colour (with « Retry » for the latter). None of it stops « Create order ».
class _Rate extends StatelessWidget {
  final MakerFormCheck check;
  final MakeOrderState state;
  final String coordinator;

  /// The side chosen: a seller is warned of a price too low only, in a seller's words.
  final OrderType? type;

  const _Rate({
    required this.check,
    required this.state,
    required this.coordinator,
    required this.type,
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
            final warns = check.warnsFor(type);
            children.add(_Line(line, color: warns ? colors.error : null));
            if (warns) {
              final selling = type == OrderType.sell;
              children.add(
                _Alert(switch (check.side) {
                  MakePriceSide.below when selling => l10n.p2pMakeRateBelowSell(
                    coordinator,
                    threshold,
                  ),
                  MakePriceSide.below => l10n.p2pMakeRateBelow(
                    coordinator,
                    threshold,
                  ),
                  MakePriceSide.above || MakePriceSide.within =>
                    l10n.p2pMakeRateAbove(coordinator, threshold),
                }, colors.error),
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

  /// Whether it is read out when it appears or changes.
  final bool live;

  const _Alert(this.text, this.color, {this.live = true});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: live,
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

/// [value] as a plain decimal number, with at most the amount's decimals and no exponent, as « From » and « to » read it back ([FormNumber]).
String _plain(double value) {
  final fixed = value.toStringAsFixed(MakerFormCheck.amountDecimals);
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// « Amount Range » / « Exact Amount » (`MakerForm.tsx:831-850`): a switch whose label says what is chosen.
class _RangeSwitch extends StatelessWidget {
  final bool range;
  final ValueChanged<bool>? onChanged;

  const _RangeSwitch({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          Switch(value: range, onChanged: onChanged),
          const Gap(BullSpacing.xs),
          Expanded(
            child: Text(
              range ? l10n.p2pMakeAmountRange : l10n.p2pMakeExactAmount,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The range (`AmountRange.tsx`): « From » … « to » and the currency, then the reference's slider over the form's limits (continuous here), its two ends marked with them (3 significant digits), each thumb's value shown as it moves (2 significant digits below 100, 3 from 100).
class _AmountRange extends StatelessWidget {
  final TextEditingController min;
  final TextEditingController max;
  final MakerFormCheck check;

  /// The coordinator's name, for the rules of the range and the reason of a range refused (#225).
  final String coordinator;
  final RobosatsCurrency currency;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onCurrency;
  final void Function(
    MakerRange previous,
    MakerRange next,
    MakerAmountLimits limits,
  )
  onSlide;

  const _AmountRange({
    required this.min,
    required this.max,
    required this.check,
    required this.coordinator,
    required this.currency,
    required this.enabled,
    required this.onChanged,
    required this.onCurrency,
    required this.onSlide,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final limits = check.limits;
    final code = currency.code;
    String bound(double value, int digits) =>
        '${formats.typedNumber(significant(value, digits))} $code';
    final label = text.labelLarge?.copyWith(color: colors.textMuted);
    // Why the range typed is refused, with the bound the form takes, where the fields are (#225): the reference only draws the field at fault in red.
    // Not for fields that cannot be typed (a renewal's, a form being sent): the line under the button says what to do then.
    final problem = enabled
        ? check.rangeProblem?.toText(
            context,
            coordinator: coordinator,
            amountOf: (amount) => '${formats.typedNumber(amount)} $code',
          )
        : null;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(child: Text(l10n.p2pMakeFrom, style: label)),
                const Gap(BullSpacing.xs),
                Expanded(
                  child: _RangeField(
                    label: l10n.p2pMakeFrom,
                    controller: min,
                    error: check.rangeMinError,
                    enabled: enabled,
                    onChanged: onChanged,
                  ),
                ),
                const Gap(BullSpacing.xs),
                ExcludeSemantics(child: Text(l10n.p2pMakeTo, style: label)),
                const Gap(BullSpacing.xs),
                Expanded(
                  child: _RangeField(
                    label: l10n.p2pMakeTo,
                    controller: max,
                    error: check.rangeMaxError,
                    enabled: enabled,
                    onChanged: onChanged,
                  ),
                ),
                const Gap(BullSpacing.xs),
                FilterChoice(
                  label: code,
                  semanticsLabel: '${l10n.p2pBookFilterSubjectCurrency}: $code',
                  onTap: enabled ? onCurrency : () {},
                ),
              ],
            ),
            if (problem != null) ...[
              const Gap(BullSpacing.xs),
              // Read out once, by the line under the button, not here too (independent review of #226, C3).
              _Alert(problem, colors.error, live: false),
            ],
            if (limits != null && limits.max > limits.min) ...[
              const Gap(BullSpacing.xs),
              Builder(
                builder: (context) {
                  double within(double value) =>
                      value.clamp(limits.min, limits.max).toDouble();
                  final start = within(check.rangeMin);
                  final end = within(check.rangeMax);
                  final values = RangeValues(start <= end ? start : end, end);
                  String thumb(double value) =>
                      bound(value, value < 100 ? 2 : 3);
                  // Continuous, where the reference's step is a 5,000th of the span (`AmountRange.tsx:236`): the bounds are rounded to 2 or 3 significant digits anyway, and a grid would move the thumb left alone at each move (Flutter's `RangeSlider` puts both values back on it), which [MakerRange.movedThumb] would then have to tell apart from a drag.
                  return SliderTheme(
                    data: SliderTheme.of(
                      context,
                    ).copyWith(showValueIndicator: ShowValueIndicator.onDrag),
                    child: RangeSlider(
                      values: values,
                      min: limits.min,
                      max: limits.max,
                      labels: RangeLabels(
                        thumb(values.start),
                        thumb(values.end),
                      ),
                      onChanged: enabled
                          ? (next) => onSlide(
                              MakerRange(values.start, values.end),
                              MakerRange(next.start, next.end),
                              limits,
                            )
                          : null,
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bound(limits.min, 3), style: text.labelMedium),
                  Text(bound(limits.max, 3), style: text.labelMedium),
                ],
              ),
              // What the two amounts under the slider are (#225), which the reference leaves to be guessed.
              const Gap(BullSpacing.xs),
              Text(
                l10n.p2pMakeRangeAccepted(
                  coordinator,
                  formats.typedNumber(significant(limits.min, 3)),
                  bound(limits.max, 3),
                ),
                style: text.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
            // How far apart the bounds may be (#225): said whenever a range is typed, with or without the slider.
            if (limits == null || limits.max <= limits.min)
              const Gap(BullSpacing.xs),
            Text(
              l10n.p2pMakeRangeRatio,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// « From » or « to »: a number field without a label of its own (the words around it are), red when the reference marks it (`AmountRange.tsx:163`, `:194`).
class _RangeField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool error;
  final bool enabled;
  final VoidCallback onChanged;

  const _RangeField({
    required this.label,
    required this.controller,
    required this.error,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final edge = error ? colors.error : colors.outline;
    return Semantics(
      container: true,
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        inputFormatters: [
          LengthLimitingTextInputFormatter(FormNumber.maxLength),
          const _DecimalsFormatter(MakerFormCheck.amountDecimals),
        ],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: error ? colors.error : colors.text,
        ),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: colors.surface,
          enabledBorder: _border(edge),
          disabledBorder: _border(colors.outline),
          focusedBorder: _border(error ? colors.error : colors.primary),
        ),
      ),
    );
  }
}

/// « See details » under a field, which unfolds [lines], the explanation shown only on demand (the owner's rule of 2026-11-20: screens kept bare), and folds them again (#189).
class _Details extends StatefulWidget {
  final List<String> lines;

  const _Details(this.lines);

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          excludeSemantics: true,
          label: _open ? l10n.p2pMakeHideDetails : l10n.p2pMakeSeeDetails,
          onTap: () => setState(() => _open = !_open),
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(BullRadius.xxs),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _open ? l10n.p2pMakeHideDetails : l10n.p2pMakeSeeDetails,
                      style: text.labelLarge?.copyWith(color: colors.primary),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          for (final line in widget.lines) ...[
            Text(
              line,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const Gap(BullSpacing.xxs),
          ],
      ],
    );
  }
}

/// « Face to Face Location » (`MakerForm.tsx:1002-1027`), where the reference puts it, under the payment methods, with its tooltip: a tap opens the map (#189). Once a point is saved, the point the order sends, already moved, in one line with a cross that removes it (the reference removes it only with the last face-to-face method), and « See details »: the reference's line on the randomization, what is published, and that nothing of the device's position is read.
class _Location extends StatelessWidget {
  final OrderLocation? location;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const _Location({
    required this.location,
    required this.enabled,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final point = location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: l10n.p2pMakeLocationHint,
          child: OutlinedButton.icon(
            onPressed: enabled ? onOpen : null,
            icon: const Icon(Icons.map_outlined),
            iconAlignment: IconAlignment.end,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(48),
              foregroundColor: colors.textMuted,
              side: BorderSide(color: colors.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BullRadius.xxs),
              ),
            ),
            label: Text(l10n.p2pMakeLocation),
          ),
        ),
        if (point != null) ...[
          const Gap(BullSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.p2pMakeLocationSent(
                    meetingPointText(point.latitude, point.longitude),
                  ),
                  style: text.bodyMedium?.copyWith(color: colors.text),
                ),
              ),
              if (enabled)
                IconButton(
                  tooltip: l10n.p2pMakeLocationRemove,
                  onPressed: onRemove,
                  color: colors.textMuted,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          _Details([
            l10n.p2pMakeLocationRandomized,
            l10n.p2pMakeLocationDetail,
          ]),
        ],
      ],
    );
  }
}

/// The alert of a protected order on a coordinator older than 0.8.7, or whose version could not be read (#189): one short line in the warning colour, never a lock; with [details], « See details » unfolds its explanation (the field's own details hold it under « Password »).
class _ExposureAlert extends StatelessWidget {
  final PasswordExposure exposure;
  final String coordinator;
  final bool details;

  const _ExposureAlert({
    required this.exposure,
    required this.coordinator,
    this.details = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final text = switch (exposure) {
      PasswordExposedByVersion(:final version) =>
        l10n.p2pMakePasswordOldCoordinator(coordinator, '$version'),
      PasswordExposureUnknown() => l10n.p2pMakePasswordUnknownVersion(
        coordinator,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Alert(text, context.bull.warning),
        if (details) _Details([l10n.p2pMakePasswordOldDetail]),
      ],
    );
  }
}

/// « Password » (`MakerForm.tsx:1085-1113`) with the reference's tooltip (#189): typed hidden, sent as its SHA-256.
///
/// Once a password is typed, one short line (out of the book, taken with the official app), the alert of a coordinator older than 0.8.7 or of unknown version in one line when there is one ([exposure], never a lock), and « See details »: the reference's help, how to share the order, what stays readable of it, that only the hash leaves and is not kept. In a renewal of an order that had a password ([needed] while it is empty), the reference's « Enter a password again » under the field in the colour of an error (`Prompts/Expired.tsx:49-58`), and the detail that the same password is needed.
class _Password extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool renewing;
  final bool needed;
  final PasswordExposure? exposure;
  final String coordinator;
  final VoidCallback onChanged;

  const _Password({
    required this.controller,
    required this.enabled,
    required this.renewing,
    required this.needed,
    required this.exposure,
    required this.coordinator,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final typed = controller.text.isNotEmpty;
    final exposure = typed ? this.exposure : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: l10n.p2pMakePasswordHint,
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: true,
            // A secret, not words: nothing suggested, corrected or learnt by the keyboard.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.text),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: l10n.p2pMakePassword,
              errorText: needed ? l10n.p2pRenewPasswordAgain : null,
              filled: true,
              fillColor: colors.surface,
              enabledBorder: _border(colors.outline),
              disabledBorder: _border(colors.outline),
              focusedBorder: _border(colors.primary),
              errorBorder: _border(colors.error),
              focusedErrorBorder: _border(colors.error),
            ),
          ),
        ),
        if (typed) ...[
          const Gap(BullSpacing.xxs),
          Text(
            l10n.p2pMakePasswordLine,
            style: text.bodyMedium?.copyWith(color: colors.text),
          ),
        ],
        if (exposure != null) ...[
          const Gap(BullSpacing.xs),
          _ExposureAlert(
            exposure: exposure,
            coordinator: coordinator,
            details: false,
          ),
        ],
        if (typed || needed)
          _Details([
            if (needed || renewing) l10n.p2pRenewPasswordSame,
            l10n.p2pMakePasswordHint,
            l10n.p2pMakePasswordShare,
            l10n.p2pMakePasswordTakers,
            l10n.p2pMakePasswordReadable,
            l10n.p2pMakePasswordHashOnly,
            if (exposure != null) l10n.p2pMakePasswordOldDetail,
          ]),
      ],
    );
  }
}

/// « Description » (`MakerForm.tsx:1051-1083`) with its tooltip, and under it the reference's line when it is too long, or the app's when others would not see it as written ([OrderDescription]).
class _Description extends StatelessWidget {
  final TextEditingController controller;
  final MakerFormCheck check;
  final bool enabled;
  final VoidCallback onChanged;

  const _Description({
    required this.controller,
    required this.check,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final error = check.descriptionTooLong
        ? l10n.p2pMakeDescriptionTooLong(
            '${MakerFormCheck.maxDescriptionLength}',
          )
        : check.descriptionNotShown
        ? l10n.p2pMakeCustomMethodNotShown
        : null;
    final edge = error == null ? colors.outline : colors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            l10n.p2pMakeDescription,
            style: text.labelLarge?.copyWith(
              color: error == null ? colors.textMuted : colors.error,
            ),
          ),
        ),
        const Gap(BullSpacing.xxs),
        Tooltip(
          message: l10n.p2pMakeDescriptionHint,
          child: Semantics(
            container: true,
            label: l10n.p2pMakeDescription,
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.text,
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
                focusedBorder: _border(
                  error == null ? colors.primary : colors.error,
                ),
                errorBorder: _border(colors.error),
                focusedErrorBorder: _border(colors.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// « Public Duration (HH:mm) » or « Escrow/Invoice Timer (HH:mm) » (`MakerForm.tsx:1115-1184`): the duration as HH:mm, a tap opening a 24-hour picker titled as the reference's ([title]).
class _DurationField extends StatelessWidget {
  final String label;
  final String title;
  final Duration value;
  final bool enabled;
  final ValueChanged<Duration> onPicked;

  const _DurationField({
    required this.label,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onPicked,
  });

  /// [duration] as the reference's field writes it, `HH:mm`.
  static String hhmm(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value.inHours, minute: value.inMinutes % 60),
      helpText: title,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    onPicked(Duration(hours: picked.hour, minutes: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: hhmm(value),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: text.labelLarge?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.xxs),
          Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BullRadius.xxs),
              side: BorderSide(color: colors.outline),
            ),
            child: InkWell(
              onTap: enabled ? () => unawaited(_pick(context)) : null,
              borderRadius: BorderRadius.circular(BullRadius.xxs),
              child: Padding(
                padding: const EdgeInsets.all(BullSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hhmm(value),
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          color: enabled ? colors.text : colors.textMuted,
                        ),
                      ),
                    ),
                    Icon(Icons.schedule, color: colors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// « Fidelity Bond Size » (`MakerForm.tsx:1186-1258`): its label with a lock and the reference's tooltip, the slider from 2 to 15 % by 0.25, and the reference's marks, 2, 5, 10 and 15 %, under it.
class _BondSizeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _BondSizeSlider({required this.value, required this.onChanged});

  static const _marks = [2.0, 5.0, 10.0, 15.0];

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String percent(double value) =>
        l10n.p2pMakeBondSizeValue(formats.number(value));
    const span = MakerFormCheck.maxBondSize - MakerFormCheck.minBondSize;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: l10n.p2pMakeBondSizeHint,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      l10n.p2pMakeBondSize,
                      style: text.labelLarge?.copyWith(color: colors.textMuted),
                    ),
                  ),
                  const Gap(BullSpacing.xxs),
                  Icon(Icons.lock_outline, size: 14, color: colors.textMuted),
                ],
              ),
            ),
            Slider(
              value: value,
              min: MakerFormCheck.minBondSize,
              max: MakerFormCheck.maxBondSize,
              divisions: (span / MakerFormCheck.bondSizeStep).round(),
              label: percent(value),
              semanticFormatterCallback: percent,
              onChanged: onChanged,
            ),
            ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // The slider's track runs inside its own padding of 24 points each side.
                  const inset = 24.0;
                  final track = constraints.maxWidth - 2 * inset;
                  return SizedBox(
                    height: 20,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final mark in _marks)
                          Positioned(
                            left:
                                inset +
                                track *
                                    (mark - MakerFormCheck.minBondSize) /
                                    span -
                                20,
                            width: 40,
                            child: Text(
                              percent(mark),
                              textAlign: TextAlign.center,
                              style: text.labelSmall?.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
