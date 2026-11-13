import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/map_marks.dart';
import '../domain/web_mercator.dart';
import '../domain/world_map.dart';
import '../presentation/book_state.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import 'depth_chart_view.dart';
import 'widgets/offer_row.dart';

/// The « Map » view of the book: the map chart of the official client (`components/Charts/MapChart`, `components/Map/index.tsx`), drawn by the app.
///
/// The world is the bundled outline of the countries (`WorldMap`), in Web Mercator as Leaflet draws it, with no tile and no request: the official client's « Show tiles », which fetches tiles from a third party outside Tor, is left out.
/// Each order of the book with a position has a pin, red for a seller and in the secondary colour for a buyer, as the official client colours them; pins that would overlap are grouped with their count (`MapMarks`).
/// A drag moves the map and a pinch zooms it, within the official client's zooms, and the « + » and « − » buttons zoom too, as Leaflet's zoom control does.
/// A tap on a pin opens its order, as a tap on the chart does; a tap on a group zooms in on it, or lists its orders when zooming cannot part them; a long press, or a pointer that hovers, shows the order of a pin.
/// It shows the orders the chart shows, those of the currency and the host of the filter, and only those with a position.
/// A screen reader reads a summary, then each pin and group in view, which it can open as a tap does; these orders are in the list too.
/// Nothing moves by itself, so there is no animation to stop for reduced motion.
class MapChartView extends StatefulWidget {
  final BookState state;
  final DateTime now;
  final ValueChanged<PublicOrder> onOpenOrder;

  const MapChartView({
    super.key,
    required this.state,
    required this.now,
    required this.onOpenOrder,
  });

  /// The key of the world map in the app's bundle.
  static const worldAsset =
      'packages/${WorldMapSource.package}/${WorldMapSource.asset}';

  /// The slop of a drag on the map, in points: below the slop of the scroll view that holds the map, so that a drag that starts on the map moves the map, as a drag of more than Leaflet's 3 pixels does.
  static const touchSlop = 3.0;

  /// The world map of [bundle], read once for it: `null` when the asset is not what `tools/troc_world_map.py` writes.
  static Future<WorldMap?> worldOf(AssetBundle bundle) =>
      (_worlds[bundle] ??= _WorldLoad(bundle)).future;

  static final _worlds = Expando<_WorldLoad>();

  @override
  State<MapChartView> createState() => _MapChartViewState();
}

/// The world map of one bundle, once it is read, and its outline, built once for every view that shows it.
final class _WorldLoad {
  late final Future<WorldMap?> future;
  bool done = false;
  Path? outline;

  _WorldLoad(AssetBundle bundle) {
    future = bundle.load(MapChartView.worldAsset).then((data) {
      final world = WorldMap.parse(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      outline = world == null ? null : MapChartPainter.outline(world);
      done = true;
      return world;
    });
  }
}

class _MapChartViewState extends State<MapChartView> {
  MapCamera _camera = const MapCamera();

  /// The marks of the current book and filter, built once for them.
  MapMarks? _marks;

  /// The outline of the world map at zoom 0, once it is read: `null` before, and when it could not be.
  Path? _worldPath;
  AssetBundle? _bundle;

  /// The camera and the point under the fingers when a drag or a pinch started.
  MapCamera? _gestureCamera;
  Offset? _gestureFocal;

  /// The pin whose order the tooltip shows, while a finger presses or a pointer hovers.
  MapPin? _selected;

