import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/coordinator_lottery.dart';
import '../domain/coordinator_size_limit.dart';
import '../domain/robot_host.dart';
import '../domain/trade/make_price_check.dart';
import '../domain/trade/maker_form.dart';
import '../domain/trade/maker_terms.dart';
import '../domain/trade/trade_make.dart';
import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_renewal.dart';
import '../domain/trade_record.dart';
import 'take_order_cubit.dart' show HasGarageKey;

/// `ListRobotHostsUsecase.execute`, which the locator gives the cubit: the coordinators of the network, in the order of the federation.
typedef ListMakeHosts = RobotHosts Function(RobosatsNetwork network);

/// `FetchCoordinatorInfoUsecase.execute`: a coordinator's `/api/info/`, anonymously.
typedef FetchMakeInfo =
    Future<Result<CoordinatorInfo, CoordinatorFailure>> Function(
      Coordinator coordinator,
      RobosatsNetwork network,
    );

/// `FetchCoordinatorLimitsUsecase.execute`: a coordinator's `/api/limits/`, anonymously.
typedef FetchMakeLimits =
    Future<Result<CurrencyLimits, CoordinatorFailure>> Function(
      Coordinator coordinator,
      RobosatsNetwork network,
    );

/// `MakeOrderUsecase.execute`: the make itself, the only call of this cubit that sends anything with a robot.
typedef MakeOrder =
    Future<Result<MakeOutcome, MakeRefusal>> Function(
      MakeOrderRequest request, {
      required Coordinator coordinator,
      required RobosatsNetwork network,
      required MakePriceSeen seen,
    });

/// `TradeGarageKeyUsecase.makeUsesExternalKey`, which the locator gives the cubit (#318): whether a make on a network would take the external Garage Key.
typedef MakeUsesExternalKey = Future<bool> Function(RobosatsNetwork network);

/// `CheckMakePriceUsecase.execute`: the chosen coordinator's price compared with the wallet's.
typedef CheckMakePrice =
    Future<MakePriceCheck> Function(
      RobosatsNetwork network,
      RobosatsCurrency currency,
      double coordinatorPrice,
    );

/// `MakeOrderUsecase.renewal`: the request and the coordinator of an order made here, read from the records, for its renewal (#185).
typedef ReadRenewal =
    Future<Result<OrderRenewal, RenewalRefusal>> Function(TradeRecord record);

/// `MakeOrderUsecase.madeAsRenewal`: whether an order a resolution confirmed is made with the request of a renewal, on its coordinator (#217).
typedef MadeAsRenewal =
    Future<Result<bool, P2pFailure>> Function(
      TradeRecord made,
      OrderRenewal renewal,
    );

/// Whether the create form renews an order made here (#185), and where the read of that order's kept terms stands.
@immutable
sealed class MakeRenewalState {
  const MakeRenewalState();
}

/// A creation: the form as the user types it.
final class MakeRenewalNone extends MakeRenewalState {
  const MakeRenewalNone();
}

/// A renewal whose kept terms are being read from the records.
final class MakeRenewalReading extends MakeRenewalState {
  const MakeRenewalReading();
}

/// A renewal of [renewal]: the form shows its request, locked, on its coordinator.
final class MakeRenewalReady extends MakeRenewalState {
  final OrderRenewal renewal;

  const MakeRenewalReady(this.renewal);
}

/// A renewal that cannot be made from this device ([refusal]): nothing is sent.
final class MakeRenewalRefused extends MakeRenewalState {
  final RenewalRefusal refusal;

  const MakeRenewalRefused(this.refusal);
}

/// Where the make of the create form stands.
@immutable
sealed class MakeProgress {
  const MakeProgress();
}

/// Nothing sent: « Create order » can be pressed when the form allows it; [problem] says why the last make did not happen, when one was tried.
final class MakeIdle extends MakeProgress {
  final MakeProblem? problem;

  const MakeIdle({this.problem});
}

/// The make runs: the coordinator's terms read again, a fresh robot reserved and put on it, the make sent (`MakeOrderUsecase`).
final class MakeSending extends MakeProgress {
  const MakeSending();
}

/// The order was made and is this robot's: the screen opens the trade of [record].
final class MakeMade extends MakeProgress {
  final TradeRecord record;

  const MakeMade(this.record);
}

