import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart' show sha256;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/limits.dart';
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

/// The answer about the robot [identity], with the key pair given as the coordinator would return it.
Map<String, Object?> _robotOf(
  RobotIdentity identity, {
  required String publicKey,
  required String encryptedPrivateKey,
}) => _robot({
  'nickname': identity.nickname,
  'hash_id': identity.hashId.hex,
  'public_key': publicKey,
  'encrypted_private_key': encryptedPrivateKey,
  'nostr_pubkey': identity.nostrKeyPair().publicKeyHex,
});

/// The robot of a first contact whose answer carries the very pair sent: it is the robot as it is, so no proof can have run.
CoordinatorRobot _sent(
  Result<CoordinatorRobotAnswer, CoordinatorFailure> answer,
) => switch (expectOk(answer)) {
  final CoordinatorRobot robot => robot,
  UnprovenCoordinatorRobot() => fail('the pair sent came back to prove'),
};

/// The answer of a first contact whose key pair is not the one sent.
UnprovenCoordinatorRobot _unproven(
  Result<CoordinatorRobotAnswer, CoordinatorFailure> answer,
) => switch (expectOk(answer)) {
  final UnprovenCoordinatorRobot unproven => unproven,
  CoordinatorRobot() => fail('expected a pair to prove'),
};

/// What a caller gets in the end: the robot of the answer, its pair proven when it is not the one sent.
Result<CoordinatorRobot, CoordinatorFailure> _settled(
  Result<CoordinatorRobotAnswer, CoordinatorFailure> answer,
) => switch (answer) {
  Err(:final failure) => Err(failure),
  Ok(value: final CoordinatorRobot robot) => Ok(robot),
  Ok(value: final UnprovenCoordinatorRobot unproven) =>
    unproven.prove().mapErr<CoordinatorFailure>((failure) => failure),
};

