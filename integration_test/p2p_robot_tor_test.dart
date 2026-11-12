import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/init.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';

// Robots are only ever created on the test network: a robot is an account on a third-party server, and this test makes throwaway ones.
const _network = RobosatsNetwork.testnet;

// A request is bounded by 132 seconds in the transport; a step that fails for a transport reason is tried this many times in all.
const _attempts = 3;

// A coordinator answers `found` once a robot is more than five minutes old (`api/views.py:738-741`): the last read waits for that, with a margin for its clock.
const _foundAfter = Duration(minutes: 5, seconds: 20);

/// Prints one measurement as a single greppable line: `P2P_ROBOT_MEASURE {json}`.
///
/// Only labels of this app, numbers and booleans: never a token, a key, a header, a nickname or text sent by a coordinator, not even a field name or a content type it chose.
void _measure(Map<String, Object?> values) {
  debugPrint('P2P_ROBOT_MEASURE ${jsonEncode(values)}');
}

/// A fixed label for a failure, with the number or field name the package gives, never coordinator text.
Map<String, Object?> _failure(CoordinatorFailure failure) => {
  'failure': failure.runtimeType.toString(),
  if (failure case CoordinatorUnexpectedStatus(:final statusCode))
    'status': statusCode,
  if (failure case CoordinatorResponseMalformed(:final field)) 'field': field,
  if (failure case RobotKeysRefused(:final reason)) 'reason': reason.name,
};

/// What a robot answer says, without anything that identifies the robot.
Map<String, Object?> _robotFields(CoordinatorRobot robot) => {
  'pgpKeyProven': robot.pgpKeyProven,
  'found': robot.found,
  'earnedRewards': robot.earnedRewards.value.toInt(),
  'wantsStealth': robot.wantsStealth,
  'hasActiveOrder': robot.activeOrderId != null,
  'hasLastOrder': robot.lastOrderId != null,
  'hasLastLogin': robot.lastLogin != null,
  'nostrKeyHeld': robot.nostrPublicKeyHex != null,
  'nostrKeyDerivation': robot.nostrKeyDerivation?.name,
};

/// The fields a coordinator of the reference source answers on `/api/robot/` (`api/views.py:703-741`): only these names are ever printed.
const _knownFields = {
  'nickname',
  'hash_id',
  'public_key',
  'encrypted_private_key',
  'earned_rewards',
  'wants_stealth',
  'nostr_pubkey',
  'webhook_url',
  'webhook_enabled',
  'webhook_api_key',
  'last_login',
  'tg_enabled',
  'tg_token',
  'tg_bot_name',
  'active_order_id',
  'last_order_id',
  'found',
};

final RegExp _isoUtcMicroseconds = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
);

/// The form of the `last_login` of an answer, as one of four fixed labels: never the text itself.
String _lastLoginForm(Object? value) => switch (value) {
  null => 'absent',
  final String text when _isoUtcMicroseconds.hasMatch(text) =>
    'iso-utc-microseconds',
  String() => 'other-text',
  _ => 'not-text',
};

/// The shape of a JSON value, never the value: its type, and the length of a text.
String _shape(Object? value) => switch (value) {
  null => 'null',
  bool() => 'bool',
  int() => 'int',
  double() => 'double',
  final String text => 'string(${text.length})',
  final List<Object?> list => 'list(${list.length})',
  Map<String, Object?>() => 'object',
  _ => 'other',
};

/// Whether a step gave up on the transport: the coordinator is left for the next one, as an outage on its side.
bool _gaveUp<T>(Result<T, CoordinatorFailure> result) => switch (result) {
  Err(failure: CoordinatorTransportFailure()) => true,
  _ => false,
};

/// The robot of an answer: as it is when it carries the pair the request has just sent, and otherwise once the robot's token has proved the pair the coordinator returned, as `FetchRobotUsecase` of the app does away from the UI isolate.
Result<CoordinatorRobot, CoordinatorFailure> _settled(
  Result<CoordinatorRobotAnswer, CoordinatorFailure> answer,
) => switch (answer) {
  Err(:final failure) => Err(failure),
  Ok(value: final CoordinatorRobot robot) => Ok(robot),
  Ok(value: final UnprovenCoordinatorRobot unproven) =>
    unproven.prove().mapErr<CoordinatorFailure>((failure) => failure),
};

