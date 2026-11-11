import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_info.dart';
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

/// Reads the public endpoints of one coordinator at a time, and the robot of this device on it, through a [CoordinatorTransport].
///
/// Every method returns a [CoordinatorFailure] instead of throwing, whatever the coordinator sends and even if the transport breaks its contract by throwing an [Exception].
/// Only exceptions are caught: an `Error` thrown by the transport is a programming error and propagates, as rule 11 of `AGENTS.md` requires.
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
  /// Nothing in a `200` answer tells the two cases apart but [CoordinatorRobot.found], so the answer is always checked against this device: see [CoordinatorRobot.parse].
  /// A robot first created by another device, with another key pair, is therefore a [RobotPgpKeyMismatch], never a silent change of key.
  /// Fails with a [CoordinatorRobotFailure] when the coordinator refuses the robot or returns another one, and with any other [CoordinatorFailure] as the public reads do.
  /// A [RobotNicknameTaken] is only reported once a second request, with the short header, has shown that the coordinator does not know this robot.
  ///
  /// [nostrKeyDerivation] chooses the Nostr public key sent: keep the default, the other formula gives a key whose secret the coordinator can compute.
  /// The coordinator keeps the key of the first contact for good.
  ///
  /// A robot costs nothing and commits to nothing, but it is an account on a third-party server: create one only when the user asks for it.
  Future<Result<CoordinatorRobot, CoordinatorFailure>> fetchRobot(
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
      pgpKey,
      identity.firstContactAuthorizationHeader(
        pgpPublicKey: pgpKey.publicKey.armored,
        pgpEncryptedPrivateKey: pgpKey.encryptedPrivateKeyArmored,
        nostrKeyDerivation: nostrKeyDerivation,
      ),
      firstContact: true,
    );
    if (contact case Err(failure: RobotNicknameTaken())) {
      // The nickname may be taken by this very robot: a coordinator that receives the first contact twice at once, as when the transport retries a request whose connection broke after it was sent, creates the robot for one and refuses the other.
      // The short header tells: it reads the robot if the coordinator knows this token, and creates nothing.
      final known = await fetchKnownRobot(
        coordinator,
        network,
        identity: identity,
        pgpKey: pgpKey,
      );
      if (known case Ok()) return known;
    }
    return contact;
  }

  /// `GET /api/robot/` with the short `Authorization` header, which sends no key: reads the robot [identity] on a [coordinator] that already knows it, and never creates it.
  ///
  /// Fails with [RobotUnknown] when the coordinator has no robot for this token.
  /// The answer is checked against this device exactly as [fetchRobot] checks it, [pgpKey] being the key pair this device holds for the robot.
  Future<Result<CoordinatorRobot, CoordinatorFailure>> fetchKnownRobot(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required RobotPgpKey pgpKey,
  }) => _fetchRobot(
    coordinator,
    network,
    identity,
    pgpKey,
    identity.authorizationHeader(),
    firstContact: false,
  );

  Future<Result<CoordinatorRobot, CoordinatorFailure>> _fetchRobot(
    Coordinator coordinator,
    RobosatsNetwork network,
    RobotIdentity identity,
    RobotPgpKey pgpKey,
    String authorization, {
    required bool firstContact,
  }) async {
    final response = await _exchange(
      coordinator,
      network,
      '/api/robot/',
      const {},
      CoordinatorReadBounds.robotBytes,
      authorization: authorization,
      identity: identity,
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
    return switch (_decode(response)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => CoordinatorRobot.parse(
        value,
        coordinator,
        identity: identity,
        pgpKey: pgpKey,
      ),
    };
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
    String? authorization,
    RobotIdentity? identity,
  }) async {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return const Err(CoordinatorNotOnNetwork());
    final request = CoordinatorRequest(
      method: CoordinatorHttpMethod.get,
      url: Uri.parse(
        onion,
      ).replace(path: path, queryParameters: query.isEmpty ? null : query),
      headers: {'Accept': 'application/json', 'Authorization': ?authorization},
      maxResponseBytes: maxResponseBytes,
      robot: identity?.sessionKey,
    );
    final Result<CoordinatorResponse, CoordinatorTransportFailure> result;
    try {
      result = await _transport.send(request);
    } on Exception {
      // The adapter should map every failure itself; one it lets through stays confined to this coordinator.
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
