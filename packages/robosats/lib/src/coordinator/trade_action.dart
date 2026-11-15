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

/// The statuses an order can be in once the reference coordinator did each action and read the order back (`api/views.py:695`), from `api/logics.py` at commit ff1998c: the status the action gives, then the moves of the backend from it that another side or a timer can make before the read.
///
/// After the buyer's « fiat sent » (10): a dispute, opened by either side or by the chat's timer (11, `:460-468`, `:485-533`), its statements and decision (16, 17, 18), the seller's confirmation (13, 14 for an on-chain payout, 15, `:1700-1730`); never 9 (only the buyer undoes), nor 12 (a cancel is refused at 10, `:1019-1032`).
@internal
const fiatSentFollows = {
  CoordinatorOrderStatus.fiatSent,
  CoordinatorOrderStatus.inDispute,
  CoordinatorOrderStatus.sendingSats,
  CoordinatorOrderStatus.successful,
  CoordinatorOrderStatus.routingFailed,
  CoordinatorOrderStatus.waitingForDisputeResolution,
  CoordinatorOrderStatus.makerLostDispute,
  CoordinatorOrderStatus.takerLostDispute,
};

/// After the undo of « fiat sent » (9, `:1737-1756`): a dispute and what follows it (11, 16, 17, 18); never 10 (only the buyer confirms), nor 13 to 15 (the seller confirms only after « fiat sent », 1027); a collaborative cancel (12) is error 1043 on the read, never a `200`.
@internal
const fiatSentUndoneFollows = {
  CoordinatorOrderStatus.sendingFiat,
  CoordinatorOrderStatus.inDispute,
  CoordinatorOrderStatus.waitingForDisputeResolution,
  CoordinatorOrderStatus.makerLostDispute,
  CoordinatorOrderStatus.takerLostDispute,
};

/// After a dispute (11, `:485-533`): its statements and decision (16, `:536-569`; 17, 18).
@internal
const disputeFollows = {
  CoordinatorOrderStatus.inDispute,
  CoordinatorOrderStatus.waitingForDisputeResolution,
  CoordinatorOrderStatus.makerLostDispute,
  CoordinatorOrderStatus.takerLostDispute,
};

/// Reads the decoded body of a `200` answer to an action of the robot [identity], whose last read of the order was [lastRead]: the order, with this robot in the same role (maker or taker, buyer or seller), at a status the action can lead to when [follows] says which ([fiatSentFollows], [fiatSentUndoneFollows], [disputeFollows]; a rating changes no status).
///
/// A status the action cannot lead to is malformed (`status`): only a coordinator that answers `200` without acting gives one, and the outcome is then unknown, never done.
@internal
Result<TradeActionOutcome, CoordinatorFailure> parseTradeActionAnswer(
  Object? body, {
  required RobotIdentity identity,
  required CoordinatorOrder lastRead,
  Set<CoordinatorOrderStatus>? follows,
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
  if (follows != null && !follows.contains(order.status)) {
    return const Err(CoordinatorResponseMalformed('status'));
  }
  return Ok(TradeActionAccepted._(order));
}
