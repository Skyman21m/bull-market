import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/domain/world_map.dart';

/// An asset as `tools/troc_world_map.py` writes it: [rings] of (longitude, latitude) in hundredths of a degree, under the given [magic] and [ringCount] when a test wants them wrong.
Uint8List asset(
  List<List<(int, int)>> rings, {
  String magic = 'TROCMAP1',
  int? ringCount,
  List<int>? counts,
}) {
  final out = BytesBuilder()..add(magic.codeUnits);
  final header = ByteData(2)
    ..setUint16(0, ringCount ?? rings.length, Endian.little);
  out.add(header.buffer.asUint8List());
  for (final (index, ring) in rings.indexed) {
    final count = ByteData(2)
      ..setUint16(0, counts?[index] ?? ring.length, Endian.little);
    out.add(count.buffer.asUint8List());
  }
  for (final ring in rings) {
    for (final (longitude, latitude) in ring) {
      final point = ByteData(4)
        ..setInt16(0, longitude, Endian.little)
        ..setInt16(2, latitude, Endian.little);
      out.add(point.buffer.asUint8List());
    }
  }
  return out.toBytes();
}

/// A triangle around the point where the equator meets the prime meridian, and one at the corners of the map.
const triangle = [(0, 0), (1000, 0), (0, 1000)];
const corners = [(-18000, -9000), (18000, -9000), (18000, 9000)];

