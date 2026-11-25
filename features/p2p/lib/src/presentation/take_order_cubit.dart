import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../public/p2p_wallet_port.dart';
import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/make_price_check.dart';
import '../domain/trade/taken_price_check.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/has_garage_key_usecase.dart';
import '../domain/usecases/trade/take_order_usecase.dart';

/// [TakeOrderUsecase.prepare], which the locator gives the cubit.
typedef PrepareTake =
    Future<Result<PreparedTake, TakeRefusal>> Function(
      PublicOrder shown, {
      required RobosatsNetwork network,
      TakeAmount? amount,
      TakeProgress? onStep,
      RobotSlot? garageRobot,
    });

/// [TakeOrderUsecase.prepareUnlisted], which the locator gives the cubit (#245).
typedef PrepareUnlistedTake =
    Future<Result<PreparedTake, TakeRefusal>> Function(
      UnlistedOrder shown, {
      TakeAmount? amount,
      TakeProgress? onStep,
      RobotSlot? garageRobot,
    });

/// [TakeOrderUsecase.confirm], which the locator gives the cubit.
typedef ConfirmTake =
    Future<Result<TakeOutcome, TakeRefusal>> Function(
      PreparedTake prepared, {
      OrderPassword? password,
      TakeProgress? onStep,
    });

/// [TakeOrderUsecase.abandon], which the locator gives the cubit.
typedef AbandonTake = void Function(PreparedTake prepared);

/// [TakeOrderUsecase.abandonOrder], which the locator gives the cubit.
typedef AbandonOrderTake =
    void Function(PublicOrder shown, {required RobosatsNetwork network});

/// `GarageRobotUsecase.execute`, the robot the Garage of a network would show, which the locator gives the take's screens for the line of the order page only (#251).
typedef GarageRobotOf = Future<RobotSlot?> Function(RobosatsNetwork network);

/// [HasGarageKeyUsecase.execute], which the locator gives the cubit.
typedef HasGarageKey =
    Future<Result<bool, P2pFailure>> Function(RobosatsNetwork network);

/// `CheckMakePriceUsecase.execute`, as it is, which the locator gives the cubit where the wallet's port was lent (#249): the coordinator's price without the premium compared with the Bull wallet's.
typedef CheckTakePrice =
    Future<MakePriceCheck> Function(
      RobosatsNetwork network,
      RobosatsCurrency currency,
      double coordinatorPrice,
    );

/// Where the comparison of the read shown with the Bull wallet's price stands (#249, slice 4; [TakenPriceCheck]).
@immutable
sealed class TakePrice {
  const TakePrice();

  /// The check the order page draws, `null` for none.
  MakePriceCheck? get shownCheck;
}

/// Nothing compared: no read shown yet, or no wallet's port lent.
final class TakePriceNone extends TakePrice {
  const TakePriceNone();

  @override
  MakePriceCheck? get shownCheck => null;
}

/// The Bull wallet's price is being read; [shown] is the check still drawn meanwhile, « Price not checked » while « Retry » reads again, `null` at a first read, which draws nothing.
final class TakePriceReading extends TakePrice {
  final MakePriceCheck? shown;

  const TakePriceReading({this.shown});

  @override
  MakePriceCheck? get shownCheck => shown;
}

/// The comparison of the read shown.
final class TakePriceChecked extends TakePrice {
  final MakePriceCheck check;

  const TakePriceChecked(this.check);

  @override
  MakePriceCheck? get shownCheck => check;
}

/// The use case's calls that the cubit makes: the take in two steps (#119).
@immutable
final class TakeCalls {
  final PrepareTake prepare;

  /// The preparation of an order no book received, reached by its URL (#245), given by the locator; `null` where none is taken.
  final PrepareUnlistedTake? prepareUnlisted;
  final ConfirmTake confirm;
  final AbandonTake abandon;
  final AbandonOrderTake abandonOrder;

  /// The robot the Garage would show, read before each preparation, so that a robot reserved by it says whether it is another one (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.2); `null` where none is read, and no line said.
  final GarageRobotOf? garageRobot;

  const TakeCalls({
    required this.prepare,
    this.prepareUnlisted,
    required this.confirm,
    required this.abandon,
    required this.abandonOrder,
    this.garageRobot,
  });
}

