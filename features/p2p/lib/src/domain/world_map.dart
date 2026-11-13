import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'web_mercator.dart';

/// Where the world map of the « Map » view comes from: Natural Earth's 1:110m « Admin 0 – Countries », public domain, reduced by `tools/troc_world_map.py`.
///
/// The script refuses any source but the file of [sourceUrl], [sourceBytes] long with the SHA-256 [sourceSha256], and writes the asset [asset], whose SHA-256 is [assetSha256].
/// `test/world_map_test.dart` pins these values and the asset's bytes, and runs the script's `--check` when the source is at hand.
abstract final class WorldMapSource {
  /// The asset, in the feature's package.
  static const asset = 'assets/map/world_110m.bin';
  static const package = 'p2p';

  static const assetSha256 =
      'c373c8159a2a103a80283fc1177ade0dcd28046acea079751973db564a422307';

  static const sourceUrl =
      'https://github.com/nvkelso/natural-earth-vector/blob/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_110m_admin_0_countries.geojson';
  static const sourceCommit = 'ca96624a56bd078437bca8184e78163e5039ad19';
  static const sourceBytes = 838726;
  static const sourceSha256 =
      '6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f';
}

/// The outline of every country, projected, as the « Map » view draws it under the orders.
///
/// Read only from the asset `tools/troc_world_map.py` writes: [parse] takes nothing else.
@immutable
final class WorldMap {
  /// Each ring, a closed outline turned counter-clockwise on the globe, as consecutive x and y of `WebMercator`, from 0 to 1.
  final List<Float64List> rings;

  const WorldMap._(this.rings);

  /// The first bytes of the asset.
  static const magic = 'TROCMAP1';

  /// The largest asset read: the one bundled is about 42 KB.
  static const maxBytes = 1 << 20;

  /// The bounds of a coordinate, in hundredths of a degree.
  static const _maxLongitude = 18000;
  static const _maxLatitude = 9000;

  /// The map in [bytes], or `null` when they are anything but what the script writes: another start, a count or a coordinate out of its bounds, a ring of fewer than 3 points, fewer bytes or more than the counts say, or more than [maxBytes].
  ///
  /// It fails closed: the view then draws the orders on an empty map, never part of a map.
  static WorldMap? parse(Uint8List bytes) {
    if (bytes.length > maxBytes || bytes.length < magic.length + 2) return null;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) return null;
    }
    final data = ByteData.sublistView(bytes);
    final ringCount = data.getUint16(magic.length, Endian.little);
    final countsStart = magic.length + 2;
    final pointsStart = countsStart + 2 * ringCount;
    if (ringCount == 0 || pointsStart > bytes.length) return null;
    var points = 0;
    for (var ring = 0; ring < ringCount; ring++) {
      final count = data.getUint16(countsStart + 2 * ring, Endian.little);
      if (count < 3) return null;
      points += count;
    }
    if (bytes.length != pointsStart + 4 * points) return null;
    final rings = <Float64List>[];
    var at = pointsStart;
    for (var ring = 0; ring < ringCount; ring++) {
      final count = data.getUint16(countsStart + 2 * ring, Endian.little);
      final outline = Float64List(2 * count);
      for (var point = 0; point < count; point++) {
        final longitude = data.getInt16(at, Endian.little);
        final latitude = data.getInt16(at + 2, Endian.little);
        at += 4;
        if (longitude.abs() > _maxLongitude || latitude.abs() > _maxLatitude) {
          return null;
        }
        outline[2 * point] = WebMercator.xOf(longitude / 100);
        outline[2 * point + 1] = WebMercator.yOf(latitude / 100);
      }
      rings.add(outline);
    }
    return WorldMap._(List.unmodifiable(rings));
  }

  /// How many points the rings hold together.
  int get pointCount =>
      rings.fold(0, (total, ring) => total + ring.length ~/ 2);
}
