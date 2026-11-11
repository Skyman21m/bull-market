import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/coordinator/currency_data.dart';
import 'package:robosats/src/coordinator/federation_data.dart';
import 'package:robosats/src/coordinator/payment_method_data.dart';
import 'package:test/test.dart';

/// The RoboSats files the constants were generated from, copied by `tool/generate_coordinator_data.dart`.
Object? _source(String name) => jsonDecode(
  File('test/fixtures/coordinator/sources/$name').readAsStringSync(),
);

/// The Git blob id of a file: what `git hash-object <file>` prints, and `git rev-parse <commit>:<path>` for the file at a commit.
String _gitBlobId(List<int> bytes) => sha1.convert([
  ...ascii.encode('blob ${bytes.length}\x00'),
  ...bytes,
]).toString();

/// Whether [url] is `http://<56 characters>.onion` naming a Tor v3 service: base32 of the 32-byte key, a 2-byte checksum and the version byte 3, the checksum being the start of SHA3-256 of `.onion checksum`, the key and the version (Tor `rend-spec-v3.txt`, section 6).
bool _isV3Onion(String url) {
  final host = RegExp(r'^http://([a-z2-7]{56})\.onion$').firstMatch(url)?[1];
  if (host == null) return false;
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  var bits = BigInt.zero;
  for (final char in host.split('')) {
    bits = (bits << 5) | BigInt.from(alphabet.indexOf(char));
  }
  final bytes = [
    for (var shift = 34 * 8; shift >= 0; shift -= 8)
      ((bits >> shift) & BigInt.from(0xff)).toInt(),
  ];
  final key = bytes.sublist(0, 32);
  final checksum = SHA3Digest(256).process(
    Uint8List.fromList([...ascii.encode('.onion checksum'), ...key, 3]),
  );
  return bytes[34] == 3 && bytes[32] == checksum[0] && bytes[33] == checksum[1];
}

/// Whether [hex] is a SEC1 compressed secp256k1 public key whose X has a point on the curve: `y² = x³ + 7` has a root modulo p.
bool _isCompressedPoint(String hex) {
  final match = RegExp(r'^0[23]([0-9a-f]{64})$').firstMatch(hex);
  if (match == null) return false;
  final p = BigInt.parse(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
    radix: 16,
  );
  final x = BigInt.parse(match[1] ?? '', radix: 16);
  if (x >= p) return false;
  final ySquared = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
  final y = ySquared.modPow((p + BigInt.one) >> 2, p);
  return y * y % p == ySquared;
}

/// An empty or missing string of the federation list is `null` in the constants, so both sides drop them before comparing.
Map<String, Object?> _withoutEmpty(Object? section) => {
  for (final MapEntry(:key, :value)
      in (section as Map<String, dynamic>? ?? {}).entries)
    if (value != null && value != '') key: value,
};

Map<String, Object?> _normalizedSource(Map<String, dynamic> entry) => {
  ...entry,
  'contact': _withoutEmpty(entry['contact']),
  'mainnet': _withoutEmpty(entry['mainnet']),
  'testnet': _withoutEmpty(entry['testnet']),
};

Map<String, Object?> _asJson(Coordinator coordinator) => {
  'longAlias': coordinator.longAlias,
  'shortAlias': coordinator.shortAlias,
  'identifier': coordinator.identifier,
  'description': coordinator.description,
  'motto': coordinator.motto,
  'color': coordinator.color,
  'established': coordinator.established,
  'nostrHexPubkey': coordinator.nostrHexPubkey,
  'contact': _withoutEmpty({
    'email': coordinator.contact.email,
    'telegram': coordinator.contact.telegram,
    'simplex': coordinator.contact.simplex,
    'matrix': coordinator.contact.matrix,
    'website': coordinator.contact.website,
    'nostr': coordinator.contact.nostr,
    'pgp': coordinator.contact.pgp,
    'fingerprint': coordinator.contact.fingerprint,
    'reddit': coordinator.contact.reddit,
    'twitter': coordinator.contact.twitter,
  }),
  'badges': {
    'isFounder': coordinator.badges.isFounder,
    'donatesToDevFund': coordinator.badges.donatesToDevFund,
    'hasGoodOpSec': coordinator.badges.hasGoodOpSec,
    'hasLargeLimits': coordinator.badges.hasLargeLimits,
  },
  'policies': coordinator.policies,
  'mainnet': _withoutEmpty({
    'onion': coordinator.mainnet.onion,
    'clearnet': coordinator.mainnet.clearnet,
    'i2p': coordinator.mainnet.i2p,
  }),
  'testnet': _withoutEmpty({
    'onion': coordinator.testnet.onion,
    'clearnet': coordinator.testnet.clearnet,
    'i2p': coordinator.testnet.i2p,
  }),
  'mainnetNodesPubkeys': coordinator.mainnetNodesPubkeys,
  'testnetNodesPubkeys': coordinator.testnetNodesPubkeys,
  'federated': coordinator.federated,
};

