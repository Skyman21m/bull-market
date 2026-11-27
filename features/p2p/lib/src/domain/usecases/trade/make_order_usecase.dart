import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../coordinator_size_limit.dart';
import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../repositories/trade_record_repository.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_binding.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bolt11.dart';
import '../../trade/make_price_check.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_edges.dart';
import '../../trade/trade_make.dart';
import '../../trade/trade_renewal.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_storable.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import '../../trade_robots.dart';
import '../put_robot_on_coordinator_usecase.dart';
import '../read_robot_on_coordinator_usecase.dart';
import 'action_outcome_log.dart';
import 'trade_make_locks.dart';
import 'trade_read_order.dart';
import 'trade_reader.dart';

/// Makes an order on a coordinator as its maker, for a fresh robot of this device, and resolves a make whose answer was lost: the only place a maker's trade starts (#179, design note `docs/design/phase-3-making-an-order.md` § 3.4).
///
/// One make, or resolution of a pending make, at a time per network in the process ([TradeMakeLocks]). In this order, each step only once the one before it succeeded:
/// 1. without a robot: the coordinator is in the federation list on the network; its `/api/info/` (the maker fee) and `/api/limits/` (the price and the limits of the order's currency) are read once, at once, anonymously (no robot's token, as the book); the price check the user saw under the form still holds at that price ([MakePriceSeen.holdsAt], #181), else [MakePriceCheckChanged]; the amount is within the limits the reference's form allows ([MakerAmountLimits]); the terms are built ([MakerTerms.create]): a make refused here costs no robot;
/// 2. a fresh robot is reserved and bound to the coordinator ([TradeRobots.robotForNewTrade]), then put on it ([PutRobotOnCoordinatorUsecase]); a robot the coordinator already knew, or that held an order, is not used, nor one whose Garage Key was deleted or replaced meanwhile: so the robot never had another order on that coordinator, which is what makes the resolution sound;
/// 3. the pending make and its terms are written, in that order ([TradeRecordRepository.recordPendingMake], [TradeTrailRepository.recordMakerTerms]), and the terms read back and compared with those built: the make is refused (and the pending make closed) when any of it fails;
/// 4. `makeOrder` is sent once, with the request given, which equals the terms' ([MakerTerms.request], kept without the password's hash, #189), through the robot's places in [RobotRequestLimiter] (a busy transport, which sends nothing, is tried again as the limiter says), and never again, whatever it gives;
/// 5. its answer: a refusal known to come before the order is made (`OrderActionRefused`), or a transport that never sent it, closes the pending make ([MakeNotMade]); an outcome unknown leaves it pending ([MakePending]); a `MadeOrder` is read by the robot (`GET /api/order/`), and only a read that shows this robot as the order's maker ([TradeReader.showsMaker]) confirms the make with that order's id, then starts its trail with `TradeStatus.afterMake` of that read, on the terms read back from the records ([TradeTerms.restoreMade]), never rebuilt from a later read; a read that does not, goes on as the resolution below.
///
/// The resolution of a pending make ([resolve]): a make whose terms were never written never sent its request and is closed at once ([MakeNeverSent]); otherwise the robot is read back (its binding's coordinator, the short header), and its `active_order_id`, else its `last_order_id` (`RobotView.get`, `api/views.py:725-737`), names the only order this robot can have made (step 2): that order is read by the robot, and confirms the make only as step 5 says; error 1043, which proves nothing, closes it, as a robot that names no order does, its read being sent after the make's request ended (the lock, or a restart). A request still in flight that lands later makes an order at 0 that this app never shows, which the coordinator expires 300 seconds after its creation with nothing paid (`api/logics.py:329-338`). Anything else leaves the make pending, and no bond is shown for it.
///
/// The password's hash leaves only in the make's request: the terms and their record keep whether there is one, never the hash nor the password (#189), and a request without the hash of its password ([MakeOrderRequest.isSendable] false, a renewal's kept terms) is refused before anything ([MakeTermsRefused]).
/// What the make's answer does not carry (the description, the password, the public duration) is compared by the state machine at the first read and the following ones (`TradeTermsChanged`): before any bond is shown.
/// Nothing here pays: the maker bond is paid by the user, from the trade screen.
final class MakeOrderUsecase {
  final CoordinatorClient _client;
  final TradeRobots _robots;
  final PutRobotOnCoordinatorUsecase _put;
  final ReadRobotOnCoordinatorUsecase _readRobot;
  final TradeRecordRepository _records;
  final TradeTrailRepository _trails;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final Bolt11Reader _invoices;
  final TradeMakeLocks _locks;
  final Federation _federation;

