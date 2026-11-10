import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';

T _ok<T>(Result<T, CoordinatorFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('expected a value, got $failure'),
};

/// The book answers recorded with `404 {"not_found": …}`: these coordinators had no public order.
const _emptyBooks = {
  ('freeport', RobosatsNetwork.mainnet),
  ('temple', RobosatsNetwork.testnet),
};

void main() {
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    transport = FakeCoordinatorTransport();
    for (final (alias, network) in recordedCoordinators) {
      transport
        ..answerRecorded(alias, network, 'info')
        ..answerRecorded(alias, network, 'limits')
        ..answerRecorded(
          alias,
          network,
          'book',
          statusCode: _emptyBooks.contains((alias, network)) ? 404 : 200,
        );
    }
    client = CoordinatorClient(transport, clock: () => recordedAt);
  });

  group('recorded /api/info/', () {
    for (final (alias, network) in recordedCoordinators) {
      test(
        'of $alias on ${network.name} is read and matches the federation',
        () async {
          final coordinator = coordinatorNamed(alias);
          final info = _ok(await client.fetchInfo(coordinator, network));
          expect(info.network, network);
          expect(coordinator.nodesPubkeys(network), contains(info.nodeId));
          expect(info.makerFee, lessThan(0.01));
          expect(info.takerFee, lessThan(0.01));
          expect(
            info.minOrderSize.compareTo(info.maxOrderSize),
            lessThanOrEqualTo(0),
          );
        },
      );
    }

    test('keeps the values temple sent on mainnet', () async {
      final info = _ok(
        await client.fetchInfo(
          coordinatorNamed('temple'),
          RobosatsNetwork.mainnet,
        ),
      );
      expect(info.version, const CoordinatorVersion(0, 8, 8));
      expect(info.numPublicBuyOrders, 19);
      expect(info.numPublicSellOrders, 14);
      expect(info.bookLiquidity, Sats.fromInt(56634461));
      expect(info.makerFee, 0.00025);
      expect(info.takerFee, 0.00175);
      expect(info.bondSize, 3.0);
      expect(info.devfund, 30.0);
      expect(info.minOrderSize, Sats.fromInt(15000));
      expect(info.maxOrderSize, Sats.fromInt(6000000));
      expect(info.swapEnabled, isTrue);
      expect(info.blossomEnabled, isTrue);
      // Temple capitalises its severity, outside the serializer's choices.
      expect(info.noticeSeverity, NoticeSeverity.info);
      expect(info.noticeMessage, isEmpty);
      expect(
        info.federationHash,
        '1b048dc5d0c035052226b732171190232627912a7f6a10d744021ae0fe587f5f',
      );
    });

    test(
      'reads the older testnet coordinator, which lacks recent fields',
      () async {
        final info = _ok(
          await client.fetchInfo(
            coordinatorNamed('temple'),
            RobosatsNetwork.testnet,
          ),
        );
        expect(info.version, const CoordinatorVersion(0, 8, 6));
        expect(info.devfund, isNull);
        expect(info.blossomEnabled, isNull);
        expect(info.federationHash, isNull);
        expect(info.lastDayVolume, 0);
      },
    );

    test('keeps the notice of lake, without printing it', () async {
      final info = _ok(
        await client.fetchInfo(
          coordinatorNamed('lake'),
          RobosatsNetwork.mainnet,
        ),
      );
      expect(info.noticeMessage, contains('PIX'));
      expect('$info', isNot(contains('PIX')));
      expect('$info', isNot(contains(info.nodeAlias)));
    });

    test('fails the identity check when asked on the other network', () async {
      final temple = coordinatorNamed('temple');
      transport.answerRecorded('temple', RobosatsNetwork.testnet, 'info');
      // The testnet answer, served at the mainnet address.
      transport.answer(
        temple,
        RobosatsNetwork.mainnet,
        '/api/info/',
        Ok(
          rawResponse(recordedBody('temple', RobosatsNetwork.testnet, 'info')),
        ),
      );
      expect(
        (await client.fetchInfo(temple, RobosatsNetwork.mainnet)),
        isA<Err<CoordinatorInfo, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorNetworkMismatch>(),
        ),
      );
    });

    test(
      'fails the identity check with the node of another coordinator',
      () async {
        transport.answer(
          coordinatorNamed('lake'),
          RobosatsNetwork.mainnet,
          '/api/info/',
          Ok(
            rawResponse(
              recordedBody('temple', RobosatsNetwork.mainnet, 'info'),
            ),
          ),
        );
        expect(
          (await client.fetchInfo(
            coordinatorNamed('lake'),
            RobosatsNetwork.mainnet,
          )),
          isA<Err<CoordinatorInfo, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<CoordinatorNodeIdMismatch>(),
          ),
        );
      },
    );
  });

  group('recorded /api/book/', () {
    for (final (alias, network) in recordedCoordinators) {
      test('of $alias on ${network.name} keeps every order', () async {
        final coordinator = coordinatorNamed(alias);
        final book = _ok(await client.fetchBook(coordinator, network));
        expect(book.droppedOrders, 0);
        expect(book.coordinator, coordinator);
        if (_emptyBooks.contains((alias, network))) {
          expect(book.orders, isEmpty);
        } else {
          expect(book.orders, isNotEmpty);
        }
        for (final order in book.orders) {
          expect(order.coordinator, coordinator);
          expect(order.expiresAt.isAfter(order.createdAt), isTrue);
        }
      });
    }

    test('gives the expected number of orders per coordinator', () async {
      final counts = {
        for (final (alias, network) in recordedCoordinators)
          '$alias ${network.name}': _ok(
            await client.fetchBook(coordinatorNamed(alias), network),
          ).orders.length,
      };
      expect(counts, {
        'temple mainnet': 33,
        'lake mainnet': 49,
        'bazaar mainnet': 16,
        'freeport mainnet': 0,
        'ammanaya mainnet': 6,
        'temple testnet': 0,
      });
    });

    test('reads the first order of temple field by field', () async {
      final book = _ok(
        await client.fetchBook(
          coordinatorNamed('temple'),
          RobosatsNetwork.mainnet,
        ),
      );
      final order = book.orders.first;
      expect(order.id, 99598);
      expect(order.createdAt, DateTime.utc(2026, 11, 9, 16, 7, 33, 375, 335));
      expect(order.expiresAt, DateTime.utc(2026, 11, 10, 16, 7, 33, 375, 335));
      expect(order.type, OrderType.sell);
      expect(order.currency.code, 'BTC');
      expect(order.amount, isA<RangeOrderAmount>());
      expect(order.amount.min.value, 0.0021);
      expect(order.amount.max.value, 0.021);
      expect(order.paymentMethods.text, 'On-Chain BTC');
      expect(order.paymentMethods.recognized.map((m) => m.name), [
        'On-Chain BTC',
      ]);
      expect(order.paymentMethods.hasOtherText, isFalse);
      expect(order.premium.percent, -0.05);
      expect(order.explicitSatoshis, isNull);
      expect(order.satoshisNow, Sats.fromInt(2101050));
      expect(order.price, 0.9995);
      expect(order.escrowDuration, const Duration(hours: 8));
      expect(order.bondSize.percent, 3);
      expect(order.location, isNull);
      expect(
        order.maker.hex,
        'e302b62121555c64060e8cb3b32e6040d544342203486fa7e17689cf735d0cae',
      );
      expect(order.maker.nickname, 'AbundantX516');
      expect(order.makerActivity, MakerActivity.active);
      expect(
        '$order',
        'PublicOrder(temple#99598, sell, BTC, RangeOrderAmount(0.0021-0.021), Premium(-0.05%))',
      );
    });

    test('reads a fixed amount, a location and every activity label', () async {
      final orders = [
        for (final (alias, network) in recordedCoordinators)
          ..._ok(
            await client.fetchBook(coordinatorNamed(alias), network),
          ).orders,
      ];
      expect(
        orders
            .whereType<PublicOrder>()
            .map((o) => o.amount)
            .whereType<FixedOrderAmount>(),
        hasLength(20),
      );
      expect(orders.where((o) => o.location != null), hasLength(1));
      expect(
        orders.map((o) => o.makerActivity).toSet(),
        MakerActivity.values.toSet(),
      );
      expect(orders.map((o) => o.type).toSet(), OrderType.values.toSet());
    });

    test(
      'sends the filters as query parameters, and none by default',
      () async {
        final temple = coordinatorNamed('temple');
        await client.fetchBook(temple, RobosatsNetwork.mainnet);
        await client.fetchBook(
          temple,
          RobosatsNetwork.mainnet,
          currency: RobosatsCurrency.fromCode('EUR'),
          type: OrderType.sell,
        );
        expect(
          transport.requests[0].url.toString(),
          '${temple.mainnet.onion}/api/book/',
        );
        expect(
          transport.requests[1].url.toString(),
          '${temple.mainnet.onion}/api/book/?currency=2&type=1',
        );
        expect(transport.requests[1].method, CoordinatorHttpMethod.get);
        expect(
          transport.requests[1].maxResponseBytes,
          CoordinatorReadBounds.bookBytes,
        );
        expect(transport.requests[1].headers, {'Accept': 'application/json'});
      },
    );
  });

  group('recorded /api/limits/', () {
    for (final (alias, network) in recordedCoordinators) {
      test('of $alias on ${network.name} has every currency', () async {
        final limits = _ok(
          await client.fetchLimits(coordinatorNamed(alias), network),
        );
        expect(limits.droppedEntries, 0);
        expect(limits.byCurrency.keys.toSet(), RobosatsCurrency.all.toSet());
      });
    }

    test('keeps the values temple sent on mainnet', () async {
      final limits = _ok(
        await client.fetchLimits(
          coordinatorNamed('temple'),
          RobosatsNetwork.mainnet,
        ),
      );
      final usd = limits[RobosatsCurrency.fromCode('USD') ?? fail('USD')];
      expect(usd?.price, 73956.8);
      expect(usd?.minAmount, 11.09352);
      expect(usd?.maxAmount, 4437.408);
      final btc = limits[RobosatsCurrency.fromId(1000) ?? fail('BTC')];
      expect(btc?.price, 1.0);
    });
  });
}
