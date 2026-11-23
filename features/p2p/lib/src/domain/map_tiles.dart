import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'web_mercator.dart';

/// One tile of OpenStreetMap's map, numbered as Leaflet numbers it: its whole zoom [z], from 0 to [maxZoom], and its column [x] and row [y], each from 0 to 2^[z] − 1 (#246).
///
/// It never says which tile it is in a text (`toString`), so that a log line that would name one shows nothing of the area looked at.
@immutable
final class MapTile {
  final int z;
  final int x;
  final int y;

  const MapTile._(this.z, this.x, this.y);

  /// The nearest zoom the reference's map lets a user see (`maxZoom={15}`, `components/Map/index.tsx`), so the nearest whole zoom of a tile asked.
  static const maxZoom = 15;

  /// The tile [z], [x], [y], or `null` when [z] is not a whole zoom from 0 to [maxZoom] or [x] or [y] is not within it.
  static MapTile? of(int z, int x, int y) {
    if (z < 0 || z > maxZoom) return null;
    final count = 1 << z;
    if (x < 0 || x >= count || y < 0 || y >= count) return null;
    return MapTile._(z, x, y);
  }

  /// The whole zoom of the tiles a map at [zoom] shows: [zoom] rounded, as Leaflet's tile layer rounds it (`_clampZoom(Math.round(zoom))`), within 0 and [maxZoom].
  static int zoomOf(double zoom) => zoom.isFinite
      ? zoom.round().clamp(0, maxZoom)
      : WebMercator.initialZoom.round();

  /// The tiles that a view of [width] by [height] points shows, centred on the point [x], [y] of the map (`MapPoint`) at [zoom]: those of [zoomOf] whose square meets the view, as Leaflet's tile layer asks them (`_getTiledPixelBounds`, `_pxBoundsToTileRange`), with no tile beside the view asked ahead; the nearest the centre first, as Leaflet sorts its queue.
  ///
  /// The map shows one world, so no tile beyond its edges; a view that is not a finite size shows none.
  static List<MapTile> covering({
    required double zoom,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    if (!x.isFinite || !y.isFinite || !(width > 0) || !(height > 0)) {
      return const [];
    }
    if (!width.isFinite || !height.isFinite) return const [];
    final z = zoomOf(zoom);
    final count = 1 << z;
    final worldSize = WebMercator.worldSize(zoom.isFinite ? zoom : z * 1.0);
    final halfWidth = width / 2 / worldSize;
    final halfHeight = height / 2 / worldSize;
    int first(double edge) => (edge * count).floor().clamp(0, count - 1);
    int last(double edge) => ((edge * count).ceil() - 1).clamp(0, count - 1);
    final (left, right) = (x - halfWidth, x + halfWidth);
    final (top, bottom) = (y - halfHeight, y + halfHeight);
    if (right <= 0 || left >= 1 || bottom <= 0 || top >= 1) return const [];
    final tiles = <MapTile>[
      for (var row = first(top); row <= last(bottom); row++)
        for (var column = first(left); column <= last(right); column++)
          MapTile._(z, column, row),
    ];
    double distance(MapTile tile) {
      final dx = (tile.x + 0.5) / count - x;
      final dy = (tile.y + 0.5) / count - y;
      return math.sqrt(dx * dx + dy * dy);
    }

    return tiles..sort((a, b) => distance(a).compareTo(distance(b)));
  }

  @override
  bool operator ==(Object other) =>
      other is MapTile && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => 'MapTile';
}

/// What a request of one tile gave.
sealed class MapTileOutcome {
  const MapTileOutcome();
}

/// The tile's picture: a PNG of 256 × 256 pixels, checked before any decoding.
final class MapTileImage extends MapTileOutcome {
  final Uint8List png;

  const MapTileImage(this.png);
}

/// The provider refused the tile: an answer with its `x-blocked` header, which comes with an error picture and HTTP 200 (the « Blocked tiles » page of OpenStreetMap's wiki), or « Too Many Requests » (429): nothing more is asked until the switch is turned off and on again.
final class MapTileRefused extends MapTileOutcome {
  const MapTileRefused();
}

/// No tile: no connection, a timeout, an answer that is not a tile.
final class MapTileFailed extends MapTileOutcome {
  const MapTileFailed();
}

/// The tile was no longer wanted, or its map closed, before it came: nothing to show.
final class MapTileDropped extends MapTileOutcome {
  const MapTileDropped();
}

/// The tiles of one map while « Show tiles » is on (#246): opened once the user turned the switch on and pressed « Acknowledged », closed when the switch goes off or the map closes.
abstract interface class MapTileSession {
  /// The tile [tile], from the session's memory or else asked of the provider; a tile already asked is not asked twice. It never throws.
  Future<MapTileOutcome> fetch(MapTile tile);

  /// [tile] left the view: its request is given up, waiting or running, and its [fetch] gives [MapTileDropped]; nothing for a tile not asked.
  void drop(MapTile tile);

  /// Closes the session: every request given up, the client closed, the tiles kept forgotten. A [fetch] after it gives [MapTileDropped] and asks nothing.
  void close();
}

/// Where the tiles of the maps come from: OpenStreetMap's, outside Tor, decided by the owner on 2026-11-23 (#246, design note `docs/design/phase-3-map-tiles.md`).
///
/// Opening a session sends nothing; its first [MapTileSession.fetch] is the first request.
abstract interface class MapTilePort {
  MapTileSession open();
}
