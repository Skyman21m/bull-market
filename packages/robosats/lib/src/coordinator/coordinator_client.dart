import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/action_signature.dart';
import 'package:robosats/src/coordinator/chat.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_info.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/coordinator/coordinator_robot.dart';
import 'package:robosats/src/coordinator/coordinator_transport.dart';
import 'package:robosats/src/coordinator/currency_limits.dart';
import 'package:robosats/src/coordinator/dropped_order_reason.dart';
import 'package:robosats/src/coordinator/host_rating.dart';
import 'package:robosats/src/coordinator/make_order.dart';
import 'package:robosats/src/coordinator/order_book.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/payout.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/coordinator/trade_action.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/bitcoin_address.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_identity.dart';
import 'package:robosats/src/robot_pgp_key.dart';

/// Reads the public endpoints of one coordinator at a time, and the robot of this device on it, through a [CoordinatorTransport], and sends that robot's make of an order and its pause, its take and cancel of an order, its payout as buyer, and the actions of the trade's chat step: « fiat sent » and its undo, a dispute, the rating of the coordinator; and the token to rate the coordinator on Nostr.
///
/// Every request that changes a state carries, after the fix of GHSA-22q8-9ghc-jg3h (RoboSats pull request 2955, head `0943c97`), a cleartext signature by the robot's key of the text `action_signature.dart` gives, in a last `signature` field of its body, as the reference's `{ ...body, signature }`: so each of those methods takes the robot's unlocked key, refuses to send with another robot's ([ActionSignatureRefusal.notSigned]), and signs at the time of this client's clock; the coordinator alias signed is the one of the federation list this client embeds, never one a coordinator sends. The chat's post is not signed, as in the reference.
/// A coordinator that does not run the fix yet ignores the field: Django REST framework reads only the fields its serializers declare (`api/serializers.py`, commit babf62e).
///
/// Every method returns a failure instead of throwing, whatever the coordinator sends and even if the transport breaks its contract by throwing an [Exception]: a [CoordinatorFailure], or an [OrderActionFailure] for an action on an order.
/// For a read, only exceptions are caught: an `Error` thrown by the transport is a programming error and propagates, as rule 11 of `AGENTS.md` requires.
/// For an action on an order, an `Error` is caught too and read as an outcome unknown, since the request may have left.
/// Methods are independent: call them concurrently, one future per coordinator.
final class CoordinatorClient {
  final CoordinatorTransport _transport;
  final DateTime Function() _clock;

