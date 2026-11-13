import 'dart:math' as math;

/// A point of the map as a fraction of its square: [x] from 0 at 180° W to 1 at 180° E, [y] from 0 at the top edge to 1 at the bottom one.
typedef MapPoint = ({double x, double y});

/// Web Mercator as Leaflet projects it (`L.CRS.EPSG3857`, the projection of the official client's map, `components/Map/index.tsx`).
///
/// Latitudes beyond ±[maxLatitude] are clamped to it, as Leaflet's `SphericalMercator.project` does, so that the poles lie on the top and bottom edges.
/// Longitudes are not wrapped: the map shows one world, from 180° W to 180° E, as the official client's GeoJSON layer does.
abstract final class WebMercator {
  /// The latitude where the square map ends (`L.Projection.SphericalMercator.MAX_LATITUDE`).
  static const maxLatitude = 85.0511287798;

  /// The width in points of the whole world at zoom 0: each zoom level doubles it, as Leaflet's 256-pixel tiles.
  static const tileSize = 256.0;

  /// The zoom the official client's map opens at (`zoom={zoom ?? 1}`), the farthest out it lets a user go (Leaflet's `minZoom`, 0 when nothing sets it) and the nearest in (`maxZoom={15}`).
  static const initialZoom = 1.0;
  static const minZoom = 0.0;
  static const maxZoom = 15.0;

  /// [latitude] and [longitude] on the map, or `null` when either is not a number within ±90° and ±180°.
  ///
  /// The package already refuses such a position, so this only keeps a hostile value away from the drawing.
  static MapPoint? project(double latitude, double longitude) {
    if (!(latitude.abs() <= 90) || !(longitude.abs() <= 180)) return null;
    return (x: xOf(longitude), y: yOf(latitude));
  }

  /// The [MapPoint.x] of [longitude], within ±180°.
  static double xOf(double longitude) => longitude / 360 + 0.5;

  /// The [MapPoint.y] of [latitude], clamped to ±[maxLatitude] first.
  static double yOf(double latitude) {
    final sin = math.sin(
      latitude.clamp(-maxLatitude, maxLatitude) * math.pi / 180,
    );
    return 0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
  }

  /// The width in points of the whole world at [zoom].
  static double worldSize(double zoom) => tileSize * math.pow(2, zoom);
}
