import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/depth_chart.dart';
import '../presentation/book_state.dart';
import '../presentation/chart_ticks.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import 'widgets/filter_choice.dart';
import 'widgets/offer_row.dart';
import 'widgets/maker_avatar.dart';

/// The « Chart » view of the book: the depth chart of the official client (`components/Charts/DepthChart/index.tsx`), drawn by the app.
///
/// Its header holds the choice of axis, « Premium » or « Price », and the zoom buttons around the value at the centre.
/// A tap opens the order nearest to it; a long press, or a pointer that hovers, shows that order and a crosshair.
/// A screen reader reads a summary of the chart.
/// Every order it draws is in the list too, under the side and payment method that show it, except the swap orders drawn when every currency is shown: the list never shows them, so a screen reader reaches those through « Search » and their URL only.
class DepthChartView extends StatefulWidget {
  final BookState state;
  final ValueChanged<PublicOrder> onOpenOrder;

  const DepthChartView({
    super.key,
    required this.state,
    required this.onOpenOrder,
  });

  @override
  State<DepthChartView> createState() => _DepthChartViewState();
}

class _DepthChartViewState extends State<DepthChartView> {
  DepthAxis _axis = DepthAxis.premium;

  /// The chart of the current book, filter and axis, built once for them.
  DepthChart? _chart;

  /// The window after a zoom, or `null` for the window the chart opens on.
  DepthWindow? _zoomed;

  /// The lines inside the current window, built once for it.
  DepthLines? _lines;

  /// The point whose order the tooltip shows, while a finger presses or a pointer hovers.
  DepthPoint? _selected;

  DepthChart get _currentChart => _chart ??= DepthChart.of(
    book: widget.state.receivedOrders,
    filter: widget.state.filter,
    axis: _axis,
  );

  DepthWindow get _window => _zoomed ?? _currentChart.window;

  DepthLines get _currentLines => _lines ??= _currentChart.linesIn(_window);

  @override
  void didUpdateWidget(covariant DepthChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // As in the official client, a new book or another filter builds the chart again and puts the zoom back.
    if (!identical(oldWidget.state.coordinators, widget.state.coordinators) ||
        oldWidget.state.filter != widget.state.filter) {
      _reset();
    }
  }

  void _reset() {
    _chart = null;
    _zoomed = null;
    _lines = null;
    _selected = null;
  }

  void _zoom(DepthWindow window) => setState(() {
    _zoomed = window;
    _lines = null;
    _selected = null;
  });

  void _select(DepthPoint? point) {
    if (point == _selected) return;
    setState(() => _selected = point);
  }

  Future<void> _pickAxis() async {
    final l10n = P2pLocalizations.of(context);
    final axis = await BullBottomSheet.show<DepthAxis>(
      context: context,
      child: BullPickerSheet<DepthAxis>(
        title: l10n.p2pBookViewChart,
        options: DepthAxis.values,
        isSelected: (axis) => axis == _axis,
        label: (axis) => axisLabel(axis, l10n),
      ),
    );
    if (!mounted || axis == null || axis == _axis) return;
    setState(() {
      _axis = axis;
      _reset();
    });
  }

  /// The name of [axis] in the selector: « Premium » or « Price ».
  static String axisLabel(DepthAxis axis, P2pLocalizations l10n) =>
      switch (axis) {
        DepthAxis.premium => l10n.p2pBookColumnPremium,
        DepthAxis.price => l10n.p2pBookColumnPrice,
      };

