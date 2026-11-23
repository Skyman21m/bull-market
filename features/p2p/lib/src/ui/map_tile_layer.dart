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

/// « Show tiles » and the acknowledgment of its dialog, kept as long as the reference keeps them (`useTiles` and `acceptedTilesWarning`, `F2fMap.tsx:40-41`, `MapChart/index.tsx:37-38`, commit babf62e): the book's map holds its own, forgotten when the map is built anew, as the reference's `MapChart` is unmounted with its view; the meeting point's map is given the create form's, as the reference's `F2fMapDialog` stays mounted in `MakerForm` (`MakerForm.tsx:651-665`), so that the map opened again from the same form has its tiles on without the dialog, and a new form starts off.
///
/// [refused] is kept with them: once the provider refused a tile, nothing more is asked, the map opened again included, until the switch is turned off and on again.
final class MapTilesChoice {
  bool acknowledged = false;
  bool shown = false;
  bool refused = false;
}

/// The tiles of one map while it is open (#246), from its [MapTilesChoice].
///
/// Nothing is asked before [show], which needs [acknowledge] first; a layer made from a choice already shown opens its session at once, the user having acknowledged the dialog in that form. The session, and so the client, is opened only then; [hide] and [dispose] close it, which forgets its tiles and their `ETag`s.
/// [view] asks the tiles in view and gives up those that left it, as the reference's tile layer aborts them (`AbortController`, `components/Map/index.tsx`), where Leaflet keeps them up to two tiles beyond the view (`keepBuffer`); a tile that failed is asked again only once the set of tiles in view changes, at the next pan or zoom that brings or takes a tile, never on a mere redraw; once the provider refused one (`x-blocked`, or too many requests), nothing more is asked until the switch is turned off and on again.
/// While the map is covered by another page ([pause]), the tiles asked are given up, those waiting their turn included, and nothing is asked until it is shown again ([resume]).
/// The pictures are decoded here and kept only while their tile is in view; their bytes stay in the session, in memory.
final class MapTileLayer extends ChangeNotifier {
  final MapTileSession Function() _open;
  final MapTilesChoice _choice;
  MapTileSession? _session;
  bool _disposed = false;
  bool _paused = false;

  /// Whether the next [view] asks again what is missing even when the tiles in view are the same: after [resume].
  bool _stale = false;

  List<MapTile> _wanted = const [];
  Set<MapTile> _inView = const {};
  final _images = <MapTile, ui.Image>{};

  /// The tiles asked, until their picture is decoded.
  final _asked = <MapTile>{};
  final _failed = <MapTile>{};
  MapTileFrame? _frame;

  MapTileLayer(this._open, {MapTilesChoice? choice})
    : _choice = choice ?? MapTilesChoice() {
    if (_choice.acknowledged && _choice.shown) _session = _open();
  }

  /// Whether « Acknowledged » was pressed for this map.
  bool get acknowledged => _choice.acknowledged;

  /// Whether the tiles are shown: the switch is on.
  bool get shown => _session != null;

  /// Whether a tile in view failed, or the provider refused one: « Map tiles unavailable ».
  bool get unavailable =>
      _session != null && (_choice.refused || _wanted.any(_failed.contains));

  /// What the map draws of its tiles, or `null` while they are not shown.
  MapTileFrame? get frame => _session == null
      ? null
      : _frame ??= MapTileFrame(
          List.unmodifiable(_wanted),
          Map.unmodifiable(_images),
        );

  /// « Acknowledged » of the dialog, which lets [show] open the tiles.
  void acknowledge() => _choice.acknowledged = true;

  /// Turns the tiles on, once acknowledged: the session opens, nothing is sent until [view] asks a tile.
  void show() {
    if (!_choice.acknowledged || _session != null || _disposed) return;
    _choice
      ..shown = true
      ..refused = false;
    _session = _open();
    _changed();
  }

  /// Turns the tiles off: the session is closed, the tiles it kept forgotten, the pictures let go.
  void hide() {
    if (_session == null) return;
    _choice
      ..shown = false
      ..refused = false;
    _close();
    _changed();
  }

  /// The map is covered by another page: every tile asked is given up, and nothing is asked until [resume]; the pictures stay.
  void pause() {
    if (_paused) return;
    _paused = true;
    final session = _session;
    for (final tile in [..._asked]) {
      session?.drop(tile);
    }
    _asked.clear();
  }

  /// The map is shown again: the next [view] asks what is missing.
  void resume() {
    if (!_paused) return;
    _paused = false;
    _stale = true;
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
    if (session == null || _paused) return;
    final wanted = MapTile.covering(
      zoom: zoom,
      x: x,
      y: y,
      width: size.width,
      height: size.height,
    );
    final inView = wanted.toSet();
    // The same tiles in another order, as a pan within them gives: nothing to ask, nothing to give up.
    if (!_stale && setEquals(inView, _inView)) return;
    _stale = false;
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
    // The tiles in view changed: those that failed are asked again, once.
    _failed.clear();
    _wanted = wanted;
    _inView = inView;
    _frame = null;
    if (_choice.refused) return;
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
        _choice.refused = true;
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
    _inView = const {};
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
