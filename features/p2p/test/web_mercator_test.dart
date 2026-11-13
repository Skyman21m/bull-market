import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/web_mercator.dart';

void main() {
  // The expected values are those of Leaflet's `L.CRS.EPSG3857`, computed with its formula: x = longitude / 360 + 0.5, y = 0.5 - ln((1 + sin φ) / (1 - sin φ)) / 4π.
  test('known points', () {
    expect(WebMercator.project(0, 0), (x: 0.5, y: 0.5));
    // Paris: Leaflet's `map.project([48.8566, 2.3522], 0)` is (129.6727, 88.0713) in the 256-point world of zoom 0.
    final paris = WebMercator.project(48.8566, 2.3522);
    expect(paris?.x, closeTo(0.5065338888888888, 1e-12));
    expect(paris?.y, closeTo(0.3440284030675782, 1e-12));
    expect((paris?.x ?? 0) * 256, closeTo(129.6727, 1e-4));
    expect((paris?.y ?? 0) * 256, closeTo(88.0713, 1e-4));
    // Sydney, south and east.
    final sydney = WebMercator.project(-33.8688, 151.2093);
    expect(sydney?.x, closeTo(0.9200258333333333, 1e-12));
    expect(sydney?.y, closeTo(0.6000922514587762, 1e-12));
    // The edge between the first and the second row of tiles at zoom 2 lies at 66.51326044311186°.
    expect(WebMercator.yOf(66.51326044311186), closeTo(0.25, 1e-12));
    expect(WebMercator.yOf(-66.51326044311186), closeTo(0.75, 1e-12));
  });

  test('the poles are clamped to the edges, as Leaflet clamps them', () {
    expect(WebMercator.yOf(WebMercator.maxLatitude), closeTo(0, 1e-9));
    expect(WebMercator.yOf(90), WebMercator.yOf(WebMercator.maxLatitude));
    expect(WebMercator.yOf(89), WebMercator.yOf(WebMercator.maxLatitude));
    expect(WebMercator.yOf(-90), closeTo(1, 1e-9));
    expect(WebMercator.yOf(-90), WebMercator.yOf(-WebMercator.maxLatitude));
    expect(WebMercator.project(90, 0)?.y, closeTo(0, 1e-9));
    expect(WebMercator.project(-90, 0)?.y, closeTo(1, 1e-9));
  });

  test('the antimeridian is the left and right edge, not wrapped', () {
    expect(WebMercator.project(0, 180), (x: 1.0, y: 0.5));
    expect(WebMercator.project(0, -180), (x: 0.0, y: 0.5));
    expect(WebMercator.project(10, 179.99)?.x, closeTo(1, 1e-4));
    expect(WebMercator.project(10, -179.99)?.x, closeTo(0, 1e-4));
  });

  test('a position out of its bounds, or not a number, has no place', () {
    for (final (latitude, longitude) in [
      (double.nan, 0.0),
      (0.0, double.nan),
      (double.infinity, 0.0),
      (0.0, double.negativeInfinity),
      (90.000001, 0.0),
      (-90.000001, 0.0),
      (0.0, 180.000001),
      (0.0, -180.000001),
      (1e308, 1e308),
    ]) {
      expect(
        WebMercator.project(latitude, longitude),
        isNull,
        reason: '$latitude, $longitude',
      );
    }
  });

  test('the zooms of the official client, and the size of the world', () {
    expect(WebMercator.initialZoom, 1);
    expect(WebMercator.minZoom, 0);
    expect(WebMercator.maxZoom, 15);
    expect(WebMercator.worldSize(0), 256);
    expect(WebMercator.worldSize(1), 512);
    expect(WebMercator.worldSize(15), 256 * 32768);
    expect(WebMercator.worldSize(1.5), closeTo(724.077, 1e-3));
  });
}
