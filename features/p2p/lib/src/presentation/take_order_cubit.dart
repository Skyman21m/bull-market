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

/// [TakeOrderUsecase.execute], which the locator gives the cubit.
typedef TakeOrder =
    Future<Result<TakeOutcome, TakeRefusal>> Function(
      PublicOrder shown, {
      required RobosatsNetwork network,
      TakeAmount? amount,
      OrderPassword? password,
    });

/// [HasGarageKeyUsecase.execute], which the locator gives the cubit.
typedef HasGarageKey =
    Future<Result<bool, P2pFailure>> Function(RobosatsNetwork network);

/// Where the take of one order of the book stands, on its order details (#88).
@immutable
sealed class TakeOrderState {
  const TakeOrderState();
}

/// Nothing runs: « Take Order » can be pressed; [problem] says why the last take did not happen, when one was tried.
final class TakeIdle extends TakeOrderState {
  final TakeProblem? problem;

  const TakeIdle({this.problem});
}

/// The take runs (the order read again, a robot put on the coordinator, the take sent): it can take a minute over Tor, and [slow] says it has run for a while.
final class TakeRunning extends TakeOrderState {
  final bool slow;

  const TakeRunning({this.slow = false});
}

/// The take was sent and started a trade, resumed one, or its outcome is unknown: the trade of [record] is the screen to show (the watch of the trade resolves an unknown outcome).
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

/// Takes one order of the book for a fresh robot of this device (#88): the only caller of [TakeOrderUsecase], which the locator gives it as its `execute`.
///
/// A take runs once at a time: a second [take] while one runs, or after one was sent, does nothing, so a double tap sends one request.
/// Nothing is retried: after a problem, the user presses « Take Order » again.
class TakeOrderCubit extends Cubit<TakeOrderState> {
  /// After how long a take that runs is said to be still waiting, as the robot panel of the Garage does (`RobotCoordinatorCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  final PublicOrder order;
  final RobosatsNetwork network;
  final TakeOrder _take;
  final HasGarageKey _hasKey;
  final Duration _stillWaitingAfter;
  Timer? _stillWaiting;

  TakeOrderCubit(
    this.order,
    this.network,
    this._take,
    this._hasKey, {
    this._stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
  }) : super(const TakeIdle());

  /// Whether a Garage Key is stored for the network, which decides between « Store your garage key » and « You do not have a Garage Key » (`Dialogs/Confirmation.tsx`): `false` only when the vault says there is none; a key that cannot be read goes on, and the take says why it fails.
  Future<bool> hasGarageKey() async => switch (await _hasKey(network)) {
    Ok(:final value) => value,
    Err() => true,
  };

  /// Takes the order, for [amount] when it has a range.
  Future<void> take({TakeAmount? amount}) async {
    if (isClosed || state is TakeRunning || state is TakeSent) return;
    emit(const TakeRunning());
    _stillWaiting = Timer(_stillWaitingAfter, () {
      if (!isClosed && state is TakeRunning) {
        emit(const TakeRunning(slow: true));
      }
    });
    final result = await _take(order, network: network, amount: amount);
    _stillWaiting?.cancel();
    if (isClosed) return;
    emit(switch (result) {
      Err(:final failure) => TakeIdle(problem: TakeWasRefused(failure)),
      Ok(value: TakeNotMade(:final refusal)) => TakeIdle(
        problem: TakeWasNotMade(refusal),
      ),
      Ok(value: final TakeStarted sent) => TakeSent(sent.record),
      Ok(value: final TakeResumed sent) => TakeSent(sent.record),
      Ok(value: final TakeOutcomeUnknown sent) => TakeSent(sent.record),
    });
  }

  @override
  Future<void> close() {
    _stillWaiting?.cancel();
    return super.close();
  }
}
