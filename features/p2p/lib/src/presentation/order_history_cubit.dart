import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/order_history.dart';
import '../domain/p2p_failure.dart';
import '../domain/usecases/trade/list_order_history_usecase.dart';

/// [ListOrderHistoryUsecase.execute], which the locator gives the cubit.
typedef OrderHistoryLister =
    Stream<Result<List<FinishedOrder>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// What the records gave of the history (#253).
@immutable
sealed class OrderHistoryRead {
  const OrderHistoryRead();
}

/// The records are being read.
final class OrderHistoryLoading extends OrderHistoryRead {
  const OrderHistoryLoading();
}

/// The finished orders of the key, the newest end first; empty when there is none.
final class OrderHistoryListed extends OrderHistoryRead {
  final List<FinishedOrder> orders;

  const OrderHistoryListed(this.orders);
}

/// The records cannot be read: said, never shown as « no order ».
final class OrderHistoryUnreadable extends OrderHistoryRead {
  const OrderHistoryUnreadable();
}

/// The history of the Garage: what the records gave, whether the user opened it, and how many of its lines are shown.
@immutable
final class OrderHistoryState {
  final OrderHistoryRead read;

  /// Whether the user opened it: folded at each arrival in the Garage, never remembered open.
  final bool open;

  /// How many lines are shown while it is open: [OrderHistory.page], and as many more at each « See more ».
  final int shown;

  const OrderHistoryState._(
    this.read, {
    required this.open,
    required this.shown,
  });

  /// The lines drawn: none while folded, the first [shown] while open.
  List<FinishedOrder> get lines => switch (read) {
    OrderHistoryListed(:final orders) when open => List.unmodifiable(
      orders.take(shown),
    ),
    _ => const [],
  };

  /// Whether « See more » has lines left to show.
  bool get hasMore => switch (read) {
    OrderHistoryListed(:final orders) => open && orders.length > shown,
    _ => false,
  };

  /// Counts only: never an order number, a coordinator or a robot.
  @override
  String toString() => switch (read) {
    OrderHistoryListed(:final orders) =>
      'OrderHistoryState(${orders.length} orders, open: $open, shown: $shown)',
    _ => 'OrderHistoryState(${read.runtimeType}, open: $open)',
  };
}

/// The history of finished orders of every Garage Key of one network (#81: each line says its key), while the Garage shows its profile (#253, design note `docs/design/phase-3-order-history.md`): read from the device only, nothing asked of a coordinator, nothing written.
///
/// It reads from [start], so that the Garage knows whether the history holds an order the « Last order #N » lines do not show, and draws nothing of it until [open]; [fold] folds it again, as the Garage does when it is covered by a page or the app is hidden.
class OrderHistoryCubit extends Cubit<OrderHistoryState> {
  final RobosatsNetwork network;

  final OrderHistoryLister _list;
  StreamSubscription<Result<List<FinishedOrder>, P2pFailure>>? _subscription;

  OrderHistoryCubit(this.network, this._list)
    : super(
        const OrderHistoryState._(
          OrderHistoryLoading(),
          open: false,
          shown: OrderHistory.page,
        ),
      );

  /// Starts reading: a new list after each write of the records or the trails, the lines shown kept as they are.
  void start() {
    if (isClosed || _subscription != null) return;
    // An `Error` the list passes on is a bug (rule 11): not caught here.
    _subscription = _list(network).listen((result) {
      if (isClosed) return;
      _emitRead(switch (result) {
        Ok(:final value) => OrderHistoryListed(value),
        Err() => const OrderHistoryUnreadable(),
      });
    });
  }

  void _emitRead(OrderHistoryRead read) =>
      emit(OrderHistoryState._(read, open: state.open, shown: state.shown));

  /// « See history »: the first [OrderHistory.page] lines.
  void open() {
    if (isClosed || state.open) return;
    emit(OrderHistoryState._(state.read, open: true, shown: OrderHistory.page));
  }

  /// « See more »: [OrderHistory.page] lines more, while some are left.
  void showMore() {
    if (isClosed || !state.hasMore) return;
    emit(
      OrderHistoryState._(
        state.read,
        open: true,
        shown: state.shown + OrderHistory.page,
      ),
    );
  }

  /// « Hide history », a page over the Garage, the app hidden: folded, its lines back to the first page.
  void fold() {
    if (isClosed || !state.open) return;
    emit(
      OrderHistoryState._(state.read, open: false, shown: OrderHistory.page),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
