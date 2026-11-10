import 'dart:convert';
import 'dart:io';

import 'package:robosats/robosats.dart';
import 'package:robosats/src/coordinator/payment_method_data.dart';
import 'package:test/test.dart';

/// The RoboSats files the constants were generated from, copied by `tool/generate_coordinator_data.dart`.
Object? _source(String name) => jsonDecode(
  File('test/fixtures/coordinator/sources/$name').readAsStringSync(),
);

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
  group('Federation.robosats', () {
    final source = _source('federation.json') as Map<String, dynamic>;

    test('holds every coordinator of federation.json, in its order', () {
      expect(
        Federation.robosats.coordinators.map((c) => c.shortAlias),
        source.keys,
      );
      expect(source.keys, ['temple', 'lake', 'bazaar', 'freeport', 'ammanaya']);
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
      expect(Federation.robosats.on(RobosatsNetwork.mainnet), hasLength(5));
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
