import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import 'book_filter.dart';

/// What the depth chart lays along its horizontal axis, the choice of its selector.
enum DepthAxis {
  /// The premium of each order, in percent: the official client's default.
  premium,

  /// The price of each order in the chosen currency, or in US dollars when the book shows every currency.
  price,
}

/// Which of the two middle votes the coordinators' vote keeps when they are even in number.
enum MiddleVote {
  /// The one nearer zero, the lower when both are as near: for the centre of the chart, since a premium near zero is the market's own, and the official client's centre before any coordinator answers is zero; for prices, which are positive, it is the lower.
  nearestZero,

  /// The lower: for the market price.
  lower,
}

/// A point of a depth line: [btc] is what the orders up to [x] add up to.
///
/// The top of the step an order adds carries that [order]; the other points only draw the line.
@immutable
final class DepthPoint {
  final double x;
  final double btc;
  final PublicOrder? order;

  const DepthPoint(this.x, this.btc, [this.order]);

  @override
  bool operator ==(Object other) =>
      other is DepthPoint &&
      other.x == x &&
      other.btc == btc &&
      other.order == order;

  @override
  int get hashCode => Object.hash(x, btc, order);

  @override
  String toString() =>
      'DepthPoint($x, $btc${order == null ? '' : ', #${order?.id}'})';
}

/// The part of the horizontal axis the chart shows: [center] plus or minus [halfRange], which each zoom changes by [step].
@immutable
final class DepthWindow {
  final double center;
  final double halfRange;
  final double step;

  const DepthWindow({
    required this.center,
    required this.halfRange,
    required this.step,
  });

  /// The largest value either bound may reach: far beyond any premium in percent or any price per bitcoin, and small enough to be written in a label.
  static const maxMagnitude = 1e15;

  double get min => center - halfRange;
  double get max => center + halfRange;

  /// Whether the window has a width the chart can draw: bounds within [maxMagnitude], the larger above the smaller.
  bool get isDrawable => _fits(min) && _fits(max) && max > min;

  /// « + », which narrows the window by one step.
  ///
  /// The official client allows it while the half range is above 1.
  /// Here it also stops before the half range would fall below half a step, so that the window never closes up into a point.
  bool get canZoomIn =>
      isDrawable &&
      step > 0 &&
      step.isFinite &&
      halfRange > 1 &&
      halfRange - step >= step / 2;

  /// « − », which widens the window by one step, as long as its bounds stay within [maxMagnitude].
  bool get canZoomOut =>
      isDrawable &&
      step > 0 &&
      step.isFinite &&
      _fits(center + halfRange + step) &&
      _fits(center - halfRange - step);

  static bool _fits(double value) =>
      value.isFinite && value.abs() <= maxMagnitude;

  DepthWindow zoomedIn() => canZoomIn
      ? DepthWindow(center: center, halfRange: halfRange - step, step: step)
      : this;

  DepthWindow zoomedOut() => canZoomOut
      ? DepthWindow(center: center, halfRange: halfRange + step, step: step)
      : this;

  @override
  bool operator ==(Object other) =>
      other is DepthWindow &&
      other.center == center &&
      other.halfRange == halfRange &&
      other.step == step;

  @override
  int get hashCode => Object.hash(center, halfRange, step);

  @override
  String toString() => 'DepthWindow($center ± $halfRange, step $step)';
}

/// The two lines of the chart inside one window.
@immutable
final class DepthLines {
  /// The orders of makers who buy, added from the right edge of the window towards the left.
  final List<DepthPoint> buy;

  /// The orders of makers who sell, added from the left edge of the window towards the right.
  final List<DepthPoint> sell;

  const DepthLines({this.buy = const [], this.sell = const []});

  /// The top of the vertical axis: the largest amount on either line, or 1 when there is none above zero.
  double get top {
    var top = 0.0;
    for (final point in [...buy, ...sell]) {
      if (point.btc > top) top = point.btc;
    }
    return top > 0 && top.isFinite ? top : 1;
  }

  /// How many buy orders add a step inside the window.
  int get buyOrders => buy.where((point) => point.order != null).length;

  /// How many sell orders add a step inside the window.
  int get sellOrders => sell.where((point) => point.order != null).length;
}

/// The depth chart of the book, as the official client builds it (`components/Charts/DepthChart/index.tsx`).
///
/// It draws every order received of the chosen currencies and hosts, swaps included when every currency is shown; neither the side nor the payment methods of the filter apply.
/// Each line adds up, order after order along the axis, the bitcoin each order trades at its largest amount.
/// The window it opens on is centred on the orders it draws, one vote per coordinator: the middle one of the coordinators' median premiums or prices (of the two middle ones, the one nearer zero), cut to a whole number toward zero.
/// The official client centres its premium axis on the 24-hour non-KYC premium of the coordinators (`/api/info/`), which the book does not read, and its fallback is the median of every order received; one vote per coordinator, after the filter, keeps a coordinator that floods the book from moving the window away from the others, and choosing a host brings the chart back to that host's orders.
@immutable
final class DepthChart {
  final DepthAxis axis;

