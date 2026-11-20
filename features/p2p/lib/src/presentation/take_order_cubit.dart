import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
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
    });

/// [TakeOrderUsecase.prepareProtected], which the locator gives the cubit (#245).
typedef PrepareProtectedTake =
    Future<Result<PreparedTake, TakeRefusal>> Function(
      ProtectedOrder shown, {
      TakeAmount? amount,
      TakeProgress? onStep,
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

/// [HasGarageKeyUsecase.execute], which the locator gives the cubit.
typedef HasGarageKey =
    Future<Result<bool, P2pFailure>> Function(RobosatsNetwork network);

/// The use case's calls that the cubit makes: the take in two steps (#119).
@immutable
final class TakeCalls {
  final PrepareTake prepare;

  /// The preparation of a password-protected order (#245), given by the locator; `null` where no protected order is taken.
  final PrepareProtectedTake? prepareProtected;
  final ConfirmTake confirm;
  final AbandonTake abandon;
  final AbandonOrderTake abandonOrder;

  const TakeCalls({
    required this.prepare,
    this.prepareProtected,
    required this.confirm,
    required this.abandon,
    required this.abandonOrder,
  });
}

/// Where the take of one order of the book stands, on its order details (#88, #119).
@immutable
sealed class TakeOrderState {
  const TakeOrderState();
}

/// Nothing runs: « Take Order » can be pressed, unless the order is gone ([orderGone]); [problem] says why the last take did not happen, when one was tried.
final class TakeIdle extends TakeOrderState {
  final TakeProblem? problem;

  const TakeIdle({this.problem});

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
/// [previous] is the read the user saw, when the confirmation found the order changed or its preparation gone and the order is read again: it stays shown meanwhile; [changed] says the order changed, which the screen says at once.
final class TakePreparing extends TakeOrderState {
  final TakeStep? step;
  final bool slow;
  final PreparedTake? previous;
  final bool changed;

  const TakePreparing({
    this.step,
    this.slow = false,
    this.previous,
    this.changed = false,
  });
}

/// The robot read the order: the order details show [prepared], and the user goes on (« Continue », then « Store your garage key » and its « Done ») or goes back.
///
/// [previous] is the read the user saw before, when the order changed at the confirmation, or when a read made again after its preparation was gone shows it otherwise: the rows that differ from it are marked.
final class TakeReady extends TakeOrderState {
  final PreparedTake prepared;
  final PreparedTake? previous;

  const TakeReady(this.prepared, {this.previous});

  /// Whether the order changed since the read the user had seen.
  bool get changed => previous != null;
}

/// The take of [prepared] is confirmed and runs (the order read again by the same robot, then the take sent); [step] is what it does now, and [slow] says it has run for a while.
final class TakeConfirming extends TakeOrderState {
  final PreparedTake prepared;
  final TakeStep? step;
  final bool slow;

  const TakeConfirming(this.prepared, {this.step, this.slow = false});
}

/// The take was sent and started a trade, resumed one, or its outcome is unknown, or the order already had an open trade here: the trade of [record] is the screen to show (the watch of the trade resolves an unknown outcome).
///
/// [prepared] is the read the take was sent on, which stays shown until the trade's screen opens.
final class TakeSent extends TakeOrderState {
  final TradeRecord record;
  final PreparedTake? prepared;

  const TakeSent(this.record, {this.prepared});
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
class TakeOrderCubit extends Cubit<TakeOrderState> {
  /// After how long a step that runs is said to be still waiting, as the robot panel of the Garage does (`RobotCoordinatorCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  /// The locator's name of the cubit that takes an order public again from the trade screen, given the trade shown ([shownTrade]).
  static const fromTrade = 'fromTrade';

  /// The locator's name of the cubit that takes a password-protected order its robot read ([TakeOrderCubit.protected], #245).
  static const protectedOrder = 'protectedOrder';

  final PublicOrder order;

  /// The password-protected order the page shows, as its robot read it (#245), `null` for an order of the book: its take is prepared with [TakeCalls.prepareProtected] and confirmed with the password's hash.
  final ProtectedOrder? protected;

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

  TakeOrderCubit(
    this.order,
    this.network,
    this._calls,
    this._hasKey, {
    this._stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
    this.shownTrade,
    this.protected,
  }) : super(const TakeIdle()) {
    if (protected != null && _calls.prepareProtected == null) {
      throw ArgumentError('A protected order without its preparation.');
    }
  }

  /// The take of the password-protected order [shown] (#245): [order] is the order as its robot read it.
  TakeOrderCubit.protected(
    ProtectedOrder shown,
    TakeCalls calls,
    HasGarageKey hasKey, {
    Duration stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
  }) : this(
         shown.order,
         shown.network,
         calls,
         hasKey,
         stillWaitingAfter: stillWaitingAfter,
         protected: shown,
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
  }

  /// Sends the take of the order as it was read and shown ([TakeReady]): « Done » of « Store your garage key ».
  ///
  /// [password], for a protected order (#245), is the password the user typed, held as its hash only and passed on, never kept here; without it nothing is sent for such an order, the screen having said why. For an order without a password it is never sent.
  Future<void> confirm({OrderPassword? password}) async {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    final prepared = current.prepared;
    if (prepared.order.hasPassword && password == null) return;
    emit(TakeConfirming(prepared));
    _startWaiting();
    final result = await _calls.confirm(
      prepared,
      password: prepared.order.hasPassword ? password : null,
      onStep: (step) {
        if (!isClosed && state is TakeConfirming) {
          emit(TakeConfirming(prepared, step: step, slow: _slow));
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
      case Err(failure: TakeOrderChanged()):
        final next = await _prepared(previous: prepared, changed: true);
        if (!isClosed) emit(next);
      // The preparation is gone (its key changed, or another one replaced it): prepared again, once, said changed when the new read shows the order otherwise.
      case Err(failure: TakePreparationGone()):
        final next = await _prepared(previous: prepared, changed: false);
        if (!isClosed) emit(next);
      case Err(failure: final refusal):
        emit(_refused(refusal));
      case Ok(value: TakeNotMade(:final refusal)):
        emit(TakeIdle(problem: TakeWasNotMade(refusal)));
      case Ok(value: final TakeStarted sent):
        emit(TakeSent(sent.record, prepared: prepared));
      case Ok(value: final TakeResumed sent):
        emit(TakeSent(sent.record, prepared: prepared));
      case Ok(value: final TakeOutcomeUnknown sent):
        emit(TakeSent(sent.record, prepared: prepared));
    }
  }

  /// Goes back from the order as it was read (« Go back », or « Go back » of « Store your garage key »): its preparation is abandoned, nothing is sent.
  void back() {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    _calls.abandon(current.prepared);
    emit(const TakeIdle());
  }

  /// The state after a preparation: [TakePreparing] meanwhile, with [previous], the read the user saw, when the order is read again, and [changed] when it is because it changed.
  ///
  /// The new read is said changed when [changed], or when it shows the order otherwise than [previous] ([PreparedTake.showsTheSameAs]).
  Future<TakeOrderState> _prepared({
    required PreparedTake? previous,
    required bool changed,
  }) async {
    emit(TakePreparing(previous: previous, changed: changed));
    _startWaiting();
    void onStep(TakeStep step) {
      if (!isClosed && state is TakePreparing) {
        emit(
          TakePreparing(
            step: step,
            slow: _slow,
            previous: previous,
            changed: changed,
          ),
        );
      }
    }

    final protected = this.protected;
    final prepareProtected = _calls.prepareProtected;
    final result = protected != null && prepareProtected != null
        ? await prepareProtected(protected, amount: _amount, onStep: onStep)
        : await _calls.prepare(
            order,
            network: network,
            amount: _amount,
            onStep: onStep,
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
        case TakePreparing(:final step, :final previous, :final changed):
          emit(
            TakePreparing(
              step: step,
              slow: true,
              previous: previous,
              changed: changed,
            ),
          );
        case TakeConfirming(:final prepared, :final step):
          emit(TakeConfirming(prepared, step: step, slow: true));
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
