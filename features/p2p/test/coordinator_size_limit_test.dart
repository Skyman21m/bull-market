import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/coordinator_size_limit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

/// [base] with other badges and another date in the federation list.
Coordinator _with(
  Coordinator base, {
  bool founder = false,
  String established = '2026-01-01',
}) => Coordinator(
  shortAlias: base.shortAlias,
  longAlias: base.longAlias,
  identifier: base.identifier,
  description: base.description,
  motto: base.motto,
  color: base.color,
  established: established,
  nostrHexPubkey: base.nostrHexPubkey,
  contact: base.contact,
  badges: CoordinatorBadges(
    isFounder: founder,
    donatesToDevFund: base.badges.donatesToDevFund,
    hasGoodOpSec: base.badges.hasGoodOpSec,
    hasLargeLimits: base.badges.hasLargeLimits,
  ),
  policies: base.policies,
  mainnet: base.mainnet,
  testnet: base.testnet,
  mainnetNodesPubkeys: base.mainnetNodesPubkeys,
  testnetNodesPubkeys: base.testnetNodesPubkeys,
  federated: base.federated,
);

/// The recorded `/api/info/` of temple on mainnet, with [changes].
Future<CoordinatorInfo> _info(Map<String, Object?> changes) async {
  final json =
      jsonDecode(
              File(
                '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>
        ..addAll(changes);
  final result = await CoordinatorClient(
    FakeTransport(infos: {'temple': json}),
  ).fetchInfo(coordinator('temple'), RobosatsNetwork.mainnet);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
}

void main() {
  final base = coordinator('freeport');
  final established = DateTime.utc(2026);
  const day = Duration(days: 1);

  double limitAfter(Duration age, {bool founder = false}) =>
      CoordinatorSizeLimit.of(
        _with(base, founder: founder),
        established.add(age),
      ).sats;

  test('a founder is trusted with 21 BTC from its first day', () {
    expect(limitAfter(Duration.zero, founder: true), 2100000000);
    expect(CoordinatorSizeLimit.mature, 2100000000);
  });

  test('a new coordinator starts at 250,000 sats', () {
    expect(limitAfter(Duration.zero), 250000);
    expect(limitAfter(const Duration(milliseconds: 1)), 250000);
    expect(limitAfter(const Duration(days: 14)), 250000);
    // A date in the future, as a clock set wrong could give.
    expect(limitAfter(-day * 30), 250000);
  });

  test('it gains 30 % at each difficulty adjustment of 14 days', () {
    expect(
      limitAfter(const Duration(days: 14, milliseconds: 1)),
      closeTo(325000, 1e-6),
    );
    expect(
      limitAfter(const Duration(days: 28, hours: 1)),
      closeTo(422500, 1e-6),
    );
    // Five adjustments after the first period: 250,000 × 1.3^5, a number of sats that is not whole, as in the official client.
    expect(limitAfter(day * 75), closeTo(928232.5, 1e-6));
  });

  test('it becomes 21 BTC after the twelfth adjustment', () {
    // Twelve periods started: 250,000 × 1.3^11, about 4.48 million sats.
    expect(limitAfter(day * (14 * 11 + 1)), closeTo(4480400.985, 0.01));
    expect(limitAfter(day * (14 * 12 + 1)), 2100000000);
    expect(limitAfter(day * 3650), 2100000000);
  });

  test('large limits are above 3 million sats', () {
    // 250,000 × 1.3^9 is about 2.65 million, 250,000 × 1.3^10 about 3.45 million.
    expect(
      CoordinatorSizeLimit.of(
        _with(base),
        established.add(day * (14 * 9 + 1)),
      ).isLarge,
      isFalse,
    );
    expect(
      CoordinatorSizeLimit.of(
        _with(base),
        established.add(day * (14 * 10 + 1)),
      ).isLarge,
      isTrue,
    );
    expect(
      CoordinatorSizeLimit.of(_with(base, founder: true), established).isLarge,
      isTrue,
    );
  });

  test('the embedded coordinators on the clock of the tests', () {
    expect(
      CoordinatorSizeLimit.of(coordinator('temple'), testNow).sats,
      CoordinatorSizeLimit.mature,
    );
    // FreePort joined on 2026-08-28: six periods started by 2026-11-10.
    expect(
      CoordinatorSizeLimit.of(coordinator('freeport'), testNow).sats,
      closeTo(928232.5, 1e-6),
    );
  });

  test('the order and swap sizes are the smallest of the limits', () async {
    final young = CoordinatorSizeLimit.of(_with(base), established);
    final mature = CoordinatorSizeLimit.of(
      _with(base, founder: true),
      established,
    );
    final info = await _info({'max_order_size': 6000000, 'max_swap': 4000000});

    expect(young.maxOrderSize(info), 250000);
    expect(young.maxSwapSize(info), 250000);
    expect(mature.maxOrderSize(info), 6000000);
    expect(mature.maxSwapSize(info), 4000000);

    final bigSwap = await _info({
      'max_order_size': 5000000,
      'max_swap': 9000000,
    });
    expect(mature.maxSwapSize(bigSwap), 5000000);
  });
}
