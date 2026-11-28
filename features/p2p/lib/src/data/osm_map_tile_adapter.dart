import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:io';
import 'dart:typed_data';

import 'package:bull_logger/bull_logger.dart';

import '../domain/map_tiles.dart';

/// Builds the tile client of one session: [OsmMapTileAdapter.newClient], or a test's.
typedef CreateMapTileClient = HttpClient Function();

/// The tiles of the maps, from OpenStreetMap, outside Tor (#246): the owner's decision of 2026-11-23, as the reference's Android app fetches them through its WebView, which has no proxy (design note `docs/design/phase-3-map-tiles.md` § 1 and § 3, option C).
///
/// The one connection the feature opens itself outside Tor, and its only one to a third party (the wallet's price and swap service, outside Tor too, are reached through the wallet's port, `P2pWalletPort`): `robot_bindings_architecture_test.dart` pins that no other file opens one.
/// What the provider learns, for each tile asked: the phone's IP address, the tile's zoom, column and row, so the area looked at, the time, and the headers below; the phone's network sees the name `tile.openstreetmap.org` asked of its resolver in clear (design note § 5).
///
/// Its rules (design note § 3), each with its test in `map_tiles_test.dart`:
/// - its own `dart:io` client, made for the tiles only, created at a session's first tile and closed with it, never the transport's nor the wallet's; it keeps no cookie and shares no header with the transport; it connects directly, never through a proxy the process's environment would name (`findProxy`);
/// - the one source `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, the reference's (`components/Map/osmTiles.ts:1`), with [MapTile]'s whole zooms 0 to 15; HTTPS only, the certificate always checked as `dart:io` checks it, never set aside, no redirect followed;
/// - the headers, exactly: `User-Agent` and `X-Requested-With` at [name], the name the owner chose on 2026-11-23 for the tile server, in place of the reference's `RoboSats` and `AndroidRobosats` (sending another app's name would impersonate it, which the provider's policy forbids); `If-None-Match` for a tile kept whose time is over; `Accept-Encoding: identity`, in place of `dart:io`'s `gzip`, which would be decompressed in memory (the client is known as a Dart client anyway: its TLS greeting has no ALPN nor GREASE, and `dart:io` writes header names in lower case); and the `Host` HTTP requires: no `Referer`, no cookie, no contact, no address, no version, as the reference sends none (`osmTiles.ts:8-12`);
/// - at most [maxRequests] requests at once, the others waiting; a wait for the connection bounded by [connectTimeout], each wait for data by [readTimeout], and the reading of one answer by [tileTimeout], so that a server that sends a byte now and then holds no place for long;
/// - an answer of at most [maxBytes], read as a tile only when it is a PNG of 256 × 256 pixels ([isTilePng], before any decoding: a small PNG can inflate into a huge picture); an answer with an `x-blocked` header, or « Too Many Requests » (429), is [MapTileRefused], where the reference shows the provider's error picture or a failed tile;
/// - the tiles kept in memory only, at most [maxKept] and [maxKeptBytes] together, the least recently used forgotten first, for the session's life, with their `ETag` and time (`Cache-Control` and `Expires` honoured, 7 days without them, as the provider's policy asks); nothing written to disk; the session closed when the switch goes off or the map closes, which forgets them: the code does not see the phone's network change, so the `ETag`s, which could tie two successive addresses of the phone together, last no longer than one map (design note § 3);
/// - nothing logged but a fixed label for a tile refused or failed, never its address, zoom, column or row, nor the error, whose text may hold the address.
final class OsmMapTileAdapter implements MapTilePort {
  final CreateMapTileClient _createClient;
  final Duration _connectTimeout;
  final Duration _readTimeout;
  final Duration _tileTimeout;
  final DateTime Function() _clock;

  const OsmMapTileAdapter({
    this._createClient = newClient,
    this._connectTimeout = OsmMapTileAdapter.connectTimeout,
    this._readTimeout = OsmMapTileAdapter.readTimeout,
    this._tileTimeout = OsmMapTileAdapter.tileTimeout,
    this._clock = DateTime.now,
  });