/// Whether the make made an order is not known: it stays pending in the records, resolved from its line of « Active trades » (#182). The form makes nothing more, so that no second order is made beside one that may exist.
final class MakeUncertain extends MakeProgress {
  /// Whether, on a renewal's page, whether the renewal made an order cannot be told: an order of the network confirmed meanwhile whose terms could not be read, or the page's own make no longer pending, confirmed or closed since (security review of #220, R1, N1): the page sends nothing more, and says to go back.
  final bool unverified;

  const MakeUncertain({this.unverified = false});
}

/// Why a make did not happen: a type, worded by the screen, never a coordinator's text.
@immutable
sealed class MakeProblem {
  const MakeProblem();
}

/// Refused before anything was sent with a robot, or before the make left ([MakeRefusal]).
final class MakeWasRefused extends MakeProblem {
  final MakeRefusal refusal;

  const MakeWasRefused(this.refusal);
}

/// Sent, and certainly not made ([MakeNotMade], [MakeNeverSent]): [refusal] is the coordinator's refusal when it gave one.
final class MakeWasNotMade extends MakeProblem {
  final Failure? refusal;

  const MakeWasNotMade(this.refusal);
}

/// Where the price check of the form stands (#181, the owner's decision of 2026-11-17, [MakePriceCheck]).
@immutable
sealed class MakeFormPrice {
  const MakeFormPrice();
}

/// No check: the wallet's port was not lent, or the coordinator gave no usable price for the currency yet.
final class MakeFormPriceNone extends MakeFormPrice {
  const MakeFormPriceNone();
}

/// The wallet's price is being read.
final class MakeFormPriceReading extends MakeFormPrice {
  const MakeFormPriceReading();
}

/// The check of the coordinator's price for the currency shown.
final class MakeFormPriceChecked extends MakeFormPrice {
  final MakePriceCheck check;

  const MakeFormPriceChecked(this.check);
}

/// The create form's business state (#181): the coordinators, the one chosen with its limits, the price check, and the make.
///
/// What the user types stays in the screen (`AGENTS.md`, rule 5); the screen judges it with `MakerFormCheck` against [limits].
@immutable
final class MakeOrderState {
  final RobosatsNetwork network;

  /// Whether the default coordinator is drawn: until then the form says « Loading coordinator list... ».
  final bool coordinatorsLoaded;

  /// The coordinators of the network in the order of the reference's lottery, as « Select Host » lists them.
  final List<RobotHost> hosts;

  /// The `/api/info/` of each coordinator that gave one, by short alias.
  final Map<String, CoordinatorInfo> infos;

  /// The coordinator the order is for, `null` until drawn (or when none can be chosen).
  final Coordinator? coordinator;

  /// The chosen coordinator's limits.
  final MakerFormLimits limits;

  /// The chosen coordinator's size limit, in sats, at the moment it was chosen (`CoordinatorSizeLimit`).
  final double sizeLimitSats;

  /// The currency the form shows, for the price check.
  final RobosatsCurrency currency;

  final MakeFormPrice price;
  final MakeProgress progress;

  /// When the chosen coordinator's limits were last read, `null` before.
  final DateTime? limitsReadAt;

  /// Whether the form renews an order made here (#185), and its kept terms.
  final MakeRenewalState renewal;

  const MakeOrderState({
    required this.network,
    required this.currency,
    this.coordinatorsLoaded = false,
    this.hosts = const [],
    this.infos = const {},
    this.coordinator,
    this.limits = const MakerFormLimitsLoading(),
    this.sizeLimitSats = 0,
    this.price = const MakeFormPriceNone(),
    this.progress = const MakeIdle(),
    this.limitsReadAt,
    this.renewal = const MakeRenewalNone(),
  });

  /// Whether the form renews an order (#185): its fields, its currency and its coordinator are the order's, never changed.
  bool get renewing => renewal is! MakeRenewalNone;

  /// Whether the form is locked: a make runs or has run, so nothing typed changes what was sent.
  bool get locked => progress is! MakeIdle;

  /// Whether the coordinators were drawn and none can be chosen (none listed, or each refuses first contacts in this run): the form says so, with « Retry », rather than « Loading... ».
  bool get noHost => coordinatorsLoaded && coordinator == null;

  /// The limits the form judges with: unreadable when no coordinator can be chosen, so that the form says « The coordinator limits are not available. » rather than waiting.
  MakerFormLimits get formLimits =>
      noHost ? const MakerFormLimitsUnreadable() : limits;

