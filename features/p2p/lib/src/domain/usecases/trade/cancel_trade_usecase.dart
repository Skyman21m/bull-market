import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_cancel.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_keyring.dart';
import 'trade_read_order.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Cancels a trade as its taker, or as the maker of an order made here (#179), with the last read the user saw, then reads the order again and keeps what it shows (#87, design note § 1.4, § 2.1; `docs/design/phase-3-making-an-order.md` § 1.7, § 3.2).
///
/// The guard `cancel_status` is the status the coordinator stores for that read, which the coordinator client sends with every cancel (`CoordinatorClient.cancelOrder`, #99): 1 for a pre-take shown as 3, so that a cancel arriving after the bond locked is refused (1020) instead of costing the bond.
/// A maker's cancel is free at 0, 1 and 2 (its order before any take), and the bond is returned at 1 and 2 ([CancelDone.makerBondReturned]); from 6 on a maker's cancel is a taker's, the bond lost at 6 and 7.
/// An answer that says the order ended closes the record, even if a coordinator that lies shows the order alive at the read that follows (it holds the bond anyway; a taker's cancel behaves the same). An order answered as it was, alive, gives [CancelDone] with the live status: a screen judges by [CancelOutcome.seen]'s status, never by the type of the outcome, and never says « bond returned » on [CancelDone.makerBondReturned] alone (security review of #179).
/// At the pre-take (3) the cancel is free; once the bond is locked and the escrow is not (6, 7) it loses the bond, and is sent only with a [BondLossAcknowledged] given for this trade at the status seen; in the chat (9) it is the collaborative cancel, free, which the reference offers there only (#95): an ask, or the acceptance of the peer's; at 8 the reference offers none; at any other status no cancel exists.
/// The cancel is sent once, through the robot's places in `RobotRequestLimiter`, and never again: an outcome unknown is said as such, and the watch of the trade resolves it.
/// It is signed by the robot's key, leased from [TradeKeyring] for the request ([TradeKeyring.signWith], GHSA-22q8-9ghc-jg3h); a key that cannot be had sends nothing, and is told as a cancel not done.
final class CancelTradeUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeTakeLocks _locks;
  final TradeKeyring _keyring;

  const CancelTradeUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._locks,
    this._keyring,
  );

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
    // A trade made here is cancelled as its maker (#179, design note `docs/design/phase-3-making-an-order.md` § 1.7): free before any take, at 0, 1 and 2.
    final made = record.origin == TradeOrigin.madeHere;
    switch (lastRead.status) {
      // The pre-take, a taker's only: a maker never sees 3 (the coordinator shows it only to a robot that holds a live pre-take, `api/views.py:381-396`, which a maker cannot, `api/logics.py:75-100`), so a read of an order made here at 3 is no cancel (functional review of #179).
      case CoordinatorOrderStatus.waitingForTakerBond:
        if (made) return const Err(CancelNotPossible());
      // The maker's own order before any take (`Logics.cancel_order`, `api/logics.py:1037-1060`): at 0 the bond invoice cancelled, at 1 or 2 the maker bond returned and every pre-take expired; the guard sent is the status shown, which a maker always sees as stored, so that a cancel that lands after the bond locked (0 → 1) or after a take (1 → 6) is refused (1020) instead of costing the bond.
      case CoordinatorOrderStatus.waitingForMakerBond ||
          CoordinatorOrderStatus.public ||
          CoordinatorOrderStatus.paused:
        // Both halves, each for a coordinator that lies: a taker's record whose read says this robot is the maker, and an order made here whose read says it is not.
        if (!made || !lastRead.isMaker) return const Err(CancelNotPossible());
      case CoordinatorOrderStatus.waitingForCollateralAndInvoice ||
          CoordinatorOrderStatus.waitingForCollateral:
        if (bondLoss == null) return const Err(CancelLosesTheBond());
        if (!bondLoss.covers(record, seen)) {
          return const Err(CancelAcknowledgementMismatch());
        }
      // The collaborative cancel (#95), as the reference offers it, from the chat only (`Prompts/Chat.tsx`, « Collaborative Cancel »): the first ask raises this robot's flag, the second side's ask cancels the order for both (12), everything returned (`api/logics.py:1130-1202`). The guard, 9, makes an ask that lands after « fiat sent » a refusal (1020), never a cancel.
      case CoordinatorOrderStatus.sendingFiat:
        // As the screen offers it: a status marked stored, at 9 before « fiat sent ».
        if (!seen.stored) return const Err(CancelNeedsARead());
        if (seen.status case Chatting(fiatSent: false)) break;
        return const Err(CancelNotPossible());
      // At 8 the coordinator would take it too, but the reference offers no cancel there (`CancelButton.tsx:27-29`, `Prompts/PayoutWait.tsx`).
      case CoordinatorOrderStatus.waitingForInvoice:
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

    // One action of an order at a time in the process: its take, its payout, the payment of its bond and this cancel (`TradeTakeLocks`): a cancel waits for a payment of the bond being sent.
    return _locks.run(
      record.network,
      trade.coordinator,
      record.orderId,
      // An action of the trade: the watch sends no read while it runs (#141).
      () => _reader.duringAction(record, () async {
        final requests = _limiter.open(trade.robot.identity.sessionKey);
        try {
          final cancelTimes = _reader.request();
          final sent = await TradeKeyring.signWith(
            _keyring.lease(trade),
            (key) => requests.send(
              record.network,
              trade.coordinator,
              () => _reader.timed(
                cancelTimes,
                () => _client.cancelOrder(
                  identity: trade.robot.identity,
                  key: key,
                  lastRead: lastRead,
                ),
              ),
              isBusy: _answeredBusy,
            ),
          );
          var current = trade;
          P2pFailure? problem;
          Future<void> keep(TradeAnswer answer, RequestTimes request) async {
            final step = await _reader.advance(
              current,
              answer,
              at: _reader.now(),
              request: request,
            );
            current = step.trade;
            problem ??= step.recordProblem;
          }

          // The cancel's own answer first, then a read after it. An answer that ends the order is no read of it: the short body of `api/views.py:604-615` (`OrderCancelEnded`) is the order's end, as error 1043 says it; for a maker, an order answered whole at 4 or 12 is taken the same way, not as a read of a status a maker is never shown (`TradeStatusRegressed`, a breach: functional review of #178).
          var ended = false;
          switch (sent) {
            case Ok(value: Ok(value: OrderCancelEnded())):
              ended = true;
              await keep(const TradeOrderCancelled(), cancelTimes);
            case Ok(value: Ok(value: OrderCancelAccepted(:final order)))
                when made &&
                    (order.status == CoordinatorOrderStatus.cancelled ||
                        order.status ==
                            CoordinatorOrderStatus.collaborativelyCancelled):
              ended = true;
              await keep(const TradeOrderCancelled(), cancelTimes);
            case Ok(value: Ok(value: OrderCancelAccepted(:final order))):
              await keep(TradeOrderRead(order), cancelTimes);
            case Ok(value: Err()) || Err():
              break;
          }
          // The coordinator ended a maker's public or paused order on this very cancel, guarded by the status shown: it returned the maker bond first (`close_public_order`, `api/logics.py:961-1003`, called at `:1048-1060`), which `Cancelled.bondMayHaveBeenLost` cannot know.
          final bondReturned =
              made &&
              ended &&
              (lastRead.status == CoordinatorOrderStatus.public ||
                  lastRead.status == CoordinatorOrderStatus.paused);
          final readAfter = _reader.request();
          final read = await _reader.readOrder(
            requests,
            record,
            trade.robot,
            trade.coordinator,
            times: readAfter,
          );
          if (read case Ok(value: final result)) {
            if (TradeAnswer.ofRead(result) case final answer?) {
              await keep(answer, readAfter);
            }
          }
          return Ok(switch (sent) {
            Ok(value: Ok()) => CancelDone(
              current.record,
              current.seen,
              recordProblem: problem,
              makerBondReturned: bondReturned,
            ),
            Ok(value: Err(failure: OrderActionRefused(:final cause))) =>
              CancelNotDone(
                current.record,
                current.seen,
                cause: cause,
                recordProblem: problem,
              ),
            // In the chat, a collaborative ask whose answer was lost and whose read after shows it recorded (this robot's flag) or the order cancelled for both: done, so that no notice contradicts the status shown.
            Ok(value: Err(failure: OrderActionOutcomeUnknown()))
                when lastRead.status == CoordinatorOrderStatus.sendingFiat &&
                    switch (current.seen.status) {
                      Chatting(:final askedToCancel) => askedToCancel,
                      Cancelled() => true,
                      _ => false,
                    } =>
              CancelDone(current.record, current.seen, recordProblem: problem),
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
      }),
    );
  }

  /// Whether the transport answered the cancel busy: nothing reached the coordinator.
  static bool _answeredBusy(
    Result<CancelOrderOutcome, OrderActionFailure> answer,
  ) => switch (answer) {
    Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) => true,
    _ => false,
  };
}
