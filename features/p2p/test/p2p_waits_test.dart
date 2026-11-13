import 'dart:async';

import 'package:bull_tor/tor.dart' show TorHttpClientFactory;
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:p2p/src/domain/p2p_waits.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// The waits of the book as the app and the test seam register them.
void main() {
  late GetIt locator;

  setUp(() => locator = GetIt.asNewInstance());
  tearDown(() => locator.reset());

  test('the app: real timers, and a random spread of each wait', () async {
    const P2pFeature().setup(
      locator,
      garageKeys: null,
      databaseDirectory: null,
    );
    final waits = locator<P2pWaits>();

    final draws = [for (var i = 0; i < 10; i++) waits.random()];
    expect(draws.every((draw) => draw >= 0 && draw < 1), isTrue);
    expect(draws.toSet().length, greaterThan(1));

    final fired = Completer<void>();
    final timer = waits.start(Duration.zero, fired.complete);
    expect(timer.isActive, isTrue);
    await fired.future.timeout(const Duration(seconds: 1));

    final cancelled = waits.start(const Duration(milliseconds: 10), () {
      fail('a cancelled timer fired');
    });
    cancelled.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test(
    'each book gets a use case of its own, and all share the requests in flight',
    () {
      // Resolving the use case builds the transport, which takes the factory of Tor's HTTP clients at once and Tor itself only at its first request.
      locator.registerSingleton<TorHttpClientFactory>(
        const TorHttpClientFactory(),
      );
      const P2pFeature().setup(
        locator,
        garageKeys: null,
        databaseDirectory: null,
      );

      expect(
        identical(
          locator<LoadFederationBooksUsecase>(),
          locator<LoadFederationBooksUsecase>(),
        ),
        isFalse,
      );
      // And every book shares the requests in flight.
      expect(
        identical(
          locator<BookRequestsInFlight>(),
          locator<BookRequestsInFlight>(),
        ),
        isTrue,
      );
    },
  );

  test('the test seam: the timers of the zone, and no spread', () async {
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(),
      torStates: () => const Stream.empty(),
      clock: () => testNow,
    );
    final waits = locator<P2pWaits>();

    expect([for (var i = 0; i < 3; i++) waits.random()], [0.5, 0.5, 0.5]);
    final fired = Completer<void>();
    waits.start(Duration.zero, fired.complete);
    await fired.future.timeout(const Duration(seconds: 1));
  });
}