  MakeOrderState _with({
    bool? coordinatorsLoaded,
    List<RobotHost>? hosts,
    Map<String, CoordinatorInfo>? infos,
    Coordinator? coordinator,
    MakerFormLimits? limits,
    double? sizeLimitSats,
    RobosatsCurrency? currency,
    MakeFormPrice? price,
    MakeProgress? progress,
    DateTime? limitsReadAt,
    MakeRenewalState? renewal,
  }) => MakeOrderState(
    network: network,
    coordinatorsLoaded: coordinatorsLoaded ?? this.coordinatorsLoaded,
    hosts: hosts ?? this.hosts,
    infos: infos ?? this.infos,
    coordinator: coordinator ?? this.coordinator,
    limits: limits ?? this.limits,
    sizeLimitSats: sizeLimitSats ?? this.sizeLimitSats,
    currency: currency ?? this.currency,
    price: price ?? this.price,
    progress: progress ?? this.progress,
    limitsReadAt: limitsReadAt ?? this.limitsReadAt,
    renewal: renewal ?? this.renewal,
  );
}

/// The create form (#181): it draws the default coordinator as the reference does, reads the chosen coordinator's limits, compares its price with the wallet's, and makes the order the screen confirmed.
///
/// Every read here is anonymous (`/api/info/`, `/api/limits/`) or the wallet's price; only [make] calls `MakeOrderUsecase.execute`, at most once at a time, and never again after a make that may have made an order ([MakeUncertain]) or did ([MakeMade]).
class MakeOrderCubit extends Cubit<MakeOrderState> {
  final ListMakeHosts _listHosts;
  final FetchMakeInfo _fetchInfo;
  final FetchMakeLimits _fetchLimits;
  final MakeOrder _make;
  final HasGarageKey _hasGarageKey;
  final CoordinatorLottery _lottery;
  final DateTime Function() _now;

  /// The wallet's price check, when the wallet's port was lent; `null` shows no check.
  final CheckMakePrice? _checkPrice;

  /// Whether the make would take the external Garage Key ([remindsGarageKey]); `null` for a renewal, and where the locator lends none.
  final MakeUsesExternalKey? _usesExternalKey;

  /// The order made here this form renews (#185), and the read of its kept terms; both `null` for a creation.
  final TradeRecord? _renewing;
  final ReadRenewal? _readRenewal;

  /// Whether an order a resolution confirmed is this renewal's own (#217); `null` for a creation.
  final MadeAsRenewal? _madeAsRenewal;

  /// How many checks of [pendingStarted] run: [make] sends nothing meanwhile.
  int _checkingStarted = 0;

  /// The pending make this page's own make left, its outcome unknown: the order a resolution confirms for its robot is this page's, and its end without an order frees a renewal's page (security review of #220, N1).
  PendingMake? _ownPending;

  /// Bumped at each read of limits or of the wallet's price, so that an answer for a coordinator or a currency no longer shown is dropped.
  int _limitsRead = 0;
  int _priceRead = 0;

  /// Whether [start] runs.
  bool _starting = false;

  /// Whether an amount is typed ([wantPrice]): only then is the Bull wallet's price read.
  bool _wanted = false;

  /// The last read of the Bull wallet's price of each currency (by its RoboSats id): when it came, and the check it gave; a read [staleAfter] old or more is forgotten at the next read (second security review of #181, R10).
  final Map<int, ({DateTime at, MakePriceCheck check})> _lastPrices = {};

  /// The read of the Bull wallet's price that runs, if one does ([priceSettled]).
  Future<MakePriceCheck>? _priceReading;

  /// The name the locator registers the renewal's cubit under (#185), built from the record of the order renewed.
  static const String renewalInstance = 'renewal';

  /// How old the limits and the Bull wallet's price may be when « Create order » is pressed: older, they are read again first ([refreshIfStale]). The reference reads them once when the form opens or the coordinator changes, never again while it stays open (`MakerForm.tsx:102-131`; `Federation.loadCoordinatorData`, `models/Federation.model.ts:763-792`, at a change of connection only).
  static const Duration staleAfter = Duration(minutes: 3);

  MakeOrderCubit(
    RobosatsNetwork network, {
    required RobosatsCurrency currency,
    required this._listHosts,
    required this._fetchInfo,
    required this._fetchLimits,
    required this._make,
    required this._hasGarageKey,
    required this._lottery,
    required this._now,
    this._checkPrice,
    this._usesExternalKey,
  }) : _renewing = null,
       _readRenewal = null,
       _madeAsRenewal = null,
       super(MakeOrderState(network: network, currency: currency));