/// Where the take of one order of the book stands, on its order details (#88, #119).
@immutable
sealed class TakeOrderState {
  const TakeOrderState();

  /// The comparison of the read shown with the Bull wallet's price (#249), [TakePriceNone] while no read is shown.
  TakePrice get price;
}

/// Nothing runs: « Take Order » can be pressed, unless the order is gone ([orderGone]); [problem] says why the last take did not happen, when one was tried.
final class TakeIdle extends TakeOrderState {
  final TakeProblem? problem;

  const TakeIdle({this.problem});

  @override
  TakePrice get price => const TakePriceNone();

  /// Whether the last try found the order no longer available: the page offers no take of it any more (review of #133).
  bool get orderGone => switch (problem) {
    TakeWasRefused(refusal: TakeOrderGone()) => true,
    TakeWasNotMade(
      refusal: OrderNotAvailable() || OrderNotPublic() || OrderCancelled(),
    ) =>
      true,
    _ => false,
  };
}

/// The order is read by the robot that will take it (the order read again, a robot put on the coordinator, its read of the order): it can take a minute over Tor; [step] is what it does now, `null` until the first one starts, and [slow] says it has run for a while.
///
/// [previous] is the read the user saw, when the confirmation found the order changed or its preparation gone and the order is read again: it stays shown meanwhile, with [price], its comparison; [changed] says the order changed, which the screen says at once.
final class TakePreparing extends TakeOrderState {
  final TakeStep? step;
  final bool slow;
  final PreparedTake? previous;
  final bool changed;
  @override
  final TakePrice price;

  const TakePreparing({
    this.step,
    this.slow = false,
    this.previous,
    this.changed = false,
    this.price = const TakePriceNone(),
  });
}

/// The robot read the order: the order details show [prepared], and the user goes on (« Continue », then « Store your garage key » and its « Done ») or goes back.
///
/// [previous] is the read the user saw before, when the order changed at the confirmation, or when a read made again after its preparation was gone shows it otherwise: the rows that differ from it are marked.
/// [price] is the comparison of [prepared] with the Bull wallet's price (#249), read once this state is shown.
final class TakeReady extends TakeOrderState {
  final PreparedTake prepared;
  final PreparedTake? previous;
  @override
  final TakePrice price;

  const TakeReady(
    this.prepared, {
    this.previous,
    this.price = const TakePriceNone(),
  });

  /// Whether the order changed since the read the user had seen.
  bool get changed => previous != null;
}

/// The take of [prepared] is confirmed and runs (the order read again by the same robot, then the take sent); [step] is what it does now, and [slow] says it has run for a while.
///
/// [price] is the comparison the user saw at « Continue », still drawn.
final class TakeConfirming extends TakeOrderState {
  final PreparedTake prepared;
  final TakeStep? step;
  final bool slow;
  @override
  final TakePrice price;

  const TakeConfirming(
    this.prepared, {
    this.step,
    this.slow = false,
    this.price = const TakePriceNone(),
  });
}

/// The take was sent and started a trade, resumed one, or its outcome is unknown, or the order already had an open trade here: the trade of [record] is the screen to show (the watch of the trade resolves an unknown outcome).
///
/// [prepared] is the read the take was sent on, which stays shown until the trade's screen opens, with [price], its comparison.
final class TakeSent extends TakeOrderState {
  final TradeRecord record;
  final PreparedTake? prepared;
  @override
  final TakePrice price;

  const TakeSent(
    this.record, {
    this.prepared,
    this.price = const TakePriceNone(),
  });
}

/// Why a take did not happen, as a type: the screen words it, never with a coordinator's text.
@immutable
sealed class TakeProblem {
  const TakeProblem();
}

/// The take was not sent ([TakeRefusal]).
final class TakeWasRefused extends TakeProblem {
  final TakeRefusal refusal;

  const TakeWasRefused(this.refusal);
}

/// The take was sent and the coordinator did not make it ([TakeNotMade]): [refusal] is why, `null` when it answered with the order as it is.
final class TakeWasNotMade extends TakeProblem {
  final Failure? refusal;

  const TakeWasNotMade(this.refusal);
}