  MapMarks get _currentMarks => _marks ??= MapMarks.of(
    widget.state.receivedOrders.where(widget.state.filter.showsInDepthChart),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (identical(bundle, _bundle)) return;
    _bundle = bundle;
    final load = MapChartView._worlds[bundle] ??= _WorldLoad(bundle);
    if (load.done) {
      _worldPath = load.outline;
    } else {
      unawaited(
        load.future.then((_) {
          if (mounted && identical(_bundle, bundle)) {
            setState(() => _worldPath = load.outline);
          }
        }),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MapChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new book or another filter groups the orders again; the map stays where the user left it, as the official client's does.
    if (!identical(oldWidget.state.coordinators, widget.state.coordinators) ||
        oldWidget.state.filter != widget.state.filter) {
      _marks = null;
      _selected = null;
    }
  }

  void _select(MapPin? pin) {
    if (pin == _selected) return;
    setState(() => _selected = pin);
  }

  void _move(MapCamera camera) {
    if (camera == _camera) return;
    setState(() => _camera = camera);
  }

  /// A tap on [mark], or its activation by a screen reader: a pin opens its order, a group zooms in on itself or lists its orders.
  void _open(MapLayout layout, MapMark? mark) {
    switch (mark) {
      case MapPin(:final order):
        widget.onOpenOrder(order);
      case final MapGroup group:
        _openGroup(layout, group);
      case null:
        break;
    }
  }

  /// What the official client does on a tap of a cluster (`_zoomOrSpiderfy` of Leaflet.markercluster): a group that zooming cannot part shows its orders, here as a list rather than spread out around it; any other zooms in on its orders.
  void _openGroup(MapLayout layout, MapGroup group) {
    // The marks the group was drawn from, never those of a newer book.
    final marks = layout.marks;
    if (marks.staysTogether(group)) {
      unawaited(_listGroup(group));
      return;
    }
    _move(
      layout.camera.zoomedOnGroup(
        group,
        splitLevel: marks.splitLevel(group, layout.level),
        view: layout.size,
      ),
    );
  }

  Future<void> _listGroup(MapGroup group) async {
    final order = await BullBottomSheet.show<PublicOrder>(
      context: context,
      child: MapGroupSheet(group: group, now: widget.now),
    );
    if (!mounted || order == null) return;
    widget.onOpenOrder(order);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
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
          Text(
            l10n.p2pBookViewMap,
            style: text.bodyLarge?.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(BullSpacing.sm),
          Expanded(child: ClipRect(child: _map(context))),
        ],
      ),
    );
  }