  /// The name the tile server is given, in `User-Agent` and `X-Requested-With`: an anagram of « Bull Market », fixed, without version, the same for every user (the owner's decision of 2026-11-23).
  static const name = 'TumbleLark';

  /// The provider's host, without subdomain, as the reference and the provider's policy write it.
  static const host = 'tile.openstreetmap.org';

  /// The most requests at once, as a browser's connections to one host.
  static const maxRequests = 6;

  /// The most bytes of one answer: a tile takes a few tens of KB.
  static const maxBytes = 512 * 1024;

  /// The most tiles a session keeps: a few MB for real tiles, which take a few tens of KB.
  static const maxKept = 256;

  /// The most bytes a session keeps, whatever the tiles' sizes: [maxKept] tiles of 64 KiB, more than real tiles take, where [maxKept] answers of [maxBytes] would take 128 MiB; past it, the least recently used are forgotten first.
  static const maxKeptBytes = 16 * 1024 * 1024;

  /// The longest wait for a connection, and for each part of an answer.
  static const connectTimeout = Duration(seconds: 10);
  static const readTimeout = Duration(seconds: 15);

  /// The longest time one tile's request may take, from its start: past it, the answer is given up at its next bytes.
  static const tileTimeout = Duration(seconds: 30);

  /// How long a tile is kept when its answer says nothing of it: the provider's policy, « cache each tile for at least 7 days ».
  static const defaultLifetime = Duration(days: 7);

  /// The side of a tile, in pixels.
  static const tileSide = 256;

  /// The address of [tile]: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`.
  static Uri urlOf(MapTile tile) =>
      Uri.https(host, '/${tile.z}/${tile.x}/${tile.y}.png');

  /// The client of one session: [name] as its user agent, a direct connection whatever the environment says of a proxy, no decompression, its connection's wait bounded, at most [maxRequests] connections.
  static HttpClient newClient() => HttpClient()
    ..findProxy = _direct
    ..userAgent = name
    ..autoUncompress = false
    ..connectionTimeout = connectTimeout
    ..idleTimeout = readTimeout
    ..maxConnectionsPerHost = maxRequests;

  static String _direct(Uri url) => 'DIRECT';

  /// Whether [bytes] are a PNG whose header (`IHDR`, its first chunk) gives 256 × 256 pixels: read before the picture is decoded.
  static bool isTilePng(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const header = [0x49, 0x48, 0x44, 0x52];
    // The signature, the chunk's length and type, its 13 bytes of data and its checksum.
    if (bytes.length < 33) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    for (var i = 0; i < header.length; i++) {
      if (bytes[12 + i] != header[i]) return false;
    }
    final data = ByteData.sublistView(bytes);
    return data.getUint32(8) == 13 &&
        data.getUint32(16) == tileSide &&
        data.getUint32(20) == tileSide;
  }

  @override
  MapTileSession open() => _OsmMapTileSession(this);
}

/// A tile kept: its picture, its `ETag` when the provider gave a usable one, and until when it is fresh.
final class _KeptTile {
  final Uint8List png;
  final String? etag;
  final DateTime freshUntil;

  const _KeptTile(this.png, this.etag, this.freshUntil);
}

/// One tile asked: waiting, then running; given up by [drop].
final class _TileRequest {
  final MapTile tile;

  /// The tile kept whose time is over, asked again with its `ETag`.
  final _KeptTile? kept;
  final done = Completer<MapTileOutcome>();
  HttpClientRequest? http;
  bool dropped = false;

  _TileRequest(this.tile, this.kept);

  void drop() {
    if (dropped) return;
    dropped = true;
    http?.abort();
    finish(const MapTileDropped());
  }

  void finish(MapTileOutcome outcome) {
    if (!done.isCompleted) done.complete(outcome);
  }
}

final class _OsmMapTileSession implements MapTileSession {
  final OsmMapTileAdapter _adapter;

  /// The client, created at the first tile asked, never before.
  HttpClient? _client;
  bool _closed = false;

  /// The tiles kept, the least recently used first.
  final _kept = <MapTile, _KeptTile>{};
  var _keptBytes = 0;

