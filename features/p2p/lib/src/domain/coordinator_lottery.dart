import 'dart:math' as math;

import 'package:robosats/robosats.dart';

/// The order in which the reference proposes the coordinators of the federation, the first being the default host of its « Create » form (`federationLottery`, `frontend/src/utils/federationLottery.ts:25-49`, commit ff1998c; design note `docs/design/phase-3-making-an-order.md` § 3.9).
///
/// Each coordinator's chance is its donation to the development fund, bounded to 0 to 50, times its total fee (`maker_fee` + `taker_fee` of its `/api/info/`, or [defaultTotalFee] when its information is not loaded); the order is an exponential race on those chances (`-ln(u) / chance`, a coordinator of no chance last), with a random tie-break. The donation is the `devfund` of its `/api/info/` when loaded and a finite figure, else the badge of the federation list (`services/DevFundProfile.ts:7-42`, `models/Federation.model.ts:584-609`). The reference gives a coordinator voted in by its discovery no donation (`_votedIn`); this app has no discovery, every coordinator coming from the federation list it embeds.
///
/// It chooses the form's default only, nothing secret: its draws come from [_random], the app's own generator, not a cryptographic one, as `P2pShuffle`'s.
final class CoordinatorLottery {
  /// The total fee of a coordinator whose `/api/info/` is not loaded (`DEFAULT_TOTAL_FEE`, `federationLottery.ts:23`).
  static const double defaultTotalFee = 0.002;

  /// The largest donation counted, in percent (`federationLottery.ts:37`).
  static const double maxDevFund = 50;

  /// Draws in `[0, 1)`, as `Math.random()`.
  final double Function() _random;

  /// A lottery whose draws are [random]'s: the app gives `Random().nextDouble`, a test a fixed sequence.
  const CoordinatorLottery(this._random);

  /// [coordinators] in the order of the reference's lottery, with the `/api/info/` read of each, by short alias, in [infos].
  ///
  /// For each coordinator in turn, a draw for its race when its chance is above zero, then a draw for its tie-break, as the reference draws them.
  List<Coordinator> order(
    Iterable<Coordinator> coordinators, {
    Map<String, CoordinatorInfo> infos = const {},
  }) {
    final drawn = <({Coordinator coordinator, double weight, double tie})>[];
    for (final coordinator in coordinators) {
      final info = infos[coordinator.shortAlias];
      final chance = devFundOf(coordinator, info) * totalFeeOf(info);
      final weight = chance > 0
          ? -math.log(_random()) / chance
          : double.infinity;
      drawn.add((coordinator: coordinator, weight: weight, tie: _random()));
    }
    drawn.sort((a, b) {
      // `a.weight - b.weight || a.tie - b.tie`: two equal weights, two infinities included (whose difference is not a number), are ordered by their tie-break.
      if (a.weight == b.weight) return a.tie.compareTo(b.tie);
      return a.weight.compareTo(b.weight);
    });
    return List.unmodifiable([for (final entry in drawn) entry.coordinator]);
  }

  /// The donation counted for [coordinator]: [info]'s `devfund` when it is a finite figure, else its badge, bounded to 0 to [maxDevFund].
  static double devFundOf(Coordinator coordinator, CoordinatorInfo? info) {
    final read = info?.devfund;
    final raw = read != null && read.isFinite
        ? read
        : coordinator.badges.donatesToDevFund.toDouble();
    return math.min(maxDevFund, math.max(0, raw));
  }

  /// The total fee of a coordinator whose `/api/info/` is [info], or [defaultTotalFee] when it is not loaded.
  static double totalFeeOf(CoordinatorInfo? info) =>
      info == null ? defaultTotalFee : info.makerFee + info.takerFee;
}
