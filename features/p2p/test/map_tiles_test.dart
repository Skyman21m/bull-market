import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/osm_map_tile_adapter.dart';
import 'package:p2p/src/domain/map_tiles.dart';

import 'support/map_tiles.dart';

/// The tiles of the maps (#246): the tile numbers, and the rules of the client of OpenStreetMap's tiles (design note `docs/design/phase-3-map-tiles.md` § 3), against a provider of the test on the loopback, which the client reaches through its connection factory: no request ever leaves the machine, and no real tile is read.
void main() {
  group('MapTile', () {
    test(
      'a tile is a whole zoom from 0 to 15, its column and row within it',
      () {
        expect(MapTile.of(0, 0, 0), isNotNull);
        expect(MapTile.of(15, 32767, 32767), isNotNull);
        expect(MapTile.of(16, 0, 0), isNull);
        expect(MapTile.of(-1, 0, 0), isNull);
        expect(MapTile.of(1, 2, 0), isNull);
        expect(MapTile.of(1, 0, -1), isNull);
        expect(MapTile.maxZoom, 15);
      },
    );

    test('it never says which tile it is in a text', () {
      expect('${MapTile.of(13, 4231, 2873)}', 'MapTile');
    });

    test(
      'the tiles of a view are those of the rounded zoom, never beyond 15',
      () {
        expect(MapTile.zoomOf(2.4), 2);
        expect(MapTile.zoomOf(2.5), 3);
        expect(MapTile.zoomOf(15), 15);
        expect(MapTile.zoomOf(17), 15);
        expect(MapTile.zoomOf(-3), 0);
        expect(MapTile.zoomOf(double.nan), 1);
        // A view asked beyond the map's zooms still gets tiles of zoom 15, never of a nearer one.
        final near = MapTile.covering(
          zoom: 17,
          x: 0.5,
          y: 0.5,
          width: 360,
          height: 640,
        );
        expect(near, isNotEmpty);
        expect(near.map((tile) => tile.z).toSet(), {15});
      },
    );

    test(
      'only the tiles that meet the view are asked, the nearest the centre first',
      () {
        // Zoom 2 is 1024 points wide: a view of 256 × 256 centred on the map meets the four middle tiles only.
        final tiles = MapTile.covering(
          zoom: 2,
          x: 0.5,
          y: 0.5,
          width: 256,
          height: 256,
        );
        expect(tiles.toSet(), {
          MapTile.of(2, 1, 1),
          MapTile.of(2, 2, 1),
          MapTile.of(2, 1, 2),
          MapTile.of(2, 2, 2),
        });
        // Twice as wide and moved by a quarter of a tile, the view meets six; the two nearest its centre first.
        final moved = MapTile.covering(
          zoom: 2,
          x: 0.5 + 64 / 1024,
          y: 0.5,
          width: 512,
          height: 256,
        );
        expect(moved, hasLength(4 + 2));
        expect(moved.take(2).toSet(), {
          MapTile.of(2, 2, 1),
          MapTile.of(2, 2, 2),
        });
        // The whole world at zoom 0 is one tile, whatever the view's size.
        expect(
          MapTile.covering(zoom: 0, x: 0.5, y: 0.5, width: 2000, height: 2000),
          [MapTile.of(0, 0, 0)],
        );
        // No tile beyond the world's edges, and none for a view that is no size.
        expect(MapTile.covering(zoom: 3, x: 0, y: 0, width: 256, height: 256), [
          MapTile.of(3, 0, 0),
        ]);
        expect(
          MapTile.covering(zoom: 3, x: 0.5, y: 0.5, width: 0, height: 256),
          isEmpty,
        );
      },
    );
  });

  group('the tile client stands apart', () {
    // Tests run with the package directory as working directory.
    final sources = {
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
    };
    const adapter = 'lib/src/data/osm_map_tile_adapter.dart';
    const transport = 'lib/src/data/tor_coordinator_transport.dart';

    test(
      'only the composition builds it; it takes nothing of Tor nor of the transport',
      () {
        expect(sources.keys, containsAll([adapter, transport]));
        expect(
          {
            for (final MapEntry(key: path, value: source) in sources.entries)
              if (source.contains('OsmMapTileAdapter')) path,
          },
          {adapter, 'lib/src/p2p_locator.dart'},
        );
        final own = sources[adapter] ?? '';
        for (final word in const [
          'bull_tor',
          'tor_coordinator_transport',
          'package:dio',
          'robosats',
          'secrets',
          'p2p_wallet_port',
        ]) {
          expect(own, isNot(contains(word)), reason: word);
        }
      },
    );

    test(
      'no header of the tiles in the transport, nor of the transport in the tiles',
      () {
        final coordinators = sources[transport] ?? '';
        for (final word in const [
          'TumbleLark',
          'X-Requested-With',
          'map_tile',
        ]) {
          expect(coordinators, isNot(contains(word)), reason: word);
        }
        // The transport's own fields of a request: none in the tile client.
        final own = sources[adapter] ?? '';
        for (final word in const [
          'Authorization',
          'Content-Type',
          'sessionKey',
        ]) {
          expect(own, isNot(contains(word)), reason: word);
        }
      },
    );

    test(
      'the certificate is never set aside, and nothing but HTTPS to the one host',
      () {
        for (final MapEntry(key: path, value: source) in sources.entries) {
          expect(
            source,
            isNot(contains('badCertificateCallback')),
            reason: path,
          );
        }
        final own = sources[adapter] ?? '';
        expect(own, isNot(contains('http://')));
        expect(own, isNot(contains('Uri.http(')));
        // The only proxy rule is a direct connection.
        expect(RegExp(r'findProxy\s*=').allMatches(own), hasLength(1));
        expect(own, contains('..findProxy = _direct'));
        expect(own, contains("static String _direct(Uri url) => 'DIRECT';"));
        expect(own, isNot(contains('connectionFactory')));
        // Nothing that writes: no file, no folder, no stored preference.
        for (final word in const [
          'File',
          'Directory',
          'path_provider',
          'SharedPreferences',
          'drift',
        ]) {
          expect(own, isNot(contains(word)), reason: word);
        }
      },
    );
  });

  group('isTilePng', () {
    test('a PNG of 256 × 256 pixels, read from its header before decoding', () {
      final tile = MapTile.of(1, 0, 0);
      if (tile == null) fail('no tile');
      expect(OsmMapTileAdapter.isTilePng(testTilePng(tile)), isTrue);
      expect(
        OsmMapTileAdapter.isTilePng(testTilePng(tile, side: 512)),
        isFalse,
      );
      expect(OsmMapTileAdapter.isTilePng(pngOf(256, 4096, const [])), isFalse);
      // A JPEG's first bytes, and a PNG cut short.
      expect(
        OsmMapTileAdapter.isTilePng(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(40, 0)]),
        ),
        isFalse,
      );
      expect(
        OsmMapTileAdapter.isTilePng(
          Uint8List.sublistView(testTilePng(tile), 0, 30),
        ),
        isFalse,
      );
    });
  });

  group('the client of the tiles', () {
    late _Provider provider;

    setUp(() async {
      provider = await _Provider.start();
    });

    tearDown(() => provider.stop());

    final tile = MapTile.of(13, 4231, 2873);
    if (tile == null) throw StateError('no tile');

    test('opening a session creates no client and sends nothing', () async {
      final session = provider.adapter().open();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.clients, 0);
      expect(provider.heads, isEmpty);
      final outcome = await session.fetch(tile);
      expect(outcome, isA<MapTileImage>());
      expect(provider.clients, 1);
      session.close();
    });

    test(
      'the request: the one address, over HTTPS, with exactly these headers',
      () async {
        final session = provider.adapter().open();
        expect(await session.fetch(tile), isA<MapTileImage>());
        session.close();
        expect(
          provider.targets.single,
          Uri.parse('https://tile.openstreetmap.org/13/4231/2873.png'),
        );
        final head = provider.heads.single;
        final lines = head.split('\r\n');
        expect(lines.first, 'GET /13/4231/2873.png HTTP/1.1');
        expect(_headersOf(head), {
          'user-agent': ['TumbleLark'],
          'x-requested-with': ['TumbleLark'],
          'accept-encoding': ['identity'],
          'host': ['tile.openstreetmap.org'],
        });
        // Nothing of the app's names, of Dart, of a contact or of a version.
        for (final word in const [
          'bull',
          'market',
          'troc',
          'robosats',
          'dart',
          'referer',
          'cookie',
          'http://',
          '@',
        ]) {
          expect(head.toLowerCase(), isNot(contains(word)), reason: word);
        }
      },
    );

    test('the name the provider is given is TumbleLark, in both headers', () {
      expect(OsmMapTileAdapter.name, 'TumbleLark');
      expect(OsmMapTileAdapter.host, 'tile.openstreetmap.org');
      expect(
        OsmMapTileAdapter.urlOf(tile).toString(),
        'https://tile.openstreetmap.org/13/4231/2873.png',
      );
    });

    test(
      'a tile kept is not asked again; once its time is over it is asked with its ETag, and « Not Modified » shows it',
      () async {
        var now = DateTime.utc(2026, 11, 23, 12);
        provider.answer = (head) => _ok(
          testTilePng(tile),
          headers: {'ETag': '"tile-1"', 'Cache-Control': 'max-age=60'},
        );
        final session = provider.adapter(clock: () => now).open();
        final first = await session.fetch(tile);
        final second = await session.fetch(tile);
        expect(provider.heads, hasLength(1));
        expect((second as MapTileImage).png, (first as MapTileImage).png);
        now = now.add(const Duration(seconds: 61));
        provider.answer = (head) => _status(304, 'Not Modified');
        final third = await session.fetch(tile);
        expect(provider.heads, hasLength(2));
        expect(_headersOf(provider.heads.last)['if-none-match'], ['"tile-1"']);
        expect((third as MapTileImage).png, first.png);
        session.close();
      },
    );

    test(
      'an ETag that is not one as HTTP writes it is never sent back',
      () async {
        var now = DateTime.utc(2026, 11, 23, 12);
        provider.answer = (head) => _ok(
          testTilePng(tile),
          headers: {'ETag': 'no quotes', 'Cache-Control': 'max-age=1'},
        );
        final session = provider.adapter(clock: () => now).open();
        await session.fetch(tile);
        now = now.add(const Duration(seconds: 2));
        await session.fetch(tile);
        expect(provider.heads, hasLength(2));
        expect(
          _headersOf(provider.heads.last).containsKey('if-none-match'),
          isFalse,
        );
        session.close();
      },
    );

    test('a redirect is never followed', () async {
      provider.answer = (head) => _status(
        302,
        'Found',
        headers: {'Location': 'http://127.0.0.1:${provider.port}/0/0/0.png'},
      );
      final session = provider.adapter().open();
      expect(await session.fetch(tile), isA<MapTileFailed>());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.heads, hasLength(1));
      session.close();
    });

    test('an answer but 200 is no tile', () async {
      provider.answer = (head) => _status(404, 'Not Found');
      final session = provider.adapter().open();
      expect(await session.fetch(tile), isA<MapTileFailed>());
      session.close();
    });

    test(
      'a tile with an x-blocked header is refused, its picture unread',
      () async {
        provider.answer = (head) =>
            _ok(testTilePng(tile), headers: {'x-blocked': 'Referer'});
        final session = provider.adapter().open();
        expect(await session.fetch(tile), isA<MapTileRefused>());
        session.close();
      },
    );

    test(
      'at most six requests at once, by the client\'s own queue, whatever its connections allow',
      () async {
        final release = Completer<void>();
        provider.answer = (head) async {
          await release.future;
          return _ok(testTilePng(tile));
        };
        final session = provider.adapter(connections: 20).open();
        final outcomes = [
          for (var x = 0; x < 10; x++)
            session.fetch(MapTile.of(13, x, 0) ?? tile),
        ];
        await _until(() => provider.running == 6);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(provider.running, 6);
        release.complete();
        await Future.wait(outcomes);
        expect(provider.mostRunning, 6);
        session.close();
      },
    );

    test(
      'a connection that comes after its wait is let go at once, nothing sent on it',
      () async {
        final session = OsmMapTileAdapter(
          createClient: () =>
              OsmMapTileAdapter.newClient()
                ..connectionFactory = (uri, host, port) async {
                  await Future<void>.delayed(const Duration(milliseconds: 600));
                  return Socket.startConnect(
                    InternetAddress.loopbackIPv4,
                    provider.port,
                  );
                },
          connectTimeout: const Duration(milliseconds: 300),
        ).open();
        expect(await session.fetch(tile), isA<MapTileFailed>());
        final watch = Stopwatch()..start();
        while ((provider.accepted == 0 || provider.ended == 0) &&
            watch.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        // The session still open: only the late connection's own release ends it.
        expect(provider.accepted, 1);
        expect(provider.ended, 1);
        expect(provider.heads, isEmpty);
        session.close();
      },
    );

    test(
      'a connection that fails after its wait: dropped when the network fails it, an Error still surfaces in the zone (#314)',
      () async {
        final outcomes = <MapTileOutcome>[];
        final reported = <Object>[];
        await runZonedGuarded(() async {
          for (final late in <Object>[
            const SocketException('late'),
            StateError('a bug'),
          ]) {
            final session = OsmMapTileAdapter(
              createClient: () => OsmMapTileAdapter.newClient()
                ..connectionFactory = (uri, host, port) async {
                  await Future<void>.delayed(const Duration(milliseconds: 600));
                  throw late;
                },
              connectTimeout: const Duration(milliseconds: 300),
            ).open();
            outcomes.add(await session.fetch(tile));
            await Future<void>.delayed(const Duration(milliseconds: 600));
            session.close();
          }
        }, (error, _) => reported.add(error));
        expect(outcomes, [isA<MapTileFailed>(), isA<MapTileFailed>()]);
        expect(reported, [isA<StateError>()]);
      },
    );

    test('a direct connection, whatever proxy the environment names', () async {
      await HttpOverrides.runZoned(() async {
        final session = provider.adapter().open();
        expect(await session.fetch(tile), isA<MapTileImage>());
        session.close();
      }, findProxyFromEnvironment: (url, environment) => 'PROXY 127.0.0.1:9');
      expect(provider.proxies, [null]);
    });

    test(
      'closing the session closes a connection whose answer is still coming',
      () async {
        provider.dribble = (head) async* {
          yield latin1.encode(
            'HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nConnection: close\r\n\r\n',
          );
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(seconds: 2));
            yield const [0];
          }
        };
        final session = provider.adapter().open();
        final outcome = session.fetch(tile);
        await _until(() => provider.running == 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        session.close();
        expect(await outcome, isA<MapTileDropped>());
        final watch = Stopwatch()..start();
        while (provider.ended == 0 &&
            watch.elapsed < const Duration(seconds: 1)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(provider.ended, 1);
        expect(watch.elapsed, lessThan(const Duration(milliseconds: 900)));
      },
    );

    test(
      'a session keeps at most 16 MiB of tiles, the least recently used forgotten first',
      () async {
        const size = 400 * 1024;
        Uint8List padded(MapTile one) {
          final png = testTilePng(one);
          return Uint8List(size)..setAll(0, png);
        }

        provider.answer = (head) {
          final path = head.split(' ')[1];
          final [z, x, y] = path
              .substring(1, path.length - 4)
              .split('/')
              .map(int.parse)
              .toList();
          return _ok(padded(MapTile.of(z, x, y) ?? tile));
        };
        expect(OsmMapTileAdapter.maxKeptBytes, 16 * 1024 * 1024);
        final session = provider.adapter().open();
        // Forty tiles of 400 KiB fit; the forty-first puts the first out.
        final kept = [
          for (var x = 0; x <= 40; x++) MapTile.of(13, x, 2) ?? tile,
        ];
        for (final one in kept) {
          expect(await session.fetch(one), isA<MapTileImage>());
        }
        expect(provider.heads, hasLength(41));
        for (final one in kept.skip(1)) {
          await session.fetch(one);
        }
        expect(provider.heads, hasLength(41));
        await session.fetch(kept.first);
        expect(provider.heads, hasLength(42));
        session.close();
      },
    );

    test('« Too Many Requests » is a refusal, as x-blocked', () async {
      provider.answer = (head) => _status(429, 'Too Many Requests');
      final session = provider.adapter().open();
      expect(await session.fetch(tile), isA<MapTileRefused>());
      session.close();
    });

    test('a tile given up while it waits its turn is never sent', () async {
      final release = Completer<void>();
      provider.answer = (head) async {
        await release.future;
        return _ok(testTilePng(tile));
      };
      final session = provider.adapter().open();
      final running = [
        for (var x = 0; x < 6; x++) session.fetch(MapTile.of(13, x, 0) ?? tile),
      ];
      final waiting = [
        for (var x = 6; x < 8; x++) MapTile.of(13, x, 0) ?? tile,
      ];
      final dropped = [for (final other in waiting) session.fetch(other)];
      await _until(() => provider.running == 6);
      for (final other in waiting) {
        session.drop(other);
      }
      expect(await Future.wait(dropped), everyElement(isA<MapTileDropped>()));
      release.complete();
      await Future.wait(running);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.heads, hasLength(6));
      for (final head in provider.heads) {
        expect(head, isNot(contains('/13/6/0.png')));
        expect(head, isNot(contains('/13/7/0.png')));
      }
      session.close();
    });

    test(
      'a session keeps at most 256 tiles, the least recently used forgotten first',
      () async {
        final session = provider.adapter().open();
        final kept = [
          for (var x = 0; x <= OsmMapTileAdapter.maxKept; x++)
            MapTile.of(13, x, 1) ?? tile,
        ];
        for (final one in kept) {
          expect(await session.fetch(one), isA<MapTileImage>());
        }
        expect(provider.heads, hasLength(OsmMapTileAdapter.maxKept + 1));
        // The last 256 are kept: asked again, they are not sent again.
        for (final one in kept.skip(1)) {
          await session.fetch(one);
        }
        expect(provider.heads, hasLength(OsmMapTileAdapter.maxKept + 1));
        // The first was forgotten: asked again, it is sent again.
        await session.fetch(kept.first);
        expect(provider.heads, hasLength(OsmMapTileAdapter.maxKept + 2));
        session.close();
      },
    );

    test('an answer larger than the bound is no tile, said or not', () async {
      final big = Uint8List(OsmMapTileAdapter.maxBytes + 1);
      big.setAll(0, testTilePng(tile).take(64));
      provider.answer = (head) => _ok(big);
      final session = provider.adapter().open();
      expect(await session.fetch(tile), isA<MapTileFailed>());
      // Without a length, the bytes are counted as they come.
      provider.answer = (head) => _ok(big, length: false);
      final other = MapTile.of(13, 4232, 2873);
      if (other == null) fail('no tile');
      expect(await session.fetch(other), isA<MapTileFailed>());
      session.close();
    });

    test('only a PNG of 256 × 256 pixels is a tile', () async {
      provider.answer = (head) => _ok(testTilePng(tile, side: 512));
      final session = provider.adapter().open();
      expect(await session.fetch(tile), isA<MapTileFailed>());
      provider.answer = (head) => _ok(utf8.encode('<html>blocked</html>'));
      final other = MapTile.of(13, 4232, 2873);
      if (other == null) fail('no tile');
      expect(await session.fetch(other), isA<MapTileFailed>());
      session.close();
    });

    test('at most six requests at once, the others waiting', () async {
      final release = Completer<void>();
      provider.answer = (head) async {
        await release.future;
        return _ok(testTilePng(tile));
      };
      final session = provider.adapter().open();
      final outcomes = [
        for (var x = 0; x < 10; x++)
          session.fetch(MapTile.of(13, x, 0) ?? tile),
      ];
      await _until(() => provider.running == 6);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.running, 6);
      expect(provider.heads, hasLength(6));
      release.complete();
      expect(
        (await Future.wait(outcomes)).whereType<MapTileImage>(),
        hasLength(10),
      );
      expect(provider.mostRunning, OsmMapTileAdapter.maxRequests);
      expect(OsmMapTileAdapter.maxRequests, 6);
      session.close();
    });

    test(
      'a provider that does not answer is given up after the wait',
      () async {
        provider.answer = (head) => Completer<List<int>>().future;
        final session = provider
            .adapter(readTimeout: const Duration(milliseconds: 300))
            .open();
        final watch = Stopwatch()..start();
        expect(await session.fetch(tile), isA<MapTileFailed>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        session.close();
      },
    );

    test(
      'an answer that comes a byte now and then is given up after the tile\'s time',
      () async {
        provider.dribble = (head) async* {
          yield latin1.encode(
            'HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nConnection: close\r\n\r\n',
          );
          for (var i = 0; i < 100; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            yield const [0];
          }
        };
        final session = provider
            .adapter(
              readTimeout: const Duration(milliseconds: 300),
              tileTimeout: const Duration(milliseconds: 500),
            )
            .open();
        final watch = Stopwatch()..start();
        expect(await session.fetch(tile), isA<MapTileFailed>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
        expect(OsmMapTileAdapter.tileTimeout, const Duration(seconds: 30));
        session.close();
      },
    );

    test(
      'a connection that does not come is given up after its wait',
      () async {
        final session = OsmMapTileAdapter(
          createClient: () =>
              OsmMapTileAdapter.newClient()
                ..connectionFactory = (uri, host, port) =>
                    Completer<ConnectionTask<Socket>>().future,
          connectTimeout: const Duration(milliseconds: 300),
        ).open();
        expect(await session.fetch(tile), isA<MapTileFailed>());
        session.close();
      },
    );

    test('the bounds of the client are these', () {
      expect(OsmMapTileAdapter.connectTimeout, const Duration(seconds: 10));
      expect(OsmMapTileAdapter.readTimeout, const Duration(seconds: 15));
      expect(OsmMapTileAdapter.maxBytes, 512 * 1024);
      expect(OsmMapTileAdapter.maxKept, 256);
      final client = OsmMapTileAdapter.newClient();
      expect(client.userAgent, 'TumbleLark');
      expect(client.autoUncompress, isFalse);
      expect(client.connectionTimeout, OsmMapTileAdapter.connectTimeout);
      expect(client.maxConnectionsPerHost, OsmMapTileAdapter.maxRequests);
      client.close(force: true);
    });

    test(
      'a tile that left the view is given up, its connection closed',
      () async {
        final release = Completer<void>();
        provider.answer = (head) async {
          await release.future;
          return _ok(testTilePng(tile));
        };
        final session = provider.adapter().open();
        final outcome = session.fetch(tile);
        await _until(() => provider.running == 1);
        session.drop(tile);
        expect(await outcome, isA<MapTileDropped>());
        await _until(() => provider.closedEarly == 1);
        release.complete();
        session.close();
      },
    );

    test(
      'closing forgets every tile and closes the client; nothing is asked after it',
      () async {
        final session = provider.adapter().open();
        expect(await session.fetch(tile), isA<MapTileImage>());
        session.close();
        expect(await session.fetch(tile), isA<MapTileDropped>());
        expect(provider.heads, hasLength(1));
        // A new session asks again: nothing was kept beyond the one closed.
        final next = provider.adapter().open();
        expect(await next.fetch(tile), isA<MapTileImage>());
        expect(provider.heads, hasLength(2));
        next.close();
      },
    );

    test('nothing of a tile is written to a file', () async {
      final touched = <String>[];
      await IOOverrides.runZoned(
        () async {
          final session = provider.adapter().open();
          expect(await session.fetch(tile), isA<MapTileImage>());
          provider.answer = (head) => _status(500, 'Error');
          final other = MapTile.of(13, 4232, 2873);
          if (other == null) fail('no tile');
          expect(await session.fetch(other), isA<MapTileFailed>());
          session.close();
        },
        createFile: (path) {
          touched.add(path);
          return _NoFile(path);
        },
      );
      expect(touched, isEmpty);
    });

    test(
      'a log line says only a fixed label: never the address, the zoom, the column or the row',
      () async {
        final printed = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        try {
          final session = provider.adapter().open();
          provider.answer = (head) => _status(500, 'Error');
          expect(await session.fetch(tile), isA<MapTileFailed>());
          provider.answer = (head) =>
              _ok(testTilePng(tile), headers: {'x-blocked': 'yes'});
          final other = MapTile.of(13, 4232, 2874);
          if (other == null) fail('no tile');
          expect(await session.fetch(other), isA<MapTileRefused>());
          // A connection refused: its exception names the address, and is not logged.
          final refused = OsmMapTileAdapter(
            createClient: () =>
                OsmMapTileAdapter.newClient()
                  ..connectionFactory = (uri, host, port) =>
                      Future.error(SocketException('refused ${uri.path}')),
          ).open();
          expect(await refused.fetch(tile), isA<MapTileFailed>());
          session.close();
          refused.close();
        } finally {
          debugPrint = original;
        }
        final all = printed.join('\n');
        expect(all, contains('P2P map tile: failed'));
        expect(all, contains('P2P map tile: refused'));
        for (final secret in const [
          'openstreetmap',
          '4231',
          '4232',
          '2873',
          '2874',
          '.png',
          'refused /',
        ]) {
          expect(all, isNot(contains(secret)), reason: secret);
        }
      },
    );
  });
}

