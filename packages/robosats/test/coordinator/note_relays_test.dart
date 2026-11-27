import 'dart:typed_data';

import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// Where the recovery note of a Garage Key is written and read (#81): every coordinator relay of the network, and the requests as the official client names them.
void main() {
  test('every coordinator with a relay on the network, in the federation\'s order', () {
    for (final network in RobosatsNetwork.values) {
      final relays = nostrRelaysOfNetwork(Federation.robosats, network);
      expect(relays, [
        for (final coordinator in Federation.robosats.coordinators)
          ?OutgoingNostrChatMessage.relayUrl(coordinator, network),
      ]);
      expect(relays.every((relay) => relay.path == '/relay/'), isTrue);
    }
    expect(
      nostrRelaysOfNetwork(Federation.robosats, RobosatsNetwork.mainnet),
      hasLength(Federation.robosats.coordinators.length),
    );
  });

  test('the filters of a note are relay filters under the official client\'s label', () {
    final key = switch (GarageKey.fromBytes(Uint8List.fromList(List.filled(32, 5)))) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    final List<NostrRelayFilter> filters = GarageRecoveryNote.filters(key);
    expect(filters.map((filter) => filter.subscriptionLabel), [
      'accountRecovery',
      'accountRecovery',
    ]);
    expect(jsonDecode(filters.first.toJson()), {
      'kinds': [1059],
      '#p': [key.recoveryNostrKeyPair.publicKeyHex],
    });
  });

  test('a read prints its counts, never its events', () {
    final read = NostrRelayRead(
      events: ['{"secret":"x"}'],
      complete: true,
      label: 'answered',
    );
    expect(read.toString(), isNot(contains('secret')));
    expect(read.events, hasLength(1));
    expect(() => read.events.add('y'), throwsUnsupportedError);
    expect(const NostrRelayRead.none('unreachable').complete, isFalse);
  });
}
