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
    });

/// [TakeOrderUsecase.confirm], which the locator gives the cubit.
typedef ConfirmTake =
    Future<Result<TakeOutcome, TakeRefusal>> Function(PreparedTake prepared);

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
  final ConfirmTake confirm;
  final AbandonTake abandon;
  final AbandonOrderTake abandonOrder;

  const TakeCalls({
    required this.prepare,
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

/// Nothing runs: « Take Order » can be pressed; [problem] says why the last take did not happen, when one was tried.
final class TakeIdle extends TakeOrderState {
  final TakeProblem? problem;

  const TakeIdle({this.problem});
}

/// The order is read by the robot that will take it (the order read again, a robot put on the coordinator, its read of the order): it can take a minute over Tor, and [slow] says it has run for a while.
final class TakePreparing extends TakeOrderState {
  final bool slow;

  const TakePreparing({this.slow = false});
}

/// The robot read the order: the order details show [prepared], and the user confirms the take or goes back; [changed] says that the order changed since the read the user had seen, and these are its new figures.
final class TakeReady extends TakeOrderState {
  final PreparedTake prepared;
  final bool changed;

  const TakeReady(this.prepared, {this.changed = false});
}

/// The take of [prepared] is confirmed and runs (the order read again by the same robot, then the take sent); [slow] says it has run for a while.
final class TakeConfirming extends TakeOrderState {
  final PreparedTake prepared;
  final bool slow;

  const TakeConfirming(this.prepared, {this.slow = false});
}

/// The take was sent and started a trade, resumed one, or its outcome is unknown, or the order already had an open trade here: the trade of [record] is the screen to show (the watch of the trade resolves an unknown outcome).
final class TakeSent extends TakeOrderState {
  final TradeRecord record;

  const TakeSent(this.record);
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
/// [take] prepares: the order read by the robot that will take it, which the order details then show ([TakeReady]); [confirm] sends the take of what the user saw; [back] abandons it.
/// One step runs at a time: a second [take] or [confirm] while one runs, or after the take was sent, does nothing, so a double tap sends one request.
/// Nothing is confirmed by itself: when the confirmation finds the order changed ([TakeOrderChanged]) or its preparation gone ([TakePreparationGone]), the order is prepared again, once, and its new figures wait for the user.
/// Closing the cubit (the page left, a system back) abandons what is prepared, or the order when the last preparation failed, so that no robot stays kept for it; a confirmation that runs then is left to finish, the user having confirmed it.
class TakeOrderCubit extends Cubit<TakeOrderState> {
  /// After how long a step that runs is said to be still waiting, as the robot panel of the Garage does (`RobotCoordinatorCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  /// The locator's name of the cubit that takes an order public again from the trade screen, given the trade shown ([shownTrade]).
  static const fromTrade = 'fromTrade';

  final PublicOrder order;

  /// The trade the screen shows, when the take starts from it: a take refused because the order still has that very trade open here (its close could not be written) is said as a refusal, not opened again over itself.
  final TradeRecord? shownTrade;
  final RobosatsNetwork network;
  final TakeCalls _calls;
  final HasGarageKey _hasKey;
  final Duration _stillWaitingAfter;
  Timer? _stillWaiting;

  /// The amount of the range the take is for, kept for a preparation made again.
  TakeAmount? _amount;

  TakeOrderCubit(
    this.order,
    this.network,
    this._calls,
    this._hasKey, {
    this._stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
    this.shownTrade,
  }) : super(const TakeIdle());

  /// Whether a Garage Key is stored for the network, which decides between « Store your garage key » and « You do not have a Garage Key » (`Dialogs/Confirmation.tsx`): `false` only when the vault says there is none; a key that cannot be read goes on, and the take says why it fails.
  Future<bool> hasGarageKey() async => switch (await _hasKey(network)) {
    Ok(:final value) => value,
    Err() => true,
  };

  /// Prepares the take of the order, for [amount] when it has a range: the robot that will take it reads the order, which the order details then show.
  Future<void> take({TakeAmount? amount}) async {
    if (isClosed || state is! TakeIdle) return;
    _amount = amount;
    final next = await _prepared(changed: false);
    if (!isClosed) emit(next);
  }

  /// Sends the take of the order as it was read and shown ([TakeReady]).
  Future<void> confirm() async {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    final prepared = current.prepared;
    emit(TakeConfirming(prepared));
    _waitFor(() => TakeConfirming(prepared, slow: true));
    final result = await _calls.confirm(prepared);
    _stillWaiting?.cancel();
    if (isClosed) return;
    switch (result) {
      // Read again by the robot, the order is no longer the one shown, or the preparation is gone: prepared again, once, and its new figures shown; never confirmed by itself.
      case Err(failure: TakeOrderChanged() || TakePreparationGone()):
        final next = await _prepared(
          changed: switch (result) {
            Err(failure: TakeOrderChanged()) => true,
            _ => false,
          },
        );
        if (!isClosed) emit(next);
      case Err(failure: final refusal):
        emit(_refused(refusal));
      case Ok(value: TakeNotMade(:final refusal)):
        emit(TakeIdle(problem: TakeWasNotMade(refusal)));
      case Ok(value: final TakeStarted sent):
        emit(TakeSent(sent.record));
      case Ok(value: final TakeResumed sent):
        emit(TakeSent(sent.record));
      case Ok(value: final TakeOutcomeUnknown sent):
        emit(TakeSent(sent.record));
    }
  }

  /// Goes back from the order as it was read: its preparation is abandoned, nothing is sent.
  void back() {
    final current = state;
    if (isClosed || current is! TakeReady) return;
    _calls.abandon(current.prepared);
    emit(const TakeIdle());
  }

  /// The state after a preparation: [TakePreparing] meanwhile.
  Future<TakeOrderState> _prepared({required bool changed}) async {
    emit(const TakePreparing());
    _waitFor(() => const TakePreparing(slow: true));
    final result = await _calls.prepare(
      order,
      network: network,
      amount: _amount,
    );
    _stillWaiting?.cancel();
    if (isClosed) {
      // The page was left while the order was read: what was prepared is abandoned at once.
      if (result case Ok(value: final prepared)) _calls.abandon(prepared);
      return state;
    }
    return switch (result) {
      Ok(value: final prepared) => TakeReady(prepared, changed: changed),
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

  /// Says, after [stillWaitingAfter], that the step that runs still waits.
  void _waitFor(TakeOrderState Function() slow) {
    _stillWaiting?.cancel();
    final running = state;
    _stillWaiting = Timer(_stillWaitingAfter, () {
      if (!isClosed && identical(state, running)) emit(slow());
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