/// Takes one order of the book for a fresh robot of this device, in two steps (#88, #119): the only caller of [TakeOrderUsecase], which the locator gives it as [TakeCalls].
///
/// [take] prepares (« Take Order »): the order read by the robot that will take it, which the order details then show ([TakeReady]); [confirm] sends the take of what the user saw (« Done » of « Store your garage key », after « Continue »); [back] abandons it (« Go back », of either).
/// One step runs at a time: a second [take] or [confirm] while one runs, or after the take was sent, does nothing, so a double tap sends one request; an order found gone is not prepared again.
/// Nothing is confirmed by itself: when the confirmation finds the order changed ([TakeOrderChanged]) or its preparation gone ([TakePreparationGone]), the order is prepared again, once, and its new figures wait for the user, the read the user saw shown meanwhile when the order changed.
/// Closing the cubit (the page left, a system back) abandons what is prepared, or the order when the last preparation failed, so that no robot stays kept for it; a confirmation that runs then is left to finish, the user having confirmed it.
///
/// The owner's payment rule before the take (#249, slice 4; design note `docs/design/phase-3-taken-order-price-check.md` § 8, point 4): once a read is shown ([TakeReady]), the coordinator's price without the premium from its terms ([TakenPriceCheck.coordinatorPrice]) is compared with the Bull wallet's through `CheckMakePriceUsecase` as it is, the Bull wallet's price read at most once per [staleAfter] per currency by this cubit, and again at each « Retry » ([retryPrice]); never when the page opens, never while the book is browsed, never for an order whose read is not shown. « Continue » pressed while it is read waits for it ([priceSettled]). The verdict is not checked again at the read that [confirm] makes: the take is sent on the very terms compared.
class TakeOrderCubit extends Cubit<TakeOrderState> {
  /// After how long a step that runs is said to be still waiting, as the robot panel of the Garage does (`RobotCoordinatorCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  /// The locator's name of the cubit that takes an order public again from the trade screen, given the trade shown ([shownTrade]).
  static const fromTrade = 'fromTrade';

  /// The locator's name of the cubit that takes an order no book received, which its robot read ([TakeOrderCubit.unlisted], #245).
  static const unlistedOrder = 'unlistedOrder';

  /// How old the last read of the Bull wallet's price of a currency may be to be compared again without a new read, as the create form keeps it (`MakeOrderCubit.staleAfter`).
  static const Duration staleAfter = Duration(minutes: 3);

  final PublicOrder order;

  /// The order no book received that the page shows, as its robot read it (#245), `null` for an order of the book: its take is prepared with [TakeCalls.prepareUnlisted], and confirmed with the password's hash when it has a password ([UnlistedOrder.hasPassword]).
  final UnlistedOrder? unlisted;

  /// The trade the screen shows, when the take starts from it: a take refused because the order still has that very trade open here (its close could not be written) is said as a refusal, not opened again over itself.
  final TradeRecord? shownTrade;
  final RobosatsNetwork network;
  final TakeCalls _calls;
  final HasGarageKey _hasKey;
  final Duration _stillWaitingAfter;
  Timer? _stillWaiting;

  /// Whether the step that runs has run for [stillWaitingAfter]: kept across its steps.
  bool _slow = false;

  /// The amount of the range the take is for, kept for a preparation made again.
  TakeAmount? _amount;

  /// The Bull wallet's price compared with the read's (#249), where the wallet's port was lent; `null` compares nothing.
  final CheckTakePrice? _checkPrice;
  final DateTime Function() _now;

  /// The last read of the Bull wallet's price of each currency (by its RoboSats id): when it came, and the check it gave; a read [staleAfter] old or more is forgotten at the next read.
  final Map<int, ({DateTime at, MakePriceCheck check})> _lastPrices = {};

  /// Bumped at each comparison started and at each read no longer shown, so that an answer for a read no longer shown is dropped.
  int _priceRead = 0;

  /// The read of the Bull wallet's price that runs, if one does ([priceSettled]).
  Future<MakePriceCheck>? _priceReading;