  const MakeOrderUsecase(
    this._client,
    this._robots,
    this._put,
    this._readRobot,
    this._records,
    this._trails,
    this._reader,
    this._limiter,
    this._invoices,
    this._locks,
    this._federation,
  );

  /// Makes the order of [request] on [coordinator] and [network], the price check under the form being [seen] when the user pressed « Create order » (#181).
  ///
  /// [Err]: the make was not sent ([MakeRefusal]); a robot reserved by then stays bound to the coordinator, without a trade, and is never used again. [MakePriceCheckChanged] when the price read just before the make would show the user another check than [seen] (security review of #181, C1): refused before any robot.
  /// [Ok]: the make was sent, or may have left; [MakeOutcome] says what it gave.
  Future<Result<MakeOutcome, MakeRefusal>> execute(
    MakeOrderRequest request, {
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required MakePriceSeen seen,
  }) => _locks.run(
    network,
    () =>
        _make(request, coordinator: coordinator, network: network, seen: seen),
  );

  /// Resolves the pending make [make]: whether it made an order, read from the coordinator by its robot (see the class).
  ///
  /// [MakeStarted] when an order is found that shows its robot as the maker; [MakeNotMade] when none can be, the make closed; [MakeNeverSent] when its terms were never written, the make closed with no request; [MakeNoLongerPending] when the records no longer hold it pending (confirmed or closed since), nothing sent; [MakePending] otherwise, for a later resolution.
  Future<MakeOutcome> resolve(PendingMake make) =>
      _locks.run(make.network, () => _resolve(make));

  /// The renewal of the order of [record] (#185): the request this device kept when it made that order, and its coordinator, for a new make by [execute]; it sends nothing and writes nothing.
  ///
  /// Read from the records only, never from what the coordinator reads back of the order: the terms (`maker_terms`, restored with the checks of [MakerTerms.restore]) and the stored trail, which must stand where the reference offers the renewal ([OrderRenewal.offeredAt]). [RenewalNotMadeHere] for a trade taken here or recovered; [RenewalNotEnded] for a trail elsewhere, or none; [RenewalTermsUnreadable] for records that cannot be read or do not restore, or that are of another trade; [RenewalCoordinatorGone] for a coordinator no longer in the federation list on the network, or at another address than the one the order was made on.
  Future<Result<OrderRenewal, RenewalRefusal>> renewal(
    TradeRecord record,
  ) async {
    if (record.origin != TradeOrigin.madeHere || record.confirmedAt == null) {
      return const Err(RenewalNotMadeHere());
    }
    final network = record.network;
    final TradeTrailRecord? trail;
    switch (await _trails.historyOf(record)) {
      case Ok(:final value) when !value.unreadable:
        trail = value.trail;
      case Ok() || Err():
        return const Err(RenewalTermsUnreadable());
    }
    final position = TradePosition.values
        .where((value) => value.name == trail?.position)
        .firstOrNull;
    if (trail == null ||
        position == null ||
        trail.network != network.name ||
        trail.coordinatorAlias != record.coordinatorAlias ||
        trail.orderId != record.orderId ||
        !OrderRenewal.offeredAt(position, role: record.role)) {
      return const Err(RenewalNotEnded());
    }
    final MakerTermsRecord stored;
    switch (await _trails.makerTermsOf(record.robot)) {
      case Ok(value: final value?)
          when value.network == network.name &&
              value.coordinatorAlias == record.coordinatorAlias &&
              value.role == record.role.name:
        stored = value;
      case Ok() || Err():
        return const Err(RenewalTermsUnreadable());
    }
    final MakerTerms terms;
    switch (MakerTerms.restore(stored)) {
      case Ok(:final value):
        terms = value;
      case Err(failure: TradeCoordinatorGone()):
        return const Err(RenewalCoordinatorGone());
      case Err():
        return const Err(RenewalTermsUnreadable());
    }
    // The coordinator of the order, as this use case's federation list gives it now, at the address the order was made on.
    final coordinator = _federation.byAlias(record.coordinatorAlias);
    if (coordinator == null ||
        coordinator != terms.coordinator ||
        CoordinatorIdentity.of(coordinator, network)?.onion !=
            record.coordinatorOnion) {
      return const Err(RenewalCoordinatorGone());
    }
    return Ok(
      OrderRenewal(
        orderId: record.orderId,
        network: network,
        coordinator: coordinator,
        request: terms.request,
      ),
    );
  }

