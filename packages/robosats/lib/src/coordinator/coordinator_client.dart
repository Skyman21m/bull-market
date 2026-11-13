import 'dart:convert';

import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart' show sha256;
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_info.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/coordinator/coordinator_robot.dart';
import 'package:robosats/src/coordinator/coordinator_transport.dart';
import 'package:robosats/src/coordinator/currency_limits.dart';
import 'package:robosats/src/coordinator/dropped_order_reason.dart';
import 'package:robosats/src/coordinator/order_book.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_identity.dart';
import 'package:robosats/src/robot_pgp_key.dart';

/// Reads the public endpoints of one coordinator at a time, and the robot of this device on it, through a [CoordinatorTransport], and sends that robot's take and cancel of an order.
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

  /// `POST /api/order/?order_id=` with the action `take`: asks [coordinator] for the order [orderId] for the robot [identity], which then has a while to lock its bond.
  ///
  /// The body is the reference client's (`frontend/src/models/Order.model.ts:233-243`, commit ff1998c): `{"action":"take","amount":…}`, with `"password"` before `"amount"` when there is one.
  /// [amount] is the amount chosen in a range order, in the order's currency, which for an order in bitcoin (currency 1000) is bitcoin, not sats; for a fixed order leave it `null`, and `0` is sent, as the reference client sends it and the coordinator ignores it.
  /// The coordinator refuses more than 8 decimals with an empty `400`, read as [OrderRequestRefused].
  /// [password] is the text the user typed for a protected order: the SHA-256 of its UTF-8 bytes is sent, in lowercase hexadecimal, as the reference client sends it; an empty one is not sent.
  ///
  /// A `200` answer is the order as the coordinator then describes it, read as a [TakeOrderOutcome]: [OrderTakeStarted] only when it shows this robot as the pre-taker with its bond, [OrderAlreadyTakenByThisRobot] when this robot was already the taker, [OrderNotTaken] otherwise (the reference coordinator answers a take on an order that is no longer public with the order as it is, and no error, `api/views.py:595-596`).
  /// A failure is an [OrderActionRefused] when nothing was done, and an [OrderActionOutcomeUnknown] when the take may have happened.
  ///
  /// Sent once and never again by this client, whatever the outcome, a timeout included: the next [fetchOrder] tells what happened.
  Future<Result<TakeOrderOutcome, OrderActionFailure>> takeOrder(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required int orderId,
    FiatAmount? amount,
    String? password,
  }) async {
    if (!_isOrderId(orderId)) {
      return const Err(OrderActionRefused(OrderNotFound()));
    }
    final response = await _postOrderAction(
      coordinator,
      network,
      identity: identity,
      orderId: orderId,
      body: {
        'action': 'take',
        if (password != null && password.isNotEmpty)
          'password': hex.encode(sha256.convert(utf8.encode(password)).bytes),
        'amount': amount == null ? 0 : _jsonNumber(amount.value),
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
      orderId: orderId,
      body: {
        'action': 'cancel',
        'cancel_status': storedStatusOf(lastRead).wire,
      },
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

  static bool _isOrderId(int orderId) => orderId >= 1 && orderId <= 1 << 53;

  /// Whether [failure] of a take or a cancel comes before the action, so that nothing was done: see [OrderActionRefused] for the list and why.
  static OrderActionFailure _afterAction(CoordinatorFailure failure) =>
      switch (failure) {
        RobotHasActiveOrder() ||
        OrderAmountOutOfRange() ||
        OrderTakePenalty() ||
        OrderStatusChanged() ||
        OrderNotFound() ||
        OrderWrongPassword() ||
        OrderRequestRefused(errorCode: null) ||
        RobotCredentialsRejected() ||
        RobotUnknown() ||
        OrderReadElsewhere() ||
        CoordinatorNotOnNetwork() ||
        CoordinatorTransportBusy() => OrderActionRefused(failure),
        _ => OrderActionOutcomeUnknown(failure),
      };

  /// [value] as JavaScript writes a number: an integral value without a fractional part, as the reference client sends `Number(...)`.
  static num _jsonNumber(double value) =>
      value == value.truncateToDouble() && value.abs() < 1e15
      ? value.toInt()
      : value;

  /// One `POST /api/order/?order_id=` with a JSON [body], for the robot [identity] only: an action on an order is never sent without the robot's credential and session.
  ///
  /// Sent once: this client never sends it again, and the transport never retries a request that is not a `GET`.
  /// Whatever the transport throws, an `Error` included, becomes [CoordinatorTransportFailed], since the request may have left: a deviation from rule 11 of `AGENTS.md` for this one call, so that a caller always learns that the outcome is unknown.
  Future<Result<CoordinatorResponse, CoordinatorFailure>> _postOrderAction(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required int orderId,
    required Map<String, Object> body,
  }) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    return _send(
      CoordinatorRequest(
        method: CoordinatorHttpMethod.post,
        url: Uri.parse(onion).replace(
          path: '/api/order/',
          queryParameters: {'order_id': '$orderId'},
        ),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': identity.authorizationHeader(),
        },
        body: utf8.encode(jsonEncode(body)),
        maxResponseBytes: CoordinatorReadBounds.orderBytes,
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

  /// The message of error 1012, the only place where the coordinator gives the seconds (`api/errors.py:13`).
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
      1023 || 1024 => const CoordinatorNodeUnavailable(),
      1025 => const OrderTakeExpired(),
      1026 => const OrderEscrowExpired(),
      1042 => const OrderNotFound(),
      1043 => const OrderCancelled(),
      1044 => const OrderNotAvailable(),
      1045 => const OrderWrongPassword(),
      1046 => const OrderNotPublic(),
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
  }) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    return _send(
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
  Future<Result<CoordinatorResponse, CoordinatorFailure>> _send(
    CoordinatorRequest request, {
    bool catchErrors = false,
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
      Ok(value: final response) when response.body.length > maxResponseBytes =>
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
}