  /// The gestures of the map: a drag or a pinch moves it, a tap opens what it reaches, a long press shows a pin's order.
  ///
  /// Only the drag and the pinch have the map's own slop ([MapChartView.touchSlop]): a tap and a long press keep the device's, and lose to a drag once it passes the map's.
  Map<Type, GestureRecognizerFactory> _gestures(
    MapLayout layout,
    DeviceGestureSettings? settings,
  ) => {
    ScaleGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
          () => ScaleGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..gestureSettings = const DeviceGestureSettings(
              touchSlop: MapChartView.touchSlop,
            )
            ..onStart = (details) {
              _gestureCamera = _camera;
              _gestureFocal = details.localFocalPoint;
              _select(null);
            }
            ..onUpdate = (details) {
              final (camera, focal) = (_gestureCamera, _gestureFocal);
              if (camera == null || focal == null) return;
              final zoom = camera.zoom + math.log(details.scale) / math.ln2;
              _move(
                camera.zoomedTo(
                  zoom.isFinite ? zoom : camera.zoom,
                  anchor: focal,
                  to: details.localFocalPoint,
                  view: layout.size,
                ),
              );
            }
            ..onEnd = (_) {
              _gestureCamera = null;
              _gestureFocal = null;
            },
        ),
    TapGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..gestureSettings = settings
            ..onTapUp = (details) {
              _open(layout, layout.markAt(details.localPosition));
            },
        ),
    LongPressGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..gestureSettings = settings
            ..onLongPressStart = (details) {
              _select(layout.pinAt(details.localPosition));
            }
            ..onLongPressMoveUpdate = (details) {
              _select(layout.pinAt(details.localPosition));
            }
            ..onLongPressEnd = (_) {
              _select(null);
            },
        ),
  };

  Widget _map(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final marks = _currentMarks;
    final buy = marks.pins.where((pin) => pin.order.type == OrderType.buy);
    final summary = marks.pins.isEmpty
        ? l10n.p2pMapNoLocation
        : l10n.p2pMapSummary(
            l10n.p2pChartBuyOrders(buy.length),
            l10n.p2pChartSellOrders(marks.pins.length - buy.length),
          );
    final countStyle =
        text.labelLarge?.copyWith(color: colors.onSurfaceFixed) ??
        TextStyle(color: colors.onSurfaceFixed, fontSize: 12);
    final direction = Directionality.of(context);
    // The count of a group grows with the text up to one and a half times, its disc with it: larger, the groups would cover the map.
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MapChartPainter.maxCountScale);
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    String label(MapMark mark) => switch (mark) {
      MapPin(:final order) => l10n.p2pMapPin(
        order.type == OrderType.sell
            ? l10n.p2pBookRoleSeller
            : l10n.p2pBookRoleBuyer,
        formats.orderAmount(order.amount),
        order.currency.code,
        CoordinatorText.of(
          order.coordinator.longAlias,
          maxCodePoints: CoordinatorText.name,
        ),
      ),
      MapGroup(:final count) => l10n.p2pMapOrdersHere(count),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final layout = MapLayout.of(marks, _camera, size);
        final selected = _selected;
        final shown = selected == null ? null : layout.offsetOf(selected);
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                label: summary,
                child: MouseRegion(
                  onHover: (event) =>
                      _select(layout.pinAt(event.localPosition)),
                  onExit: (_) => _select(null),
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // The zoom buttons, and each pin and group, carry what a screen reader can do.
                    excludeFromSemantics: true,
                    gestures: _gestures(layout, settings),
                    child: CustomPaint(
                      size: size,
                      painter: MapChartPainter(
                        layout: layout,
                        world: _worldPath,
                        colors: MapColors.of(colors),
                        countStyle: countStyle,
                        direction: direction,
                        scaler: scaler,
                        label: label,
                        onTap: (mark) => _open(layout, mark),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (marks.pins.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(BullSpacing.lg),
                        child: Text(
                          l10n.p2pMapNoLocation,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(color: colors.text),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: BullSpacing.xs,
              top: BullSpacing.xs,
              child: _ZoomButtons(
                camera: _camera,
                onZoom: (zoom) => _move(
                  _camera.zoomedTo(
                    zoom,
                    anchor: size.center(Offset.zero),
                    view: size,
                  ),
                ),
              ),
            ),
            if ((selected, shown) case (final pin?, final at?))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomSingleChildLayout(
                    delegate: OrderTooltipPosition(
                      at.translate(0, -MapChartPainter.pinHeadAbove),
                    ),
                    child: OrderTooltip(order: pin.order),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The zoom control of Leaflet, in the top left corner of the map: « + » and « − », each disabled at its end of the zooms.
class _ZoomButtons extends StatelessWidget {
  final MapCamera camera;
  final ValueChanged<double> onZoom;

  const _ZoomButtons({required this.camera, required this.onZoom});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    Widget button(String tooltip, IconData icon, double? zoom) => IconButton(
      tooltip: tooltip,
      onPressed: zoom == null ? null : () => onZoom(zoom),
      icon: Icon(icon),
      color: colors.text,
      disabledColor: colors.outline,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(BullRadius.xs),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(l10n.p2pChartZoomIn, Icons.add, camera.zoomInTo),
          Container(width: 32, height: 1, color: colors.outline),
          button(l10n.p2pChartZoomOut, Icons.remove, camera.zoomOutTo),
        ],
      ),
    );
  }
}

/// The orders of a group that zooming cannot part, as the list shows them; a tap on one closes the sheet with it.
class MapGroupSheet extends StatelessWidget {
  final MapGroup group;
  final DateTime now;

  const MapGroupSheet({super.key, required this.group, required this.now});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(BullSpacing.md),
          Row(
            children: [
              const Gap(48),
              Expanded(
                child: Text(
                  l10n.p2pMapOrdersHere(group.count),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: colors.onSurface),
                ),
              ),
              IconButton(
                iconSize: 20,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                color: colors.onSurface,
                icon: const Icon(Icons.close),
              ),
              const Gap(BullSpacing.md),
            ],
          ),
          const Gap(BullSpacing.sm),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: group.pins.length,
              itemBuilder: (context, index) {
                final order = group.pins[index].order;
                return OfferRow(
                  key: ValueKey((order.coordinator.shortAlias, order.id)),
                  order: order,
                  now: now,
                  onTap: () => Navigator.pop(context, order),
                );
              },
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.outlineVariant),
            ),
          ),
          const Gap(BullSpacing.md),
        ],
      ),
    );
  }
}

