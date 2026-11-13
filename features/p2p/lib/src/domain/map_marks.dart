import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import 'web_mercator.dart';

/// What the « Map » view draws at one zoom level: the pin of one order, or a group of orders whose pins would overlap.
@immutable
sealed class MapMark {
  const MapMark();

  /// Where it is drawn, as a [MapPoint].
  double get x;
  double get y;

  /// How many orders it stands for.
  int get count;
}

/// An order with a position, where the map draws its pin.
final class MapPin extends MapMark {
  final PublicOrder order;

  @override
  final double x;

  @override
  final double y;

  /// Its place in [MapMarks.pins].
  final int index;

  const MapPin._(this.order, this.x, this.y, this.index);

  @override
  int get count => 1;
}

/// Orders whose pins would overlap at a level, drawn as one disc with their count, as the official client's `MarkerClusterGroup` draws a cluster.
final class MapGroup extends MapMark {
  /// Its orders, in the order of [MapMarks.pins].
  final List<MapPin> pins;

  /// Where the disc is drawn: the mean position of its orders.
  @override
  final double x;

  @override
  final double y;

  /// The box its orders lie in.
  final double left;
  final double top;
  final double right;
  final double bottom;

  const MapGroup._(
    this.pins,
    this.x,
    this.y,
    this.left,
    this.top,
    this.right,
    this.bottom,
  );

  factory MapGroup._of(List<MapMark> marks) {
    final pins = [
      for (final mark in marks)
        ...switch (mark) {
          final MapPin pin => [pin],
          final MapGroup group => group.pins,
        },
    ]..sort((a, b) => a.index.compareTo(b.index));
    var (sumX, sumY) = (0.0, 0.0);
    var (left, top) = (double.infinity, double.infinity);
    var (right, bottom) = (double.negativeInfinity, double.negativeInfinity);
    for (final pin in pins) {
      sumX += pin.x;
      sumY += pin.y;
      if (pin.x < left) left = pin.x;
      if (pin.x > right) right = pin.x;
      if (pin.y < top) top = pin.y;
      if (pin.y > bottom) bottom = pin.y;
    }
    return MapGroup._(
      List.unmodifiable(pins),
      sumX / pins.length,
      sumY / pins.length,
      left,
      top,
      right,
      bottom,
    );
  }

  @override
  int get count => pins.length;
}

/// The marks of every zoom level for the orders of the book that have a position, built once for a book.
///
/// The orders are grouped as the official client's `MarkerClusterGroup` groups them (`components/Map/index.tsx`, Leaflet.markercluster): marks closer than [radius] points at a level become one group, from level 0 to [lastGroupedLevel], and from zoom 14 every order has its own pin.
/// The groups are built level by level from the deepest one, each level grouping the marks of the level below it, so that a group of one level is whole at every level above it, as Leaflet.markercluster's tree is; a mark takes every mark within [radius] of it that no earlier mark took, in the order of the orders given, where Leaflet.markercluster adds each marker to the nearest group in reach, so a pin between two groups can end in the other one.
/// Building them costs about one pass over the orders per level, with a grid of [radius]; nothing is grouped again while the map moves.
final class MapMarks {
  /// How close two marks are grouped, in points at their level: Leaflet.markercluster's `maxClusterRadius`.
  static const radius = 80.0;

  /// The deepest level with groups: the official client sets `disableClusteringAtZoom={14}`.
  static const lastGroupedLevel = 13;

  /// Every order with a position, in the order given.
  final List<MapPin> pins;

  /// The marks of each level from 0 to [lastGroupedLevel], from north to south.
  final List<List<MapMark>> _levels;

  /// [pins] from north to south, the marks of every level past [lastGroupedLevel].
  final List<MapPin> _pinsFromNorth;

  /// For each level from 0 to [lastGroupedLevel], the place in [_levels] of the mark each pin is in, by [MapPin.index].
  final List<Int32List> _markOf;

  const MapMarks._(this.pins, this._levels, this._pinsFromNorth, this._markOf);

