import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/public_order.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The public orders of one coordinator, as `GET /api/book/` lists them.
@immutable
final class OrderBook {
  final Coordinator coordinator;

  /// The valid orders, in the order the coordinator listed them.
  final List<PublicOrder> orders;

  /// How many listed orders were left out: invalid, or sharing their id with another.
  final int droppedOrders;

  const OrderBook._(this.coordinator, this.orders, this.droppedOrders);

  /// The book of a coordinator with no public order: it answers `404` with `{"not_found": …}` (`api/views.py:797-801`).
  @internal
  factory OrderBook.empty(Coordinator coordinator) =>
      OrderBook._(coordinator, const [], 0);

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
    for (final element in body) {
      if (PublicOrder.parse(element, coordinator) case Ok(:final value)) {
        parsed.add(value);
      }
    }
    final occurrences = <int, int>{};
    for (final order in parsed) {
      occurrences.update(order.id, (count) => count + 1, ifAbsent: () => 1);
    }
    final orders = List<PublicOrder>.unmodifiable(
      parsed.where((order) => occurrences[order.id] == 1),
    );
    return Ok(OrderBook._(coordinator, orders, body.length - orders.length));
  }

  @override
  String toString() =>
      'OrderBook(${coordinator.shortAlias}, ${orders.length} orders, $droppedOrders dropped)';
}
