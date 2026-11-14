import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_status.dart';
import 'trade_terms.dart';

/// The amount chosen in the range of an order, in the order's currency (bitcoin, not sats, for an order in bitcoin), as the take sends it.
///
/// The reference client sends the number typed (`Number(takeAmount)`, `frontend/src/models/Order.model.ts:241`, divided by 10⁸ for an order in sats) and the coordinator keeps 8 decimals, refusing more (`DecimalField(decimal_places=8)`, `api/serializers.py:684`): the amount is rounded to 8 decimals here, and the take checks it against the range of the order read just before it (`min_amount ≤ amount ≤ max_amount`, `api/logics.py:190-194`).
@immutable
final class TakeAmount {
  /// The decimals the coordinator keeps.
  static const int decimals = 8;

  /// The largest amount taken, far above any order's (`max_order_size` is in sats; a fiat amount of 10¹² is no order).
  static const double maxValue = 1e12;

  final FiatAmount amount;

  const TakeAmount._(this.amount);

  /// [value] rounded to [decimals] decimals, or `null` when it is not finite, not above zero, or above [maxValue].
  static TakeAmount? tryCreate(double value) {
    if (!value.isFinite || value <= 0 || value > maxValue) return null;
    final rounded = (value * 1e8).roundToDouble() / 1e8;
    return switch (FiatAmount.tryCreate(rounded)) {
      final amount? => TakeAmount._(amount),
      null => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TakeAmount && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'TakeAmount(${amount.value})';
}

/// The password the user typed for a protected order: the take sends its SHA-256 (the coordinator client hashes it), never the text.
///
/// Bounded as the coordinator bounds it (`max_length=2000`, `api/serializers.py:631-636`); never printed.
@immutable
final class OrderPassword {
  static const int maxLength = 2000;

  final String text;

  const OrderPassword._(this.text);

  /// [text] as typed, or `null` when it is empty or longer than [maxLength].
  static OrderPassword? tryCreate(String text) =>
      text.isEmpty || text.length > maxLength ? null : OrderPassword._(text);

  @override
  bool operator ==(Object other) =>
      other is OrderPassword && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'OrderPassword(<redacted>)';
}

/// Why a take was not sent: nothing left with a robot, and no trade was started.
///
/// A type for each reason, which the screen words (#88); none carries a coordinator's text.
sealed class TakeRefusal extends Failure {
  const TakeRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The coordinator could not be read just before the take (its book or its `/api/info/`): nothing was sent with a robot.
final class TakeCoordinatorUnreadable extends TakeRefusal {
  final CoordinatorFailure cause;

  const TakeCoordinatorUnreadable(this.cause);

  @override
  String toString() => 'TakeCoordinatorUnreadable(${cause.runtimeType})';
}

/// The order is no longer in the coordinator's book read just before the take: taken, paused, cancelled or expired.
final class TakeOrderGone extends TakeRefusal {
  const TakeOrderGone();
}

/// The order read just before the take is not the one the user accepted: another type, currency, amount or range, premium, bond size, escrow duration, or sats of an order priced in sats (the price may move, nothing else).
final class TakeOrderChanged extends TakeRefusal {
  const TakeOrderChanged();
}

/// The order is a buy order: taking it would make this robot the seller, a later slice (#96): « Selling is coming in a later version. »
final class TakeOfBuyOrderRefused extends TakeRefusal {
  const TakeOfBuyOrderRefused();
}

/// An amount was given for a fixed order, none for a range, or one outside the range of the order read just before the take.
final class TakeAmountRefused extends TakeRefusal {
  const TakeAmountRefused();
}

/// The terms of the take cannot be checked, so the take is not made: [reason] is [TakerFeeTooHigh] or [TradeTermsUnusable].
final class TakeTermsRefused extends TakeRefusal {
  final TradeTermsRefusal reason;

  const TakeTermsRefused(this.reason);

  @override
  String toString() => 'TakeTermsRefused(${reason.runtimeType})';
}

/// No robot could be reserved for the trade, or one reserved could not be put on the coordinator or recorded with its take: [failure] says why.
///
/// A robot reserved stays bound to that coordinator, without a trade, and is never used again; its first contact may have reached the coordinator, never a take.
final class TakeRobotRefused extends TakeRefusal {
  final P2pFailure failure;

  const TakeRobotRefused(this.failure);

  @override
  String toString() => 'TakeRobotRefused(${failure.runtimeType})';
}

/// The coordinator refused the robot's first contact, or could not be reached for it: [cause] says why; no take was sent.
final class TakeRobotNotPut extends TakeRefusal {
  final CoordinatorFailure cause;

  const TakeRobotNotPut(this.cause);

  @override
  String toString() => 'TakeRobotNotPut(${cause.runtimeType})';
}

/// The pending take, its terms or its first trail could not be written: the take was not sent (`TradeRecordRepository.recordPendingTake`, #87).
final class TakeNotRecorded extends TakeRefusal {
  final P2pFailure failure;

  const TakeNotRecorded(this.failure);

  @override
  String toString() => 'TakeNotRecorded(${failure.runtimeType})';
}

/// What a take sent to the coordinator gave.
@immutable
sealed class TakeOutcome {
  /// The trade's record as stored once the take's writes are over (pending, taken or closed).
  TradeRecord get record;

  const TakeOutcome();
}

/// The take started a trade: [status] is the pre-take with its bond (`TradeStatus.afterTake`).
///
/// [recordProblem] is set when the trail or the confirmation could not be written: the trade runs on the coordinator all the same, and the next read of the trade writes them; the screen shows the status and that the records could not be written.
final class TakeStarted extends TakeOutcome {
  @override
  final TradeRecord record;
  final TradeStatus status;
  final P2pFailure? recordProblem;

  const TakeStarted(this.record, this.status, {this.recordProblem});

  @override
  String toString() => 'TakeStarted($record, $status)';
}

/// The order was already this robot's: the trade goes on at [status], resumed from its recorded trail.
final class TakeResumed extends TakeOutcome {
  @override
  final TradeRecord record;
  final TradeStatus status;
  final P2pFailure? recordProblem;

  const TakeResumed(this.record, this.status, {this.recordProblem});

  @override
  String toString() => 'TakeResumed($record, $status)';
}

/// The take certainly did not happen: the coordinator answered with the order as it is, this robot not its taker ([OrderNotTaken]), or refused the take before acting ([refusal]: a penalty, a wrong password, an amount out of range, another active order, a busy transport…).
///
/// The pending take is closed ([TakeOutcome.record] closed), or stays pending when the close could not be written ([closeProblem]), for the next read to close.
final class TakeNotMade extends TakeOutcome {
  @override
  final TradeRecord record;

  /// Why the coordinator refused, or `null` when it answered with the order as it is.
  final Failure? refusal;
  final P2pFailure? closeProblem;

  const TakeNotMade(this.record, {required this.refusal, this.closeProblem});

  @override
  String toString() => 'TakeNotMade($record, ${refusal?.runtimeType})';
}

/// The take was sent and what it did is unknown (a timeout, a broken answer…): the pending take stays, and the next read of the trade tells whether this robot holds the pre-take (`WatchTradeUsecase`).
final class TakeOutcomeUnknown extends TakeOutcome {
  @override
  final TradeRecord record;

  const TakeOutcomeUnknown(this.record);

  @override
  String toString() => 'TakeOutcomeUnknown($record)';
}