  /// [clock] gives the time that rules out absurd order dates, the system clock by default.
  CoordinatorClient(this._transport, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// `GET /api/info/`, checked against the federation entry of [coordinator]: an identity mismatch is a [CoordinatorIdentityFailure].
  Future<Result<CoordinatorInfo, CoordinatorFailure>> fetchInfo(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/info/',
      const {},
      CoordinatorReadBounds.infoBytes,
    );
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => switch (CoordinatorInfo.parse(value)) {
        Err(:final failure) => Err(failure),
        Ok(value: final info) => coordinator.verifyIdentity(info, network),
      },
    };
  }

  /// `GET /api/book/`, the public orders of [coordinator], of one [currency] and one [type] when given.
  ///
  /// The official client sends no parameter, which is the same as asking for every currency and both types (`currency=0`, `type=2`).
  /// A coordinator with no order answers `404`, which gives an empty book.
  /// An order that does not match the filters is dropped with [DroppedOrderReason.filterMismatch].
  Future<Result<OrderBook, CoordinatorFailure>> fetchBook(
    Coordinator coordinator,
    RobosatsNetwork network, {
    RobosatsCurrency? currency,
    OrderType? type,
  }) async {
    final response = await _exchange(coordinator, network, '/api/book/', {
      if (currency != null) 'currency': '${currency.id}',
      if (type != null) 'type': '${type.wire}',
    }, CoordinatorReadBounds.bookBytes);
    if (response case Ok(value: CoordinatorResponse(statusCode: 404))) {
      return switch (_decode(response)) {
        Ok(value: final Map<String, Object?> body)
            when body.containsKey('not_found') =>
          Ok(OrderBook.empty(coordinator)),
        _ => const Err(CoordinatorUnexpectedStatus(404)),
      };
    }
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => OrderBook.parse(
        value,
        coordinator,
        _clock(),
        currency: currency,
        type: type,
      ),
    };
  }

  /// `GET /api/limits/`, the market price of [coordinator] and its order size bounds in every currency.
  Future<Result<CurrencyLimits, CoordinatorFailure>> fetchLimits(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/limits/',
      const {},
      CoordinatorReadBounds.limitsBytes,
    );
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => CurrencyLimits.parse(value),
    };
  }

  /// `GET /api/robot/` with the first-contact `Authorization` header: creates the robot [identity] on [coordinator] when it does not know it, and reads it back either way.
  ///
  /// The official client sends this same request for a new and for a known robot, to every coordinator, with the same [pgpKey] (`frontend/src/models/Robot.model.ts:113-114`).
  /// What a coordinator does with it (`robosats/middleware.py:62-178`, commit ff1998c):
  /// - it does not know the token hash: it checks the two OpenPGP keys, creates the robot with them and with the Nostr public key, and answers with what it stored;
  /// - it knows the token hash: it ignores the three keys of the header and answers with the ones it stored at the first contact, whoever made it.
  ///
  /// Nothing in a `200` answer tells the two cases apart but [CoordinatorRobot.found] and the key pair, so the answer is always checked against this device: see [CoordinatorRobotAnswer.parse].
  /// The answer is a [CoordinatorRobot] that carries [pgpKey] when the coordinator returned that very pair: it created the robot with it.
  /// It is an [UnprovenCoordinatorRobot] when the coordinator returned another pair, as it does for a robot first created by another device or client: only [UnprovenCoordinatorRobot.prove] takes that pair, once the robot's token has proved it, and never silently.
  /// Fails with a [CoordinatorRobotFailure] when the coordinator refuses the robot or returns another one, and with any other [CoordinatorFailure] as the public reads do.
  ///
  /// Send a pair made for [identity] by `RobotPgpKey.generate` for this very request: the coordinator keeps the pair of the first contact for good, and a pair returned equal to [pgpKey] is taken without any proof, so this device must know that [pgpKey] is locked by the token of [identity].
  ///
  /// Error 7004, [RobotNicknameTaken], is followed by one request with the short header, which reads the robot back when the coordinator created it for another copy of this very request, as when the transport retries a request whose connection broke after it was sent; its answer is checked against [pgpKey] too.
  /// That check has a blind window: the reference coordinator creates the user (`robosats/middleware.py:152`) before the token (`:163`), so a follow-up that lands between the two is answered 7001, and [RobotNicknameTaken] is reported although the robot is being created for this device.
  /// A coordinator can also answer 7004 for ever, to every robot.
  /// So a caller must not give up a Garage Key index on one [RobotNicknameTaken]: it asks again with [fetchKnownRobot] a little later before it moves to the next index, and it bounds how many indexes a single coordinator can make it give up.
  ///
  /// [nostrKeyDerivation] chooses the Nostr public key sent: keep the default, the other formula gives a key whose secret the coordinator can compute.
  /// The coordinator keeps the key of the first contact for good.
  ///
  /// A robot costs nothing and commits to nothing, but it is an account on a third-party server: create one only when the user asks for it.
  Future<Result<CoordinatorRobotAnswer, CoordinatorFailure>> fetchRobot(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required RobotPgpKey pgpKey,
    NostrKeyDerivation nostrKeyDerivation = NostrKeyDerivation.currentFrontend,
  }) async {
    final contact = await _fetchRobot(
      coordinator,
      network,
      identity,
      identity.firstContactAuthorizationHeader(
        pgpPublicKey: pgpKey.publicKey.armored,
        pgpEncryptedPrivateKey: pgpKey.encryptedPrivateKeyArmored,
        nostrKeyDerivation: nostrKeyDerivation,
      ),
      firstContact: true,
    );
    if (contact case Err(failure: RobotNicknameTaken())) {
      // The nickname may be taken by this very robot: a coordinator that receives the first contact twice at once, as when the transport retries a request whose connection broke after it was sent, creates the robot for one and refuses the other.
      // The short header tells, unless it lands before the coordinator has stored the token: it reads the robot if the coordinator knows this token, and creates nothing.
      final known = await _fetchRobot(
        coordinator,
        network,
        identity,
        identity.authorizationHeader(),
        firstContact: false,
      );
      if (known case Ok(value: final body)) {
        final read = CoordinatorRobotAnswer.parse(
          body,
          coordinator,
          identity: identity,
          sentKey: pgpKey,
        );
        if (read case Ok()) return read;
      }
    }
    return switch (contact) {
      Err(:final failure) => Err(failure),
      Ok(value: final body) => CoordinatorRobotAnswer.parse(
        body,
        coordinator,
        identity: identity,
        sentKey: pgpKey,
      ),
    };
  }

  /// `GET /api/robot/` with the short `Authorization` header, which sends no key: reads the robot [identity] on a [coordinator] that already knows it, and never creates it.
  ///
  /// Fails with [RobotUnknown] when the coordinator has no robot for this token.
  /// The answer is checked against this device as [fetchRobot] checks it, but nothing was sent to compare its key pair with: it is always an [UnprovenCoordinatorRobot], whose [UnprovenCoordinatorRobot.prove] gives the robot once the robot's token has proved the pair.
  /// So nothing has to be stored on this device to read a robot back: its token is enough.
  Future<Result<UnprovenCoordinatorRobot, CoordinatorFailure>> fetchKnownRobot(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
  }) async => switch (await _fetchRobot(
    coordinator,
    network,
    identity,
    identity.authorizationHeader(),
    firstContact: false,
  )) {
    Err(:final failure) => Err(failure),
    Ok(value: final body) => UnprovenCoordinatorRobot.parse(
      body,
      coordinator,
      identity: identity,
    ),
  };

  /// `GET /api/order/?order_id=`, the order [orderId] as [coordinator] describes it to the robot [identity], sent with the robot's short `Authorization` header, which sends no key.
  ///
  /// The answer depends on who asks and on the status (`api/views.py:226-528`, commit ff1998c): see [CoordinatorOrder] for what is read and checked, against [identity] too.
  /// A coordinator that does not know the robot answers [RobotUnknown]; an order cancelled is [OrderCancelled], one this robot may not see is [OrderNotAvailable], and an unknown number is [OrderNotFound], as is a number out of range, which is not sent.
  /// A `GET`, so the transport may send it again after a connection failure.
  ///
  /// Known limit: the short header carries no Nostr key, so a read never replaces the all-zero placeholder key a coordinator may hold for the robot; only a request with the first-contact header does (`robosats/middleware.py:98-107`).
  Future<Result<CoordinatorOrder, CoordinatorFailure>> fetchOrder(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required int orderId,
  }) async {
    if (!_isOrderId(orderId)) return const Err(OrderNotFound());
    final response = await _exchange(
      coordinator,
      network,
      '/api/order/',
      {'order_id': '$orderId'},
      CoordinatorReadBounds.orderBytes,
      robot: (
        identity: identity,
        authorization: identity.authorizationHeader(),
      ),
    );
    return switch (_orderAnswer(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => CoordinatorOrder.parse(
        value,
        coordinator,
        network,
        orderId: orderId,
        identity: identity,
      ),
    };
  }

  /// `POST /api/make/`: asks [coordinator] to make the order of [request] with the robot [identity] as its maker (`MakerView.post`, `api/views.py:90-216`, commit ff1998c).
  ///
  /// The body is the reference client's, its keys in the same order (`Order.make`, `frontend/src/models/Order.model.ts:196-215`): see [MakeOrderRequest]; it is sent with the robot's short header and session, where the reference sends the first-contact header with the robot's keys (`frontend/src/models/Robot.model.ts:72-86`): put the robot on the coordinator first. A coordinator that knows the robot makes nothing of the keys of a first-contact header but its Nostr key, which it takes only to replace the placeholder key it may hold for the robot, at most once every two minutes (`robosats/middleware.py:93-107`); the short header carries no Nostr key, so such a placeholder stays, as for every request of this client with that header ([fetchOrder]).
  ///
  /// A `201` answer is the order as `ListOrderSerializer` writes it, read as a [MadeOrder] only when it is at status 0 and every term it carries equals [request]'s (see there for the terms it does not carry); it holds no bond invoice and does not say that this robot is the maker: the first [fetchOrder] by the robot does.
  /// A `201` that differs, any other `2xx` included, is an [OrderActionOutcomeUnknown]: an order may exist.
  ///
  /// The coordinator's refusals that come before it makes anything (`api/views.py:99-209`) are an [OrderActionRefused]: the empty `400` of its form check ([OrderRequestRefused] without a code), the authentication's (`401`, `403`, 1036, 7000, 7003: [RobotCredentialsRejected]; 7001: [RobotUnknown]), its book full ([OrderBookFull], 1037), no amount (1038, 1039, unreachable with a [MakeOrderRequest]: [OrderRequestRefused] with the code), this robot already in an order ([RobotHasActiveOrder], 1000 to 1003, `409`), the size of the order ([OrderSizeRefused], 1004 to 1009), its meeting point ([OrderLocationRefused], 1010); and the transport's [CoordinatorTransportBusy], before sending.
  /// Every other failure is an [OrderActionOutcomeUnknown]: an order may exist, made with this robot, waiting at 0 for a bond that nobody was shown, which the coordinator expires 300 seconds after its creation with nothing paid (`api/logics.py:329-338`). Reading the robot (`fetchKnownRobot`, its active or last order) tells whether it made one.
  /// Known limits, each an outcome unknown although the reference made nothing: a currency the app knows and the coordinator's table lacks, which fails with a `500` before the order is saved (`Currency.objects.get`, `api/views.py:181`); a `4xx` with a body and no code, such as Django REST framework's own parse error, which comes before the view. Both are left unknown on purpose: a `500` or a body without a code is no proof of when it came.
  /// The other way round, a `401` or `403` whatever its body (a proxy's page included) and an empty `400` are taken as refusals known to come before the order is made, because the reference never answers them after it saved one; an intermediary that answered them after passing the request on would make a refusal of an order that exists.
  /// The dates of a [MadeOrder] are the coordinator's word, bounded only by 2020 to 2100 and `expires_at` after `created_at`: not a deadline to rely on.
  /// A refusal is the coordinator's word too: one that lies after making the order leaves it at 0, with no bond invoice made, until it expires; if the make use case (#179) later finds that order by reading the robot, it shows a bond only after it has compared the order read with the terms it asked.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  /// Signed with [key], the unlocked key of [identity], over `make:{shortAlias}:{unix_ts}` at this client's clock: a coordinator whose clock is more than 300 seconds away refuses it with 1060 ([ActionSignatureRefused]).
  ///
  /// A request that cannot be sent ([MakeOrderRequest.isSendable]: one a device kept of an order with a password, without the password's hash) is refused before anything is sent, with [OrderRequestRefused] without a code: the body would send a protected order without its password.
  Future<Result<MadeOrder, OrderActionFailure>> makeOrder(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required MakeOrderRequest request,
  }) async {
    if (!request.isSendable) {
      return const Err(OrderActionRefused(OrderRequestRefused(null)));
    }
    final response = await _postAsRobot(
      coordinator,
      network,
      identity: identity,
      key: key,
      path: '/api/make/',
      body: request.body,
      signedText: (now) =>
          timedActionContent('make', coordinator.shortAlias, now),
    );
    return switch (response) {
      Err(:final failure) => Err(_afterMake(failure)),
      Ok(value: CoordinatorResponse(statusCode: 201)) => switch (_decode(
        response,
      )) {
        Err(:final failure) => Err(_afterMake(failure)),
        Ok(:final value) => parseMakeAnswer(
          value,
          coordinator,
          network,
          request: request,
        ).mapErr(_afterMake),
      },
      Ok(value: final answer) => Err(_afterMake(_makeRefusal(answer))),
    };
  }

  /// Why a coordinator answered a make with a status other than `201`: the codes of `MakerView.post` (`api/views.py:99-209`) and of the checks it calls (`api/logics.py:138-188`), then the rule of every request about an order ([_orderRefusal]).
  ///
  /// A code is read on a `4xx` answer only; a `2xx` other than `201` is the HTTP status alone.
  static CoordinatorFailure _makeRefusal(CoordinatorResponse answer) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) {
      return CoordinatorUnexpectedStatus(status);
    }
    final code = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(
        object,
      ).optionalInt('error_code', min: 0, max: 99999),
      _ => null,
    };
    for (final reason in OrderSizeRefusal.values) {
      if (reason.code == code) return OrderSizeRefused(reason);
    }
    return switch (code) {
      1010 => const OrderLocationRefused(),
      1036 => const RobotCredentialsRejected(),
      1037 => const OrderBookFull(),
      _ => _orderRefusal(answer),
    };
  }

  /// Whether [failure] of a make comes before the coordinator made an order, so that none was made.
  ///
  /// Refused: the refusals listed in [makeOrder], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy] (nothing sent).
  /// Everything else is an outcome unknown: a code the reference does not answer to a make, a `5xx` (the reference logs the order after it saved it, `api/views.py:213-215`), a malformed or unexpected answer, a lost connection, a timeout.
  static OrderActionFailure _afterMake(CoordinatorFailure failure) =>
      switch (failure) {
        RobotHasActiveOrder() ||
        OrderSizeRefused() ||
        OrderLocationRefused() ||
        OrderBookFull() ||
        OrderRequestRefused(errorCode: null || 1038 || 1039) ||
        ActionSignatureRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// `POST /api/order/?order_id=` with the action `take`: asks [coordinator] for the order [orderId] for the robot [identity], which then has a while to lock its bond.
  ///
  /// The body is the reference client's (`frontend/src/models/Order.model.ts:233-243`, commit ff1998c): `{"action":"take","amount":…}`, with `"password"` before `"amount"` when there is one.
  /// [amount] is the amount chosen in a range order, in the order's currency, which for an order in bitcoin (currency 1000) is bitcoin, not sats; for a fixed order leave it `null`, and `0` is sent, as the reference client sends it and the coordinator ignores it.
  /// The coordinator refuses more than 8 decimals with an empty `400`, read as [OrderRequestRefused].
  /// [password] is the hash of the password the user typed for a protected order ([OrderPasswordHash.of], the SHA-256 of its UTF-8 bytes in lowercase hexadecimal, `OrderDetails/TakeButton.tsx:333`, the very hash a make sends, #189), sent as the reference client sends it; `null`, for an order without a password, sends no `password` field. The text never reaches this client (#245).
  ///
  /// A `200` answer is the order as the coordinator then describes it, read as a [TakeOrderOutcome]: [OrderTakeStarted] only when it shows this robot as the pre-taker with its bond, [OrderAlreadyTakenByThisRobot] when this robot was already the taker, [OrderNotTaken] otherwise (the reference coordinator answers a take on an order that is no longer public with the order as it is, and no error, `api/views.py:595-596`).
  /// A failure is an [OrderActionRefused] when nothing was done, and an [OrderActionOutcomeUnknown] when the take may have happened.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included: the next [fetchOrder] tells what happened.
  Future<Result<TakeOrderOutcome, OrderActionFailure>> takeOrder(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required int orderId,
    FiatAmount? amount,
    OrderPasswordHash? password,
  }) async {
    if (!_isOrderId(orderId)) {
      return const Err(OrderActionRefused(OrderNotFound()));
    }
    final response = await _postOrderAction(
      coordinator,
      network,
      identity: identity,
      key: key,
      orderId: orderId,
      action: 'take',
      fields: {
        if (password != null) 'password': password.hex,
        'amount': amount == null ? 0 : jsonNumber(amount.value),
      },
    );
    return switch (_orderAnswer(response)) {
      Err(:final failure) => Err(_afterAction(failure)),
      Ok(:final value) => parseTakeAnswer(
        value,
        coordinator,
        network,
        orderId: orderId,
        identity: identity,
      ).mapErr(_afterAction),
    };
  }

  /// `POST /api/order/?order_id=` with the action `cancel`: asks the coordinator of [lastRead] to cancel that order for the robot [identity], which read it.
  ///
  /// The cancel is always guarded: `cancel_status` is the status of [lastRead], and the coordinator cancels only if it still has the order in that status, refusing with [OrderStatusChanged] otherwise (`api/logics.py:1010-1015`).
  /// Without the guard, a cancel that lands after the taker's bond locked settles that bond (`api/logics.py:1108-1130`); with it, it is refused.
  /// The coordinator compares the status it stores, and a pre-take shown as [CoordinatorOrderStatus.waitingForTakerBond] is stored as [CoordinatorOrderStatus.public]: that is what is sent then.
  /// The body is `{"action":"cancel","cancel_status":N}`: the reference client's, plus a guard its taker never sends (`frontend/src/components/TradeBox/index.tsx:245-254`), a deviation.
  /// The coordinator and the network are those of [lastRead]; an order read by another robot is refused with [OrderReadElsewhere], and nothing is sent.
  ///
  /// The answer is [OrderCancelEnded] when the order is over, and otherwise [OrderCancelAccepted] with the order as it then is; a failure is an [OrderActionRefused] when nothing was done, and an [OrderActionOutcomeUnknown] when the cancel may have happened.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included: the next [fetchOrder] tells what happened.
  Future<Result<CancelOrderOutcome, OrderActionFailure>> cancelOrder({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) async {
    if (!lastRead.wasReadBy(identity)) {
      return const Err(OrderActionRefused(OrderReadElsewhere()));
    }
    final coordinator = lastRead.coordinator;
    final network = lastRead.network;
    final orderId = lastRead.id;
    final response = await _postOrderAction(
      coordinator,
      network,
      identity: identity,
      key: key,
      orderId: orderId,
      action: 'cancel',
      fields: {'cancel_status': storedStatusOf(lastRead).wire},
    );
    return switch (_orderAnswer(response)) {
      Err(:final failure) => Err(_afterAction(failure)),
      Ok(:final value) => parseCancelAnswer(
        value,
        coordinator,
        network,
        orderId: orderId,
        identity: identity,
      ).mapErr(_afterAction),
    };
  }

  /// `POST /api/order/?order_id=` with the action `pause`: pauses the public order of [lastRead], or makes its paused order public again, for the robot [identity], its maker (`Logics.pause_unpause_public_order`, `api/logics.py:1758-1782`, commit ff1998c).
  ///
  /// **The request has no direction**: the coordinator turns 1 into 2 and 2 into 1, whatever status the maker saw, so the same request pauses and resumes, and a request sent twice undoes itself.
  /// Never send it again to retry, nor because an answer was lost: read the order first, and send it only when the fresh read shows the status the user saw (design note `docs/design/phase-3-making-an-order.md` § 3.4).
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:310-313`): `{"action":"pause"}`, for both buttons.
  ///
  /// Nothing is sent, and the failure is an [OrderActionRefused], when [lastRead] was read by another robot ([OrderReadElsewhere]), does not show this robot as the maker ([TradeActionNotMaker]), or is not at 1 or 2 ([TradeActionNotNow]), each decided from [lastRead]: read the order again before telling the user.
  /// The answer is [TradeActionAccepted] with the order as it then is, at a status the toggle can lead to ([pauseFollows]: 1 or 2, or what a timer or a taker made of it before the read); any other is an outcome unknown.
  /// 5 is the public deadline passed between the toggle and the read; 6, 7 and 8 are a take whose bond locked in that moment, and the taker's step, which can only follow a toggle 2 → 1, a resume: the coordinator finalizes a take only on a public order (`api/management/commands/follow_invoices.py:243-251`), so after a toggle 1 → 2 they come only from a coordinator that answers falsely. They are accepted because the last read cannot tell which way the coordinator toggled; the caller reads the order again either way.
  /// So the package returns the order read after the toggle and does not say which way the toggle went. **An answer at the status of [lastRead] means that the order was toggled the other way, or twice**: without any malice when the same robot paused or resumed it from another client (the official app with the same token) between the fresh read and this request, so that a « pause » sent here makes the order public again and its answer comes as an accepted action. The caller must compare the status of the answer with the status it wanted, show the status of the answer, never the direction asked, and tell the user when the order stayed or became public again: a public order can be taken, and the maker's bond is then at stake.
  /// The coordinator's refusals, 1032 ([TradeActionNotMaker]), 1033 ([TradeActionNotNow]), 1047 ([OrderNotParticipant], `api/views.py:617-619`), the empty `400` of its form check and the authentication's, come before it changes anything and are an [OrderActionRefused]; every other failure is an [OrderActionOutcomeUnknown]: read the order again, and never send again blindly.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> pauseOrder({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) async {
    if (!lastRead.wasReadBy(identity)) {
      return const Err(OrderActionRefused(OrderReadElsewhere()));
    }
    if (!lastRead.isMaker) {
      return const Err(
        OrderActionRefused(TradeActionNotMaker(fromLastRead: true)),
      );
    }
    if (lastRead.status != CoordinatorOrderStatus.public &&
        lastRead.status != CoordinatorOrderStatus.paused) {
      return const Err(
        OrderActionRefused(TradeActionNotNow(fromLastRead: true)),
      );
    }
    final response = await _postOrderAction(
      lastRead.coordinator,
      lastRead.network,
      identity: identity,
      key: key,
      orderId: lastRead.id,
      action: 'pause',
    );
    return switch (response) {
      Err(:final failure) => Err(_afterPause(failure)),
      Ok(value: CoordinatorResponse(statusCode: 200)) => switch (_decode(
        response,
      )) {
        Err(:final failure) => Err(_afterPause(failure)),
        Ok(:final value) => parseTradeActionAnswer(
          value,
          identity: identity,
          lastRead: lastRead,
          follows: pauseFollows,
        ).mapErr(_afterPause),
      },
      Ok(value: final answer) => Err(_afterPause(_pauseRefusal(answer))),
    };
  }

  /// Why a coordinator answered a pause with a status other than `200`: 1032, 1033 and 1047, then the rule of every request about an order ([_orderRefusal]).
  ///
  /// A code is read on a `4xx` answer only; the codes of the other actions are not a pause's refusals.
  static CoordinatorFailure _pauseRefusal(CoordinatorResponse answer) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) return _orderRefusal(answer);
    final code = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(
        object,
      ).optionalInt('error_code', min: 0, max: 99999),
      _ => null,
    };
    return switch (code) {
      1032 => const TradeActionNotMaker(fromLastRead: false),
      1033 => const TradeActionNotNow(fromLastRead: false),
      1047 => const OrderNotParticipant(),
      _ => _orderRefusal(answer),
    };
  }

  /// Whether [failure] of a pause comes before the coordinator changed anything, so that the order is as it was.
  ///
  /// Refused: [TradeActionNotMaker], [TradeActionNotNow] and [OrderNotParticipant] (each answered before the toggle, `api/views.py:617-619`, `api/logics.py:1759-1781`), the empty `400` of the form check, the authentication's refusals, [OrderReadElsewhere], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy].
  /// Everything else is an outcome unknown: a code of another action, a `5xx`, an error of the read that follows the toggle, a malformed answer, a lost connection.
  static OrderActionFailure _afterPause(CoordinatorFailure failure) =>
      switch (failure) {
        TradeActionNotMaker() ||
        TradeActionNotNow() ||
        OrderNotParticipant() ||
        OrderRequestRefused(errorCode: null) ||
        ActionSignatureRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// `POST /api/order/?order_id=` with the action `confirm`, as the buyer: tells the coordinator of [lastRead] that the robot [identity] sent the fiat (« Confirm {{amount}} {{currencyCode}} sent »), which moves the order from 9 to 10 (`Logics.confirm_fiat`, `api/logics.py:1686-1735`, commit ff1998c).
  ///
  /// From then on the seller may release the escrow, the buyer can no longer cancel, and a false confirmation risks the bond in a dispute: the buyer alone takes it back only while the seller has not acted ([undoConfirmFiat]).
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:266-269`): `{"action":"confirm"}`.
  ///
  /// Nothing is sent, and the failure is an [OrderActionRefused], when [lastRead] was read by another robot ([OrderReadElsewhere]), does not show this robot as the buyer ([TradeActionNotBuyer]) or is not at 9 ([TradeActionNotNow]), each decided from [lastRead]: read the order again before telling the user.
  /// The answer is [TradeActionAccepted] with the order as it then is, at a status « fiat sent » can lead to (`fiatSentFollows`; any other is an outcome unknown); the coordinator's refusals ([TradeActionNotNow] for 1029, [OrderNotParticipant]) and the authentication's are an [OrderActionRefused], every other failure an [OrderActionOutcomeUnknown]: read the order again, and never send again blindly.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> confirmFiat({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) => _tradeAction(
    identity: identity,
    key: key,
    lastRead: lastRead,
    refusedFromLastRead: switch (lastRead) {
      CoordinatorOrder(isBuyer: != true) => const TradeActionNotBuyer(
        fromLastRead: true,
      ),
      CoordinatorOrder(status: != CoordinatorOrderStatus.sendingFiat) =>
        const TradeActionNotNow(fromLastRead: true),
      _ => null,
    },
    action: 'confirm',
    follows: fiatSentFollows,
  );

  /// `POST /api/order/?order_id=` with the action `confirm`, as the seller: tells the coordinator of [lastRead] that the robot [identity] received the fiat (« Confirm {{amount}} {{currencyCode}} received »), which **settles the escrow and pays the buyer** (`Logics.confirm_fiat`, `api/logics.py:1686-1735`, commit ff1998c): 10 → 13, or 14 at once for an on-chain payout. It cannot be taken back.
  ///
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:261-264`): `{"action":"confirm"}`, the very body of the buyer's « fiat sent »; the coordinator tells them apart by the robot's role.
  ///
  /// Nothing is sent, and the failure is an [OrderActionRefused], when [lastRead] was read by another robot ([OrderReadElsewhere]), does not show this robot as the seller ([TradeActionNotSeller]), or is not at 10 with « fiat sent » recorded ([TradeActionNotNow]), each decided from [lastRead]: read the order again before telling the user.
  /// The answer is [TradeActionAccepted] with the order as it then is, at 13, 14 or 15 (`fiatReceivedFollows`); a `200` at any other status, 10 included, is an outcome unknown (the reference answers `200` at 10 when it could not settle the escrow). The coordinator's refusals, 1027 and 1029 ([TradeActionNotNow]), 1028 ([EscrowBelowPayout]), 1047 ([OrderNotParticipant]) and the authentication's, come before it settles anything and are an [OrderActionRefused]; every other failure is an [OrderActionOutcomeUnknown]: read the order again, and never send again blindly.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> releaseEscrow({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) => _tradeAction(
    identity: identity,
    key: key,
    lastRead: lastRead,
    refusedFromLastRead: switch (lastRead) {
      CoordinatorOrder(isSeller: != true) => const TradeActionNotSeller(
        fromLastRead: true,
      ),
      CoordinatorOrder(status: != CoordinatorOrderStatus.fiatSent) ||
      CoordinatorOrder(
        isFiatSent: != true,
      ) => const TradeActionNotNow(fromLastRead: true),
      _ => null,
    },
    action: 'confirm',
    follows: fiatReceivedFollows,
  );

  /// `POST /api/order/?order_id=` with the action `undo_confirm`, as the buyer: takes back the robot's « fiat sent » (« Payment failed? »), which moves the order from 10 back to 9 (`Logics.undo_confirm_fiat_sent`, `api/logics.py:1737-1756`, commit ff1998c).
  ///
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:271-274`): `{"action":"undo_confirm"}`.
  /// Nothing is sent, as for [confirmFiat], when [lastRead] was read by another robot, does not show this robot as the buyer ([TradeActionNotBuyer]) or is not at 10 ([TradeActionNotNow]); the coordinator refuses with 1030 ([TradeActionNotBuyer]) and 1031 ([TradeActionNotNow]).
  /// The answer and the other failures are as for [confirmFiat].
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> undoConfirmFiat({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) => _tradeAction(
    identity: identity,
    key: key,
    lastRead: lastRead,
    refusedFromLastRead: switch (lastRead) {
      CoordinatorOrder(isBuyer: != true) => const TradeActionNotBuyer(
        fromLastRead: true,
      ),
      CoordinatorOrder(status: != CoordinatorOrderStatus.fiatSent) =>
        const TradeActionNotNow(fromLastRead: true),
      _ => null,
    },
    action: 'undo_confirm',
    follows: fiatSentUndoneFollows,
  );

  /// How long before the end of the chat's time a dispute may be opened: the reference coordinator refuses one earlier than `expires_at` minus 18 hours (`api/logics.py:500-501`, a constant of its code), which is 6 hours into the chat with the default 24 hours (`FIAT_EXCHANGE_DURATION`).
  static const disputeWindow = Duration(hours: 18);

  /// `POST /api/order/?order_id=` with the action `dispute`: opens a dispute of the order of [lastRead] for the robot [identity] (« Open Dispute », `Logics.open_dispute`, `api/logics.py:485-533`, commit ff1998c).
  ///
  /// The coordinator settles the escrow and both bonds to itself at once, and the order moves to 11: the side that loses the dispute loses its bond.
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:256-259`): `{"action":"dispute"}`.
  ///
  /// Nothing is sent when [lastRead] was read by another robot, does not show this robot as a participant ([OrderNotParticipant]), is not at 9 or 10 ([TradeActionNotNow]), or when this client's clock is earlier than [lastRead]'s `expires_at` minus [disputeWindow] ([DisputeTooEarly]), each decided from [lastRead]; the coordinator refuses with 1013 ([TradeActionNotNow]) and 1054 ([DisputeTooEarly]).
  /// The answer and the other failures are as for [confirmFiat].
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> openDispute({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
  }) => _tradeAction(
    identity: identity,
    key: key,
    lastRead: lastRead,
    refusedFromLastRead: switch (lastRead) {
      CoordinatorOrder(isParticipant: false) => const OrderNotParticipant(),
      CoordinatorOrder(
        status: != CoordinatorOrderStatus.sendingFiat &&
            != CoordinatorOrderStatus.fiatSent,
      ) =>
        const TradeActionNotNow(fromLastRead: true),
      _ when _clock().isBefore(lastRead.expiresAt.subtract(disputeWindow)) =>
        const DisputeTooEarly(fromLastRead: true),
      _ => null,
    },
    action: 'dispute',
    follows: disputeFollows,
  );

  /// `POST /api/order/?order_id=` with the action `rate_platform`: the robot [identity] gives its coordinator, the one of [lastRead], [rating] stars (« Rate your trade experience », `Logics.rate_platform`, `api/logics.py:1785-1789`, commit ff1998c).
  ///
  /// The coordinator keeps the latest rating of the robot, whatever the order's status; the reference client offers it once the trade is finished (`TradeBox/Prompts/Successful.tsx`).
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:315-317`): `{"action":"rate_platform","rating":N}`, a number the coordinator's serializer reads as one of its choices « 1 » to « 5 ».
  /// Nothing is sent when [lastRead] was read by another robot or does not show this robot as a participant ([OrderNotParticipant]); the answer and the other failures are as for [confirmFiat].
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<TradeActionOutcome, OrderActionFailure>> ratePlatform({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
    required PlatformRating rating,
  }) => _tradeAction(
    identity: identity,
    key: key,
    lastRead: lastRead,
    refusedFromLastRead: lastRead.isParticipant
        ? null
        : const OrderNotParticipant(),
    action: 'rate_platform',
    fields: {'rating': rating.stars},
  );

  /// `POST /api/review/`, the token with which the robot [identity] rates [coordinator] on Nostr once its last order there is finished (« Rate your host », `Robot.loadReviewToken`, `frontend/src/models/Robot.model.ts:220-245`, commit ff1998c): the body `{"pubkey": <the robot's Nostr key>}` with the robot's short header, as the reference sends it.
  ///
  /// The coordinator answers `200` with the token only when the robot's last order is at 14, 17 or 18 and the key is the one it holds for the robot, which it records when it holds none (`ReviewView`, `api/views.py:1236-1269`); otherwise a `400` (1052), read as [CoordinatorUnexpectedStatus], its text never kept.
  /// A `200` whose `token` is not 128 lowercase hexadecimal characters ([HostReviewToken.parse]) is [CoordinatorResponseMalformed]: the reference's `""` when its signature failed, or anything a coordinator could slip into a public event.
  /// The body carries, last, the signature by [key] of `review:{pubkey}` (RoboSats pull request 2955); a refusal of that signature (1059, 1060, 1061, 1048) is an [ActionSignatureRefused], and the token is not given.
  /// Sent once, never again by this client; the transport never retries a request that is not a `GET`. Whatever the transport throws, an `Error` included, is [CoordinatorTransportFailed].
  Future<Result<HostReviewToken, CoordinatorFailure>> fetchReviewToken({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required String nostrPublicKeyHex,
  }) async {
    final response = await _postAsRobot(
      coordinator,
      network,
      identity: identity,
      key: key,
      path: '/api/review/',
      body: {'pubkey': nostrPublicKeyHex},
      signedText: (_) => reviewActionContent(nostrPublicKeyHex),
      maxResponseBytes: CoordinatorReadBounds.reviewBytes,
    );
    if (response case Ok(
      value: final answer,
    ) when answer.statusCode >= 400 && answer.statusCode <= 499) {
      if (_orderRefusal(answer) case final ActionSignatureRefused refused) {
        return Err(refused);
      }
    }
    return switch (_decodeOk(response)) {
      Err(:final failure) => Err(failure),
      Ok(value: {'token': final Object? token}) =>
        switch (HostReviewToken.parse(token)) {
          final parsed? => Ok(parsed),
          null => const Err(CoordinatorResponseMalformed('token')),
        },
      Ok() => const Err(CoordinatorResponseMalformed('token')),
    };
  }

  /// The checks every action of the trade makes before it is sent, [refusedFromLastRead] included, then the request and the reading of its answer.
  Future<Result<TradeActionOutcome, OrderActionFailure>> _tradeAction({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
    required CoordinatorFailure? refusedFromLastRead,
    required String action,
    Map<String, Object> fields = const {},
    Set<CoordinatorOrderStatus>? follows,
  }) async {
    if (!lastRead.wasReadBy(identity)) {
      return const Err(OrderActionRefused(OrderReadElsewhere()));
    }
    if (refusedFromLastRead != null) {
      return Err(OrderActionRefused(refusedFromLastRead));
    }
    final response = await _postOrderAction(
      lastRead.coordinator,
      lastRead.network,
      identity: identity,
      key: key,
      orderId: lastRead.id,
      action: action,
      fields: fields,
    );
    return switch (response) {
      Err(:final failure) => Err(_afterTradeAction(failure)),
      Ok(value: CoordinatorResponse(statusCode: 200)) => switch (_decode(
        response,
      )) {
        Err(:final failure) => Err(_afterTradeAction(failure)),
        Ok(:final value) => parseTradeActionAnswer(
          value,
          identity: identity,
          lastRead: lastRead,
          follows: follows,
        ).mapErr(_afterTradeAction),
      },
      Ok(value: final answer) => Err(
        _afterTradeAction(_tradeActionRefusal(answer)),
      ),
    };
  }

  /// Why a coordinator answered an action of the trade with a status other than `200`: the codes of `Logics.confirm_fiat` (the buyer's and the seller's), `undo_confirm_fiat_sent` and `open_dispute`, and 1047, then the rule of every action on an order ([_orderRefusal]).
  ///
  /// A code is read on a `4xx` answer only.
  static CoordinatorFailure _tradeActionRefusal(CoordinatorResponse answer) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) return _orderRefusal(answer);
    final code = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(
        object,
      ).optionalInt('error_code', min: 0, max: 99999),
      _ => null,
    };
    return switch (code) {
      1047 => const OrderNotParticipant(),
      1030 => const TradeActionNotBuyer(fromLastRead: false),
      1028 => const EscrowBelowPayout(fromLastRead: false),
      1013 ||
      1027 ||
      1029 ||
      1031 => const TradeActionNotNow(fromLastRead: false),
      1054 => const DisputeTooEarly(fromLastRead: false),
      _ => _orderRefusal(answer),
    };
  }

  /// Whether [failure] of an action of the trade comes before the coordinator changed anything.
  ///
  /// Refused: every [TradeActionRefused] and [OrderNotParticipant] (each answered before `Logics` changes the order, `api/views.py:617-619`, `api/logics.py:497-501`, `:1703-1704`, `:1712-1713`, `:1732-1733`, `:1742-1746`), the empty `400` of the form check, the authentication's refusals, [OrderReadElsewhere], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy].
  /// Everything else is an outcome unknown: a code of another action, a `5xx`, an error of the read that follows the action, a malformed answer, a lost connection.
  static OrderActionFailure _afterTradeAction(CoordinatorFailure failure) =>
      switch (failure) {
        TradeActionRefused() ||
        OrderNotParticipant() ||
        OrderRequestRefused(errorCode: null) ||
        ActionSignatureRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// `POST /api/order/?order_id=` with the action `update_invoice`: gives the coordinator of [lastRead] the Lightning invoice the robot [identity] is to be paid with as buyer.
  ///
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:276-290`, commit ff1998c): `{"action":"update_invoice","invoice":…,"routing_budget_ppm":…}`, the invoice clear-signed by the robot's key ([SignedPayoutInvoice.signedMessage]), which the coordinator verifies with GnuPG and reads back with its own split (`api/utils.py:628-648`).
  /// The invoice must be for [RoutingBudgetPpm.invoiceSats] of the buyer's amount with this [routingBudget]: the coordinator refuses any other amount, and does not check how long the invoice has left before it expires.
  /// What is signed is exactly what was decoded and shown: decode [SignedPayoutInvoice.text] itself, never a string read again.
  ///
  /// Nothing is sent, and the failure is an [OrderActionRefused], when [lastRead] was read by another robot ([OrderReadElsewhere]), when [invoice] was signed by another robot's key ([PayoutSignedByAnotherRobot]) or is for another network ([PayoutInvoiceRefused] with [PayoutInvoiceRefusal.wrongNetwork]), when [lastRead] does not show this robot as the buyer ([PayoutNotBuyer]), or not at a step the coordinator takes an invoice ([PayoutNotNow]): 6 or 8, or 15 once the failed invoice has expired (`api/logics.py:846-863`).
  ///
  /// The answer is [PayoutAccepted] with the order as it then is.
  /// A refusal of the coordinator is an [OrderActionRefused] whose cause is a [PayoutRefused] kind, [OrderNotParticipant] or one of the authentication's: each comes before the coordinator records a payout (`api/views.py:617-634`, `api/logics.py:835-880`); before the node's refusals and 3002 it may still mark the order's unused `OnchainPayment` cancelled (`api/logics.py:866`) or create one (`payout_amount`), which changes nothing the buyer depends on.
  /// A [PayoutRefused] with [PayoutRefused.fromLastRead] was decided here from [lastRead], which may be stale: read the order again and decide from the fresh read before telling the user.
  /// Every other failure is an [OrderActionOutcomeUnknown]: read the order again.
  ///
  /// A signed invoice is not tied to an order or a step: sign it just before submitting, from the fresh read, and never submit one again to another order or step.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<PayoutOutcome, OrderActionFailure>> submitPayoutInvoice({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
    required SignedPayoutInvoice invoice,
    required RoutingBudgetPpm routingBudget,
  }) {
    final status = lastRead.status;
    final mayGiveInvoice =
        status == CoordinatorOrderStatus.waitingForCollateralAndInvoice ||
        status == CoordinatorOrderStatus.waitingForInvoice ||
        (status == CoordinatorOrderStatus.routingFailed &&
            lastRead.payoutInvoiceExpired == true);
    return _submitPayout(
      identity: identity,
      key: key,
      lastRead: lastRead,
      payout: invoice,
      mayGive: mayGiveInvoice,
      wrongNetwork: const PayoutInvoiceRefused(
        PayoutInvoiceRefusal.wrongNetwork,
      ),
      action: 'update_invoice',
      fields: {
        'invoice': invoice.signedMessage,
        'routing_budget_ppm': routingBudget.ppm,
      },
    );
  }

  /// `POST /api/order/?order_id=` with the action `update_address`: gives the coordinator of [lastRead] the on-chain address the robot [identity] is to be paid at as buyer, through the coordinator's swap.
  ///
  /// The body is the reference client's (`frontend/src/components/TradeBox/index.tsx:292-308`, commit ff1998c): `{"action":"update_address","address":…,"mining_fee_rate":…}`, the address clear-signed by the robot's key, the rate a number with at most 3 decimals, always sent.
  /// The address was checked by [BitcoinAddress.check] for the order's network, a pre-check: the coordinator's bitcoind is the judge, and refuses with [PayoutAddressRefused].
  /// What the address receives is [MiningFeeRate.sentSats]; under [MiningFeeRate.minimumSentSats] the coordinator refuses ([PayoutBelowDustLimit]).
  ///
  /// Nothing is sent, and the failure is an [OrderActionRefused], in the cases of [submitPayoutInvoice] (with [PayoutAddressRefusal.wrongNetwork]), at a step other than 6 or 8 (`api/logics.py:760-769`), and when [lastRead] does not offer the swap ([PayoutSwapUnavailable]): the reference coordinator answers that case with a `500`, not a refusal (`api/logics.py:800-803`).
  ///
  /// The answer and the failures are as for [submitPayoutInvoice] (`api/logics.py:752-820`).
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included.
  Future<Result<PayoutOutcome, OrderActionFailure>> submitPayoutAddress({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
    required SignedPayoutAddress address,
    required MiningFeeRate miningFeeRate,
  }) {
    final status = lastRead.status;
    final mayGiveAddress =
        status == CoordinatorOrderStatus.waitingForCollateralAndInvoice ||
        status == CoordinatorOrderStatus.waitingForInvoice;
    return _submitPayout(
      identity: identity,
      key: key,
      lastRead: lastRead,
      payout: address,
      mayGive: mayGiveAddress,
      swap: true,
      wrongNetwork: const PayoutAddressRefused(
        PayoutAddressRefusal.wrongNetwork,
      ),
      action: 'update_address',
      fields: {
        'address': address.signedMessage,
        'mining_fee_rate': miningFeeRate.wire,
      },
    );
  }

  /// The checks every payout makes before it is sent, then the request and the reading of its answer.
  Future<Result<PayoutOutcome, OrderActionFailure>> _submitPayout({
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required CoordinatorOrder lastRead,
    required SignedPayout payout,
    required bool mayGive,
    required PayoutRefused wrongNetwork,
    required String action,
    required Map<String, Object> fields,
    bool swap = false,
  }) async {
    final CoordinatorFailure? before;
    if (!lastRead.wasReadBy(identity)) {
      before = const OrderReadElsewhere();
    } else if (payout.signer != identity.hashId) {
      before = const PayoutSignedByAnotherRobot();
    } else if (payout.network != lastRead.network) {
      before = wrongNetwork;
    } else if (lastRead.isBuyer != true) {
      before = const PayoutNotBuyer(fromLastRead: true);
    } else if (!mayGive) {
      before = const PayoutNotNow(fromLastRead: true);
    } else if (swap && lastRead.swapAllowed != true) {
      before = const PayoutSwapUnavailable();
    } else {
      before = null;
    }
    if (before != null) return Err(OrderActionRefused(before));
    final response = await _postOrderAction(
      lastRead.coordinator,
      lastRead.network,
      identity: identity,
      key: key,
      orderId: lastRead.id,
      action: action,
      fields: fields,
    );
    return switch (response) {
      Err(:final failure) => Err(_afterPayout(failure)),
      Ok(value: CoordinatorResponse(statusCode: 200)) => switch (_decode(
        response,
      )) {
        Err(:final failure) => Err(_afterPayout(failure)),
        Ok(:final value) => parsePayoutAnswer(
          value,
          identity: identity,
          lastRead: lastRead,
        ).mapErr(_afterPayout),
      },
      Ok(value: final answer) => Err(
        _afterPayout(
          _payoutRefusal(answer, invoice: payout is SignedPayoutInvoice),
        ),
      ),
    };
  }

  /// Whether [failure] of a payout comes before the coordinator recorded a payout, so that the order has no new payout.
  ///
  /// Refused: every [PayoutRefused] and [OrderNotParticipant] (each answered before `Logics` records a payout, `api/views.py:617-649`, `api/logics.py:752-880`), the empty `400` of the form check, the authentication's refusals, [OrderReadElsewhere], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy].
  /// Everything else is an outcome unknown, the codes of the other actions included, which the reference never answers to a payout: a `5xx` (an on-chain payout the coordinator does not offer fails with a `500`, `api/logics.py:800-803`), an error of the read that follows the action, a malformed answer, a lost connection.
  static OrderActionFailure _afterPayout(CoordinatorFailure failure) =>
      switch (failure) {
        PayoutRefused() ||
        OrderNotParticipant() ||
        OrderRequestRefused(errorCode: null) ||
        ActionSignatureRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// The texts the reference coordinator sends for an invoice its Lightning node refuses, with no code (`validate_ln_invoice`, `api/lightning/lnd.py:463-533`, the same in `cln.py:504-574`): compared, never kept.
  static const _invoiceTexts = {
    'Does not look like a valid lightning invoice':
        PayoutInvoiceRefusal.notAnInvoice,
    'The invoice hinted private routes are not payable within the submitted routing budget. This can be adjusted with Advanced Options enabled.':
        PayoutInvoiceRefusal.routeHintsUnpayable,
    'The invoice provided has no explicit amount':
        PayoutInvoiceRefusal.noAmount,
    'The invoice provided has already expired': PayoutInvoiceRefusal.expired,
  };

  /// `"The invoice provided is not for " + "{:,}".format(num_satoshis) + " Sats"` (`lnd.py:514-520`): the amount the coordinator expects, kept as a number only ([_expectedSats]).
  static final RegExp _wrongAmountText = RegExp(
    r'^The invoice provided is not for ([0-9]{1,3}(?:,[0-9]{3}){0,5}) Sats$',
  );

  /// All the bitcoin there will ever be, in sats: an expected amount above it is no amount.
  static const _maxSats = 2100000000000000;

  /// The amount of a [_wrongAmountText] message, within 0 to [_maxSats], else `null`.
  static int? _expectedSats(String text) {
    final digits = _wrongAmountText.firstMatch(text)?.group(1);
    final sats = digits == null
        ? null
        : int.tryParse(digits.replaceAll(',', ''));
    return sats != null && sats >= 0 && sats <= _maxSats ? sats : null;
  }

  /// The texts of `validate_onchain_address` (`api/utils.py:106-121`), with no code: compared, never kept.
  static const _addressTexts = {
    'Invalid address': PayoutAddressRefusal.invalid,
    'Unable to validate address, check bitcoind backend':
        PayoutAddressRefusal.unverifiable,
  };

  /// The message of error 4001, the only place where the coordinator gives its minimum rate (`api/errors.py:83`, `api/logics.py:791-793`): an integer, or a Python float.
  static final RegExp _minimumFeeText = RegExp(
    r'^The mining fee is too low\. Must be higher than ([0-9]{1,4}(?:\.[0-9]{1,17})?) Sat/vbyte$',
  );

  /// Why a coordinator answered a payout with a status other than `200`: the codes and texts of the payout of the kind [invoice] says, then the rule of every action on an order ([_orderRefusal]).
  ///
  /// A code is read on a `4xx` answer only; the code of a refusal of the other payout kind is no payout refusal.
  /// With no code, a `400` that holds a `bad_invoice` (invoice) or `bad_address` (address) text is that refusal, of the kind its exact wording gives, `unspecified` for any other text: only the reference's refusals before the payout is recorded write those keys.
  static CoordinatorFailure _payoutRefusal(
    CoordinatorResponse answer, {
    required bool invoice,
  }) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) {
      return CoordinatorUnexpectedStatus(status);
    }
    final fields = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(object),
      _ => null,
    };
    if (fields == null) return _orderRefusal(answer);
    final textKey = invoice ? 'bad_invoice' : 'bad_address';
    final code = fields.optionalInt('error_code', min: 0, max: 99999);
    final CoordinatorFailure? refusal = switch ((code, invoice)) {
      (1047, _) => const OrderNotParticipant(),
      (1048, _) => const PayoutSignatureRefused(),
      (1017, true) ||
      (1015, false) => const PayoutNotBuyer(fromLastRead: false),
      (1018 || 1019 || 3001, true) ||
      (1016, false) => const PayoutNotNow(fromLastRead: false),
      (3000, true) => const PayoutInvoiceRefused(PayoutInvoiceRefusal.empty),
      (3002, true) => const PayoutInvoiceRefused(
        PayoutInvoiceRefusal.alreadySubmitted,
      ),
      (4000, false) => const PayoutAddressRefused(PayoutAddressRefusal.empty),
      (4001, false) => PayoutMiningFeeTooLow(
        _minimumFee(fields.optionalString(textKey, maxLength: 200)),
      ),
      (4002, false) => const PayoutMiningFeeTooHigh(),
      (4003, false) => const PayoutBelowDustLimit(),
      (4004, false) => const PayoutAddressRefused(PayoutAddressRefusal.invalid),
      (4005, false) => const PayoutAddressRefused(
        PayoutAddressRefusal.unverifiable,
      ),
      (null, true) when status == 400 => switch (fields.optionalString(
        textKey,
        maxLength: 500,
      )) {
        final text? => switch (_invoiceTexts[text]) {
          final reason? => PayoutInvoiceRefused(reason),
          null when _wrongAmountText.hasMatch(text) => PayoutInvoiceRefused(
            PayoutInvoiceRefusal.wrongAmount,
            expectedSats: _expectedSats(text),
          ),
          null => const PayoutInvoiceRefused(PayoutInvoiceRefusal.unspecified),
        },
        null => null,
      },
      (null, false) when status == 400 => switch (fields.optionalString(
        textKey,
        maxLength: 500,
      )) {
        final text? => PayoutAddressRefused(
          _addressTexts[text] ?? PayoutAddressRefusal.unspecified,
        ),
        null => null,
      },
      _ => null,
    };
    return refusal ?? _orderRefusal(answer);
  }

  static double? _minimumFee(String? message) {
    final minimum = double.tryParse(
      _minimumFeeText.firstMatch(message ?? '')?.group(1) ?? '',
    );
    return minimum != null && minimum >= 2 && minimum <= 1000 ? minimum : null;
  }

  static bool _isOrderId(int orderId) => orderId >= 1 && orderId <= 1 << 53;

  /// Whether [failure] of a take or a cancel comes before the action, so that nothing was done: see [OrderActionRefused] for the list and why.
  ///
  /// An [OrderNotFound] (1042) received here is an outcome unknown: on a `POST` an unknown order fails with a `500` before any 1042 (`api/views.py:542`), so a 1042 comes from the read that follows the action, the order gone after it ran.
  static OrderActionFailure _afterAction(CoordinatorFailure failure) =>
      switch (failure) {
        RobotHasActiveOrder() ||
        OrderAmountOutOfRange() ||
        OrderTakePenalty() ||
        OrderStatusChanged() ||
        OrderWrongPassword() ||
        OrderRequestRefused(errorCode: null) ||
        ActionSignatureRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// One `POST /api/order/?order_id=` with the JSON body `{"action": [action], …[fields], "signature": …}`, for the robot [identity] only: an action on an order is never sent without the robot's credential and session, nor without its signature of `{action}:{order_id}:{shortAlias}` ([orderActionContent]), which the reference signs for every action of this endpoint.
  Future<Result<CoordinatorResponse, CoordinatorFailure>> _postOrderAction(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required int orderId,
    required String action,
    Map<String, Object> fields = const {},
  }) => _postAsRobot(
    coordinator,
    network,
    identity: identity,
    key: key,
    path: '/api/order/',
    query: {'order_id': '$orderId'},
    body: {'action': action, ...fields},
    signedText: (_) =>
        orderActionContent(action, orderId, coordinator.shortAlias),
  );

  /// One `POST` of a JSON [body] to [path] of [coordinator], for the robot [identity] only, with its short header and its session, and with the signature by [key] of the text [signedText] gives for this client's clock, added as the last field `signature`: an action of a robot is never sent without them.
  ///
  /// The signature is made just before the request is handed to the transport, at the time of this client's clock, the very time a timed text carries; the signed text is never logged nor kept.
  /// Nothing is sent, and the failure is [ActionSignatureRefused] with [ActionSignatureRefusal.notSigned], when [key] is not the key of [identity] or the signature cannot be made.
  /// Sent once: this client never sends it again, and the transport never retries a request that is not a `GET`.
  /// Whatever the transport throws, an `Error` included, becomes [CoordinatorTransportFailed], since the request may have left: a deviation from rule 11 of `AGENTS.md` for this one call, so that a caller always learns that the outcome is unknown.
  Future<Result<CoordinatorResponse, CoordinatorFailure>> _postAsRobot(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required UnlockedRobotPgpKey key,
    required String path,
    Map<String, String>? query,
    required Map<String, Object?> body,
    required String Function(DateTime now) signedText,
    int maxResponseBytes = CoordinatorReadBounds.orderBytes,
  }) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    if (!key.isKeyOf(identity)) {
      return const Err(
        ActionSignatureRefused(ActionSignatureRefusal.notSigned),
      );
    }
    final now = _clock();
    final String signature;
    switch (key.signCleartext(signedText(now), now: now)) {
      case Ok(:final value):
        signature = value;
      case Err():
        return const Err(
          ActionSignatureRefused(ActionSignatureRefusal.notSigned),
        );
    }
    return _send(
      CoordinatorRequest(
        method: CoordinatorHttpMethod.post,
        url: Uri.parse(onion).replace(path: path, queryParameters: query),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': identity.authorizationHeader(),
        },
        body: utf8.encode(jsonEncode({...body, 'signature': signature})),
        maxResponseBytes: maxResponseBytes,
        robot: identity.sessionKey,
      ),
      catchErrors: true,
    );
  }

  /// The decoded JSON of a `200` answer about an order, or why the coordinator refused.
  static Result<Object?, CoordinatorFailure> _orderAnswer(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) => switch (response) {
    Err(:final failure) => Err(failure),
    Ok(value: CoordinatorResponse(statusCode: 200)) => _decode(response),
    Ok(value: final answer) => Err(_orderRefusal(answer)),
  };

  /// The message of error 1012, the only place where the coordinator gives the seconds (`api/errors.py:15`).
  static final RegExp _penaltyMessage = RegExp(
    r'^You need to wait (\d{1,5}) seconds to take an order$',
  );

  /// Why a coordinator answered a request about an order with a status other than `200`.
  ///
  /// Its errors are `{"error_code": …, "bad_request": …}` (`api/errors.py:120-138`): only the code is read, and the seconds of 1012; the message is never kept.
  /// A code is read on a `4xx` answer only, as for the robot's requests ([_robotRefusal]): the reference sends its codes with `400`, `403`, `404` and `409`, and a `5xx` or anything else is the HTTP status alone, whatever its body.
  /// With no code, `401` and `403` are the authentication's refusal, an empty `400` is the form check of the `POST` (`api/views.py:539-540`), and anything else is the HTTP status alone.
  static CoordinatorFailure _orderRefusal(CoordinatorResponse answer) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) {
      return CoordinatorUnexpectedStatus(status);
    }
    final fields = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(object),
      _ => null,
    };
    final code = fields?.optionalInt('error_code', min: 0, max: 99999);
    if (code == null) {
      if (status == 401 || status == 403) {
        return const RobotCredentialsRejected();
      }
      if (status == 400 && answer.body.isEmpty) {
        return const OrderRequestRefused(null);
      }
      return CoordinatorUnexpectedStatus(status);
    }
    return switch (code) {
      1000 => const RobotAlreadyMaker(),
      1001 => const RobotAlreadyTaker(),
      1002 => const RobotAlreadyTaking(),
      1003 => const RobotPayoutPending(),
      1011 => const OrderAmountOutOfRange(),
      1012 => OrderTakePenalty(
        _penaltySeconds(fields?.optionalString('bad_request', maxLength: 100)),
      ),
      1020 => const OrderStatusChanged(),
      1021 => const OrderNotCancellable(),
      1022 => const OrderMakerBondExpired(),
      1023 || 1024 => const CoordinatorNodeUnavailable(),
      1025 => const OrderTakeExpired(),
      1026 => const OrderEscrowExpired(),
      1042 => const OrderNotFound(),
      1043 => const OrderCancelled(),
      1044 => const OrderNotAvailable(),
      1045 => const OrderWrongPassword(),
      1046 => const OrderNotPublic(),
      // The signature of the action (RoboSats pull request 2955, head `0943c97`): checked before anything changes; 1048 is a payout's own refusal in [_payoutRefusal], read before this.
      1048 => const ActionSignatureRefused(ActionSignatureRefusal.invalid),
      1059 => const ActionSignatureRefused(ActionSignatureRefusal.missing),
      1060 => const ActionSignatureRefused(ActionSignatureRefusal.clockSkew),
      1061 => const ActionSignatureRefused(
        ActionSignatureRefusal.otherCoordinator,
      ),
      7001 => const RobotUnknown(),
      7000 || 7003 => const RobotCredentialsRejected(),
      _ => OrderRequestRefused(code),
    };
  }

  static int? _penaltySeconds(String? message) {
    final seconds = int.tryParse(
      _penaltyMessage.firstMatch(message ?? '')?.group(1) ?? '',
    );
    return seconds != null && seconds < 86400 ? seconds : null;
  }

  /// The decoded body of a `200` answer of `GET /api/robot/` for the robot [identity], sent with [authorization], or why there is none.
  Future<Result<Object?, CoordinatorFailure>> _fetchRobot(
    Coordinator coordinator,
    RobosatsNetwork network,
    RobotIdentity identity,
    String authorization, {
    required bool firstContact,
  }) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/robot/',
      const {},
      CoordinatorReadBounds.robotBytes,
      robot: (identity: identity, authorization: authorization),
    );
    final CoordinatorResponse answer;
    switch (response) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        answer = value;
    }
    if (answer.statusCode != 200) {
      return Err(_robotRefusal(answer, firstContact: firstContact));
    }
    return _decode(response);
  }

  /// The code of the key error inside the message of error 7002, which is the text of a Python dictionary: `{'error_code': 1056, …`.
  static final RegExp _nestedErrorCode = RegExp(
    r'''error_code['"]?\s*:\s*(\d{1,6})''',
  );

  /// Why a coordinator answered an authenticated request with a status other than `200`.
  ///
  /// The errors of the authentication middleware are `{"error_code": 7000…7004, "bad_request": …}` (`api/errors.py:90-117`), with HTTP 400, or 409 for 7004.
  /// Only the code is read, and, for 7002, the code of the key error the coordinator writes inside its message: the message itself is never kept.
  /// Anything else is the HTTP status alone.
  static CoordinatorFailure _robotRefusal(
    CoordinatorResponse answer, {
    required bool firstContact,
  }) {
    final status = answer.statusCode;
    final fallback = status == 401 || status == 403
        ? const RobotCredentialsRejected()
        : CoordinatorUnexpectedStatus(status);
    if (status < 400 || status > 499) return fallback;
    final Map<String, Object?> body;
    switch (_decode(Ok(answer))) {
      case Ok(value: final Map<String, Object?> object):
        body = object;
      default:
        return fallback;
    }
    final fields = JsonFields(body);
    final code = fields.optionalInt('error_code', min: 0, max: 99999);
    final message = fields.optionalString(
      'bad_request',
      maxLength: CoordinatorReadBounds.robotBytes,
    );
    return switch (code) {
      7001 when !firstContact => const RobotUnknown(),
      7000 || 7001 || 7003 => const RobotCredentialsRejected(),
      7002 => RobotKeysRefused(switch (int.tryParse(
        _nestedErrorCode.firstMatch(message ?? '')?.group(1) ?? '',
      )) {
        1034 => RobotKeysRefusal.invalidKey,
        1055 => RobotKeysRefusal.keyAlreadyUsed,
        1056 => RobotKeysRefusal.keyTooRecent,
        _ => RobotKeysRefusal.unspecified,
      }),
      7004 => const RobotNicknameTaken(),
      _ => fallback,
    };
  }

  Future<Result<CoordinatorResponse, CoordinatorFailure>> _exchange(
    Coordinator coordinator,
    RobosatsNetwork network,
    String path,
    Map<String, String> query,
    int maxResponseBytes, {
    ({RobotIdentity identity, String authorization})? robot,
    bool keepOversized = false,
  }) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    return _send(
      keepOversized: keepOversized,
      CoordinatorRequest(
        method: CoordinatorHttpMethod.get,
        url: Uri.parse(
          onion,
        ).replace(path: path, queryParameters: query.isEmpty ? null : query),
        // A credential never travels without the name of its robot, which keeps it off the anonymous sessions of the transport.
        headers: {
          'Accept': 'application/json',
          'Authorization': ?robot?.authorization,
        },
        maxResponseBytes: maxResponseBytes,
        robot: robot?.identity.sessionKey,
      ),
    );
  }

  /// Hands [request] to the transport, once.
  ///
  /// With [catchErrors], an `Error` the transport throws is a [CoordinatorTransportFailed] too, instead of propagating.
  /// With [keepOversized], an answer over the request's bound is returned as it is, for the caller to judge by its status; otherwise it is a [CoordinatorResponseTooLarge].
  Future<Result<CoordinatorResponse, CoordinatorFailure>> _send(
    CoordinatorRequest request, {
    bool catchErrors = false,
    bool keepOversized = false,
  }) async {
    final maxResponseBytes = request.maxResponseBytes;
    final Result<CoordinatorResponse, CoordinatorTransportFailure> result;
    try {
      result = await _transport.send(request);
    } on Exception {
      // The adapter should map every failure itself; one it lets through stays confined to this coordinator.
      return const Err(CoordinatorTransportFailed());
    } on Object {
      if (!catchErrors) rethrow;
      return const Err(CoordinatorTransportFailed());
    }
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final response)
          when !keepOversized && response.body.length > maxResponseBytes =>
        const Err(CoordinatorResponseTooLarge()),
      Ok(value: final response) => Ok(response),
    };
  }

  /// The decoded JSON of a `200` answer.
  static Result<Object?, CoordinatorFailure> _decodeOk(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) => switch (response) {
    Ok(value: CoordinatorResponse(statusCode: 200)) => _decode(response),
    Ok(value: CoordinatorResponse(:final statusCode)) => Err(
      CoordinatorUnexpectedStatus(statusCode),
    ),
    Err(:final failure) => Err(failure),
  };

  /// The decoded JSON of an answer whatever its status: a JSON content type, UTF-8 and a body that parses.
  static Result<Object?, CoordinatorFailure> _decode(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) {
    final CoordinatorResponse value;
    switch (response) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final ok):
        value = ok;
    }
    final contentType = value.contentType?.toLowerCase().trim();
    if (contentType == null ||
        !(contentType == 'application/json' ||
            contentType.startsWith('application/json;'))) {
      return const Err(CoordinatorNotJson());
    }
    try {
      return Ok(jsonDecode(utf8.decode(value.body)));
    } on FormatException {
      return const Err(CoordinatorNotJson());
    }
  }

  /// `GET /api/chat/?order_id=&offset=`, the messages of the chat of the order of [lastRead] above [offset], as its coordinator gives them to the robot [identity], with the peer's connection and key.
  ///
  /// The request is the reference client's poll (`frontend/src/components/TradeBox/EncryptedChat/EncryptedApiChat/index.tsx:133-136`, commit ff1998c), with the robot's short header and session; the coordinator answers it for the maker and the taker at 9, 10, 11 and 16 (`chat/views.py:40-113`).
  /// The coordinator, the network and the order come from [lastRead], which must be this robot's read, show it as the maker or the taker with a named peer, and be at one of those statuses: otherwise nothing is sent and the failure is [OrderReadElsewhere] or a [ChatRefused] with [ChatRefused.fromLastRead] ([ChatRefusal.notParticipant], [ChatRefusal.notInChat]: read the order again before telling the user); an [offset] outside 0 to [ChatPage.maxIndex] is [ChatRefusal.offsetOutOfRange].
  /// See [ChatPage] for what is read, what refuses the page and what is only stated; the peer's key is the coordinator's word: pin it for the trade.
  /// The coordinator's refusals are [ChatRefused] kinds (6000 to 6002) and the authentication's ([RobotUnknown], [RobotCredentialsRejected]), never its text; an unknown order is a `500` at the reference (`chat/views.py:51`), read as [CoordinatorUnexpectedStatus].
  /// A `200` page over [CoordinatorReadBounds.chatBytes] is [ChatPageTooLarge], which a peer can cause by posting enough (see there for what the caller can do); an error answer over it is a [CoordinatorResponseTooLarge].
  /// A `GET`, so the transport may send it again after a connection failure.
  /// Poll it through the app's robot request limiter, as every request of a robot.
  Future<Result<ChatPage, CoordinatorFailure>> fetchChat({
    required RobotIdentity identity,
    required CoordinatorOrder lastRead,
    required int offset,
  }) async {
    if (_chatRefusalBefore(
          identity,
          lastRead,
          offset,
          statuses: _chatReadStatuses,
        )
        case final refusal?) {
      return Err(refusal);
    }
    final response = await _exchange(
      lastRead.coordinator,
      lastRead.network,
      '/api/chat/',
      {'order_id': '${lastRead.id}', 'offset': '$offset'},
      CoordinatorReadBounds.chatBytes,
      robot: (
        identity: identity,
        authorization: identity.authorizationHeader(),
      ),
      keepOversized: true,
    );
    return switch (_chatAnswer(_chatPageBounded(response, offset))) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => ChatPage.parse(
        value,
        identity: identity,
        lastRead: lastRead,
        offset: offset,
      ),
    };
  }

  /// `POST /api/chat/` with `{"PGP_message":…,"order_id":…,"offset":…}`: posts [message] to the chat of the order of [lastRead] as the robot [identity], and reads the messages above [offset] that the coordinator answers with.
  ///
  /// The body is the reference client's (`frontend/src/components/TradeBox/EncryptedChat/index.tsx:259-267`, commit ff1998c), `PGP_message` being [OutgoingChatMessage.wire], with the robot's short header and session.
  /// [offset] is always sent, so the answer is a [ChatPage] (`chat/views.py:194-214`): pass the last index read, and [ChatPage.indexOf] gives the index the coordinator gave the message when the page holds it.
  /// Nothing is sent, and the failure is an [OrderActionRefused], when [lastRead] was read by another robot ([OrderReadElsewhere]), when [message] was encrypted by another robot's key ([ChatRefusal.messageOfAnotherRobot]), when [lastRead] does not show this robot as the maker or the taker with a named peer ([ChatRefusal.notParticipant]) or is not at 9 or 10, the statuses where the coordinator stores a message ([ChatRefusal.notInChat], `chat/views.py:136-137`), both with [ChatRefused.fromLastRead] (read the order again before telling the user), or when [offset] is outside 0 to [ChatPage.maxIndex].
  ///
  /// A refusal of the coordinator is an [OrderActionRefused] whose cause is a [ChatRefused] kind (6000 to 6003) or one of the authentication's: the reference answers each before it stores the message (`chat/views.py:121-137`), so it is the coordinator's word that nothing was stored.
  /// Every other failure is an [OrderActionOutcomeUnknown]: the message may have been stored, since the reference stores it before it notifies and answers, and a `500` after storing is possible (`chat/views.py:158-192`, `:206`).
  /// The caller then reads the chat again from the offset it posted with and looks for the message with [ChatPage.indexOf]: found, the coordinator shows it as stored; not found, it is not confirmed, never « not sent » nor « failed », since a hostile coordinator can keep it out of this robot's pages and still deliver it to the peer.
  /// If the user sends it again, send this same value, so that a reader can tell the duplicate by its text ([ChatPage.repeatsACiphertext]).
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included; the transport never retries a request that is not a `GET`.
  ///
  /// [onSending] is called when the transport starts writing the post on a connection to the coordinator ([CoordinatorRequest.onSending]), never when nothing is written: a refusal above, a transport without a place or a session for it, a connection that fails first.
  Future<Result<ChatPage, OrderActionFailure>> postChat({
    required RobotIdentity identity,
    required CoordinatorOrder lastRead,
    required OutgoingChatMessage message,
    required int offset,
    void Function()? onSending,
  }) async {
    final before =
        _chatRefusalBefore(
          identity,
          lastRead,
          offset,
          statuses: _chatPostStatuses,
        ) ??
        (message.sender != identity.hashId
            ? const ChatRefused(ChatRefusal.messageOfAnotherRobot)
            : null);
    if (before != null) return Err(OrderActionRefused(before));
    final onion = lastRead.coordinator.origins(lastRead.network).onion;
    if (onion == null) {
      return const Err(OrderActionRefused(CoordinatorNotOnNetwork()));
    }
    final response = await _send(
      CoordinatorRequest(
        method: CoordinatorHttpMethod.post,
        url: Uri.parse(onion).replace(path: '/api/chat/'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': identity.authorizationHeader(),
        },
        body: utf8.encode(
          jsonEncode({
            'PGP_message': message.wire,
            'order_id': lastRead.id,
            'offset': offset,
          }),
        ),
        maxResponseBytes: CoordinatorReadBounds.chatBytes,
        robot: identity.sessionKey,
        onSending: onSending,
      ),
      catchErrors: true,
      keepOversized: true,
    );
    return switch (_chatAnswer(_chatPageBounded(response, offset))) {
      Err(:final failure) => Err(_afterChatPost(failure)),
      Ok(:final value) => ChatPage.parse(
        value,
        identity: identity,
        lastRead: lastRead,
        offset: offset,
      ).mapErr(_afterChatPost),
    };
  }

  /// The statuses at which the coordinator answers a read of the chat (`chat/views.py:56-62`) and stores a post (`:136-137`).
  static const _chatReadStatuses = {
    CoordinatorOrderStatus.sendingFiat,
    CoordinatorOrderStatus.fiatSent,
    CoordinatorOrderStatus.inDispute,
    CoordinatorOrderStatus.waitingForDisputeResolution,
  };
  static const _chatPostStatuses = {
    CoordinatorOrderStatus.sendingFiat,
    CoordinatorOrderStatus.fiatSent,
  };

  /// Why a request about the chat of the order of [lastRead] must not be sent by the robot [identity], or `null`.
  static CoordinatorFailure? _chatRefusalBefore(
    RobotIdentity identity,
    CoordinatorOrder lastRead,
    int offset, {
    required Set<CoordinatorOrderStatus> statuses,
  }) {
    if (!lastRead.wasReadBy(identity)) return const OrderReadElsewhere();
    final peer = lastRead.isMaker ? lastRead.taker : lastRead.maker;
    if (!(lastRead.isMaker || lastRead.isTaker) || peer == null) {
      return const ChatRefused(ChatRefusal.notParticipant, fromLastRead: true);
    }
    if (!statuses.contains(lastRead.status)) {
      return const ChatRefused(ChatRefusal.notInChat, fromLastRead: true);
    }
    if (offset < 0 || offset > ChatPage.maxIndex) {
      return const ChatRefused(ChatRefusal.offsetOutOfRange);
    }
    return null;
  }

  /// Whether [failure] of a post comes before the message was stored, so that nothing was done.
  ///
  /// Refused: every [ChatRefused] (6000 to 6003, each answered before the message is stored, `chat/views.py:121-137`, and the checks of this package), the authentication's refusals, [OrderReadElsewhere], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy].
  /// Everything else is an outcome unknown: a `5xx` (the reference can fail after storing, `chat/views.py:169-192`), a code the reference does not send to a post, a malformed answer to a post that was stored, a lost connection.
  static OrderActionFailure _afterChatPost(CoordinatorFailure failure) =>
      switch (failure) {
        ChatRefused() ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// [response] judged against [CoordinatorReadBounds.chatBytes]: a `200` over the bound is a [ChatPageTooLarge] for [offset], any other answer over it a [CoordinatorResponseTooLarge], as for every other request.
  ///
  /// The transport's own [CoordinatorResponseTooLarge], for an answer it stopped reading at the bound, does not say the status: it is taken as a [ChatPageTooLarge], since a peer can make a page that large and an honest coordinator's errors are a few dozen bytes; a coordinator that sends an error that large is not honest, and the caller's answer to either is the same, the chat cannot be read from [offset].
  static Result<CoordinatorResponse, CoordinatorFailure> _chatPageBounded(
    Result<CoordinatorResponse, CoordinatorFailure> response,
    int offset,
  ) => switch (response) {
    Err(failure: CoordinatorResponseTooLarge()) => Err(
      ChatPageTooLarge(offset),
    ),
    Ok(value: final answer)
        when answer.body.length > CoordinatorReadBounds.chatBytes =>
      Err(
        answer.statusCode == 200
            ? ChatPageTooLarge(offset)
            : const CoordinatorResponseTooLarge(),
      ),
    _ => response,
  };

  /// The decoded JSON of a `200` answer about a chat, or why the coordinator refused.
  static Result<Object?, CoordinatorFailure> _chatAnswer(
    Result<CoordinatorResponse, CoordinatorFailure> response,
  ) => switch (response) {
    Err(:final failure) => Err(failure),
    Ok(value: CoordinatorResponse(statusCode: 200)) => _decode(response),
    Ok(value: final answer) => Err(_chatRefusal(answer)),
  };

  /// Why a coordinator answered a request about a chat with a status other than `200`.
  ///
  /// Its errors are `{"error_code": …, "bad_request": …}` (`api/errors.py:85-89`, `:99-117`): only the code is read, on a `4xx` answer only, as for an order; the message is never kept.
  /// With no code, `401` and `403` are the authentication's refusal, and anything else is the HTTP status alone.
  static CoordinatorFailure _chatRefusal(CoordinatorResponse answer) {
    final status = answer.statusCode;
    if (status < 400 || status > 499) {
      return CoordinatorUnexpectedStatus(status);
    }
    final code = switch (_decode(Ok(answer))) {
      Ok(value: final Map<String, Object?> object) => JsonFields(
        object,
      ).optionalInt('error_code', min: 0, max: 99999),
      _ => null,
    };
    return switch (code) {
      null when status == 401 || status == 403 =>
        const RobotCredentialsRejected(),
      null => CoordinatorUnexpectedStatus(status),
      6000 => const ChatRefused(ChatRefusal.orderIdMissing),
      6001 => const ChatRefused(ChatRefusal.notParticipant),
      6002 => const ChatRefused(ChatRefusal.notInChat),
      6003 => const ChatRefused(ChatRefusal.invalidRequest),
      7001 => const RobotUnknown(),
      7000 || 7003 => const RobotCredentialsRejected(),
      _ => OrderRequestRefused(code),
    };
  }
}
