import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_identity.dart';

/// The stars a robot gives its coordinator, 1 to 5 (`rate_platform`, the serializer's choices « 1 » to « 5 », `api/serializers.py:678-683`, commit ff1998c).
@immutable
final class PlatformRating {
  static const min = 1;
  static const max = 5;

  /// The stars, [min] to [max].
  final int stars;

  const PlatformRating._(this.stars);

  /// The rating of [stars], or `null` outside [min] to [max].
  static PlatformRating? of(int stars) =>
      stars >= min && stars <= max ? PlatformRating._(stars) : null;

  @override
  bool operator ==(Object other) =>
      other is PlatformRating && other.stars == stars;

  @override
  int get hashCode => stars.hashCode;

  @override
  String toString() => 'PlatformRating($stars)';
}

/// What a coordinator answered to an action of the trade that it accepted: « fiat sent », its undo, a dispute, a rating of the coordinator.
///
/// The reference coordinator answers each of them with the order as this robot then sees it (`api/views.py:651-695`, commit ff1998c), and every refusal with an error: a `200` is never an action that did not happen, so there is one outcome.
sealed class TradeActionOutcome {
  /// The order as the coordinator described it in its answer.
  CoordinatorOrder get order;

  const TradeActionOutcome();
}

/// The coordinator did the action: [order] is the order as it now is, still this robot's in the same role.
///
/// The answer is the read that follows the action; a later read tells if the order moved on meanwhile.
final class TradeActionAccepted extends TradeActionOutcome {
  @override
  final CoordinatorOrder order;

  const TradeActionAccepted._(this.order);

  @override
  String toString() => 'TradeActionAccepted($order)';
}

/// Reads the decoded body of a `200` answer to an action of the robot [identity], whose last read of the order was [lastRead]: the order, with this robot in the same role (maker or taker, buyer or seller).
@internal
Result<TradeActionOutcome, CoordinatorFailure> parseTradeActionAnswer(
  Object? body, {
  required RobotIdentity identity,
  required CoordinatorOrder lastRead,
}) {
  final CoordinatorOrder order;
  switch (CoordinatorOrder.parse(
    body,
    lastRead.coordinator,
    lastRead.network,
    orderId: lastRead.id,
    identity: identity,
  )) {
    case Err(:final failure):
      return Err(failure);
    case Ok(:final value):
      order = value;
  }
  if (order.isMaker != lastRead.isMaker || order.isTaker != lastRead.isTaker) {
    return const Err(CoordinatorResponseMalformed('is_taker'));
  }
  if (order.isBuyer != lastRead.isBuyer ||
      order.isSeller != lastRead.isSeller) {
    return const Err(CoordinatorResponseMalformed('is_buyer'));
  }
  return Ok(TradeActionAccepted._(order));
}
