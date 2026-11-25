import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/robot_binding.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/take_order_usecase.dart';

/// [TakeOrderUsecase.readUnlisted], which the locator gives the cubit.
typedef ReadUnlistedOrder =
    Future<Result<UnlistedOrder, TakeRefusal>> Function(
      Coordinator coordinator,
      int orderId, {
      required RobosatsNetwork network,
      TakeProgress? onStep,
      RobotSlot? garageRobot,
    });

/// [TakeOrderUsecase.abandonRead], which the locator gives the cubit.
typedef AbandonUnlistedRead =
    void Function(
      Coordinator coordinator,
      int orderId, {
      required RobosatsNetwork network,
    });

/// Where the read of an order no book received stands, on its page (#245).
@immutable
sealed class UnlistedOrderState {
  const UnlistedOrderState();
}

/// The robot that will take the order reads it: [step] is what it does now, `null` until the first one starts, and [slow] says it has run for a while.
final class UnlistedOrderReading extends UnlistedOrderState {
  final TakeStep? step;
  final bool slow;

  const UnlistedOrderReading({this.step, this.slow = false});
}

/// The robot read the order: the page shows [order], with « Password » and « Take Order ».
final class UnlistedOrderShown extends UnlistedOrderState {
  final UnlistedOrder order;

  const UnlistedOrderShown(this.order);
}

/// The order could not be read as a public order: [refusal] says why; [canRetry] when another read may give it (the coordinator not reached, a robot refused), never for an order gone.
final class UnlistedOrderRefused extends UnlistedOrderState {
  final TakeRefusal refusal;

  const UnlistedOrderRefused(this.refusal);

  bool get canRetry => switch (refusal) {
    TakeOrderGone() || TakeOrderAlreadyTraded() => false,
    _ => true,
  };
}

/// The order has an open trade on this device (a take, or an order made here): its trade is the screen to show.
final class UnlistedOrderTraded extends UnlistedOrderState {
  final TradeRecord record;

  const UnlistedOrderTraded(this.record);
}

/// Reads one order that no book received, a password-protected one or a public one the book in memory does not hold yet, with the robot that will take it, for its page (#245): the only caller of [TakeOrderUsecase.readUnlisted].
///
/// [load] reads once, [retry] once per press; nothing reads by itself. Closing the cubit before the order is shown forgets the robot kept for it; once shown, the take's cubit on the page holds it.
class UnlistedOrderCubit extends Cubit<UnlistedOrderState> {
  final Coordinator coordinator;
  final int orderId;
  final RobosatsNetwork network;
  final ReadUnlistedOrder _read;
  final AbandonUnlistedRead _abandon;
  final Duration _stillWaitingAfter;

  /// The robot the Garage would show, read before the read reserves its robot, for the line of the order page (#251); `null` where none is read.
  final Future<RobotSlot?> Function(RobosatsNetwork network)? _garageRobot;
  Timer? _stillWaiting;

  bool _slow = false;

  UnlistedOrderCubit(
    this.coordinator,
    this.orderId,
    this.network,
    this._read,
    this._abandon, {
    this._stillWaitingAfter = const Duration(seconds: 30),
    this._garageRobot,
  }) : super(const UnlistedOrderReading());

  /// Reads the order, once.
  Future<void> load() async {
    if (isClosed) return;
    emit(const UnlistedOrderReading());
    _stillWaiting?.cancel();
    _slow = false;
    _stillWaiting = Timer(_stillWaitingAfter, () {
      _slow = true;
      if (isClosed) return;
      if (state case UnlistedOrderReading(:final step)) {
        emit(UnlistedOrderReading(step: step, slow: true));
      }
    });
    // Read before the robot is reserved (#251, § 4.2).
    RobotSlot? garageRobot;
    if (_garageRobot case final read?) {
      garageRobot = await read(network);
      if (isClosed) {
        _stillWaiting?.cancel();
        return;
      }
    }
    final result = await _read(
      coordinator,
      orderId,
      network: network,
      garageRobot: garageRobot,
      onStep: (step) {
        if (!isClosed && state is UnlistedOrderReading) {
          emit(UnlistedOrderReading(step: step, slow: _slow));
        }
      },
    );
    _stillWaiting?.cancel();
    if (isClosed) {
      _abandon(coordinator, orderId, network: network);
      return;
    }
    emit(switch (result) {
      Ok(:final value) => UnlistedOrderShown(value),
      Err(failure: TakeOrderAlreadyTraded(:final record)) =>
        UnlistedOrderTraded(record),
      Err(:final failure) => UnlistedOrderRefused(failure),
    });
  }

  /// « Retry »: reads the order again, once, after a refusal that another read may change.
  Future<void> retry() async {
    if (state case final UnlistedOrderRefused refused when refused.canRetry) {
      await load();
    }
  }

  @override
  Future<void> close() {
    _stillWaiting?.cancel();
    // Once shown, the take's cubit of the page forgets the robot when it closes.
    if (state is! UnlistedOrderShown) {
      _abandon(coordinator, orderId, network: network);
    }
    return super.close();
  }
}