/// [key] locked again, each secret part by [passphrase] with its own S2K: [counts], [s2kHashId] and [cipherId].
String _lockedWith(
  CraftedKey key,
  String passphrase, {
  required List<int> counts,
  int s2kHashId = HashId.sha256,
  int cipherId = CipherId.aes256,
}) {
  var part = 0;
  return armorPackets(
    ArmorBlock.privateKey,
    key.privatePackets(
      passphrase,
      protect: (secret, passphrase) => protectSecret(
        secret,
        passphrase,
        // The primary key's part first, then the subkey's.
        codedCount: counts[part++],
        s2kHashId: s2kHashId,
        cipherId: cipherId,
      ),
    ),
  );
}

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

  Future<Result<CoordinatorRobotAnswer, CoordinatorFailure>> fetch({
    RobotPgpKey? pgpKey,
    NostrKeyDerivation derivation = NostrKeyDerivation.currentFrontend,
  }) => client.fetchRobot(
    temple,
    _testnet,
    identity: _identity,
    pgpKey: pgpKey ?? _key,
    nostrKeyDerivation: derivation,
  );

  Future<Result<UnprovenCoordinatorRobot, CoordinatorFailure>> fetchKnown({
    RobotIdentity? identity,
  }) =>
      client.fetchKnownRobot(temple, _testnet, identity: identity ?? _identity);

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
      final bazaar = coordinatorNamed('bazaar');
      final contact = await client.fetchRobot(
        bazaar,
        _testnet,
        identity: _identity,
        pgpKey: _key,
      );
      final read = await client.fetchKnownRobot(
        bazaar,
        _testnet,
        identity: _identity,
      );

      expect(expectErr(contact), isA<CoordinatorNotOnNetwork>());
      expect(expectErr(read), isA<CoordinatorNotOnNetwork>());
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
        final robot = _sent(await fetch());

        expect(robot.pgpKey, same(_key));
        expect(robot.pgpKeyProven, isFalse);
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
      final robot = _sent(await fetch());

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

        _sent(await fetch());
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

        _sent(await fetch());
      }
    });

    test('is read when the public key comes back exactly as sent', () async {
      serveJson(_robot({'public_key': _key.publicKey.armored}));

      _sent(await fetch());
    });

    test('prints public identifiers only', () async {
      serveJson(_robot());
      final robot = _sent(await fetch());

      expect(
        '$robot',
        'CoordinatorRobot(temple, ${_identity.nickname}, found: false)',
      );
    });
  });

  group('a known robot', () {
    test(
      'is read the same way from the short header, once its pair is proven',
      () async {
        serveJson(
          _robot({
            'found': true,
            'earned_rewards': 1500,
            'wants_stealth': false,
            'active_order_id': 4242,
          }),
        );
        final unproven = expectOk(await fetchKnown());

        expect(unproven.coordinator, temple);
        expect(unproven.hashId, _identity.hashId);
        final robot = expectOk(unproven.prove());
        expect(robot.found, isTrue);
        expect(robot.earnedRewards, Sats.fromInt(1500));
        expect(robot.wantsStealth, isFalse);
        expect(robot.activeOrderId, 4242);
        expect(robot.lastOrderId, isNull);
        // Nothing was held on this device: the pair the token proved is the one the coordinator holds, still locked.
        expect(robot.pgpKeyProven, isTrue);
        expect(robot.pgpKey, _key);
        expect(robot.pgpKey, isNot(same(_key)));
      },
    );

    test('is read the same way from a first contact it ignores', () async {
      serveJson(_robot({'found': true, 'last_order_id': 77}));
      final robot = _sent(await fetch());

      expect(robot.found, isTrue);
      expect(robot.activeOrderId, isNull);
      expect(robot.lastOrderId, 77);
    });

    test('that the coordinator does not know is a typed failure', () async {
      serveJson(_error(7001), statusCode: 400);

      expect(expectErr(await fetchKnown()), isA<RobotUnknown>());
    });

    test(
      'created elsewhere with another key pair of its token is proven, then taken',
      () async {
        // What a coordinator returns to a device that restored a Garage Key: the key pair of the first device, locked by the same token.
        final other = expectOk(
          RobotPgpKey.generateWith(
            _identity,
            now: interopNow,
            random: DeterministicRandom('another device'),
          ),
        );
        expect(other, isNot(_key));
        serveJson(
          _robot({
            'found': true,
            'public_key': other.publicKey.armored,
            'encrypted_private_key': other.encryptedPrivateKeyArmored,
          }),
        );

        final contact = _unproven(await fetch());
        final read = expectOk(await fetchKnown());
        for (final robot in [
          expectOk(contact.prove()),
          expectOk(read.prove()),
        ]) {
          expect(robot.pgpKey, other);
          expect(robot.pgpKeyProven, isTrue);
          expect(robot.found, isTrue);
        }
        // Proving again gives the same robot.
        expect(expectOk(read.prove()).pgpKey, other);
      },
    );
  });

  group('the key pair of an answer', () {
    test('equal to the pair sent is taken as it is, and nothing proves it', () async {
      // A pair the token of this robot does not unlock, as a caller that sends the pair of another robot would send: it comes back as sent, and is taken without unlocking anything.
      // `FetchRobotUsecase` of the app makes the pair of each first contact itself, for that robot, for this reason.
      final crafted = CraftedKey(label: 'sent', userId: _identity.pgpUserId);
      final notTheToken = crafted.privateArmored('not the token');
      final sent = expectOk(
        RobotPgpKey.parse(
          publicKey: crafted.publicArmored,
          encryptedPrivateKey: notTheToken,
        ),
      );
      serveJson(
        _robot({
          'public_key': crafted.publicArmored,
          'encrypted_private_key': notTheToken,
        }),
      );

      final robot = _sent(await fetch(pgpKey: sent));
      expect(robot.pgpKey, same(sent));
      expect(robot.pgpKeyProven, isFalse);
      // Read back with the short header, which sends nothing, the same pair must be proven, and is not.
      expect(
        expectErr(_settled(await fetchKnown())),
        isA<RobotPgpKeyNotProven>(),
      );
    });

    test('another than the pair sent is proven before it is taken', () async {
      final crafted = CraftedKey(label: 'sent', userId: _identity.pgpUserId);
      final sent = expectOk(
        RobotPgpKey.parse(
          publicKey: crafted.publicArmored,
          encryptedPrivateKey: crafted.privateArmored(_identity.token.reveal()),
        ),
      );
      // The same keys locked again by the token: other packets, so another pair than the one sent, which the token proves.
      final lockedAgain = _lockedWith(
        crafted,
        _identity.token.reveal(),
        counts: [97, 97],
      );
      serveJson(
        _robot({
          'public_key': crafted.publicArmored,
          'encrypted_private_key': lockedAgain,
        }),
      );

      final robot = expectOk(_unproven(await fetch(pgpKey: sent)).prove());
      expect(robot.pgpKeyProven, isTrue);
      expect(robot.pgpKey, isNot(sent));
      expect(robot.pgpKey.publicKey, sent.publicKey);
      expect(
        robot.pgpKey.encryptedPrivateKeyArmored,
        armorEncode(
          ArmorBlock.privateKey,
          armorDecode(ArmorBlock.privateKey, lockedAgain) ?? fail('armor'),
        ),
      );

      // Locked again by anything but the token, it is not proven.
      serveJson(
        _robot({
          'public_key': crafted.publicArmored,
          'encrypted_private_key': _lockedWith(
            crafted,
            'not the token',
            counts: [97, 97],
          ),
        }),
      );
      expect(
        expectErr(_settled(await fetch(pgpKey: sent))),
        isA<RobotPgpKeyNotProven>(),
      );
    });

    test(
      'of the test robots of the RoboSats repository is proven by their own tokens',
      () async {
        // Made by the official client with OpenPGP.js, the public key re-exported by GnuPG, each locked by the public token of its robot.
        for (final number in [1, 2, 3]) {
          final identity = repositoryRobotIdentity(number);
          serveJson(
            _robotOf(
              identity,
              publicKey: repositoryRobotFile(number, 'pub_key'),
              encryptedPrivateKey: repositoryRobotFile(number, 'enc_priv_key'),
            ),
          );

          final robot = expectOk(
            expectOk(await fetchKnown(identity: identity)).prove(),
          );
          expect(robot.hashId, identity.hashId, reason: 'robot $number');
          expect(robot.pgpKeyProven, isTrue);
          // Re-encoded from the packets the proof checked: the same key, by its fingerprints.
          expect(robot.pgpKey.publicKey, repositoryRobotKey(number).publicKey);
        }
      },
    );

    test('locked by the token of another robot is not proven', () async {
      // The official pair of each test robot, answered for the next one: right hash id and nickname, but a pair that robot's token does not unlock.
      for (final (owner, reader) in [(1, 2), (2, 3), (3, 1)]) {
        final identity = repositoryRobotIdentity(reader);
        serveJson(
          _robotOf(
            identity,
            publicKey: repositoryRobotFile(owner, 'pub_key'),
            encryptedPrivateKey: repositoryRobotFile(owner, 'enc_priv_key'),
          ),
        );

        expect(
          expectErr(_settled(await fetchKnown(identity: identity))),
          isA<RobotPgpKeyNotProven>(),
          reason: 'pair of robot $owner for robot $reader',
        );
      }
      // And the pair of this robot answered for the peer robot.
      serveJson(
        _robotOf(
          interopPeerIdentity,
          publicKey: _reexportedPublicKey,
          encryptedPrivateKey: _key.encryptedPrivateKeyArmored,
        ),
      );
      expect(
        expectErr(_settled(await fetchKnown(identity: interopPeerIdentity))),
        isA<RobotPgpKeyNotProven>(),
      );
    });

    test(
      'that hashes the bound in all is proven, and a pair over it is refused before any hashing',
      () async {
        final crafted = CraftedKey(label: 'bound', userId: _identity.pgpUserId);
        final token = _identity.token.reveal();

        // Coded count 239 is 32 505 856 bytes: two parts of it are the bound exactly.
        expect(s2kByteCount(239) * 2, PgpLimits.proofHashedBytes);
        final watch = Stopwatch();
        serveJson(
          _robot({
            'public_key': crafted.publicArmored,
            'encrypted_private_key': _lockedWith(
              crafted,
              token,
              counts: [239, 239],
            ),
          }),
        );
        final atBound = expectOk(await fetchKnown());
        watch.start();
        expectOk(atBound.prove());
        final atBoundTime = watch.elapsed;

        // Each locked by the token, so that only the bound can refuse them: one count over in one part, and the costliest pair the format allows, SHA-1 with AES-256 at the largest count, which hashes each part twice.
        for (final over in [
          _lockedWith(crafted, token, counts: [239, 240]),
          _lockedWith(crafted, token, counts: [240, 239]),
          _lockedWith(
            crafted,
            token,
            counts: [255, 255],
            s2kHashId: HashId.sha1,
          ),
        ]) {
          serveJson(
            _robot({
              'public_key': crafted.publicArmored,
              'encrypted_private_key': over,
            }),
          );
          final unproven = expectOk(await fetchKnown());
          watch
            ..reset()
            ..start();
          expect(expectErr(unproven.prove()), isA<RobotPgpKeyNotProven>());
          // Refused before hashing: well under a tenth of the time the pair at the bound took.
          expect(watch.elapsed * 10, lessThan(atBoundTime));
        }
      },
    );

    test(
      'counts both passes of an S2K whose digest is shorter than the key',
      () async {
        final crafted = CraftedKey(
          label: 'passes',
          userId: _identity.pgpUserId,
        );
        final token = _identity.token.reveal();
        Future<Result<CoordinatorRobot, CoordinatorFailure>> proofOf(
          String encryptedPrivateKey,
        ) async {
          serveJson(
            _robot({
              'public_key': crafted.publicArmored,
              'encrypted_private_key': encryptedPrivateKey,
            }),
          );
          return _settled(await fetchKnown());
        }

        // The parameters of the official client, two parts of 16 MiB: proven.
        expectOk(
          await proofOf(_lockedWith(crafted, token, counts: [224, 224])),
        );
        // SHA-1 with AES-128, one pass each: proven.
        expectOk(
          await proofOf(
            _lockedWith(
              crafted,
              token,
              counts: [224, 224],
              s2kHashId: HashId.sha1,
              cipherId: CipherId.aes128,
            ),
          ),
        );
        // The same count with SHA-1 and AES-256 hashes each part twice, 64 MiB in all: over the bound.
        expect(
          expectErr(
            await proofOf(
              _lockedWith(
                crafted,
                token,
                counts: [224, 224],
                s2kHashId: HashId.sha1,
              ),
            ),
          ),
          isA<RobotPgpKeyNotProven>(),
        );
      },
    );

    test(
      'GnuPG protected at its largest count is over the bound, though its token unlocks it',
      () async {
        // `pgp_interop_test.dart` unlocks it with this token: S2K count 255, SHA-1, AES-128, 62 MiB per part.
        final identity = interopPeerIdentity;
        serveJson(
          _robotOf(
            identity,
            publicKey: interopFile('gpg_protected_pub_key'),
            encryptedPrivateKey: interopFile('gpg_protected_enc_priv_key'),
          ),
        );

        expect(
          expectErr(_settled(await fetchKnown(identity: identity))),
          isA<RobotPgpKeyNotProven>(),
        );
      },
    );

    test(
      'of armor at the bound is read, and keeps only its canonical form',
      () async {
        // Armor headers pad each block to the bound: they are dropped, so a pair a coordinator padded never grows what this device holds or sends.
        String padded(String armored) {
          final lines = armored.trim().split('\n');
          const header = 'Comment: ';
          final room =
              PgpLimits.keyArmorChars -
              armored.trim().length -
              1 -
              header.length;
          return [
            lines.first,
            '$header${'x' * room}',
            ...lines.skip(1),
          ].join('\n');
        }

        final publicKey = padded(_reexportedPublicKey);
        final encryptedPrivateKey = padded(_key.encryptedPrivateKeyArmored);
        expect(publicKey.length, PgpLimits.keyArmorChars);
        expect(encryptedPrivateKey.length, PgpLimits.keyArmorChars);
        serveJson(
          _robot({
            'public_key': publicKey,
            'encrypted_private_key': encryptedPrivateKey,
          }),
        );

        final sent = _sent(await fetch());
        final proven = expectOk(expectOk(await fetchKnown()).prove());
        for (final robot in [sent, proven]) {
          expect(robot.pgpKey, _key);
          expect(robot.pgpKey.publicKey.armored, isNot(contains('Comment')));
          expect(
            robot.pgpKey.encryptedPrivateKeyArmored,
            _key.encryptedPrivateKeyArmored,
          );
        }
      },
    );

    test('of armor over the bound is malformed, on both requests', () async {
      for (final field in ['public_key', 'encrypted_private_key']) {
        serveJson(_robot({field: '${_robot()[field]}${'\n' * 20000}'}));

        for (final result in [await fetch(), await fetchKnown()]) {
          expect(
            expectErr(result),
            isA<CoordinatorResponseMalformed>().having(
              (f) => f.field,
              'field',
              field,
            ),
          );
        }
      }
    });

    test('prints neither the token, nor its hash, nor a key', () async {
      final other = expectOk(
        RobotPgpKey.generateWith(
          _identity,
          now: interopNow,
          random: DeterministicRandom('another device'),
        ),
      );
      serveJson(
        _robot({
          'public_key': other.publicKey.armored,
          'encrypted_private_key': other.encryptedPrivateKeyArmored,
        }),
      );
      final unproven = _unproven(await fetch());
      final robot = expectOk(unproven.prove());
      serveJson(
        _robot({
          'public_key': other.publicKey.armored,
          'encrypted_private_key':
              generateInteropPeerKey().encryptedPrivateKeyArmored,
        }),
      );
      final refused = expectErr(_settled(await fetch()));

      expect(
        '$unproven',
        'UnprovenCoordinatorRobot(temple, ${_identity.nickname})',
      );
      expect(
        '$robot',
        'CoordinatorRobot(temple, ${_identity.nickname}, found: false)',
      );
      expect('${robot.pgpKey}', 'RobotPgpKey(${other.publicKey.fingerprint})');
      expect(refused, isA<RobotPgpKeyNotProven>());
      final secrets = [
        _identity.token.reveal(),
        _identity.tokenSha256Hex,
        _identity.tokenSha256Base91,
        // A line of base64 from each block.
        other.publicKey.armored.split('\n')[2],
        other.encryptedPrivateKeyArmored.split('\n')[2],
        other.encryptedPrivateKeyArmored.split('\n')[5],
      ];
      for (final printed in [
        '$unproven',
        '$robot',
        '${robot.pgpKey}',
        '$refused',
        '${robot.pgpKey.publicKey}',
      ]) {
        expect(printed, isNot(contains('PGP')));
        for (final secret in secrets) {
          expect(printed, isNot(contains(secret)));
        }
      }
    });
  });

  group('the Nostr key the coordinator holds', () {
    Future<CoordinatorRobot> withKey(Object? key) async {
      serveJson(_robot({'nostr_pubkey': key}));
      return _sent(await fetch());
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
    /// The failure of both requests, a first contact and a read, the pair proven when it is to be proven.
    Future<List<CoordinatorFailure>> failures({RobotPgpKey? sent}) async => [
      expectErr(_settled(await fetch(pgpKey: sent))),
      expectErr(_settled(await fetchKnown())),
    ];

    test('by its hash id', () async {
      serveJson(_robot({'hash_id': interopPeerIdentity.hashId.hex}));

      expect(await failures(), everyElement(isA<RobotHashIdMismatch>()));
    });

    test('by its hash id, whatever the nickname says', () async {
      serveJson(
        _robot({
          'hash_id': interopPeerIdentity.hashId.hex,
          'nickname': interopPeerIdentity.nickname,
        }),
      );

      expect(await failures(), everyElement(isA<RobotHashIdMismatch>()));
    });

    test('by the case of its hash id', () async {
      serveJson(_robot({'hash_id': _identity.hashId.hex.toUpperCase()}));

      expect(await failures(), everyElement(isA<RobotHashIdMismatch>()));
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
          await failures(),
          everyElement(isA<RobotNicknameMismatch>()),
          reason: nickname,
        );
      }
    });

    test('by its hash id or its nickname before any key is read', () async {
      // A wrong hash id or nickname with a key that is not even a key, or the right pair of this robot: the answer is about another robot, and nothing of it is parsed or proven.
      for (final (publicKey, privateKey) in [
        ('not a key', 'not a key'),
        ('', ''),
        ('A' * 20000, 'A' * 20000),
        (_reexportedPublicKey, _key.encryptedPrivateKeyArmored),
      ]) {
        serveJson(
          _robot({
            'hash_id': interopPeerIdentity.hashId.hex,
            'public_key': publicKey,
            'encrypted_private_key': privateKey,
          }),
        );
        expect(await failures(), everyElement(isA<RobotHashIdMismatch>()));

        serveJson(
          _robot({
            'nickname': interopPeerIdentity.nickname,
            'public_key': publicKey,
            'encrypted_private_key': privateKey,
          }),
        );
        expect(await failures(), everyElement(isA<RobotNicknameMismatch>()));
      }
    });

    test('by a key pair the coordinator made for the same hash id', () async {
      // A dishonest coordinator can name a key of its own after the robot and lock it with anything but the token, which it never sees.
      final forged = CraftedKey(label: 'forged', userId: _identity.pgpUserId);
      serveJson(
        _robot({
          'public_key': forged.publicArmored,
          'encrypted_private_key': forged.privateArmored('a passphrase'),
        }),
      );

      expect(await failures(), everyElement(isA<RobotPgpKeyNotProven>()));
      // Locked by the token hash, the credential every request sends, it is not proven either.
      serveJson(
        _robot({
          'public_key': forged.publicArmored,
          'encrypted_private_key': forged.privateArmored(
            _identity.tokenSha256Base91,
          ),
        }),
      );
      expect(await failures(), everyElement(isA<RobotPgpKeyNotProven>()));
    });

    test(
      'by the public key alone, the private key being the right one',
      () async {
        serveJson(
          _robot({'public_key': generateInteropPeerKey().publicKey.armored}),
        );

        // Two blocks of two keys: refused when read, before any proof.
        expect(expectErr(await fetch()), isA<RobotPgpKeyNotProven>());
        expect(expectErr(await fetchKnown()), isA<RobotPgpKeyNotProven>());
      },
    );

    test('by the private key of another pair', () async {
      serveJson(
        _robot({
          'encrypted_private_key':
              generateInteropPeerKey().encryptedPrivateKeyArmored,
        }),
      );

      expect(expectErr(await fetch()), isA<RobotPgpKeyNotProven>());
      expect(expectErr(await fetchKnown()), isA<RobotPgpKeyNotProven>());
    });

    test('by a public key with another encryption subkey', () async {
      final own = CraftedKey();
      // The same primary key certifies another subkey: chat messages would be encrypted to it.
      final otherSubkey = CraftedKey(
        subkeyPoint: x25519PublicKey(CraftedKey(label: 'other').scalar),
      );
      final token = _identity.token.reveal();
      final local = expectOk(
        RobotPgpKey.parse(
          publicKey: own.publicArmored,
          encryptedPrivateKey: own.privateArmored(token),
        ),
      );
      expect(otherSubkey.publicKey, isNot(own.publicKey));
      expect(otherSubkey.publicKey.fingerprint, own.publicKey.fingerprint);
      // The private key is the one sent, locked by the token: only the public key differs.
      serveJson(
        _robot({
          'public_key': otherSubkey.publicArmored,
          'encrypted_private_key': own.privateArmored(token),
        }),
      );

      expect(
        await failures(sent: local),
        everyElement(isA<RobotPgpKeyNotProven>()),
      );
    });

    test('by another primary key that binds the subkey of this device', () async {
      // A coordinator can make a primary key of its own and bind the encryption subkey of the robot under it: the subkey alone proves nothing.
      final own = CraftedKey();
      final token = _identity.token.reveal();
      final local = expectOk(
        RobotPgpKey.parse(
          publicKey: own.publicArmored,
          encryptedPrivateKey: own.privateArmored(token),
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
          'encrypted_private_key': own.privateArmored(token),
        }),
      );

      expect(
        await failures(sent: local),
        everyElement(isA<RobotPgpKeyNotProven>()),
      );
    });

    test('by a public key of a kind this package does not read', () async {
      final unsupported = CraftedKey(kdf: const [3, 1, 1, 2]).publicArmored;
      expect(
        expectErr(PgpPublicKey.parse(unsupported)),
        isA<PgpKeyUnsupported>(),
      );
      serveJson(_robot({'public_key': unsupported}));

      expect(expectErr(await fetch()), isA<RobotPgpKeyNotProven>());
      expect(expectErr(await fetchKnown()), isA<RobotPgpKeyNotProven>());
    });

    test('by a private key of a kind this package does not read', () async {
      // Not passphrase-protected (S2K usage 0): nothing locks it, so nothing can prove it.
      final crafted = CraftedKey(label: 'open', userId: _identity.pgpUserId);
      final open = armorPackets(
        ArmorBlock.privateKey,
        crafted.privatePackets(
          _identity.token.reveal(),
          protect: (secret, passphrase) =>
              protectSecret(secret, passphrase, usage: 0),
        ),
      );
      serveJson(
        _robot({
          'public_key': crafted.publicArmored,
          'encrypted_private_key': open,
        }),
      );

      expect(expectErr(await fetch()), isA<RobotPgpKeyNotProven>());
      expect(expectErr(await fetchKnown()), isA<RobotPgpKeyNotProven>());
    });

    test(
      'by secret values that are not those of its public key, though the token unlocks them',
      () async {
        // The token unlocks both parts, but the primary key's part holds the seed of another key: unlocking checks the values against the points.
        final crafted = CraftedKey(
          label: 'values',
          userId: _identity.pgpUserId,
        );
        final otherSeed = CraftedKey(label: 'other values').seed;
        final wrongValues = armorPackets(
          ArmorBlock.privateKey,
          crafted.privatePackets(
            _identity.token.reveal(),
            primarySecret: mpiEncode(otherSeed),
          ),
        );
        serveJson(
          _robot({
            'public_key': crafted.publicArmored,
            'encrypted_private_key': wrongValues,
          }),
        );

        expect(await failures(), everyElement(isA<RobotPgpKeyNotProven>()));
      },
    );
  });

  group('a key pair the coordinator locked itself', () {
    final token = _identity.token.reveal();
    // What every request gives the coordinator: the SHA-256 of the token.
    final tokenHash = Uint8List.fromList(hex.decode(_identity.tokenSha256Hex));

    test('a simple S2K over SHA-256 of the token is the token hash itself', () {
      expect(sha256.convert(utf8.encode(token)).bytes, tokenHash);
    });

    test(
      'under the token hash, with a simple or a salted S2K, is not proven',
      () async {
        // A coordinator that accepted such a key would have a pair of its own proven, from what every request sends it: the parser refuses these S2K, and the proof checks it again.
        final forged = CraftedKey(
          label: 'coordinator-own',
          userId: _identity.pgpUserId,
        );
        for (final s2kType in [0, 1]) {
          serveJson(
            _robot({
              'public_key': forged.publicArmored,
              'encrypted_private_key': armorPackets(
                ArmorBlock.privateKey,
                forged.privatePackets(
                  'unused',
                  protect: (secret, _) =>
                      protectSecretWithKey(secret, tokenHash, s2kType: s2kType),
                ),
              ),
            }),
          );

          for (final result in [
            _settled(await fetch()),
            _settled(await fetchKnown()),
          ]) {
            expect(
              expectErr(result),
              isA<RobotPgpKeyNotProven>(),
              reason: 'S2K type $s2kType',
            );
          }
        }
      },
    );

    test('each of the two parts must unlock with the token', () async {
      final key = CraftedKey(label: 'halves', userId: _identity.pgpUserId);
      String lockedPerPart(List<String> passphrases) {
        var part = 0;
        return armorPackets(
          ArmorBlock.privateKey,
          key.privatePackets(
            'unused',
            protect: (secret, _) => protectSecret(secret, passphrases[part++]),
          ),
        );
      }

      serveJson(
        _robot({
          'public_key': key.publicArmored,
          'encrypted_private_key': lockedPerPart([token, token]),
        }),
      );
      expectOk(_settled(await fetchKnown()));
      for (final passphrases in [
        // The primary key's part by the token, the subkey's by anything else.
        [token, 'not the token'],
        // The reverse.
        ['not the token', token],
      ]) {
        serveJson(
          _robot({
            'public_key': key.publicArmored,
            'encrypted_private_key': lockedPerPart(passphrases),
          }),
        );

        expect(
          expectErr(_settled(await fetchKnown())),
          isA<RobotPgpKeyNotProven>(),
          reason: '$passphrases'.replaceAll(token, 'token'),
        );
      }
    });

    test('a genuine secret moved to the other part is not proven', () async {
      // The token unlocks both parts, but each holds the value of the other key.
      final key = CraftedKey(label: 'moved', userId: _identity.pgpUserId);
      for (final packets in [
        key.privatePackets(token, subkeySecret: mpiEncode(key.seed)),
        key.privatePackets(
          token,
          primarySecret: mpiEncode(key.scalar.reversed.toList()),
        ),
      ]) {
        serveJson(
          _robot({
            'public_key': key.publicArmored,
            'encrypted_private_key': armorPackets(
              ArmorBlock.privateKey,
              packets,
            ),
          }),
        );

        expect(
          expectErr(_settled(await fetchKnown())),
          isA<RobotPgpKeyNotProven>(),
        );
      }
    });
  });

  group('what « proven » covers', () {
    final token = _identity.token.reveal();

    test(
      'a proven pair keeps only what the proof checked: no foreign packet, no second key',
      () async {
        final key = CraftedKey(label: 'carried', userId: _identity.pgpUserId);
        final attacker = CraftedKey(label: 'attacker');
        final foreignUserId = (
          tag: PacketTag.userId,
          body: Uint8List.fromList(utf8.encode('coordinator was here')),
        );
        serveJson(
          _robot({
            'public_key': armorPackets(ArmorBlock.publicKey, [
              ...key.publicPackets,
              foreignUserId,
              // A whole second key, the coordinator's own.
              ...attacker.publicPackets,
            ]),
            'encrypted_private_key': armorPackets(ArmorBlock.privateKey, [
              ...key.privatePackets(token),
              foreignUserId,
              // And its secret, unprotected.
              (
                tag: PacketTag.secretKey,
                body: Uint8List.fromList([
                  ...attacker.primaryBody,
                  ...unprotectedSecret(mpiEncode(attacker.seed)),
                ]),
              ),
              (
                tag: PacketTag.userId,
                body: Uint8List.fromList(attacker.userId),
              ),
              (tag: PacketTag.signature, body: attacker.certification),
            ]),
          }),
        );

        final robot = expectOk(_settled(await fetchKnown()));

        expect(robot.pgpKeyProven, isTrue);
        expect(robot.pgpKey.publicKey.armored, key.publicArmored);
        expect(
          robot.pgpKey.encryptedPrivateKeyArmored,
          key.privateArmored(token),
        );
        expect(
          packetsOf(ArmorBlock.publicKey, robot.pgpKey.publicKey.armored),
          hasLength(5),
        );
        expect(
          packetsOf(
            ArmorBlock.privateKey,
            robot.pgpKey.encryptedPrivateKeyArmored,
          ),
          hasLength(5),
        );
        // What the robot holds is bounded by the key its owner made, not by what the coordinator padded the blocks with.
        expect(robot.pgpKey.publicKey.armored.length, lessThan(1000));
        expect(robot.pgpKey.encryptedPrivateKeyArmored.length, lessThan(1000));
      },
    );

    test(
      'pgpKeyProven is the coordinator\'s word: the pair just sent, framed another way, comes back proven',
      () async {
        final key = CraftedKey(label: 'reframed', userId: _identity.pgpUserId);
        final sent = expectOk(
          RobotPgpKey.parse(
            publicKey: key.publicArmored,
            encryptedPrivateKey: key.privateArmored(token),
          ),
        );
        // The same packets with old-format headers: other bytes, so not « the pair sent ».
        final reframed = BytesBuilder();
        for (final packet in key.privatePackets(token)) {
          reframed
            ..addByte(0x80 | (packet.tag << 2) | 1)
            ..add(u16Bytes(packet.body.length))
            ..add(packet.body);
        }
        serveJson(
          _robot({
            'public_key': key.publicArmored,
            'encrypted_private_key': armorEncode(
              ArmorBlock.privateKey,
              reframed.takeBytes(),
            ),
          }),
        );

        final robot = expectOk(_unproven(await fetch(pgpKey: sent)).prove());

        // It says the robot existed with another pair, though it is the pair sent: no screen may rely on it alone.
        expect(robot.pgpKeyProven, isTrue);
        expect(robot.pgpKey, sent);
      },
    );

    test(
      'a coordinator can hand back any genuine pair of the robot, another at each read',
      () async {
        // Two pairs the token holder made, as two first contacts of this device would leave.
        final one = CraftedKey(label: 'pair one', userId: _identity.pgpUserId);
        final two = CraftedKey(label: 'pair two', userId: _identity.pgpUserId);
        final robots = <CoordinatorRobot>[];
        for (final key in [one, two, one]) {
          serveJson(
            _robot({
              'public_key': key.publicArmored,
              'encrypted_private_key': key.privateArmored(token),
            }),
          );
          robots.add(expectOk(_settled(await fetchKnown())));
        }

        // Each is proven: « proven » says who made a pair, not which pair the coordinator stored first or will check signatures with.
        final [first, second, third] = robots;
        expect(first.pgpKey.publicKey, one.publicKey);
        expect(second.pgpKey.publicKey, two.publicKey);
        expect(third.pgpKey.publicKey, one.publicKey);
        expect(first.pgpKey.publicKey, isNot(second.pgpKey.publicKey));
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
      'is rejected when the private key is not an armored private key',
      () async {
        // The private key of another pair is a well-formed key: it is a pair not proven, in `a robot that is not the one of this device`.
        for (final key in [
          '',
          'not a key',
          _reexportedPublicKey,
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

      _sent(await fetch());
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

      // The pair of the read is the one the first contact sent, so it is taken without a proof.
      final robot = _sent(await fetch());

      expect(robot.hashId, _identity.hashId);
      expect(robot.pgpKey, same(_key));
      expect(transport.requests, hasLength(2));
    });

    test(
      'of a nickname taken by this robot with another pair gives the pair to prove',
      () async {
        final other = expectOk(
          RobotPgpKey.generateWith(
            _identity,
            now: interopNow,
            random: DeterministicRandom('another device'),
          ),
        );
        transport.route(temple, _testnet, '/api/robot/', (request) async {
          final firstContact = (request.headers['Authorization'] ?? '')
              .contains(' | ');
          return Ok(
            firstContact
                ? jsonResponse(_error(7004), statusCode: 409)
                : jsonResponse(
                    _robot({
                      'public_key': other.publicKey.armored,
                      'encrypted_private_key': other.encryptedPrivateKeyArmored,
                    }),
                  ),
          );
        });

        final robot = expectOk(_unproven(await fetch()).prove());

        expect(robot.pgpKey, other);
        expect(robot.pgpKeyProven, isTrue);
      },
    );

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
          Future<Result<CoordinatorRobotAnswer, CoordinatorFailure>> Function()
        >{'a first contact': fetch, 'a read of a known robot': fetchKnown};

    for (final MapEntry(key: label, value: call) in calls.entries) {
      test('$label passes transport failures through', () async {
        for (final failure in const <CoordinatorTransportFailure>[
          CoordinatorUnreachable(),
          CoordinatorTimedOut(),
          CoordinatorResponseTooLarge(),
          CoordinatorTransportBusy(),
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