/// Waits, on real time, until [done] holds.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

/// The headers of a request's head, by lower-case name.
Map<String, List<String>> _headersOf(String head) {
  final headers = <String, List<String>>{};
  for (final line in head.split('\r\n').skip(1)) {
    final colon = line.indexOf(':');
    (headers[line.substring(0, colon).toLowerCase()] ??= []).add(
      line.substring(colon + 1).trim(),
    );
  }
  return headers;
}

List<int> _ok(
  List<int> body, {
  Map<String, String> headers = const {},
  bool length = true,
}) => [
  ...latin1.encode(
    [
      'HTTP/1.1 200 OK',
      'Content-Type: image/png',
      if (length) 'Content-Length: ${body.length}',
      'Connection: close',
      for (final MapEntry(:key, :value) in headers.entries) '$key: $value',
      '',
      '',
    ].join('\r\n'),
  ),
  ...body,
];

List<int> _status(
  int status,
  String reason, {
  Map<String, String> headers = const {},
}) => latin1.encode(
  [
    'HTTP/1.1 $status $reason',
    'Content-Length: 0',
    'Connection: close',
    for (final MapEntry(:key, :value) in headers.entries) '$key: $value',
    '',
    '',
  ].join('\r\n'),
);

/// The tile provider of the test, on the loopback: it reads each request's head as it comes on the wire and answers what the test says, a tile made by the test by default; the client reaches it through its connection factory, its requests still written for `https://tile.openstreetmap.org`.
final class _Provider {
  final ServerSocket _server;
  final heads = <String>[];
  final targets = <Uri>[];
  var clients = 0;
  var running = 0;
  var mostRunning = 0;

