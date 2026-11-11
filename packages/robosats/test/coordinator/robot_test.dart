import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/craft.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;

/// The robot of every test: index 0 of the example Garage Key of the RoboSats repository (`garageKey.test.ts`), a token published there and never a secret.
final _identity = interopIdentity;

/// Its key pair on this device, the one `tool/pgp_interop.sh` showed to GnuPG.
final _key = generateInteropKey();

/// The same public key as GnuPG exports it again, which is the form a coordinator stores and returns.
final _reexportedPublicKey = interopFile('troc_pub_key_reexported_by_gpg');

/// The answer of a coordinator that has just created [_identity] with [_key]: the fields and their order as temple sent them on testnet, with the values of the test robot.
Map<String, Object?> _robot([Map<String, Object?> changes = const {}]) => {
  'nickname': _identity.nickname,
  'hash_id': _identity.hashId.hex,
  'public_key': _reexportedPublicKey,
  'encrypted_private_key': _key.encryptedPrivateKeyArmored,
  'earned_rewards': 0,
  'wants_stealth': true,
  'nostr_pubkey': _identity.nostrKeyPair().publicKeyHex,
  'webhook_url': '',
  'webhook_enabled': false,
  'webhook_api_key': null,
  'last_login': '2026-11-11T10:20:30.123456Z',
  'tg_enabled': false,
  'tg_token': 'not-read',
  'tg_bot_name': 'not-read',
  ...changes,
};

Map<String, Object?> _without(String key) => Map.of(_robot())..remove(key);

/// The error body of the authentication middleware (`api/errors.py:99-117`).
Map<String, Object?> _error(int code, [String message = 'Some text.']) => {
  'error_code': code,
  'bad_request': message,
};

/// The message of error 7002: the key error, written as the text of a Python dictionary.
String _keysMessage(int nestedCode) =>
    "Invalid keys: {'error_code': $nestedCode, 'bad_request': 'Your PGP public key was not accepted. SECRET-LOOKING-TEXT'}";

