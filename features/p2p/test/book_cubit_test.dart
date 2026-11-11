import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/domain/order_search.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/retry_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/start_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'package:p2p/src/presentation/book_cubit.dart';
import 'package:p2p/src/presentation/book_state.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

void main() {
  late FakeTor tor;
  late FakeTransport transport;

  BookCubit cubit({RobosatsNetwork network = RobosatsNetwork.mainnet}) =>
      BookCubit(
        network,
        WatchP2pTorStateUsecase(() => tor),
        StartP2pTorUsecase(() => tor),
        RetryP2pTorUsecase(() => tor),
        RequestFederationBooksUsecase(
          FederationBookReader(transport, clock: () => testNow),
          Federation.robosats,
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
      'a coordinator that fails stays visible and does not hide the others',
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
        expect(book.state.orders.map((o) => o.id), [2]);
        await book.close();
      },
    );

    test('retry asks again only the coordinators that failed', () async {
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
      await settle();
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

    test('an answer to an older request is dropped', () async {
      transport = FakeTransport(
        books: {
          'temple': [bookOrder(id: 1)],
        },
        held: {'temple'},
      );
      final book = cubit()..start();
      tor.embedded.ready();
      await settle();
      // The first request is still held when a refresh is answered at once.
      transport
        ..held.remove('temple')
        ..books['temple'] = [bookOrder(id: 2)];
      await book.refresh();
      expect(book.state.orders.map((o) => o.id), [2]);

      // The first request answers last, with an older book: it is dropped.
      transport.books['temple'] = [bookOrder(id: 1)];
      transport.release('temple');
      await settle();
      await settle();
      expect(book.state.orders.map((o) => o.id), [2]);
      await book.close();
    });

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
