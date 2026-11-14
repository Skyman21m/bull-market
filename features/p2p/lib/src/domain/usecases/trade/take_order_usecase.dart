import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../repositories/trade_record_repository.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bolt11.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_take.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_tolerances.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import '../../trade_robots.dart';
import '../put_robot_on_coordinator_usecase.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Takes an order of the book as its taker, for a fresh robot of this device: the only place a trade starts (#87, design note § 2.1, `AGENTS.md` « Rules for the trade use cases (#87) » and « The rule for #87 »).
///
/// One take of an order at a time in the process ([TradeTakeLocks]), and none of an order that already has an open trade here: [TakeOrderAlreadyTraded], with its record (the database refuses a second open trade of an order too, the trigger `trades_one_open_per_order`).
/// In this order, each step only once the one before it succeeded:
/// 1. the order is read again just before the take, from the coordinator's book (`GET /api/book/` of its currency and type) with its `/api/info/` (the taker fee), both anonymous: never from a book left open; the terms are built from that read ([TradeTerms.take]), and a take that cannot be checked (a taker fee above the ceiling, an order gone or changed, its sats moved by more than [TradeTolerances.price] from what the user saw, an amount outside the range, a buy order) stops here, nothing sent with a robot;
/// 2. a fresh robot is reserved for the trade, bound to the order's coordinator ([TradeRobots.robotForNewTrade]), then put on it ([PutRobotOnCoordinatorUsecase]: read back, then its first contact); a robot that already existed there, or held an order, is not used;
/// 3. the pending take, its terms and the first trail of a pending take are written, in that order ([TradeRecordRepository.recordPendingTake], [TradeTrailRepository.recordTerms], [TradeTrailRepository.storeTrail]): the take is refused when any of them fails;
/// 4. the take is sent once, through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again;
/// 5. its answer: [OrderTakeStarted] starts the trade from [TradeStatus.afterTake], its trail stored and its record confirmed (when that trail cannot be stored, the status returned is the stored pending trail's, which holds no invoice: an invoice is shown or paid only from a status whose trail is stored); [OrderAlreadyTakenByThisRobot] resumes it from its recorded trail; [OrderNotTaken], or a refusal that comes before the action, closes the pending take; an outcome unknown leaves it pending, for the next read of the trade to resolve (`WatchTradeUsecase`).
///
/// Nothing here pays: the bond is paid by the user, from the trade screen.
final class TakeOrderUsecase {
  final CoordinatorClient _client;
  final TradeRobots _robots;
  final PutRobotOnCoordinatorUsecase _put;
  final TradeRecordRepository _records;
  final TradeTrailRepository _trails;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final Bolt11Reader _invoices;
  final TradeTakeLocks _locks;

  const TakeOrderUsecase(
    this._client,
    this._robots,
    this._put,
    this._records,
    this._trails,
    this._reader,
    this._limiter,
    this._invoices,
    this._locks,
  );

  /// Takes [shown], the order of the book the user accepted, on [network], for [amount] when it has a range, with [password] when it is protected.
  ///
  /// [Err]: the take was not sent, and no trade started ([TakeRefusal]); a robot reserved by then stays bound to the coordinator, without a trade, and is never used again.
  /// [Ok]: the take was sent, or the request may have left; [TakeOutcome] says what it gave.
  Future<Result<TakeOutcome, TakeRefusal>> execute(
    PublicOrder shown, {
    required RobosatsNetwork network,
    TakeAmount? amount,
    OrderPassword? password,
  }) async {
    if (shown.type == OrderType.buy) return const Err(TakeOfBuyOrderRefused());
    return _locks.run(
      network,
      shown.coordinator,
      shown.id,
      () => _take(shown, network: network, amount: amount, password: password),
    );
  }

