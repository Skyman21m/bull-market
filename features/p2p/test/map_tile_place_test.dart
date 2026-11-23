import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/map_tiles.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/ui/map_chart_view.dart';
import 'package:p2p/src/ui/map_tile_layer.dart';

/// Where a tile is drawn (#246): checked against OpenStreetMap's own numbering of tiles (the « Slippy map tilenames » formula of its wiki), written here apart from the code, so that a place lies on the tile the provider would send for it, at its place on that tile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// OpenStreetMap's tile of [latitude] and [longitude] at zoom [z], and where the place lies on it, in pixels.
  ({int x, int y, double left, double top}) osm(
    double latitude,
    double longitude,
    int z,
  ) {
    final count = math.pow(2, z).toDouble();
    final column = (longitude + 180) / 360 * count;
    final radians = latitude * math.pi / 180;
    final row =
        (1 - math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
        2 *
        count;
    return (
      x: column.floor(),
      y: row.floor(),
      left: (column - column.floor()) * 256,
      top: (row - row.floor()) * 256,
    );
  }

  const view = Size(360, 640);
  final centre = view.center(Offset.zero);

  for (final (name, latitude, longitude, z) in const [
    ('Paris at zoom 15', 48.8566, 2.3522, 15),
    ('Paris at zoom 14', 48.8566, 2.3522, 14),
    ('Longyearbyen, far north, at zoom 12', 78.2232, 15.6267, 12),
    ('Longyearbyen, far north, at zoom 15', 78.2232, 15.6267, 15),
    ('Sydney at zoom 9', -33.8688, 151.2093, 9),
    ('the north-east edge at zoom 3', 85.05, 179.99, 3),
    ('the south-west edge at zoom 3', -85.05, -179.99, 3),
    ('the whole world at zoom 0', 10.0, -20.0, 0),
  ]) {
    test(
      '$name: the place lies on the tile OpenStreetMap numbers for it, at its place on that tile',
      () {
        final expected = osm(latitude, longitude, z);
        final tile = MapTile.of(z, expected.x, expected.y);
        if (tile == null) fail('no tile ${expected.x} ${expected.y}');
        final camera = MapCamera.at(
          zoom: z.toDouble(),
          x: WebMercator.xOf(longitude),
          y: WebMercator.yOf(latitude),
        );
        // The camera looks at the place: it lies at the centre of the view.
        final square = MapChartPainter.tileRect(tile, camera, view);
        expect(square.width, closeTo(256, 1));
        expect(square.height, closeTo(256, 1));
        final onTile = square.topLeft + Offset(expected.left, expected.top);
        expect((onTile - centre).dx.abs(), lessThan(0.51));
        expect((onTile - centre).dy.abs(), lessThan(0.51));
        // And the map asks that tile.
        expect(
          MapTile.covering(
            zoom: z.toDouble(),
            x: camera.x,
            y: camera.y,
            width: view.width,
            height: view.height,
          ),
          contains(tile),
        );
      },
    );
  }

  test('a tile\'s picture is drawn exactly in its square, the whole picture', () async {
    final image = await createTestImage(width: 256, height: 256);
    final tile = MapTile.of(15, 16598, 11273);
    if (tile == null) fail('no tile');
    final camera = MapCamera.at(
      zoom: 15,
      x: WebMercator.xOf(2.3522),
      y: WebMercator.yOf(48.8566),
    );
    final canvas = _RecordingCanvas();
    MapChartPainter.paintGround(
      canvas,
      view,
      camera,
      null,
      MapTileFrame([tile], {tile: image}),
      MapColors.of(testBullTheme),
    );
    expect(canvas.drawn, [
      (const Rect.fromLTWH(0, 0, 256, 256), MapChartPainter.tileRect(tile, camera, view)),
    ]);
    image.dispose();
  });
}

/// A canvas that records where each picture is drawn.
final class _RecordingCanvas implements Canvas {
  final drawn = <(Rect, Rect)>[];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      drawn.add((src, dst));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
