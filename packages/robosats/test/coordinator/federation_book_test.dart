import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';

void main() {
  group('FederationBookReader', () {
    late FakeCoordinatorTransport transport;
    late FederationBookReader reader;

    setUp(() {
      transport = FakeCoordinatorTransport();
      reader = FederationBookReader(transport);
    });

    test('merges the recorded books of every mainnet coordinator', () async {
      for (final alias in ['temple', 'lake', 'bazaar', 'ammanaya']) {
        transport.answerRecorded(alias, RobosatsNetwork.mainnet, 'book');
      }
      transport.answerRecorded(
        'freeport',
        RobosatsNetwork.mainnet,
        'book',
        statusCode: 404,
      );
      final book = await reader.read(
        Federation.robosats,
        RobosatsNetwork.mainnet,
      );
      expect(book.failures, isEmpty);
      expect(book.orders, hasLength(33 + 49 + 16 + 6));
      expect(book.outcomes.map((outcome) => outcome.coordinator.shortAlias), [
        'temple',
        'lake',
        'bazaar',
        'freeport',
        'ammanaya',
      ]);
      // By coordinator in federation order, then by id.
      final keys = [
        for (final order in book.orders)
          (
            Federation.robosats.coordinators.indexOf(order.coordinator),
            order.id,
          ),
      ];
      final sorted = List.of(keys)
        ..sort(
          (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
        );
      expect(keys, sorted);
    });

    test('keeps the other books when coordinators fail or misbehave', () async {
      transport
        ..answerRecorded('temple', RobosatsNetwork.mainnet, 'book')
        ..answer(
          coordinatorNamed('lake'),
          RobosatsNetwork.mainnet,
          '/api/book/',
          const Err(CoordinatorTimedOut()),
        )
        ..answer(
          coordinatorNamed('bazaar'),
          RobosatsNetwork.mainnet,
          '/api/book/',
          Ok(rawResponse(List.filled(64, 0x41), contentType: 'text/plain')),
        )
        ..route(
          coordinatorNamed('freeport'),
          RobosatsNetwork.mainnet,
          '/api/book/',
          (_) => Future.error(Exception('adapter bug')),
        );
      // ammanaya has no route: the fake answers unreachable.
      final book = await reader.read(
        Federation.robosats,
        RobosatsNetwork.mainnet,
      );
      expect(book.orders, hasLength(33));
      expect(
        book.orders.every((o) => o.coordinator.shortAlias == 'temple'),
        isTrue,
      );
      expect(
        book.failures.map((c, f) => MapEntry(c.shortAlias, f.runtimeType)),
        {
          'lake': CoordinatorTimedOut,
          'bazaar': CoordinatorNotJson,
          'freeport': CoordinatorTransportFailed,
          'ammanaya': CoordinatorUnreachable,
        },
      );
    });

    test(
      'tags orders with their coordinator, so equal ids stay apart',
      () async {
        transport
          ..answerRecorded('temple', RobosatsNetwork.mainnet, 'book')
          ..answer(
            coordinatorNamed('lake'),
            RobosatsNetwork.mainnet,
            '/api/book/',
            Ok(
              rawResponse(
                recordedBody('temple', RobosatsNetwork.mainnet, 'book'),
              ),
            ),
          );
        final book = await reader.read(
          Federation([coordinatorNamed('temple'), coordinatorNamed('lake')]),
          RobosatsNetwork.mainnet,
        );
        expect(book.orders, hasLength(66));
        expect(book.orders.toSet(), hasLength(66));
      },
    );

    test('starts every request before any answer arrives', () async {
      final pending =
          <
            String,
            Completer<Result<CoordinatorResponse, CoordinatorTransportFailure>>
          >{};
      for (final coordinator in Federation.robosats.on(
        RobosatsNetwork.mainnet,
      )) {
        final completer =
            Completer<
              Result<CoordinatorResponse, CoordinatorTransportFailure>
            >();
        pending[coordinator.shortAlias] = completer;
        transport.route(
          coordinator,
          RobosatsNetwork.mainnet,
          '/api/book/',
          (_) => completer.future,
        );
      }
      final futures = reader.requestAll(
        Federation.robosats,
        RobosatsNetwork.mainnet,
      );
      expect(futures, hasLength(5));
      expect(transport.requests, hasLength(5));

      // The last coordinator answers first, and its book is usable at once.
      pending['ammanaya']?.complete(
        Ok(
          rawResponse(
            recordedBody('ammanaya', RobosatsNetwork.mainnet, 'book'),
          ),
        ),
      );
      final first = await futures.last;
      expect(first.coordinator.shortAlias, 'ammanaya');
      expect(first.result, isA<Ok<OrderBook, CoordinatorFailure>>());
      for (final completer in pending.values.where((c) => !c.isCompleted)) {
        completer.complete(const Err(CoordinatorUnreachable()));
      }
      final book = FederationBook.merge(await Future.wait(futures));
      expect(book.orders, hasLength(6));
      expect(book.failures, hasLength(4));
    });

    test(
      'reports coordinators absent from testnet without a request',
      () async {
        transport.answerRecorded(
          'temple',
          RobosatsNetwork.testnet,
          'book',
          statusCode: 404,
        );
        final book = await reader.read(
          Federation.robosats,
          RobosatsNetwork.testnet,
        );
        expect(transport.requests.map((r) => r.url.host), hasLength(2));
        expect(
          book.failures.map((c, f) => MapEntry(c.shortAlias, f.runtimeType)),
          {
            'lake': CoordinatorUnreachable,
            'bazaar': CoordinatorNotOnNetwork,
            'freeport': CoordinatorNotOnNetwork,
            'ammanaya': CoordinatorNotOnNetwork,
          },
        );
        expect(book.orders, isEmpty);
      },
    );

    test('passes the filters to every coordinator', () async {
      await reader.read(
        Federation.robosats,
        RobosatsNetwork.mainnet,
        currency: RobosatsCurrency.fromCode('USD'),
        type: OrderType.buy,
      );
      expect(transport.requests.map((r) => r.url.query).toSet(), {
        'currency=1&type=0',
      });
    });
  });
}
