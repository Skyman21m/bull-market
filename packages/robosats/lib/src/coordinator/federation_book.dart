import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_client.dart';
import 'package:robosats/src/coordinator/coordinator_transport.dart';
import 'package:robosats/src/coordinator/federation.dart';
import 'package:robosats/src/coordinator/order_book.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/public_order.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// What the book request to one coordinator gave: its book, or why there is none.
@immutable
final class CoordinatorBookOutcome {
  final Coordinator coordinator;
  final Result<OrderBook, CoordinatorFailure> result;

  const CoordinatorBookOutcome(this.coordinator, this.result);

  @override
  String toString() =>
      'CoordinatorBookOutcome(${coordinator.shortAlias}, ${switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => failure,
      }})';
}

/// The books of several coordinators, merged: a coordinator that fails or misbehaves only loses its own orders.
@immutable
final class FederationBook {
  /// One outcome per coordinator, in the order they were given.
  final List<CoordinatorBookOutcome> outcomes;

  /// Every valid order, each tagged with its coordinator: by coordinator in the order of [outcomes], then by order id.
  final List<PublicOrder> orders;

  const FederationBook._(this.outcomes, this.orders);

  /// Merges outcomes collected by the caller, for instance as each future of [FederationBookReader.requestAll] completes.
  factory FederationBook.merge(Iterable<CoordinatorBookOutcome> outcomes) {
    final list = List<CoordinatorBookOutcome>.unmodifiable(outcomes);
    return FederationBook._(
      list,
      List.unmodifiable([
        for (final outcome in list)
          if (outcome.result case Ok(:final value))
            ...(List.of(value.orders)..sort((a, b) => a.id.compareTo(b.id))),
      ]),
    );
  }

  /// The coordinators whose book could not be read, with the reason.
  Map<Coordinator, CoordinatorFailure> get failures => {
    for (final outcome in outcomes)
      if (outcome.result case Err(:final failure)) outcome.coordinator: failure,
  };

  @override
  String toString() =>
      'FederationBook(${orders.length} orders, ${failures.length} failed coordinators)';
}

/// Reads the books of all the coordinators of a federation, each independently of the others.
///
/// It starts every request at once and leaves concurrency limits, deadlines and retries to the [CoordinatorTransport] adapter.
final class FederationBookReader {
  final CoordinatorClient _client;

  /// [clock] is passed to the [CoordinatorClient] of each request.
  FederationBookReader(
    CoordinatorTransport transport, {
    DateTime Function()? clock,
  }) : _client = CoordinatorClient(transport, clock: clock);

  /// Starts one book request per coordinator of [federation], in its order, and returns them without waiting.
  ///
  /// A coordinator without an onion address on [network] completes at once with [CoordinatorNotOnNetwork].
  /// Failures are values, so a future completes with an error only on a programming error, and the caller can show each book as it arrives.
  List<Future<CoordinatorBookOutcome>> requestAll(
    Federation federation,
    RobosatsNetwork network, {
    RobosatsCurrency? currency,
    OrderType? type,
  }) => [
    for (final coordinator in federation.coordinators)
      _client
          .fetchBook(coordinator, network, currency: currency, type: type)
          .then((result) => CoordinatorBookOutcome(coordinator, result)),
  ];

  /// Waits for every request of [requestAll] and merges them.
  Future<FederationBook> read(
    Federation federation,
    RobosatsNetwork network, {
    RobosatsCurrency? currency,
    OrderType? type,
  }) async => FederationBook.merge(
    await Future.wait(
      requestAll(federation, network, currency: currency, type: type),
    ),
  );
}
