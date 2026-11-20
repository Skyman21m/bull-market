import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/take_order_usecase.dart';

/// [TakeOrderUsecase.readProtected], which the locator gives the cubit.
typedef ReadProtectedOrder =
    Future<Result<ProtectedOrder, TakeRefusal>> Function(
      Coordinator coordinator,
      int orderId, {
      required RobosatsNetwork network,
      TakeProgress? onStep,
    });

/// [TakeOrderUsecase.abandonRead], which the locator gives the cubit.
typedef AbandonProtectedRead =
    void Function(
      Coordinator coordinator,
      int orderId, {
      required RobosatsNetwork network,
    });

/// Where the read of a password-protected order stands, on its page (#245).
@immutable
sealed class ProtectedOrderState {
  const ProtectedOrderState();
}

/// The robot that will take the order reads it: [step] is what it does now, `null` until the first one starts, and [slow] says it has run for a while.
final class ProtectedOrderReading extends ProtectedOrderState {
  final TakeStep? step;
  final bool slow;

  const ProtectedOrderReading({this.step, this.slow = false});
}

/// The robot read the order: the page shows [order], with « Password » and « Take Order ».
final class ProtectedOrderShown extends ProtectedOrderState {
  final ProtectedOrder order;

  const ProtectedOrderShown(this.order);
}

/// The order could not be read as a protected public order: [refusal] says why; [canRetry] when another read may give it (the coordinator not reached, a robot refused), never for an order gone.
final class ProtectedOrderRefused extends ProtectedOrderState {
  final TakeRefusal refusal;

  const ProtectedOrderRefused(this.refusal);

  bool get canRetry => switch (refusal) {
    TakeOrderGone() || TakeOrderAlreadyTraded() => false,
    _ => true,
  };
}

/// The order has an open trade on this device (a take, or an order made here): its trade is the screen to show.
final class ProtectedOrderTraded extends ProtectedOrderState {
  final TradeRecord record;

  const ProtectedOrderTraded(this.record);
}

/// Reads one order that the public book does not list, such as a password-protected one, with the robot that will take it, for its page (#245): the only caller of [TakeOrderUsecase.readProtected].
///
/// [load] reads once, [retry] once per press; nothing reads by itself. Closing the cubit before the order is shown forgets the robot kept for it; once shown, the take's cubit on the page holds it.
class ProtectedOrderCubit extends Cubit<ProtectedOrderState> {
  final Coordinator coordinator;
  final int orderId;
  final RobosatsNetwork network;
  final ReadProtectedOrder _read;
  final AbandonProtectedRead _abandon;
  final Duration _stillWaitingAfter;
  Timer? _stillWaiting;

  bool _slow = false;

  ProtectedOrderCubit(
    this.coordinator,
    this.orderId,
    this.network,
    this._read,
    this._abandon, {
    this._stillWaitingAfter = const Duration(seconds: 30),
  }) : super(const ProtectedOrderReading());

  /// Reads the order, once.
  Future<void> load() async {
    if (isClosed) return;
    emit(const ProtectedOrderReading());
    _stillWaiting?.cancel();
    _slow = false;
    _stillWaiting = Timer(_stillWaitingAfter, () {
      _slow = true;
      if (isClosed) return;
      if (state case ProtectedOrderReading(:final step)) {
        emit(ProtectedOrderReading(step: step, slow: true));
      }
    });
    final result = await _read(
      coordinator,
      orderId,
      network: network,
      onStep: (step) {
        if (!isClosed && state is ProtectedOrderReading) {
          emit(ProtectedOrderReading(step: step, slow: _slow));
        }
      },
    );
    _stillWaiting?.cancel();
    if (isClosed) {
      _abandon(coordinator, orderId, network: network);
      return;
    }
    emit(switch (result) {
      Ok(:final value) => ProtectedOrderShown(value),
      Err(failure: TakeOrderAlreadyTraded(:final record)) =>
        ProtectedOrderTraded(record),
      Err(:final failure) => ProtectedOrderRefused(failure),
    });
  }

  /// « Retry »: reads the order again, once, after a refusal that another read may change.
  Future<void> retry() async {
    if (state case final ProtectedOrderRefused refused when refused.canRetry) {
      await load();
    }
  }

  @override
  Future<void> close() {
    _stillWaiting?.cancel();
    // Once shown, the take's cubit of the page forgets the robot when it closes.
    if (state is! ProtectedOrderShown) {
      _abandon(coordinator, orderId, network: network);
    }
    return super.close();
  }
}