void main() {
  group('the bundled asset', () {
    final file = File('assets/map/world_110m.bin');

    test('is the file the script wrote from the pinned source', () {
      // `python3 tools/troc_world_map.py <ne_110m_admin_0_countries.geojson>` wrote it; `--check` below says it still would.
      expect(WorldMapSource.asset, 'assets/map/world_110m.bin');
      expect(WorldMapSource.package, 'p2p');
      expect(file.lengthSync(), 41764);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        'c373c8159a2a103a80283fc1177ade0dcd28046acea079751973db564a422307',
      );
      expect(
        WorldMapSource.assetSha256,
        'c373c8159a2a103a80283fc1177ade0dcd28046acea079751973db564a422307',
      );
    });

    test('its source is Natural Earth at a pinned commit', () {
      // The source, public domain, is not committed: the script refuses any other file.
      expect(
        WorldMapSource.sourceUrl,
        'https://github.com/nvkelso/natural-earth-vector/blob/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_110m_admin_0_countries.geojson',
      );
      expect(
        WorldMapSource.sourceCommit,
        'ca96624a56bd078437bca8184e78163e5039ad19',
      );
      expect(WorldMapSource.sourceBytes, 838726);
      expect(
        WorldMapSource.sourceSha256,
        '6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f',
      );
      final script = File('../../tools/troc_world_map.py').readAsStringSync();
      for (final value in [
        WorldMapSource.sourceUrl,
        WorldMapSource.sourceCommit,
        '${WorldMapSource.sourceBytes}',
        WorldMapSource.sourceSha256,
        WorldMapSource.asset,
      ]) {
        expect(script, contains(value.split('/').last));
      }
    });

    test('reads as 287 outlines on the map', () {
      final world = WorldMap.parse(file.readAsBytesSync());
      expect(world, isNotNull);
      expect(world?.rings, hasLength(287));
      expect(world?.pointCount, 10295);
      for (final ring in world?.rings ?? const <Float64List>[]) {
        expect(ring.length, greaterThanOrEqualTo(6));
        for (final value in ring) {
          expect(value, inInclusiveRange(-1e-9, 1 + 1e-9));
        }
      }
    });

    test('the folder holds the map and nothing else', () {
      expect(
        {for (final entry in Directory('assets/map').listSync()) entry.path},
        {'assets/map/world_110m.bin'},
      );
    });

    // The source is not in the repository: point TROC_NATURAL_EARTH at `ne_110m_admin_0_countries.geojson` to run it.
    final source = Platform.environment['TROC_NATURAL_EARTH'];
    test(
      'the script, given the source, writes the same bytes',
      skip: source == null ? 'TROC_NATURAL_EARTH names no source' : null,
      () async {
        final result = await Process.run('python3', [
          '-I',
          '../../tools/troc_world_map.py',
          '--check',
          source ?? '',
          '../..',
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect('${result.stdout}', startsWith('up to date: 287 rings'));
      },
    );
  });

  group('the script', () {
    // It needs python3 only, no source: each of these is refused before anything is read or written.
    final python = _hasPython();
    for (final (name, arguments, message) in [
      (
        'a path that does not exist',
        ['/nonexistent/source.geojson'],
        'cannot read the source',
      ),
      ('a folder', ['.'], 'not the pinned source'),
      ('a file of another size', ['pubspec.yaml'], 'not the pinned source'),
      ('an argument too many', ['a', 'b', 'c'], 'usage:'),
      ('an unknown option', ['--write', 'a'], 'usage:'),
      ('no source', <String>[], 'usage:'),
    ]) {
      test('refuses $name', skip: python ? null : 'no python3', () {
        final result = Process.runSync('python3', [
          '-I',
          '../../tools/troc_world_map.py',
          '--check',
          ...arguments,
        ]);
        expect(result.exitCode, 1, reason: name);
        expect('${result.stderr}', contains(message), reason: name);
        expect('${result.stderr}', isNot(contains('Traceback')));
      });
    }
  });

  group('the reader', () {
    test('reads the rings, projected', () {
      final world = WorldMap.parse(asset([triangle, corners]));
      expect(world?.rings, hasLength(2));
      expect(world?.pointCount, 6);
      final first = world?.rings.first ?? Float64List(0);
      expect(first, hasLength(6));
      expect(first[0], 0.5);
      expect(first[1], 0.5);
      expect(first[2], closeTo(10 / 360 + 0.5, 1e-12));
      expect(first[3], 0.5);
      expect(first[4], 0.5);
      expect(first[5], closeTo(WebMercator.yOf(10), 1e-12));
      // The corners: the poles clamped to the edges of the map.
      final last = world?.rings.last ?? Float64List(0);
      expect(last[0], 0);
      expect(last[1], closeTo(1, 1e-9));
      expect(last[2], 1);
      expect(last[5], closeTo(0, 1e-9));
    });

    test('fails closed on anything but what the script writes', () {
      final good = asset([triangle, corners]);
      expect(WorldMap.parse(good), isNotNull);
      final cases = <String, Uint8List>{
        'nothing': Uint8List(0),
        'the start only': Uint8List.fromList('TROCMAP1'.codeUnits),
        'another start': asset([triangle], magic: 'TROCMAP2'),
        'another start, same length': asset([triangle], magic: 'trocmap1'),
        'no ring': asset([]),
        'a count of rings beyond the counts': asset([triangle], ringCount: 2),
        'a count of rings beyond the bytes': asset([
          triangle,
        ], ringCount: 60000),
        'a ring of two points': asset([
          [(0, 0), (10, 10)],
        ]),
        'a ring of no point': asset([triangle], counts: [0]).sublist(0, 12),
        'a count of points beyond the bytes': asset([triangle], counts: [4]),
        'a count of points short of the bytes': asset(
          [
            [...triangle, (5, 5)],
          ],
          counts: [3],
        ),
        'one byte missing': good.sublist(0, good.length - 1),
        'one point missing': good.sublist(0, good.length - 4),
        'the counts cut': good.sublist(0, 11),
        'one byte more': Uint8List.fromList([...good, 0]),
        'a longitude past 180°': asset([
          [(0, 0), (18001, 0), (0, 10)],
        ]),
        'a longitude past -180°': asset([
          [(0, 0), (-18001, 0), (0, 10)],
        ]),
        'a latitude past 90°': asset([
          [(0, 0), (10, 9001), (0, 10)],
        ]),
        'a latitude past -90°': asset([
          [(0, 0), (10, -9001), (0, 10)],
        ]),
        'the lowest int16': asset([
          [(0, 0), (-32768, 0), (0, 10)],
        ]),
      };
      for (final MapEntry(key: name, value: bytes) in cases.entries) {
        expect(WorldMap.parse(bytes), isNull, reason: name);
      }
    });

    test('an asset larger than the bound is not read', () {
      // As many rings of 100 points as fit under the bound, then one more.
      final ring = [for (var i = 0; i < 100; i++) (i, i)];
      final rings = (WorldMap.maxBytes - 10) ~/ (2 + 4 * 100);
      final largest = asset(List.filled(rings, ring));
      expect(largest.length, lessThanOrEqualTo(WorldMap.maxBytes));
      expect(WorldMap.parse(largest), isNotNull);
      final larger = asset(List.filled(rings + 1, ring));
      expect(larger.length, greaterThan(WorldMap.maxBytes));
      expect(WorldMap.parse(larger), isNull);
    });

    test('its bounds are the asset\'s: ±180° and ±90° in hundredths', () {
      expect(
        WorldMap.parse(
          asset([
            [(-18000, -9000), (18000, 9000), (0, 0)],
          ]),
        ),
        isNotNull,
      );
    });
  });
}

/// Whether `python3` can be run here: a machine without it skips the script's tests rather than failing the file.
bool _hasPython() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