void main() {
  group('sources of the generated constants', () {
    for (final (file, copy, source) in [
      ('federation_data.dart', 'federation.json', robosatsFederationSource),
      ('currency_data.dart', 'currencies.json', robosatsCurrenciesSource),
      ('payment_method_data.dart', 'MethodList.ts', robosatsMethodsSource),
    ]) {
      test('$file states the commit and blob of its copied source', () {
        expect(source.commit, matches(RegExp(r'^[0-9a-f]{40}$')));
        expect(source.path, endsWith('/$copy'));
        expect(
          File('lib/src/coordinator/$file').readAsStringSync(),
          startsWith(
            '// Generated by `tool/generate_coordinator_data.dart` from RoboSats `${source.path}` (https://github.com/RoboSats/robosats, commit ${source.commit}).\n',
          ),
        );
        expect(
          _gitBlobId(
            File('test/fixtures/coordinator/sources/$copy').readAsBytesSync(),
          ),
          source.blob,
        );
      });
    }

    test('are the protocol reference, with a later federation list', () {
      // See the RoboSats refresh procedure in AGENTS.md, section "Troc (fork)".
      // The protocol reference is ff1998c (2026-11-06); only the federation list was taken from e56f9cf7c (2026-11-08), which adds gumpellite.
      // Each blob was checked against RoboSats when it was generated (`gh api 'repos/RoboSats/robosats/contents/<path>?ref=<commit>' --jq .sha`): pinning the pair makes a list regenerated from files of another commit, under the old commit id, fail here.
      const reference = 'ff1998caed30888b2fb60e15022c29063a60f1ba';
      expect(robosatsFederationSource, (
        path: 'frontend/static/federation.json',
        commit: 'e56f9cf7cd4e6b01aa78589922f7c648f262b6b6',
        blob: '85c118156dda4b9914175d6a87c5daab68151e19',
      ));
      expect(robosatsCurrenciesSource, (
        path: 'frontend/static/assets/currencies.json',
        commit: reference,
        blob: '6cce82c269a1e301b7a3b700dc15868fbc81bc62',
      ));
      expect(robosatsMethodsSource, (
        path: 'frontend/src/components/PaymentMethods/MethodList.ts',
        commit: reference,
        blob: '85df6c6c3aba192af16926694ed47a49e1bd32b3',
      ));
    });
  });

  group('Federation.robosats', () {
    final source = _source('federation.json') as Map<String, dynamic>;

    test('holds every coordinator of federation.json, in its order', () {
      expect(
        Federation.robosats.coordinators.map((c) => c.shortAlias),
        source.keys,
      );
      expect(source.keys, [
        'temple',
        'lake',
        'bazaar',
        'freeport',
        'ammanaya',
        'gumpellite',
      ]);
    });

    test('equals federation.json, empty and missing strings aside', () {
      for (final coordinator in Federation.robosats.coordinators) {
        expect(
          _asJson(coordinator),
          _normalizedSource(
            source[coordinator.shortAlias] as Map<String, dynamic>,
          ),
          reason: coordinator.shortAlias,
        );
        expect(
          coordinator.policies.keys,
          (source[coordinator.shortAlias]['policies'] as Map).keys,
          reason: 'policy order of ${coordinator.shortAlias}',
        );
      }
    });

    test('has well-formed onion addresses, node keys and dates', () {
      final onion = RegExp(r'^http://[a-z2-7]{56}\.onion$');
      final nodeKey = RegExp(r'^0[23][0-9a-f]{64}$');
      for (final coordinator in Federation.robosats.coordinators) {
        expect(coordinator.mainnet.onion, matches(onion));
        for (final network in RobosatsNetwork.values) {
          final address = coordinator.origins(network).onion;
          if (address != null) expect(address, matches(onion));
          for (final key in coordinator.nodesPubkeys(network)) {
            expect(key, matches(nodeKey));
          }
          if (coordinator.isOn(network)) {
            expect(coordinator.nodesPubkeys(network), isNotEmpty);
          }
        }
        expect(coordinator.nostrHexPubkey, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(coordinator.establishedOn.isUtc, isTrue);
      }
      expect(coordinatorEstablished('temple'), DateTime.utc(2023, 12, 2));
    });

    test('has real v3 onion addresses and secp256k1 keys', () {
      // The shape checks of `Federation.problems` cannot see a mistyped address: the onion checksum can.
      // A mistyped key is caught only when its X has no point on the curve, about half the time.
      // Keys rest on the byte comparison with the upstream file and on the provenance trail.
      for (final coordinator in Federation.robosats.coordinators) {
        final alias = coordinator.shortAlias;
        for (final network in RobosatsNetwork.values) {
          final onion = coordinator.origins(network).onion;
          if (onion != null) {
            expect(_isV3Onion(onion), isTrue, reason: '$alias $network onion');
          }
          for (final key in coordinator.nodesPubkeys(network)) {
            expect(
              _isCompressedPoint(key),
              isTrue,
              reason: '$alias $network node key',
            );
          }
        }
        expect(
          _isCompressedPoint('02${coordinator.nostrHexPubkey}'),
          isTrue,
          reason: '$alias Nostr key',
        );
      }
      // The checks themselves reject a corrupted address and an X with no point.
      final temple = Federation.robosats.coordinators.first;
      final onion = temple.mainnet.onion ?? '';
      expect(_isV3Onion('http://a${onion.substring(8)}'), isFalse);
      expect(
        _isV3Onion(onion.replaceFirst(RegExp(r'd\.onion$'), 'a.onion')),
        isFalse,
      );
      expect(_isCompressedPoint('02${'0' * 63}5'), isFalse);
      expect(_isCompressedPoint('02${'f' * 64}'), isFalse);
    });

    test(
      'has contacts and onion addresses in printable ASCII, with no space at either end',
      () {
        // The app offers a contact or an address for copy only when it is printable ASCII that neither starts nor ends with a space: a change of the list that breaks it fails here, not silently in the app.
        final printable = RegExp(r'^[\x21-\x7E](?:[\x20-\x7E]*[\x21-\x7E])?$');
        expect(printable.hasMatch('a'), isTrue);
        expect(printable.hasMatch('a b'), isTrue);
        for (final text in ['', ' ', ' a', 'a ', 'a\tb']) {
          expect(printable.hasMatch(text), isFalse, reason: '"$text"');
        }
        for (final coordinator in Federation.robosats.coordinators) {
          final contact = coordinator.contact;
          for (final text in [
            contact.email,
            contact.telegram,
            contact.simplex,
            contact.matrix,
            contact.website,
            contact.nostr,
            contact.pgp,
            contact.fingerprint,
            contact.reddit,
            contact.twitter,
            coordinator.mainnet.onion,
            coordinator.testnet.onion,
          ]) {
            if (text == null) continue;
            expect(
              printable.hasMatch(text),
              isTrue,
              reason: '${coordinator.shortAlias}: $text',
            );
          }
        }
      },
    );

    test('has free text that needs no cleaning and stays short', () {
      // The list is reviewed when it is generated, but its text comes from RoboSats contributors: it must already be what the cleaning of coordinator text would leave.
      for (final coordinator in Federation.robosats.coordinators) {
        final contact = coordinator.contact;
        final texts = [
          coordinator.longAlias,
          coordinator.identifier,
          coordinator.description,
          coordinator.motto,
          coordinator.color,
          for (final text in [
            contact.email,
            contact.telegram,
            contact.simplex,
            contact.matrix,
            contact.website,
            contact.nostr,
            contact.pgp,
            contact.fingerprint,
            contact.reddit,
            contact.twitter,
            coordinator.mainnet.clearnet,
            coordinator.mainnet.i2p,
            coordinator.testnet.clearnet,
            coordinator.testnet.i2p,
          ])
            ?text,
          for (final MapEntry(:key, :value)
              in coordinator.policies.entries) ...[key, value],
        ];
        for (final text in texts) {
          expect(displayText(text), text, reason: coordinator.shortAlias);
          expect(text.runes.length, lessThanOrEqualTo(1000));
        }
        expect(coordinator.policies.length, lessThanOrEqualTo(20));
      }
    });

    test('has no problem, and problems are found in a broken list', () {
      expect(Federation.robosats.problems(), isEmpty);
      final temple = Federation.robosats.coordinators.first;
      Coordinator broken({
        String? shortAlias,
        CoordinatorOrigins? mainnet,
        CoordinatorOrigins? testnet,
        List<String>? testnetNodesPubkeys,
        String? established,
      }) => Coordinator(
        shortAlias: shortAlias ?? temple.shortAlias,
        longAlias: temple.longAlias,
        identifier: temple.identifier,
        description: temple.description,
        motto: temple.motto,
        color: temple.color,
        established: established ?? temple.established,
        nostrHexPubkey: temple.nostrHexPubkey,
        contact: temple.contact,
        badges: temple.badges,
        policies: temple.policies,
        mainnet: mainnet ?? temple.mainnet,
        testnet: testnet ?? temple.testnet,
        mainnetNodesPubkeys: temple.mainnetNodesPubkeys,
        testnetNodesPubkeys: testnetNodesPubkeys ?? temple.testnetNodesPubkeys,
        federated: temple.federated,
      );
      expect(Federation([temple, broken()]).problems(), [
        'temple: duplicated alias',
      ]);
      expect(Federation([broken(shortAlias: 'Temple')]).problems(), [
        'Temple: malformed alias',
      ]);
      expect(
        Federation([broken(mainnet: const CoordinatorOrigins())]).problems(),
        ['temple: no mainnet onion'],
      );
      expect(
        Federation([
          broken(
            mainnet: const CoordinatorOrigins(onion: 'http://example.onion'),
          ),
        ]).problems(),
        ['temple: malformed mainnet onion'],
      );
      expect(Federation([broken(testnetNodesPubkeys: [])]).problems(), [
        'temple: no testnet node key',
      ]);
      expect(
        Federation([
          broken(testnetNodesPubkeys: ['04ab']),
        ]).problems(),
        ['temple: malformed testnet node key'],
      );
      expect(Federation([broken(established: '2023-13-45')]).problems(), [
        'temple: malformed established date',
      ]);
    });

    test('lists the testnet coordinators', () {
      expect(
        Federation.robosats
            .on(RobosatsNetwork.testnet)
            .map((c) => c.shortAlias),
        ['temple', 'lake'],
      );
      expect(Federation.robosats.on(RobosatsNetwork.mainnet), hasLength(6));
    });

    test('has gumpellite on mainnet only, as reviewed on 2026-11-11', () {
      final gumpellite = Federation.robosats.byAlias('gumpellite');
      expect(gumpellite?.longAlias, 'Gumpellite');
      expect(
        gumpellite?.mainnet,
        const CoordinatorOrigins(
          onion:
              'http://jvnfeiy3aizcpva6zekd3v6o5kpzduqeeqqihhtudhuqqa7e5jzm7kyd.onion',
        ),
      );
      expect(gumpellite?.mainnetNodesPubkeys, [
        '0337a597a971a8dadd4e7bcec2638e4b5156a36157ec91c26d782aa4a0a8a7cef2',
      ]);
      expect(gumpellite?.testnet, const CoordinatorOrigins());
      expect(gumpellite?.testnetNodesPubkeys, isEmpty);
    });

    test('finds a coordinator by alias and identifies it by alias', () {
      final lake = Federation.robosats.byAlias('lake');
      expect(lake?.longAlias, 'TheBigLake');
      expect(Federation.robosats.byAlias('Lake'), isNull);
      expect('$lake', 'Coordinator(lake)');
    });
  });

  group('RobosatsCurrency', () {
    test('equals currencies.json, in its order', () {
      final source = _source('currencies.json') as Map<String, dynamic>;
      expect({
        for (final currency in RobosatsCurrency.all)
          '${currency.id}': currency.code,
      }, source);
      expect(
        RobosatsCurrency.all.map((currency) => '${currency.id}'),
        source.keys,
      );
      expect(RobosatsCurrency.all, hasLength(80));
    });

    test('maps ids and codes both ways', () {
      expect(RobosatsCurrency.fromId(2)?.code, 'EUR');
      expect(RobosatsCurrency.fromCode('EUR')?.id, 2);
      expect(RobosatsCurrency.fromId(1000)?.isBitcoin, isTrue);
      expect(RobosatsCurrency.fromId(1)?.isBitcoin, isFalse);
      expect(RobosatsCurrency.fromId(0), isNull);
      expect(RobosatsCurrency.fromId(79), isNull);
      expect(RobosatsCurrency.fromCode('eur'), isNull);
    });
  });

  group('payment method list', () {
    test('equals MethodList.ts, in its order', () {
      final source = File(
        'test/fixtures/coordinator/sources/MethodList.ts',
      ).readAsStringSync();
      final entry = RegExp(
        r"\{ name: '([^']*)', icon: '([^']*)', reversible: (true|false) \}",
      );
      final swapStart = source.indexOf('export const swapMethods');
      List<String> describe(Iterable<PaymentMethodInfo> methods) => [
        for (final method in methods)
          '${method.name}|${method.icon}|${method.reversible}',
      ];
      List<String> parse(String text) => [
        for (final match in entry.allMatches(text))
          '${match[1]}|${match[2]}|${match[3]}',
      ];
      expect(
        describe(robosatsFiatMethods),
        parse(source.substring(0, swapStart)),
      );
      expect(describe(robosatsSwapMethods), parse(source.substring(swapStart)));
      expect(robosatsFiatMethods.length + robosatsSwapMethods.length, 101);
      expect(
        robosatsFiatMethods.where((m) => m.reversible).map((m) => m.name),
        ['PIX', 'Revolut'],
      );
    });
  });
}

DateTime coordinatorEstablished(String alias) =>
    Federation.robosats.byAlias(alias)?.establishedOn ?? DateTime(0);
