import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';

const _mainnet = RobosatsNetwork.mainnet;

/// A valid book entry, the first order of temple on 10/11/2026.
Map<String, Object?> _order([Map<String, Object?> changes = const {}]) => {
  'id': 99598,
  'created_at': '2026-11-09T16:07:33.375335Z',
  'expires_at': '2026-11-10T16:07:33.375335Z',
  'type': 1,
  'currency': 1000,
  'amount': null,
  'has_range': true,
  'min_amount': '0.00210000',
  'max_amount': '0.02100000',
  'payment_method': 'On-Chain BTC',
  'is_explicit': false,
  'premium': '-0.05',
  'satoshis': null,
  'maker': 535480,
  'escrow_duration': 28800,
  'bond_size': '3.00',
  'latitude': null,
  'longitude': null,
  'maker_nick': 'AbundantX516',
  'maker_hash_id':
      'e302b62121555c64060e8cb3b32e6040d544342203486fa7e17689cf735d0cae',
  'satoshis_now': 2101050,
  'price': 0.9995,
  'maker_status': 'Active',
  ...changes,
};

/// A valid info answer of temple on mainnet.
Map<String, Object?> _info([Map<String, Object?> changes = const {}]) => {
  ...jsonDecode(utf8.decode(recordedBody('temple', _mainnet, 'info')))
      as Map<String, Object?>,
  ...changes,
};

Map<String, Object?> _without(Map<String, Object?> map, String key) =>
    Map.of(map)..remove(key);

F _failure<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => fail('expected a failure, got $value'),
  Err(:final failure) => failure,
};

T _value<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('expected a value, got $failure'),
};

String? _droppedField(Map<String, Object?> order) =>
    switch (PublicOrder.parse(order, coordinatorNamed('temple'))) {
      Ok() => null,
      Err(:final failure) => failure.field,
    };