  /// The form renewing the order of [renewing] (#185): its kept terms read by [readRenewal] when it starts, shown locked, sent to its own coordinator only. [placeholder] is the currency of the state until those terms are read, which the screen shows nowhere (it shows the wait).
  MakeOrderCubit.renewal(
    TradeRecord renewing, {
    required RobosatsCurrency placeholder,
    required ReadRenewal this._readRenewal,
    required MadeAsRenewal this._madeAsRenewal,
    required this._listHosts,
    required this._fetchInfo,
    required this._fetchLimits,
    required this._make,
    required this._hasGarageKey,
    required this._lottery,
    required this._now,
    this._checkPrice,
  }) : _renewing = renewing,
       _usesExternalKey = null,
       super(
         MakeOrderState(
           network: renewing.network,
           currency: placeholder,
           renewal: const MakeRenewalReading(),
         ),
       );

  /// Reads every coordinator's `/api/info/` at once, then draws their order by the reference's lottery (`federationLottery`, run once the information is loaded, `models/Federation.model.ts:584-609`): the first one that takes first contacts is the default, as the reference picks the first of its list (`MakerForm.tsx:132-138`); then its limits.
  Future<void> start() async {
    if (_starting || state.locked) return;
    _starting = true;
    try {
      await _start();
    } finally {
      _starting = false;
    }
  }

  /// « Retry » when no coordinator could be chosen: the coordinators listed and drawn again.
  Future<void> retryHosts() async {
    if (!state.noHost) return;
    emit(state._with(coordinatorsLoaded: false));
    await start();
  }

  Future<void> _start() async {
    if (_renewing case final renewing?) return _startRenewal(renewing);
    final network = state.network;
    final hosts = _listHosts(network).choices;
    final answers = await Future.wait([
      for (final host in hosts) _fetchInfo(host.coordinator, network),
    ]);
    if (isClosed) return;
    final infos = <String, CoordinatorInfo>{
      for (final (index, answer) in answers.indexed)
        if (answer case Ok(:final value))
          hosts[index].coordinator.shortAlias: value,
    };
    final order = _lottery.order([
      for (final host in hosts) host.coordinator,
    ], infos: infos);
    final byAlias = {
      for (final host in hosts) host.coordinator.shortAlias: host,
    };
    final drawn = [
      for (final coordinator in order) ?byAlias[coordinator.shortAlias],
    ];
    final first = drawn.where((host) => !host.refusesFirstContacts).firstOrNull;
    emit(
      state._with(
        coordinatorsLoaded: true,
        hosts: List.unmodifiable(drawn),
        infos: Map.unmodifiable(infos),
      ),
    );
    if (first != null) await choose(first.coordinator);
  }

  /// A renewal's start (#185): the order's kept terms read from the records, then its own coordinator, with no lottery and no other choice (the reference renews on the order's coordinator, `TradeBox/index.tsx:178`): its `/api/info/` and limits read as for a creation, then the Bull wallet's price compared, an amount being shown from the start. A coordinator no longer listed, or that refuses first contacts in this run, is said as for a creation (« Retry » reads all again).
  Future<void> _startRenewal(TradeRecord renewing) async {
    final read = _readRenewal;
    if (read == null) return;
    emit(
      state._with(
        coordinatorsLoaded: false,
        renewal: const MakeRenewalReading(),
      ),
    );
    final OrderRenewal renewal;
    switch (await read(renewing)) {
      case Ok(:final value):
        renewal = value;
      case Err(:final failure):
        if (isClosed) return;
        emit(
          state._with(
            coordinatorsLoaded: true,
            renewal: MakeRenewalRefused(failure),
          ),
        );
        return;
    }
    if (isClosed) return;
    final coordinator = renewal.coordinator;
    final hosts = [
      for (final host in _listHosts(state.network).choices)
        if (host.coordinator == coordinator) host,
    ];
    final info = await _fetchInfo(coordinator, state.network);
    if (isClosed) return;
    _wanted = true;
    emit(
      state._with(
        coordinatorsLoaded: true,
        hosts: List.unmodifiable(hosts),
        infos: Map.unmodifiable({
          if (info case Ok(:final value)) coordinator.shortAlias: value,
        }),
        currency: renewal.request.currency,
        renewal: MakeRenewalReady(renewal),
      ),
    );
    if (hosts.any((host) => !host.refusesFirstContacts)) {
      await choose(coordinator);
    }
  }

