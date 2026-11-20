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

/// An order URL, but not of an order in the public book received: only a robot can read it from its coordinator, as for a password-protected order, unless the book of [coordinator] has not arrived yet.
final class OrderSearchNeedsRobot extends OrderSearchOutcome {
  /// The URL searched, to search it again once the book of [coordinator] arrives.
  final String url;

  /// The order number the URL names, `null` when it is none (#245).
  final int? orderId;

  /// The short alias the URL names.
  final String coordinator;

  const OrderSearchNeedsRobot(this.url, this.coordinator, {this.orderId});
}

/// What the screen says for an [OrderSearchNeedsRobot], once the book of its coordinator is settled.
@immutable
sealed class OrderSearchMiss {
  const OrderSearchMiss();
}

/// The book of the coordinator arrived meanwhile, and holds the order: its page opens.
final class OrderSearchMissFound extends OrderSearchMiss {
  final PublicOrder order;

  const OrderSearchMissFound(this.order);
}

/// The book of the coordinator could not be had: nothing tells whether the order is there.
final class OrderSearchMissOffline extends OrderSearchMiss {
  const OrderSearchMissOffline();
}

/// No Garage Key is stored for the network: the official client's « You do not have a Garage Key ».
final class OrderSearchMissNoGarageKey extends OrderSearchMiss {
  const OrderSearchMissNoGarageKey();
}

/// A Garage Key is stored, and the URL names a coordinator of the federation and an order number: the order may be a password-protected one, which no book lists, or a public one the book in memory does not hold yet; its page opens, and the robot that would take it reads it there (#245), as the official client's order page reads it with the user's robot.
final class OrderSearchMissUnlisted extends OrderSearchMiss {
  final Coordinator coordinator;
  final int orderId;

  const OrderSearchMissUnlisted(this.coordinator, this.orderId);
}

/// A Garage Key is stored, or cannot be read, and the URL names no coordinator of the federation or no order number, or no protected order can be read here: the official client's « This order is not available ».
final class OrderSearchMissNotAvailable extends OrderSearchMiss {
  const OrderSearchMissNotAvailable();
}

/// « Search order », the « Search » entry of the book of the official client (`components/Dialogs/GoToOrder.tsx` at commit ff1998c).
///
/// The official client reads `http(s)://<host>/order/<coordinator>/<id>`, ignores the host, and opens the page of that order, which asks the coordinator for it with the robot of the user (`GET /api/order/`, authenticated).
/// The order opens at once when it is in the public book received, after the book of its coordinator when it is still awaited; otherwise the screen says « Coordinator offline » when that book could not be had, « You do not have a Garage Key » when no Garage Key is stored, and with a Garage Key the order's page opens, its robot reading it there (#245: a password-protected order, which no book lists).
/// The search itself requests nothing from any coordinator.
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
    return OrderSearchNeedsRobot(text, coordinator, orderId: id);
  }
}
