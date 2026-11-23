import '../map_tiles.dart';

/// Opens the tiles of one map, once its « Show tiles » is on and its dialog acknowledged (#246): nothing is sent until the session's first tile is asked.
///
/// Its only callers are the two maps, through the composition that hands them its [execute].
final class OpenMapTilesUsecase {
  final MapTilePort _tiles;

  const OpenMapTilesUsecase(this._tiles);

  MapTileSession execute() => _tiles.open();
}
