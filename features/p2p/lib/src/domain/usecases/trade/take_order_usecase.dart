import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../repositories/trade_record_repository.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_binding.dart';
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
import 'action_outcome_log.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';
import 'prepared_takes.dart';
import 'trade_take_locks.dart';

/// Takes an order of the book as its taker, for a fresh robot of this device: the only place a trade starts (#87, design note § 2.1, `AGENTS.md` « Rules for the trade use cases (#87) » and « The rule for #87 »).
///
/// One take of an order at a time in the process ([TradeTakeLocks]), and none of an order that already has an open trade here: [TakeOrderAlreadyTraded], with its record (the database refuses a second open trade of an order too, the trigger `trades_one_open_per_order`).
/// In this order, each step only once the one before it succeeded:
/// 1. the order is read again just before the take, from the coordinator's book (`GET /api/book/` of its currency and type) with its `/api/info/` (the taker fee), both anonymous: never from a book left open; the terms are built from that read ([TradeTerms.take]), and a take that cannot be checked (a taker fee above the ceiling, an order gone or changed, its sats moved by more than [TradeTolerances.price] from what the user saw, an amount outside the range) stops here, nothing sent with a robot;
/// 2. a fresh robot is reserved for the trade, bound to the order's coordinator ([TradeRobots.robotForNewTrade]), then put on it ([PutRobotOnCoordinatorUsecase]: read back, then its first contact); a robot that already existed there, or held an order, is not used; and a robot whose Garage Key was deleted or replaced meanwhile is not used either ([TradeRobots.robotOfSlot]), a trade of it could never be read again;
/// 3. the pending take, its terms and the first trail of a pending take are written, in that order ([TradeRecordRepository.recordPendingTake], [TradeTrailRepository.recordTerms], [TradeTrailRepository.storeTrail]): the take is refused when any of them fails;
/// 4. the take is sent once, signed by the robot's key leased from [TradeKeyring] for the request ([TradeKeyring.leaseRobot], GHSA-22q8-9ghc-jg3h: a key that cannot be had sends nothing and closes the pending take), through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again;
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
  final TradeKeyring _keyring;
  final PreparedTakes _prepared;

  /// [preparedTakes] holds the takes prepared and not sent: the composition gives its one instance, so that a take prepared through one use case object is confirmed through another.
  TakeOrderUsecase(
    this._client,
    this._robots,
    this._put,
    this._records,
    this._trails,
    this._reader,
    this._limiter,
    this._invoices,
    this._locks,
    this._keyring, {
    PreparedTakes? preparedTakes,
  }) : _prepared = preparedTakes ?? PreparedTakes();

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
    return _locks.run(
      network,
      shown.coordinator,
      shown.id,
      () async => _saidIfNotSent(
        await _take(
          shown,
          network: network,
          amount: amount,
          password: password,
        ),
      ),
    );
  }

  /// [taken], after the support log has said, for a take refused before its request left, the type of its refusal (its type only).
  static Result<TakeOutcome, TakeRefusal> _saidIfNotSent(
    Result<TakeOutcome, TakeRefusal> taken,
  ) {
    if (taken case Err(:final failure)) {
      ActionOutcomeLog.notSent(OutcomeAction.take, failure);
    }
    return taken;
  }

  /// Prepares a take of [shown], the order the user is about to take on [network], for [amount] when it has a range (#119): every step and check of [execute] before the take's request, then a read of the order by the robot that will take it, nothing written in the trade records and no take sent.
  ///
  /// In this order, each step only once the one before it succeeded:
  /// 1. no open trade of the order here; the order read again from the book with the taker fee, both anonymous, checked against [shown], and its terms built and checked from that read ([TradeTerms.take]: the taker fee under its ceiling, sats known, the amount in the range, a sell order), as [execute] does: a take refused here costs no robot;
  /// 2. the robot of the order's preparation, or a fresh one reserved and put on the coordinator, as [execute] does;
  /// 3. `GET /api/order/` by that robot, through its places in `RobotRequestLimiter`: it must be of a public order without a password that this robot takes no part in ([TakeOrderGone] otherwise), and agree with the book's read (type, currency, amount or range, payment methods, maker, bond size, escrow duration, sats of an order priced in sats, premium of an order priced against the market, sats at the current price within `TradeTolerances.price`) and with [shown]'s sats ([TakeOrderChanged] otherwise), the read of the robot never being preferred over the book's, nor the book's over it;
  /// 4. the terms built from the robot's read (`TradeTerms.takeRead`): the read of the robot that takes is the one the take and every later answer are checked against.
  ///
  /// A robot reserved stays the order's until the take is confirmed or abandoned, the order is gone or refused for good ([TakeOrderGone], [TakeTermsRefused], [TakeOrderAlreadyTraded]: then it is forgotten), or another order is prepared: a new preparation of the order (a second tap, a read that failed, figures that changed, another amount) reuses it. A robot reserved and put on the coordinator is a robot the coordinator now knows, without an order, whatever comes next.
  /// [TakePreparationGone] when the order was abandoned or another order prepared while this preparation ran.
  /// [onStep] is told [TakeStep.checkingOrder], [TakeStep.creatingRobot] when a fresh robot is reserved, then [TakeStep.readingOrder], each as it starts.
  /// An order protected by a password is not in the public book, and its robot's read is refused here ([TakeOrderGone]): [prepareUnlisted] prepares it, as an order reached by its URL that no book received (#245).
  /// [garageRobot] is the robot the Garage showed before this call, as the take's screen read it (#251, § 4.2): only kept with a robot reserved here, to say on [PreparedTake.freshRobot] whether the two differ; the robot of the take never comes from it.
  Future<Result<PreparedTake, TakeRefusal>> prepare(
    PublicOrder shown, {
    required RobosatsNetwork network,
    TakeAmount? amount,
    TakeProgress? onStep,
    RobotSlot? garageRobot,
  }) => _prepareLocked(
    shown,
    network: network,
    amount: amount,
    onStep: onStep,
    unlisted: null,
    garageRobot: garageRobot,
  );

  /// Reads order [orderId] of [coordinator] on [network] with the robot that will take it, for an order no book received (#245): a password-protected one, which every book leaves out (`api/views.py:788-790`) and a coordinator shows only to an authenticated robot (`:232-233`), or a public one the book in memory does not hold yet; what the reference's order page does with the user's robot (`basic/OrderPage/index.tsx:75-96`).
  ///
  /// In this order, each step only once the one before it succeeded: no open trade of the order here ([TakeOrderAlreadyTraded], whose trade is opened instead: an order made here included); the robot kept for the order, or a fresh one reserved and put on the coordinator, as [prepare] does ([TakeStep.creatingRobot]); then `GET /api/order/` by that robot ([TakeStep.readingOrder]): it must be a public order that the robot takes no part in, with a password or without, which [UnlistedOrder.ofRead] reads as the book would list it ([TakeOrderGone] otherwise: taken, paused, cancelled, expired or unknown, the robot then forgotten).
  /// The robot stays kept for the order, as after a preparation: [prepareUnlisted] uses it; nothing is written in the trade records and no take is sent. The read itself leaves nothing at the coordinator but the robot's last activity (`api/views.py:226-299`).
  /// [garageRobot] as for [prepare].
  Future<Result<UnlistedOrder, TakeRefusal>> readUnlisted(
    Coordinator coordinator,
    int orderId, {
    required RobosatsNetwork network,
    TakeProgress? onStep,
    RobotSlot? garageRobot,
  }) => _locks.run(network, coordinator, orderId, () async {
    final read = await _readUnlisted(
      coordinator,
      orderId,
      network: network,
      onStep: onStep ?? _noStep,
      garageRobot: garageRobot,
    );
    if (read case Err(failure: TakeOrderGone() || TakeOrderAlreadyTraded())) {
      _prepared.releaseOrder(network, coordinator.shortAlias, orderId);
    }
    return read;
  });

  /// Prepares a take of [shown], an order no book received that its robot read ([readUnlisted]), for [amount] when it has a range (#245): [prepare]'s steps and checks, with [shown] in place of the book's read.
  ///
  /// No open trade of the order here; the taker fee read again, anonymously ([TakeStep.checkingOrder]); the terms of [shown] checked as [prepare] checks the book's read (the taker fee under its ceiling, sats known, the amount in the range); then the robot kept for the order, or a fresh one; then its read again, which must still be public, with a password exactly when [shown] has one ([TakeOrderGone] otherwise), and agree with [shown] as [prepare]'s read agrees with the book's (type, currency, amount or range, payment methods, maker, bond size, escrow duration, sats of an order priced in sats, premium of an order priced against the market, sats at the current price within `TradeTolerances.price`: [TakeOrderChanged] otherwise); the terms built from that read. None of [prepare]'s protections is lifted; [confirm] then reads the order a third time and sends the take, with the password's hash for a protected order. The book is not read again: a coordinator caches its book for 10 s (`api/views.py:85`, `:824`), and the robot's read of the page stands for it.
  /// [garageRobot] as for [prepare].
  Future<Result<PreparedTake, TakeRefusal>> prepareUnlisted(
    UnlistedOrder shown, {
    TakeAmount? amount,
    TakeProgress? onStep,
    RobotSlot? garageRobot,
  }) => _prepareLocked(
    shown.order,
    network: shown.network,
    amount: amount,
    onStep: onStep,
    unlisted: shown,
    garageRobot: garageRobot,
  );

  Future<Result<PreparedTake, TakeRefusal>> _prepareLocked(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
    required TakeProgress? onStep,
    required UnlistedOrder? unlisted,
    required RobotSlot? garageRobot,
  }) async {
    return _locks.run(network, shown.coordinator, shown.id, () async {
      final prepared = await _prepare(
        shown,
        network: network,
        amount: amount,
        onStep: onStep ?? _noStep,
        unlisted: unlisted,
        garageRobot: garageRobot,
      );
      if (prepared case Err(
        failure: TakeOrderGone() ||
            TakeTermsRefused() ||
            TakeOrderAlreadyTraded(),
      )) {
        // Refused for good: its robot, if one was reserved, is never used again.
        _prepared.releaseOrder(network, shown.coordinator.shortAlias, shown.id);
      }
      return prepared;
    });
  }

  /// Sends the take [prepared] holds, on the terms the user saw (#119): steps 3 to 5 of [execute], once the order read again by the same robot is still the one [prepared] shows.
  ///
  /// [TakePreparationGone] when [prepared] is not the current preparation of its order (confirmed already, abandoned, replaced, prepared before a restart, or abandoned while this confirmation read the order), or when the Garage Key that gave its robot was deleted or replaced since; [TakeOrderAlreadyTraded] when the order has an open trade here.
  /// The read again, by the robot, must still be of a public order that it takes no part in, with a password exactly when [prepared]'s read had one ([TakeOrderGone] otherwise), and agree with [prepared]'s read as [prepare] checks the book's, sats within `TradeTolerances.price` of those the user saw, the description the same ([TakeOrderChanged] otherwise: prepare again, with the same robot, to show the new figures): a preparation grown old is never sent, whatever the time it took.
  /// Then the pending take, its terms ([PreparedTake.terms]) and its first trail are written, the take is sent once, and its answer kept, as [execute] does; the order's robot is then the trade's, or spent. An [abandon] after that point does not stop the take.
  /// [onStep] is told [TakeStep.readingOrderAgain], then [TakeStep.sendingTake], each as it starts.
  /// For an order with a password ([prepareUnlisted], #245), [password] is sent as its hash, and without one nothing is read or sent ([TakePasswordMissing]), the preparation kept; the read again must still be of an order with a password. For an order without one, [password] is never sent: its take carries no `password` field.
  Future<Result<TakeOutcome, TakeRefusal>> confirm(
    PreparedTake prepared, {
    OrderPassword? password,
    TakeProgress? onStep,
  }) {
    final terms = prepared.terms;
    return _locks.run(
      terms.network,
      terms.coordinator,
      terms.orderId,
      () async =>
          _saidIfNotSent(await _confirm(prepared, password, onStep ?? _noStep)),
    );
  }

  static void _noStep(TakeStep step) {}

  /// Abandons [prepared] (#119) when it is still its order's latest preparation: nothing is sent; its robot stays bound to that coordinator, without a trade, and is never used again.
  ///
  /// The robot was put on the coordinator, which keeps it as a robot without an order; its read of a public order left nothing there but its last activity: no take, no penalty (`api/views.py:226-299`, `robosats/middleware.py:95-96`, commit ff1998c).
  void abandon(PreparedTake prepared) => _prepared.release(prepared);

  /// Abandons whatever was prepared of [shown] on [network] (#119): for a screen that leaves an order whose preparation failed, which holds no [PreparedTake] to [abandon]. Nothing is sent.
  void abandonOrder(PublicOrder shown, {required RobosatsNetwork network}) =>
      _prepared.releaseOrder(network, shown.coordinator.shortAlias, shown.id);

  /// Forgets the robot kept for order [orderId] of [coordinator] on [network] by [readUnlisted] (#245): for a page left before the order was shown. Nothing is sent.
  void abandonRead(
    Coordinator coordinator,
    int orderId, {
    required RobosatsNetwork network,
  }) => _prepared.releaseOrder(network, coordinator.shortAlias, orderId);

  /// [unlisted], for an order no book received ([prepareUnlisted]): [shown] is its robot's first read, which stands in place of the book's read; `null` for an order of the book.
  Future<Result<PreparedTake, TakeRefusal>> _prepare(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
    required TakeProgress onStep,
    required UnlistedOrder? unlisted,
    required RobotSlot? garageRobot,
  }) async {
    final coordinator = shown.coordinator;
    if (await _noOpenTrade(network, coordinator, shown.id) case Err(
      :final failure,
    )) {
      return Err(failure);
    }
    onStep(TakeStep.checkingOrder);
    final _FreshRead fresh;
    switch (unlisted == null
        ? await _freshRead(shown, network: network, amount: amount)
        : await _unlistedRead(shown, network: network, amount: amount)) {
      case Ok(:final value):
        fresh = value;
      case Err(:final failure):
        return Err(failure);
    }
    // Every check that needs no robot, as [execute] makes it, before a robot is reserved: a take refused so costs none.
    switch (TradeTerms.take(
      fresh.order,
      network: network,
      rangeAmount: amount?.amount,
      takerFee: fresh.takerFee,
    )) {
      case Ok():
        break;
      case Err(:final failure):
        return Err(TakeTermsRefused(failure));
    }
    var reserved = _prepared.robotFor(
      network,
      coordinator.shortAlias,
      shown.id,
    );
    // A robot kept for the order is used again only while the Garage Key still gives it: one of a key deleted or replaced since is forgotten, and a robot of the key now is reserved instead (second review of #126).
    if (reserved != null) {
      if (await _robots.robotOfSlot(reserved.robot.slot) case Err()) {
        _prepared.releaseOrder(network, coordinator.shortAlias, shown.id);
        reserved = null;
      }
    }
    if (reserved == null) {
      onStep(TakeStep.creatingRobot);
      switch (await _freshRobot(network, coordinator)) {
        case Ok(:final value):
          reserved = value;
        case Err(:final failure):
          return Err(failure);
      }
      _prepared.keepRobot(
        network,
        coordinator.shortAlias,
        shown.id,
        reserved,
        garageRobot: garageRobot,
      );
    }
    onStep(TakeStep.readingOrder);
    final CoordinatorOrder read;
    switch (await _robotRead(
      reserved,
      network,
      coordinator,
      shown.id,
      protected: unlisted?.hasPassword ?? false,
    )) {
      case Ok(:final value):
        read = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (!_agree(fresh.order, read) ||
        !_nearSats(shown.satoshisNow, read.satoshisNow)) {
      return const Err(TakeOrderChanged());
    }
    final TradeTerms<TakenSide> terms;
    switch (TradeTerms.takeRead(
      read,
      rangeAmount: amount?.amount,
      takerFee: fresh.takerFee,
    )) {
      case Ok(:final value):
        terms = value;
      case Err(:final failure):
        return Err(TakeTermsRefused(failure));
    }
    final prepared = PreparedTake(
      order: read,
      terms: terms,
      amount: amount,
      readAt: _reader.now(),
      externalKey: reserved.externalKey,
      // Kept with the robot when it was reserved, never computed again (#251, § 4.2).
      freshRobot:
          _prepared.changedRobotFor(network, coordinator.shortAlias, shown.id)
          ? reserved.robot.identity.nickname
          : null,
    );
    // The order abandoned, or another prepared, while this read ran: its robot is no longer kept.
    if (!identical(
      _prepared.robotFor(network, coordinator.shortAlias, shown.id),
      reserved,
    )) {
      return const Err(TakePreparationGone());
    }
    _prepared.add(prepared);
    return Ok(prepared);
  }

  Future<Result<TakeOutcome, TakeRefusal>> _confirm(
    PreparedTake prepared,
    OrderPassword? password,
    TakeProgress onStep,
  ) async {
    final terms = prepared.terms;
    final coordinator = terms.coordinator;
    final network = terms.network;
    // Whether the order the user saw has a password: the read again must say the same, and only then is the password's hash sent.
    final protected = prepared.order.hasPassword;
    if (protected && password == null) return const Err(TakePasswordMissing());
    if (await _noOpenTrade(network, coordinator, terms.orderId) case Err(
      :final failure,
    )) {
      if (failure is TakeOrderAlreadyTraded) _prepared.release(prepared);
      return Err(failure);
    }
    final reserved = _prepared.robotOf(prepared);
    if (reserved == null) return const Err(TakePreparationGone());
    onStep(TakeStep.readingOrderAgain);
    final CoordinatorOrder again;
    switch (await _robotRead(
      reserved,
      network,
      coordinator,
      terms.orderId,
      protected: protected,
    )) {
      case Ok(:final value):
        again = value;
      case Err(failure: final TakeOrderGone gone):
        _prepared.release(prepared);
        return Err(gone);
      case Err(:final failure):
        return Err(failure);
    }
    final seen = prepared.order;
    if (!_sameRead(seen, again) ||
        !_nearSats(seen.satoshisNow, again.satoshisNow)) {
      _prepared.forget(prepared);
      return const Err(TakeOrderChanged());
    }
    // The Garage Key still the one that gives this robot: a trade of a robot whose key is gone could never be read again, its bond paid (review of #126).
    switch (await _robots.robotOfSlot(reserved.robot.slot)) {
      case Ok():
        break;
      case Err(failure: TradeKeyMissingFailure()):
        _prepared.release(prepared);
        return const Err(TakePreparationGone());
      case Err(:final failure):
        return Err(TakeRobotRefused(failure));
    }
    // Still the current preparation once the reads are over: an abandon, or a newer preparation, made meanwhile wins.
    if (!identical(_prepared.robotOf(prepared), reserved)) {
      return const Err(TakePreparationGone());
    }
    // From here the robot is the trade's, or spent: never prepared again.
    _prepared.release(prepared);
    onStep(TakeStep.sendingTake);
    return _recordAndSend(
      reserved,
      coordinator: coordinator,
      network: network,
      terms: terms,
      amount: prepared.amount,
      password: protected ? password : null,
    );
  }

  /// Order [orderId] read by [reserved]'s robot through its places: a public order that it takes no part in, with a password when [protected] is true, without one when false, either when `null` ([readUnlisted]), or why not ([TakeOrderGone] for an order cancelled, out of reach, no longer public to it, or whose password is not as expected; [TakeCoordinatorUnreadable] or [TakeRobotRefused] when the read gave nothing).
  Future<Result<CoordinatorOrder, TakeRefusal>> _robotRead(
    ReservedRobot reserved,
    RobosatsNetwork network,
    Coordinator coordinator,
    int orderId, {
    required bool? protected,
  }) async {
    final requests = _limiter.open(reserved.robot.identity.sessionKey);
    try {
      return switch (await _reader.readOrderOf(
        requests,
        network,
        orderId,
        reserved.robot,
        coordinator,
      )) {
        Err(:final failure) => Err(TakeRobotRefused(failure)),
        Ok(value: Ok(value: final order))
            when order.status == CoordinatorOrderStatus.public &&
                !order.isParticipant &&
                (protected == null || order.hasPassword == protected) =>
          Ok(order),
        // A fresh robot is never a participant: an order shown otherwise is not the public one the user saw.
        Ok(value: Ok()) => const Err(TakeOrderGone()),
        Ok(
          value: Err(
            failure: OrderCancelled() || OrderNotAvailable() || OrderNotFound(),
          ),
        ) =>
          const Err(TakeOrderGone()),
        Ok(value: Err(:final failure)) => Err(
          TakeCoordinatorUnreadable(failure),
        ),
      };
    } finally {
      requests.close();
    }
  }

  Future<Result<UnlistedOrder, TakeRefusal>> _readUnlisted(
    Coordinator coordinator,
    int orderId, {
    required RobosatsNetwork network,
    required TakeProgress onStep,
    required RobotSlot? garageRobot,
  }) async {
    if (await _noOpenTrade(network, coordinator, orderId) case Err(
      :final failure,
    )) {
      return Err(failure);
    }
    var reserved = _prepared.robotFor(network, coordinator.shortAlias, orderId);
    // A robot kept for the order is used again only while the Garage Key still gives it, as in a preparation (second review of #126).
    if (reserved != null) {
      if (await _robots.robotOfSlot(reserved.robot.slot) case Err()) {
        _prepared.releaseOrder(network, coordinator.shortAlias, orderId);
        reserved = null;
      }
    }
    if (reserved == null) {
      onStep(TakeStep.creatingRobot);
      switch (await _freshRobot(network, coordinator)) {
        case Ok(:final value):
          reserved = value;
        case Err(:final failure):
          return Err(failure);
      }
      _prepared.keepRobot(
        network,
        coordinator.shortAlias,
        orderId,
        reserved,
        garageRobot: garageRobot,
      );
    }
    onStep(TakeStep.readingOrder);
    switch (await _robotRead(
      reserved,
      network,
      coordinator,
      orderId,
      protected: null,
    )) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final read):
        // The order abandoned, or another prepared, while this read ran: its robot is no longer kept.
        if (!identical(
          _prepared.robotFor(network, coordinator.shortAlias, orderId),
          reserved,
        )) {
          return const Err(TakePreparationGone());
        }
        return switch (UnlistedOrder.ofRead(read, at: _reader.now())) {
          final shown? when read.id == orderId => Ok(shown),
          _ => const Err(TakeOrderGone()),
        };
    }
  }

  /// The taker fee of [shown]'s coordinator read again from its `/api/info/`, anonymously, and [amount] checked against [shown], the robot's read of an order no book received standing in place of the book (#245): nothing sent with a robot.
  Future<Result<_FreshRead, TakeRefusal>> _unlistedRead(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
  }) async {
    final double takerFee;
    switch (await _client.fetchInfo(shown.coordinator, network)) {
      case Ok(:final value):
        takerFee = value.takerFee;
      case Err(:final failure):
        return Err(TakeCoordinatorUnreadable(failure));
    }
    if (!_amountFits(shown, amount)) return const Err(TakeAmountRefused());
    return Ok((order: shown, takerFee: takerFee));
  }

  /// Whether [amount] is given for a range of [order] and within it, or not given for a fixed amount.
  static bool _amountFits(PublicOrder order, TakeAmount? amount) =>
      switch ((order.amount, amount?.amount)) {
        (FixedOrderAmount(), null) => true,
        (RangeOrderAmount(:final min, :final max), final value?) =>
          value.value >= min.value && value.value <= max.value,
        _ => false,
      };

  /// Whether the robot's [read] says what the book's [fresh] says of the order: its type, currency, amount or range, payment methods, maker, bond size, escrow duration, sats of an order priced in sats, premium of an order priced against the market, and sats at the current price within [TradeTolerances.price].
  static bool _agree(PublicOrder fresh, CoordinatorOrder read) =>
      read.coordinator == fresh.coordinator &&
      read.id == fresh.id &&
      read.type == fresh.type &&
      read.currency == fresh.currency &&
      read.amount == fresh.amount &&
      read.paymentMethods == fresh.paymentMethods &&
      read.maker == fresh.maker &&
      read.bondSize == fresh.bondSize &&
      read.escrowDuration == fresh.escrowDuration &&
      read.explicitSatoshis == fresh.explicitSatoshis &&
      (fresh.explicitSatoshis != null || read.premium == fresh.premium) &&
      _nearSats(fresh.satoshisNow, read.satoshisNow);

  /// Whether the robot's read [again] says what its read [seen], which the user saw, said of the order: the same as [_agree], and the same description.
  static bool _sameRead(CoordinatorOrder seen, CoordinatorOrder again) =>
      again.coordinator == seen.coordinator &&
      again.network == seen.network &&
      again.id == seen.id &&
      again.type == seen.type &&
      again.currency == seen.currency &&
      again.amount == seen.amount &&
      again.paymentMethods == seen.paymentMethods &&
      again.maker == seen.maker &&
      again.bondSize == seen.bondSize &&
      again.escrowDuration == seen.escrowDuration &&
      again.explicitSatoshis == seen.explicitSatoshis &&
      (seen.explicitSatoshis != null || again.premium == seen.premium) &&
      again.description == seen.description;

  Future<Result<TakeOutcome, TakeRefusal>> _take(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
    required OrderPassword? password,
  }) async {
    final coordinator = shown.coordinator;
    // 0. No second trade of an order that has one open here.
    if (await _noOpenTrade(network, coordinator, shown.id) case Err(
      :final failure,
    )) {
      return Err(failure);
    }
    // 1. A fresh read of the order and of the taker fee, with no robot.
    final _FreshRead read;
    switch (await _freshRead(shown, network: network, amount: amount)) {
      case Ok(:final value):
        read = value;
      case Err(:final failure):
        return Err(failure);
    }
    final TradeTerms<TakenSide> terms;
    switch (TradeTerms.take(
      read.order,
      network: network,
      rangeAmount: amount?.amount,
      takerFee: read.takerFee,
    )) {
      case Ok(:final value):
        terms = value;
      case Err(:final failure):
        return Err(TakeTermsRefused(failure));
    }
    // 2. A fresh robot, bound to the coordinator, then put on it.
    final ReservedRobot reserved;
    switch (await _freshRobot(network, coordinator)) {
      case Ok(:final value):
        reserved = value;
      case Err(:final failure):
        return Err(failure);
    }
    // The Garage Key still the one that gives this robot after its first contact: one deleted or replaced meanwhile leaves a trade that could never be read again (review of #126).
    if (await _robots.robotOfSlot(reserved.robot.slot) case Err(
      :final failure,
    )) {
      return Err(TakeRobotRefused(failure));
    }
    return _recordAndSend(
      reserved,
      coordinator: coordinator,
      network: network,
      terms: terms,
      amount: amount,
      password: password,
    );
  }

  /// [Err] when order [orderId] of [coordinator] has an open trade here ([TakeOrderAlreadyTraded]) or the records cannot be read.
  Future<Result<void, TakeRefusal>> _noOpenTrade(
    RobosatsNetwork network,
    Coordinator coordinator,
    int orderId,
  ) async => switch (await _openTradeOf(network, coordinator, orderId)) {
    Err(:final failure) => Err(TakeNotRecorded(failure)),
    Ok(value: final open?) => Err(TakeOrderAlreadyTraded(open)),
    Ok(value: null) => const Ok(null),
  };

  /// The order [shown] read again from its coordinator's book, with the taker fee of its `/api/info/`, both anonymous, checked against [shown] and [amount]: nothing sent with a robot.
  Future<Result<_FreshRead, TakeRefusal>> _freshRead(
    PublicOrder shown, {
    required RobosatsNetwork network,
    required TakeAmount? amount,
  }) async {
    final coordinator = shown.coordinator;
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
    if (!_sameTerms(shown, fresh)) return const Err(TakeOrderChanged());
    if (!_amountFits(fresh, amount)) return const Err(TakeAmountRefused());
    return Ok((order: fresh, takerFee: takerFee));
  }

  /// A fresh robot for a take of an order of [coordinator] on [network]: reserved (bound to the coordinator) by the robot layer, then put on the coordinator; a robot the coordinator already knew with another pair, or with an order, is not used.
  Future<Result<ReservedRobot, TakeRefusal>> _freshRobot(
    RobosatsNetwork network,
    Coordinator coordinator,
  ) async {
    final ReservedRobot reserved;
    switch (await _robots.robotForNewTrade(network, coordinator)) {
      case Ok(:final value):
        reserved = value;
      case Err(:final failure):
        return Err(TakeRobotRefused(failure));
    }
    switch (await _put.execute(reserved.robot, coordinator)) {
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
    return Ok(reserved);
  }

  /// Steps 3 to 5 of a take by [reserved]: the pending take, its terms and its first trail written, the take sent once, its answer kept.
  Future<Result<TakeOutcome, TakeRefusal>> _recordAndSend(
    ReservedRobot reserved, {
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required TradeTerms<TakenSide> terms,
    required TakeAmount? amount,
    required OrderPassword? password,
  }) async {
    final robot = reserved.robot;
    final chosen = amount?.amount;
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
    // Ranked when the take leaves and when its answer arrives: its answer, and a read of the trade it resumes, give the trade's first status; an action of the trade, during which the watch sends no read (#141).
    final takeTimes = _reader.request();
    try {
      taken = await _reader.duringAction(
        pending,
        () => TradeKeyring.signWith(
          _keyring.leaseRobot(robot),
          (key) => requests.send(
            network,
            coordinator,
            () => _reader.timed(
              takeTimes,
              () => _client.takeOrder(
                coordinator,
                network,
                identity: robot.identity,
                key: key,
                orderId: terms.orderId,
                amount: chosen,
                password: password?.hash,
              ),
            ),
            isBusy: _answeredBusy,
          ),
        ),
      );
    } finally {
      requests.close();
    }

    // 5. What it gave.
    ActionOutcomeLog.answered(
      OutcomeAction.take,
      switch (taken) {
        Err() => OutcomeAnswer.notSent,
        Ok(value: Err(failure: OrderActionRefused())) => OutcomeAnswer.refused,
        Ok(value: Err()) => OutcomeAnswer.pending,
        Ok(value: Ok(value: final outcome)) => OutcomeAnswer.ofTake(outcome),
      },
      switch (taken) {
        Err(:final failure) => failure,
        Ok(value: Err(:final failure)) => failure,
        Ok(value: Ok()) => null,
      },
    );
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
          request: takeTimes,
        );
        return Ok(
          TakeStarted(
            step.trade.record,
            step.trade.seen.status,
            recordProblem: step.recordProblem,
            stored: step.stored,
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
              request: takeTimes,
            );
            return Ok(
              TakeResumed(
                step.trade.record,
                step.trade.seen.status,
                recordProblem: step.recordProblem,
                stored: step.stored,
              ),
            );
          case TradeNotRestorable() || TradeNotOpened() || TradeTakeNeverSent():
            return Ok(TakeOutcomeUnknown(pending));
        }
    }
  }

  /// Whether the order read just before the take is the one the user accepted on the order's page: the same type, currency, amount or range, payment methods, maker, bond size, escrow duration, sats of an order priced in sats, premium of an order priced against the market (the premium of an order priced in sats moves with its price), and sats at the current price within [TradeTolerances.price] of those the page showed, both ways, so that the bond the terms expect is the one the user saw (the reference's flow has no confirmation apart from the page).
  ///
  /// The payment methods and the maker are compared too (security review of #133): otherwise a book could show one method on the page and the take go out on another.
  static bool _sameTerms(PublicOrder shown, PublicOrder fresh) =>
      fresh.coordinator == shown.coordinator &&
      fresh.type == shown.type &&
      fresh.currency == shown.currency &&
      fresh.amount == shown.amount &&
      fresh.paymentMethods == shown.paymentMethods &&
      fresh.maker == shown.maker &&
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

/// The order read again from the book just before a take, and the taker fee of its coordinator.
typedef _FreshRead = ({PublicOrder order, double takerFee});
