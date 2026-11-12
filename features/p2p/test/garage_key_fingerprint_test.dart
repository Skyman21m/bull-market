import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// The fingerprint that ties the bindings of the robots of a Garage Key to that key, and the domain rules of a binding.
void main() {
  // Fixed test bytes, 0x01 to 0x20, and 0x02 to 0x21: not keys anyone uses.
  GarageKey keyOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final keyA = keyOf(1);
  final keyB = keyOf(2);

  T ok<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('expected a value, got $failure'),
  };

  group('the fingerprint of a key', () {
    test('is the HMAC of its purpose keyed by the token of robot 0', () {
      final token = ok(keyA.deriveToken(0)).reveal();
      final expected = Hmac(
        sha256,
        utf8.encode(token),
      ).convert(utf8.encode('troc/p2p/garage-key-fingerprint/v1')).toString();

      expect(ok(GarageKeyFingerprint.of(keyA)).hex, expected);
    });

    test('is pinned: changing it orphans every stored binding', () {
      expect(
        ok(GarageKeyFingerprint.of(keyA)).hex,
        '71c973ce0ff8c22195cfabb4416d8382f4f753ede34331b90cccffeefda3f9f8',
      );
    });

    test('is 64 lowercase hexadecimal characters, the same at each call', () {
      final fingerprint = ok(GarageKeyFingerprint.of(keyA));

      expect(fingerprint.hex, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(ok(GarageKeyFingerprint.of(keyOf(1))), fingerprint);
      expect(ok(GarageKeyFingerprint.of(keyB)), isNot(fingerprint));
    });

    test('is no value a coordinator receives or publishes', () {
      final fingerprint = ok(GarageKeyFingerprint.of(keyA)).hex;
      for (final index in [0, 1]) {
        final identity = ok(keyA.deriveIdentity(index));
        for (final known in [
          identity.tokenSha256Hex,
          identity.hashId.hex,
          identity.nostrKeyPair().publicKeyHex,
          sha256.convert(utf8.encode(identity.token.reveal())).toString(),
        ]) {
          expect(fingerprint, isNot(known));
        }
        expect(fingerprint.contains(identity.token.reveal()), isFalse);
      }
      expect(fingerprint, isNot(keyA.recoveryNostrKeyPair.publicKeyHex));
    });

    test('is carried by every robot of the key, on each network', () {
      final fingerprint = ok(GarageKeyFingerprint.of(keyA));
      for (final network in RobosatsNetwork.values) {
        final key = NetworkGarageKey(network, keyA);
        expect(ok(key.fingerprint), fingerprint);
        for (final index in [0, 1, 7]) {
          final next = ok(key.firstUsableRobot(index));
          final previous = ok(key.lastUsableRobot(index));
          expect(next.keyFingerprint, fingerprint);
          expect(previous.keyFingerprint, fingerprint);
          expect(next.slot, RobotSlot(network, fingerprint, index));
        }
      }
    });

    test('is the same on both networks, as the tokens of its robots are', () {
      final testnet = NetworkGarageKey(RobosatsNetwork.testnet, keyA);
      final mainnet = NetworkGarageKey(RobosatsNetwork.mainnet, keyA);

      expect(ok(testnet.fingerprint), ok(mainnet.fingerprint));
      for (final index in [0, 1, 5]) {
        // One credential on both networks: hence one binding per index, whatever the network.
        expect(
          ok(mainnet.firstUsableRobot(index)).identity.tokenSha256Base91,
          ok(testnet.firstUsableRobot(index)).identity.tokenSha256Base91,
        );
      }
    });

    test(
      'skips a robot 0 whose token fails the entropy rule, and stops on any other failure',
      () {
        final token1 = ok(keyA.deriveToken(1));
        final asked = <int>[];
        final fingerprint = GarageKeyFingerprint.fromTokens((index) {
          asked.add(index);
          return index == 0
              ? const Err(
                  TokenEntropyTooLow(
                    TokenEntropy(bitsEntropy: 1, shannonEntropy: 1),
                  ),
                )
              : Ok(token1);
        });

        expect(asked, [0, 1]);
        expect(
          ok(fingerprint).hex,
          Hmac(sha256, utf8.encode(token1.reveal()))
              .convert(utf8.encode('troc/p2p/garage-key-fingerprint/v1'))
              .toString(),
        );
        asked.clear();
        expect(
          GarageKeyFingerprint.fromTokens((index) {
            asked.add(index);
            return const Err(AccountIndexOutOfRange());
          }),
          isA<Err<GarageKeyFingerprint, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<GarageRobotUnavailableFailure>(),
          ),
        );
        expect(asked, [0]);
        asked.clear();
        expect(
          GarageKeyFingerprint.fromTokens((index) {
            asked.add(index);
            return const Err(
              TokenEntropyTooLow(
                TokenEntropy(bitsEntropy: 1, shannonEntropy: 1),
              ),
            );
          }),
          isA<Err<GarageKeyFingerprint, P2pFailure>>(),
        );
        expect(asked, hasLength(GarageKey.maxAccountSearch));
      },
    );

    test('never prints its value', () {
      final fingerprint = ok(GarageKeyFingerprint.of(keyA));

      expect('$fingerprint', 'GarageKeyFingerprint(<redacted>)');
      expect('$fingerprint'.contains(fingerprint.hex), isFalse);
      final robot = ok(
        NetworkGarageKey(RobosatsNetwork.testnet, keyA).firstUsableRobot(0),
      );
      for (final printed in ['$robot', '${robot.slot}']) {
        expect(printed.contains(fingerprint.hex), isFalse, reason: printed);
      }
    });

    test('tells the robots of two keys apart, index by index', () {
      final robotA = ok(
        NetworkGarageKey(RobosatsNetwork.testnet, keyA).firstUsableRobot(0),
      );
      final robotB = ok(
        NetworkGarageKey(RobosatsNetwork.testnet, keyB).firstUsableRobot(0),
      );
      final mainnetA = ok(
        NetworkGarageKey(RobosatsNetwork.mainnet, keyA).firstUsableRobot(0),
      );

      expect(robotA.slot, isNot(robotB.slot));
      expect(robotA.slot, isNot(mainnetA.slot));
      expect(robotA.slot.keyFingerprint, mainnetA.slot.keyFingerprint);
    });
  });

  group('a coordinator as a binding records it', () {
    test('is its alias, onion address, node keys and Nostr key there', () {
      final temple = coordinator('temple');
      for (final network in RobosatsNetwork.values) {
        final identity = CoordinatorIdentity.of(temple, network);

        expect(identity?.network, network);
        expect(identity?.alias, 'temple');
        expect(identity?.onion, temple.origins(network).onion);
        expect(identity?.nodeKeys, [...temple.nodesPubkeys(network)]..sort());
        expect(identity?.nostrKey, temple.nostrHexPubkey);
      }
      expect(
        CoordinatorIdentity.of(temple, RobosatsNetwork.mainnet),
        isNot(CoordinatorIdentity.of(temple, RobosatsNetwork.testnet)),
      );
    });

    test('does not exist where the coordinator has no onion address', () {
      final bazaar = coordinator('bazaar');
      expect(bazaar.isOn(RobosatsNetwork.testnet), isFalse);

      expect(CoordinatorIdentity.of(bazaar, RobosatsNetwork.testnet), isNull);
    });
  });

  group('a binding', () {
    final temple = CoordinatorIdentity(
      network: RobosatsNetwork.testnet,
      alias: 'temple',
      onion: 'http://temple.onion',
      nodeKeys: const ['02aa', '03bb'],
      nostrKey: 'nostr-temple',
    );
    final binding = RobotBinding(temple, testNow, BindingProvenance.drawnHere);

    Matcher refusedWith<T>() => isA<Err<void, P2pFailure>>().having(
      (err) => err.failure,
      'failure',
      isA<T>(),
    );

    test('admits its coordinator as it was, node keys in any order', () {
      expect(binding.admits(temple), isA<Ok<void, P2pFailure>>());
      expect(
        binding.admits(
          CoordinatorIdentity(
            network: RobosatsNetwork.testnet,
            alias: 'temple',
            onion: 'http://temple.onion',
            nodeKeys: const ['03bb', '02aa'],
            nostrKey: 'nostr-temple',
          ),
        ),
        isA<Ok<void, P2pFailure>>(),
      );
    });

    test(
      'refuses the instance of the other network, whatever its alias or address',
      () {
        for (final other in [
          CoordinatorIdentity(
            network: RobosatsNetwork.mainnet,
            alias: 'temple',
            onion: 'http://temple.onion',
            nodeKeys: const ['02aa', '03bb'],
            nostrKey: 'nostr-temple',
          ),
          CoordinatorIdentity(
            network: RobosatsNetwork.mainnet,
            alias: 'temple',
            onion: 'http://temple-mainnet.onion',
            nodeKeys: const ['02cc'],
            nostrKey: 'nostr-temple',
          ),
        ]) {
          expect(
            binding.admits(other),
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
            reason: '$other',
          );
        }
      },
    );

    test('refuses another coordinator', () {
      expect(
        binding.admits(
          CoordinatorIdentity(
            network: RobosatsNetwork.testnet,
            alias: 'lake',
            onion: 'http://lake.onion',
            nodeKeys: const ['02aa', '03bb'],
            nostrKey: 'nostr-temple',
          ),
        ),
        refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
      );
    });

    test('refuses its coordinator once anything recorded changed', () {
      for (final changed in [
        CoordinatorIdentity(
          network: RobosatsNetwork.testnet,
          alias: 'temple',
          onion: 'http://elsewhere.onion',
          nodeKeys: const ['02aa', '03bb'],
          nostrKey: 'nostr-temple',
        ),
        CoordinatorIdentity(
          network: RobosatsNetwork.testnet,
          alias: 'temple',
          onion: 'http://temple.onion',
          nodeKeys: const ['02aa'],
          nostrKey: 'nostr-temple',
        ),
        CoordinatorIdentity(
          network: RobosatsNetwork.testnet,
          alias: 'temple',
          onion: 'http://temple.onion',
          nodeKeys: const ['02aa', '03bb'],
          nostrKey: 'nostr-other',
        ),
        CoordinatorIdentity(
          network: RobosatsNetwork.testnet,
          alias: 'renamed',
          onion: 'http://temple.onion',
          nodeKeys: const ['02aa', '03bb'],
          nostrKey: 'nostr-temple',
        ),
      ]) {
        expect(
          binding.admits(changed),
          refusedWith<RobotCoordinatorChangedFailure>(),
          reason: '$changed',
        );
      }
    });
  });
}