  /// The order this form renews, once its kept terms are read; `null` for a creation or before.
  OrderRenewal? get _renewal => switch (state.renewal) {
    MakeRenewalReady(:final renewal) => renewal,
    _ => null,
  };

  /// The coordinator the user chose in « Select Host », or the default: its limits read again, even when it is the one shown (a choice is the reference's way of reading them again, `MakerForm.tsx:102-131`), then its price compared. Nothing while a make runs or has run.
  Future<void> choose(Coordinator coordinator) async {
    if (state.locked) return;
    // A renewal is sent to its order's coordinator only (#185).
    if (state.renewing && coordinator != _renewal?.coordinator) return;
    emit(
      state._with(
        coordinator: coordinator,
        limits: const MakerFormLimitsLoading(),
        sizeLimitSats: CoordinatorSizeLimit.of(coordinator, _now()).sats,
        price: const MakeFormPriceNone(),
      ),
    );
    await _readLimits(coordinator);
  }

  /// « Retry » of a renewal whose coordinator's limits could not be read (#185, functional review R3): its page offers no « Select Host », whose choice is a creation's way of reading them again; nothing while a make runs or has run.
  Future<void> retryLimits() async {
    final coordinator = state.coordinator;
    if (state.locked ||
        coordinator == null ||
        state.limits is! MakerFormLimitsUnreadable) {
      return;
    }
    await choose(coordinator);
  }

  /// Reads the chosen coordinator's limits again when the last read is older than [staleAfter], then compares their price, reading the Bull wallet's again only when its last read for the currency is that old too: called by « Create order » before its dialogs, so that the form never warns or reassures on an old rate when the user confirms; never in a loop. Whether anything was read.
  Future<bool> refreshIfStale() async {
    final coordinator = state.coordinator;
    final readAt = state.limitsReadAt;
    if (state.locked || coordinator == null || readAt == null) return false;
    if (_now().difference(readAt) < staleAfter) return false;
    await _readLimits(coordinator);
    return true;
  }

  /// [coordinator]'s limits read, kept only while it is still the one chosen, then its price compared.
  Future<void> _readLimits(Coordinator coordinator) async {
    final read = ++_limitsRead;
    _priceRead++;
    final answer = await _fetchLimits(coordinator, state.network);
    if (isClosed || read != _limitsRead) return;
    emit(
      state._with(
        limits: switch (answer) {
          Ok(:final value) => MakerFormLimitsRead(value),
          Err() => const MakerFormLimitsUnreadable(),
        },
        limitsReadAt: _now(),
      ),
    );
    await _readPrice();
  }

  /// The currency the form shows: its price compared when an amount is typed ([wantPrice]), from the last read of the Bull wallet's price for that currency when it is less than [staleAfter] old.
  Future<void> showCurrency(RobosatsCurrency currency) async {
    if (state.locked || state.renewing || currency == state.currency) return;
    _priceRead++;
    emit(state._with(currency: currency, price: const MakeFormPriceNone()));
    await _readPrice();
  }

  /// Whether the user typed an amount (a number above zero): the Bull wallet's price is read, outside Tor, only for someone about to make an order (security review of #181), and only then; « Clear form » and an amount taken away ask nothing more, the line shown, if any, staying as it was.
  Future<void> wantPrice(bool wanted) async {
    // A renewal shows its order's amount from the start: its price is compared once its terms are read (#185).
    if (state.renewing || wanted == _wanted) return;
    _wanted = wanted;
    if (wanted) await _readPrice();
  }

  /// « Retry » of a wallet's price that could not be read: read once more, never while a read runs.
  Future<void> retryPrice() async {
    if (state.locked) return;
    if (state.price case MakeFormPriceChecked(check: MakePriceUnverified())) {
      await _readPrice(again: true);
    }
  }

