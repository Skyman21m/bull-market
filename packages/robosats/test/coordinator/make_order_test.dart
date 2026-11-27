import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/make_answers.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;
final _us = interopIdentity;

/// The make of an order (#175): the request checked before anything is sent, the body of `POST /api/make/`, how its `201` and its refusals are read (`MakerView.post`, `api/views.py:90-216`, `api/logics.py:75-188`, commit ff1998c), and the maker's reads of its order, error 1022 included.
///
/// Every answer is built from the reference's code (`test/support/make_answers.dart`, `order_answers.dart`), never recorded: no order was made to record it.
void main() {
  final temple = coordinatorNamed('temple');
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    transport = FakeCoordinatorTransport();
    client = CoordinatorClient(transport, clock: () => recordedAt);
  });

  void serve(Result<CoordinatorResponse, CoordinatorTransportFailure> answer) =>
      transport.answer(temple, _testnet, '/api/make/', answer);

  void serveJson(Object? json, {int statusCode = 201}) =>
      serve(Ok(jsonResponse(json, statusCode: statusCode)));

  Future<Result<MadeOrder, OrderActionFailure>> make([
    MakeOrderRequest? request,
  ]) => client.makeOrder(
    temple,
    _testnet,
    identity: _us,
    key: interopUnlockedKey,
    request: request ?? testMakeRequest(),
  );

  /// The timed text a make to Temple signs at the tests' clock (GHSA-22q8-9ghc-jg3h).
  final signedMake = 'make:temple:${unixSeconds(recordedAt)}';

  Matcher malformed(String field) => isA<CoordinatorResponseMalformed>().having(
    (f) => f.field,
    'field',
    field,
  );

  /// The body sent for [request], decoded.
  Future<Map<String, Object?>> bodyOf(MakeOrderRequest request) async {
    transport.requests.clear();
    serveJson(madeAnswer(request));
    expectOk(await make(request));
    return switch (jsonDecode(
      unsignedBody(transport.requests.single.body, signedMake),
    )) {
      final Map<String, Object?> body => body,
      _ => fail('the body is no object'),
    };
  }

  group('the request, checked before anything is sent', () {
    MakeOrderRequest? request({
      OrderType type = OrderType.buy,
      int currencyId = 2,
      OrderAmount? amount,
      String paymentMethod = 'SEPA Revolut',
      double premium = 1.5,
      Duration publicDuration = const Duration(seconds: 86340),
      Duration escrowDuration = const Duration(seconds: 10800),
      double bondSize = 3,
      String? description,
      OrderLocation? location,
      OrderPasswordHash? password,
      bool keptWithPassword = false,
    }) => MakeOrderRequest.tryCreate(
      type: type,
      currency: RobosatsCurrency.fromId(currencyId) ?? fail('currency'),
      amount: amount ?? FixedOrderAmount(fiat(150)),
      paymentMethod: paymentMethod,
      premium: Premium.tryCreate(premium) ?? fail('premium'),
      publicDuration: publicDuration,
      escrowDuration: escrowDuration,
      bondSize: BondSize.tryCreate(bondSize) ?? fail('bond'),
      description: description,
      location: location,
      password: password,
      keptWithPassword: keptWithPassword,
    );

    test('the reference client\'s defaults make a request', () {
      final made = request() ?? fail('request');
      expect(made.type, OrderType.buy);
      expect(made.currency.code, 'EUR');
      expect(made.amount, FixedOrderAmount(fiat(150)));
      expect(made.paymentMethod, 'SEPA Revolut');
      expect(made.premium.percent, 1.5);
      expect(made.publicDuration, const Duration(seconds: 86340));
      expect(made.escrowDuration, const Duration(seconds: 10800));
      expect(made.bondSize.percent, 3);
      expect(made.description, isNull);
      expect(made, request());
      expect(made.hashCode, request()?.hashCode);
      expect(made, isNot(request(premium: 1.25)));
      expect(made, isNot(request(description: 'Cash')));
    });

    test('any currency but bitcoin, the currency of swaps', () {
      expect(request(currencyId: 1000), isNull);
      for (final id in [1, 2, 78, 300]) {
        expect(request(currencyId: id)?.currency.id, id);
      }
    });

    test('an amount above 0 and below 10^10, with at most 8 decimals', () {
      for (final value in [
        150.0,
        0.00000001,
        0.12345678,
        9999999999.0,
        1234567.89,
      ]) {
        expect(
          request(amount: FixedOrderAmount(fiat(value))),
          isNotNull,
          reason: '$value',
        );
      }
      for (final value in [1e10, 1e12, 0.000000001, 0.123456789, 1.5e-9]) {
        expect(
          request(amount: FixedOrderAmount(fiat(value))),
          isNull,
          reason: '$value',
        );
      }
    });

    test(
      'a range from 1.5 to 15 times its minimum, the coordinator\'s nominal bounds, each bound a valid amount',
      () {
        for (final (min, max) in [
          (100.0, 150.0),
          (100.0, 1500.0),
          (100.0, 300.0),
          (0.1, 0.16),
          (0.1, 1.5),
        ]) {
          expect(
            request(amount: testRange(min, max)),
            isNotNull,
            reason: '$min-$max',
          );
        }
        for (final (min, max) in [
          (100.0, 149.99),
          (100.0, 100.0),
          (100.0, 1500.01),
          (100.0, 3000.0),
          (100.0, 1e10),
          (0.000000001, 0.000000002),
          // A bound that is no amount the coordinator stores, the ratio valid: the minimum, then the maximum.
          (100.000000001, 200.0),
          (100.0, 200.000000001),
          (1e9, 1e10),
        ]) {
          expect(
            request(amount: testRange(min, max)),
            isNull,
            reason: '$min-$max',
          );
        }
      },
    );

    test('a payment method of 1 to 70 code points of clean text', () {
      for (final text in [
        'SEPA',
        'Bizum Revolut Paypal Friends & Family',
        'Espèces F2F €',
        'x' * 70,
        // 70 code points, 140 UTF-16 units.
        '🐂' * 70,
        'not specified',
      ]) {
        expect(request(paymentMethod: text), isNotNull, reason: text);
      }
      for (final text in [
        '',
        'x' * 71,
        '🐂' * 71,
        ' SEPA',
        'SEPA ',
        '\u00a0SEPA',
        'SEPA\u3000',
        'SEPA\tRevolut',
        'SEPA\nRevolut',
        'SEPA\u0000',
        'SEPA\u007f',
        'SEPA\u0085',
        'SEPA\u2028',
        'SEPA \u202eRevolut',
        'SEPA \u2066Revolut',
        'SEPA\u200f',
        'SEPA\ud800',
        // Since #181 (security review of #194): a text that shows as empty, or with an invisible character or a space other than U+0020.
        '\u200b',
        '\u200b\u200b',
        'SEPA\u200bRevolut',
        'SEPA\u00a0Revolut',
        'SEPA\u{e0041}',
        '\u0301',
        'SEPA\ue000',
      ]) {
        expect(request(paymentMethod: text), isNull, reason: jsonEncode(text));
      }
    });

    test('a premium above -100 and at most 999, with 2 decimals', () {
      for (final premium in [-99.99, -5.0, 0.0, 1.23, 999.0, 500.5]) {
        expect(request(premium: premium), isNotNull, reason: '$premium');
      }
      for (final premium in [-100.0, 999.01, 1000.0, 1.234, 0.001, -99.999]) {
        expect(request(premium: premium), isNull, reason: '$premium');
      }
    });

    test('a public duration of whole seconds, 10 minutes to 24 hours', () {
      for (final seconds in [600, 86340, 86400, 3600]) {
        expect(
          request(publicDuration: Duration(seconds: seconds)),
          isNotNull,
          reason: '$seconds',
        );
      }
      for (final duration in [
        const Duration(seconds: 599),
        const Duration(seconds: 598),
        const Duration(seconds: 86401),
        const Duration(seconds: 600, milliseconds: 500),
        const Duration(seconds: 3600, microseconds: 1),
        Duration.zero,
      ]) {
        expect(request(publicDuration: duration), isNull, reason: '$duration');
      }
    });

    test('an escrow duration of whole seconds, 30 minutes to 10 hours', () {
      for (final seconds in [1800, 3600, 10800, 36000]) {
        expect(
          request(escrowDuration: Duration(seconds: seconds)),
          isNotNull,
          reason: '$seconds',
        );
      }
      for (final duration in [
        const Duration(seconds: 1799),
        const Duration(seconds: 36001),
        const Duration(seconds: 1800, milliseconds: 1),
        Duration.zero,
      ]) {
        expect(request(escrowDuration: duration), isNull, reason: '$duration');
      }
    });

    test('a bond size of 2 to 15 % with at most 2 decimals', () {
      for (final bond in [2.0, 2.25, 3.0, 14.99, 15.0]) {
        expect(request(bondSize: bond), isNotNull, reason: '$bond');
      }
      for (final bond in [2.125, 3.001, 14.999]) {
        expect(request(bondSize: bond), isNull, reason: '$bond');
      }
    });

    test('a description: none, or 1 to 240 code points of clean text', () {
      for (final text in [
        'Revolut only, € please.',
        'x' * 240,
        '🐂' * 240,
        'کارت\u200cبه\u200cکارت',
      ]) {
        expect(request(description: text), isNotNull, reason: text);
      }
      for (final text in [
        '',
        'x' * 241,
        ' Revolut',
        'Revolut ',
        'line\nbreak',
        'tab\there',
        'nul\u0000',
        'bidi\u202e',
        'lone\udc00',
        // Since #181: a text that shows as empty, or with an invisible character.
        '\u200b',
        'hidden\u{e0041}\u{e0042}',
        'soft\u00adhyphen',
      ]) {
        expect(request(description: text), isNull, reason: jsonEncode(text));
      }
    });

    test('nothing of the request is printed but its side and currency', () {
      final made =
          request(
            amount: testRange(123.45, 543.21),
            description: 'Meet at the café',
            paymentMethod: 'Bizum',
            premium: 7.77,
            location: testLocation(),
            password: OrderPasswordHash.of('abc'),
          ) ??
          fail('request');
      expect('$made', 'MakeOrderRequest(buy, EUR)');
      expect('${made.passwordHash}', 'OrderPasswordHash(<redacted>)');
    });

    test(
      'a meeting point: none, or a latitude and a longitude within their bounds with at most 6 decimals (#189)',
      () {
        expect(request()?.location, isNull);
        for (final (lat, lon) in [
          (48.8566, 2.35221),
          (-33.8688, 151.209),
          (90.0, 180.0),
          (-90.0, -180.0),
          (0.000001, -0.000001),
          (12.345678, -123.456789),
          (0.0, 0.0),
        ]) {
          final location = OrderLocation.tryCreate(lat, lon) ?? fail('$lat');
          expect(request(location: location)?.location, location);
        }
        // More than 6 decimals: the coordinator's empty `400` (`decimal_places=6`, `api/models/order.py:148-167`).
        for (final (lat, lon) in [
          (48.8566001, 2.35221),
          (48.8566, 2.3522101),
          (0.0000001, 0.0),
          (1e-7, 1e-7),
        ]) {
          final location = OrderLocation.tryCreate(lat, lon) ?? fail('$lat');
          expect(request(location: location), isNull, reason: '$lat, $lon');
        }
        expect(OrderLocation.tryCreate(90.000001, 0), isNull);
        expect(OrderLocation.tryCreate(0, -180.000001), isNull);
        expect(OrderLocation.tryCreate(double.nan, 0), isNull);
        expect(
          request(location: testLocation()),
          isNot(request(location: testLocation(48.8566, 2.3522))),
        );
        expect(request(location: testLocation()), isNot(request()));
      },
    );

    test(
      'a password: its SHA-256 in lowercase hexadecimal, of the text as typed, none for an empty text (#189)',
      () {
        // The FIPS 180-2 vector of SHA-256, and texts of the reference's field: neither trimmed nor bounded.
        expect(
          OrderPasswordHash.of('abc')?.hex,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        expect(
          OrderPasswordHash.of('mot de passe é 🔑')?.hex,
          '3da7efd4406cc4f61fc3bd6243ed0f140cb7cccddaa3851b1d0aa6487c933882',
        );
        expect(
          OrderPasswordHash.of('  spaces  ')?.hex,
          '3294fa4c529bfcd6d2b5683a79ea6ca944a92bc2dd8b2601cb2427a6abd0ba04',
        );
        expect(OrderPasswordHash.of(''), isNull);
        expect(OrderPasswordHash.of('x' * 10000)?.hex, hasLength(64));
        final protected =
            request(password: OrderPasswordHash.of('abc')) ?? fail('request');
        expect(protected.hasPassword, isTrue);
        expect(protected.isSendable, isTrue);
        expect(request()?.hasPassword, isFalse);
        expect(request()?.isSendable, isTrue);
      },
    );

    test(
      'two requests of the same order are equal whatever the password\'s hash; what a device keeps says there is one and is never sendable',
      () {
        final one =
            request(password: OrderPasswordHash.of('one')) ?? fail('one');
        final two =
            request(password: OrderPasswordHash.of('two')) ?? fail('two');
        expect(one, two);
        expect(one.hashCode, two.hashCode);
        expect(one, isNot(request()));
        final kept = one.kept;
        expect(kept.passwordHash, isNull);
        expect(kept.hasPassword, isTrue);
        expect(kept.isSendable, isFalse);
        expect(kept, one);
        final restored = request(keptWithPassword: true) ?? fail('restored');
        expect(restored.hasPassword, isTrue);
        expect(restored.isSendable, isFalse);
        expect(restored, kept);
        expect(request()?.kept, request());
        expect(request()?.kept.isSendable, isTrue);
      },
    );
  });

  group('the request sent', () {
    test('the reference client\'s body, keys in its order', () async {
      serveJson(madeAnswer(testMakeRequest()));
      expectOk(await make());
      final request = transport.requests.single;
      expect(request.method, CoordinatorHttpMethod.post);
      expect(request.url.toString(), '${temple.testnet.onion}/api/make/');
      expect(request.headers, {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Token ${_us.tokenSha256Base91}',
      });
      expect(request.robot, _us.sessionKey);
      expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
      // `JSON.stringify` of the body of `Order.make` (`frontend/src/models/Order.model.ts:197-215`) for the form's attributes (`MakerForm.tsx:257-275`).
      // Then the signature of `make:{shortAlias}:{unix_ts}`, last, as the reference's `{ ...body, signature }` (GHSA-22q8-9ghc-jg3h).
      expect(
        unsignedBody(request.body, signedMake),
        '{"type":0,"currency":2,"amount":150,"has_range":false,'
        '"min_amount":null,"max_amount":null,"payment_method":"SEPA Revolut",'
        '"is_explicit":false,"premium":1.5,"satoshis":null,'
        '"public_duration":86340,"escrow_duration":10800,"bond_size":3,'
        '"latitude":null,"longitude":null,"password":null,"description":null}',
      );
    });

    test('a sell order sends type 1', () async {
      final body = await bodyOf(testMakeRequest(type: OrderType.sell));
      expect(body['type'], 1);
    });

    test('a range sends no amount, its bounds and has_range', () async {
      final body = await bodyOf(testMakeRequest(amount: testRange(100, 300)));
      expect(body['amount'], isNull);
      expect(body.containsKey('amount'), isTrue);
      expect(body['has_range'], isTrue);
      expect(body['min_amount'], 100);
      expect(body['max_amount'], 300);
    });

    test(
      'decimals are sent as they are written, integers without any',
      () async {
        final body = await bodyOf(
          testMakeRequest(
            amount: FixedOrderAmount(fiat(0.00000001)),
            premium: -99.99,
            bondSize: 2.25,
            currencyId: 300,
          ),
        );
        expect(body['amount'], 1e-8);
        expect(body['premium'], -99.99);
        expect(body['bond_size'], 2.25);
        expect(body['currency'], 300);
        final zero = await bodyOf(testMakeRequest(premium: 0));
        expect(zero['premium'], 0);
        expect(zero['premium'], isA<int>());
      },
    );

    test('the durations in seconds, the description as written', () async {
      final body = await bodyOf(
        testMakeRequest(
          publicDuration: const Duration(minutes: 10),
          escrowDuration: const Duration(hours: 10),
          description: 'Revolut only, € please.',
        ),
      );
      expect(body['public_duration'], 600);
      expect(body['escrow_duration'], 36000);
      expect(body['description'], 'Revolut only, € please.');
    });

    test('no price in sats, no meeting point, no password', () async {
      final body = await bodyOf(testMakeRequest());
      for (final key in [
        'satoshis',
        'latitude',
        'longitude',
        'password',
        'description',
      ]) {
        expect(body.containsKey(key), isTrue, reason: key);
        expect(body[key], isNull, reason: key);
      }
      expect(body['is_explicit'], isFalse);
      expect(body.keys, hasLength(17));
    });

    test(
      'a meeting point and a password\'s SHA-256, never the password (#189)',
      () async {
        final body = await bodyOf(
          testMakeRequest(
            location: testLocation(-33.8688, 151.209),
            password: OrderPasswordHash.of('abc'),
          ),
        );
        expect(body['latitude'], -33.8688);
        expect(body['longitude'], 151.209);
        expect(
          body['password'],
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        );
        expect(body.keys, hasLength(17));
        final text = utf8.decode(transport.requests.single.body ?? const []);
        expect(
          text,
          contains(
            '"latitude":-33.8688,"longitude":151.209,'
            '"password":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",',
          ),
        );
        expect(text, isNot(contains('"abc"')));
        // A meeting point on whole degrees is written as the reference's `Number` writes it.
        final whole = await bodyOf(
          testMakeRequest(location: testLocation(48, -3)),
        );
        expect(whole['latitude'], 48);
        expect(whole['latitude'], isA<int>());
        expect(whole['longitude'], -3);
      },
    );

    test(
      'a request kept without its password\'s hash is refused, nothing sent (#189)',
      () async {
        final kept = testMakeRequest(
          password: OrderPasswordHash.of('abc'),
        ).kept;
        final failure = expectErr(await make(kept));
        expect(failure, isA<OrderActionRefused>());
        expect(
          failure.cause,
          isA<OrderRequestRefused>().having((f) => f.errorCode, 'code', null),
        );
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'a coordinator with no instance on the network: nothing sent',
      () async {
        // Freeport has no testnet instance in the federation list.
        final freeport = coordinatorNamed('freeport');
        expect(freeport.origins(_testnet).onion, isNull);
        final failure = expectErr(
          await client.makeOrder(
            freeport,
            _testnet,
            identity: _us,
            key: interopUnlockedKey,
            request: testMakeRequest(),
          ),
        );
        expect(failure, isA<OrderActionRefused>());
        expect(failure.cause, isA<CoordinatorNotOnNetwork>());
        expect(transport.requests, isEmpty);
      },
    );
  });

  group('the answer 201', () {
    test('the order made, with the terms sent', () async {
      final request = testMakeRequest();
      serveJson(madeAnswer(request));
      final made = expectOk(await make(request));
      expect(made.id, testOrderId);
      expect(made.coordinator, temple);
      expect(made.network, _testnet);
      expect(made.request, request);
      expect(made.createdAt, DateTime.utc(2026, 11, 16, 10, 0, 0, 0, 12));
      expect(made.expiresAt, DateTime.utc(2026, 11, 16, 10, 5, 0, 0, 3));
      expect('$made', 'MadeOrder(#42)');
    });

    test('a range, a sell order, a description, any other terms', () async {
      for (final request in [
        testMakeRequest(amount: testRange(100, 300)),
        testMakeRequest(amount: testRange(0.12345678, 1.5)),
        testMakeRequest(type: OrderType.sell, currencyId: 1),
        testMakeRequest(description: 'Revolut only, € please.'),
        testMakeRequest(premium: -99.99, bondSize: 15),
        testMakeRequest(premium: 999, bondSize: 2.25),
        testMakeRequest(paymentMethod: '🐂' * 70),
        testMakeRequest(escrowDuration: const Duration(minutes: 30)),
        testMakeRequest(amount: FixedOrderAmount(fiat(9999999999.5))),
      ]) {
        serveJson(madeAnswer(request));
        expect(expectOk(await make(request)).request, request);
      }
    });

    test('the maker and the taker are read as nothing', () async {
      for (final changes in [
        {'maker': 'someone', 'taker': 3},
        {'maker': null, 'taker': null},
        {'maker': -1},
      ]) {
        serveJson(madeAnswer(testMakeRequest(), changes: changes));
        expectOk(await make());
      }
    });

    Future<void> unknown(
      Map<String, Object?> changes,
      String field, {
      MakeOrderRequest? request,
    }) async {
      final sent = request ?? testMakeRequest();
      serveJson(madeAnswer(sent, changes: changes));
      final failure = expectErr(await make(sent));
      expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$changes');
      expect(failure.cause, malformed(field), reason: '$changes');
    }

    test('a field missing: the outcome is unknown', () async {
      for (final key in [
        'id',
        'status',
        'created_at',
        'expires_at',
        'type',
        'currency',
        'amount',
        'has_range',
        'min_amount',
        'max_amount',
        'payment_method',
        'is_explicit',
        'premium',
        'satoshis',
        'escrow_duration',
        'bond_size',
        'latitude',
        'longitude',
      ]) {
        serveJson(madeAnswer(testMakeRequest())..remove(key));
        final failure = expectErr(await make());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: key);
        expect(failure.cause, malformed(key), reason: key);
      }
    });

    test('an id that is no order number', () async {
      for (final id in [0, -1, -42, 1.5, '42', true, (1 << 53) + 1]) {
        await unknown({'id': id}, 'id');
      }
    });

    test('a status other than 0', () async {
      for (final status in [1, 2, 3, 5, 18, '0', -1, 19]) {
        await unknown({'status': status}, 'status');
      }
    });

    test(
      'dates that are not dates, or a deadline not after the creation',
      () async {
        await unknown({'created_at': 'yesterday'}, 'created_at');
        await unknown({'created_at': '2026-11-16T10:00:00'}, 'created_at');
        await unknown({'expires_at': 1763287500}, 'expires_at');
        await unknown({
          'expires_at': '2026-11-16T10:00:00.000012Z',
        }, 'expires_at');
        await unknown({'expires_at': '2026-11-16T09:59:59Z'}, 'expires_at');
      },
    );

    test('a term other than the one sent', () async {
      await unknown({'type': 1}, 'type');
      await unknown({'type': '0'}, 'type');
      await unknown({'currency': 1}, 'currency');
      await unknown({'currency': '2'}, 'currency');
      await unknown({'amount': '150.00000001'}, 'amount');
      await unknown({'amount': '1500.00000000'}, 'amount');
      // The serializer's decimals are strings: a number is not what it writes.
      await unknown({'amount': 150}, 'amount');
      await unknown({'has_range': true}, 'has_range');
      await unknown({'has_range': 'false'}, 'has_range');
      await unknown({'min_amount': '100.00000000'}, 'min_amount');
      await unknown({'max_amount': '300.00000000'}, 'max_amount');
      await unknown({'payment_method': 'SEPA'}, 'payment_method');
      await unknown({'payment_method': 'SEPA Revolut '}, 'payment_method');
      await unknown({'payment_method': 'sepa revolut'}, 'payment_method');
      await unknown({'payment_method': 7}, 'payment_method');
      await unknown({'is_explicit': true}, 'is_explicit');
      await unknown({'is_explicit': 0}, 'is_explicit');
      await unknown({'premium': '1.49'}, 'premium');
      await unknown({'premium': '0.00'}, 'premium');
      await unknown({'premium': 1.5}, 'premium');
      await unknown({'satoshis': 164414}, 'satoshis');
      await unknown({'escrow_duration': 10799}, 'escrow_duration');
      await unknown({'escrow_duration': '10800'}, 'escrow_duration');
      await unknown({'bond_size': '3.01'}, 'bond_size');
      await unknown({'bond_size': 3}, 'bond_size');
      await unknown({'latitude': '48.856600'}, 'latitude');
      await unknown({'longitude': '2.352200'}, 'longitude');
    });

    test(
      'a meeting point answered as sent, its texts of 6 decimals; any other is unknown (#189)',
      () async {
        final placed = testMakeRequest(
          location: testLocation(48.8566, 2.35221),
        );
        serveJson(madeAnswer(placed));
        expect(madeAnswer(placed)['latitude'], '48.856600');
        expect(madeAnswer(placed)['longitude'], '2.352210');
        expect(expectOk(await make(placed)).request, placed);
        Future<void> answered(
          Map<String, Object?> changes,
          String field,
        ) async {
          serveJson(madeAnswer(placed, changes: changes));
          expect(
            expectErr(await make(placed)).cause,
            malformed(field),
            reason: '$changes',
          );
        }

        await answered({'latitude': '48.856601'}, 'latitude');
        await answered({'longitude': '2.352200'}, 'longitude');
        await answered({'latitude': 48.8566}, 'latitude');
        await answered({'latitude': '90.000001'}, 'latitude');
        serveJson({...madeAnswer(placed), 'latitude': null});
        expect(expectErr(await make(placed)).cause, malformed('latitude'));
        serveJson({...madeAnswer(placed), 'longitude': null});
        expect(expectErr(await make(placed)).cause, malformed('longitude'));
        final protected = testMakeRequest(
          password: OrderPasswordHash.of('abc'),
        );
        serveJson(madeAnswer(protected));
        expect(expectOk(await make(protected)).request.hasPassword, isTrue);
      },
    );

    test('a range answered as another range, or as a fixed amount', () async {
      final range = testMakeRequest(amount: testRange(100, 300));
      await unknown(
        {'min_amount': '100.50000000'},
        'min_amount',
        request: range,
      );
      await unknown(
        {'max_amount': '299.00000000'},
        'max_amount',
        request: range,
      );
      await unknown({'max_amount': null}, 'max_amount', request: range);
      await unknown({'min_amount': null}, 'min_amount', request: range);
      await unknown({'amount': '100.00000000'}, 'amount', request: range);
      await unknown({'has_range': false}, 'has_range', request: range);
    });

    test('a body that is no order', () async {
      for (final body in [<Object?>[], 'order', 42, null]) {
        serveJson(body);
        final failure = expectErr(await make());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$body');
        expect(failure.cause, malformed('order'), reason: '$body');
      }
    });

    test('the right body with a status other than 201', () async {
      for (final status in [200, 202, 204, 302]) {
        serveJson(madeAnswer(testMakeRequest()), statusCode: status);
        final failure = expectErr(await make());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$status');
        expect(
          failure.cause,
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
      }
    });

    test(
      'a valid 201 larger than the bound is an outcome unknown, never a made order',
      () async {
        final request = testMakeRequest();
        // The answer of `madeAnswer` with a field the parser ignores, padded to exactly [CoordinatorReadBounds.orderBytes] bytes, then one more.
        List<int> padded(int size) {
          final bare = utf8.encode(
            jsonEncode(madeAnswer(request, changes: {'padding': ''})),
          );
          return utf8.encode(
            jsonEncode(
              madeAnswer(
                request,
                changes: {'padding': 'x' * (size - bare.length)},
              ),
            ),
          );
        }

        final atBound = padded(CoordinatorReadBounds.orderBytes);
        expect(atBound, hasLength(CoordinatorReadBounds.orderBytes));
        serve(Ok(rawResponse(atBound, statusCode: 201)));
        expect(expectOk(await make(request)).request, request);

        final over = padded(CoordinatorReadBounds.orderBytes + 1);
        expect(over, hasLength(CoordinatorReadBounds.orderBytes + 1));
        transport.requests.clear();
        serve(Ok(rawResponse(over, statusCode: 201)));
        final failure = expectErr(await make(request));
        expect(failure, isA<OrderActionOutcomeUnknown>());
        expect(failure.cause, isA<CoordinatorResponseTooLarge>());
        expect(transport.requests, hasLength(1));
      },
    );

    test('a 201 that is not JSON', () async {
      serve(
        Ok(
          rawResponse(
            utf8.encode('<html></html>'),
            statusCode: 201,
            contentType: 'text/html',
          ),
        ),
      );
      final failure = expectErr(await make());
      expect(failure, isA<OrderActionOutcomeUnknown>());
      expect(failure.cause, isA<CoordinatorNotJson>());
    });
  });

  group('refusals', () {
    Future<OrderActionFailure> answered(int code, int httpStatus) async {
      serveJson(orderError(code), statusCode: httpStatus);
      transport.requests.clear();
      final failure = expectErr(await make());
      expect(transport.requests, hasLength(1));
      return failure;
    }

    // The codes `MakerView.post` answers before it makes anything, each with the HTTP status the reference gives it.
    final codes = <int, (int, Matcher)>{
      1000: (409, isA<RobotAlreadyMaker>()),
      1001: (409, isA<RobotAlreadyTaker>()),
      1002: (409, isA<RobotAlreadyTaking>()),
      1003: (409, isA<RobotPayoutPending>()),
      1004: (400, _size(OrderSizeRefusal.tooBig)),
      1005: (400, _size(OrderSizeRefusal.tooSmall)),
      1006: (400, _size(OrderSizeRefusal.rangeTooNarrow)),
      1007: (400, _size(OrderSizeRefusal.rangeMaximumTooBig)),
      1008: (400, _size(OrderSizeRefusal.rangeMinimumTooSmall)),
      1009: (400, _size(OrderSizeRefusal.rangeTooWide)),
      1010: (400, isA<OrderLocationRefused>()),
      1036: (400, isA<RobotCredentialsRejected>()),
      1037: (400, isA<OrderBookFull>()),
      1038: (400, _request(1038)),
      1039: (400, _request(1039)),
      7000: (400, isA<RobotCredentialsRejected>()),
      7001: (400, isA<RobotUnknown>()),
      7003: (400, isA<RobotCredentialsRejected>()),
    };

    for (final MapEntry(key: code, value: (status, matcher)) in codes.entries) {
      test('error $code: refused, nothing made', () async {
        final failure = await answered(code, status);
        expect(failure, isA<OrderActionRefused>());
        expect(failure.cause, matcher);
        // Read on any `4xx`, as every refusal of an order.
        for (final other in [400, 403, 404, 409]) {
          final again = await answered(code, other);
          expect(again, isA<OrderActionRefused>(), reason: '$other');
          expect(again.cause, matcher, reason: '$other');
        }
      });
    }

    test('each size code is its own reason', () {
      expect(
        {for (final reason in OrderSizeRefusal.values) reason.code},
        {1004, 1005, 1006, 1007, 1008, 1009},
      );
    });

    test('the empty 400 of the form check: refused', () async {
      serve(Ok(rawResponse(const [], statusCode: 400, contentType: null)));
      final failure = expectErr(await make());
      expect(failure, isA<OrderActionRefused>());
      expect(failure.cause, _request(null));
    });

    test('401 and 403 of the authentication: refused', () async {
      for (final status in [401, 403]) {
        serveJson({'detail': 'Not authenticated.'}, statusCode: status);
        final failure = expectErr(await make());
        expect(failure, isA<OrderActionRefused>(), reason: '$status');
        expect(failure.cause, isA<RobotCredentialsRejected>());
        serve(Ok(rawResponse(const [], statusCode: status, contentType: null)));
        expect(expectErr(await make()), isA<OrderActionRefused>());
      }
    });

    test('a code the reference never answers to a make: unknown', () async {
      for (final code in [
        1011,
        1012,
        1020,
        1021,
        1022,
        1032,
        1033,
        1042,
        1043,
        1044,
        1047,
        1049,
        7002,
        7004,
        9999,
      ]) {
        final failure = await answered(code, 400);
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
      }
    });

    test('a code on a status that is not 4xx is the status alone', () async {
      for (final status in [500, 502, 503, 200, 302]) {
        final failure = await answered(1037, status);
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$status');
        expect(
          failure.cause,
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
      }
    });

    test(
      'nothing sent: refused; maybe made: unknown, never sent again',
      () async {
        serve(const Err(CoordinatorTransportBusy()));
        final busy = expectErr(await make());
        expect(busy, isA<OrderActionRefused>());
        expect(busy.cause, isA<CoordinatorTransportBusy>());
        for (final answer
            in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
              const Err(CoordinatorTimedOut()),
              const Err(CoordinatorUnreachable()),
              const Err(CoordinatorTransportFailed()),
              const Err(CoordinatorResponseTooLarge()),
              Ok(rawResponse(utf8.encode('not json'), statusCode: 201)),
              Ok(
                rawResponse(
                  utf8.encode('<html>Bad gateway</html>'),
                  statusCode: 400,
                  contentType: 'text/html',
                ),
              ),
              Ok(rawResponse(utf8.encode('{}'), statusCode: 500)),
              Ok(
                rawResponse(
                  List.filled(CoordinatorReadBounds.orderBytes + 1, 0x20),
                  statusCode: 201,
                ),
              ),
            ]) {
          // A coordinator that would answer a second request: the client never sends one.
          var calls = 0;
          transport
            ..requests.clear()
            ..route(temple, _testnet, '/api/make/', (_) async {
              calls++;
              return calls == 1
                  ? answer
                  : Ok(
                      jsonResponse(
                        madeAnswer(testMakeRequest()),
                        statusCode: 201,
                      ),
                    );
            });
          final failure = expectErr(await make());
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$answer');
          expect(transport.requests, hasLength(1), reason: '$answer');
        }
      },
    );

    test('a transport that throws: the outcome is unknown', () async {
      for (final thrown in <Object>[
        StateError('broken'),
        Exception('broken'),
      ]) {
        transport.route(
          temple,
          _testnet,
          '/api/make/',
          (_) async => throw thrown,
        );
        final failure = expectErr(await make());
        expect(failure, isA<OrderActionOutcomeUnknown>());
        expect(failure.cause, isA<CoordinatorTransportFailed>());
      }
    });

    test('no text of the coordinator is kept', () async {
      serveJson(
        orderError(1004, 'Your order is too big. It is worth 600000 Sats now'),
        statusCode: 400,
      );
      final failure = expectErr(await make());
      expect('$failure ${failure.cause}', isNot(contains('600000')));
    });
  });

  group('the maker\'s reads of its order', () {
    // Each answer of `OrderView.get` to the maker (`api/views.py:226-528`) written out field by field from the view's code, for the order of `madeAnswer`: a buy order of 150 EUR made by this robot, with no meeting point and no description.
    final base = {
      'id': testOrderId,
      'status': 0,
      'created_at': '2026-11-16T10:00:00.000012Z',
      'expires_at': '2026-11-16T10:05:00.000003Z',
      'type': 0,
      'currency': 2,
      'amount': '150.00000000',
      'has_range': false,
      'min_amount': null,
      'max_amount': null,
      'payment_method': 'SEPA Revolut',
      'is_explicit': false,
      'premium': '1.50',
      'satoshis': null,
      'maker': 7,
      'taker': null,
      'escrow_duration': 10800,
      'bond_size': '3.00',
      'latitude': null,
      'longitude': null,
      // `:253-256`
      'is_maker': true,
      'is_taker': false,
      'is_participant': true,
      'has_password': false,
      // `:262`, `Order.t_to_expire(0)`: `EXP_MAKER_BOND_INVOICE`.
      'total_secs_exp': 300,
      // `:277-285`
      'maker_nick': _us.nickname,
      'maker_hash_id': _us.hashId.hex,
      'maker_nostr_pubkey': _us.nostrKeyPair().publicKeyHex,
      'description': null,
      'maker_status': 'Active',
      // `:312-324`: the participant's fields; the raw coordinates, `None`.
      'is_buyer': true,
      'is_seller': false,
      'taker_nick': 'None',
      'status_message': 'Waiting for maker bond',
      'is_fiat_sent': false,
      'is_disputed': false,
      'ur_nick': _us.nickname,
      'satoshis_now': 164414,
      // `:328-344`: no bond yet at the first read, an unpaid one later.
      'maker_locked': false,
      'taker_locked': false,
      'escrow_locked': false,
    };
    // `:373-379`, `Logics.gen_maker_hold_invoice`: 3 % of the order's sats (`api/logics.py:1266-1268`).
    final at0 = {
      ...base,
      'bond_invoice': testBondInvoice,
      'bond_satoshis': 4932,
    };
    // Public: `publish_order` set the deadline to the creation plus the public duration (`api/logics.py:1205-1227`); `:302-309` adds the price now.
    final at1 = {
      ...base,
      'status': 1,
      'expires_at': '2026-11-17T09:59:00.000012Z',
      'total_secs_exp': 86340,
      'status_message': 'Public',
      'price_now': 91234.0,
      'premium_now': 1.5,
      'maker_locked': true,
    };
    // Paused: `t_to_expire(2)` is 0, the deadline unchanged (`api/models/order.py:316`).
    final at2 = {
      ...at1,
      'status': 2,
      'total_secs_exp': 0,
      'status_message': 'Paused',
    };
    // Expired at 0 (`Logics.order_expires`, `api/logics.py:329-338`), then `:490-509`: the renewal's fields and the reason; the price now still, 5 being between 1 and 6.
    final at5bond = {
      ...base,
      'status': 5,
      'total_secs_exp': 0,
      'status_message': 'Expired',
      'price_now': 91234.0,
      'premium_now': 1.5,
      'public_duration': 86340,
      'bond_size': '3.00',
      'expiry_reason': 1,
      'expiry_message': 'Maker bond not locked',
    };
    // Expired public, untaken (`api/logics.py:340-358`): the bond returned, so not locked.
    final at5untaken = {
      ...at5bond,
      'expires_at': '2026-11-17T09:59:00.000012Z',
      'expiry_reason': 0,
      'expiry_message': 'Expired not taken',
    };

    void serveRead(Object? json, {int statusCode = 200}) => transport.answer(
      temple,
      _testnet,
      '/api/order/',
      Ok(jsonResponse(json, statusCode: statusCode)),
    );

    Future<Result<CoordinatorOrder, CoordinatorFailure>> fetch() => client
        .fetchOrder(temple, _testnet, identity: _us, orderId: testOrderId);

    test('at 0: the maker bond to lock, and nothing of a taker', () async {
      serveRead(at0);
      final order = expectOk(await fetch());
      expect(order.status, CoordinatorOrderStatus.waitingForMakerBond);
      expect(order.isMaker, isTrue);
      expect(order.isTaker, isFalse);
      expect(order.maker, _us.hashId);
      expect(order.taker, isNull);
      expect(order.isBuyer, isTrue);
      expect(order.bondInvoice?.invoice, testBondInvoice);
      expect(order.bondInvoice?.satoshis, Sats.fromInt(4932));
      expect(order.makerBondLocked, isFalse);
      expect(order.priceNow, isNull);
      expect(order.location, isNull);
      expect(order.description, isNull);
      expect(order.stepDuration, const Duration(seconds: 300));
      expect(order.expiresAt, DateTime.utc(2026, 11, 16, 10, 5, 0, 0, 3));
      expect(order.premium?.percent, 1.5);
      expect(order.bondSize.percent, 3);
      expect(order.escrowDuration, const Duration(seconds: 10800));
    });

    test('at 1 and 2: public, then paused, the bond locked', () async {
      for (final (answer, status, step) in [
        (at1, CoordinatorOrderStatus.public, 86340),
        (at2, CoordinatorOrderStatus.paused, 0),
      ]) {
        serveRead(answer);
        final order = expectOk(await fetch());
        expect(order.status, status);
        expect(order.isMaker, isTrue);
        expect(order.makerBondLocked, isTrue);
        expect(order.bondInvoice, isNull);
        expect(order.priceNow, 91234.0);
        expect(order.premiumNow?.percent, 1.5);
        expect(order.satoshisNow, Sats.fromInt(164414));
        expect(order.stepDuration, Duration(seconds: step));
        expect(order.expiresAt, DateTime.utc(2026, 11, 17, 9, 59, 0, 0, 12));
      }
    });

    test('at 5: why it expired, and the renewal\'s fields', () async {
      for (final (answer, reason) in [
        (at5bond, OrderExpiryReason.makerBondNotLocked),
        (at5untaken, OrderExpiryReason.notTaken),
      ]) {
        serveRead(answer);
        final order = expectOk(await fetch());
        expect(order.status, CoordinatorOrderStatus.expired);
        expect(order.expiryReason, reason);
        expect(order.publicDuration, const Duration(seconds: 86340));
        expect(order.bondSize.percent, 3);
        expect(order.makerBondLocked, isFalse);
        expect(order.bondInvoice, isNull);
      }
    });

    test(
      'a bond invoice to the maker anywhere but at 0 is malformed',
      () async {
        for (final answer in [at1, at2, at5bond]) {
          serveRead({
            ...answer,
            'bond_invoice': testBondInvoice,
            'bond_satoshis': 4932,
          });
          expect(expectErr(await fetch()), malformed('bond_invoice'));
        }
      },
    );

    test('status 3 is never the maker\'s', () async {
      serveRead({...at1, 'status': 3});
      expect(expectErr(await fetch()), malformed('status'));
    });

    test('a read that names another robot as the maker is malformed', () async {
      serveRead({
        ...at0,
        'maker_hash_id': interopPeerIdentity.hashId.hex,
        'maker_nick': interopPeerIdentity.nickname,
      });
      expect(expectErr(await fetch()), malformed('maker_hash_id'));
    });

    test(
      'error 1022: the time to lock the bond is over, the order expired',
      () async {
        // `Logics.gen_maker_hold_invoice`, `api/logics.py:1254-1256`: `new_error(1022)` with a `400`, once.
        serveRead(
          orderError(
            1022,
            'Invoice expired. You did not confirm publishing the order in time. Make a new order.',
          ),
          statusCode: 400,
        );
        expect(expectErr(await fetch()), isA<OrderMakerBondExpired>());
        // The next read: the order at 5, reason 1.
        serveRead(at5bond);
        expect(
          expectOk(await fetch()).expiryReason,
          OrderExpiryReason.makerBondNotLocked,
        );
      },
    );

    test(
      '1022 after an action is an outcome unknown, never a refusal',
      () async {
        transport.answer(
          temple,
          _testnet,
          '/api/order/',
          Ok(jsonResponse(orderError(1022), statusCode: 400)),
        );
        final cancel = expectErr(
          await client.cancelOrder(
            identity: _us,
            key: interopUnlockedKey,
            lastRead: readOrder(at0),
          ),
        );
        expect(cancel, isA<OrderActionOutcomeUnknown>());
        expect(cancel.cause, isA<OrderMakerBondExpired>());
      },
    );
  });
}

Matcher _size(OrderSizeRefusal reason) =>
    isA<OrderSizeRefused>().having((f) => f.reason, 'reason', reason);

Matcher _request(int? code) =>
    isA<OrderRequestRefused>().having((f) => f.errorCode, 'errorCode', code);