/// Runs [step] until it gives anything but a transport failure, [_attempts] times at most, and measures each try.
Future<Result<T, CoordinatorFailure>> _try<T>(
  String alias,
  String label,
  Stopwatch watch,
  Future<Result<T, CoordinatorFailure>> Function() step, {
  Map<String, Object?> Function(T value)? fields,
}) async {
  late Result<T, CoordinatorFailure> result;
  for (var attempt = 1; attempt <= _attempts; attempt++) {
    final start = watch.elapsedMilliseconds;
    result = await step();
    _measure({
      'step': label,
      'alias': alias,
      'attempt': attempt,
      'ms': watch.elapsedMilliseconds - start,
      ...switch (result) {
        Ok(:final value) => {'outcome': 'ok', ...?fields?.call(value)},
        Err(:final failure) => {'outcome': 'failed', ..._failure(failure)},
      },
    });
    if (result case Err(failure: CoordinatorTransportFailure())) continue;
    break;
  }
  return result;
}

Future<void> main({bool isInitialized = false}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  // Opt-in only, as in p2p_book_tor_test.dart: this test calls live RoboSats coordinators over Tor and creates robots on them.
  final runLiveRobosatsTest =
      Platform.environment['RUN_LIVE_ROBOSATS_TEST'] == 'true' ||
      const bool.fromEnvironment('RUN_LIVE_ROBOSATS_TEST');

  group(
    'P2P robot on a testnet coordinator over embedded Tor',
    skip: runLiveRobosatsTest
        ? false
        : 'creates robots on live RoboSats testnet coordinators: set RUN_LIVE_ROBOSATS_TEST=true',
    () {
      test(
        'creates a robot, reads it back with nothing in memory, and settles the Nostr key question',
        timeout: const Timeout(Duration(minutes: 45)),
        () async {
          final facade = locator<P2pFacade>();
          final transport = liveCoordinatorTransportForTesting(locator);
          final client = CoordinatorClient(transport);
          final watch = Stopwatch()..start();

          // Everything secret lives in these variables only, and dies with the test: nothing is written anywhere.
          final garageKey = GarageKey.generate();
          final first = switch (garageKey.firstUsableRobot(0)) {
            Ok(:final value) => value,
            Err() => fail('no robot at the start of a random Garage Key'),
          };
          final second = switch (garageKey.firstUsableRobot(
            first.accountIndex + 1,
          )) {
            Ok(:final value) => value,
            Err() => fail('no second robot in a random Garage Key'),
          };
          RobotPgpKey generate(RobotIdentity identity, String label) {
            final start = watch.elapsedMilliseconds;
            final key = switch (RobotPgpKey.generate(identity)) {
              Ok(:final value) => value,
              Err() => fail('the clock of this machine is out of range'),
            };
            _measure({
              'step': 'pgp_generate',
              'key': label,
              'ms': watch.elapsedMilliseconds - start,
            });
            return key;
          }

          final firstKey = generate(first.identity, 'robot_a');
          final otherKeyOfFirst = generate(first.identity, 'robot_a_other');
          final secondKey = generate(second.identity, 'robot_b');
          _measure({
            'step': 'robots',
            'robotAIndex': first.accountIndex,
            'robotBIndex': second.accountIndex,
          });

          final completed = <String>[];
          // When the first robot was created on each coordinator, in milliseconds on [watch].
          final createdAt = <Coordinator, int>{};
          try {
            // The federation list itself: asking the facade for the books would start anonymous requests next to the ones measured here.
            for (final coordinator in Federation.robosats.on(_network)) {
              final alias = coordinator.shortAlias;
              // A testnet instance has its own onion address: never the mainnet one.
              expect(coordinator.testnet.onion, isNotNull);
              expect(
                coordinator.testnet.onion,
                isNot(coordinator.mainnet.onion),
              );

              // `/api/info/` first: it starts Tor, and it proves the instance announces testnet and the testnet node of the federation list.
              final info = await _try(
                alias,
                'info',
                watch,
                () => facade.fetchInfo(coordinator, _network),
                fields: (info) => {
                  'network': info.network?.name,
                  'version': '${info.version}',
                },
              );
              if (info case Err()) continue;
              if (info case Ok(:final value)) {
                expect(value.network, RobosatsNetwork.testnet);
              }

              // A step proves the pair of an answer when it is not the one just sent: the time of the proof is in the time of the step.
              Future<Result<CoordinatorRobot, CoordinatorFailure>> step(
                String label,
                Future<Result<CoordinatorRobotAnswer, CoordinatorFailure>>
                Function()
                call,
              ) => _try(
                alias,
                label,
                watch,
                () async => _settled(await call()),
                fields: _robotFields,
              );

              // The app-facing facade has no robot call: the client of the package is driven here over the real transport of the app.
              // 1. The short header before any first contact: the coordinator does not know the robot.
              final unknown = await step(
                'a_short_header_before_first_contact',
                () => client.fetchKnownRobot(
                  coordinator,
                  _network,
                  identity: first.identity,
                ),
              );
              if (_gaveUp(unknown)) continue;
              expect(
                unknown,
                isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
                  (err) => err.failure,
                  'failure',
                  isA<RobotUnknown>(),
                ),
              );

              // 2. First contact: token hash, both PGP keys, Nostr key of the current frontend.
              final created = await step(
                'a_first_contact',
                () => client.fetchRobot(
                  coordinator,
                  _network,
                  identity: first.identity,
                  pgpKey: firstKey,
                ),
              );
              if (_gaveUp(created)) continue;
              final createdRobot = switch (created) {
                Ok(:final value) => value,
                Err(:final failure) => fail(
                  'first contact refused: ${_failure(failure)}',
                ),
              };
              createdAt[coordinator] = watch.elapsedMilliseconds;
              // The cross-checks passed: hash id, nickname and both PGP keys are the ones of this device, the pair taken as sent, without a proof.
              expect(createdRobot.hashId, first.identity.hashId);
              expect(createdRobot.pgpKey, same(firstKey));
              expect(createdRobot.pgpKeyProven, isFalse);
              expect(
                createdRobot.nostrPublicKeyHex,
                first.identity.nostrKeyPair().publicKeyHex,
              );
              expect(
                createdRobot.nostrKeyDerivation,
                NostrKeyDerivation.currentFrontend,
              );

              // 3. The short header now reads the same robot back with nothing in memory, as after a restart: the robot derived again from the Garage Key, a new client, no pair given; the pair comes from the coordinator and is taken once the token has proved it.
              final readBack = await step(
                'a_read_back_with_nothing_in_memory',
                () async {
                  final again = switch (garageKey.firstUsableRobot(
                    first.accountIndex,
                  )) {
                    Ok(:final value) => value,
                    Err() => fail('the robot cannot be derived again'),
                  };
                  return CoordinatorClient(transport).fetchKnownRobot(
                    coordinator,
                    _network,
                    identity: again.identity,
                  );
                },
              );
              if (_gaveUp(readBack)) continue;
              final readBackRobot = switch (readBack) {
                Ok(:final value) => value,
                Err(:final failure) => fail(
                  'read back refused: ${_failure(failure)}',
                ),
              };
              expect(readBackRobot.hashId, first.identity.hashId);
              expect(
                readBackRobot.nostrKeyDerivation,
                NostrKeyDerivation.currentFrontend,
              );
              // The pair the token proved is the one the first contact sent, which this test kept only to compare.
              expect(readBackRobot.pgpKeyProven, isTrue);
              expect(readBackRobot.pgpKey, firstKey);

              // 4. A first contact again, as the official client sends at every start: same robot.
              final again = await step(
                'a_first_contact_again',
                () => client.fetchRobot(
                  coordinator,
                  _network,
                  identity: first.identity,
                  pgpKey: firstKey,
                ),
              );
              if (_gaveUp(again)) continue;
              expect(
                again,
                isA<Ok<CoordinatorRobot, CoordinatorFailure>>().having(
                  (ok) => ok.value.pgpKeyProven,
                  'pgpKeyProven',
                  isFalse,
                ),
              );

              // 5. A first contact with another key pair for the same token, as a second device would send: the coordinator keeps the first pair, which the token proves, so it is taken instead of the pair sent.
              final otherKey = await step(
                'a_first_contact_with_another_key_pair',
                () => client.fetchRobot(
                  coordinator,
                  _network,
                  identity: first.identity,
                  pgpKey: otherKeyOfFirst,
                ),
              );
              if (_gaveUp(otherKey)) continue;
              expect(
                otherKey,
                isA<Ok<CoordinatorRobot, CoordinatorFailure>>()
                    .having((ok) => ok.value.pgpKey, 'pgpKey', firstKey)
                    .having(
                      (ok) => ok.value.pgpKeyProven,
                      'pgpKeyProven',
                      isTrue,
                    ),
              );

              // 6. A first contact for the known robot with the Nostr key of the other formula: the coordinator keeps the first one.
              final keptNostr = await step(
                'a_first_contact_with_the_other_nostr_key',
                () => client.fetchRobot(
                  coordinator,
                  _network,
                  identity: first.identity,
                  pgpKey: firstKey,
                  nostrKeyDerivation: NostrKeyDerivation.repositoryFixtures,
                ),
              );
              if (_gaveUp(keptNostr)) continue;
              expect(
                keptNostr,
                isA<Ok<CoordinatorRobot, CoordinatorFailure>>().having(
                  (ok) => ok.value.nostrKeyDerivation,
                  'nostrKeyDerivation',
                  NostrKeyDerivation.currentFrontend,
                ),
              );

              // 7. A second robot whose first contact sends the Nostr key of the other formula: does the coordinator accept it too?
              final fixtures = await step(
                'b_first_contact_with_the_other_nostr_key',
                () => client.fetchRobot(
                  coordinator,
                  _network,
                  identity: second.identity,
                  pgpKey: secondKey,
                  nostrKeyDerivation: NostrKeyDerivation.repositoryFixtures,
                ),
              );
              if (_gaveUp(fixtures)) continue;
              final fixturesRead = await step(
                'b_short_header_after_first_contact',
                () => client.fetchKnownRobot(
                  coordinator,
                  _network,
                  identity: second.identity,
                ),
              );
              if (_gaveUp(fixturesRead)) continue;
              for (final result in [fixtures, fixturesRead]) {
                expect(
                  result,
                  isA<Ok<CoordinatorRobot, CoordinatorFailure>>().having(
                    (ok) => ok.value.nostrKeyDerivation,
                    'nostrKeyDerivation',
                    NostrKeyDerivation.repositoryFixtures,
                  ),
                );
              }

              // 8. The raw answer, for its shape only: which fields, of which type and length, and whether the keys came back as sent.
              final onion = coordinator.testnet.onion ?? '';
              final raw = await transport.send(
                CoordinatorRequest(
                  method: CoordinatorHttpMethod.get,
                  url: Uri.parse(onion).replace(path: '/api/robot/'),
                  headers: {
                    'Accept': 'application/json',
                    'Authorization': first.identity.authorizationHeader(),
                  },
                  maxResponseBytes: 65536,
                  robot: first.identity.sessionKey,
                ),
              );
              if (raw case Ok(value: final response)) {
                final body = jsonDecode(utf8.decode(response.body));
                final fields = body is Map<String, Object?>
                    ? body
                    : const <String, Object?>{};
                _measure({
                  'step': 'a_raw_answer_shape',
                  'alias': alias,
                  'status': response.statusCode,
                  'bytes': response.body.length,
                  'contentTypeIsJson':
                      response.contentType == 'application/json',
                  // In the order of the answer; a name this test does not know is counted, never printed.
                  'fields': {
                    for (final MapEntry(:key, :value) in fields.entries)
                      if (_knownFields.contains(key)) key: _shape(value),
                  },
                  'unknownFields': fields.keys
                      .where((name) => !_knownFields.contains(name))
                      .length,
                  'publicKeyAsSent':
                      fields['public_key'] == firstKey.publicKey.armored,
                  'publicKeyAsSentButForOuterWhitespace':
                      '${fields['public_key']}'.trim() ==
                      firstKey.publicKey.armored.trim(),
                  'privateKeyAsSent':
                      fields['encrypted_private_key'] ==
                      firstKey.encryptedPrivateKeyArmored,
                  'privateKeyAsSentButForOuterWhitespace':
                      '${fields['encrypted_private_key']}'.trim() ==
                      firstKey.encryptedPrivateKeyArmored.trim(),
                  'publicKeySentChars': firstKey.publicKey.armored.length,
                  'privateKeySentChars':
                      firstKey.encryptedPrivateKeyArmored.length,
                  'lastLoginForm': _lastLoginForm(fields['last_login']),
                });
              }

              completed.add(alias);
            }

            // 9. Five minutes later the coordinator says it knew the robot: the only thing that tells a known robot from a new one.
            for (final MapEntry(key: coordinator, value: created)
                in createdAt.entries) {
              final alias = coordinator.shortAlias;
              if (!completed.contains(alias)) continue;
              final wait =
                  _foundAfter.inMilliseconds -
                  (watch.elapsedMilliseconds - created);
              if (wait > 0) {
                await Future<void>.delayed(Duration(milliseconds: wait));
              }
              final later = await _try(
                alias,
                'a_short_header_after_five_minutes',
                watch,
                () async => _settled(
                  await client.fetchKnownRobot(
                    coordinator,
                    _network,
                    identity: first.identity,
                  ),
                ),
                fields: _robotFields,
              );
              if (_gaveUp(later)) {
                completed.remove(alias);
                continue;
              }
              expect(
                later,
                isA<Ok<CoordinatorRobot, CoordinatorFailure>>().having(
                  (ok) => ok.value.found,
                  'found',
                  isTrue,
                ),
              );
            }
          } finally {
            // Every session, the ones of the two robots included.
            await facade.closeSessions();
          }

          _measure({
            'step': 'summary',
            'completed': completed,
            'totalMs': watch.elapsedMilliseconds,
          });
          // A coordinator that is down is an outage on its side: one testnet coordinator that goes through every step is enough.
          expect(completed, isNotEmpty);
        },
      );
    },
  );
}
