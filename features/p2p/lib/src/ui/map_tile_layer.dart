import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/map_tiles.dart';

/// What a map draws of its tiles at one moment: the tiles in view, at one whole zoom, and the pictures of those that came; a tile without its picture leaves the countries drawn in its square.
@immutable
final class MapTileFrame {
  final List<MapTile> wanted;
  final Map<MapTile, ui.Image> images;

  const MapTileFrame(this.wanted, this.images);
}

/// The tiles of one map (#246): « Show tiles » and the acknowledgment of its dialog, kept by the map as the reference keeps them in each map's state (`useTiles` and `acceptedTilesWarning`, `F2fMap.tsx:40-41`, `MapChart/index.tsx:37-38`, commit babf62e), so forgotten with the map: every map opened starts without tiles and asks again.
///
/// Nothing is asked before [show], which needs [acknowledge] first: the session, and so the client, is opened only then; [hide] and [dispose] close it.
/// [view] asks the tiles in view and gives up those that left it, as the reference's tile layer aborts them (`AbortController`, `components/Map/index.tsx`); a tile that failed is asked again once the view's tiles change, at the next pan or zoom; once the provider refused one, nothing more is asked until the switch is turned off and on again.
/// The pictures are decoded here and kept only while their tile is in view; their bytes stay in the session, in memory.
final class MapTileLayer extends ChangeNotifier {
  final MapTileSession Function() _open;
  MapTileSession? _session;
  bool _acknowledged = false;
  bool _refused = false;
  bool _disposed = false;

  List<MapTile> _wanted = const [];
  final _images = <MapTile, ui.Image>{};

  /// The tiles asked, until their picture is decoded.
  final _asked = <MapTile>{};
  final _failed = <MapTile>{};
  MapTileFrame? _frame;

  MapTileLayer(this._open);

  /// Whether « Acknowledged » was pressed on this map.
  bool get acknowledged => _acknowledged;

  /// Whether the tiles are shown: the switch is on.
  bool get shown => _session != null;

  /// Whether a tile in view failed, or the provider refused one: « Map tiles unavailable ».
  bool get unavailable =>
      _session != null && (_refused || _wanted.any(_failed.contains));

  /// What the map draws of its tiles, or `null` while they are not shown.
  MapTileFrame? get frame => _session == null
      ? null
      : _frame ??= MapTileFrame(
          List.unmodifiable(_wanted),
          Map.unmodifiable(_images),
        );

  /// « Acknowledged » of the dialog, which lets [show] open the tiles.
  void acknowledge() => _acknowledged = true;

  /// Turns the tiles on, once acknowledged: the session opens, nothing is sent until [view] asks a tile.
  void show() {
    if (!_acknowledged || _session != null || _disposed) return;
    _session = _open();
    _changed();
  }

  /// Turns the tiles off: the session is closed, the tiles it kept forgotten, the pictures let go.
  void hide() {
    if (_session == null) return;
    _close();
    _changed();
  }

  /// The view of [size] points centred on the point [x], [y] of the map at [zoom]: the tiles now in view that are not there are asked, those that left it given up.
  ///
  /// It notifies nothing, so that a map may call it while it builds and read [frame] after it.
  void view({
    required double zoom,
    required double x,
    required double y,
    required ui.Size size,
  }) {
    final session = _session;
    if (session == null) return;
    final wanted = MapTile.covering(
      zoom: zoom,
      x: x,
      y: y,
      width: size.width,
      height: size.height,
    );
    if (listEquals(wanted, _wanted)) return;
    final inView = wanted.toSet();
    for (final tile in [..._asked]) {
      if (inView.contains(tile)) continue;
      _asked.remove(tile);
      session.drop(tile);
    }
    _images.removeWhere((tile, image) {
      if (inView.contains(tile)) return false;
      image.dispose();
      return true;
    });
    // The next pan or zoom asks again the tiles that failed.
    _failed.clear();
    _wanted = wanted;
    _frame = null;
    if (_refused) return;
    for (final tile in wanted) {
      if (_images.containsKey(tile) || _asked.contains(tile)) continue;
      _asked.add(tile);
      unawaited(_load(session, tile));
    }
  }

  Future<void> _load(MapTileSession session, MapTile tile) async {
    final outcome = await session.fetch(tile);
    if (!identical(session, _session) || !_asked.contains(tile)) return;
    switch (outcome) {
      case MapTileImage(:final png):
        final image = await _decode(png);
        if (!identical(session, _session) || !_asked.remove(tile)) {
          image?.dispose();
          return;
        }
        if (image == null) {
          _failed.add(tile);
        } else {
          _images[tile] = image;
        }
      case MapTileRefused():
        _asked.remove(tile);
        _failed.add(tile);
        _refused = true;
      case MapTileFailed():
        _asked.remove(tile);
        _failed.add(tile);
      case MapTileDropped():
        _asked.remove(tile);
        return;
    }
    _frame = null;
    _changed();
  }

  /// The picture of [png], already checked to be a PNG of 256 × 256 pixels; `null` when it cannot be decoded.
  static Future<ui.Image?> _decode(Uint8List png) async {
    try {
      final codec = await ui.instantiateImageCodec(png);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Exception {
      return null;
    }
  }

  void _close() {
    final session = _session;
    _session = null;
    session?.close();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _asked.clear();
    _failed.clear();
    _wanted = const [];
    _refused = false;
    _frame = null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _close();
    super.dispose();
  }
}
