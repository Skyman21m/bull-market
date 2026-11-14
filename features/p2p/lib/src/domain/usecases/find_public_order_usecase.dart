import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// Finds an order in its coordinator's public book, as the book lists it: an anonymous read, with no robot (#88).
///
/// The trade screen needs it when the order of a trade it shows is public again: the official client shows « Take Order » to a robot that is no participant (`components/OrderDetails/index.tsx:568-578`), and a take starts from the order of the book (`TakeOrderUsecase`, which reads the book again itself just before the take).
final class FindPublicOrderUsecase {
  final CoordinatorClient _client;

  const FindPublicOrderUsecase(this._client);

  /// The order [orderId] of [coordinator]'s book on [network], read for its [currency] and [type] as the take reads it; `Ok(null)` when the book no longer lists it.
  Future<Result<PublicOrder?, CoordinatorFailure>> execute(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required int orderId,
    required RobosatsCurrency currency,
    required OrderType type,
  }) async => switch (await _client.fetchBook(
    coordinator,
    network,
    currency: currency,
    type: type,
  )) {
    Ok(:final value) => Ok(
      value.orders.where((order) => order.id == orderId).firstOrNull,
    ),
    Err(:final failure) => Err(failure),
  };
}