  /// The tiles asked, waiting or running.
  final _requests = <MapTile, _TileRequest>{};
  final _waiting = Queue<_TileRequest>();
  var _running = 0;

  _OsmMapTileSession(this._adapter);

  /// An `ETag` sent back only when it is one as HTTP writes it, short and printable: anything else is not kept.
  static final _etagPattern = RegExp(r'^(W/)?"[\x21\x23-\x7E]{0,200}"$');
  static final _maxAgePattern = RegExp(r'(?:^|[,\s])max-age\s*=\s*(\d{1,10})');

  @override
  Future<MapTileOutcome> fetch(MapTile tile) {
    if (_closed) return Future.value(const MapTileDropped());
    final kept = _kept.remove(tile);
    if (kept != null) {
      _kept[tile] = kept;
      if (_adapter._clock().isBefore(kept.freshUntil)) {
        return Future.value(MapTileImage(kept.png));
      }
    }
    final asked = _requests[tile];
    if (asked != null) return asked.done.future;
    final request = _TileRequest(tile, kept);
    _requests[tile] = request;
    _waiting.add(request);
    _start();
    return request.done.future;
  }

  @override
  void drop(MapTile tile) {
    final request = _requests.remove(tile);
    if (request == null) return;
    _waiting.remove(request);
    request.drop();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final requests = [..._requests.values];
    _requests.clear();
    _waiting.clear();
    for (final request in requests) {
      request.drop();
    }
    _client?.close(force: true);
    _client = null;
    _kept.clear();
    _keptBytes = 0;
  }

  void _start() {
    while (!_closed &&
        _running < OsmMapTileAdapter.maxRequests &&
        _waiting.isNotEmpty) {
      final request = _waiting.removeFirst();
      _running++;
      unawaited(
        _run(request).whenComplete(() {
          _running--;
          _start();
        }),
      );
    }
  }

  Future<void> _run(_TileRequest request) async {
    final outcome = await _ask(request);
    if (identical(_requests[request.tile], request)) {
      _requests.remove(request.tile);
    }
    switch (outcome) {
      case MapTileRefused():
        log.info('P2P map tile: refused');
      case MapTileFailed():
        log.info('P2P map tile: failed');
      case MapTileImage() || MapTileDropped():
        break;
    }
    request.finish(outcome);
  }

  bool _given(_TileRequest request) => request.dropped || _closed;

