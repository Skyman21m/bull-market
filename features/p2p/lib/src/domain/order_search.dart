import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// What « Search order » finds for the text the user entered.
@immutable
sealed class OrderSearchOutcome {
  const OrderSearchOutcome();
}

/// The text is not an order URL: the field goes red, as in the official client.
final class OrderSearchInvalidUrl extends OrderSearchOutcome {
  const OrderSearchInvalidUrl();
}

/// The order is in the public book this screen received: its page opens.
final class OrderSearchFound extends OrderSearchOutcome {
  final PublicOrder order;

  const OrderSearchFound(this.order);
}

/// An order URL, but not of an order in the public book: only a robot can read it from its coordinator, as for a password-protected order.
final class OrderSearchNeedsRobot extends OrderSearchOutcome {
  const OrderSearchNeedsRobot();
}

/// « Search order », the « Search » entry of the book of the official client (`components/Dialogs/GoToOrder.tsx` at commit ff1998c).
///
/// The official client reads `http(s)://<host>/order/<coordinator>/<id>`, ignores the host, and opens the page of that order, which asks the coordinator for it with the robot of the user (`GET /api/order/`, authenticated).
/// Troc has no robot yet: it opens the order only when it is in the public book already received, and says a robot is needed otherwise.
/// Nothing is requested from any coordinator.
abstract final class OrderSearch {
  /// The pattern of the official client, unchanged.
  static final RegExp _orderUrl = RegExp(
    r'^(https?:\/\/[^\s/]+\/order\/([^/]+)\/([^/]+))\/?$',
  );

  /// What [text] finds in [book], every order received whatever the filter.
  static OrderSearchOutcome run(String text, Iterable<PublicOrder> book) {
    final match = _orderUrl.firstMatch(text);
    final coordinator = match?.group(2);
    final orderId = match?.group(3);
    if (coordinator == null || orderId == null) {
      return const OrderSearchInvalidUrl();
    }
    // Like `Number` in the official client, `int.tryParse` ignores the spaces around the number.
    final id = int.tryParse(orderId, radix: 10);
    for (final order in book) {
      if (order.id == id && order.coordinator.shortAlias == coordinator) {
        return OrderSearchFound(order);
      }
    }
    return const OrderSearchNeedsRobot();
  }
}