  TakeOrderCubit(
    this.order,
    this.network,
    this._calls,
    this._hasKey, {
    this._stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
    this.shownTrade,
    this.unlisted,
    this._checkPrice,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const TakeIdle()) {
    if (unlisted != null && _calls.prepareUnlisted == null) {
      throw ArgumentError('An order by its URL without its preparation.');
    }
  }

  /// The take of [shown], an order no book received (#245): [order] is the order as its robot read it.
  TakeOrderCubit.unlisted(
    UnlistedOrder shown,
    TakeCalls calls,
    HasGarageKey hasKey, {
    Duration stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
    CheckTakePrice? checkPrice,
    DateTime Function()? now,
  }) : this(
         shown.order,
         shown.network,
         calls,
         hasKey,
         stillWaitingAfter: stillWaitingAfter,
         unlisted: shown,
         checkPrice: checkPrice,
         now: now,
       );

  /// Whether a Garage Key is stored for the network, which decides between preparing the take and « You do not have a Garage Key » (`Dialogs/Confirmation.tsx`): `false` only when the vault says there is none; a key that cannot be read goes on, and the take says why it fails.
  Future<bool> hasGarageKey() async => switch (await _hasKey(network)) {
    Ok(:final value) => value,
    Err() => true,
  };

  /// Prepares the take of the order (« Take Order »), for [amount] when it has a range: the robot that will take it reads the order, which the order details then show.
  Future<void> take({TakeAmount? amount}) async {
    final current = state;
    if (isClosed || current is! TakeIdle || current.orderGone) return;
    _amount = amount;
    final next = await _prepared(previous: null, changed: false);
    if (!isClosed) emit(next);
    await _readPrice();
  }

  /// Sends the take of the order as it was read and shown ([TakeReady]): « Done » of « Store your garage key ».
  ///
  /// [password], for a protected order (#245), is the password the user typed, held as its hash only and passed on, never kept here; without it nothing is sent for such an order, the screen having said why. For an order without a password it is never sent.
  Future<void> confirm({OrderPassword? password}) async {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    final prepared = current.prepared;
    if (prepared.order.hasPassword && password == null) return;
    // A comparison still read is no longer awaited: its answer would be of a read the confirmation moves on from.
    _priceRead++;
    final price = switch (current.price) {
      TakePriceReading(:final shown?) => TakePriceChecked(shown),
      TakePriceReading() => const TakePriceNone(),
      final other => other,
    };
    emit(TakeConfirming(prepared, price: price));
    _startWaiting();
    final result = await _calls.confirm(
      prepared,
      password: prepared.order.hasPassword ? password : null,
      onStep: (step) {
        if (!isClosed && state is TakeConfirming) {
          emit(TakeConfirming(prepared, step: step, slow: _slow, price: price));
        }
      },
    );
    _stillWaiting?.cancel();
    if (isClosed) {
      // The page was left while the confirmation ran, and it was refused: the order's robot, kept for a new preparation, is forgotten (security review of #133).
      if (result is Err) _calls.abandonOrder(order, network: network);
      return;
    }
    switch (result) {
      // Read again by the robot, the order is no longer the one shown: prepared again, once, the read the user saw kept on screen meanwhile; never confirmed by itself.
      // The new read is compared anew once shown, from the Bull wallet's price already read when it is less than [staleAfter] old.
      case Err(failure: TakeOrderChanged()):
        final next = await _prepared(
          previous: prepared,
          changed: true,
          price: price,
        );
        if (!isClosed) emit(next);
        await _readPrice();
      // The preparation is gone (its key changed, or another one replaced it): prepared again, once, said changed when the new read shows the order otherwise.
      case Err(failure: TakePreparationGone()):
        final next = await _prepared(
          previous: prepared,
          changed: false,
          price: price,
        );
        if (!isClosed) emit(next);
        await _readPrice();
      case Err(failure: final refusal):
        emit(_refused(refusal));
      case Ok(value: TakeNotMade(:final refusal)):
        emit(TakeIdle(problem: TakeWasNotMade(refusal)));
      case Ok(value: final TakeStarted sent):
        emit(TakeSent(sent.record, prepared: prepared, price: price));
      case Ok(value: final TakeResumed sent):
        emit(TakeSent(sent.record, prepared: prepared, price: price));
      case Ok(value: final TakeOutcomeUnknown sent):
        emit(TakeSent(sent.record, prepared: prepared, price: price));
    }
  }

  /// Goes back from the order as it was read (« Go back », or « Go back » of « Store your garage key »): its preparation is abandoned, nothing is sent.
  void back() {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    _priceRead++;
    _calls.abandon(current.prepared);
    emit(const TakeIdle());
  }

  /// « Retry » of « Price not checked »: the Bull wallet's price read once more, « Price not checked » still drawn meanwhile with « Retry » not offered; never while a read runs, never once « Continue » moved on.
  Future<void> retryPrice() async {
    final current = state;
    if (isClosed ||
        current is! TakeReady ||
        current.price is! TakePriceChecked ||
        current.price.shownCheck is! MakePriceUnverified) {
      return;
    }
    await _readPrice(again: true);
  }

  /// When the Bull wallet's price is being read for the read shown: the end of that read, for « Continue » pressed meanwhile; at once otherwise. Bounded by the read itself, which the shell stops after 15 s (`ReadWalletRateUsecase.readBound`).
  Future<void> priceSettled() async {
    while (!isClosed && state.price is TakePriceReading) {
      final reading = _priceReading;
      if (reading == null) return;
      // The read's own continuation, registered first, shows its answer before this one runs.
      await reading;
    }
  }

  /// What the order page shows of the comparison now ([TakenPriceShown]), for the taker of the read shown; nothing while no read is shown.
  TakenPriceShown get priceShown {
    final read = switch (state) {
      TakeReady(:final prepared) || TakeConfirming(:final prepared) => prepared,
      TakePreparing(:final previous) => previous,
      TakeSent(:final prepared) => prepared,
      TakeIdle() => null,
    };
    if (read == null) return TakenPriceShown.nothing;
    return TakenPriceCheck.shownOf(state.price.shownCheck, read.terms.role);
  }

  /// The read shown compared with the Bull wallet's price, once [TakeReady] shows it and where the wallet's port was lent: from the last read for its currency when it is less than [staleAfter] old (nothing is sent then), else read; [again] (« Retry ») always reads. A coordinator's price that gives no figure (a premium of −100 %) is « Price not checked », nothing read.
  Future<void> _readPrice({bool again = false}) async {
    final check = _checkPrice;
    final current = state;
    if (check == null || isClosed || current is! TakeReady) return;
    final prepared = current.prepared;
    final terms = prepared.terms;
    final currency = terms.currency;
    final coordinatorPrice = TakenPriceCheck.coordinatorPrice(terms);
    if (coordinatorPrice == null) {
      _priceRead++;
      emit(
        TakeReady(
          prepared,
          previous: current.previous,
          price: TakePriceChecked(
            MakePriceCheck.of(
              currency: currency,
              coordinatorPrice: 0,
              wallet: const P2pWalletRateUnavailable(),
            ),
          ),
        ),
      );
      return;
    }
    final now = _now();
    _lastPrices.removeWhere((_, last) => now.difference(last.at) >= staleAfter);
    final last = _lastPrices[currency.id];
    if (!again && last != null) {
      _priceRead++;
      final kept = MakePriceSeen.of(
        currency: currency,
        coordinatorPrice: coordinatorPrice,
        check: last.check,
      ).checkAt(coordinatorPrice);
      if (kept != null) {
        emit(
          TakeReady(
            prepared,
            previous: current.previous,
            price: TakePriceChecked(kept),
          ),
        );
        return;
      }
    }
    final read = ++_priceRead;
    emit(
      TakeReady(
        prepared,
        previous: current.previous,
        price: TakePriceReading(shown: current.price.shownCheck),
      ),
    );
    final reading = check(network, currency, coordinatorPrice);
    _priceReading = reading;
    final result = await reading;
    if (identical(_priceReading, reading)) _priceReading = null;
    if (isClosed) return;
    // Kept for the next comparison of the currency even when the read it was for is no longer shown: a read made is never made again within [staleAfter].
    _lastPrices[currency.id] = (at: _now(), check: result);
    final shown = state;
    if (read != _priceRead ||
        shown is! TakeReady ||
        !identical(shown.prepared, prepared)) {
      return;
    }
    emit(
      TakeReady(
        prepared,
        previous: shown.previous,
        price: TakePriceChecked(result),
      ),
    );
  }

  /// The state after a preparation: [TakePreparing] meanwhile, with [previous], the read the user saw, when the order is read again, and [changed] when it is because it changed.
  ///
  /// The new read is said changed when [changed], or when it shows the order otherwise than [previous] ([PreparedTake.showsTheSameAs]).
  ///
  /// [price] is the comparison of [previous], drawn with it meanwhile.
  Future<TakeOrderState> _prepared({
    required PreparedTake? previous,
    required bool changed,
    TakePrice price = const TakePriceNone(),
  }) async {
    emit(TakePreparing(previous: previous, changed: changed, price: price));
    _startWaiting();
    void onStep(TakeStep step) {
      if (!isClosed && state is TakePreparing) {
        emit(
          TakePreparing(
            step: step,
            slow: _slow,
            previous: previous,
            changed: changed,
            price: price,
          ),
        );
      }
    }

    final unlisted = this.unlisted;
    // Read before the preparation, so before any robot it reserves (#251, § 4.2): the use case keeps it with a robot reserved now, never takes its robot from it.
    final garageRobot = switch (_calls.garageRobot) {
      final read? => await read(network),
      null => null,
    };
    final prepareUnlisted = _calls.prepareUnlisted;
    final result = unlisted != null && prepareUnlisted != null
        ? await prepareUnlisted(
            unlisted,
            amount: _amount,
            onStep: onStep,
            garageRobot: garageRobot,
          )
        : await _calls.prepare(
            order,
            network: network,
            amount: _amount,
            onStep: onStep,
            garageRobot: garageRobot,
          );
    _stillWaiting?.cancel();
    if (isClosed) {
      // The page was left while the order was read: what was prepared is abandoned at once.
      if (result case Ok(value: final prepared)) _calls.abandon(prepared);
      return state;
    }
    return switch (result) {
      Ok(value: final prepared) => TakeReady(
        prepared,
        previous:
            previous != null && (changed || !prepared.showsTheSameAs(previous))
            ? previous
            : null,
      ),
      // Abandoned while it ran, or another order prepared meanwhile: nothing to say.
      Err(failure: TakePreparationGone()) => const TakeIdle(),
      Err(failure: final refusal) => _refused(refusal),
    };
  }

  /// The state after a [refusal] of either step.
  TakeOrderState _refused(TakeRefusal refusal) => switch (refusal) {
    // The order already has an open trade on this device: that trade is opened rather than taken again.
    // ... unless it is the trade on screen, whose close could not be written: said as a refusal, never opened over itself.
    TakeOrderAlreadyTraded(:final record) when record == shownTrade => TakeIdle(
      problem: TakeWasRefused(refusal),
    ),
    TakeOrderAlreadyTraded(:final record) => TakeSent(record),
    _ => TakeIdle(problem: TakeWasRefused(refusal)),
  };

  /// Says, after [stillWaitingAfter], that the preparation or the confirmation that runs still waits, whatever its step.
  void _startWaiting() {
    _stillWaiting?.cancel();
    _slow = false;
    _stillWaiting = Timer(_stillWaitingAfter, () {
      _slow = true;
      if (isClosed) return;
      switch (state) {
        case TakePreparing(
          :final step,
          :final previous,
          :final changed,
          :final price,
        ):
          emit(
            TakePreparing(
              step: step,
              slow: true,
              previous: previous,
              changed: changed,
              price: price,
            ),
          );
        case TakeConfirming(:final prepared, :final step, :final price):
          emit(TakeConfirming(prepared, step: step, slow: true, price: price));
        case _:
          break;
      }
    });
  }

  @override
  Future<void> close() {
    _stillWaiting?.cancel();
    switch (state) {
      case TakeReady(:final prepared):
        _calls.abandon(prepared);
      // The user confirmed: the take finishes, and its trade is in the active trades.
      case TakeConfirming() || TakeSent():
        break;
      // After a preparation that failed, or while one runs: the order's robot, if one is kept, is forgotten.
      case TakeIdle() || TakePreparing():
        _calls.abandonOrder(order, network: network);
    }
    return super.close();
  }
}
