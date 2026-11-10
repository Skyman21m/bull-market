import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// Answers every coordinator at once with an empty book, except the one whose onion host is [heldHost], which answers only when the test says so.
final class _HoldingTransport implements CoordinatorTransport {
  final String heldHost;
  final held =
      Completer<Result<CoordinatorResponse, CoordinatorTransportFailure>>();
  final List<Uri> sent = [];

  _HoldingTransport(this.heldHost);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) {
    sent.add(request.url);
    if (request.url.host == heldHost) return held.future;
    return Future.value(
      Ok(
        CoordinatorResponse(
          statusCode: 200,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode('[]'),
        ),
      ),
    );
  }
}

Coordinator _named(String alias) => switch (Federation.robosats.byAlias(
  alias,
)) {
  final coordinator? => coordinator,
  null => throw StateError('no coordinator $alias'),
};

String _host(Coordinator coordinator, RobosatsNetwork network) =>
    Uri.parse(coordinator.origins(network).onion ?? '').host;

void main() {
  test('lists the coordinators of each network, in the federation order', () {
    final usecase = RequestFederationBooksUsecase(
      FederationBookReader(_HoldingTransport('none')),
      Federation.robosats,
    );

    expect(
      usecase.execute(RobosatsNetwork.mainnet).keys,
      Federation.robosats.on(RobosatsNetwork.mainnet),
    );
    expect(
      usecase.execute(RobosatsNetwork.testnet).keys.map((c) => c.shortAlias),
      ['temple', 'lake'],
    );
  });

  test(
    'one coordinator that does not answer neither delays nor hides the others',
    () async {
      const network = RobosatsNetwork.mainnet;
      final temple = _named('temple');
      final transport = _HoldingTransport(_host(temple, network));
      final books = RequestFederationBooksUsecase(
        FederationBookReader(transport),
        Federation.robosats,
      ).execute(network);

      // Every request is sent before any answer arrives.
      expect(transport.sent, hasLength(books.length));

      var templeDone = false;
      final templeBook = books[temple];
      if (templeBook == null) fail('no book for temple');
      templeBook.then((_) => templeDone = true).ignore();
      final others = [
        for (final MapEntry(:key, :value) in books.entries)
          if (key != temple) value,
      ];
      final outcomes = await Future.wait(
        others,
      ).timeout(const Duration(seconds: 1));

      expect(outcomes, hasLength(4));
      for (final outcome in outcomes) {
        expect(
          outcome.result,
          isA<Ok<OrderBook, CoordinatorFailure>>().having(
            (ok) => ok.value.orders,
            'orders',
            isEmpty,
          ),
        );
      }
      expect(templeDone, isFalse);

      transport.held.complete(const Err(CoordinatorUnreachable()));
      final outcome = await templeBook;
      expect(outcome.coordinator, temple);
      expect(
        outcome.result,
        isA<Err<OrderBook, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorUnreachable>(),
        ),
      );
    },
  );
}
