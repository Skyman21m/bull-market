import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_cancel.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_reader.dart';

/// Cancels a trade as its taker, with the last read the user saw, then reads the order again and keeps what it shows (#87, design note § 1.4, § 2.1).
///
/// The guard `cancel_status` is the status the coordinator stores for that read, which the coordinator client sends with every cancel (`CoordinatorClient.cancelOrder`, #99): 1 for a pre-take shown as 3, so that a cancel arriving after the bond locked is refused (1020) instead of costing the bond.
/// At the pre-take (3) the cancel is free; once the bond is locked and the escrow is not (6, 7) it loses the bond, and is sent only with a [BondLossAcknowledged] given for this trade at the status seen; with the escrow locked (8, 9) only a collaborative cancel exists, a later slice; at any other status no cancel exists.
/// The cancel is sent once, through the robot's places in `RobotRequestLimiter`, and never again: an outcome unknown is said as such, and the watch of the trade resolves it.
final class CancelTradeUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;

  const CancelTradeUsecase(this._client, this._reader, this._limiter);

  /// Cancels the trade of [record] as [seen] showed it, [bondLoss] given when the user confirmed losing the bond.
  ///
  /// [Err]: nothing was sent ([CancelRefusal]). [Ok]: the cancel was sent, or may have left; [CancelOutcome] says what it and the read after it gave.
  Future<Result<CancelOutcome, CancelRefusal>> execute(
    TradeRecord record,
    TradeSeen seen, {
    BondLossAcknowledged? bondLoss,
  }) async {
    final lastRead = seen.order;
    if (lastRead == null) return const Err(CancelNeedsARead());
    switch (lastRead.status) {
      case CoordinatorOrderStatus.waitingForTakerBond:
        break;
      case CoordinatorOrderStatus.waitingForCollateralAndInvoice ||
          CoordinatorOrderStatus.waitingForCollateral:
        if (bondLoss == null) return const Err(CancelLosesTheBond());
        if (!bondLoss.covers(record, seen)) {
          return const Err(CancelAcknowledgementMismatch());
        }
      case CoordinatorOrderStatus.waitingForInvoice ||
          CoordinatorOrderStatus.sendingFiat:
        return const Err(CancelOnlyTogether());
      default:
        return const Err(CancelNotPossible());
    }
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable(:final reason):
        return Err(CancelTradeUnrestorable(reason));
      case TradeNotOpened(:final failure):
        return Err(CancelTradeUnavailable(failure));
      case TradeTakeNeverSent():
        return const Err(CancelOfAnotherTrade());
    }
    final terms = trade.terms;
    if (lastRead.id != terms.orderId ||
        lastRead.coordinator != terms.coordinator ||
        lastRead.network != terms.network) {
      return const Err(CancelOfAnotherTrade());
    }

    final requests = _limiter.open(trade.robot.identity.sessionKey);
    try {
      final sent = await requests.send(
        record.network,
        trade.coordinator,
        () => _client.cancelOrder(
          identity: trade.robot.identity,
          lastRead: lastRead,
        ),
        isBusy: _answeredBusy,
      );
      var current = trade;
      P2pFailure? problem;
      Future<void> keep(TradeAnswer answer) async {
        final step = await _reader.advance(current, answer, at: _reader.now());
        current = step.trade;
        problem ??= step.recordProblem;
      }

      // The cancel's own answer first, then a read after it.
      switch (sent) {
        case Ok(value: Ok(value: OrderCancelEnded())):
          await keep(const TradeOrderCancelled());
        case Ok(value: Ok(value: OrderCancelAccepted(:final order))):
          await keep(TradeOrderRead(order));
        case Ok(value: Err()) || Err():
          break;
      }
      final read = await _reader.readOrder(
        requests,
        record,
        trade.robot,
        trade.coordinator,
      );
      if (read case Ok(value: final result)) {
        if (TradeAnswer.ofRead(result) case final answer?) await keep(answer);
      }
      return Ok(switch (sent) {
        Ok(value: Ok()) => CancelDone(
          current.record,
          current.seen,
          recordProblem: problem,
        ),
        Ok(value: Err(failure: OrderActionRefused(:final cause))) =>
          CancelNotDone(
            current.record,
            current.seen,
            cause: cause,
            recordProblem: problem,
          ),
        Ok(value: Err(failure: OrderActionOutcomeUnknown())) =>
          CancelOutcomeUnknown(
            current.record,
            current.seen,
            recordProblem: problem,
          ),
        // Busy every time, or the robot released: the cancel never reached the coordinator.
        Err(:final failure) => CancelNotDone(
          current.record,
          current.seen,
          cause: failure,
          recordProblem: problem,
        ),
      });
    } finally {
      requests.close();
    }
  }

  /// Whether the transport answered the cancel busy: nothing reached the coordinator.
  static bool _answeredBusy(
    Result<CancelOrderOutcome, OrderActionFailure> answer,
  ) => switch (answer) {
    Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) => true,
    _ => false,
  };
}