void main() {
  final temple = coordinatorNamed('temple');
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    transport = FakeCoordinatorTransport();
    client = CoordinatorClient(transport);
  });

  void serve(
    String path,
    Result<CoordinatorResponse, CoordinatorTransportFailure> response,
  ) => transport.answer(temple, _mainnet, path, response);

  group('every endpoint', () {
    final endpoints =
        <String, Future<Result<Object?, CoordinatorFailure>> Function()>{
          '/api/info/': () => client.fetchInfo(temple, _mainnet),
          '/api/book/': () => client.fetchBook(temple, _mainnet),
          '/api/limits/': () => client.fetchLimits(temple, _mainnet),
        };

    for (final MapEntry(key: path, value: fetch) in endpoints.entries) {
      test('$path passes transport failures through', () async {
        for (final failure in const <CoordinatorTransportFailure>[
          CoordinatorUnreachable(),
          CoordinatorTimedOut(),
          CoordinatorResponseTooLarge(),
          CoordinatorTransportFailed(),
        ]) {
          serve(path, Err(failure));
          expect(_failure(await fetch()), same(failure));
        }
      });

      test('$path turns an exception of the adapter into a failure', () async {
        transport.route(
          temple,
          _mainnet,
          path,
          (_) => Future.error(const FormatException('socket closed')),
        );
        expect(_failure(await fetch()), isA<CoordinatorTransportFailed>());
      });

      test('$path rejects a status other than 200', () async {
        for (final status in [301, 400, 403, 500, 503]) {
          serve(path, Ok(jsonResponse({}, statusCode: status)));
          expect(
            _failure(await fetch()),
            isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              status,
            ),
          );
        }
      });

      test('$path rejects anything but JSON', () async {
        final notJson = [
          rawResponse(utf8.encode('{}'), contentType: 'text/plain'),
          rawResponse(
            utf8.encode('{}'),
            contentType: 'text/html; charset=utf-8',
          ),
          rawResponse(utf8.encode('{}'), contentType: null),
          rawResponse(utf8.encode('<html></html>')),
          rawResponse(utf8.encode('{"a": NaN}')),
          rawResponse(utf8.encode('{"a": 1')),
          rawResponse(const []),
          rawResponse(const [0x7b, 0x22, 0xff, 0xfe, 0x22, 0x3a, 0x31, 0x7d]),
        ];
        for (final response in notJson) {
          serve(path, Ok(response));
          expect(_failure(await fetch()), isA<CoordinatorNotJson>());
        }
      });

      test('$path rejects a body above its bound, as the decoy does', () async {
        final bound = switch (path) {
          '/api/book/' => CoordinatorReadBounds.bookBytes,
          _ => CoordinatorReadBounds.infoBytes,
        };
        serve(path, Ok(rawResponse(List.filled(bound + 1, 0x20))));
        expect(_failure(await fetch()), isA<CoordinatorResponseTooLarge>());
        expect(transport.requests.last.maxResponseBytes, bound);
      });

      test('$path rejects JSON of the wrong shape', () async {
        for (final body in [null, 1, 'text', true]) {
          serve(path, Ok(jsonResponse(body)));
          expect(_failure(await fetch()), isA<CoordinatorResponseMalformed>());
        }
      });

      test(
        '$path sends nothing for a coordinator absent from the network',
        () async {
          final bazaar = coordinatorNamed('bazaar');
          final result = switch (path) {
            '/api/info/' => await client.fetchInfo(
              bazaar,
              RobosatsNetwork.testnet,
            ),
            '/api/book/' => await client.fetchBook(
              bazaar,
              RobosatsNetwork.testnet,
            ),
            _ => await client.fetchLimits(bazaar, RobosatsNetwork.testnet),
          };
          expect(_failure(result), isA<CoordinatorNotOnNetwork>());
          expect(transport.requests, isEmpty);
        },
      );
    }

    test('deep nesting and huge numbers neither throw nor pass', () async {
      const depth = 400000;
      serve(
        '/api/book/',
        Ok(rawResponse(utf8.encode('${'[' * depth}${']' * depth}'))),
      );
      final book = _value(await client.fetchBook(temple, _mainnet));
      expect(book.orders, isEmpty);
      expect(book.droppedOrders, 1);

      String infoWith(String field, String number) {
        final text = jsonEncode(_info({field: 0}));
        return text.replaceFirst('"$field":0', '"$field":$number');
      }

      for (final (field, number) in [
        ('maker_fee', '1e400'),
        ('maker_fee', '-1e400'),
        ('book_liquidity', '99999999999999999999999'),
        ('num_public_buy_orders', '1e3'),
      ]) {
        serve(
          '/api/info/',
          Ok(rawResponse(utf8.encode(infoWith(field, number)))),
        );
        final failure = _failure(await client.fetchInfo(temple, _mainnet));
        expect(
          failure,
          isA<CoordinatorResponseMalformed>().having(
            (f) => f.field,
            'field',
            field,
          ),
          reason: number,
        );
      }
    });

    test('a failure never prints coordinator text', () async {
      serve('/api/info/', Ok(jsonResponse(_info({'node_alias': 42}))));
      final failure = _failure(await client.fetchInfo(temple, _mainnet));
      expect(failure, isA<CoordinatorResponseMalformed>());
      expect((failure as CoordinatorResponseMalformed).field, 'node_alias');
      expect('$failure', 'CoordinatorResponseMalformed');
    });
  });

  group('/api/info/ rejects the whole answer', () {
    Future<CoordinatorFailure> fetchWith(Map<String, Object?> body) async {
      serve('/api/info/', Ok(jsonResponse(body)));
      return _failure(await client.fetchInfo(temple, _mainnet));
    }

    final invalid = <String, List<Object?>>{
      'num_public_buy_orders': [-1, 1.5, '3', null],
      'book_liquidity': [-1, 2100000000000001, 1e300],
      'last_day_nonkyc_btc_premium': ['0.95', null, -101],
      'maker_fee': [-0.1, 1.5, '0.00025', null],
      'taker_fee': [2, null],
      'bond_size': [-3, 101, null],
      'devfund': [-1, 101, '30'],
      'min_order_size': [0, -5, 2.5, null],
      'max_order_size': [null, 'big'],
      'swap_enabled': ['true', 1, null],
      'max_swap': [-1, null],
      'node_id': [
        null,
        '0226F31C5F3A8B48BBBB7AAA97A10EFFCFB445B5972A676955D5C095383D35A428',
        '0426f31c5f3a8b48bbbb7aaa97a10effcfb445b5972a676955d5c095383d35a428',
        'ab',
        66,
      ],
      'network': [null, 1],
      'node_alias': [null, 7, 'x' * 1025],
      'version': [
        null,
        '0.8.8',
        {'major': 0, 'minor': 8},
        {'major': -1, 'minor': 8, 'patch': 8},
        {'major': 0, 'minor': '8', 'patch': 8},
      ],
      'notice_message': [42, 'x' * 16385],
      'blossom_enabled': ['yes'],
      'federation_hash': [64],
      'current_swap_fee_rate': [-1, 101, 'NaN'],
    };

    for (final MapEntry(key: field, value: values) in invalid.entries) {
      test('for an invalid $field', () async {
        for (final value in values) {
          final failure = await fetchWith(_info({field: value}));
          expect(
            failure,
            isA<CoordinatorResponseMalformed>(),
            reason: '$value',
          );
          expect(
            (failure as CoordinatorResponseMalformed).field,
            field == 'max_order_size' || field == 'min_order_size'
                ? anyOf('min_order_size', 'max_order_size')
                : field,
            reason: '$value',
          );
        }
      });
    }

    test('when the minimum order is above the maximum', () async {
      final failure = await fetchWith(
        _info({'min_order_size': 600000, 'max_order_size': 500000}),
      );
      expect((failure as CoordinatorResponseMalformed).field, 'max_order_size');
    });

    test('for a missing required field', () async {
      for (final field in [
        'num_public_sell_orders',
        'node_id',
        'network',
        'version',
        'maker_fee',
        'min_order_size',
      ]) {
        final failure = await fetchWith(_without(_info(), field));
        expect(failure, isA<CoordinatorResponseMalformed>(), reason: field);
      }
    });

    test('for an unknown network, as an identity failure', () async {
      for (final network in ['signet', 'Mainnet', '']) {
        expect(
          await fetchWith(_info({'network': network})),
          isA<CoordinatorNetworkMismatch>(),
        );
      }
    });
  });

  group('/api/info/ tolerates', () {
    test('missing recent fields, extra fields and odd labels', () async {
      var body = _info({
        'notice_severity': 'Critical',
        'federation_hash': 'not a hash',
        'features': {'anything': true},
      });
      for (final field in [
        'devfund',
        'blossom_enabled',
        'current_swap_fee_rate',
        'lnd_version',
        'cln_version',
        'robosats_running_commit_hash',
        'alternative_site',
        'alternative_name',
        'market_price_apis',
        'notice_message',
      ]) {
        body = _without(body, field);
      }
      serve('/api/info/', Ok(jsonResponse(body)));
      final info = _value(await client.fetchInfo(temple, _mainnet));
      expect(info.noticeSeverity, NoticeSeverity.info);
      expect(info.federationHash, isNull);
      expect(info.devfund, isNull);
      expect(info.noticeMessage, '');
      serve('/api/info/', Ok(jsonResponse(_without(body, 'notice_severity'))));
      expect(
        _value(await client.fetchInfo(temple, _mainnet)).noticeSeverity,
        NoticeSeverity.none,
      );
    });

    test('a JSON content type with parameters', () async {
      serve(
        '/api/info/',
        Ok(
          jsonResponse(_info(), contentType: 'Application/JSON; charset=utf-8'),
        ),
      );
      expect(
        await client.fetchInfo(temple, _mainnet),
        isA<Ok<CoordinatorInfo, CoordinatorFailure>>(),
      );
    });
  });

  group('/api/book/', () {
    Future<OrderBook> bookOf(Object? body) async {
      serve('/api/book/', Ok(jsonResponse(body)));
      return _value(await client.fetchBook(temple, _mainnet));
    }

    test('reads 404 with not_found as an empty book', () async {
      serve(
        '/api/book/',
        Ok(jsonResponse({'not_found': 'No orders found'}, statusCode: 404)),
      );
      final book = _value(await client.fetchBook(temple, _mainnet));
      expect(book.orders, isEmpty);
      expect(book.droppedOrders, 0);
    });

    test('rejects any other 404', () async {
      for (final response in [
        jsonResponse({'detail': 'Not found.'}, statusCode: 404),
        jsonResponse([], statusCode: 404),
        rawResponse(
          utf8.encode('<h1>Not Found</h1>'),
          statusCode: 404,
          contentType: 'text/html',
        ),
      ]) {
        serve('/api/book/', Ok(response));
        expect(
          _failure(await client.fetchBook(temple, _mainnet)),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            404,
          ),
        );
      }
    });

    test(
      'rejects a book with too many orders, and accepts the bound',
      () async {
        final many = [
          for (var i = 1; i <= CoordinatorReadBounds.maxOrders + 1; i++)
            _order({'id': i}),
        ];
        serve('/api/book/', Ok(jsonResponse(many)));
        expect(
          _failure(await client.fetchBook(temple, _mainnet)),
          isA<CoordinatorTooManyOrders>(),
        );
        final book = await bookOf(many.sublist(1));
        expect(book.orders, hasLength(CoordinatorReadBounds.maxOrders));
      },
    );

    test('drops a bad order and keeps the others', () async {
      final book = await bookOf([
        _order({'id': 1}),
        _order({'id': 2, 'premium': 'NaN'}),
        'not an order',
        null,
        _order({'id': 3}),
      ]);
      expect(book.orders.map((o) => o.id), [1, 3]);
      expect(book.droppedOrders, 3);
    });

    test('drops every copy of a duplicated id', () async {
      final book = await bookOf([
        _order({'id': 1}),
        _order({'id': 2}),
        _order({'id': 1, 'premium': '5.00'}),
      ]);
      expect(book.orders.map((o) => o.id), [2]);
      expect(book.droppedOrders, 2);
    });

    test('reads a fixed, explicitly priced order with a location', () async {
      final book = await bookOf([
        _order({
          'type': 0,
          'currency': 2,
          'has_range': false,
          'amount': '150.00000000',
          'min_amount': null,
          'max_amount': null,
          'is_explicit': true,
          'satoshis': 250000,
          'premium': '1500.5',
          'latitude': '48.856600',
          'longitude': '-2.352200',
          'maker_status': 'Away',
          'maker_nick': null,
        }),
      ]);
      expect(book.droppedOrders, 1, reason: 'a premium above 999 % is dropped');
      final kept = await bookOf([
        _order({
          'type': 0,
          'currency': 2,
          'has_range': false,
          'amount': '150.00000000',
          'is_explicit': true,
          'satoshis': 250000,
          'premium': '12.34',
          'latitude': '48.856600',
          'longitude': '-2.352200',
          'maker_status': 'Away',
          'maker_nick': null,
        }),
      ]);
      final order = kept.orders.single;
      expect(order.type, OrderType.buy);
      expect(order.amount, isA<FixedOrderAmount>());
      expect(order.amount.min.value, 150);
      expect(order.explicitSatoshis, Sats.fromInt(250000));
      expect(order.premium.percent, 12.34);
      expect(order.location?.latitude, 48.8566);
      expect(order.location?.longitude, -2.3522);
      expect(order.makerActivity, isNull);
    });
  });

  group('a book entry is dropped', () {
    final invalid = <String, List<Object?>>{
      'id': [null, 0, -1, '1', 1.5],
      'created_at': [null, 'yesterday', '2026-11-09T16:07:33', 7],
      'expires_at': [
        null,
        '2026-11-09T16:07:33.375335Z',
        '2026-11-08T00:00:00Z',
      ],
      'type': [null, 2, -1, '1'],
      'currency': [null, 0, 79, 999, '2'],
      'has_range': [null, 'true'],
      'min_amount': [null, '0', '-1', '0.5e-3', 'NaN', 0.0021, '0.03'],
      'max_amount': [null, '0.002', 'Infinity', '1e400'],
      'payment_method': [null, 5, 'x' * 71],
      'is_explicit': [null, 0],
      'premium': [
        null,
        -5,
        '1000',
        '-100.01',
        'NaN',
        'Infinity',
        '1e2',
        ' 5',
        '+5',
      ],
      'satoshis': ['250000', -1],
      'satoshis_now': [-1, 2100000000000001, '5'],
      'price': ['0.9995', -1],
      'escrow_duration': [null, 1799, 36001, '28800', 28800.5],
      'bond_size': [null, '1.99', '15.01', 3, '-3'],
      'latitude': ['91', '45'],
      'longitude': ['181', '2.3'],
      'maker_hash_id': [
        null,
        'E302B62121555C64060E8CB3B32E6040D544342203486FA7E17689CF735D0CAE',
        'e302',
        'f' * 64,
      ],
      'maker_nick': ['SomebodyElse1', 7],
      'maker_status': [5],
    };

    for (final MapEntry(key: field, value: values) in invalid.entries) {
      test('for an invalid $field', () {
        for (final value in values) {
          final changes = <String, Object?>{field: value};
          // A location needs both coordinates: '45' is paired with an invalid longitude, '2.3' with a missing latitude.
          if (field == 'latitude' && value == '45') {
            changes['longitude'] = '200';
          }
          if (field == 'longitude' && value == '2.3') {
            changes['latitude'] = null;
          }
          expect(
            _droppedField(_order(changes)),
            isNotNull,
            reason: '$field = $value',
          );
        }
      });
    }

    test(
      'for a fixed order without an amount, or an explicit one without sats',
      () {
        expect(
          _droppedField(_order({'has_range': false, 'amount': null})),
          'amount',
        );
        expect(
          _droppedField(_order({'has_range': false, 'amount': '0'})),
          'amount',
        );
        expect(
          _droppedField(_order({'is_explicit': true, 'satoshis': null})),
          'satoshis',
        );
      },
    );

    test('for a range whose minimum is above its maximum', () {
      expect(
        _droppedField(_order({'min_amount': '2.0', 'max_amount': '1.0'})),
        'max_amount',
      );
    });

    test('for a book element that is not an object', () {
      for (final element in [null, 1, 'order', [], true]) {
        expect(
          PublicOrder.parse(element, temple),
          isA<Err<PublicOrder, CoordinatorResponseMalformed>>(),
        );
      }
    });

    test('but not for a missing optional field', () {
      for (final field in [
        'amount',
        'satoshis',
        'satoshis_now',
        'price',
        'latitude',
        'longitude',
        'maker_nick',
        'maker_status',
        'maker',
      ]) {
        expect(_droppedField(_without(_order(), field)), isNull, reason: field);
      }
    });
  });

  group('/api/limits/', () {
    Future<CurrencyLimits> limitsOf(Object? body) async {
      serve('/api/limits/', Ok(jsonResponse(body)));
      return _value(await client.fetchLimits(temple, _mainnet));
    }

    Map<String, Object?> entry(
      String code, [
      Map<String, Object?> changes = const {},
    ]) => {
      'code': code,
      'price': 66227.95,
      'min_amount': 9.93,
      'max_amount': 3973.67,
      ...changes,
    };

    test('drops invalid entries and keeps the others', () async {
      final limits = await limitsOf({
        '2': entry('EUR'),
        '1': entry('EUR'),
        '79': entry('XYZ'),
        '02': entry('EUR'),
        'eur': entry('EUR'),
        '3': entry('JPY', {'price': 0}),
        '4': entry('GBP', {'price': -1}),
        '5': entry('AUD', {'min_amount': 10, 'max_amount': 5}),
        '6': entry('CAD', {'price': '1'}),
        '7': entry('CHF', {'max_amount': null}),
        '8': 'CNY',
        '9': entry('HKD', {'min_amount': -1}),
      });
      expect(limits.byCurrency.keys.map((c) => c.code), ['EUR']);
      expect(limits.droppedEntries, 11);
    });

    test('rejects too many entries', () async {
      serve(
        '/api/limits/',
        Ok(
          jsonResponse({
            for (var i = 0; i <= CoordinatorReadBounds.maxLimitEntries; i++)
              'k$i': 0,
          }),
        ),
      );
      expect(
        _failure(await client.fetchLimits(temple, _mainnet)),
        isA<CoordinatorResponseMalformed>(),
      );
    });

    test('rejects a list', () async {
      serve('/api/limits/', Ok(jsonResponse([entry('EUR')])));
      expect(
        _failure(await client.fetchLimits(temple, _mainnet)),
        isA<CoordinatorResponseMalformed>(),
      );
    });
  });
}