void main() {
  final temple = coordinatorNamed('temple');
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    transport = FakeCoordinatorTransport();
    client = CoordinatorClient(transport, clock: () => recordedAt);
  });

  void serve(Result<CoordinatorResponse, CoordinatorTransportFailure> answer) =>
      transport.answer(temple, _testnet, '/api/robot/', answer);

  void serveJson(Object? json, {int statusCode = 200}) =>
      serve(Ok(jsonResponse(json, statusCode: statusCode)));

  Future<Result<CoordinatorRobot, CoordinatorFailure>> fetch({
    RobotPgpKey? pgpKey,
    NostrKeyDerivation derivation = NostrKeyDerivation.currentFrontend,
  }) => client.fetchRobot(
    temple,
    _testnet,
    identity: _identity,
    pgpKey: pgpKey ?? _key,
    nostrKeyDerivation: derivation,
  );

  Future<Result<CoordinatorRobot, CoordinatorFailure>> fetchKnown() => client
      .fetchKnownRobot(temple, _testnet, identity: _identity, pgpKey: _key);

  group('the request', () {
    test(
      'of a first contact carries the four parts a coordinator splits',
      () async {
        serveJson(_robot());
        await fetch();

        final request = transport.requests.single;
        expect(request.method, CoordinatorHttpMethod.get);
        expect(request.url.toString(), '${temple.testnet.onion}/api/robot/');
        expect(request.body, isNull);
        expect(request.maxResponseBytes, CoordinatorReadBounds.robotBytes);
        expect(request.headers.keys, ['Accept', 'Authorization']);
        expect(request.headers['Accept'], 'application/json');

        // `SplitAuthorizationHeaderMiddleware` of `robosats/middleware.py:51-59`.
        final parts = (request.headers['Authorization'] ?? '').split(' | ');
        expect(parts, hasLength(4));
        expect(parts[0], 'Token ${_identity.tokenSha256Base91}');
        expect(parts[1], 'Public ${pgpArmorToWire(_key.publicKey.armored)}');
        expect(
          parts[2],
          'Private ${pgpArmorToWire(_key.encryptedPrivateKeyArmored)}',
        );
        expect(parts[3], 'Nostr ${_identity.nostrKeyPair().publicKeyHex}');
        expect(request.headers['Authorization'], isNot(contains('\n')));
      },
    );

    test('of a first contact sends the Nostr key of the formula asked', () async {
      serveJson(_robot());
      await fetch(derivation: NostrKeyDerivation.repositoryFixtures);

      expect(
        transport.requests.single.headers['Authorization'],
        endsWith(
          ' | Nostr ${_identity.nostrKeyPair(NostrKeyDerivation.repositoryFixtures).publicKeyHex}',
        ),
      );
    });

    test('of a known robot carries the token hash alone', () async {
      serveJson(_robot());
      await fetchKnown();

      final request = transport.requests.single;
      expect(request.url.toString(), '${temple.testnet.onion}/api/robot/');
      expect(request.headers, {
        'Accept': 'application/json',
        'Authorization': 'Token ${_identity.tokenSha256Base91}',
      });
    });

    test('never carries the token itself', () async {
      serveJson(_robot());
      await fetch();
      await fetchKnown();

      for (final request in transport.requests) {
        expect(
          request.headers.values.join(' '),
          isNot(contains(_identity.token.reveal())),
        );
        expect('${request.url}', isNot(contains(_identity.token.reveal())));
      }
    });

    test('never carries the armor headers a key was read with', () async {
      // What the reviewer of #39 tried: a `Comment` header would have made five parts, and a value `dart:io` refuses.
      String withHeader(String armored) {
        final lines = armored.trim().split('\n');
        return [
          lines.first,
          'Version: Another client',
          'Comment: café | pipe\ttab',
          ...lines.skip(1),
        ].join('\n');
      }

      final read = expectOk(
        RobotPgpKey.parse(
          publicKey: withHeader(_key.publicKey.armored),
          encryptedPrivateKey: withHeader(_key.encryptedPrivateKeyArmored),
        ),
      );
      serveJson(_robot());
      expectOk(await fetch(pgpKey: read));
      await fetch();

      final [fromRead, fromGenerated] = transport.requests;
      final header = fromRead.headers['Authorization'] ?? '';
      expect(header, fromGenerated.headers['Authorization']);
      expect(header.split(' | '), hasLength(4));
      expect(header, isNot(contains('Comment')));
      expect(header, isNot(contains('café')));
      // Printable ASCII only, which every HTTP stack carries.
      expect(header, matches(RegExp(r'^[\x20-\x7E]+$')));
    });

    test('names its robot, and only authenticated requests do', () async {
      serveJson(_robot());
      await fetch();
      await fetchKnown();
      transport.answerRecorded('temple', _testnet, 'info');
      await client.fetchInfo(temple, _testnet);

      final [first, known, info] = transport.requests;
      expect(first.robot, _identity.sessionKey);
      expect(known.robot, _identity.sessionKey);
      expect(info.robot, isNull);
      expect(info.headers, {'Accept': 'application/json'});
    });

    test('prints neither its credential nor its robot', () async {
      serveJson(_robot());
      await fetch();

      final request = transport.requests.single;
      expect('$request', 'CoordinatorRequest(GET /api/robot/)');
      expect('${request.robot}', 'RobotSessionKey(<redacted>)');
    });

    test('is not sent to a coordinator that is not on the network', () async {
      final result = await client.fetchRobot(
        coordinatorNamed('bazaar'),
        _testnet,
        identity: _identity,
        pgpKey: _key,
      );

      expect(expectErr(result), isA<CoordinatorNotOnNetwork>());
      expect(transport.requests, isEmpty);
    });
  });

  group('a session key', () {
    test('is the same for the same robot, and differs between robots', () {
      expect(_identity.sessionKey, interopIdentity.sessionKey);
      expect(
        _identity.sessionKey.hashCode,
        interopIdentity.sessionKey.hashCode,
      );
      expect(_identity.sessionKey, isNot(interopPeerIdentity.sessionKey));
    });
  });

  group('a new robot', () {
    test(
      'is read when the coordinator returns the robot of this device',
      () async {
        serveJson(_robot());
        final robot = expectOk(await fetch());

        expect(robot.coordinator, temple);
        expect(robot.hashId, _identity.hashId);
        expect(robot.hashId.nickname, _identity.nickname);
        expect(robot.found, isFalse);
        expect(robot.earnedRewards, Sats.fromInt(0));
        expect(robot.wantsStealth, isTrue);
        expect(robot.activeOrderId, isNull);
        expect(robot.lastOrderId, isNull);
        expect(
          robot.lastLogin,
          DateTime.utc(2026, 11, 11, 10, 20, 30, 123, 456),
        );
        expect(robot.nostrPublicKeyHex, _identity.nostrKeyPair().publicKeyHex);
        expect(robot.nostrKeyDerivation, NostrKeyDerivation.currentFrontend);
      },
    );

    test('is read with only the fields this package requires', () async {
      serveJson({
        'nickname': _identity.nickname,
        'hash_id': _identity.hashId.hex,
        'public_key': _reexportedPublicKey,
        'encrypted_private_key': _key.encryptedPrivateKeyArmored,
      });
      final robot = expectOk(await fetch());

      expect(robot.found, isFalse);
      expect(robot.earnedRewards, Sats.fromInt(0));
      expect(robot.wantsStealth, isTrue);
      expect(robot.lastLogin, isNull);
      expect(robot.nostrPublicKeyHex, isNull);
      expect(robot.nostrKeyDerivation, isNull);
    });

    test(
      'is read when the keys come back on one line, with backslashes',
      () async {
        serveJson(
          _robot({
            'public_key': pgpArmorToWire(_reexportedPublicKey),
            'encrypted_private_key': pgpArmorToWire(
              _key.encryptedPrivateKeyArmored,
            ),
          }),
        );

        expectOk(await fetch());
      },
    );

    test('is read when the keys come back in another armor', () async {
      String withHeader(String armored) {
        final lines = armored.trim().split('\n');
        return [lines.first, 'Comment: x', ...lines.skip(1)].join('\n');
      }

      for (final rearmor in <String Function(String)>[
        withHeader,
        (armored) => armored.replaceAll('\n', '\r\n'),
        (armored) => '\n  $armored\n\n',
      ]) {
        serveJson(
          _robot({
            'public_key': rearmor(_reexportedPublicKey),
            'encrypted_private_key': rearmor(_key.encryptedPrivateKeyArmored),
          }),
        );

        expectOk(await fetch());
      }
    });

    test('is read when the public key comes back exactly as sent', () async {
      serveJson(_robot({'public_key': _key.publicKey.armored}));

      expectOk(await fetch());
    });

    test('prints public identifiers only', () async {
      serveJson(_robot());
      final robot = expectOk(await fetch());

      expect(
        '$robot',
        'CoordinatorRobot(temple, ${_identity.nickname}, found: false)',
      );
    });
  });

  group('a known robot', () {
    test('is read the same way from the short header', () async {
      serveJson(
        _robot({
          'found': true,
          'earned_rewards': 1500,
          'wants_stealth': false,
          'active_order_id': 4242,
        }),
      );
      final robot = expectOk(await fetchKnown());

      expect(robot.found, isTrue);
      expect(robot.earnedRewards, Sats.fromInt(1500));
      expect(robot.wantsStealth, isFalse);
      expect(robot.activeOrderId, 4242);
      expect(robot.lastOrderId, isNull);
    });

    test('is read the same way from a first contact it ignores', () async {
      serveJson(_robot({'found': true, 'last_order_id': 77}));
      final robot = expectOk(await fetch());

      expect(robot.found, isTrue);
      expect(robot.activeOrderId, isNull);
      expect(robot.lastOrderId, 77);
    });

    test('that the coordinator does not know is a typed failure', () async {
      serveJson(_error(7001), statusCode: 400);

      expect(expectErr(await fetchKnown()), isA<RobotUnknown>());
    });

    test('created elsewhere with another key pair is a mismatch', () async {
      // What a coordinator returns to a device that restored a Garage Key: the key pair of the first device.
      final other = expectOk(
        RobotPgpKey.generateWith(
          _identity,
          now: interopNow,
          random: DeterministicRandom('another device'),
        ),
      );
      expect(other.isNamedAfter(_identity), isTrue);
      serveJson(
        _robot({
          'found': true,
          'public_key': other.publicKey.armored,
          'encrypted_private_key': other.encryptedPrivateKeyArmored,
        }),
      );

      expect(expectErr(await fetch()), isA<RobotPgpKeyMismatch>());
      expect(expectErr(await fetchKnown()), isA<RobotPgpKeyMismatch>());
    });
  });

  group('the Nostr key the coordinator holds', () {
    Future<CoordinatorRobot> withKey(Object? key) async {
      serveJson(_robot({'nostr_pubkey': key}));
      return expectOk(await fetch());
    }

    test('is recognised under either formula', () async {
      for (final derivation in NostrKeyDerivation.values) {
        final key = _identity.nostrKeyPair(derivation).publicKeyHex;
        final robot = await withKey(key);

        expect(robot.nostrPublicKeyHex, key);
        expect(robot.nostrKeyDerivation, derivation);
      }
    });

    test('is reported as foreign when it is neither', () async {
      final foreign = interopPeerIdentity.nostrKeyPair().publicKeyHex;
      final robot = await withKey(foreign);

      expect(robot.nostrPublicKeyHex, foreign);
      expect(robot.nostrKeyDerivation, isNull);
    });

    test('is reported as foreign when it is the placeholder', () async {
      final robot = await withKey('0' * 64);

      expect(robot.nostrPublicKeyHex, '0' * 64);
      expect(robot.nostrKeyDerivation, isNull);
    });

    test('is absent when the coordinator sends none', () async {
      for (final none in [null, '']) {
        final robot = await withKey(none);

        expect(robot.nostrPublicKeyHex, isNull);
        expect(robot.nostrKeyDerivation, isNull);
      }
    });

    test('rejects the answer when it is not a key', () async {
      final valid = _identity.nostrKeyPair().publicKeyHex;
      for (final invalid in [
        valid.toUpperCase(),
        valid.substring(1),
        '${valid}0',
        'g${valid.substring(1)}',
        ' ${valid.substring(1)}',
        'Nostr $valid',
        42,
        [valid],
        true,
      ]) {
        serveJson(_robot({'nostr_pubkey': invalid}));

        expect(
          expectErr(await fetch()),
          isA<CoordinatorResponseMalformed>().having(
            (f) => f.field,
            'field',
            'nostr_pubkey',
          ),
          reason: '$invalid',
        );
      }
    });
  });

  group('a robot that is not the one of this device', () {
    test('by its hash id', () async {
      serveJson(_robot({'hash_id': interopPeerIdentity.hashId.hex}));

      expect(expectErr(await fetch()), isA<RobotHashIdMismatch>());
    });

    test('by its hash id, whatever the nickname says', () async {
      serveJson(
        _robot({
          'hash_id': interopPeerIdentity.hashId.hex,
          'nickname': interopPeerIdentity.nickname,
        }),
      );

      expect(expectErr(await fetch()), isA<RobotHashIdMismatch>());
    });

    test('by the case of its hash id', () async {
      serveJson(_robot({'hash_id': _identity.hashId.hex.toUpperCase()}));

      expect(expectErr(await fetch()), isA<RobotHashIdMismatch>());
    });

    test('by its nickname', () async {
      for (final nickname in [
        interopPeerIdentity.nickname,
        _identity.nickname.toLowerCase(),
        '${_identity.nickname} ',
        '',
      ]) {
        serveJson(_robot({'nickname': nickname}));

        expect(
          expectErr(await fetch()),
          isA<RobotNicknameMismatch>(),
          reason: nickname,
        );
      }
    });

    test('by a public key the coordinator made for the same hash id', () async {
      // A dishonest coordinator can name a key of its own after the robot: only the fingerprints tell.
      final forged = CraftedKey(label: 'forged', userId: _identity.pgpUserId);
      serveJson(
        _robot({
          'public_key': forged.publicArmored,
          'encrypted_private_key': forged.privateArmored('a passphrase'),
        }),
      );

      expect(expectErr(await fetch()), isA<RobotPgpKeyMismatch>());
    });

    test(
      'by the public key alone, the private key being the right one',
      () async {
        serveJson(
          _robot({'public_key': generateInteropPeerKey().publicKey.armored}),
        );

        expect(expectErr(await fetch()), isA<RobotPgpKeyMismatch>());
      },
    );

    test('by a public key with another encryption subkey', () async {
      final own = CraftedKey();
      // The same primary key certifies another subkey: chat messages would be encrypted to it.
      final otherSubkey = CraftedKey(
        subkeyPoint: x25519PublicKey(CraftedKey(label: 'other').scalar),
      );
      final local = expectOk(
        RobotPgpKey.parse(
          publicKey: own.publicArmored,
          encryptedPrivateKey: own.privateArmored('a passphrase'),
        ),
      );
      expect(otherSubkey.publicKey, isNot(own.publicKey));
      expect(otherSubkey.publicKey.fingerprint, own.publicKey.fingerprint);
      serveJson(
        _robot({
          'public_key': otherSubkey.publicArmored,
          'encrypted_private_key': own.privateArmored('a passphrase'),
        }),
      );

      expect(expectErr(await fetch(pgpKey: local)), isA<RobotPgpKeyMismatch>());
    });

    test('by another primary key that binds the subkey of this device', () async {
      // A coordinator can make a primary key of its own and bind the encryption subkey of the robot under it: the subkey alone proves nothing.
      final own = CraftedKey();
      final local = expectOk(
        RobotPgpKey.parse(
          publicKey: own.publicArmored,
          encryptedPrivateKey: own.privateArmored('a passphrase'),
        ),
      );
      final foreign = CraftedKey(
        label: 'another primary key',
        subkeyPoint: x25519PublicKey(own.scalar),
      );
      expect(foreign.subkeyBody, own.subkeyBody);
      expect(foreign.publicKey.fingerprint, isNot(own.publicKey.fingerprint));
      serveJson(
        _robot({
          'public_key': foreign.publicArmored,
          'encrypted_private_key': own.privateArmored('a passphrase'),
        }),
      );

      expect(expectErr(await fetch(pgpKey: local)), isA<RobotPgpKeyMismatch>());
    });

    test('by its hash id before any key is read', () async {
      // A wrong hash id with a key that is not even a key: the answer is about another robot, and nothing of it is parsed.
      for (final key in ['not a key', '', 'A' * 20000]) {
        serveJson(
          _robot({
            'hash_id': interopPeerIdentity.hashId.hex,
            'public_key': key,
            'encrypted_private_key': key,
          }),
        );
        expect(expectErr(await fetch()), isA<RobotHashIdMismatch>());

        serveJson(
          _robot({
            'nickname': interopPeerIdentity.nickname,
            'public_key': key,
            'encrypted_private_key': key,
          }),
        );
        expect(expectErr(await fetch()), isA<RobotNicknameMismatch>());
      }
    });

    test('by a public key of a kind this package does not make', () async {
      final unsupported = CraftedKey(kdf: const [3, 1, 1, 2]).publicArmored;
      expect(
        expectErr(PgpPublicKey.parse(unsupported)),
        isA<PgpKeyUnsupported>(),
      );
      serveJson(_robot({'public_key': unsupported}));

      expect(expectErr(await fetch()), isA<RobotPgpKeyMismatch>());
    });

    test(
      'by an encrypted private key that is another locking of the same key',
      () async {
        final crafted = CraftedKey();
        final local = expectOk(
          RobotPgpKey.parse(
            publicKey: crafted.publicArmored,
            encryptedPrivateKey: crafted.privateArmored('a passphrase'),
          ),
        );
        final lockedAgain = armorPackets(
          ArmorBlock.privateKey,
          crafted.privatePackets(
            'a passphrase',
            protect: (secret, passphrase) =>
                protectSecret(secret, passphrase, codedCount: 97),
          ),
        );
        serveJson(
          _robot({
            'public_key': crafted.publicArmored,
            'encrypted_private_key': lockedAgain,
          }),
        );
        expect(
          expectErr(await fetch(pgpKey: local)),
          isA<RobotPgpKeyMismatch>(),
        );

        // The same answer with the private key as this device holds it is accepted.
        serveJson(
          _robot({
            'public_key': crafted.publicArmored,
            'encrypted_private_key':
                '${crafted.privateArmored('a passphrase')}\n',
          }),
        );
        expectOk(await fetch(pgpKey: local));
      },
    );
  });

  group('a malformed answer', () {
    Future<void> expectMalformed(Object? body, String field) async {
      serveJson(body);
      expect(
        expectErr(await fetch()),
        isA<CoordinatorResponseMalformed>().having(
          (f) => f.field,
          'field',
          field,
        ),
        reason: field,
      );
    }

    test('is rejected when it is not an object', () async {
      for (final body in [
        null,
        <Object?>[],
        [_robot()],
        'robot',
        42,
        true,
      ]) {
        await expectMalformed(body, 'robot');
      }
    });

    test('is rejected when a required field is missing or null', () async {
      for (final field in [
        'hash_id',
        'nickname',
        'public_key',
        'encrypted_private_key',
      ]) {
        await expectMalformed(_without(field), field);
        await expectMalformed(_robot({field: null}), field);
      }
    });

    test('is rejected when a field has the wrong type', () async {
      final wrong = <String, List<Object?>>{
        'hash_id': [42, true, <Object?>[]],
        'nickname': [42, <String, Object?>{}],
        'public_key': [42, <Object?>[]],
        'encrypted_private_key': [42, false],
        'earned_rewards': ['0', 1.5, true],
        'wants_stealth': ['true', 1, 0],
        'active_order_id': ['12', 1.5, true],
        'last_order_id': ['12', <Object?>[]],
        'found': ['true', 1],
        'last_login': [1794392430, true],
      };
      for (final MapEntry(key: field, value: values) in wrong.entries) {
        for (final value in values) {
          await expectMalformed(_robot({field: value}), field);
        }
      }
    });

    test('is rejected when a number is out of range', () async {
      final outOfRange = <String, List<int>>{
        'earned_rewards': [-1, CoordinatorReadBounds.maxSats + 1],
        'active_order_id': [0, -5, (1 << 53) + 1],
        'last_order_id': [0, -5, (1 << 53) + 1],
      };
      for (final MapEntry(key: field, value: values) in outOfRange.entries) {
        for (final value in values) {
          await expectMalformed(_robot({field: value}), field);
        }
      }
    });

    test('is rejected when a text is longer than its bound', () async {
      await expectMalformed(_robot({'hash_id': 'a' * 65}), 'hash_id');
      await expectMalformed(_robot({'nickname': 'A' * 65}), 'nickname');
      await expectMalformed(_robot({'nostr_pubkey': 'a' * 65}), 'nostr_pubkey');
      await expectMalformed(
        _robot({'public_key': '$_reexportedPublicKey${'\n' * 20000}'}),
        'public_key',
      );
      await expectMalformed(
        _robot({
          'encrypted_private_key':
              '${_key.encryptedPrivateKeyArmored}${'\n' * 20000}',
        }),
        'encrypted_private_key',
      );
    });

    test('is rejected when the date of the last login is not one', () async {
      for (final date in [
        '',
        'yesterday',
        '2026-11-11T10:20:30',
        '2026-11-11 10:20:30Z',
        '2026-13-11T10:20:30Z',
        '2026-11-11T25:20:30Z',
        '1999-11-11T10:20:30Z',
        '2026-11-11T10:20:30Z${' ' * 40}',
      ]) {
        await expectMalformed(_robot({'last_login': date}), 'last_login');
      }
    });

    test('is rejected when the public key is not an armored key', () async {
      for (final key in [
        '',
        'not a key',
        _key.encryptedPrivateKeyArmored,
        _reexportedPublicKey.replaceFirst('mDME', 'mDMF'),
        _reexportedPublicKey.substring(0, _reexportedPublicKey.length ~/ 2),
      ]) {
        await expectMalformed(_robot({'public_key': key}), 'public_key');
      }
    });

    test(
      'is rejected when the private key is not the pair of the public key',
      () async {
        for (final key in [
          '',
          'not a key',
          _reexportedPublicKey,
          generateInteropPeerKey().encryptedPrivateKeyArmored,
          _key.encryptedPrivateKeyArmored.substring(
            0,
            _key.encryptedPrivateKeyArmored.length ~/ 2,
          ),
        ]) {
          await expectMalformed(
            _robot({'encrypted_private_key': key}),
            'encrypted_private_key',
          );
        }
      },
    );

    test('names the first invalid field before any mismatch', () async {
      await expectMalformed(
        _robot({'hash_id': interopPeerIdentity.hashId.hex, 'found': 'yes'}),
        'found',
      );
    });

    test('ignores the fields this package does not read', () async {
      serveJson(
        _robot({
          'tg_token': 42,
          'tg_enabled': 'x',
          'tg_bot_name': <Object?>[],
          'webhook_url': 42,
          'webhook_enabled': 'x',
          'webhook_api_key': <String, Object?>{},
          'unknown_field': 'x' * 1000,
        }),
      );

      expectOk(await fetch());
    });
  });

  group('a refusal', () {
    Future<CoordinatorFailure> refusal(
      Object? body, {
      required int statusCode,
      bool known = false,
    }) async {
      serveJson(body, statusCode: statusCode);
      return expectErr(known ? await fetchKnown() : await fetch());
    }

    test(
      'of the token hash, or of the header, is a credentials failure',
      () async {
        expect(
          await refusal(_error(7000), statusCode: 400),
          isA<RobotCredentialsRejected>(),
        );
        // After a first contact, error 7001 means the coordinator did not find the keys this package sent.
        expect(
          await refusal(_error(7001), statusCode: 400),
          isA<RobotCredentialsRejected>(),
        );
        expect(
          await refusal(_error(7003), statusCode: 401),
          isA<RobotCredentialsRejected>(),
        );
        expect(
          await refusal(_error(7000), statusCode: 400, known: true),
          isA<RobotCredentialsRejected>(),
        );
      },
    );

    test(
      'without the error body is a credentials failure for 401 and 403',
      () async {
        for (final status in [401, 403]) {
          for (final body in [
            <String, Object?>{},
            {'detail': 'Invalid token.'},
            'Forbidden',
            {'error_code': 9999},
          ]) {
            expect(
              await refusal(body, statusCode: status),
              isA<RobotCredentialsRejected>(),
            );
          }
          serve(
            Ok(rawResponse(utf8.encode('<html></html>'), statusCode: status)),
          );
          expect(expectErr(await fetch()), isA<RobotCredentialsRejected>());
        }
      },
    );

    test('of the keys gives the reason the coordinator names', () async {
      final reasons = {
        1034: RobotKeysRefusal.invalidKey,
        1055: RobotKeysRefusal.keyAlreadyUsed,
        1056: RobotKeysRefusal.keyTooRecent,
        1048: RobotKeysRefusal.unspecified,
      };
      for (final MapEntry(key: code, value: reason) in reasons.entries) {
        expect(
          await refusal(_error(7002, _keysMessage(code)), statusCode: 400),
          isA<RobotKeysRefused>().having((f) => f.reason, 'reason', reason),
        );
      }
    });

    test('of the keys without a readable reason is unspecified', () async {
      for (final body in [
        {'error_code': 7002},
        {'error_code': 7002, 'bad_request': 42},
        {'error_code': 7002, 'bad_request': ''},
        {'error_code': 7002, 'bad_request': 'Invalid keys: None'},
        {'error_code': 7002, 'bad_request': "{'error_code': 'x'}"},
        {'error_code': 7002, 'bad_request': "{'error_code': 99999999}"},
        {'error_code': 7002, 'bad_request': 'x' * 60000},
      ]) {
        expect(
          await refusal(body, statusCode: 400),
          isA<RobotKeysRefused>().having(
            (f) => f.reason,
            'reason',
            RobotKeysRefusal.unspecified,
          ),
        );
      }
    });

    test('of a nickname already taken is typed', () async {
      expect(
        await refusal(_error(7004), statusCode: 409),
        isA<RobotNicknameTaken>(),
      );
    });

    test(
      'of a nickname already taken is checked with the short header',
      () async {
        // The coordinator refuses every first contact, and does not know the robot.
        transport.route(temple, _testnet, '/api/robot/', (request) async {
          final firstContact = (request.headers['Authorization'] ?? '')
              .contains(' | ');
          return Ok(
            firstContact
                ? jsonResponse(_error(7004), statusCode: 409)
                : jsonResponse(_error(7001), statusCode: 400),
          );
        });

        expect(expectErr(await fetch()), isA<RobotNicknameTaken>());
        final [contact, check] = transport.requests;
        expect(contact.headers['Authorization'], contains(' | Public '));
        expect(
          check.headers['Authorization'],
          'Token ${_identity.tokenSha256Base91}',
        );
        expect(check.robot, _identity.sessionKey);
      },
    );

    test('of a nickname taken by this very robot gives the robot', () async {
      // What a retried first contact meets: the coordinator created the robot for the first copy of the request.
      transport.route(temple, _testnet, '/api/robot/', (request) async {
        final firstContact = (request.headers['Authorization'] ?? '').contains(
          ' | ',
        );
        return Ok(
          firstContact
              ? jsonResponse(_error(7004), statusCode: 409)
              : jsonResponse(_robot()),
        );
      });

      final robot = expectOk(await fetch());

      expect(robot.hashId, _identity.hashId);
      expect(transport.requests, hasLength(2));
    });

    test(
      'of a nickname already taken stays one when the check fails',
      () async {
        for (final check in [
          const Err<CoordinatorResponse, CoordinatorTransportFailure>(
            CoordinatorUnreachable(),
          ),
          Ok<CoordinatorResponse, CoordinatorTransportFailure>(
            jsonResponse(_robot({'hash_id': interopPeerIdentity.hashId.hex})),
          ),
          Ok<CoordinatorResponse, CoordinatorTransportFailure>(
            jsonResponse(_error(7004), statusCode: 409),
          ),
        ]) {
          transport.route(temple, _testnet, '/api/robot/', (request) async {
            final firstContact = (request.headers['Authorization'] ?? '')
                .contains(' | ');
            return firstContact
                ? Ok(jsonResponse(_error(7004), statusCode: 409))
                : check;
          });

          expect(expectErr(await fetch()), isA<RobotNicknameTaken>());
        }
      },
    );

    test(
      'of a nickname already taken is not checked for a known robot',
      () async {
        serveJson(_error(7004), statusCode: 409);

        expect(expectErr(await fetchKnown()), isA<RobotNicknameTaken>());
        expect(transport.requests, hasLength(1));
      },
    );

    test('carries no text of the coordinator', () async {
      const secretLooking = 'SECRET-LOOKING-TEXT';
      final failures = [
        await refusal(_error(7000, secretLooking), statusCode: 400),
        await refusal(_error(7001, secretLooking), statusCode: 400),
        await refusal(
          _error(7001, secretLooking),
          statusCode: 400,
          known: true,
        ),
        await refusal(_error(7002, _keysMessage(1056)), statusCode: 400),
        await refusal(_error(7003, secretLooking), statusCode: 401),
        await refusal(_error(7004, secretLooking), statusCode: 409),
        await refusal({'bad_request': secretLooking}, statusCode: 400),
      ];
      for (final failure in failures) {
        expect('$failure', isNot(contains(secretLooking)));
        expect('$failure', isNot(contains('Some text')));
      }
    });

    test('with an unknown code, or none, is the status alone', () async {
      for (final body in [
        <String, Object?>{},
        {'bad_request': 'Robot token SHA256 was provided…'},
        {'error_code': 1034, 'bad_request': 'x'},
        {'error_code': '7004'},
        {'error_code': 7004.5},
        {'error_code': -7004},
        {'error_code': 100000},
        [7004],
        'Bad Request',
        null,
      ]) {
        expect(
          await refusal(body, statusCode: 400),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            400,
          ),
          reason: '$body',
        );
      }
    });

    test('that is not JSON is the status alone', () async {
      for (final status in [400, 404, 409, 429]) {
        serve(
          Ok(rawResponse(utf8.encode('<html></html>'), statusCode: status)),
        );
        expect(
          expectErr(await fetch()),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
        serve(
          Ok(
            rawResponse(
              utf8.encode(jsonEncode(_error(7004))),
              statusCode: status,
              contentType: 'text/html',
            ),
          ),
        );
        expect(expectErr(await fetch()), isA<CoordinatorUnexpectedStatus>());
      }
    });

    test('outside the 4xx range never reads the error body', () async {
      for (final status in [201, 204, 301, 302, 500, 502, 503]) {
        expect(
          await refusal(_error(7004), statusCode: status),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
      }
    });

    test('is not mistaken for a robot when the status is not 200', () async {
      for (final status in [201, 400, 500]) {
        expect(
          await refusal(_robot(), statusCode: status),
          isA<CoordinatorUnexpectedStatus>(),
        );
      }
    });

    test('with the error body under a 200 is a malformed answer', () async {
      serveJson(_error(7002, _keysMessage(1056)));

      expect(expectErr(await fetch()), isA<CoordinatorResponseMalformed>());
    });
  });

  group('the transport', () {
    final calls =
        <
          String,
          Future<Result<CoordinatorRobot, CoordinatorFailure>> Function()
        >{'a first contact': fetch, 'a read of a known robot': fetchKnown};

    for (final MapEntry(key: label, value: call) in calls.entries) {
      test('$label passes transport failures through', () async {
        for (final failure in const <CoordinatorTransportFailure>[
          CoordinatorUnreachable(),
          CoordinatorTimedOut(),
          CoordinatorResponseTooLarge(),
          CoordinatorTransportFailed(),
        ]) {
          serve(Err(failure));
          expect(expectErr(await call()), same(failure));
        }
      });

      test('$label turns an exception of the adapter into a failure', () async {
        transport.route(
          temple,
          _testnet,
          '/api/robot/',
          (_) => Future.error(const FormatException('socket closed')),
        );

        expect(expectErr(await call()), isA<CoordinatorTransportFailed>());
      });

      test('$label lets an error of the adapter through', () async {
        transport.route(
          temple,
          _testnet,
          '/api/robot/',
          (_) => Future.error(StateError('a bug')),
        );

        await expectLater(call(), throwsStateError);
      });

      test('$label refuses a body above the bound', () async {
        serve(
          Ok(
            rawResponse(
              utf8.encode(
                jsonEncode(
                  _robot({'padding': 'x' * CoordinatorReadBounds.robotBytes}),
                ),
              ),
            ),
          ),
        );

        expect(expectErr(await call()), isA<CoordinatorResponseTooLarge>());
      });

      test('$label rejects anything but JSON under a 200', () async {
        for (final response in [
          rawResponse(utf8.encode(jsonEncode(_robot())), contentType: null),
          rawResponse(
            utf8.encode(jsonEncode(_robot())),
            contentType: 'text/html',
          ),
          rawResponse(utf8.encode('<html></html>')),
          rawResponse(const []),
          rawResponse(const [0x7b, 0x22, 0xff, 0xfe, 0x22, 0x3a, 0x31, 0x7d]),
        ]) {
          serve(Ok(response));
          expect(expectErr(await call()), isA<CoordinatorNotJson>());
        }
      });
    }
  });
}
