import 'dart:math' as math;

import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/testing.dart' show ScriptedMakerCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The default coordinator of the « Create » form (#179, design note `docs/design/phase-3-making-an-order.md` § 3.9): the reference's `federationLottery` (`frontend/src/utils/federationLottery.ts:25-49`), and the limits of an amount its form allows (`MakerForm.tsx:96`, `:140-158`, `AmountRange.tsx:57-77`).
void main() {
  Coordinator coordinator(String alias) =>
      Federation.robosats.byAlias(alias) ?? (throw StateError(alias));

  /// The `/api/info/` of [alias] as a coordinator of the tests gives it, with [devfund] and [makerFee] (its taker fee 0.00175).
  Future<CoordinatorInfo> infoOf(
    String alias, {
    double? devfund,
    double makerFee = 0.001,
  }) async {
    final fake =
        ScriptedMakerCoordinator(
            network: RobosatsNetwork.mainnet,
            robots: const [],
            clock: () => DateTime.utc(2026, 11, 14),
            alias: alias,
          )
          ..devfund = devfund
          ..makerFee = makerFee;
    return switch (await CoordinatorClient(
      fake,
    ).fetchInfo(coordinator(alias), RobosatsNetwork.mainnet)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  /// A lottery that draws [draws] in order, and counts them.
  (CoordinatorLottery, List<double>) lotteryOf(List<double> draws) {
    final drawn = <double>[];
    var next = 0;
    return (
      CoordinatorLottery(() {
        final value = draws[next++];
        drawn.add(value);
        return value;
      }),
      drawn,
    );
  }

  group('the lottery', () {
    test(
      'without information: the badges at the default total fee of 0.002, an exponential race',
      () {
        // temple 30, lake 30, freeport 20: chances 0.06, 0.06, 0.04.
        final (lottery, drawn) = lotteryOf([0.5, 0.1, 0.9, 0.2, 0.2, 0.3]);
        final order = lottery.order([
          coordinator('temple'),
          coordinator('lake'),
          coordinator('freeport'),
        ]);
        // -ln(0.5)/0.06 = 11.55, -ln(0.9)/0.06 = 1.76, -ln(0.2)/0.04 = 40.24.
        expect(order.map((c) => c.shortAlias), ['lake', 'temple', 'freeport']);
        expect(drawn, hasLength(6));
        expect(-math.log(0.9) / 0.06, lessThan(-math.log(0.5) / 0.06));
      },
    );

    test(
      'with information: its DevFund, bounded to 50, and its total fee; a coordinator of no chance last, with a tie-break draw only',
      () async {
        final infos = {
          'temple': await infoOf('temple', devfund: 0),
          'freeport': await infoOf('freeport', devfund: 80),
        };
        final (lottery, drawn) = lotteryOf([0.7, 0.5, 0.1, 0.5, 0.2]);
        final order = lottery.order([
          coordinator('temple'),
          coordinator('lake'),
          coordinator('freeport'),
        ], infos: infos);
        // temple: devfund 0, no race draw; lake: badge 30 × 0.002 = 0.06, weight 11.55; freeport: 50 × (0.001 + 0.00175) = 0.1375, weight 5.04.
        expect(order.map((c) => c.shortAlias), ['freeport', 'lake', 'temple']);
        expect(drawn, hasLength(5));
        expect(
          CoordinatorLottery.devFundOf(
            coordinator('freeport'),
            infos['freeport'],
          ),
          50,
        );
        expect(
          CoordinatorLottery.devFundOf(coordinator('temple'), infos['temple']),
          0,
        );
        expect(
          CoordinatorLottery.totalFeeOf(infos['freeport']),
          closeTo(0.00275, 1e-12),
        );
      },
    );

    test(
      'a coordinator whose information has no DevFund keeps its badge',
      () async {
        final info = await infoOf('ammanaya');
        expect(CoordinatorLottery.devFundOf(coordinator('ammanaya'), info), 50);
        expect(CoordinatorLottery.devFundOf(coordinator('freeport'), null), 20);
        expect(
          CoordinatorLottery.totalFeeOf(null),
          CoordinatorLottery.defaultTotalFee,
        );
      },
    );

    test(
      'coordinators of equal weight, infinite ones included, are ordered by their tie-break',
      () async {
        final infos = {
          'temple': await infoOf('temple', devfund: 0),
          'lake': await infoOf('lake', devfund: 0),
        };
        final (lottery, _) = lotteryOf([0.9, 0.1]);
        expect(
          lottery
              .order([coordinator('temple'), coordinator('lake')], infos: infos)
              .map((c) => c.shortAlias),
          ['lake', 'temple'],
        );
      },
    );

    test('a draw of 0 is an infinite weight, as -Math.log(0) is', () {
      final (lottery, _) = lotteryOf([0, 0.1, 0.5, 0.2]);
      expect(
        lottery
            .order([coordinator('temple'), coordinator('lake')])
            .map((c) => c.shortAlias),
        ['lake', 'temple'],
      );
    });
  });

  group('the limits of an amount', () {
    Future<CurrencyLimit> limitAt(double price) async {
      final fake = ScriptedMakerCoordinator(
        network: RobosatsNetwork.mainnet,
        robots: const [],
        clock: () => DateTime.utc(2026, 11, 14),
      )..prices[2] = price;
      return switch (await CoordinatorClient(
        fake,
      ).fetchLimits(coordinator('temple'), RobosatsNetwork.mainnet)) {
        Ok(:final value) =>
          value[RobosatsCurrency.fromId(2) ?? (throw StateError('EUR'))] ??
              (throw StateError('no EUR')),
        Err(:final failure) => throw StateError('$failure'),
      };
    }

    FiatAmount fiat(double value) =>
        FiatAmount.tryCreate(value) ?? (throw StateError('$value'));

    test(
      'a fixed amount within the coordinator\'s bounds with the premium, times 1.03 and 0.98',
      () async {
        final limit = await limitAt(91711.15);
        final premium = Premium.tryCreate(2) ?? (throw StateError('premium'));
        final limits = MakerAmountLimits.of(
          limit,
          premium: premium,
          sizeLimitSats: 21 * 100000000,
        );
        // 20,000 and 5,000,000 sats at 91,711.15 EUR, the premium applied, then the reference's margins.
        final low = 20000 / 100000000 * 91711.15 * 1.02 * 1.03;
        final high = 5000000 / 100000000 * 91711.15 * 1.02 * 0.98;
        expect(limits.min, closeTo(low, 1e-9));
        expect(limits.max, closeTo(high, 1e-9));
        expect(limits.allows(FixedOrderAmount(fiat(19.28))), isTrue);
        expect(limits.allows(FixedOrderAmount(fiat(19.27))), isFalse);
        expect(limits.allows(FixedOrderAmount(fiat(4583.72))), isTrue);
        expect(limits.allows(FixedOrderAmount(fiat(4583.73))), isFalse);
      },
    );

    test(
      'the maximum capped by the coordinator\'s size limit at its price, without the premium',
      () async {
        final limit = await limitAt(91711.15);
        final limits = MakerAmountLimits.of(
          limit,
          premium: Premium.tryCreate(2) ?? (throw StateError('premium')),
          sizeLimitSats: 250000,
        );
        expect(limits.max, closeTo(250000 / 100000000 * 91711.15 * 0.98, 1e-9));
      },
    );

    test('a range\'s bounds within 0.99 and 1.01 of them', () async {
      final limit = await limitAt(91711.15);
      final limits = MakerAmountLimits.of(
        limit,
        premium: Premium.tryCreate(0) ?? (throw StateError('premium')),
        sizeLimitSats: 21 * 100000000,
      );
      RangeOrderAmount range(double min, double max) =>
          RangeOrderAmount.tryCreate(fiat(min), fiat(max)) ??
          (throw StateError('range'));
      final low = limits.min * 0.99;
      final high = limits.max * 1.01;
      expect(limits.allows(range(low + 0.001, 100)), isTrue);
      expect(limits.allows(range(low - 0.001, 100)), isFalse);
      expect(limits.allows(range(1000, high - 0.001)), isTrue);
      expect(limits.allows(range(1000, high + 0.001)), isFalse);
    });
  });
}