  /// The Bull wallet's price compared with the coordinator's, when an amount is typed and the coordinator gives a price: from the last read for the currency when it is less than [staleAfter] old (none is sent then, whatever the coordinator chosen), else read; [again] (« Retry ») always reads.
  Future<void> _readPrice({bool again = false}) async {
    final check = _checkPrice;
    final coordinatorPrice = _usablePrice();
    if (check == null || coordinatorPrice == null || !_wanted) return;
    final currency = state.currency;
    final now = _now();
    _lastPrices.removeWhere((_, last) => now.difference(last.at) >= staleAfter);
    final last = _lastPrices[currency.id];
    if (!again && last != null) {
      _priceRead++;
      final seen = MakePriceSeen.of(
        currency: currency,
        coordinatorPrice: coordinatorPrice,
        check: last.check,
      );
      final now = seen.checkAt(coordinatorPrice);
      if (now != null) emit(state._with(price: MakeFormPriceChecked(now)));
      return;
    }
    final read = ++_priceRead;
    emit(state._with(price: const MakeFormPriceReading()));
    final reading = check(state.network, currency, coordinatorPrice);
    _priceReading = reading;
    final result = await reading;
    if (identical(_priceReading, reading)) _priceReading = null;
    if (isClosed || read != _priceRead) return;
    _lastPrices[currency.id] = (at: _now(), check: result);
    emit(state._with(price: MakeFormPriceChecked(result)));
  }

  /// When the form shows the Bull wallet's price being read: the end of that read, for « Create order » pressed meanwhile (second security review of #181, R8); at once otherwise. Bounded by the read itself, which the shell stops after 15 s (`ReadWalletRateUsecase.readBound`).
  Future<void> priceSettled() async {
    while (!isClosed && state.price is MakeFormPriceReading) {
      final reading = _priceReading;
      if (reading == null) return;
      // The read's own continuation, registered first, shows its answer before this one runs.
      await reading;
    }
  }

  /// The price check as the form shows it now ([MakePriceSeen]), for the press of « Create order »: `null` when the coordinator gives no usable price for the currency, when no order can be made anyway.
  MakePriceSeen? seen() {
    final coordinatorPrice = _usablePrice();
    if (coordinatorPrice == null) return null;
    return MakePriceSeen.of(
      currency: state.currency,
      coordinatorPrice: coordinatorPrice,
      check: switch (state.price) {
        MakeFormPriceChecked(:final check) => check,
        _ => null,
      },
    );
  }

  /// The chosen coordinator's price for the currency shown, when the make's terms would take it.
  double? _usablePrice() {
    final limits = state.limits;
    if (limits is! MakerFormLimitsRead) return null;
    final price = limits.limits[state.currency]?.price;
    if (price == null ||
        !price.isFinite ||
        price < MakerTerms.minCreatedPrice ||
        price >= MakerTerms.maxCreatedPrice) {
      return null;
    }
    return price;
  }

  /// Whether a Garage Key is stored for the network: without one, the screen shows « You do not have a Garage Key », as the reference does without a robot (`MakerForm.tsx:1303-1307`); a key that cannot be read is no key.
  Future<bool> hasGarageKey() async =>
      switch (await _hasGarageKey(state.network)) {
        Ok(:final value) => value,
        Err() => false,
      };

  /// Whether « Store your garage key » is shown before this form's make (#318, decided on 2026-11-28): only when the key a make would take now is the external Garage Key, the key the vault keeps, which nothing else backs up; a key of the wallet's words comes back with the words, and the make is sent at once. Never for a renewal, which sends at once as the reference's (#185). Where no reading was lent (the form's own tests), shown as before #318.
  Future<bool> remindsGarageKey() async {
    if (state.renewing) return false;
    final read = _usesExternalKey;
    return read == null || await read(state.network);
  }

  /// The network's last pending make is resolved or set aside (#182, functional review C1): a creation's form locked by a make whose outcome was unknown is free again, nothing sent; any other state is left as it is.
  ///
  /// Never for a renewal (security review of #220, R1): its own make may be the very order a resolution has just confirmed; a renewal's page is freed only when its own make is known to have ended without an order ([pendingEnded]).
  void pendingCleared() {
    if (isClosed || state.progress is! MakeUncertain || state.renewing) return;
    emit(state._with(progress: const MakeIdle()));
  }

  /// The pending make of [robot] ended without an order on this screen: closed by a resolution as not made, or set aside by the user (security review of #220, N1). A renewal's page whose own make it was is free again, a new make legitimate; anything else is left as it is.
  void pendingEnded(RobotSlot robot) {
    if (isClosed || !state.renewing || _ownPending?.robot != robot) return;
    if (state.progress case MakeUncertain(unverified: false)) {
      _ownPending = null;
      emit(state._with(progress: const MakeIdle()));
    }
  }