/// Where the map looks: its zoom, and the point of the map at the centre of the view.
@immutable
final class MapCamera {
  final double zoom;

  /// The centre of the view, as a `MapPoint`.
  final double x;
  final double y;

  /// The view the official client's map opens on: zoom 1, centred on latitude 0 and longitude 0.
  const MapCamera() : zoom = WebMercator.initialZoom, x = 0.5, y = 0.5;

  /// A camera at [zoom] looking at [x] and [y], kept within the zooms of the map and with its centre on the map, so that the world cannot be dragged out of view.
  MapCamera.at({required double zoom, required double x, required double y})
    : zoom = zoom.isFinite
          ? zoom.clamp(WebMercator.minZoom, WebMercator.maxZoom).toDouble()
          : WebMercator.initialZoom,
      x = x.isFinite ? x.clamp(0, 1).toDouble() : 0.5,
      y = y.isFinite ? y.clamp(0, 1).toDouble() : 0.5;

  /// The width of the whole world in points at this zoom.
  double get worldSize => WebMercator.worldSize(zoom);

  /// Where the point [x], [y] of the map lies in a view of [view].
  Offset toView(double x, double y, Size view) => Offset(
    (x - this.x) * worldSize + view.width / 2,
    (y - this.y) * worldSize + view.height / 2,
  );

  /// The point of the map that lies at [at] in a view of [view].
  MapPoint toMap(Offset at, Size view) => (
    x: x + (at.dx - view.width / 2) / worldSize,
    y: y + (at.dy - view.height / 2) / worldSize,
  );

  /// This camera at [zoom], the point of the map at [anchor] moved to [to], or kept where it is.
  MapCamera zoomedTo(
    double zoom, {
    required Offset anchor,
    Offset? to,
    required Size view,
  }) {
    final point = toMap(anchor, view);
    final target = to ?? anchor;
    final next = MapCamera.at(zoom: zoom, x: point.x, y: point.y);
    return MapCamera.at(
      zoom: next.zoom,
      x: point.x - (target.dx - view.width / 2) / next.worldSize,
      y: point.y - (target.dy - view.height / 2) / next.worldSize,
    );
  }

  /// The zoom « + » goes to: the next whole level, as Leaflet's zoom control; `null` at the nearest zoom.
  double? get zoomInTo => zoom >= WebMercator.maxZoom
      ? null
      : math.min((zoom + _snap).floorToDouble() + 1, WebMercator.maxZoom);

  /// The zoom « − » goes to: the previous whole level; `null` at the farthest zoom.
  double? get zoomOutTo => zoom <= WebMercator.minZoom
      ? null
      : math.max((zoom - _snap).ceilToDouble() - 1, WebMercator.minZoom);

  /// How near a whole level a zoom counts as that level.
  static const _snap = 0.01;

  /// The largest whole zoom at which a box of [width] by [height], in `MapPoint` units, fits in [view], as Leaflet's `getBoundsZoom` with its zoom snapped to whole levels; the nearest zoom for a box of one point.
  static double fitZoom(double width, double height, Size view) {
    final scale = math.min(
      width > 0 ? view.width / (width * WebMercator.tileSize) : double.infinity,
      height > 0
          ? view.height / (height * WebMercator.tileSize)
          : double.infinity,
    );
    if (!(scale < double.infinity)) return WebMercator.maxZoom;
    final exact = math.log(scale) / math.ln2;
    // Leaflet rounds to a hundredth of a level first, so a box that just fits is not one level short.
    return ((exact * 100).round() / 100)
        .floorToDouble()
        .clamp(WebMercator.minZoom, WebMercator.maxZoom)
        .toDouble();
  }