  Future<MapTileOutcome> _ask(_TileRequest request) async {
    final started = Stopwatch()..start();
    try {
      final client = _client ??= _adapter._createClient();
      final connecting = client.getUrl(OsmMapTileAdapter.urlOf(request.tile));
      final http = await connecting.timeout(
        _adapter._connectTimeout,
        onTimeout: () {
          // A connection that comes after its wait is let go at once, never kept unused until the session closes; one that fails after its wait is dropped, as the tile already failed, but an `Error`, a bug, still surfaces in the zone (rule 11 of `AGENTS.md`, #314).
          unawaited(
            connecting.then(
              (late) => late.abort(),
              onError: (Object error, StackTrace stackTrace) {
                if (error is! Exception) {
                  Error.throwWithStackTrace(error, stackTrace);
                }
              },
            ),
          );
          throw TimeoutException(null);
        },
      );
      if (_given(request)) {
        http.abort();
        return const MapTileDropped();
      }
      request.http = http;
      http
        ..followRedirects = false
        ..maxRedirects = 0
        ..persistentConnection = true;
      http.headers
        ..removeAll(HttpHeaders.acceptEncodingHeader)
        ..set(HttpHeaders.acceptEncodingHeader, 'identity')
        ..set(HttpHeaders.userAgentHeader, OsmMapTileAdapter.name)
        ..set(
          'X-Requested-With',
          OsmMapTileAdapter.name,
          preserveHeaderCase: true,
        );
      if (request.kept?.etag case final etag?) {
        http.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response = await http.close().timeout(_adapter._readTimeout);
      return await _read(request, response, started);
    } on Exception {
      // The exception is never logged nor kept: its text may hold the tile's address.
      return _given(request) ? const MapTileDropped() : const MapTileFailed();
    }
  }

  Future<MapTileOutcome> _read(
    _TileRequest request,
    HttpClientResponse response,
    Stopwatch started,
  ) async {
    final status = response.statusCode;
    final kept = request.kept;
    if (status == HttpStatus.notModified && kept != null) {
      _discard(response);
      final png = kept.png;
      _keep(request.tile, png, response.headers, kept.etag);
      return MapTileImage(png);
    }
    // Too many requests: a refusal, as `x-blocked`, so that nothing more is asked.
    if (status == HttpStatus.tooManyRequests) {
      _discard(response);
      return const MapTileRefused();
    }
    if (status != HttpStatus.ok) {
      _discard(response);
      return const MapTileFailed();
    }
    if (response.headers['x-blocked'] != null) {
      _discard(response);
      return const MapTileRefused();
    }
    if (response.contentLength > OsmMapTileAdapter.maxBytes) {
      _discard(response);
      return const MapTileFailed();
    }
    final body = BytesBuilder(copy: false);
    // Leaving the loop cancels the answer, which closes its connection.
    await for (final chunk in response.timeout(_adapter._readTimeout)) {
      if (_given(request)) return const MapTileDropped();
      body.add(chunk);
      if (body.length > OsmMapTileAdapter.maxBytes ||
          started.elapsed > _adapter._tileTimeout) {
        return const MapTileFailed();
      }
    }
    if (_given(request)) return const MapTileDropped();
    final png = body.takeBytes();
    if (!OsmMapTileAdapter.isTilePng(png)) return const MapTileFailed();
    _keep(request.tile, png, response.headers, null);
    return MapTileImage(png);
  }

  /// Keeps [png] for [tile] for as long as [headers] say, with their `ETag`, or [etag] when they give none: nothing when they say `no-store`.
  void _keep(MapTile tile, Uint8List png, HttpHeaders headers, String? etag) {
    if (_closed) return;
    final lifetime = _lifetimeOf(headers);
    if (lifetime == null) {
      _forget(tile);
      return;
    }
    final given = headers[HttpHeaders.etagHeader];
    final tag = given == null
        ? etag
        : (given.length == 1 && _etagPattern.hasMatch(given.single)
              ? given.single
              : null);
    _forget(tile);
    _kept[tile] = _KeptTile(png, tag, _adapter._clock().add(lifetime));
    _keptBytes += png.length;
    while (_kept.length > 1 &&
        (_kept.length > OsmMapTileAdapter.maxKept ||
            _keptBytes > OsmMapTileAdapter.maxKeptBytes)) {
      _forget(_kept.keys.first);
    }
  }

  void _forget(MapTile tile) {
    final kept = _kept.remove(tile);
    if (kept != null) _keptBytes -= kept.png.length;
  }

  /// How long a tile is fresh: `Cache-Control`'s `max-age`, else `Expires`, else [OsmMapTileAdapter.defaultLifetime]; `null` for `no-store`.
  Duration? _lifetimeOf(HttpHeaders headers) {
    final control = headers[HttpHeaders.cacheControlHeader]
        ?.join(',')
        .toLowerCase();
    if (control != null) {
      if (control.contains('no-store')) return null;
      final seconds = int.tryParse(
        _maxAgePattern.firstMatch(control)?.group(1) ?? '',
      );
      if (seconds != null) {
        return Duration(
          seconds: seconds.clamp(
            0,
            OsmMapTileAdapter.defaultLifetime.inSeconds,
          ),
        );
      }
    }
    final expires = headers[HttpHeaders.expiresHeader];
    if (expires != null && expires.length == 1) {
      try {
        final until = HttpDate.parse(expires.single);
        final left = until.difference(_adapter._clock());
        return left.isNegative
            ? Duration.zero
            : (left > OsmMapTileAdapter.defaultLifetime
                  ? OsmMapTileAdapter.defaultLifetime
                  : left);
      } on HttpException {
        return Duration.zero;
      }
    }
    return OsmMapTileAdapter.defaultLifetime;
  }

  /// Lets an answer go unread: its connection is closed, not reused.
  static void _discard(HttpClientResponse response) {
    response.listen(null).cancel().ignore();
  }
}
