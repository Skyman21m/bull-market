import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/usecases/fetch_coordinator_info_usecase.dart';
import '../domain/usecases/find_public_order_usecase.dart';

/// [FetchCoordinatorInfoUsecase.execute], which the locator gives the cubit.
typedef CoordinatorInfoReader =
    Future<Result<CoordinatorInfo, CoordinatorFailure>> Function(
      Coordinator coordinator,
      RobosatsNetwork network,
    );

/// [FindPublicOrderUsecase.execute], which the locator gives the cubit.
typedef PublicOrderFinder =
    Future<Result<PublicOrder?, CoordinatorFailure>> Function(
      Coordinator coordinator,
      RobosatsNetwork network, {
      required int orderId,
      required RobosatsCurrency currency,
      required OrderType type,
    });

/// What the order's side of the trade screen shows besides the order itself: the fees its coordinator announces, and, once the order is public again, the order as the book lists it, which « Take Order » takes.
@immutable
final class TradeOrderPageState {
  /// What the coordinator says about itself, `null` until it answers or when it does not (the fee row is then empty and the estimate counts no fee, as the reference does without its info).
  final CoordinatorInfo? info;
  final PublicOrderLookup publicOrder;

  const TradeOrderPageState({
    this.info,
    this.publicOrder = const PublicOrderNotLooked(),
  });

  TradeOrderPageState _with({
    CoordinatorInfo? info,
    PublicOrderLookup? publicOrder,
  }) => TradeOrderPageState(
    info: info ?? this.info,
    publicOrder: publicOrder ?? this.publicOrder,
  );
}

/// Where the order public again stands in its coordinator's book.
@immutable
sealed class PublicOrderLookup {
  const PublicOrderLookup();
}

final class PublicOrderNotLooked extends PublicOrderLookup {
  const PublicOrderNotLooked();
}

final class PublicOrderLooking extends PublicOrderLookup {
  final int orderId;

  const PublicOrderLooking(this.orderId);
}

/// The book lists it: « Take Order » takes [order].
final class PublicOrderFound extends PublicOrderLookup {
  final PublicOrder order;

  const PublicOrderFound(this.order);
}

/// The book does not list it: it cannot be taken from here.
final class PublicOrderNotListed extends PublicOrderLookup {
  final int orderId;

  const PublicOrderNotListed(this.orderId);
}

/// The book could not be read: nothing is said of the order, and « Retry » reads it again ([TradeOrderPageCubit.retryPublic]).
final class PublicOrderLookFailed extends PublicOrderLookup {
  final int orderId;

  const PublicOrderLookFailed(this.orderId);
}

/// Reads, without a robot, what the order's side of the trade screen shows besides the order: the only caller of [FindPublicOrderUsecase].
class TradeOrderPageCubit extends Cubit<TradeOrderPageState> {
  /// The trade's coordinator, `null` when the federation no longer lists it: nothing is then asked.
  final Coordinator? coordinator;
  final RobosatsNetwork network;
  final CoordinatorInfoReader _info;
  final PublicOrderFinder _find;
  bool _askedInfo = false;

  TradeOrderPageCubit(this.coordinator, this.network, this._info, this._find)
    : super(const TradeOrderPageState());

  /// Asks the coordinator for its fees, once.
  Future<void> loadInfo() async {
    final coordinator = this.coordinator;
    if (_askedInfo || isClosed || coordinator == null) return;
    _askedInfo = true;
    final result = await _info(coordinator, network);
    if (isClosed) return;
    if (result case Ok(:final value)) emit(state._with(info: value));
  }

  /// Looks for [order], public again, in its coordinator's book: once per order, a second call while one runs or after it ended doing nothing, a failed read included (only [retryPublic] reads again).
  Future<void> findPublic(CoordinatorOrder order) async {
    switch (state.publicOrder) {
      case PublicOrderLooking(:final orderId) ||
              PublicOrderNotListed(:final orderId) ||
              PublicOrderLookFailed(:final orderId)
          when orderId == order.id:
        return;
      case PublicOrderFound(order: final found) when found.id == order.id:
        return;
      case _:
        await _look(order);
    }
  }

  /// Reads the book again once, on « Retry », after a read of it failed for [order]; nothing retries by itself.
  Future<void> retryPublic(CoordinatorOrder order) async {
    if (state.publicOrder case PublicOrderLookFailed(
      :final orderId,
    ) when orderId == order.id) {
      await _look(order);
    }
  }

  Future<void> _look(CoordinatorOrder order) async {
    final coordinator = this.coordinator;
    if (isClosed || coordinator == null) return;
    emit(state._with(publicOrder: PublicOrderLooking(order.id)));
    final result = await _find(
      coordinator,
      network,
      orderId: order.id,
      currency: order.currency,
      type: order.type,
    );
    if (isClosed) return;
    emit(
      state._with(
        publicOrder: switch (result) {
          Ok(value: final found?) => PublicOrderFound(found),
          Ok() => PublicOrderNotListed(order.id),
          Err() => PublicOrderLookFailed(order.id),
        },
      ),
    );
  }
}