  /// A pending make of the network that a resolution confirmed while the renewal's page is open, the order of [record] (#217, security review of #185, R3): [MakeMade], which the screen opens in place of the order renewed, when that order is this page's own make (its robot), or made with this renewal's very request on its coordinator (an earlier try of this renewal whose answer was lost); a make unrelated to it, confirmed meanwhile, neither closes the page nor takes the place of the order renewed. When that check cannot read the records, the page sends nothing more and says to go back (`MakeUncertain.unverified`, security review of #220, R1, N1), rather than be free for a second order. Nothing while a make of this page runs or made an order; nothing for a creation, whose screen opens such a trade at once (#182).
  ///
  /// While that check runs, [make] sends nothing (security review of #220, R1, its mutant M14): the pending list may empty meanwhile and turn « Create order » on, and the order just confirmed may be this renewal's own.
  Future<void> pendingStarted(TradeRecord record) async {
    final check = _madeAsRenewal;
    final renewal = _renewal;
    if (isClosed || check == null || renewal == null || _busy) return;
    if (_ownPending?.robot == record.robot) {
      _ownPending = null;
      emit(state._with(progress: MakeMade(record)));
      return;
    }
    _checkingStarted++;
    final Result<bool, P2pFailure> own;
    try {
      own = await check(record, renewal);
    } finally {
      _checkingStarted--;
    }
    if (isClosed || _busy) return;
    switch (own) {
      case Ok(value: true):
        emit(state._with(progress: MakeMade(record)));
      case Ok(value: false):
        break;
      case Err():
        emit(state._with(progress: const MakeUncertain(unverified: true)));
    }
  }

  /// Whether a make of this page runs or made an order.
  bool get _busy => switch (state.progress) {
    MakeSending() || MakeMade() => true,
    MakeIdle() || MakeUncertain() => false,
  };

  /// Makes [request] on [coordinator], the price check shown being [seen] (all three taken at the press): once at a time, and never after a make that made, or may have made, an order. The screen calls it after « Store your garage key ».
  ///
  /// When the price read just before the make would show another check ([MakePriceCheckChanged], security review of #181), nothing was sent with a robot: the form shows the coordinator's limits and the check at that price, the Bull wallet's price compared being the one already shown (nothing is read anew), and the user may press again having seen it.
  Future<void> make(
    MakeOrderRequest request, {
    required Coordinator coordinator,
    required MakePriceSeen seen,
  }) async {
    if (state.progress is! MakeIdle ||
        state.coordinator != coordinator ||
        _checkingStarted > 0 ||
        // A protected order is sent with its password's hash, never without (#189).
        !request.isSendable) {
      return;
    }
    // A renewal sends its order's kept request to its order's coordinator, nothing else (#185).
    if (state.renewing) {
      final renewal = _renewal;
      if (renewal == null ||
          request != renewal.request ||
          coordinator != renewal.coordinator) {
        return;
      }
    }
    emit(state._with(progress: const MakeSending()));
    final result = await _make(
      request,
      coordinator: coordinator,
      network: state.network,
      seen: seen,
    );
    if (isClosed) return;
    if (result case Ok(value: MakePending(:final make))) _ownPending = make;
    if (result case Err(failure: MakePriceCheckChanged(:final limits))) {
      _limitsRead++;
      _priceRead++;
      final price = limits[seen.currency]?.price;
      final check = price == null ? null : seen.checkAt(price);
      emit(
        state._with(
          limits: MakerFormLimitsRead(limits),
          limitsReadAt: _now(),
          price: check == null ? null : MakeFormPriceChecked(check),
        ),
      );
    }
    emit(
      state._with(
        progress: switch (result) {
          Err(:final failure) => MakeIdle(problem: MakeWasRefused(failure)),
          Ok(value: MakeStarted(:final record)) => MakeMade(record),
          Ok(value: MakeNotMade(:final refusal)) => MakeIdle(
            problem: MakeWasNotMade(refusal),
          ),
          Ok(value: MakeNeverSent()) => const MakeIdle(
            problem: MakeWasNotMade(null),
          ),
          // A renewal's page knows its own pending make by its robot (security review of #220, N1); a make no longer pending cannot be told, and stays locked, said so.
          Ok(value: MakePending()) => const MakeUncertain(),
          Ok(value: MakeNoLongerPending()) => MakeUncertain(
            unverified: state.renewing,
          ),
        },
      ),
    );
  }
}
