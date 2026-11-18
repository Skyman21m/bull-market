import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../trade_record.dart';
import 'trade_edges.dart';

/// The renewal of an order made here (#185, design note `docs/design/phase-3-making-an-order.md` § 1.8, § 2.2): what « Renew Order » at 5 and « Renew » at 14 (and at 13 and 15 for a maker seller) make again.
///
/// The reference makes a new order with a new `POST /api/make/` from the fields of the order the coordinator gave the maker (`TradeBox/index.tsx:146-200`, commit ff1998c), on the same coordinator (`shortAlias: newOrder.shortAlias`, `:178`). Here the order is made from the terms this device kept when it made [orderId] (`maker_terms`, never what the coordinator reads back), on that same coordinator, by the make of a creation (`MakeOrderUsecase.execute`, a fresh robot, the same checks of the price and of the limits): a new order, with its own number, its own record and its own bond, the order renewed staying in the history as it was.
@immutable
final class OrderRenewal {
  /// The order renewed.
  final int orderId;
  final RobosatsNetwork network;

  /// The coordinator of the order renewed, as the federation list gives it now.
  final Coordinator coordinator;

  /// What the renewal sends: the order renewed's request, as the records keep it.
  final MakeOrderRequest request;

  const OrderRenewal({
    required this.orderId,
    required this.network,
    required this.coordinator,
    required this.request,
  });

  /// Whether the reference offers its maker a renewal at [position], for [role]: « Renew Order » once the order expired (`Prompts/Expired.tsx:40-97`, whatever its reason), « Renew » wherever it shows « Trade finished! » (`Prompts/Successful.tsx:276-285`, `order.is_maker`): at 14 for both sides, at 13 and 15 for the seller only, the buyer being shown the payment's progress there (`TradeBox/index.tsx:602-690`).
  static bool offeredAt(TradePosition position, {required TradeRole role}) =>
      switch (position) {
        TradePosition.expired || TradePosition.succeeded => true,
        TradePosition.sendingSats ||
        TradePosition.routingFailed => role == TradeRole.seller,
        _ => false,
      };

  @override
  bool operator ==(Object other) =>
      other is OrderRenewal &&
      other.orderId == orderId &&
      other.network == network &&
      other.coordinator == coordinator &&
      other.request == request;

  @override
  int get hashCode => Object.hash(orderId, network, coordinator, request);

  @override
  String toString() => 'OrderRenewal($orderId)';
}

/// Why an order cannot be renewed from this device: nothing is sent, and a screen words each type with a text of its own.
sealed class RenewalRefusal extends Failure {
  const RenewalRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The trade was not made here (taken here, or found by recovery): no terms of it were kept to make it again.
final class RenewalNotMadeHere extends RenewalRefusal {
  const RenewalNotMadeHere();
}

/// The trail this device stored of the order is not at a position where the reference offers its renewal ([OrderRenewal.offeredAt]), or none is stored.
final class RenewalNotEnded extends RenewalRefusal {
  const RenewalNotEnded();
}

/// The records of the order could not be read, or its terms do not restore as this code wrote them.
final class RenewalTermsUnreadable extends RenewalRefusal {
  const RenewalTermsUnreadable();
}

/// The order's coordinator is no longer in the federation list on its network, or no longer at the same address.
final class RenewalCoordinatorGone extends RenewalRefusal {
  const RenewalCoordinatorGone();
}
