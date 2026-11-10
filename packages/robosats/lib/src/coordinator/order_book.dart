import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/dropped_order_reason.dart';
import 'package:robosats/src/coordinator/public_order.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The public orders of one coordinator, as `GET /api/book/` lists them.
@immutable
final class OrderBook {
  final Coordinator coordinator;

  /// The valid orders, in the order the coordinator listed them.
  final List<PublicOrder> orders;

  /// Why each left-out element was dropped, in the order of the book.
  final List<DroppedOrderReason> dropped;

  const OrderBook._(this.coordinator, this.orders, this.dropped);

  /// The book of a coordinator with no public order: it answers `404` with `{"not_found": …}` (`api/views.py:797-801`).
  @internal
  factory OrderBook.empty(Coordinator coordinator) =>
      OrderBook._(coordinator, const [], const []);

  /// How many listed orders were left out.
  int get droppedOrders => dropped.length;

  /// Reads the decoded body of a `200` answer: a JSON array of orders.
  ///
  /// A body that is not an array rejects the response, and so does one with more than `CoordinatorReadBounds.maxOrders` elements.
  /// An invalid order is dropped alone, so a coordinator cannot blank its book, let alone the others, with one bad order; orders that share an id are all dropped, since none of them can be told apart.
  @internal
  static Result<OrderBook, CoordinatorFailure> parse(
    Object? body,
    Coordinator coordinator,
  ) {
    if (body is! List<Object?>) {
      return const Err(CoordinatorResponseMalformed('book'));
    }
    if (body.length > CoordinatorReadBounds.maxOrders) {
      return const Err(CoordinatorTooManyOrders());
    }
    final parsed = <PublicOrder>[];
    final dropped = <DroppedOrderReason>[];
    for (final element in body) {
      switch (PublicOrder.parse(element, coordinator)) {
        case (order: final PublicOrder order, dropped: _):
          parsed.add(order);
        case (order: _, dropped: final reason?):
          dropped.add(reason);
        case (order: null, dropped: null):
          throw StateError(
            'PublicOrder.parse returned neither an order nor a reason',
          );
      }
    }
    final occurrences = <int, int>{};
    for (final order in parsed) {
      occurrences.update(order.id, (count) => count + 1, ifAbsent: () => 1);
    }
    final orders = <PublicOrder>[];
    for (final order in parsed) {
      if (occurrences[order.id] == 1) {
        orders.add(order);
      } else {
        dropped.add(DroppedOrderReason.duplicateId);
      }
    }
    return Ok(
      OrderBook._(
        coordinator,
        List.unmodifiable(orders),
        List.unmodifiable(dropped),
      ),
    );
  }

  @override
  String toString() =>
      'OrderBook(${coordinator.shortAlias}, ${orders.length} orders, $droppedOrders dropped)';
}
