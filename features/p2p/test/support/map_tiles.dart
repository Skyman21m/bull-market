import 'dart:async';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/testing.dart';

/// A tile provider of the tests (#246): it never makes a request; each tile asked is recorded, and answered with a picture the test makes ([testTilePng]) unless [answer] says otherwise.
///
/// While [held], answers wait until [release].
final class FakeMapTiles implements MapTilePort {
  MapTileOutcome Function(MapTile tile) answer;
  bool held;
  final sessions = <FakeTileSession>[];

  FakeMapTiles({
    MapTileOutcome Function(MapTile tile)? answer,
    this.held = false,
  }) : answer = answer ?? ((tile) => MapTileImage(testTilePng(tile)));

  /// Every tile asked of every session, in order.
  List<MapTile> get asked => [for (final session in sessions) ...session.asked];

  /// Every tile given up, in order.
  List<MapTile> get dropped => [
    for (final session in sessions) ...session.dropped,
  ];

  /// Answers every tile held.
  void release() {
    held = false;
    for (final session in sessions) {
      session.release();
    }
  }

  @override
  MapTileSession open() {
    final session = FakeTileSession(this);
    sessions.add(session);
    return session;
  }
}

final class FakeTileSession implements MapTileSession {
  final FakeMapTiles _tiles;
  final asked = <MapTile>[];
  final dropped = <MapTile>[];
  final _waiting = <MapTile, Completer<MapTileOutcome>>{};
  bool closed = false;

  FakeTileSession(this._tiles);

  void release() {
    final waiting = {..._waiting};
    _waiting.clear();
    for (final MapEntry(key: tile, value: done) in waiting.entries) {
      done.complete(_tiles.answer(tile));
    }
  }

  @override
  Future<MapTileOutcome> fetch(MapTile tile) {
    if (closed) fail('a tile asked of a closed session');
    asked.add(tile);
    if (!_tiles.held) return Future.value(_tiles.answer(tile));
    final done = _waiting[tile] = Completer<MapTileOutcome>();
    return done.future;
  }

  @override
  void drop(MapTile tile) {
    dropped.add(tile);
    _waiting.remove(tile)?.complete(const MapTileDropped());
  }

  @override
  void close() {
    closed = true;
    for (final done in _waiting.values) {
      done.complete(const MapTileDropped());
    }
    _waiting.clear();
  }
}

/// A PNG of 256 × 256 pixels made by the test, never a real tile (real tiles are under licence): a checkerboard of 32-pixel squares, in a colour that changes with the tile's column and row, so that two tiles side by side differ.
Uint8List testTilePng(MapTile tile, {int side = 256}) {
  final light = [
    0x60 + (tile.x * 37) % 0x80,
    0x90 + (tile.y * 53) % 0x60,
    0xC0 + (tile.z * 7) % 0x30,
  ];
  final dark = [for (final value in light) value ~/ 2];
  final raw = BytesBuilder();
  for (var row = 0; row < side; row++) {
    raw.addByte(0);
    for (var column = 0; column < side; column++) {
      final square = (row ~/ 32 + column ~/ 32).isEven;
      raw.add(square ? light : dark);
    }
  }
  return pngOf(side, side, raw.takeBytes());
}

/// A PNG of [width] by [height] RGB pixels from [scanlines], each led by its filter byte.
Uint8List pngOf(int width, int height, List<int> scanlines) {
  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = [...type.codeUnits, ...data];
    png
      ..add(_uint32(data.length))
      ..add(typed)
      ..add(_uint32(_crc32(typed)));
  }

  chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 2, 0, 0, 0]);
  chunk('IDAT', zlib.encode(scanlines));
  chunk('IEND', const []);
  return png.takeBytes();
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 8) & 0xFF,
  value & 0xFF,
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