  /// The request this device kept of the order of [record], the orders made here after it with that very request, on its coordinator and network, and whether such a make is still pending (#216, #217): its renewals, or an order made again by hand with the same terms, which this device cannot tell apart and which say the same to the user (an order with these terms already exists). Oldest first: a new list after each write of the records or of the terms, read from the device only, nothing sent.
  ///
  /// The reference, which renews with the same robot, has a second renewal refused while the first order is active (`api/logics.py:75-100`, error 1000); here each renewal has a fresh robot, so nothing refuses it, and the trade screen says it instead (never a lock: renewing again stays the user's choice). [Err] when the records cannot be read, or the terms kept of [record] do not restore: whether it was renewed is then not known, never « not renewed ». An order whose own terms do not restore is never counted as one of them.
  Stream<Result<OrderRenewals, P2pFailure>> renewalsOf(TradeRecord record) {
    final network = record.network;
    Result<List<TradeRecord>, P2pFailure>? recorded;
    Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>? histories;
    Result<List<PendingMake>, P2pFailure>? pending;
    final subscriptions = <StreamSubscription<Object?>>[];
    late final StreamController<Result<OrderRenewals, P2pFailure>> out;

    // Made after [record]: never by the device's clock when both are of the same Garage Key, which may have been set forward or back (security review of #220, C2, N2): a fresh robot of the same key always takes a higher index than every robot used before (`TradeRobots.robotForNewTrade`: the first index neither bound nor recorded, and neither binding nor record is ever deleted); another key's robot, by the time written alone.
    bool after(RobotSlot robot, DateTime writtenAt) =>
        robot != record.robot &&
        (robot.keyFingerprint == record.robot.keyFingerprint
            ? robot.accountIndex > record.robot.accountIndex
            : writtenAt.isAfter(record.takenAt));

    void emit() {
      final (t, h, p) = (recorded, histories, pending);
      if (t == null || h == null || p == null) return;
      switch ((t, h, p)) {
        case (Err(:final failure), _, _) ||
            (_, Err(:final failure), _) ||
            (_, _, Err(:final failure)):
          out.add(Err(failure));
        case (
          Ok(value: final list),
          Ok(value: final made),
          Ok(value: final makes),
        ):
          final kept = record.origin == TradeOrigin.madeHere
              ? _keptRequest(
                  made[record.robot],
                  network: record.network,
                  alias: record.coordinatorAlias,
                  role: record.role,
                )
              : null;
          if (kept == null) {
            out.add(const Err(P2pStorageFailure()));
            return;
          }
          final since = <OrderMadeSince>[];
          for (final trade in list) {
            if (trade.origin != TradeOrigin.madeHere ||
                trade.coordinatorAlias != record.coordinatorAlias ||
                !after(trade.robot, trade.takenAt)) {
              continue;
            }
            final terms = _keptRequest(
              made[trade.robot],
              network: trade.network,
              alias: trade.coordinatorAlias,
              role: trade.role,
            );
            // Terms of an order made after this one that cannot be read: whether it has the same is not known, never « none » (security review of #220, C3).
            if (terms == null) {
              out.add(const Err(P2pStorageFailure()));
              return;
            }
            if (terms != kept) continue;
            since.add(
              OrderMadeSince(
                trade,
                OrderMadeSince.standsOf(
                  trade,
                  TradePosition.values
                      .where(
                        (position) =>
                            position.name == made[trade.robot]?.trail?.position,
                      )
                      .firstOrNull,
                ),
              ),
            );
          }
          // A make of the same terms whose answer was lost, still pending (security review of #220, R2); one whose terms were never written never left, and is none.
          var pendingSameTerms = false;
          for (final make in makes) {
            if (!make.isActive ||
                make.coordinatorAlias != record.coordinatorAlias ||
                !after(make.robot, make.writtenAt) ||
                made[make.robot] == null) {
              continue;
            }
            final terms = _keptRequest(
              made[make.robot],
              network: make.network,
              alias: make.coordinatorAlias,
              role: make.role,
            );
            if (terms == null) {
              out.add(const Err(P2pStorageFailure()));
              return;
            }
            if (terms == kept) pendingSameTerms = true;
          }
          out.add(
            Ok(OrderRenewals(kept, since, pendingSameTerms: pendingSameTerms)),
          );
      }
    }

    void failed(Object error, StackTrace stackTrace) {
      if (error is Exception) {
        out.add(const Err(P2pStorageFailure()));
      } else {
        out.addError(error, stackTrace);
      }
    }

    out = StreamController(
      onListen: () {
        subscriptions
          ..add(
            _records.watchTrades(network).listen((value) {
              recorded = value;
              emit();
            }, onError: failed),
          )
          ..add(
            _trails.watchMadeHistories(network).listen((value) {
              histories = value;
              emit();
            }, onError: failed),
          )
          ..add(
            _records.watchPendingMakes(network).listen((value) {
              pending = value;
              emit();
            }, onError: failed),
          );
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return out.stream;
  }

  /// Whether [made], an order a resolution of a pending make confirmed while the page of [renewal] is open, is made with the very request of [renewal], on its coordinator and network (#217, security review of #185, R3): only such an order closes the renewal's page, a make unrelated to it leaving the page as it is. Read from the records only: [Err] when they cannot be read or the order's terms do not restore, so that the page never takes « cannot tell » for « unrelated » (security review of #220, R1, N1).
  Future<Result<bool, P2pFailure>> madeAsRenewal(
    TradeRecord made,
    OrderRenewal renewal,
  ) async {
    if (made.origin != TradeOrigin.madeHere ||
        made.network != renewal.network ||
        made.coordinatorAlias != renewal.coordinator.shortAlias) {
      return const Ok(false);
    }
    return switch (await _trails.makerTermsOf(made.robot)) {
      Ok(value: final terms?) => switch (MakerTerms.restore(terms)) {
        Ok(:final value) => Ok(
          value.request == renewal.request &&
              value.coordinator == renewal.coordinator,
        ),
        Err() => const Err(P2pStorageFailure()),
      },
      Ok() => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  /// The request kept in [history], the terms of one make, or `null` when none is stored, they are of another [network], coordinator ([alias]) or side ([role]) than its record's (as [renewal] refuses them), or they do not restore.
  static MakeOrderRequest? _keptRequest(
    StoredMadeHistory? history, {
    required RobosatsNetwork network,
    required String alias,
    required TradeRole role,
  }) {
    final terms = history?.terms;
    if (history == null ||
        history.unreadable ||
        terms == null ||
        terms.network != network.name ||
        terms.coordinatorAlias != alias ||
        terms.role != role.name) {
      return null;
    }
    return switch (MakerTerms.restore(terms)) {
      Ok(:final value) => value.request,
      Err() => null,
    };
  }

  /// Sets the pending make [make] aside, on the user's request (#182, reviews of #179): a make that does not resolve (its coordinator left the list or moved, its robot unknown to it, an order it names that is not the robot's, an outcome unknown again and again) is closed in the records, so that nothing reads it again; it is never made again in its place.
  ///
  /// Under the lock of the makes, so that it never closes a make a resolution is confirming. [Ok] `true` when it was closed, `false` when the records no longer hold it pending (confirmed or closed since it was listed), nothing written; [Err] when the records could not be read or written. Nothing is sent: an order the make may have made waits at 0 for a bond this app never shows, and the coordinator expires it on its own (300 s by default, `api/logics.py:329-338`).
  Future<Result<bool, P2pFailure>> dismiss(PendingMake make) =>
      _locks.run(make.network, () async {
        if (!make.isActive) return const Ok(false);
        switch (await _records.watchPendingMakes(make.network).first) {
          case Ok(:final value) when value.any((m) => m.robot == make.robot):
            break;
          case Ok():
            return const Ok(false);
          case Err(:final failure):
            return Err(failure);
        }
        return switch (await _records.closePendingMake(make)) {
          Ok() => const Ok(true),
          Err(:final failure) => Err(failure),
        };
      });

  /// The pending makes of [network], oldest first, each with whether its terms were never written (its request never left), for the « Active trades » list (design note § 3.4, « The screens of a pending make »): a new list after each write of the records or the terms, read from the device only; a database that cannot be read gives a [P2pStorageFailure] in place of the list, never an empty one.
  Stream<Result<List<ActivePendingMake>, P2pFailure>> pendingMakes(
    RobosatsNetwork network,
  ) {
    Result<List<PendingMake>, P2pFailure>? makes;
    Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>? histories;
    StreamSubscription<Result<List<PendingMake>, P2pFailure>>? makesSub;
    StreamSubscription<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>>?
    historiesSub;
    late final StreamController<Result<List<ActivePendingMake>, P2pFailure>>
    out;

    void emit() {
      final (m, h) = (makes, histories);
      if (m == null || h == null) return;
      switch ((m, h)) {
        case (Err(:final failure), _) || (_, Err(:final failure)):
          out.add(Err(failure));
        case (Ok(value: final list), Ok(value: final map)):
          out.add(
            Ok(
              List.unmodifiable([
                for (final make in list)
                  ActivePendingMake(
                    make,
                    neverSent: _neverSent(map[make.robot]),
                  ),
              ]),
            ),
          );
      }
    }

    void failed(Object error, StackTrace stackTrace) {
      if (error is Exception) {
        out.add(const Err(P2pStorageFailure()));
      } else {
        out.addError(error, stackTrace);
      }
    }

    out = StreamController(
      onListen: () {
        makesSub = _records.watchPendingMakes(network).listen((value) {
          makes = value;
          emit();
        }, onError: failed);
        historiesSub = _trails.watchMadeHistories(network).listen((value) {
          histories = value;
          emit();
        }, onError: failed);
      },
      onCancel: () async {
        await makesSub?.cancel();
        await historiesSub?.cancel();
      },
    );
    return out.stream;
  }

  /// Whether a pending make whose stored terms and trail are [history] never sent its request: no terms row at all (`watchMadeHistories` lists the makes that have one), never a row it cannot read, which may be of a make that left (security review of #179).
  static bool _neverSent(StoredMadeHistory? history) =>
      history == null || (history.terms == null && !history.unreadable);

  Future<Result<MakeOutcome, MakeRefusal>> _make(
    MakeOrderRequest request, {
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required MakePriceSeen seen,
  }) async {
    // A protected order sends its password's hash: a request kept without it (a renewal's kept terms) is never sent (#189).
    if (!request.isSendable) {
      return const Err(MakeTermsRefused(MakerTermsUnusable()));
    }
    // 1. The coordinator, its fee and its price, with no robot.
    final listed = _federation.byAlias(coordinator.shortAlias);
    if (listed == null ||
        listed != coordinator ||
        CoordinatorIdentity.of(coordinator, network) == null) {
      return const Err(MakeCoordinatorNotOnNetwork());
    }
    final (info, limits) = await (
      _client.fetchInfo(coordinator, network),
      _client.fetchLimits(coordinator, network),
    ).wait;
    final double makerFee;
    switch (info) {
      case Ok(:final value):
        makerFee = value.makerFee;
      case Err(:final failure):
        return Err(MakeCoordinatorUnreadable(failure));
    }
    final CurrencyLimit limit;
    final CurrencyLimits read;
    switch (limits) {
      case Ok(:final value):
        final found = value[request.currency];
        if (found == null) return const Err(MakePriceUnknown());
        limit = found;
        read = value;
      case Err(:final failure):
        return Err(MakeCoordinatorUnreadable(failure));
    }
    final MakerTerms maker;
    switch (MakerTerms.create(
      network: network,
      coordinator: coordinator,
      request: request,
      createdPrice: limit.price,
      makerFee: makerFee,
    )) {
      case Ok(:final value):
        maker = value;
      case Err(:final failure):
        return Err(MakeTermsRefused(failure));
    }
    // The price check the user saw, at the price this make keeps (`createdPrice`): another line than the one seen stops here, before any robot (#181, security review C1).
    if (seen.currency != request.currency || !seen.holdsAt(limit.price)) {
      return Err(
        MakePriceCheckChanged(
          read,
          MakePriceSeen.of(
            currency: request.currency,
            coordinatorPrice: limit.price,
            check: seen.checkAt(limit.price),
          ),
        ),
      );
    }
    final amountLimits = MakerAmountLimits.of(
      limit,
      premium: request.premium,
      sizeLimitSats: CoordinatorSizeLimit.of(coordinator, _reader.now()).sats,
    );
    if (!amountLimits.allows(request.amount)) {
      return Err(MakeAmountOutsideLimits(amountLimits));
    }

    // 2. A fresh robot, bound to the coordinator, then put on it.
    final ReservedRobot reserved;
    switch (await _robots.robotForNewTrade(network, coordinator)) {
      case Ok(:final value):
        reserved = value;
      case Err(:final failure):
        return Err(MakeRobotRefused(failure));
    }
    switch (await _put.execute(reserved.robot, coordinator)) {
      case Err(:final failure):
        return Err(MakeRobotRefused(failure));
      case Ok(value: Err(:final failure)):
        return Err(MakeRobotNotPut(failure));
      case Ok(value: Ok(value: final face)):
        // A robot of this index that was already there, with another pair, or that held an order, may have travelled: an order it names could be another's.
        if (face.alreadyExisted ||
            face.activeOrderId != null ||
            face.lastOrderId != null) {
          return const Err(MakeRobotRefused(RobotNotForNewTradeFailure()));
        }
    }
    // The Garage Key still the one that gives this robot after its first contact: one deleted or replaced meanwhile leaves a make that could never be read again (as the take, review of #126).
    if (await _robots.robotOfSlot(reserved.robot.slot) case Err(
      :final failure,
    )) {
      return Err(MakeRobotRefused(failure));
    }
    final robot = reserved.robot;

    // 3. The pending make and its terms, before the make leaves.
    final PendingMake pending;
    switch (await _records.recordPendingMake(
      reserved.reservation,
      role: maker.role,
    )) {
      case Ok(:final value):
        pending = value;
      case Err(:final failure):
        return Err(MakeNotRecorded(failure));
    }
    if (await _trails.recordMakerTerms(pending, maker.record) case Err(
      :final failure,
    )) {
      return Err(MakeNotRecorded(await _closedUnsent(pending, failure)));
    }
    // Read back: what is sent is what the records hold, so that every later check compares with what was asked.
    switch (await _trails.makerTermsOf(pending.robot)) {
      case Ok(value: final stored?) when stored == maker.record:
        break;
      case Ok() || Err():
        return Err(
          MakeNotRecorded(
            await _closedUnsent(pending, const P2pStorageFailure()),
          ),
        );
    }

    // 4. The make, once.
    final requests = _limiter.open(robot.identity.sessionKey);
    try {
      final sent = await requests.send(
        network,
        coordinator,
        () => _client.makeOrder(
          coordinator,
          network,
          identity: robot.identity,
          // The request given, with its password's hash: the terms keep it without (#189), equal to it.
          request: request,
        ),
        isBusy: _answeredBusy,
      );

      // 5. What it gave.
      ActionOutcomeLog.answered(
        'make',
        switch (sent) {
          Err() => 'notSent',
          Ok(value: Err(failure: OrderActionRefused())) => 'refused',
          Ok(value: Err()) => 'pending',
          Ok(value: Ok()) => 'answered',
        },
        switch (sent) {
          Err(:final failure) => failure,
          Ok(value: Err(:final failure)) => failure,
          Ok(value: Ok()) => null,
        },
      );
      return Ok(switch (sent) {
        // Busy every time, or the robot released: the make never reached the coordinator.
        Err(:final failure) => await _notMade(pending, refusal: failure),
        Ok(value: Err(failure: OrderActionRefused(:final cause))) =>
          await _notMade(pending, refusal: cause),
        Ok(value: Err(failure: OrderActionOutcomeUnknown())) => MakePending(
          pending,
          MakePendingReason.outcomeUnknown,
        ),
        Ok(value: Ok(value: final made)) => await _settle(
          pending,
          robot,
          coordinator,
          requests,
          candidate: made.id,
        ),
      });
    } finally {
      requests.close();
    }
  }

  Future<MakeOutcome> _resolve(PendingMake make) async {
    if (!make.isActive) return MakeNoLongerPending(make);
    // The make as the records hold it now: one confirmed or closed since it was listed is not resolved again, and its robot not read.
    switch (await _records.watchPendingMakes(make.network).first) {
      case Ok(:final value) when value.any((m) => m.robot == make.robot):
        break;
      case Ok():
        return _said(MakeNoLongerPending(make), 'noLongerListed');
      case Err():
        return _said(
          MakePending(make, MakePendingReason.unread),
          'recordsUnread',
        );
    }
    final MakerTermsRecord? record;
    switch (await _trails.makerTermsOf(make.robot)) {
      case Ok(:final value):
        record = value;
      case Err():
        return _said(
          MakePending(make, MakePendingReason.unread),
          'termsUnread',
        );
    }
    // The make sends its request only once its terms are written: without them it never left.
    if (record == null) {
      return _said(
        MakeNeverSent(
          make,
          closed: switch (await _records.closePendingMake(make)) {
            Ok() => true,
            Err() => false,
          },
        ),
        'noTerms',
      );
    }
    final coordinator = _federation.byAlias(make.coordinatorAlias);
    if (coordinator == null ||
        CoordinatorIdentity.of(coordinator, make.network)?.onion !=
            make.coordinatorOnion ||
        record.coordinatorAlias != make.coordinatorAlias ||
        record.network != make.network.name) {
      return _said(
        MakePending(make, MakePendingReason.unread),
        'coordinatorNotListed',
      );
    }
    final NetworkRobot robot;
    switch (await _robots.robotOfSlot(make.robot)) {
      case Ok(:final value):
        robot = value;
      case Err(:final failure):
        return _said(
          MakePending(make, MakePendingReason.unread),
          'robot ${failure.runtimeType}',
        );
    }
    final requests = _limiter.open(robot.identity.sessionKey);
    try {
      return await _settle(make, robot, coordinator, requests);
    } finally {
      requests.close();
    }
  }

  /// Whether [make] made an order, once its request ended: the order [candidate] the make's answer named, when it shows [robot] as its maker; otherwise the order the robot names (its active order, else its last one), read by the robot.
  Future<MakeOutcome> _settle(
    PendingMake make,
    NetworkRobot robot,
    Coordinator coordinator,
    RobotRequests requests, {
    int? candidate,
  }) async {
    if (candidate != null) {
      switch (await _readMade(make, robot, coordinator, requests, candidate)) {
        case _Read(:final order, :final times)
            when _isOurs(make, coordinator, candidate, order):
          return _said(
            await _confirm(make, robot, coordinator, order, times),
            'answerOrder',
          );
        case _:
          // Not shown as this robot's order, or not read: the robot says which order it made.
          break;
      }
    }
    final int? named;
    switch (await _readRobot.execute(robot)) {
      case Ok(value: Ok(value: final face)):
        named = face.activeOrderId ?? face.lastOrderId;
      case Ok(value: Err(:final failure)):
        return _said(
          MakePending(make, MakePendingReason.unread),
          'robotUnread ${ActionOutcomeLog.causeOf(failure)}',
        );
      case Err(:final failure):
        return _said(
          MakePending(make, MakePendingReason.unread),
          'robotUnread ${failure.runtimeType}',
        );
    }
    // Read after the make's request ended: a robot that names no order made none that this app could show.
    if (named == null) {
      return _said(await _notMade(make, refusal: null), 'noOrderNamed');
    }
    return switch (await _readMade(make, robot, coordinator, requests, named)) {
      _Read(:final order, :final times)
          when _isOurs(make, coordinator, named, order) =>
        _said(
          await _confirm(make, robot, coordinator, order, times),
          'orderNamed',
        ),
      _Read() => _said(
        MakePending(make, MakePendingReason.notRecognized),
        'notTheMaker',
      ),
      // Error 1043 proves nothing about the maker, but leaves nothing to pay: no invoice was ever shown for this make.
      _Cancelled() => _said(
        await _notMade(make, refusal: const OrderCancelled()),
        'cancelled',
      ),
      _NotRead() => _said(
        MakePending(make, MakePendingReason.unread),
        'orderUnread',
      ),
    };
  }

  /// Order [orderId] read by [robot]; the read that expires an order at 0 (error 1022, `api/logics.py:1254-1256`) is followed by one more, which shows it expired.
  Future<_MadeRead> _readMade(
    PendingMake make,
    NetworkRobot robot,
    Coordinator coordinator,
    RobotRequests requests,
    int orderId,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final times = _reader.request();
      switch (await _reader.readOrderOf(
        requests,
        make.network,
        orderId,
        robot,
        coordinator,
        times: times,
      )) {
        case Ok(value: Ok(value: final order)):
          return _Read(order, times);
        case Ok(value: Err(failure: OrderCancelled())):
          return const _Cancelled();
        case Ok(value: Err(failure: OrderMakerBondExpired())):
          continue;
        case Ok(value: Err()) || Err():
          return const _NotRead();
      }
    }
    return const _NotRead();
  }

  /// Whether [order], read as order [orderId] of [coordinator], shows the robot of [make] as its maker, as [TradeReader.showsMaker] says.
  static bool _isOurs(
    PendingMake make,
    Coordinator coordinator,
    int orderId,
    CoordinatorOrder order,
  ) => TradeReader.showsMaker(
    TradeOrderRead(order),
    coordinator: coordinator,
    network: make.network,
    orderId: orderId,
  );

  /// [make] confirmed with [order], which shows its robot as the maker, and its trade started from `TradeStatus.afterMake` of that read, on the terms read back from the records.
  Future<MakeOutcome> _confirm(
    PendingMake make,
    NetworkRobot robot,
    Coordinator coordinator,
    CoordinatorOrder order,
    RequestTimes times,
  ) async {
    // The terms read back from the records, with the order's number, before the confirmation: a make is confirmed only with terms that restore.
    final TradeTerms<MadeSide> terms;
    switch (await _trails.makerTermsOf(make.robot)) {
      case Ok(value: final record?):
        switch (TradeTerms.restoreMade(record, orderId: order.id)) {
          case Ok(:final value):
            terms = value;
          case Err():
            return MakePending(make, MakePendingReason.notConfirmed);
        }
      case Ok() || Err():
        return MakePending(make, MakePendingReason.notConfirmed);
    }
    final TradeRecord record;
    switch (await _records.confirmMake(make, orderId: order.id)) {
      case Ok(:final value):
        record = value;
      case Err():
        return MakePending(make, MakePendingReason.notConfirmed);
    }
    final now = _reader.now();
    final answer = TradeOrderRead(order);
    final status = TradeStatus.afterMake(
      answer,
      terms: terms,
      now: now,
      reader: _invoices,
    );
    // What stays when the first trail cannot be stored: no trail on disk, so no invoice; the next read starts the trade again from its first read.
    final step = await _reader.keep(
      OpenTrade(
        record: record,
        robot: robot,
        coordinator: coordinator,
        terms: terms,
        seen: TradeSeen(
          TradeStatus.beforeFirstRead(
            TradeTrail.forConfirmedMake(terms, record.confirmedAt ?? now),
          ),
          order: null,
        ),
      ),
      TradeSeen(status, order: order, asked: TradeReader.askedOf(terms)),
      showsTaker: false,
      request: times,
      answer: answer,
      at: now,
    );
    return MakeStarted(
      step.trade.record,
      step.trade.seen.status,
      stored: step.stored,
      recordProblem: step.recordProblem,
    );
  }

  /// [outcome], once its line is in the support log ([ActionOutcomeLog.resolved]) with [reason], a fixed word.
  static MakeOutcome _said(MakeOutcome outcome, String reason) {
    ActionOutcomeLog.resolved('make', switch (outcome) {
      MakeStarted() => 'started',
      MakeNotMade() => 'notMade',
      MakeNeverSent() => 'neverSent',
      MakePending(:final reason) => 'pending ${reason.name}',
      MakeNoLongerPending() => 'noLongerPending',
    }, reason);
    return outcome;
  }

  /// Whether the transport answered the make busy: nothing reached the coordinator ([OrderActionRefused]).
  static bool _answeredBusy(Result<MadeOrder, OrderActionFailure> answer) =>
      switch (answer) {
        Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) =>
          true,
        _ => false,
      };

  /// The pending make [make], certainly not made, closed: kept pending when the close cannot be written, for a later resolution to close.
  Future<MakeNotMade> _notMade(
    PendingMake make, {
    required Failure? refusal,
  }) async => switch (await _records.closePendingMake(make)) {
    Ok(:final value) => MakeNotMade(value, refusal: refusal),
    Err(:final failure) => MakeNotMade(
      make,
      refusal: refusal,
      closeProblem: failure,
    ),
  };

  /// [failure], once the pending make [make], whose request was never sent, is closed: best effort, its resolution closing it otherwise ([MakeNeverSent], or the robot naming no order).
  Future<P2pFailure> _closedUnsent(
    PendingMake make,
    P2pFailure failure,
  ) async => switch (await _records.closePendingMake(make)) {
    Ok() || Err() => failure,
  };
}

/// What a read of an order by the robot of a make gave.
sealed class _MadeRead {
  const _MadeRead();
}

/// The order, as the coordinator describes it to the robot, and the times of its read.
final class _Read extends _MadeRead {
  final CoordinatorOrder order;
  final RequestTimes times;

  const _Read(this.order, this.times);
}

/// Error 1043: the order is cancelled.
final class _Cancelled extends _MadeRead {
  const _Cancelled();
}

/// The read gave nothing that tells.
final class _NotRead extends _MadeRead {
  const _NotRead();
}