  /// The value between the zoom buttons: the premium as a whole number, or the price and its currency; `null` when there is no axis to draw.
  static String? centerLabel(
    DepthChart chart,
    DepthWindow window,
    P2pLocalizations l10n,
    P2pFormats formats,
  ) {
    if (!window.isDrawable) return null;
    return switch ((chart.axis, chart.priceCurrency)) {
      (DepthAxis.premium, _) => formats.chartCenterPremium(window.center),
      (DepthAxis.price, final currency?) => l10n.p2pChartCenterPrice(
        formats.price(window.center),
        currency.code,
      ),
      (DepthAxis.price, null) => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final chart = _currentChart;
    final window = _window;
    final lines = _currentLines;
    final center = centerLabel(chart, window, l10n, formats);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        BullSpacing.md,
        BullSpacing.xs,
        BullSpacing.md,
        BullSpacing.sm,
      ),
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(BullRadius.xs),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.p2pBookViewChart,
                  style: text.bodyLarge?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilterChoice(label: axisLabel(_axis, l10n), onTap: _pickAxis),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.p2pChartZoomOut,
                onPressed: window.canZoomOut
                    ? () => _zoom(window.zoomedOut())
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: colors.text,
                disabledColor: colors.outline,
              ),
              Flexible(
                child: Text(
                  center ?? '',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(
                    color: colors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.p2pChartZoomIn,
                onPressed: window.canZoomIn
                    ? () => _zoom(window.zoomedIn())
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: colors.text,
                disabledColor: colors.outline,
              ),
            ],
          ),
          Expanded(
            child: Semantics(
              container: true,
              label: switch (center) {
                final center? => l10n.p2pChartSummary(
                  center,
                  l10n.p2pChartBuyOrders(lines.buyOrders),
                  l10n.p2pChartSellOrders(lines.sellOrders),
                ),
                null => l10n.p2pChartSummaryNoAxis,
              },
              excludeSemantics: true,
              child: _plot(context, chart, window, lines, formats, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plot(
    BuildContext context,
    DepthChart chart,
    DepthWindow window,
    DepthLines lines,
    P2pFormats formats,
    P2pLocalizations l10n,
  ) {
    final colors = context.bull;
    final style =
        Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.textMuted) ??
        TextStyle(color: colors.textMuted, fontSize: 10);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    String xLabel(double value) => switch (chart.axis) {
      DepthAxis.premium => formats.chartPremium(value),
      DepthAxis.price => formats.chartPrice(value),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final layout = DepthChartLayout.of(
          size: size,
          window: window,
          top: lines.top,
          measure: (label) => _measure(label, style, direction, scaler),
          xLabel: xLabel,
          yLabel: formats.chartBtc,
        );
        final selected = _selected;
        return MouseRegion(
          onHover: (event) =>
              _select(layout?.nearestOrder(lines, event.localPosition)),
          onExit: (_) => _select(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final point = layout?.nearestOrder(lines, details.localPosition);
              if (point?.order case final order?) widget.onOpenOrder(order);
            },
            onLongPressStart: (details) =>
                _select(layout?.nearestOrder(lines, details.localPosition)),
            onLongPressMoveUpdate: (details) =>
                _select(layout?.nearestOrder(lines, details.localPosition)),
            onLongPressEnd: (_) => _select(null),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DepthChartPainter(
                      layout: layout,
                      lines: lines,
                      selected: selected,
                      legend: l10n.p2pChartBtc,
                      style: style,
                      direction: direction,
                      scaler: scaler,
                      colors: (
                        axis: colors.text,
                        buy: colors.secondary,
                        sell: colors.primary,
                      ),
                    ),
                  ),
                ),
                if ((layout, selected, selected?.order) case (
                  final layout?,
                  final point?,
                  final order?,
                ))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomSingleChildLayout(
                        delegate: _TooltipPosition(layout.offsetOf(point)),
                        child: OrderTooltip(order: order),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Size _measure(
    String label,
    TextStyle style,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }
}

/// Where the plot of the depth chart lies in its box, the ticks of its two axes, and how a value maps to a point of the screen.
@immutable
final class DepthChartLayout {
  /// The area the lines are drawn in.
  final Rect plot;
  final DepthWindow window;

  /// The amount at the top of the vertical axis.
  final double top;

  /// The ticks of the horizontal axis, with their labels.
  final List<(double, String)> xTicks;

  /// The ticks of the vertical axis, with their labels.
  final List<(double, String)> yTicks;

  /// The widest a label of the vertical axis is drawn, between the legend and its tick: a longer one is cut with an ellipsis.
  final double yLabelWidth;

  const DepthChartLayout._({
    required this.plot,
    required this.window,
    required this.top,
    required this.xTicks,
    required this.yTicks,
    required this.yLabelWidth,
  });

  /// The length of a tick, as in the official client.
  static const tickSize = 5.0;

  /// The space between a tick and its label, and around the legend of the vertical axis.
  static const gap = 4.0;

  /// The space above and to the right of the plot.
  static const margin = 10.0;

  /// The least distance between two ticks of the horizontal and of the vertical axis.
  static const xTickSpacing = 72.0;
  static const yTickSpacing = 40.0;

  /// The layout of a chart of [size], or `null` when [window] cannot be drawn or the box is too small for a plot.
  ///
  /// [measure] gives the size of a label as it will be drawn; the plot leaves room for the labels of the ticks and for the legend of the vertical axis, written upright.
  static DepthChartLayout? of({
    required Size size,
    required DepthWindow window,
    required double top,
    required Size Function(String) measure,
    required String Function(double) xLabel,
    required String Function(double) yLabel,
  }) {
    if (!window.isDrawable || !(top > 0) || !top.isFinite) return null;
    final lineHeight = measure('0').height;
    final bottom = size.height - lineHeight - tickSize - gap;
    final plotHeight = bottom - margin;
    if (!(plotHeight > 0)) return null;
    final yTicks = [
      for (final value in ChartTicks.between(
        0,
        top,
        math.max(2, plotHeight ~/ yTickSpacing),
      ))
        (value, yLabel(value)),
    ];
    var widest = 0.0;
    for (final (_, label) in yTicks) {
      widest = math.max(widest, measure(label).width);
    }
    // The labels of the vertical axis never take more than half of the width, however long a hostile value writes.
    final left = math.min(
      lineHeight + gap + widest + gap + tickSize,
      size.width / 2,
    );
    final plotWidth = size.width - left - margin;
    if (!(plotWidth > 0)) return null;

    List<(double, String)> xTicksFor(int count) => [
      for (final value in ChartTicks.between(window.min, window.max, count))
        (value, xLabel(value)),
    ];
    var xTicks = xTicksFor(math.max(2, plotWidth ~/ xTickSpacing));
    var widestX = 0.0;
    for (final (_, label) in xTicks) {
      widestX = math.max(widestX, measure(label).width);
    }
    // Labels too wide for their spacing are written fewer.
    if (xTicks.length > 1 && widestX + gap * 2 > plotWidth / xTicks.length) {
      xTicks = xTicksFor(math.max(1, plotWidth ~/ (widestX + gap * 4)));
    }
    return DepthChartLayout._(
      plot: Rect.fromLTRB(left, margin, left + plotWidth, bottom),
      window: window,
      top: top,
      xTicks: xTicks,
      yTicks: yTicks,
      yLabelWidth: math.max(0, left - tickSize - gap - gap - lineHeight),
    );
  }

  /// Where a label of [width] that would start at [left] starts, moved sideways so as to stay within a box of [boxWidth], from its left edge when it is wider.
  static double keepInside(double left, double width, double boxWidth) =>
      left.clamp(0, math.max(0, boxWidth - width));

  /// The horizontal position of [x], kept inside the plot.
  double dx(double x) {
    final ratio = (x - window.min) / (window.max - window.min);
    return plot.left + plot.width * (ratio.isFinite ? ratio.clamp(0, 1) : 0);
  }

  /// The vertical position of [btc], kept inside the plot.
  double dy(double btc) {
    final ratio = btc / top;
    return plot.bottom - plot.height * (ratio.isFinite ? ratio.clamp(0, 1) : 0);
  }

  Offset offsetOf(DepthPoint point) => Offset(dx(point.x), dy(point.btc));

  /// The point that carries an order nearest to [position], on either line, or `null` when no line has one or [position] is outside the plot.
  ///
  /// Like the mesh of the official client, which covers the plot and not its axes, it does not need to be close: the whole plot leads to an order.
  DepthPoint? nearestOrder(DepthLines lines, Offset position) {
    if (!plot.contains(position)) return null;
    DepthPoint? nearest;
    var best = double.infinity;
    for (final point in [...lines.buy, ...lines.sell]) {
      if (point.order == null) continue;
      final distance = (offsetOf(point) - position).distanceSquared;
      if (distance < best) {
        best = distance;
        nearest = point;
      }
    }
    return nearest;
  }
}

/// The colours of the chart: its axes and centre line, and its two lines.
typedef _ChartColors = ({Color axis, Color buy, Color sell});

/// Paints the layers of the official client, in its order: axes, areas, crosshair, lines, then the centre line.
final class _DepthChartPainter extends CustomPainter {
  final DepthChartLayout? layout;
  final DepthLines lines;
  final DepthPoint? selected;
  final String legend;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  final _ChartColors colors;

  const _DepthChartPainter({
    required this.layout,
    required this.lines,
    required this.selected,
    required this.legend,
    required this.style,
    required this.direction,
    required this.scaler,
    required this.colors,
  });

  /// The opacity of the areas under the lines, and the width of the lines, as in the official client.
  static const areaOpacity = 0.2;
  static const lineWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = this.layout;
    if (layout == null) return;
    final plot = layout.plot;
    final axis = Paint()
      ..color = colors.axis
      ..strokeWidth = 1;

    // Axes: the two domain lines, their ticks and labels, and the legend « BTC ».
    canvas
      ..drawLine(plot.bottomLeft, plot.topLeft, axis)
      ..drawLine(plot.bottomLeft, plot.bottomRight, axis);
    for (final (value, label) in layout.xTicks) {
      final x = layout.dx(value);
      canvas.drawLine(
        Offset(x, plot.bottom),
        Offset(x, plot.bottom + DepthChartLayout.tickSize),
        axis,
      );
      _text(
        canvas,
        label,
        Offset(
          x,
          plot.bottom + DepthChartLayout.tickSize + DepthChartLayout.gap,
        ),
        horizontal: 0.5,
        vertical: 0,
        maxWidth: plot.width,
        boxWidth: size.width,
      );
    }
    for (final (value, label) in layout.yTicks) {
      final y = layout.dy(value);
      canvas.drawLine(
        Offset(plot.left - DepthChartLayout.tickSize, y),
        Offset(plot.left, y),
        axis,
      );
      _text(
        canvas,
        label,
        Offset(plot.left - DepthChartLayout.tickSize - DepthChartLayout.gap, y),
        horizontal: 1,
        vertical: 0.5,
        maxWidth: layout.yLabelWidth,
      );
    }
    canvas
      ..save()
      ..translate(0, plot.center.dy)
      ..rotate(-math.pi / 2);
    _text(
      canvas,
      legend,
      Offset.zero,
      horizontal: 0.5,
      vertical: 0,
      maxWidth: plot.height,
    );
    canvas.restore();

    canvas
      ..save()
      ..clipRect(plot.inflate(lineWidth));
    for (final (line, color) in [
      (lines.buy, colors.buy),
      (lines.sell, colors.sell),
    ]) {
      if (line.isEmpty) continue;
      final area = _path(layout, line)
        ..lineTo(layout.dx(line.last.x), plot.bottom)
        ..lineTo(layout.dx(line.first.x), plot.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = color.withValues(alpha: areaOpacity),
      );
    }

    // The crosshair of the point shown, dashed.
    if (selected case final point?) {
      final at = layout.offsetOf(point);
      _dashed(
        canvas,
        Offset(at.dx, plot.top),
        Offset(at.dx, plot.bottom),
        axis,
      );
      _dashed(
        canvas,
        Offset(plot.left, at.dy),
        Offset(plot.right, at.dy),
        axis,
      );
    }

    for (final (line, color) in [
      (lines.buy, colors.buy),
      (lines.sell, colors.sell),
    ]) {
      if (line.isEmpty) continue;
      canvas.drawPath(
        _path(layout, line),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final center = layout.dx(layout.window.center);
    canvas
      ..drawLine(Offset(center, plot.top), Offset(center, plot.bottom), axis)
      ..restore();
  }

  static Path _path(DepthChartLayout layout, List<DepthPoint> line) {
    final path = Path();
    for (final (index, point) in line.indexed) {
      final at = layout.offsetOf(point);
      if (index == 0) {
        path.moveTo(at.dx, at.dy);
      } else {
        path.lineTo(at.dx, at.dy);
      }
    }
    return path;
  }

  /// A dashed line of dashes and gaps of 6, as the crosshair of the official client.
  static void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    final length = (to - from).distance;
    if (!(length > 0)) return;
    final direction = (to - from) / length;
    for (var start = 0.0; start < length; start += dash * 2) {
      final end = math.min(start + dash, length);
      canvas.drawLine(from + direction * start, from + direction * end, paint);
    }
  }

  /// Writes [label], cut at [maxWidth], so that the point at the fractions [horizontal] and [vertical] of its box lies on [anchor], moved sideways if needed to stay within [boxWidth].
  void _text(
    Canvas canvas,
    String label,
    Offset anchor, {
    required double horizontal,
    required double vertical,
    required double maxWidth,
    double? boxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    var left = anchor.dx - painter.width * horizontal;
    if (boxWidth != null) {
      left = DepthChartLayout.keepInside(left, painter.width, boxWidth);
    }
    painter.paint(canvas, Offset(left, anchor.dy - painter.height * vertical));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_DepthChartPainter old) =>
      old.layout != layout ||
      !identical(old.lines, lines) ||
      old.selected != selected ||
      old.legend != legend ||
      old.style != style ||
      old.direction != direction ||
      old.scaler != scaler ||
      old.colors != colors;
}

/// What the official client shows of an order on the chart (`Charts/helpers/OrderTooltip`): the maker's robot, the amount and its currency, the payment methods, and the coordinator.
///
/// The official client marks the coordinator with a badge on the robot; here its name is written below, cleaned and bounded as every P2P screen shows it.
/// The payment methods are maker text, shown as plain text.
class OrderTooltip extends StatelessWidget {
  final PublicOrder order;

  const OrderTooltip({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(BullRadius.xs),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MakerAvatar(order: order, size: 32),
          const Gap(BullSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: formats.orderAmount(order.amount)),
                      TextSpan(text: ' ${order.currency.code}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(color: colors.text),
                ),
                Text(
                  OfferRow.paymentMethodsLine(order.paymentMethods, l10n),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(color: colors.textMuted),
                ),
                Text(
                  CoordinatorText.of(
                    order.coordinator.longAlias,
                    maxCodePoints: CoordinatorText.name,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the tooltip beside the point it shows, above it when there is room, and always inside the chart.
final class _TooltipPosition extends SingleChildLayoutDelegate {
  final Offset anchor;

  const _TooltipPosition(this.anchor);

  static const _offset = 12.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx + _offset;
    if (x + childSize.width > size.width) {
      x = anchor.dx - _offset - childSize.width;
    }
    var y = anchor.dy - _offset - childSize.height;
    if (y < 0) y = anchor.dy + _offset;
    return Offset(
      x.clamp(0, math.max(0, size.width - childSize.width)),
      y.clamp(0, math.max(0, size.height - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(_TooltipPosition old) => old.anchor != anchor;
}
