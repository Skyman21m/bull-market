import 'dart:math';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

final String _exampleKey = garageKeyVector['garage_key'] as String;

GarageKey _key(String encoded) => switch (GarageKey.parse(encoded)) {
  Ok(:final value) => value,
  Err(:final failure) => fail('expected a valid Garage Key, got $failure'),
};

GarageKeyFailure _rejection(String encoded) =>
    switch (GarageKey.parse(encoded)) {
      Ok() => fail('expected "$encoded" to be rejected'),
      Err(:final failure) => failure,
    };

GarageRobot _robotOf(Result<GarageRobot, RobosatsFailure> result) =>
    switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => fail('expected a robot, got $failure'),
    };

RobosatsFailure _failureOf<T>(Result<T, RobosatsFailure> result) =>
    switch (result) {
      Ok() => fail('expected a failure, got a value'),
      Err(:final failure) => failure,
    };

/// A checksummed bech32 string for [bytes], built with the third-party codec only, to craft inputs this package must reject.
String _bech32(String hrp, List<int> bytes) {
  final words = <int>[];
  var accumulator = 0;
  var bits = 0;
  for (final byte in bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      words.add((accumulator >> bits) & 31);
    }
  }
  if (bits > 0) words.add((accumulator << (5 - bits)) & 31);
  return bech32.encode(Bech32(hrp, words));
}

/// A [Random] that replays [values], to make key generation deterministic.
class _ReplayRandom implements Random {
  final List<int> values;
  var _next = 0;

  _ReplayRandom(this.values);