  /// Where a tap on [group], shown at [MapLayout.level], takes the map, as Leaflet.markercluster's `zoomToBounds`: to the level where it parts ([splitLevel]) when its orders fit in the view only nearer, else to its orders' box when that zooms in, else one level nearer, centred on it.
  MapCamera zoomedOnGroup(
    MapGroup group, {
    required int splitLevel,
    required Size view,
  }) {
    final fit = fitZoom(
      group.right - group.left,
      group.bottom - group.top,
      view,
    );
    if (fit > splitLevel) {
      return MapCamera.at(zoom: splitLevel.toDouble(), x: group.x, y: group.y);
    }
    if (fit <= zoom) {
      return MapCamera.at(
        zoom: (zoom + _snap).floorToDouble() + 1,
        x: group.x,
        y: group.y,
      );
    }
    return MapCamera.at(
      zoom: fit,
      x: (group.left + group.right) / 2,
      y: (group.top + group.bottom) / 2,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapCamera && other.zoom == zoom && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(zoom, x, y);

  @override
  String toString() => 'MapCamera($zoom, $x, $y)';
}

/// What a view of the map shows: the marks of the level of its zoom that are in view, each where it is drawn.
@immutable
final class MapLayout {
  /// The marks laid out.
  final MapMarks marks;
  final MapCamera camera;
  final Size size;

  /// The level of [MapMarks] drawn.
  final int level;

  /// The marks drawn, in the order they are drawn, with where each one stands: the tip of a pin, the centre of a group.
  ///
  /// The marks out of view are left out, and of pins at one point of the view only the one drawn last, which hides the others.
  final List<(MapMark, Offset)> drawn;

  const MapLayout._(this.marks, this.camera, this.size, this.level, this.drawn);

  /// How far past the edge of the view a mark is still drawn: a pin or a group standing there reaches into the view.
  static const _margin = 64.0;

  factory MapLayout.of(MapMarks marks, MapCamera camera, Size size) {
    final level = MapMarks.levelOf(camera.zoom);
    final view = (Offset.zero & size).inflate(_margin);
    final inView = <(MapMark, Offset)>[];
    for (final mark in marks.marksAt(level)) {
      final at = camera.toView(mark.x, mark.y, size);
      if (view.contains(at)) inView.add((mark, at));
    }
    if (level <= MapMarks.lastGroupedLevel) {
      return MapLayout._(marks, camera, size, level, List.unmodifiable(inView));
    }
    // Past the levels with groups, thousands of pins can lie at one point: only the last of them, the one seen, is drawn.
    final seen = <(int, int)>{};
    final kept = <(MapMark, Offset)>[];
    for (final entry in inView.reversed) {
      if (seen.add((entry.$2.dx.round(), entry.$2.dy.round()))) {
        kept.add(entry);
      }
    }
    return MapLayout._(
      marks,
      camera,
      size,
      level,
      List.unmodifiable(kept.reversed),
    );
  }

  /// The size of the place a tap reaches around a pin or a group.
  static const touchSize = 48.0;

  /// The place a tap on [mark], drawn at [at], reaches: at least [touchSize] square, around the head of a pin or the disc of a group.
  static Rect touchRectOf(MapMark mark, Offset at) => switch (mark) {
    MapPin() => Rect.fromCenter(
      center: at.translate(0, -MapChartPainter.pinHeight / 2),
      width: math.max(touchSize, MapChartPainter.pinWidth),
      height: math.max(touchSize, MapChartPainter.pinHeight),
    ),
    MapGroup() => Rect.fromCenter(
      center: at,
      width: math.max(touchSize, MapChartPainter.groupDiameter),
      height: math.max(touchSize, MapChartPainter.groupDiameter),
    ),
  };

  /// The place of [mark], drawn at [at], for a screen reader: where a tap reaches it, within the view; `null` when none of it is in the view.
  static Rect? semanticsRectOf(MapMark mark, Offset at, Size view) {
    final rect = touchRectOf(mark, at).intersect(Offset.zero & view);
    return rect.width > 0 && rect.height > 0 ? rect : null;
  }

  /// The mark a tap at [at] reaches: of those drawn there, the one drawn last; `null` when none is.
  MapMark? markAt(Offset at) {
    for (final (mark, place) in drawn.reversed) {
      if (touchRectOf(mark, place).contains(at)) return mark;
    }
    return null;
  }

  /// The pin a long press or a pointer at [at] shows: as [markAt], `null` when it is a group.
  MapPin? pinAt(Offset at) => switch (markAt(at)) {
    final MapPin pin => pin,
    _ => null,
  };

  /// Where [pin] is drawn, or `null` when it is not drawn by itself.
  Offset? offsetOf(MapPin pin) {
    for (final (mark, at) in drawn) {
      if (identical(mark, pin)) return at;
    }
    return null;
  }
}

/// The colours of the map: the land and its outlines, the two kinds of pins, and the three sizes of groups.
@immutable
final class MapColors {
  final Color land;
  final Color border;
  final Color sell;
  final Color buy;
  final Color pinOutline;
  final Color pinEyes;
  final Color small;
  final Color medium;
  final Color large;

  const MapColors._({
    required this.land,
    required this.border,
    required this.sell,
    required this.buy,
    required this.pinOutline,
    required this.pinEyes,
    required this.small,
    required this.medium,
    required this.large,
  });

  /// The colours of the official client in the theme: the countries filled with the disabled text colour at Leaflet's fill opacity of 0.2 and outlined with the secondary text colour, sellers in the primary colour and buyers in the secondary one, a pin outlined in black with white eyes, and groups green, yellow and orange by size.
  factory MapColors.of(BullTheme colors) => MapColors._(
    land: colors.text.withValues(alpha: 0.1),
    border: colors.textMuted,
    sell: colors.primary,
    buy: colors.secondary,
    pinOutline: colors.onSurfaceFixed,
    pinEyes: colors.surfaceFixed,
    small: colors.success,
    medium: colors.tertiary,
    large: colors.warning,
  );

  @override
  bool operator ==(Object other) =>
      other is MapColors &&
      other.land == land &&
      other.border == border &&
      other.sell == sell &&
      other.buy == buy &&
      other.pinOutline == pinOutline &&
      other.pinEyes == pinEyes &&
      other.small == small &&
      other.medium == medium &&
      other.large == large;

  @override
  int get hashCode => Object.hash(
    land,
    border,
    sell,
    buy,
    pinOutline,
    pinEyes,
    small,
    medium,
    large,
  );
}

/// Paints the map as the official client's Leaflet map lays it: the countries, then the pins and groups, a mark further south over one further north.
final class MapChartPainter extends CustomPainter {
  final MapLayout layout;

  /// The outline of the countries at zoom 0 ([outline]), or `null` while the world map is read or when it could not be.
  final Path? world;
  final MapColors colors;
  final TextStyle countStyle;
  final TextDirection direction;
  final TextScaler scaler;

  /// What a screen reader says of a mark, and what activating it does.
  final String Function(MapMark mark) label;
  final ValueChanged<MapMark> onTap;

  const MapChartPainter({
    required this.layout,
    required this.world,
    required this.colors,
    required this.countStyle,
    required this.direction,
    required this.scaler,
    required this.label,
    required this.onTap,
  });

  /// The size of a pin, whose tip is the position of its order: the official client's icon, 24 points wide.
  static const pinWidth = 24.0;
  static const pinHeight = 38.0;

  /// How far above its tip the centre of a pin's head is.
  static const pinHeadAbove = 26.0;

  /// The size of a group's disc, and of the disc inside it, as Leaflet.markercluster's default style.
  static const groupDiameter = 40.0;
  static const groupInnerDiameter = 30.0;

  /// The largest text scale of a group's count.
  static const maxCountScale = 1.5;

  /// The width of the outlines of the countries, Leaflet's `weight: 1` of the official client.
  static const borderWidth = 1.0;

  /// The outline of [world] at zoom 0, in points: one path, every ring filled together.
  static Path outline(WorldMap world) {
    final path = Path();
    for (final ring in world.rings) {
      for (var i = 0; i < ring.length; i += 2) {
        final x = ring[i] * WebMercator.tileSize;
        final y = ring[i + 1] * WebMercator.tileSize;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (world case final world?) {
      final camera = layout.camera;
      final scale = camera.worldSize / WebMercator.tileSize;
      final transform = Float64List(16)
        ..[0] = scale
        ..[5] = scale
        ..[10] = 1
        ..[12] = size.width / 2 - camera.x * camera.worldSize
        ..[13] = size.height / 2 - camera.y * camera.worldSize
        ..[15] = 1;
      final drawn = world.transform(transform);
      canvas
        ..drawPath(drawn, Paint()..color = colors.land)
        ..drawPath(
          drawn,
          Paint()
            ..color = colors.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth
            ..strokeJoin = StrokeJoin.round,
        );
    }
    for (final (mark, at) in layout.drawn) {
      switch (mark) {
        case MapPin(:final order):
          _pin(
            canvas,
            at,
            order.type == OrderType.sell ? colors.sell : colors.buy,
          );
        case MapGroup(:final count):
          _group(canvas, at, count);
      }
    }
  }

  /// A pin of the app's own drawing, tip at [at]: a drop with a robot's visor, two eyes and a smile, as the official client's `MapPin`, none of whose drawing it reuses.
  void _pin(Canvas canvas, Offset at, Color fill) {
    final head = at.translate(0, -pinHeadAbove);
    const radius = 11.0;
    // The tail leaves the head where the lines from the tip touch it.
    final touch = math.acos(radius / pinHeadAbove);
    final body = Path()
      ..moveTo(at.dx, at.dy)
      ..arcTo(
        Rect.fromCircle(center: head, radius: radius),
        math.pi / 2 + touch,
        2 * math.pi - 2 * touch,
        false,
      )
      ..close();
    final outline = Paint()
      ..color = colors.pinOutline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final visor = RRect.fromRectAndRadius(
      Rect.fromCenter(center: head.translate(0, 0.5), width: 16, height: 10),
      const Radius.circular(5),
    );
    final eyes = Paint()..color = colors.pinEyes;
    canvas
      ..drawPath(body, Paint()..color = fill)
      ..drawPath(body, outline)
      ..drawRRect(visor, Paint()..color = colors.pinOutline);
    for (final side in const [-4.0, 4.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: head.translate(side, -0.5),
            width: 2.8,
            height: 3,
          ),
          const Radius.circular(1.3),
        ),
        eyes,
      );
    }
    canvas.drawArc(
      Rect.fromCenter(center: head.translate(0, 1.6), width: 5, height: 3),
      0.2,
      math.pi - 0.4,
      false,
      Paint()
        ..color = colors.pinEyes
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  /// A group: two discs in the colour of its size, as Leaflet.markercluster's default style (fewer than 10, fewer than 100, more), and its count.
  void _group(Canvas canvas, Offset at, int count) {
    final color = count < 10
        ? colors.small
        : count < 100
        ? colors.medium
        : colors.large;
    final painter = TextPainter(
      text: TextSpan(text: '$count', style: countStyle),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final inner = math.max(
      groupInnerDiameter,
      math.max(painter.width, painter.height) + 8,
    );
    canvas
      ..drawCircle(
        at,
        inner / 2 + (groupDiameter - groupInnerDiameter) / 2,
        Paint()..color = color.withValues(alpha: 0.35),
      )
      ..drawCircle(
        at,
        inner / 2,
        Paint()..color = color.withValues(alpha: 0.75),
      );
    painter
      ..paint(canvas, at - Offset(painter.width / 2, painter.height / 2))
      ..dispose();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final (mark, at) in layout.drawn)
          if (MapLayout.semanticsRectOf(mark, at, size) case final rect?)
            CustomPainterSemantics(
              rect: rect,
              properties: SemanticsProperties(
                label: label(mark),
                textDirection: direction,
                button: true,
                onTap: () => onTap(mark),
              ),
            ),
      ];

  @override
  bool shouldRepaint(MapChartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.world != world ||
      oldDelegate.colors != colors ||
      oldDelegate.countStyle != countStyle ||
      oldDelegate.direction != direction ||
      oldDelegate.scaler != scaler;

  @override
  bool shouldRebuildSemantics(MapChartPainter oldDelegate) =>
      shouldRepaint(oldDelegate) || oldDelegate.label != label;
}