  /// Connections the client closed before their answer was written.
  var closedEarly = 0;
  late FutureOr<List<int>> Function(String head) answer;

  /// An answer written bit by bit, in place of [answer], when set.
  Stream<List<int>> Function(String head)? dribble;

  _Provider._(this._server) {
    answer = (head) {
      final path = head.split(' ')[1];
      final [z, x, y] = path
          .substring(1, path.length - 4)
          .split('/')
          .map(int.parse)
          .toList();
      return switch (MapTile.of(z, x, y)) {
        final tile? => _ok(testTilePng(tile)),
        null => _status(400, 'Bad Request'),
      };
    };
    _server.listen(_serve);
  }

  int get port => _server.port;

  static Future<_Provider> start() async =>
      _Provider._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> stop() => _server.close();

  /// The proxy each connection was asked to go through, `null` for a direct one.
  final proxies = <String?>[];

  /// Connections ended, by the client or by the provider, and connections accepted.
  var ended = 0;
  var accepted = 0;

  OsmMapTileAdapter adapter({
    Duration readTimeout = const Duration(seconds: 5),
    Duration tileTimeout = const Duration(seconds: 30),
    DateTime Function()? clock,
    int? connections,
  }) => OsmMapTileAdapter(
    createClient: () {
      clients++;
      final client = OsmMapTileAdapter.newClient()
        ..connectionFactory = (uri, host, port) {
          targets.add(uri);
          proxies.add(host);
          return Socket.startConnect(InternetAddress.loopbackIPv4, this.port);
        };
      if (connections != null) client.maxConnectionsPerHost = connections;
      return client;
    },
    readTimeout: readTimeout,
    tileTimeout: tileTimeout,
    clock: clock ?? DateTime.now,
  );

