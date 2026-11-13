import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/domain/order_search.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/retry_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/start_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'package:p2p/src/presentation/book_cubit.dart';
import 'package:p2p/src/presentation/book_state.dart';
import 'package:robosats/robosats.dart';

import 'support/book_attempts.dart';
import 'support/fakes.dart';

void main() {
  late FakeTor tor;
  late FakeTransport transport;
  late FakeWaits waits;

  /// The book requests in flight, which every book of a test shares, as the books of the app share the locator's.
  late BookRequestsInFlight inFlight;

  /// The book over [transport], or over [scripted] when given.
  BookCubit cubit({
    RobosatsNetwork network = RobosatsNetwork.mainnet,
    ScriptedTransport? scripted,
  }) => BookCubit(
    network,
    WatchP2pTorStateUsecase(() => tor),
    StartP2pTorUsecase(() => tor),
    RetryP2pTorUsecase(() => tor),
    LoadFederationBooksUsecase(
      RequestFederationBooksUsecase(
        FederationBookReader(scripted ?? transport, clock: () => testNow),
        Federation.robosats,
      ),
      inFlight,
      waits.waits,
    ),
  );

  /// Lets the stream events and the request futures run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// One book request per mainnet coordinator of the embedded list, whose count `packages/robosats/test/coordinator/embedded_data_test.dart` pins.
  final mainnetCoordinators = Federation.robosats
      .on(RobosatsNetwork.mainnet)
      .length;

  setUp(() {
    tor = FakeTor();
    transport = FakeTransport();
    waits = FakeWaits();
    inFlight = BookRequestsInFlight();
  });

  group('Tor', () {
    test('starts Tor and requests nothing before it is ready', () async {
      final book = cubit()..start();
      await settle();
      tor.embedded
        ..notStarted()
        ..connecting();
      await settle();

      expect(tor.embedded.starts, 1);
      expect(book.state.tor, TorWait.connecting);
      expect(transport.requested, isEmpty);
      await book.close();
    });

    test('cold start: the books are requested once Tor is ready', () async {
      final book = cubit()..start();
      tor.embedded.notStarted();
      await settle();
      expect(book.state.tor, TorWait.initializing);

      tor.embedded.connecting();
      await settle();
      expect(transport.requested, isEmpty);

      tor.embedded.ready();
      await settle();
      expect(book.state.tor, TorWait.ready);
      expect(
        transport.requested,
        unorderedEquals([
          for (final coordinator in Federation.robosats.on(
            RobosatsNetwork.mainnet,
          ))
            '${coordinator.shortAlias}/api/book/',
        ]),
      );
      await book.close();
    });

    test('Tor already ready: the books are requested at once', () async {
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();

      expect(book.state.tor, TorWait.ready);
      expect(transport.requested, hasLength(mainnetCoordinators));
      await book.close();
    });

    test('the start-up flicker does not go back to « initializing »', () async {
      final book = cubit()..start();
      final steps = <TorWait>[];
      final subscription = book.stream.listen((s) => steps.add(s.tor));
      tor.embedded
        ..notStarted()
        ..connecting()
        ..stopped()
        ..connecting();
      await settle();

      expect(steps.toSet(), {TorWait.connecting});
      expect(book.state.tor, TorWait.connecting);
      await subscription.cancel();
      await book.close();
    });

    test('once ready, a later « connecting » keeps the book', () async {
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();
      tor.embedded
        ..connecting()
        ..stopped()
        ..failed();
      await settle();

      expect(book.state.tor, TorWait.ready);
      expect(transport.requested, hasLength(mainnetCoordinators));
      await book.close();
    });

    test(
      'the share of the start shows in whole percent while Tor connects',
      () async {
        final book = cubit()..start();
        tor.embedded.notStarted();
        await settle();
        expect(book.state.torPercent, isNull);

        tor.embedded.connecting();
        await settle();
        expect(
          (book.state.tor, book.state.torPercent),
          (TorWait.connecting, null),
        );

        tor.embedded.connecting(0);
        await settle();
        expect(book.state.torPercent, 0);

        tor.embedded.connecting(0.429);
        await settle();
        expect(book.state.torPercent, 42);

        // Arti's share dips while it fetches the directory: the percentage stays.
        tor.embedded.connecting(0.3);
        await settle();
        expect(book.state.torPercent, 42);

        // A full share before ready, while `bull_tor` holds readiness.
        tor.embedded.connecting(1);
        await settle();
        expect(
          (book.state.tor, book.state.torPercent),
          (TorWait.connecting, 99),
        );
        expect(transport.requested, isEmpty);

        tor.embedded.ready();
        await settle();
        expect((book.state.tor, book.state.torPercent), (TorWait.ready, null));
        expect(transport.requested, hasLength(mainnetCoordinators));

        // A directory refresh after ready asks nothing again and shows no percentage.
        tor.embedded
          ..connecting(0.5)
          ..connecting(1)
          ..ready();
        await settle();
        expect((book.state.tor, book.state.torPercent), (TorWait.ready, null));
        expect(transport.requested, hasLength(mainnetCoordinators));
        await book.close();
      },
    );

    test('a new attempt starts the percentage over', () async {
      final book = cubit()..start();
      final shown = <(TorWait, int?)>[];
      final subscription = book.stream.listen(
        (s) => shown.add((s.tor, s.torPercent)),
      );
      tor.embedded
        ..connecting(0.45)
        ..connecting()
        ..stopped()
        ..connecting(0)
        ..connecting(0.2);
      await settle();

      expect(shown, [
        (TorWait.connecting, 45),
        (TorWait.connecting, null),
        (TorWait.connecting, 0),
        (TorWait.connecting, 20),
      ]);
      await subscription.cancel();
      await book.close();
    });

    test('a report that changes nothing shown emits nothing', () async {
      final book = cubit()..start();
      final shown = <(TorWait, int?)>[];
      final subscription = book.stream.listen(
        (s) => shown.add((s.tor, s.torPercent)),
      );
      tor.embedded
        ..connecting(0.421)
        ..connecting(0.425)
        ..connecting(0.4);
      await settle();

      expect(shown, [(TorWait.connecting, 42)]);
      await subscription.cancel();
      await book.close();
    });

    test('a failure and Retry show no percentage', () async {
      final book = cubit()..start();
      tor.embedded.connecting(0.4);
      await settle();
      expect(book.state.torPercent, 40);

      tor.embedded.failed();
      await settle();
      expect((book.state.tor, book.state.torPercent), (TorWait.failed, null));

      book.retryTor();
      await settle();
      expect(
        (book.state.tor, book.state.torPercent),
        (TorWait.initializing, null),
      );

      tor.embedded
        ..connecting()
        ..stopped()
        ..connecting(0.1);
      await settle();
      expect((book.state.tor, book.state.torPercent), (TorWait.connecting, 10));
      await book.close();
    });

    test('a failed start shows the error, and retry restarts Tor', () async {
      final book = cubit()..start();
      tor.embedded
        ..connecting()
        ..failed();
      await settle();
      expect(book.state.tor, TorWait.failed);

      book.retryTor();
      await settle();
      expect(tor.embedded.retries, 1);
      expect(book.state.tor, TorWait.initializing);

      tor.embedded
        ..connecting()
        ..ready();
      await settle();
      expect(book.state.tor, TorWait.ready);
      await book.close();
    });
  });

  group('lifecycle', () {
    test('closing while a book is pending drops its answer', () async {
      transport = FakeTransport(
        books: {
          'temple': [bookOrder(id: 1)],
        },
        held: {'temple'},
      );
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();
      expect(book.state.loadingCoordinators, contains(coordinator('temple')));

      await book.close();
      transport.release('temple');
      await settle();
      await settle();

      // An answer handled after `close` would throw from `emit` and fail the test zone.
      expect(book.isClosed, isTrue);
    });

    test('closing stops following Tor', () async {
      final book = cubit()..start();
      await settle();
      await book.close();

      tor.embedded.ready();
      await settle();
      await settle();

      expect(transport.requested, isEmpty);
    });

    test('retryTor does nothing unless Tor failed', () async {
      final book = cubit()..start();
      book.retryTor();
      tor.embedded.connecting();
      await settle();
      book.retryTor();
      await settle();

      expect(tor.embedded.retries, 0);
      expect(book.state.tor, TorWait.connecting);

      tor.embedded.ready();
      await settle();
      book.retryTor();
      await settle();
      expect(tor.embedded.retries, 0);
      expect(book.state.tor, TorWait.ready);
      await book.close();
    });
  });

  group('books', () {
    test(
      'each book shows as it arrives, without waiting for the others',
      () async {
        transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: 1)],
            'lake': [bookOrder(id: 2, makerSeed: 2)],
          },
          held: {'lake'},
        );
        final book = cubit()..start();
        tor.embedded.ready();
        await settle();
        await settle();

        expect(book.state.orders.map((o) => o.id), [1]);
        expect(book.state.loadingCoordinators.map((c) => c.shortAlias), [
          'lake',
        ]);
        expect(book.state.isWaitingForFirstBook, isFalse);

        transport.release('lake');
        await settle();
        await settle();
        expect(book.state.orders.map((o) => o.id), unorderedEquals([1, 2]));
        expect(book.state.loadingCoordinators, isEmpty);
        await book.close();
      },
    );

    test(
      'the orders follow the federation order, whatever the arrival order',
      () async {
        transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: 10)],
            'lake': [bookOrder(id: 20, makerSeed: 2)],
          },
          held: {'temple'},
        );
        final book = cubit()..start();
        tor.embedded.ready();
        await settle();
        await settle();
        expect(book.state.orders.map((o) => o.id), [20]);

        transport.release('temple');
        await settle();
        await settle();
        // temple comes before lake in the federation list.
        expect(book.state.orders.map((o) => o.id), [10, 20]);
        await book.close();
      },
    );

    test(
      'a coordinator that gets no answer stays awaited while it is asked again, then shows offline, and hides no other',
      () async {
        transport = FakeTransport(
          books: {
            'lake': [bookOrder(id: 2)],
          },
          failures: {'temple': const CoordinatorUnreachable()},
        );
        final book = cubit()..start();
        tor.embedded.ready();
        await settle();
        await settle();

        // Asked again after 5 seconds: still awaited, the others shown.
        expect(book.state.loadingCoordinators.map((c) => c.shortAlias), [
          'temple',
        ]);
        expect(book.state.failedCoordinators, isEmpty);
        expect(book.state.orders.map((o) => o.id), [2]);
        expect(waits.pending.single.duration, const Duration(seconds: 5));

        waits.fireAll();
        await settle();
        expect(book.state.loadingCoordinators.map((c) => c.shortAlias), [
          'temple',
        ]);
        expect(waits.pending.single.duration, const Duration(seconds: 15));

        waits.fireAll();
        await settle();
        expect(book.state.loadingCoordinators, isEmpty);
        expect(book.state.failedCoordinators.map((c) => c.shortAlias), [
          'temple',
        ]);
        expect(
          book.state.coordinators[coordinator('temple')],
          isA<CoordinatorBookFailed>().having(
            (s) => s.failure,
            'failure',
            isA<CoordinatorUnreachable>(),
          ),
        );
        expect(
          transport.requested.where((r) => r == 'temple/api/book/'),
          hasLength(3),
        );
        expect(book.state.orders.map((o) => o.id), [2]);
        expect(book.state.answeredCount, mainnetCoordinators - 1);
        await book.close();
      },
    );

    test('retry asks again only the coordinators offline', () async {
      transport = FakeTransport(
        books: {
          'temple': [bookOrder(id: 1)],
          'lake': [bookOrder(id: 2, makerSeed: 2)],
        },
        failures: {'temple': const CoordinatorTimedOut()},
      );
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();
      waits.fireAll();
      await settle();
      waits.fireAll();
      await settle();
      expect(book.state.failedCoordinators, [coordinator('temple')]);
      transport.requested.clear();
      transport.failures.clear();

      await book.retryFailed();

      expect(transport.requested, ['temple/api/book/']);
      expect(book.state.failedCoordinators, isEmpty);
      expect(book.state.orders.map((o) => o.id), unorderedEquals([1, 2]));
      await book.close();
    });

    test(
      'refresh asks everyone again and keeps the orders meanwhile',
      () async {
        transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: 1)],
          },
        );
        final book = cubit()..start();
        tor.embedded.ready();
        await settle();
        await settle();
        transport
          ..requested.clear()
          ..held.add('temple');

        final refreshed = book.refresh();
        await settle();
        expect(transport.requested, hasLength(mainnetCoordinators));
        expect(book.state.loadingCoordinators, contains(coordinator('temple')));
        expect(book.state.orders.map((o) => o.id), [1]);

        transport.books['temple'] = [bookOrder(id: 3)];
        transport.release('temple');
        await refreshed;
        expect(book.state.orders.map((o) => o.id), [3]);
        await book.close();
      },
    );

    test(
      'a refresh sends no second request to a coordinator still in flight: it waits for that one',
      () async {
        transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: 1)],
          },
          held: {'temple'},
        );
        final book = cubit()..start();
        tor.embedded.ready();
        await settle();
        transport.requested.clear();

        final refreshed = book.refresh();
        await settle();
        expect(transport.requested, hasLength(mainnetCoordinators - 1));
        expect(transport.requested, isNot(contains('temple/api/book/')));
        expect(book.state.loadingCoordinators, [coordinator('temple')]);

        transport.release('temple');
        await refreshed;
        expect(book.state.orders.map((o) => o.id), [1]);
        expect(book.state.loadingCoordinators, isEmpty);
        await book.close();
      },
    );

    test('testnet asks the testnet instances', () async {
      transport = FakeTransport(network: RobosatsNetwork.testnet);
      final book = cubit(network: RobosatsNetwork.testnet)..start();
      tor.embedded.ready();
      await settle();
      await settle();

      expect(
        transport.requested,
        unorderedEquals(['temple/api/book/', 'lake/api/book/']),
      );
      expect(book.state.isWaitingForFirstBook, isFalse);
      expect(book.state.orders, isEmpty);
      await book.close();
    });
  });

  group('asking again by itself', () {
    late ScriptedTransport scripted;

    setUp(() {
      scripted = ScriptedTransport(
        books: {
          'temple': [bookOrder(id: 1)],
          'lake': [bookOrder(id: 2, makerSeed: 2)],
        },
      );
    });

    Future<BookCubit> shown() async {
      final book = cubit(scripted: scripted)..start();
      tor.embedded.ready();
      await settle();
      await settle();
      return book;
    }

    test('a book on the second attempt lights the coordinator', () async {
      scripted.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
      ];
      final book = await shown();
      expect(book.state.loadingCoordinators, [coordinator('temple')]);
      expect(book.state.orders.map((o) => o.id), [2]);

      waits.fireAll();
      await settle();
      expect(book.state.loadingCoordinators, isEmpty);
      expect(book.state.failedCoordinators, isEmpty);
      expect(book.state.orders.map((o) => o.id), [1, 2]);
      expect(scripted.requestsTo('temple'), 2);
      await book.close();
    });

    test('leaving the tab ends the wait, and nothing more is sent', () async {
      scripted.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
      ];
      final book = await shown();
      final wait = waits.pending.single;

      await book.close();
      expect(wait.cancelled, isTrue);
      wait.fire();
      await settle();
      expect(scripted.requestsTo('temple'), 1);
    });

    test(
      'Tor failing under the book shows offline at once a coordinator waiting to be asked again, and asks none again',
      () async {
        scripted
          ..script['temple'] = const [ScriptedFailure(CoordinatorUnreachable())]
          ..script['lake'] = const [ScriptedFailure(CoordinatorTimedOut())]
          ..held.add('lake');
        final book = await shown();
        final wait = waits.pending.single;
        expect(book.state.loadingCoordinators, [
          coordinator('temple'),
          coordinator('lake'),
        ]);

        tor.embedded.failed();
        await settle();
        expect(wait.cancelled, isTrue);
        expect(book.state.tor, TorWait.ready);
        expect(book.state.failedCoordinators, [coordinator('temple')]);
        expect(book.state.loadingCoordinators, [coordinator('lake')]);

        // The request in flight gives the last failure: no wait is started.
        scripted.release('lake');
        await settle();
        expect(book.state.failedCoordinators, [
          coordinator('temple'),
          coordinator('lake'),
        ]);
        expect(waits.started, hasLength(1));
        expect(scripted.requestsTo('temple'), 1);
        expect(scripted.requestsTo('lake'), 1);
        await book.close();
      },
    );

    test(
      'a refresh ends the wait and asks at once, with all the attempts again',
      () async {
        scripted.script['temple'] = [
          for (var i = 0; i < 6; i++)
            const ScriptedFailure(CoordinatorUnreachable()),
        ];
        final book = await shown();
        waits.fireAll();
        await settle();
        final second = waits.pending.single;
        expect(second.duration, const Duration(seconds: 15));
        expect(scripted.requestsTo('temple'), 2);

        final refreshed = book.refresh();
        await settle();
        expect(second.cancelled, isTrue);
        expect(scripted.requestsTo('temple'), 3);
        // Not reached yet: the attempts of a first contact again, from the first wait.
        expect(waits.pending.single.duration, const Duration(seconds: 5));
        expect(book.state.loadingCoordinators, [coordinator('temple')]);

        waits.fireAll();
        await settle();
        waits.fireAll();
        await refreshed;
        expect(scripted.requestsTo('temple'), 5);
        expect(book.state.failedCoordinators, [coordinator('temple')]);
        expect(scripted.mostAtOnce['temple'], 1);
        await book.close();
      },
    );

    test(
      'an outcome a newer request overtook before the book handled it is dropped',
      () async {
        scripted.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
        ];
        final book = await shown();
        expect(waits.pending, hasLength(1));
        scripted.held.add('temple');

        // Tor fails under the book: temple's attempts end at once with their failure, and a refresh asks it again before the book has handled that outcome.
        tor.embedded.failed();
        late Future<void> refreshed;
        scheduleMicrotask(() => refreshed = book.refresh());
        await settle();

        expect(scripted.requestsTo('temple'), 2);
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        expect(book.state.failedCoordinators, isEmpty);

        scripted.release('temple');
        await refreshed;
        expect(book.state.loadingCoordinators, isEmpty);
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        await book.close();
      },
    );

    test('Retry gives the offline ones all their attempts again', () async {
      scripted.script['temple'] = [
        for (var i = 0; i < 4; i++)
          const ScriptedFailure(CoordinatorUnreachable()),
      ];
      final book = await shown();
      waits.fireAll();
      await settle();
      waits.fireAll();
      await settle();
      expect(book.state.failedCoordinators, [coordinator('temple')]);
      scripted.requested.clear();

      final retried = book.retryFailed();
      await settle();
      expect(scripted.requested, ['temple/api/book/']);
      expect(book.state.loadingCoordinators, [coordinator('temple')]);
      expect(waits.pending.single.duration, const Duration(seconds: 5));

      waits.fireAll();
      await retried;
      expect(book.state.failedCoordinators, isEmpty);
      expect(book.state.orders.map((o) => o.id), [1, 2]);
      await book.close();
    });

    test(
      'a coordinator that answered before is asked again once, after 5 seconds, on a refresh',
      () async {
        final book = await shown();
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        scripted.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
          ScriptedFailure(CoordinatorUnreachable()),
        ];

        final refreshed = book.refresh();
        await settle();
        // Its orders stay on screen while it is asked again.
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        expect(waits.pending.single.duration, const Duration(seconds: 5));

        waits.fireAll();
        await refreshed;
        expect(waits.started, hasLength(1));
        expect(book.state.failedCoordinators, [coordinator('temple')]);
        expect(book.state.orders.map((o) => o.id), [2]);
        await book.close();
      },
    );
  });

  group('how long the user waits', () {
    late ScriptedTransport scripted;

    setUp(() {
      scripted = ScriptedTransport(
        books: {
          'temple': [bookOrder(id: 1)],
          'lake': [bookOrder(id: 2, makerSeed: 2)],
        },
      );
    });

    Future<BookCubit> shown() async {
      final book = cubit(scripted: scripted)..start();
      tor.embedded.ready();
      await settle();
      await settle();
      return book;
    }

    /// Whether [future] has completed after the fake transport and the book have run.
    Future<bool> isDone(Future<void> future) async {
      var done = false;
      future.then((_) => done = true).ignore();
      await settle();
      await settle();
      return done;
    }

    test(
      'still no answer 80 seconds after its load began: shown offline, its request going on; a late answer lights it',
      () async {
        scripted.held.add('temple');
        final book = await shown();
        expect(book.state.loadingCoordinators, [coordinator('temple')]);

        waits.fireAwaitedBounds();
        await settle();
        expect(
          book.state.coordinators[coordinator('temple')],
          isA<CoordinatorBookFailed>().having(
            (s) => s.failure,
            'failure',
            isA<CoordinatorTimedOut>(),
          ),
        );
        expect(book.state.loadingCoordinators, isEmpty);
        expect(book.state.orders.map((o) => o.id), [2]);

        scripted.release('temple');
        await settle();
        expect(book.state.failedCoordinators, isEmpty);
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        expect(book.state.answeredCount, mainnetCoordinators);
        expect(scripted.requestsTo('temple'), 1);
        await book.close();
      },
    );

    test(
      '« Retry » on it sends nothing while its request is in flight, and shows it awaited for a new 80 seconds',
      () async {
        scripted.held.add('temple');
        final book = await shown();
        waits.fireAwaitedBounds();
        await settle();
        expect(book.state.failedCoordinators, [coordinator('temple')]);

        final retried = book.retryFailed();
        await settle();
        expect(scripted.requestsTo('temple'), 1);
        expect(scripted.mostAtOnce['temple'], 1);
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        expect(waits.awaitedBounds, hasLength(1));

        waits.fireAwaitedBounds();
        await settle();
        expect(book.state.failedCoordinators, [coordinator('temple')]);
        expect(await isDone(retried), isTrue);

        scripted.release('temple');
        await settle();
        expect(book.state.failedCoordinators, isEmpty);
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        expect(scripted.requestsTo('temple'), 1);
        await book.close();
      },
    );

    test(
      'an overdue a newer request overtook before the book handled it is dropped',
      () async {
        scripted.held.add('temple');
        final book = await shown();

        // The 80 seconds pass, and a refresh asks temple again before the book has shown it offline.
        waits.fireAwaitedBounds();
        final refreshed = book.refresh();
        await settle();
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        expect(book.state.failedCoordinators, isEmpty);
        expect(waits.awaitedBounds, hasLength(1));

        scripted.release('temple');
        await refreshed;
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        await book.close();
      },
    );

    test('the bound starts again on a refresh', () async {
      scripted.held.add('temple');
      final book = await shown();
      final first = waits.awaitedBounds.single;

      final refreshed = book.refresh();
      await settle();
      expect(first.cancelled, isTrue);
      final second = waits.awaitedBounds.single;
      expect(identical(first, second), isFalse);
      expect(book.state.loadingCoordinators, [coordinator('temple')]);
      expect(scripted.requestsTo('temple'), 1);

      second.fire();
      await settle();
      expect(book.state.failedCoordinators, [coordinator('temple')]);
      expect(await isDone(refreshed), isTrue);
      scripted.release('temple');
      await settle();
      await book.close();
    });

    test(
      'Tor failing: a coordinator in flight is shown offline at 80 seconds at the latest, then gives its last failure, asked no more',
      () async {
        scripted
          ..script['temple'] = const [ScriptedFailure(CoordinatorUnreachable())]
          ..held.add('temple');
        final book = await shown();

        tor.embedded.failed();
        await settle();
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        waits.fireAwaitedBounds();
        await settle();
        expect(book.state.failedCoordinators, [coordinator('temple')]);

        scripted.release('temple');
        await settle();
        expect(
          book.state.coordinators[coordinator('temple')],
          isA<CoordinatorBookFailed>().having(
            (s) => s.failure,
            'failure',
            isA<CoordinatorUnreachable>(),
          ),
        );
        expect(waits.started, isEmpty);
        expect(waits.running, isEmpty);
        expect(scripted.requestsTo('temple'), 1);
        await book.close();
      },
    );

    test(
      'leaving the tab during a load and coming back: one request in flight, and the new book gets its answer',
      () async {
        scripted.held.add('temple');
        final left = await shown();
        expect(scripted.requestsTo('temple'), 1);
        await left.close();

        final back = await shown();
        expect(scripted.requestsTo('temple'), 1);
        expect(back.state.loadingCoordinators, [coordinator('temple')]);

        scripted.release('temple');
        await settle();
        expect(back.state.loadingCoordinators, isEmpty);
        expect(back.state.orders.map((o) => o.id), [1, 2]);
        expect(scripted.mostAtOnce['temple'], 1);
        // The book that was left emits nothing.
        expect(left.state.loadingCoordinators, [coordinator('temple')]);
        await back.close();
      },
    );

    test(
      'leaving the tab and coming back five times: still one request in flight',
      () async {
        scripted.held.add('temple');
        for (var visit = 0; visit < 5; visit++) {
          final book = await shown();
          expect(book.state.loadingCoordinators, [coordinator('temple')]);
          await book.close();
        }
        final last = await shown();
        expect(scripted.requestsTo('temple'), 1);
        expect(scripted.mostAtOnce['temple'], 1);

        scripted.release('temple');
        await settle();
        expect(last.state.orders.map((o) => o.id), [1, 2]);
        await last.close();
        expect(waits.running, isEmpty);
      },
    );

    test('leaving the tab ends every wait and every bound', () async {
      scripted
        ..script['lake'] = const [ScriptedFailure(CoordinatorUnreachable())]
        ..held.add('temple');
      final book = await shown();
      final refreshed = book.refresh();
      await settle();
      expect(waits.running, isNotEmpty);

      await book.close();
      expect(waits.running, isEmpty);
      expect(await isDone(refreshed), isTrue);
      scripted.release('temple');
      await settle();
    });
    test(
      'a refresh where every coordinator answers is done then, its 10-second bound ended',
      () async {
        final book = await shown();
        final refreshed = book.refresh();

        expect(await isDone(refreshed), isTrue);
        expect(waits.refreshBounds, isEmpty);
        expect(waits.running, isEmpty);
        await book.close();
      },
    );

    test(
      'a refresh with one silent coordinator is done at 10 seconds, the row still showing it awaited',
      () async {
        final book = await shown();
        scripted.held.add('temple');
        final refreshed = book.refresh();
        expect(await isDone(refreshed), isFalse);

        waits.fireRefreshBounds();
        expect(await isDone(refreshed), isTrue);
        expect(book.state.loadingCoordinators, [coordinator('temple')]);
        // Its orders stay shown while it is awaited.
        expect(book.state.orders.map((o) => o.id), [1, 2]);
        scripted.release('temple');
        await settle();
        await book.close();
      },
    );

    test('« Retry » is waited for 10 seconds at most too', () async {
      scripted.script['temple'] = [
        for (var i = 0; i < 3; i++)
          const ScriptedFailure(CoordinatorUnreachable()),
      ];
      final book = await shown();
      waits.fireAll();
      await settle();
      waits.fireAll();
      await settle();
      expect(book.state.failedCoordinators, [coordinator('temple')]);

      scripted.held.add('temple');
      final retried = book.retryFailed();
      expect(await isDone(retried), isFalse);
      waits.fireRefreshBounds();
      expect(await isDone(retried), isTrue);
      expect(book.state.loadingCoordinators, [coordinator('temple')]);
      scripted.release('temple');
      await settle();
      expect(book.state.failedCoordinators, isEmpty);
      await book.close();
    });
  });

  group('filters', () {
    setUp(() {
      transport = FakeTransport(
        books: {
          'temple': [
            bookOrder(id: 1, type: 1, premium: 3),
            bookOrder(id: 2, type: 1, premium: 1, makerSeed: 2),
            bookOrder(id: 3, type: 0, premium: 5, makerSeed: 3),
            bookOrder(id: 4, type: 1, currency: 1, premium: 0, makerSeed: 4),
            bookOrder(id: 5, type: 1, currency: 1000, makerSeed: 5),
          ],
          'lake': [
            bookOrder(id: 6, type: 0, premium: 7, makerSeed: 6),
            bookOrder(
              id: 7,
              type: 1,
              premium: 2,
              paymentMethod: 'Wise',
              makerSeed: 7,
            ),
          ],
        },
      );
    });

    Future<BookCubit> loaded() async {
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();
      await settle();
      return book;
    }

    test('any side keeps the federation order and leaves swaps out', () async {
      final book = await loaded();

      expect(book.state.filter, const BookFilter());
      expect(book.state.orders.map((o) => o.id), [1, 2, 3, 4, 6, 7]);
      await book.close();
    });

    test('buying shows sell orders, the lowest premium first', () async {
      final book = await loaded()
        ..selectSide(BookSide.buy);

      expect(book.state.orders.map((o) => o.id), [4, 2, 7, 1]);
      await book.close();
    });

    test('selling shows buy orders, the highest premium first', () async {
      final book = await loaded()
        ..selectSide(BookSide.sell);

      expect(book.state.orders.map((o) => o.id), [6, 3]);
      await book.close();
    });

    test('currency, payment method and host narrow the book', () async {
      final book = await loaded()
        ..selectSide(BookSide.buy)
        ..selectCurrency(RobosatsCurrency.fromCode('EUR'));
      expect(book.state.orders.map((o) => o.id), [2, 7, 1]);

      book.selectPaymentMethod('Wise');
      expect(book.state.orders.map((o) => o.id), [7]);

      book
        ..selectPaymentMethod(null)
        ..selectHost(coordinator('temple'));
      expect(book.state.orders.map((o) => o.id), [2, 1]);

      book
        ..selectHost(null)
        ..selectCurrency(null)
        ..selectSide(BookSide.any);
      expect(book.state.orders.map((o) => o.id), [1, 2, 3, 4, 6, 7]);
      await book.close();
    });

    test(
      'the payment methods offered are those of the matching orders',
      () async {
        final book = await loaded();

        expect(
          const BookFilter(
            side: BookSide.buy,
          ).paymentMethodsIn(book.state.receivedOrders).map((m) => m.name),
          ['Instant SEPA', 'Revolut', 'Wise'],
        );
        expect(
          const BookFilter(
            side: BookSide.buy,
            host: null,
            paymentMethod: 'Wise',
          ).paymentMethodsIn(book.state.receivedOrders).map((m) => m.name),
          ['Instant SEPA', 'Revolut', 'Wise'],
        );
        await book.close();
      },
    );

    test('search finds any order received, whatever the filter', () async {
      final book = await loaded();
      book.selectSide(BookSide.sell);
      final temple = hostOf('temple', RobosatsNetwork.mainnet);
      final lake = hostOf('lake', RobosatsNetwork.mainnet);

      // Order 1 sells bitcoin, hidden while the user sells; order 5 is a swap, never in the list.
      expect(book.state.orders.map((o) => o.id), isNot(contains(1)));
      expect(
        book.searchOrder('http://$temple/order/temple/1'),
        isA<OrderSearchFound>().having((found) => found.order.id, 'id', 1),
      );
      expect(
        book.searchOrder('http://$temple/order/temple/5'),
        isA<OrderSearchFound>().having((found) => found.order.id, 'id', 5),
      );
      expect(
        book.searchOrder('http://$lake/order/lake/7'),
        isA<OrderSearchFound>().having(
          (found) => found.order.coordinator.shortAlias,
          'coordinator',
          'lake',
        ),
      );
      expect(
        book.searchOrder('http://$lake/order/lake/1'),
        isA<OrderSearchNeedsRobot>(),
      );
      expect(book.searchOrder('order 1'), isA<OrderSearchInvalidUrl>());
      await book.close();
    });
  });
}