  /// The currency of the price axis: the one chosen, or US dollars when every currency is shown or several are chosen, as the official client prices every currency when it shows them all; `null` on the premium axis.
  final RobosatsCurrency? priceCurrency;

  /// The window the chart opens on, which the zoom buttons narrow or widen.
  final DepthWindow window;

  /// The orders the chart draws, along the axis.
  final List<_PlacedOrder> _orders;

  const DepthChart._(this.axis, this.priceCurrency, this.window, this._orders);

  /// The half range and the step of the premium axis in the official client.
  static const premiumHalfRange = 8.0;
  static const premiumStep = 0.5;

  /// What the zoom of the price axis moves by: a tenth of its opening half range.
  static const priceSteps = 10;

  /// When every order of the price axis has the same price, its window would have no width: it then spans this fraction of the price either side, the width of the premium axis.
  static const flatPriceHalfRange = 0.08;

  /// The most an order can add to a line: every bitcoin there will be.
  static const maxBtc = 21000000.0;

  /// The chart of [book], every order received, under the currencies and the hosts of [filter], along [axis].
  factory DepthChart.of({
    required Iterable<PublicOrder> book,
    required BookFilter filter,
    required DepthAxis axis,
  }) {
    final all = book.toList();
    final priceCurrency = switch (axis) {
      DepthAxis.premium => null,
      DepthAxis.price => switch (filter.currencies) {
        final chosen when chosen.length == 1 => chosen.single,
        _ => RobosatsCurrency.fromId(_usdId),
      },
    };
    final market = priceCurrency == null
        ? null
        : _marketPrice(all, filter.hosts, priceCurrency);
    double? place(PublicOrder order) => switch (axis) {
      DepthAxis.premium => order.premium.percent,
      DepthAxis.price => market == null ? null : priceAt(market, order),
    };

    final placed = [
      for (final (index, order) in all.indexed)
        if (filter.showsInDepthChart(order))
          if (place(order) case final x?)
            _PlacedOrder(order, x, btcOf(order), index),
    ]..sort();
    final center = wholeTowardZero(
      medianOfCoordinators([
            for (final order in placed) (order.order.coordinator, order.x),
          ], middle: MiddleVote.nearestZero) ??
          0,
    );
    final window = switch (axis) {
      DepthAxis.premium => DepthWindow(
        center: center,
        halfRange: premiumHalfRange,
        step: premiumStep,
      ),
      // Without a market price, or without an order to draw, there is no price axis: a window of no width, which the chart does not draw.
      DepthAxis.price when placed.isEmpty => const DepthWindow(
        center: 0,
        halfRange: 0,
        step: 0,
      ),
      DepthAxis.price => _priceWindow(center, [
        for (final order in placed) order.x,
      ]),
    };
    return DepthChart._(axis, priceCurrency, window, placed);
  }

  /// [value] cut to a whole number toward zero, as `~~` does, never a negative zero, which a locale writes « -0 ».
  ///
  /// Unlike `~~`, it does not wrap around beyond 32 bits.
  static double wholeTowardZero(double value) {
    final whole = value.truncateToDouble();
    return whole == 0 ? 0 : whole;
  }

  /// The market price of [currency]: the one the orders of [hosts] imply, when hosts are chosen and their orders give one, else the one the orders of every coordinator imply.
  static double? _marketPrice(
    List<PublicOrder> all,
    Set<Coordinator> hosts,
    RobosatsCurrency currency,
  ) {
    if (hosts.isNotEmpty) {
      final own = impliedMarketPrice(
        all.where((order) => hosts.contains(order.coordinator)),
        currency,
      );
      if (own != null) return own;
    }
    return impliedMarketPrice(all, currency);
  }

  /// The id of US dollars, the currency of the price axis when every currency is shown.
  static const _usdId = 1;

  /// The window of the price axis: from its centre to the highest price drawn either side, moved by a tenth of that at each zoom.
  static DepthWindow _priceWindow(double center, List<double> places) {
    var highest = center;
    for (final x in places) {
      if (x > highest) highest = x;
    }
    var halfRange = highest - center;
    if (!(halfRange > 0) || !halfRange.isFinite) {
      final flat = center.abs() * flatPriceHalfRange;
      halfRange = flat > 0 && flat.isFinite ? flat : 1;
    }
    return DepthWindow(
      center: center,
      halfRange: halfRange,
      step: halfRange / priceSteps,
    );
  }

  /// The orders that add a step inside [window]: the two lines of the chart.
  DepthLines linesIn(DepthWindow window) {
    if (!window.isDrawable) return const DepthLines();
    return DepthLines(
      buy: _close(
        _line([
          for (final placed in _orders.reversed)
            if (placed.order.type == OrderType.buy) placed,
        ], window),
        from: window.max,
        to: window.min,
      ),
      sell: _close(
        _line([
          for (final placed in _orders)
            if (placed.order.type == OrderType.sell) placed,
        ], window),
        from: window.min,
        to: window.max,
      ),
    );
  }