  @override
  int nextInt(int max) {
    expect(max, 256);
    return values[_next++];
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  group('GarageKey.parse', () {
    test('decodes the example key of the RoboSats frontend tests', () {
      final key = _key(_exampleKey);
      expect(hex.encode(key.revealBytes()), garageKeyVector['plain_key_hex']);
      expect(key.revealBech32(), _exampleKey);
      expect(_exampleKey, hasLength(63));
    });

    test('accepts an all-uppercase key and normalises it', () {
      final key = _key(_exampleKey.toUpperCase());
      expect(key, _key(_exampleKey));
      expect(key.revealBech32(), _exampleKey);
    });

    test('rejects an empty string', () {
      expect(_rejection(''), isA<GarageKeyEmpty>());
    });

    test('rejects another human-readable part', () {
      final bytes = hex.decode(garageKeyVector['plain_key_hex'] as String);
      expect(_rejection(_bech32('bc', bytes)), isA<GarageKeyWrongPrefix>());
      expect(_rejection(_bech32('robot', bytes)), isA<GarageKeyWrongPrefix>());
      expect(_rejection(_bech32('nsec', bytes)), isA<GarageKeyWrongPrefix>());
      // Starts with `robo1` but the bech32 separator is the last `1`.
      expect(_rejection(_bech32('robo1q', bytes)), isA<GarageKeyWrongPrefix>());
    });

    test('rejects a wrong length before decoding', () {
      expect(_rejection('robo1'), isA<GarageKeyWrongLength>());
      expect(_rejection('robo1qqqqqq'), isA<GarageKeyWrongLength>());
      expect(
        _rejection(_exampleKey.substring(0, 54)),
        isA<GarageKeyWrongLength>(),
      );
      expect(_rejection('${_exampleKey}qqq'), isA<GarageKeyWrongLength>());
    });

    test('rejects a bad checksum, as the RoboSats frontend test does', () {
      final tampered = '${_exampleKey.substring(0, _exampleKey.length - 1)}q';
      expect(_rejection(tampered), isA<GarageKeyBadChecksum>());
    });

    test('detects up to four substituted characters', () {
      const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
      final random = Random(173);
      for (var i = 0; i < 500; i++) {
        final characters = _exampleKey.split('');
        final positions = <int>{};
        final errors = 1 + random.nextInt(4);
        while (positions.length < errors) {
          positions.add(5 + random.nextInt(characters.length - 5));
        }
        for (final position in positions) {
          String replacement;
          do {
            replacement = charset[random.nextInt(charset.length)];
          } while (replacement == characters[position]);
          characters[position] = replacement;
        }
        expect(
          _rejection(characters.join()),
          isA<GarageKeyBadChecksum>(),
          reason: characters.join(),
        );
      }
    });

    test('rejects mixed case and characters outside the bech32 charset', () {
      final mixed = 'ROBO1${_exampleKey.substring(5)}';
      expect(_rejection(mixed), isA<GarageKeyMalformed>());
      for (final invalid in ['b', 'i', 'o', '1', ' ', 'é']) {
        final tampered = _exampleKey.replaceRange(20, 21, invalid);
        expect(_rejection(tampered), isA<GarageKeyFailure>(), reason: invalid);
        expect(GarageKey.parse(tampered), isNot(isA<Ok>()), reason: invalid);
      }
      expect(
        _rejection(_exampleKey.replaceRange(20, 21, 'b')),
        isA<GarageKeyMalformed>(),
      );
    });

    test('rejects a payload that is not 32 bytes long', () {
      for (final length in [31, 33]) {
        final encoded = _bech32('robo', List.filled(length, 7));
        expect(encoded.length, inInclusiveRange(55, 65));
        expect(_rejection(encoded), isA<GarageKeyWrongByteLength>());
      }
    });

    test('rejects non-zero padding bits', () {
      final decoded = bech32.decode(_exampleKey);
      final words = [...decoded.data];
      words[words.length - 1] |= 1;
      final encoded = bech32.encode(Bech32('robo', words));
      expect(_rejection(encoded), isA<GarageKeyMalformed>());
    });

    test('does not tolerate surrounding whitespace', () {
      expect(GarageKey.parse(' $_exampleKey'), isNot(isA<Ok>()));
      expect(GarageKey.parse('$_exampleKey\n'), isNot(isA<Ok>()));
    });
  });

  group('GarageKey.fromBytes', () {
    test('encodes the example key of the RoboSats frontend tests', () {
      final bytes = Uint8List.fromList(
        hex.decode(garageKeyVector['plain_key_hex'] as String),
      );
      final result = GarageKey.fromBytes(bytes);
      expect(result, isA<Ok<GarageKey, GarageKeyFailure>>());
      expect(
        (result as Ok<GarageKey, GarageKeyFailure>).value.revealBech32(),
        _exampleKey,
      );
    });

    test('rejects any length other than 32 bytes', () {
      for (final length in [0, 16, 31, 33, 64]) {
        expect(
          GarageKey.fromBytes(Uint8List(length)),
          isA<Err<GarageKey, GarageKeyFailure>>(),
          reason: '$length',
        );
      }
    });

    test('round-trips random keys through their bech32 form', () {
      final random = Random(88);
      for (var i = 0; i < 300; i++) {
        final bytes = Uint8List.fromList(
          List.generate(32, (_) => random.nextInt(256)),
        );
        final key =
            (GarageKey.fromBytes(bytes) as Ok<GarageKey, GarageKeyFailure>)
                .value;
        final encoded = key.revealBech32();
        expect(encoded, startsWith('robo1'));
        expect(encoded, hasLength(63));
        expect(_key(encoded).revealBytes(), bytes);
        expect(_key(encoded), key);
      }
    });

    test('is isolated from later changes to the caller bytes', () {
      final bytes = Uint8List(32)..fillRange(0, 32, 9);
      final key =
          (GarageKey.fromBytes(bytes) as Ok<GarageKey, GarageKeyFailure>).value;
      final encoded = key.revealBech32();
      bytes[0] = 0;
      key.revealBytes()[1] = 0;
      expect(key.revealBech32(), encoded);
    });
  });

  group('GarageKey.generate', () {
    test('takes 32 bytes from the injected generator', () {
      final values = List.generate(32, (i) => 255 - i);
      final key = GarageKey.generateWith(_ReplayRandom(values));
      expect(key.revealBytes(), values);
    });

    test('yields distinct, valid keys from the secure generator', () {
      final first = GarageKey.generate();
      final second = GarageKey.generate();
      expect(first, isNot(second));
      expect(first.revealBech32(), hasLength(63));
      expect(_key(first.revealBech32()), first);
    });
  });

  group('GarageKey.deriveToken', () {
    final key = _key(_exampleKey);

    for (final robot in [...garageKeyRobots, base91ShortRobot]) {
      final index = robot['account_index'] as int;
      test('derives the robot token at index $index', () {
        final result = key.deriveToken(index);
        expect(result, isA<Ok<RobotToken, RobosatsFailure>>());
        final token = (result as Ok<RobotToken, RobosatsFailure>).value;
        expect(token.reveal(), robot['token']);
        expect(token.reveal(), hasLength(36));
      });
    }

    test('reproduces the tokens asserted by the RoboSats frontend tests', () {
      // `frontend/src/utils/__tests__/garageKey.test.ts:23-27` (commit ff1998c).
      const expected = {
        0: '2gYWvCarekOrMwc2LwA30tnUdyqcuPB8xsAx',
        1: '94PXnMt4tcXGi33QS9wNYjg2dPawXA9r6h5t',
        18: '9bagGwV1l8JzixhBzjDyflNmQlEfNha8AA6I',
      };
      for (final MapEntry(key: index, value: token) in expected.entries) {
        final result = key.deriveToken(index);
        expect(
          (result as Ok<RobotToken, RobosatsFailure>).value.reveal(),
          token,
        );
      }
    });

    test('accepts the highest hardened index', () {
      expect(
        key.deriveToken(0x7fffffff),
        isA<Ok<RobotToken, RobosatsFailure>>(),
      );
    });

    test('rejects an index outside 0..2^31-1', () {
      for (final index in [-1, 0x80000000, 0x100000000]) {
        final result = key.deriveToken(index);
        expect(result, isA<Err<RobotToken, RobosatsFailure>>());
        expect(
          (result as Err<RobotToken, RobosatsFailure>).failure,
          isA<AccountIndexOutOfRange>(),
        );
      }
    });
  });

  group('GarageKey.deriveIdentity', () {
    final key = _key(_exampleKey);

    test('derives the identity of the token at each index', () {
      for (final robot in garageKeyRobots) {
        final index = robot['account_index'] as int;
        final result = key.deriveIdentity(index);
        expect(result, isA<Ok<RobotIdentity, RobosatsFailure>>());
        final identity = (result as Ok<RobotIdentity, RobosatsFailure>).value;
        expect(identity.token.reveal(), robot['token']);
        expect(identity.hashId.hex, robot['hash_id']);
      }
    });

    test('rejects an index outside 0..2^31-1', () {
      for (final index in [-1, 0x80000000]) {
        expect(
          _failureOf(key.deriveIdentity(index)),
          isA<AccountIndexOutOfRange>(),
        );
      }
    });
  });

  group('GarageKey.firstUsableRobot', () {
    final key = _key(_exampleKey);

    /// The identity of a real robot, standing for whatever index a test puts it at.
    RobotIdentity identity(int number) => switch (key.deriveIdentity(number)) {
      Ok(:final value) => value,
      Err(:final failure) => fail('expected an identity, got $failure'),
    };

    /// What the entropy rule answers for a token it refuses.
    const tooLow = TokenEntropyTooLow(
      TokenEntropy(bitsEntropy: 0, shannonEntropy: 0),
    );

    test('is the robot of the index asked when its token is strong', () {
      for (final robot in garageKeyRobots) {
        final index = robot['account_index'] as int;
        final found = _robotOf(key.firstUsableRobot(index));
        expect(found.accountIndex, index);
        expect(found.identity.token.reveal(), robot['token']);
        expect(found, GarageRobot(index, identity(index)));
      }
    });

    test('skips an index whose token fails the entropy rule', () {
      final asked = <int>[];
      final found = _robotOf(
        GarageKey.firstUsableRobotAmong(7, (index) {
          asked.add(index);
          return index < 9 ? const Err(tooLow) : Ok(identity(index));
        }),
      );

      expect(asked, [7, 8, 9]);
      expect(found.accountIndex, 9);
      expect(found.identity, identity(9));
    });

    test('skips an index whose hash id has no nickname', () {
      final found = _robotOf(
        GarageKey.firstUsableRobotAmong(
          0,
          (index) => index == 0
              ? const Err(NicknameUnavailable())
              : Ok(identity(index)),
        ),
      );

      expect(found.accountIndex, 1);
    });

    test('really refuses a weak token, which is what the skip relies on', () {
      // No Garage Key is known to give one: this is the token a skipped index would have.
      expect(
        RobotToken.parse('A' * 36),
        isA<Err<RobotToken, TokenEntropyTooLow>>(),
      );
    });

    test('looks at 100 indexes at most, as the official client', () {
      final asked = <int>[];
      final result = GarageKey.firstUsableRobotAmong(5, (index) {
        asked.add(index);
        return const Err(tooLow);
      });

      expect(_failureOf(result), isA<NoUsableAccountIndex>());
      expect(asked, [for (var index = 5; index < 105; index++) index]);
      expect(GarageKey.maxAccountSearch, 100);
    });

    test('finds a robot at the last index of the search', () {
      final found = _robotOf(
        GarageKey.firstUsableRobotAmong(
          5,
          (index) => index < 104 ? const Err(tooLow) : Ok(identity(1)),
        ),
      );

      expect(found.accountIndex, 104);
    });

    test('stops at any other failure', () {
      final asked = <int>[];
      final result = GarageKey.firstUsableRobotAmong(3, (index) {
        asked.add(index);
        return index == 3 ? const Err(tooLow) : const Err(HashIdMalformed());
      });

      expect(_failureOf(result), isA<HashIdMalformed>());
      expect(asked, [3, 4]);
    });

    test('rejects a start outside 0..2^31-1 without deriving anything', () {
      for (final index in [-1, 0x80000000, 0x100000000]) {
        final result = GarageKey.firstUsableRobotAmong(
          index,
          (_) => fail('nothing to derive'),
        );
        expect(_failureOf(result), isA<AccountIndexOutOfRange>());
        expect(
          _failureOf(key.firstUsableRobot(index)),
          isA<AccountIndexOutOfRange>(),
        );
      }
    });

    test('never searches past the highest index', () {
      final asked = <int>[];
      final result = GarageKey.firstUsableRobotAmong(0x7ffffffe, (index) {
        asked.add(index);
        return const Err(tooLow);
      });

      expect(_failureOf(result), isA<AccountIndexOutOfRange>());
      expect(asked, [0x7ffffffe, 0x7fffffff]);
      expect(
        _robotOf(key.firstUsableRobot(0x7fffffff)).accountIndex,
        0x7fffffff,
      );
    });

    test('prints the index and the nickname only', () {
      final robot = _robotOf(key.firstUsableRobot(0));

      expect('$robot', 'GarageRobot(0, ${robot.identity.nickname})');
      expect('$robot', isNot(contains(robot.identity.token.reveal())));
    });
  });

  group('GarageKey recovery Nostr keys', () {
    final key = _key(_exampleKey);

    test('derives the current key pair from the raw bytes', () {
      final pair = key.recoveryNostrKeyPair;
      expect(
        hex.encode(pair.revealSecretKey()),
        garageKeyVector['nostr_seckey_hex'],
      );
      expect(pair.publicKeyHex, garageKeyVector['nostr_pubkey_hex']);
    });

    test('derives the legacy key pair from the hexadecimal string', () {
      final pair = key.legacyRecoveryNostrKeyPair;
      expect(
        hex.encode(pair.revealSecretKey()),
        garageKeyVector['legacy_nostr_seckey_hex'],
      );
      expect(pair.publicKeyHex, garageKeyVector['legacy_nostr_pubkey_hex']);
    });
  });

  group('GarageKey secrecy', () {
    test('never prints the key', () {
      final key = _key(_exampleKey);
      final secrets = [
        _exampleKey,
        _exampleKey.substring(5, 20),
        garageKeyVector['plain_key_hex'] as String,
      ];
      for (final text in [
        '$key',
        '${[key]}',
        '${GarageKey.parse(_exampleKey)}',
      ]) {
        for (final secret in secrets) {
          expect(text, isNot(contains(secret)));
        }
      }
    });

    test('never carries the rejected input in a failure', () {
      final tampered = '${_exampleKey.substring(0, _exampleKey.length - 1)}q';
      final failure = _rejection(tampered);
      expect('$failure', isNot(contains('robo1')));
      expect(failure.logMessage, isNull);
    });

    test('never prints a Nostr secret key', () {
      final pair = _key(_exampleKey).recoveryNostrKeyPair;
      expect(
        '$pair',
        isNot(contains(garageKeyVector['nostr_seckey_hex'] as String)),
      );
      expect('$pair', contains(garageKeyVector['nostr_pubkey_hex'] as String));
    });
  });
}