  void _serve(Socket socket) {
    accepted++;
    final received = BytesBuilder();
    var answered = false;
    var written = false;
    var closed = false;
    void ended() {
      if (closed) return;
      closed = true;
      this.ended++;
      if (answered && !written) closedEarly++;
    }

    socket.listen(
      (data) async {
        received.add(data);
        final text = latin1.decode(received.toBytes());
        final end = text.indexOf('\r\n\r\n');
        if (end < 0 || answered) return;
        answered = true;
        heads.add(text.substring(0, end));
        running++;
        mostRunning = math.max(mostRunning, running);
        try {
          final dribble = this.dribble;
          if (dribble != null) {
            written = true;
            await for (final bytes in dribble(text.substring(0, end))) {
              if (closed) return;
              socket.add(bytes);
              await socket.flush();
            }
            await socket.close();
            return;
          }
          final reply = await answer(text.substring(0, end));
          if (closed) return;
          written = true;
          socket.add(reply);
          await socket.flush();
          await socket.close();
        } on SocketException {
          // The client went away while the answer was written.
        } finally {
          running--;
        }
      },
      onDone: ended,
      onError: (Object _) => ended(),
      cancelOnError: true,
    );
  }
}

/// A file that refuses everything, for the overrides that watch for one.
final class _NoFile implements File {
  @override
  final String path;

  _NoFile(this.path);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('a file was used: $path');
}
