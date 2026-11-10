import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

RobotIdentity _identity(String token) => switch (RobotToken.parse(token)) {
  Err(:final failure) => fail('expected a valid token, got $failure'),
  Ok(value: final parsed) => switch (RobotIdentity.fromToken(parsed)) {
    Ok(:final value) => value,
    Err(:final failure) => fail('expected an identity, got $failure'),
  },
};

/// The armored PGP keys of `tests/robots/1/` in the RoboSats repository (commit ff1998c), copied verbatim: public test material whose passphrase is the public test token.
String _robot1Key(String name) =>
    File('test/fixtures/robosats_tests_robot_1/$name').readAsStringSync();

void main() {
  for (final MapEntry(key: label, value: robot) in allRobots.entries) {
    group('RobotIdentity of $label', () {
      final identity = _identity(robot['token'] as String);

      test('hashes the UTF-8 token once for the coordinator', () {
        expect(identity.tokenSha256Hex, robot['sha256_hex']);
        expect(
          identity.tokenSha256Hex,
          robot['websocket_query_token_sha256_hex'],
        );
        expect(identity.tokenSha256Base91, robot['token_sha256_base91']);
        expect(
          identity.tokenSha256Base91.length,
          robot['token_sha256_base91_length'],
        );
      });

      test('hashes the hexadecimal string again for the hash id', () {
        expect(identity.hashId.hex, robot['hash_id']);
        expect(identity.pgpUserId, robot['pgp_user_id']);
      });

      test('derives the nickname the coordinator assigns', () {
        expect(identity.nickname, robot['nickname']);
        expect(identity.nickname, robot['nickname_reference_python']);
      });

      test('derives the Nostr key of the current frontend by default', () {
        final pair = identity.nostrKeyPair();
        expect(pair, identity.nostrKeyPair(NostrKeyDerivation.currentFrontend));
        expect(hex.encode(pair.revealSecretKey()), robot['nostr_seckey_hex']);
        expect(pair.publicKeyHex, robot['nostr_pubkey_hex']);
        expect(
          pair.revealSecretKey(),
          sha256.convert(hex.decode(robot['sha512_hex'] as String)).bytes,
        );
      });

      test('derives the Nostr key of the repository fixtures on request', () {
        final pair = identity.nostrKeyPair(
          NostrKeyDerivation.repositoryFixtures,
        );
        expect(
          hex.encode(pair.revealSecretKey()),
          robot['legacy_nostr_seckey_sha256_token_hex'],
        );
        expect(
          pair.publicKeyHex,
          robot['legacy_nostr_pubkey_sha256_token_hex'],
        );
        expect(pair, isNot(identity.nostrKeyPair()));
      });

      test('builds the Authorization value of subsequent requests', () {
        expect(
          identity.authorizationHeader(),
          robot['authorization_header_short'],
        );
      });

      final fromRepository = robot['expected_from_robosats_repo'];
      if (fromRepository is Map) {
        test('matches the files of the RoboSats repository', () {
          expect(identity.tokenSha256Base91, fromRepository['b91_token']);
          expect(identity.nickname, fromRepository['nickname']);
          expect(
            identity
                .nostrKeyPair(NostrKeyDerivation.repositoryFixtures)
                .publicKeyHex,
            fromRepository['nostr_pubkey'],
          );
          expect(
            identity.nostrKeyPair().publicKeyHex,
            isNot(fromRepository['nostr_pubkey']),
            reason: 'the open question: current frontend and fixtures differ',
          );
        });
      }
    });
  }

  group('RobotIdentity of test robot 1', () {
    test('has the user id found in its PGP key by GnuPG', () {
      final pgpKey = vectors['cle_pgp_reference_robot_1'] as Map;
      expect(
        _identity(repositoryRobots.first['token'] as String).pgpUserId,
        pgpKey['user_id'],
      );
    });
  });

  group('RobotIdentity from a Garage Key', () {
    test('chains key, index, token and identity', () {
      final key =
          (GarageKey.parse(garageKeyVector['garage_key'] as String)
                  as Ok<GarageKey, GarageKeyFailure>)
              .value;
      for (final robot in [...garageKeyRobots, base91ShortRobot]) {
        final token =
            (key.deriveToken(robot['account_index'] as int)
                    as Ok<RobotToken, RobosatsFailure>)
                .value;
        final identity =
            (RobotIdentity.fromToken(token)
                    as Ok<RobotIdentity, NicknameUnavailable>)
                .value;
        expect(identity.token, token);
        expect(identity.tokenSha256Base91, robot['token_sha256_base91']);
        expect(identity.hashId.hex, robot['hash_id']);
        expect(identity.nickname, robot['nickname']);
        expect(identity.nostrKeyPair().publicKeyHex, robot['nostr_pubkey_hex']);
      }
    });
  });

  group('first-contact Authorization value', () {
    final robot = repositoryRobots.first;
    final identity = _identity(robot['token'] as String);
    final publicKey = _robot1Key('pub_key');
    final privateKey = _robot1Key('enc_priv_key');

    test('matches the reference example built from test robot 1', () {
      expect(
        identity.firstContactAuthorizationHeader(
          pgpPublicKey: publicKey,
          pgpEncryptedPrivateKey: privateKey,
        ),
        firstContactHeaderExample,
      );
    });

    test('has the four parts the coordinator requires', () {
      final value = identity.firstContactAuthorizationHeader(
        pgpPublicKey: publicKey,
        pgpEncryptedPrivateKey: privateKey,
      );
      // `robosats/middleware.py:53-59` splits on " | " and requires exactly four parts.
      final parts = value.split(' | ');
      expect(parts, hasLength(4));
      expect(parts[0], identity.authorizationHeader());
      expect(
        parts[1],
        startsWith('Public -----BEGIN PGP PUBLIC KEY BLOCK-----'),
      );
      expect(
        parts[2],
        startsWith('Private -----BEGIN PGP PRIVATE KEY BLOCK-----'),
      );
      expect(parts[3], 'Nostr ${robot['nostr_pubkey_hex']}');
      expect(value, isNot(contains('\n')));
      expect(value, isNot(contains('\r')));
      // `api/utils.py:525-526` turns the backslashes back into line feeds.
      expect(
        parts[1].substring('Public '.length).replaceAll(r'\', '\n'),
        publicKey,
      );
      expect(
        parts[2].substring('Private '.length).replaceAll(r'\', '\n'),
        privateKey,
      );
    });

    test('normalises CRLF and lone CR line endings like the client', () {
      for (final lineEnding in ['\r\n', '\r']) {
        expect(
          identity.firstContactAuthorizationHeader(
            pgpPublicKey: publicKey.replaceAll('\n', lineEnding),
            pgpEncryptedPrivateKey: privateKey.replaceAll('\n', lineEnding),
          ),
          firstContactHeaderExample,
          reason: jsonEncode(lineEnding),
        );
      }
    });

    test('can carry the Nostr key of the repository fixtures instead', () {
      final value = identity.firstContactAuthorizationHeader(
        pgpPublicKey: publicKey,
        pgpEncryptedPrivateKey: privateKey,
        nostrKeyDerivation: NostrKeyDerivation.repositoryFixtures,
      );
      final expected = robot['expected_from_robosats_repo'] as Map;
      expect(value, endsWith(' | Nostr ${expected['nostr_pubkey']}'));
      expect(
        value.substring(0, value.lastIndexOf(' | Nostr ')),
        firstContactHeaderExample.substring(
          0,
          firstContactHeaderExample.lastIndexOf(' | Nostr '),
        ),
      );
    });

    test('treats the PGP keys as opaque strings', () {
      expect(
        identity.firstContactAuthorizationHeader(
          pgpPublicKey: 'a\nb',
          pgpEncryptedPrivateKey: '',
        ),
        '${identity.authorizationHeader()} | Public a\\b | Private  | Nostr ${robot['nostr_pubkey_hex']}',
      );
    });
  });

  group('RobotIdentity secrecy and equality', () {
    final robot = repositoryRobots.first;
    final identity = _identity(robot['token'] as String);

    test('prints only public values', () {
      final text = '$identity ${[identity]} ${identity.nostrKeyPair()}';
      for (final secret in [
        'token',
        'sha256_hex',
        'token_sha256_base91',
        'nostr_seckey_hex',
        'legacy_nostr_seckey_sha256_token_hex',
      ]) {
        expect(text, isNot(contains(robot[secret] as String)), reason: secret);
      }
      expect(text, contains(robot['nickname'] as String));
      expect(text, contains(robot['hash_id'] as String));
    });

    test('has value equality on the token', () {
      expect(identity, _identity(robot['token'] as String));
      expect(identity.hashCode, _identity(robot['token'] as String).hashCode);
      expect(
        identity,
        isNot(_identity(repositoryRobots[1]['token'] as String)),
      );
    });
  });
}
