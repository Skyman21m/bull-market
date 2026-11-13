import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// What a read of the trade's order told, as the state machine takes it: the order as the coordinator describes it to this robot, or one of the two refusals that say where the order went (design note § 2.1).
///
/// Any other failure of a read (no answer, a malformed one, an unknown robot…) says nothing about the trade: the caller keeps the last status and reads again.
sealed class TradeAnswer {
  const TradeAnswer();

  /// The answer a read gave, or `null` when it says nothing about the trade.
  ///
  /// The same holds for the order a take or a cancel answered with: pass it as [TradeOrderRead].
  static TradeAnswer? ofRead(
    Result<CoordinatorOrder, CoordinatorFailure> read,
  ) => switch (read) {
    Ok(:final value) => TradeOrderRead(value),
    Err(failure: OrderCancelled()) => const TradeOrderCancelled(),
    Err(failure: OrderNotAvailable()) => const TradeOrderNotAvailable(),
    Err() => null,
  };
}

/// The order as its coordinator describes it to this robot, already checked by `package:robosats` against the robot that asked (`CoordinatorOrder`).
final class TradeOrderRead extends TradeAnswer {
  final CoordinatorOrder order;

  const TradeOrderRead(this.order);

  @override
  String toString() => 'TradeOrderRead($order)';
}

/// Error 1043: the order is cancelled, by one side or by both (`api/views.py:258-260`).
final class TradeOrderCancelled extends TradeAnswer {
  const TradeOrderCancelled();

  @override
  String toString() => 'TradeOrderCancelled';
}

/// Error 1044: this robot is neither the maker nor the taker of an order that is not public (`api/views.py:269-275`), as after another robot locked its bond first.
final class TradeOrderNotAvailable extends TradeAnswer {
  const TradeOrderNotAvailable();

  @override
  String toString() => 'TradeOrderNotAvailable';
}
