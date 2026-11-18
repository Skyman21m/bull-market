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

/// `CheckMakePriceUsecase.execute`: the chosen coordinator's price compared with the wallet's.
typedef CheckMakePrice =
    Future<MakePriceCheck> Function(
      RobosatsNetwork network,
      RobosatsCurrency currency,
      double coordinatorPrice,
    );

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
  const MakeUncertain();
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
  });

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
  }) : super(MakeOrderState(network: network, currency: currency));

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

  /// The coordinator the user chose in « Select Host », or the default: its limits read again, even when it is the one shown (a choice is the reference's way of reading them again, `MakerForm.tsx:102-131`), then its price compared. Nothing while a make runs or has run.
  Future<void> choose(Coordinator coordinator) async {
    if (state.locked) return;
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
    if (state.locked || currency == state.currency) return;
    _priceRead++;
    emit(state._with(currency: currency, price: const MakeFormPriceNone()));
    await _readPrice();
  }

  /// Whether the user typed an amount (a number above zero): the Bull wallet's price is read, outside Tor, only for someone about to make an order (security review of #181), and only then; « Clear form » and an amount taken away ask nothing more, the line shown, if any, staying as it was.
  Future<void> wantPrice(bool wanted) async {
    if (wanted == _wanted) return;
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

  /// The network's last pending make is resolved or set aside (#182, functional review C1): a form locked by a make whose outcome was unknown is free again, nothing sent; any other state is left as it is.
  void pendingCleared() {
    if (isClosed || state.progress is! MakeUncertain) return;
    emit(state._with(progress: const MakeIdle()));
  }

  /// Makes [request] on [coordinator], the price check shown being [seen] (all three taken at the press): once at a time, and never after a make that made, or may have made, an order. The screen calls it after « Store your garage key ».
  ///
  /// When the price read just before the make would show another check ([MakePriceCheckChanged], security review of #181), nothing was sent with a robot: the form shows the coordinator's limits and the check at that price, the Bull wallet's price compared being the one already shown (nothing is read anew), and the user may press again having seen it.
  Future<void> make(
    MakeOrderRequest request, {
    required Coordinator coordinator,
    required MakePriceSeen seen,
  }) async {
    if (state.progress is! MakeIdle || state.coordinator != coordinator) return;
    emit(state._with(progress: const MakeSending()));
    final result = await _make(
      request,
      coordinator: coordinator,
      network: state.network,
      seen: seen,
    );
    if (isClosed) return;
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
          Ok(value: MakePending() || MakeNoLongerPending()) =>
            const MakeUncertain(),
        },
      ),
    );
  }
}