  /// Adds the orders up in the given order and keeps the steps strictly inside [window], as `generateSerie` does: the orders outside still count in the sum.
  static List<DepthPoint> _line(List<_PlacedOrder> orders, DepthWindow window) {
    final points = <DepthPoint>[];
    var sum = 0.0;
    for (final placed in orders) {
      final before = sum;
      sum += placed.btc;
      if (placed.x > window.min && placed.x < window.max) {
        points
          ..add(DepthPoint(placed.x, before))
          ..add(DepthPoint(placed.x, sum, placed.order));
      }
    }
    return points;
  }

  /// Takes a line from the edge [from] to the edge [to], as `closeSerie` does: a line that does not start at zero starts flat from [from], and every line ends flat at [to].
  static List<DepthPoint> _close(
    List<DepthPoint> line, {
    required double from,
    required double to,
  }) {
    if (line.isEmpty) return const [];
    return [
      if (line.first.btc != 0) DepthPoint(from, line.first.btc),
      ...line,
      DepthPoint(to, line.last.btc),
    ];
  }

  /// The vote of the coordinators: the median of the values of each coordinator, then the middle one of those, one vote per coordinator however many orders it sends; `null` when there is no value.
  ///
  /// With an even number of votes, it keeps one of the two middle votes as [middle] says, never their mean, which could fall between two coordinators where neither has an order.
  /// It is a prior, not a proof: one coordinator against one cannot be decided by counting, and a majority of coordinators that flood the book wins; choosing a host is the recourse.
  static double? medianOfCoordinators(
    Iterable<(Coordinator, double)> values, {
    required MiddleVote middle,
  }) {
    final byCoordinator = <Coordinator, List<double>>{};
    for (final (coordinator, value) in values) {
      (byCoordinator[coordinator] ??= []).add(value);
    }
    final votes = [for (final own in byCoordinator.values) ?median(own)]
      ..sort();
    if (votes.isEmpty) return null;
    final half = votes.length ~/ 2;
    if (votes.length.isOdd) return votes[half];
    final (low, high) = (votes[half - 1], votes[half]);
    return switch (middle) {
      MiddleVote.lower => low,
      MiddleVote.nearestZero => high.abs() < low.abs() ? high : low,
    };
  }

  /// The median of [values] as `matchMedian` computes it, or `null` when there is none.
  ///
  /// Two middle values are halved before they are added, so that two huge values cannot overflow.
  static double? median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return sorted[middle - 1] / 2 + sorted[middle] / 2;
  }

  /// The market price of [currency] the orders of [book] imply: each order's price without its premium, the median for each coordinator, then the vote of the coordinators, the lower of the two middle votes when they are even in number; `null` when no order gives one.
  ///
  /// The official client prices the axis with the market price of a coordinator (`/api/limits/`), which the book does not read: each order's own price, which its coordinator computed from its market price and the premium, gives it back.
  /// One vote per coordinator keeps a coordinator that floods the book from setting the price of the others.
  static double? impliedMarketPrice(
    Iterable<PublicOrder> book,
    RobosatsCurrency currency,
  ) => medianOfCoordinators([
    for (final order in book)
      if (order.currency == currency)
        if (order.price case final price?)
          if (price / (1 + order.premium.percent / 100) case final market
              when market.isFinite && market > 0)
            (order.coordinator, market),
  ], middle: MiddleVote.lower);

  /// Where [order] lies on the price axis: [market] with the order's premium, as `base_price` in the official client, or `null` when that is not a finite number.
  static double? priceAt(double market, PublicOrder order) {
    final price = market * (1 + order.premium.percent / 100);
    return price.isFinite ? price : null;
  }

  /// The bitcoin [order] trades at its largest amount: the sats its coordinator gives (`satoshis_now`), or else its largest amount at its price, or nothing.
  ///
  /// It is never more than [maxBtc], so that the lines stay finite whatever a coordinator sends.
  static double btcOf(PublicOrder order) {
    final btc = switch ((order.satoshisNow, order.price)) {
      (final sats?, _) => sats.value.toDouble() / 100000000,
      (null, final price?) => order.amount.max.value / price,
      (null, null) => 0.0,
    };
    if (!btc.isFinite || btc <= 0) return 0;
    return math.min(btc, maxBtc);
  }
}

/// An order of the chart, with its place along the axis and the bitcoin it adds.
///
/// Orders are sorted by place, and equal places keep the order of the book, as the stable sort of the official client does.
@immutable
final class _PlacedOrder implements Comparable<_PlacedOrder> {
  final PublicOrder order;
  final double x;
  final double btc;
  final int index;

  const _PlacedOrder(this.order, this.x, this.btc, this.index);

  @override
  int compareTo(_PlacedOrder other) {
    final byPlace = x.compareTo(other.x);
    return byPlace != 0 ? byPlace : index.compareTo(other.index);
  }
}