  Future<Result<TakeOutcome, TakeRefusal>> _take(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
    required OrderPassword? password,
  }) async {
    final coordinator = shown.coordinator;
    // 0. No second trade of an order that has one open here.
    switch (await _openTradeOf(network, coordinator, shown.id)) {
      case Err(:final failure):
        return Err(TakeNotRecorded(failure));
      case Ok(value: final open?):
        return Err(TakeOrderAlreadyTraded(open));
      case Ok(value: null):
        break;
    }

    // 1. A fresh read of the order and of the taker fee, with no robot.
    final (book, info) = await (
      _client.fetchBook(
        coordinator,
        network,
        currency: shown.currency,
        type: shown.type,
      ),
      _client.fetchInfo(coordinator, network),
    ).wait;
    final double takerFee;
    switch (info) {
      case Ok(:final value):
        takerFee = value.takerFee;
      case Err(:final failure):
        return Err(TakeCoordinatorUnreadable(failure));
    }
    final PublicOrder fresh;
    switch (book) {
      case Ok(:final value):
        final found = value.orders.where((order) => order.id == shown.id);
        if (found.isEmpty) return const Err(TakeOrderGone());
        fresh = found.first;
      case Err(:final failure):
        return Err(TakeCoordinatorUnreadable(failure));
    }
    if (fresh.type == OrderType.buy) return const Err(TakeOfBuyOrderRefused());
    if (!_sameTerms(shown, fresh)) return const Err(TakeOrderChanged());
    final chosen = amount?.amount;
    switch ((fresh.amount, chosen)) {
      case (FixedOrderAmount(), null):
        break;
      case (RangeOrderAmount(:final min, :final max), final value?)
          when value.value >= min.value && value.value <= max.value:
        break;
      default:
        return const Err(TakeAmountRefused());
    }
    final TradeTerms terms;
    switch (TradeTerms.take(
      fresh,
      network: network,
      rangeAmount: chosen,
      takerFee: takerFee,
    )) {
      case Ok(:final value):
        terms = value;
      case Err(:final failure):
        return Err(TakeTermsRefused(failure));
    }
    if (terms.role != TradeRole.buyer) {
      return const Err(TakeOfBuyOrderRefused());
    }

    // 2. A fresh robot, bound to the coordinator, then put on it.
    final ReservedRobot reserved;
    switch (await _robots.robotForNewTrade(network, coordinator)) {
      case Ok(:final value):
        reserved = value;
      case Err(:final failure):
        return Err(TakeRobotRefused(failure));
    }
    final robot = reserved.robot;
    switch (await _put.execute(robot, coordinator)) {
      case Err(:final failure):
        return Err(TakeRobotRefused(failure));
      case Ok(value: Err(:final failure)):
        return Err(TakeRobotNotPut(failure));
      case Ok(value: Ok(value: final face)):
        // A robot of this index that was already there, with another pair, or that held an order, may have travelled: its token is not this trade's alone.
        if (face.alreadyExisted ||
            face.activeOrderId != null ||
            face.lastOrderId != null) {
          return const Err(TakeRobotRefused(RobotNotForNewTradeFailure()));
        }
    }

    // 3. The pending take, its terms and its first trail, before the take leaves.
    final TradeRecord pending;
    switch (await _records.recordPendingTake(
      reserved.reservation,
      orderId: terms.orderId,
      role: terms.role,
    )) {
      case Ok(:final value):
        pending = value;
      case Err(:final failure):
        // Another take of the order, from another connection, may have recorded its trade first.
        if (await _openTradeOf(network, coordinator, terms.orderId) case Ok(
          value: final open?,
        )) {
          return Err(TakeOrderAlreadyTraded(open));
        }
        return Err(TakeNotRecorded(failure));
    }
    if (await _trails.recordTerms(pending, terms.record) case Err(
      :final failure,
    )) {
      return Err(TakeNotRecorded(await _closedUnsent(pending, failure)));
    }
    switch (await _trails.storeTrail(
      pending,
      TradeTrail.forPendingTake(terms, pending.takenAt).record,
    )) {
      case Ok(value: TrailStored()):
        break;
      case Ok(value: TrailKept()):
        return Err(
          TakeNotRecorded(
            await _closedUnsent(pending, const P2pStorageFailure()),
          ),
        );
      case Err(:final failure):
        return Err(TakeNotRecorded(await _closedUnsent(pending, failure)));
    }

    // 4. The take, once.
    final requests = _limiter.open(robot.identity.sessionKey);
    final Result<Result<TakeOrderOutcome, OrderActionFailure>, P2pFailure>
    taken;
    try {
      taken = await requests.send(
        network,
        coordinator,
        () => _client.takeOrder(
          coordinator,
          network,
          identity: robot.identity,
          orderId: terms.orderId,
          amount: chosen,
          password: password?.text,
        ),
        isBusy: _answeredBusy,
      );
    } finally {
      requests.close();
    }

    // 5. What it gave.
    switch (taken) {
      case Err(:final failure):
        // Busy every time, or the robot released: the take never reached the coordinator.
        return Ok(await _notMade(pending, refusal: failure));
      case Ok(value: Err(failure: OrderActionRefused(:final cause))):
        return Ok(await _notMade(pending, refusal: cause));
      case Ok(value: Err(failure: OrderActionOutcomeUnknown())):
        return Ok(TakeOutcomeUnknown(pending));
      case Ok(value: Ok(value: OrderNotTaken())):
        return Ok(await _notMade(pending, refusal: null));
      case Ok(value: Ok(value: final OrderTakeStarted started)):
        final status = TradeStatus.afterTake(
          started,
          terms: terms,
          now: _reader.now(),
          reader: _invoices,
        );
        // From the pending trail stored before the take: what stays if the take's own trail cannot be stored.
        final step = await _reader.keep(
          OpenTrade(
            record: pending,
            robot: robot,
            coordinator: coordinator,
            terms: terms,
            seen: TradeSeen(
              TradeStatus.beforeFirstRead(
                TradeTrail.forPendingTake(terms, pending.takenAt),
              ),
              order: null,
            ),
          ),
          TradeSeen(status, order: started.order),
          showsTaker: true,
        );
        return Ok(
          TakeStarted(
            step.trade.record,
            step.trade.seen.status,
            recordProblem: step.recordProblem,
          ),
        );
      case Ok(value: Ok(value: OrderAlreadyTakenByThisRobot(:final order))):
        // Resumed from its recorded trail, never from a fresh one.
        switch (await _reader.open(pending)) {
          case TradeOpened(:final trade):
            final step = await _reader.advance(
              trade,
              TradeOrderRead(order),
              at: _reader.now(),
            );
            return Ok(
              TakeResumed(
                step.trade.record,
                step.trade.seen.status,
                recordProblem: step.recordProblem,
              ),
            );
          case TradeNotRestorable() || TradeNotOpened() || TradeTakeNeverSent():
            return Ok(TakeOutcomeUnknown(pending));
        }
    }
  }

  /// Whether the order read just before the take is the one the user accepted on the order's page: the same type, currency, amount or range, bond size, escrow duration, sats of an order priced in sats, premium of an order priced against the market (the premium of an order priced in sats moves with its price), and sats at the current price within [TradeTolerances.price] of those the page showed, both ways, so that the bond the terms expect is the one the user saw (the reference's flow has no confirmation apart from the page).
  static bool _sameTerms(PublicOrder shown, PublicOrder fresh) =>
      fresh.coordinator == shown.coordinator &&
      fresh.type == shown.type &&
      fresh.currency == shown.currency &&
      fresh.amount == shown.amount &&
      fresh.bondSize == shown.bondSize &&
      fresh.escrowDuration == shown.escrowDuration &&
      fresh.explicitSatoshis == shown.explicitSatoshis &&
      (shown.explicitSatoshis != null || fresh.premium == shown.premium) &&
      _nearSats(shown.satoshisNow, fresh.satoshisNow);

  /// Whether [fresh] is within [TradeTolerances.price] of [shown], plus [TradeTolerances.roundingSats], both known.
  static bool _nearSats(Sats? shown, Sats? fresh) {
    if (shown == null || fresh == null) return shown == fresh;
    final a = shown.value.toInt();
    final b = fresh.value.toInt();
    return (b - a).abs() <=
        a * TradeTolerances.price + TradeTolerances.roundingSats;
  }

  /// The open trade of order [orderId] of [coordinator] on [network], if this device has one.
  Future<Result<TradeRecord?, P2pFailure>> _openTradeOf(
    RobosatsNetwork network,
    Coordinator coordinator,
    int orderId,
  ) async {
    switch (await _records.watchActiveTrades(network).first) {
      case Ok(:final value):
        for (final record in value) {
          if (record.coordinatorAlias == coordinator.shortAlias &&
              record.orderId == orderId) {
            return Ok(record);
          }
        }
        return const Ok(null);
      case Err(:final failure):
        return Err(failure);
    }
  }

  /// Whether the transport answered the take busy: nothing reached the coordinator ([OrderActionRefused]).
  static bool _answeredBusy(
    Result<TakeOrderOutcome, OrderActionFailure> answer,
  ) => switch (answer) {
    Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) => true,
    _ => false,
  };

  /// The pending take [pending], certainly not made, closed: kept pending when the close cannot be written, for a later read to close.
  Future<TakeNotMade> _notMade(
    TradeRecord pending, {
    required Failure? refusal,
  }) async => switch (await _records.closeTrade(pending)) {
    Ok(:final value) => TakeNotMade(value, refusal: refusal),
    Err(:final failure) => TakeNotMade(
      pending,
      refusal: refusal,
      closeProblem: failure,
    ),
  };

  /// [failure], once the pending take [pending], whose request was never sent, is closed: best effort, a later read of the trade closing it otherwise (`WatchTradeUsecase`).
  Future<P2pFailure> _closedUnsent(
    TradeRecord pending,
    P2pFailure failure,
  ) async => switch (await _records.closeTrade(pending)) {
    Ok() || Err() => failure,
  };
}