  /// The marks of [orders]: those without a position, or with one `WebMercator` refuses, are left out.
  factory MapMarks.of(Iterable<PublicOrder> orders) {
    final pins = <MapPin>[];
    for (final order in orders) {
      final location = order.location;
      if (location == null) continue;
      final point = WebMercator.project(location.latitude, location.longitude);
      if (point == null) continue;
      pins.add(MapPin._(order, point.x, point.y, pins.length));
    }
    final levels = List<List<MapMark>>.filled(lastGroupedLevel + 1, const []);
    final markOf = List<Int32List>.filled(lastGroupedLevel + 1, Int32List(0));
    List<MapMark> below = pins;
    for (var level = lastGroupedLevel; level >= 0; level--) {
      below = _group(below, radius / WebMercator.worldSize(level.toDouble()));
      final drawn = _fromNorth(below);
      final places = Int32List(pins.length);
      for (final (place, mark) in drawn.indexed) {
        switch (mark) {
          case MapPin(:final index):
            places[index] = place;
          case MapGroup(pins: final grouped):
            for (final pin in grouped) {
              places[pin.index] = place;
            }
        }
      }
      levels[level] = List.unmodifiable(drawn);
      markOf[level] = places;
    }
    return MapMarks._(
      List.unmodifiable(pins),
      List.unmodifiable(levels),
      List.unmodifiable(_fromNorth(pins)),
      List.unmodifiable(markOf),
    );
  }

  /// The level whose marks a map at [zoom] draws: the nearest whole one.
  static int levelOf(double zoom) =>
      zoom.round().clamp(WebMercator.minZoom, WebMercator.maxZoom).toInt();

  /// The marks a map at [level] draws, in the order they are drawn: from north to south, so that a mark further south covers one further north, as Leaflet stacks its markers.
  List<MapMark> marksAt(int level) => level > lastGroupedLevel
      ? _pinsFromNorth
      : _levels[level.clamp(0, lastGroupedLevel)];

  /// The first level past [level] where no order of [group] is in a group any more: as far as zooming in on it is useful.
  int splitLevel(MapGroup group, int level) {
    for (var deeper = level + 1; deeper <= lastGroupedLevel; deeper++) {
      final marks = _levels[deeper];
      final places = _markOf[deeper];
      if (!group.pins.any((pin) => marks[places[pin.index]] is MapGroup)) {
        return deeper;
      }
    }
    return lastGroupedLevel + 1;
  }

  /// Whether every order of [group] is still in one group at [lastGroupedLevel], where zooming in cannot part them: the official client then spreads its pins out (`spiderfyOnMaxZoom`), and this view lists its orders.
  bool staysTogether(MapGroup group) {
    final place = _markOf[lastGroupedLevel][group.pins.first.index];
    final deepest = _levels[lastGroupedLevel][place];
    return deepest is MapGroup && deepest.count == group.count;
  }

  /// Groups [marks] within [reach] of each other, in their order: each mark not yet taken takes every mark within [reach] of it not yet taken.
  static List<MapMark> _group(List<MapMark> marks, double reach) {
    final cells = <int, List<int>>{};
    int cell(double value) => (value / reach).floor();
    // The coordinates lie within 0 and 1, so a cell index is below 2^20 at every level.
    int key(int column, int row) => column * 0x100000 + row;
    for (final (index, mark) in marks.indexed) {
      (cells[key(cell(mark.x), cell(mark.y))] ??= []).add(index);
    }
    final taken = List.filled(marks.length, false);
    final grouped = <MapMark>[];
    final reachSquared = reach * reach;
    for (final (index, mark) in marks.indexed) {
      if (taken[index]) continue;
      taken[index] = true;
      final column = cell(mark.x);
      final row = cell(mark.y);
      final near = <MapMark>[];
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final other
              in cells[key(column + dx, row + dy)] ?? const <int>[]) {
            if (taken[other]) continue;
            final ox = marks[other].x - mark.x;
            final oy = marks[other].y - mark.y;
            if (ox * ox + oy * oy <= reachSquared) {
              taken[other] = true;
              near.add(marks[other]);
            }
          }
        }
      }
      grouped.add(near.isEmpty ? mark : MapGroup._of([mark, ...near]));
    }
    return grouped;
  }

  /// [marks] sorted from north to south, those on one line keeping their order.
  static List<T> _fromNorth<T extends MapMark>(List<T> marks) {
    final sorted = marks.indexed.toList()
      ..sort((a, b) {
        final byY = a.$2.y.compareTo(b.$2.y);
        return byY != 0 ? byY : a.$1.compareTo(b.$1);
      });
    return [for (final (_, mark) in sorted) mark];
  }
}
