import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// What the fake coordinators do with one robot request.
enum RobotReply {
  /// As the reference coordinator: a first contact creates the robot with its pair and its Nostr key unless it knows it, every request is answered with what it kept, and a short header for an unknown robot is error 7001.
  keep,

  /// The transport had no place for the request: nothing reaches the coordinator.
  busy,

  /// The coordinator could not be reached.
  unreachable,

  /// Error 7004: the nickname is taken.
  nicknameTaken,

  /// Error 7001, whatever the header: the robot is unknown.
  unknown,

  /// Error 7002 with the key error 1056: the key is too recent for the coordinator's clock.
  keyTooRecent,

  /// Error 7002 with no key error this client knows.
  keysRefused,

  /// A page that is not JSON.
  notJson,

  /// The robot of another hash id.
  otherRobot,
}

/// Coordinators behind one fake transport, which answer the robot requests of the robots the test names: each request gets the next reply of [script], or [RobotReply.keep] once it is empty.
///
/// Tests only: every robot, pair and token is made from fixed test bytes.
final class FakeRobotCoordinators implements CoordinatorTransport {
  final Map<RobotSessionKey, RobotIdentity> _robots;

  /// Every request received, in order.
  final List<CoordinatorRequest> requests = [];

  /// The replies to the next requests, in order.
  final List<RobotReply> script = [];

  /// What each coordinator, by onion host, keeps of each robot: its two key blocks, its Nostr key and any other field.
  final Map<(String, RobotSessionKey), Map<String, Object?>> kept = {};

  /// Fields every answer about a robot carries, by robot: order ids, rewards, a Nostr key.
  final Map<RobotSessionKey, Map<String, Object?>> fields = {};

  /// When set, every request waits for it before it is answered.
  Completer<void>? hold;

  /// Runs as each request arrives, before it is answered.
  void Function(CoordinatorRequest request)? onSend;

  FakeRobotCoordinators(Iterable<RobotIdentity> robots)
    : _robots = {for (final robot in robots) robot.sessionKey: robot};

  /// The requests that were first contacts: they carry a key pair.
  List<CoordinatorRequest> get firstContacts => [
    for (final request in requests)
      if (_parts(request).length == 4) request,
  ];

  /// The onion host of [alias] on [network].
  static String hostOf(String alias, RobosatsNetwork network) => Uri.parse(
    Federation.robosats.byAlias(alias)?.origins(network).onion ?? '',
  ).host;

  /// [robot] as [alias] on [network] keeps it with [pair], as after a first contact made elsewhere.
  void keepFor(
    RobotIdentity robot,
    String alias,
    RobosatsNetwork network,
    RobotPgpKey pair,
  ) => kept[(hostOf(alias, network), robot.sessionKey)] = {
    'public_key': pair.publicKey.armored,
    'encrypted_private_key': pair.encryptedPrivateKeyArmored,
    'nostr_pubkey': robot.nostrKeyPair().publicKeyHex,
  };

  static List<String> _parts(CoordinatorRequest request) =>
      (request.headers['Authorization'] ?? '').split(' | ');

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    onSend?.call(request);
    if (hold case final hold?) await hold.future;
    final reply = script.isEmpty ? RobotReply.keep : script.removeAt(0);
    final key = request.robot;
    final identity = key == null ? null : _robots[key];
    if (key == null || identity == null) {
      throw StateError('a request for no robot of the test');
    }
    final place = (request.url.host, key);
    final parts = _parts(request);
    switch (reply) {
      case RobotReply.busy:
        return const Err(CoordinatorTransportBusy());
      case RobotReply.unreachable:
        return const Err(CoordinatorUnreachable());
      case RobotReply.nicknameTaken:
        return Ok(_json(409, {'error_code': 7004, 'bad_request': 'taken'}));
      case RobotReply.unknown:
        return Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
      case RobotReply.keyTooRecent:
        return Ok(
          _json(400, {
            'error_code': 7002,
            'bad_request': "{'error_code': 1056}",
          }),
        );
      case RobotReply.keysRefused:
        return Ok(_json(400, {'error_code': 7002, 'bad_request': 'no'}));
      case RobotReply.notJson:
        return Ok(
          CoordinatorResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/html'},
            body: utf8.encode('<html></html>'),
          ),
        );
      case RobotReply.otherRobot:
      case RobotReply.keep:
        if (parts.length == 4) {
          kept.putIfAbsent(
            place,
            () => {
              'public_key': pgpArmorFromWire(
                parts[1].substring('Public '.length),
              ),
              'encrypted_private_key': pgpArmorFromWire(
                parts[2].substring('Private '.length),
              ),
              'nostr_pubkey': parts[3].substring('Nostr '.length),
            },
          );
        }
        final robot = kept[place];
        if (robot == null) {
          return Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
        }
        // Another robot of the test, as a coordinator that mixed up its robots would answer.
        final shown = reply == RobotReply.otherRobot
            ? _robots.values.firstWhere((robot) => robot.sessionKey != key)
            : identity;
        return Ok(
          _json(200, {
            'nickname': shown.nickname,
            'hash_id': shown.hashId.hex,
            ...robot,
            ...?fields[key],
          }),
        );
    }
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

/// The key work of the robots on the test's own isolate: each robot gets the pair the test made for it, and the proofs are the package's.
final class PairsByRobot implements RobotKeyComputePort {
  final Map<RobotHashId, RobotPgpKey> _pairs;
  final List<RobotHashId> generated = [];
  final List<RobotHashId> proved = [];

  /// What every pair asked for gives instead, when it is set.
  RobotKeyComputeFailure? generateFailure;

  PairsByRobot(this._pairs);

  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async {
    generated.add(identity.hashId);
    if (generateFailure case final failure?) return Err(failure);
    final pair = _pairs[identity.hashId];
    if (pair == null) throw StateError('no pair made for this robot');
    return Ok(pair);
  }

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) async {
    proved.add(robot.hashId);
    return Ok(robot.prove());
  }
}

/// The Tor sessions of the robots, whose closes are kept.
final class RecordingSessions implements CoordinatorSessionsPort {
  final List<RobotSessionKey> closed = [];

  @override
  Future<void> closeSessions() async {}

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async =>
      closed.add(robot);
}

/// The pair of [robot], locked by its token: one S2K of 32 MiB, so a test makes each once.
RobotPgpKey pairOf(RobotIdentity robot) =>
    switch (RobotPgpKey.generate(robot)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
