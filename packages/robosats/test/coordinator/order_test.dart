import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;
const _orderId = 42;

/// This device's robot, the taker of the tests: index 0 of the example Garage Key of the RoboSats repository, a token published there and never a secret.
final _us = interopIdentity;

/// The peer, the maker of the tests: index 1 of the same example key.
final _peer = interopPeerIdentity;

/// Fake hold invoices, built by the test: a coordinator's are about 400 characters of bech32.
final _bondInvoice = 'lntb30u1pfakebondinvoice${'q' * 360}';
final _escrowInvoice = 'lntb1m1pfakeescrowinvoice${'p' * 360}';

/// Who this device's robot is to the order of an answer.
enum _Role { maker, taker, preTaker, outsider }

/// The answer of `OrderView.get` (`api/views.py:226-528`, commit ff1998c) about order [_orderId] to this device's robot, built step by step as the view builds it, for an order in [status] (the stored one: a pre-take is asked with status 1).
///
/// [buyer] says whether this device's robot buys bitcoin, so the order's type follows from it and [role]; [range] makes a range order of 100-300 EUR taken for 150.5.
/// [bondsLocked] and [escrowLocked] are what the hold invoices of the coordinator say; [changes] is applied last, a `null` value removing its key.
Map<String, Object?> _answer(
  int status, {
  _Role role = _Role.taker,
  bool buyer = true,
  bool range = false,
  bool password = false,
  bool bondsLocked = true,
  bool escrowLocked = true,
  Map<String, Object?> changes = const {},
}) {
  final isMaker = role == _Role.maker;
  final isTaker = role == _Role.taker || role == _Role.preTaker;
  final makerIdentity = isMaker ? _us : _peer;
  final takerIdentity = switch (role) {
    _Role.maker => status >= 6 ? _peer : null,
    _Role.taker => _us,
    _ => null,
  };
  // The maker buys when this robot buys as maker, or sells to this robot as taker.
  final makerBuys = isMaker == buyer;
  final taken = takerIdentity != null;
  final data = <String, Object?>{
    'id': _orderId,
    'status': status,
    'created_at': '2026-11-13T08:00:00.123456Z',
    'expires_at': '2026-11-13T11:00:00Z',
    'type': makerBuys ? 0 : 1,
    'currency': 2,
    'amount': range ? (taken ? '150.50000000' : null) : '150.00000000',
    'has_range': range,
    'min_amount': range ? '100.00000000' : null,
    'max_amount': range ? '300.00000000' : null,
    'payment_method': 'SEPA Revolut',
    'is_explicit': false,
    'premium': '1.50',
    'satoshis': null,
    'maker': 7,
    'taker': taken ? 8 : null,
    'escrow_duration': 10799,
    'bond_size': '3.00',
    'latitude': null,
    'longitude': null,
    'is_maker': isMaker,
    'is_taker': isTaker,
    'is_participant': isMaker || isTaker,
    'has_password': password,
    'total_secs_exp': _stepSeconds(status),
    'maker_nick': makerIdentity.nickname,
    'maker_hash_id': makerIdentity.hashId.hex,
    'maker_nostr_pubkey': makerIdentity.nostrKeyPair().publicKeyHex,
    'description': 'Revolut only, € please.',
    'maker_status': 'Active',
    if (taken) 'taker_status': 'Seen recently',
  };
  if (role == _Role.outsider) {
    data
      ..['price_now'] = 91234.5
      ..['premium_now'] = 1.5
      ..['satoshis_now'] = 164414;
    if (password) {
      data
        ..['latitude'] = null
        ..['longitude'] = null
        ..['description'] = null;
    }
    return _apply(data, changes);
  }
  if (status >= 1 && status < 6) {
    data
      ..['price_now'] = 91234.5
      ..['premium_now'] = 1.5;
  }
  data
    ..['is_buyer'] = buyer
    ..['is_seller'] = !buyer
    ..['taker_nick'] = takerIdentity?.nickname ?? 'None';
  if (takerIdentity != null) {
    data
      ..['taker_hash_id'] = takerIdentity.hashId.hex
      ..['taker_nostr_pubkey'] = takerIdentity.nostrKeyPair().publicKeyHex;
  }
  data
    ..['status_message'] = 'Some label'
    ..['is_fiat_sent'] = status == 10
    ..['is_disputed'] = status == 11 || status >= 16
    ..['ur_nick'] = _us.nickname
    ..['satoshis_now'] = 164414
    ..['maker_locked'] = status >= 1 && status != 5
    ..['taker_locked'] = status >= 6 && bondsLocked
    ..['escrow_locked'] = (status == 8 || status >= 9) && escrowLocked;
  if ([6, 7, 8, 12, 10, 11, 13, 14, 15].contains(status) && bondsLocked) {
    data['trade_satoshis'] = buyer ? 164126 : 164702;
  }
  if (status == 0 && isMaker) {
    data
      ..['bond_invoice'] = _bondInvoice
      ..['bond_satoshis'] = 4932
      ..['expires_at'] = '2026-11-13T08:05:00.654321Z';
  } else if (status == 1 && role == _Role.preTaker) {
    data
      ..['status'] = 3
      ..['total_secs_exp'] = 150
      ..['amount'] = range ? '150.50000000' : '150.00000000'
      ..['bond_invoice'] = _bondInvoice
      ..['bond_satoshis'] = 4932
      ..['expires_at'] = '2026-11-13T08:02:30.000001Z';
  } else if (!buyer && (status == 6 || status == 7)) {
    if (bondsLocked) {
      data
        ..['escrow_invoice'] = _escrowInvoice
        ..['escrow_satoshis'] = 164702;
    }
  } else if (buyer && (status == 6 || status == 8)) {
    if (bondsLocked) {
      data
        ..['invoice_amount'] = 164126
        ..['swap_allowed'] = false
        ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
    }
  } else if ([8, 9, 10].contains(status)) {
    if (bondsLocked && escrowLocked) data['asked_for_cancel'] = false;
    data['chat_last_index'] = 3;
  } else if (status == 11) {
    data['statement_submitted'] = false;
  } else if (status == 15 && buyer) {
    data
      ..['retries'] = 2
      ..['next_retry_time'] = '2026-11-13T09:10:00.5Z'
      ..['failure_reason'] =
          'All possible routes were tried and failed permanently. Or there were no routes to the destination at all.'
      ..['invoice_expired'] = true
      ..['trade_satoshis'] = 164126;
  } else if ([5, 14, 13, 15].contains(status)) {
    data
      ..['public_duration'] = 86399
      ..['bond_size'] = '3.00';
    if (status != 5) data.addAll(_summaries(buyer: buyer, isMaker: isMaker));
    if (status == 5) {
      data
        ..['expiry_reason'] = 2
        ..['expiry_message'] = 'Escrow not locked';
    }
  }
  return _apply(data, changes);
}

Map<String, Object?> _apply(
  Map<String, Object?> data,
  Map<String, Object?> changes,
) {
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
  return data;
}

/// `Order.t_to_expire` with the defaults of the code (`api/models/order.py:310-339`).
int _stepSeconds(int status) => switch (status) {
  0 => 300,
  1 => 86399,
  3 => 150,
  6 || 7 || 8 => 10799,
  9 || 10 => 86400,
  11 => 86400,
  >= 13 => 8640000,
  _ => 0,
};

/// The summaries of `Logics.summarize_trade` (`api/logics.py:2047-2139`) for a Lightning payout.
Map<String, Object?> _summaries({required bool buyer, required bool isMaker}) {
  Map<String, Object?> side({required bool isBuyer, required bool ofMaker}) => {
    'trade_fee_percent': ofMaker ? 0.00025 : 0.00175,
    'bond_size_sats': 4932,
    'bond_size_percent': 3.0,
    'is_buyer': isBuyer,
    if (isBuyer) ...{
      'sent_fiat': 150.0,
      'received_sats': 164126,
      'payment_hash': 'f' * 64,
      'preimage': 'processing',
      'trade_fee_sats': 288,
    } else ...{
      'sent_sats': 164702,
      'received_fiat': 150.0,
      'trade_fee_sats': 288,
    },
  };
  final makerBuys = isMaker == buyer;
  return {
    'maker_summary': side(isBuyer: makerBuys, ofMaker: true),
    'taker_summary': side(isBuyer: !makerBuys, ofMaker: false),
    'platform_summary': {
      'contract_exchange_rate': 91234.56,
      'contract_timestamp': '2026-11-13T08:03:00Z',
      'contract_total_time': 1234.5,
      'routing_budget_sats': 0,
      'trade_revenue_sats': 576,
    },
  };
}

/// The error body of `new_error` (`api/errors.py:120-138`).
Map<String, Object?> _error(int code, [String message = 'Some text.']) => {
  'error_code': code,
  'bad_request': message,
};

/// The short body of a cancel that ended the order (`api/views.py:604-615`).
Map<String, Object?> _ended(int status) => {
  'id': _orderId,
  'status': status,
  'type': 1,
  'expires_at': '2026-11-13T11:00:00Z',
  'bad_request': 'This order has been cancelled',
};

void main() {
  final temple = coordinatorNamed('temple');
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    transport = FakeCoordinatorTransport();
    client = CoordinatorClient(transport, clock: () => recordedAt);
  });

  void serve(Result<CoordinatorResponse, CoordinatorTransportFailure> answer) =>
      transport.answer(temple, _testnet, '/api/order/', answer);

  void serveJson(Object? json, {int statusCode = 200}) =>
      serve(Ok(jsonResponse(json, statusCode: statusCode)));

  Future<Result<CoordinatorOrder, CoordinatorFailure>> fetch({
    int orderId = _orderId,
  }) => client.fetchOrder(temple, _testnet, identity: _us, orderId: orderId);

  Future<Result<TakeOrderOutcome, CoordinatorFailure>> take({
    FiatAmount? amount,
    String? password,
  }) => client.takeOrder(
    temple,
    _testnet,
    identity: _us,
    orderId: _orderId,
    amount: amount,
    password: password,
  );

  Future<Result<CancelOrderOutcome, CoordinatorFailure>> cancel({
    CoordinatorOrderStatus? onlyIfStatus,
  }) => client.cancelOrder(
    temple,
    _testnet,
    identity: _us,
    orderId: _orderId,
    onlyIfStatus: onlyIfStatus,
  );

  /// The order read from [answer].
  Future<CoordinatorOrder> read(Map<String, Object?> answer) async {
    serveJson(answer);
    return expectOk(await fetch());
  }

  /// The failure of reading [answer].
  Future<CoordinatorFailure> refuse(Object? answer) async {
    serveJson(answer);
    return expectErr(await fetch());
  }

  Matcher malformed(String field) => isA<CoordinatorResponseMalformed>().having(
    (f) => f.field,
    'field',
    field,
  );

  group('the requests', () {
    test('a read is a GET with the robot\'s short header', () async {
      serveJson(_answer(9));
      await fetch();

      final request = transport.requests.single;
      expect(request.method, CoordinatorHttpMethod.get);
      expect(
        request.url.toString(),
        '${temple.testnet.onion}/api/order/?order_id=42',
      );
      expect(request.headers, {
        'Accept': 'application/json',
        'Authorization': 'Token ${_us.tokenSha256Base91}',
      });
      expect(request.body, isNull);
      expect(request.robot, _us.sessionKey);
      expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
    });

    // What the reference client sends (`frontend/src/models/Order.model.ts:233-262`, `services/api/ApiWebClient/index.ts:57-69`): `JSON.stringify` of the action, with the short header.
    final postHeaders = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Token ${_us.tokenSha256Base91}',
    };

    void expectPost(String body) {
      final request = transport.requests.single;
      expect(request.method, CoordinatorHttpMethod.post);
      expect(
        request.url.toString(),
        '${temple.testnet.onion}/api/order/?order_id=42',
      );
      expect(request.headers, postHeaders);
      expect(request.body, utf8.encode(body));
      expect(request.robot, _us.sessionKey);
      expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
    }

    test(
      'a take of a fixed order sends the amount 0, as the reference',
      () async {
        // `TakeButton.tsx:50` keeps the amount empty for a fixed order, and `Number('')` is 0.
        serveJson(_answer(1, role: _Role.preTaker));
        await take();
        expectPost('{"action":"take","amount":0}');
      },
    );

    test('a take of a range sends the amount as a JSON number', () async {
      for (final (value, wire) in [
        (150.0, '150'),
        (150.5, '150.5'),
        (0.0015, '0.0015'),
        (1e-7, '1e-7'),
        (1234567.12345678, '1234567.12345678'),
      ]) {
        transport.requests.clear();
        serveJson(_answer(1, role: _Role.preTaker, range: true));
        await take(amount: FiatAmount.tryCreate(value));
        expectPost('{"action":"take","amount":$wire}');
      }
    });

    test('a take with a password sends its SHA-256, before the amount', () async {
      serveJson(_answer(1, role: _Role.preTaker, password: true));
      // The SHA-256 of "abc", from FIPS 180-2.
      await take(password: 'abc');
      expectPost(
        '{"action":"take","password":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","amount":0}',
      );
    });

    test('a take with an empty password sends none', () async {
      serveJson(_answer(1, role: _Role.preTaker));
      await take(password: '');
      expectPost('{"action":"take","amount":0}');
    });

    test('a password is hashed as UTF-8 text', () async {
      serveJson(_answer(1, role: _Role.preTaker, password: true));
      await take(password: 'café 🔑');
      final body =
          jsonDecode(utf8.decode(transport.requests.single.body ?? []))
              as Map<String, Object?>;
      expect(
        body['password'],
        sha256.convert(utf8.encode('café 🔑')).toString(),
      );
      expect(body['password'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a cancel sends the action alone, as the reference taker', () async {
      serveJson(_answer(1, role: _Role.outsider));
      await cancel();
      expectPost('{"action":"cancel"}');
    });

    test('a cancel with a status sends it as a number', () async {
      serveJson(_answer(1, role: _Role.outsider));
      await cancel(onlyIfStatus: CoordinatorOrderStatus.public);
      expectPost('{"action":"cancel","cancel_status":1}');
    });

    test(
      'a cancel never guards on the status a coordinator never stores',
      () async {
        // The pre-take is stored as public: a guard of 3 would always be refused with 1020.
        await expectLater(
          cancel(onlyIfStatus: CoordinatorOrderStatus.waitingForTakerBond),
          throwsArgumentError,
        );
        expect(transport.requests, isEmpty);
      },
    );

    test('an order number out of range is not sent', () async {
      for (final orderId in [0, -1, (1 << 53) + 1]) {
        await expectLater(
          client.fetchOrder(temple, _testnet, identity: _us, orderId: orderId),
          throwsArgumentError,
        );
        await expectLater(
          client.takeOrder(temple, _testnet, identity: _us, orderId: orderId),
          throwsArgumentError,
        );
        await expectLater(
          client.cancelOrder(temple, _testnet, identity: _us, orderId: orderId),
          throwsArgumentError,
        );
      }
      expect(transport.requests, isEmpty);
    });

    test('every POST names its robot and carries its credential', () async {
      serveJson(_answer(1, role: _Role.preTaker));
      await take();
      serveJson(_answer(1, role: _Role.outsider));
      await cancel();
      for (final request in transport.requests) {
        expect(request.method, CoordinatorHttpMethod.post);
        expect(request.robot, _us.sessionKey);
        expect(request.headers['Authorization'], startsWith('Token '));
        expect(
          request.headers.values.join(' '),
          isNot(contains(_us.token.reveal())),
        );
        expect('${request.url}', isNot(contains(_us.token.reveal())));
      }
    });

    test(
      'nothing is sent to a coordinator that is not on the network',
      () async {
        final bazaar = coordinatorNamed('bazaar');
        final results = [
          await client.fetchOrder(
            bazaar,
            _testnet,
            identity: _us,
            orderId: _orderId,
          ),
          await client.takeOrder(
            bazaar,
            _testnet,
            identity: _us,
            orderId: _orderId,
          ),
          await client.cancelOrder(
            bazaar,
            _testnet,
            identity: _us,
            orderId: _orderId,
          ),
        ];
        for (final result in results) {
          expect(expectErr(result), isA<CoordinatorNotOnNetwork>());
        }
        expect(transport.requests, isEmpty);
      },
    );
  });

  group('a POST is never sent twice', () {
    final failures = <CoordinatorTransportFailure>[
      const CoordinatorTimedOut(),
      const CoordinatorUnreachable(),
      const CoordinatorTransportFailed(),
      const CoordinatorTransportBusy(),
      const CoordinatorResponseTooLarge(),
    ];

    for (final failure in failures) {
      test('by the client, after ${failure.runtimeType}', () async {
        serve(Err(failure));
        final took = await take();
        final cancelled = await cancel();

        // The action may have reached the coordinator: only the next read tells.
        expect(expectErr(took), same(failure));
        expect(expectErr(cancelled), same(failure));
        expect(transport.requests, hasLength(2));
        expect(
          transport.requests.map((request) => request.method),
          everyElement(CoordinatorHttpMethod.post),
        );
      });
    }

    test('by the client, after a transport that throws', () async {
      transport.route(
        temple,
        _testnet,
        '/api/order/',
        (_) async => throw const FormatException('broken adapter'),
      );
      expect(expectErr(await take()), isA<CoordinatorTransportFailed>());
      expect(transport.requests, hasLength(1));
    });

    test('by the client, after a server error or a refusal', () async {
      for (final answer in [
        rawResponse(
          utf8.encode('<html>Bad gateway</html>'),
          statusCode: 502,
          contentType: 'text/html',
        ),
        jsonResponse(
          _error(1012, 'You need to wait 60 seconds to take an order'),
          statusCode: 403,
        ),
        rawResponse(const [], statusCode: 400),
      ]) {
        transport.requests.clear();
        serve(Ok(answer));
        await take();
        await cancel();
        expect(transport.requests, hasLength(2));
      }
    });

    test('by the client, after a timeout that comes late', () async {
      final answered = Completer<void>();
      transport.route(temple, _testnet, '/api/order/', (_) async {
        await answered.future;
        return const Err(CoordinatorTimedOut());
      });
      final pending = take();
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests, hasLength(1));
      answered.complete();
      expect(expectErr(await pending), isA<CoordinatorTimedOut>());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(transport.requests, hasLength(1));
    });
  });

  group('every status, both roles', () {
    for (final status in [
      0,
      1,
      2,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      13,
      14,
      15,
      16,
      17,
      18,
    ]) {
      for (final role in [_Role.maker, _Role.taker]) {
        for (final buyer in [true, false]) {
          for (final range in [false, true]) {
            // The taker of an order is never shown status 0 to 2: before the take it is no participant.
            if (role == _Role.taker && status <= 2) continue;
            final label =
                'status $status, ${role.name}, ${buyer ? 'buyer' : 'seller'}, ${range ? 'range' : 'fixed'}';
            test(label, () async {
              final order = await read(
                _answer(status, role: role, buyer: buyer, range: range),
              );
              expect(order.id, _orderId);
              expect(order.status.wire, status);
              expect(order.coordinator, temple);
              expect(order.isMaker, role == _Role.maker);
              expect(order.isTaker, role == _Role.taker);
              expect(order.isParticipant, isTrue);
              expect(order.isBuyer, buyer);
              expect(order.isSeller, !buyer);
              expect(
                order.type,
                (role == _Role.maker) == buyer ? OrderType.buy : OrderType.sell,
              );
              expect(order.currency.code, 'EUR');
              expect(
                order.maker,
                role == _Role.maker ? _us.hashId : _peer.hashId,
              );
              final taken = role == _Role.taker || status >= 6;
              expect(
                order.taker,
                !taken
                    ? isNull
                    : role == _Role.taker
                    ? _us.hashId
                    : _peer.hashId,
              );
              if (range) {
                expect(order.amount, isA<RangeOrderAmount>());
                expect(order.takenAmount?.value, taken ? 150.5 : isNull);
              } else {
                expect(
                  order.amount,
                  FixedOrderAmount(FiatAmount.tryCreate(150) ?? fail('amount')),
                );
                expect(order.takenAmount, isNull);
              }
              expect(
                order.stepDuration,
                Duration(seconds: _stepSeconds(status)),
              );
              expect(order.escrowDuration, const Duration(seconds: 10799));
              expect(order.bondSize.percent, 3);
              expect(order.paymentMethods.text, 'SEPA Revolut');
              expect(order.description, 'Revolut only, € please.');
              expect(order.makerActivity, MakerActivity.active);
              expect(
                order.makerNostrPublicKeyHex,
                matches(RegExp(r'^[0-9a-f]{64}$')),
              );
              expect(
                order.bondInvoice != null,
                status == 0 && role == _Role.maker,
              );
              final seller = !buyer;
              expect(
                order.escrowInvoice?.invoice,
                seller && (status == 6 || status == 7)
                    ? _escrowInvoice
                    : isNull,
              );
              expect(
                order.payoutInvoiceAmount,
                buyer && (status == 6 || status == 8)
                    ? Sats.fromInt(164126)
                    : isNull,
              );
              expect(
                order.chatLastIndex,
                [9, 10].contains(status) || (status == 8 && !buyer)
                    ? 3
                    : isNull,
              );
              expect(order.statementSubmitted, status == 11 ? isFalse : isNull);
              expect(
                order.expiryReason,
                status == 5 ? OrderExpiryReason.escrowNotLocked : isNull,
              );
              expect(
                order.publicDuration,
                [5, 13, 14].contains(status) || (status == 15 && !buyer)
                    ? const Duration(seconds: 86399)
                    : isNull,
              );
              final summarised =
                  [13, 14].contains(status) || (status == 15 && !buyer);
              expect(order.summary?.isBuyer, summarised ? buyer : isNull);
              expect(order.payoutRetries, status == 15 && buyer ? 2 : isNull);
            });
          }
        }
      }
    }

    test(
      'the pre-taker sees status 3, its bond and the pre-take\'s amount',
      () async {
        final order = await read(_answer(1, role: _Role.preTaker, range: true));
        expect(order.status, CoordinatorOrderStatus.waitingForTakerBond);
        expect(order.isTaker, isTrue);
        expect(order.taker, isNull, reason: 'a pre-taker is not the taker yet');
        expect(order.takenAmount?.value, 150.5);
        expect(order.stepDuration, const Duration(seconds: 150));
        expect(order.expiresAt, DateTime.utc(2026, 11, 13, 8, 2, 30, 0, 1));
        expect(order.bondInvoice?.invoice, _bondInvoice);
        expect(order.bondInvoice?.satoshis, Sats.fromInt(4932));
        expect(order.priceNow, 91234.5);
        expect(order.premiumNow?.percent, 1.5);
        expect(order.satoshisNow, Sats.fromInt(164414));
      },
    );

    test('a robot that is no participant sees a public order', () async {
      final order = await read(_answer(1, role: _Role.outsider));
      expect(order.status, CoordinatorOrderStatus.public);
      expect(order.isParticipant, isFalse);
      expect(order.isBuyer, isNull);
      expect(order.taker, isNull);
      expect(order.makerBondLocked, isNull);
      expect(order.satoshisNow, Sats.fromInt(164414));
    });

    test(
      'a password order hides its place and description from others',
      () async {
        final order = await read(
          _answer(1, role: _Role.outsider, password: true),
        );
        expect(order.hasPassword, isTrue);
        expect(order.description, isNull);
        expect(order.location, isNull);
      },
    );

    test(
      'a buyer whose payout failed sees its retries and the reason',
      () async {
        final order = await read(_answer(15));
        expect(order.payoutRetries, 2);
        expect(
          order.nextPayoutRetry,
          DateTime.utc(2026, 11, 13, 9, 10, 0, 500),
        );
        expect(order.payoutFailureReason, PayoutFailureReason.noRoute);
        expect(order.payoutInvoiceExpired, isTrue);
        expect(order.tradeSatoshis, Sats.fromInt(164126));
      },
    );

    test('an unknown payout failure label is read, never kept', () async {
      final order = await read(
        _answer(
          15,
          changes: {'failure_reason': 'Call 555-0100 and send us your seed'},
        ),
      );
      expect(order.payoutFailureReason, PayoutFailureReason.unspecified);
      expect('$order', isNot(contains('555')));
    });

    test('every reason a swap is refused is read, never kept', () async {
      for (final (text, refusal) in [
        (
          'Order amount is smaller than the minimum swap available of 20000 Sats',
          SwapRefusal.belowMinimum,
        ),
        (
          'Order amount is bigger than the maximum swap available of 500000 Sats',
          SwapRefusal.aboveMaximum,
        ),
        ('On-the-fly submarine swaps are disabled', SwapRefusal.disabled),
        (
          'Not enough onchain liquidity available to offer a swap',
          SwapRefusal.noLiquidity,
        ),
        ('Something else entirely', SwapRefusal.unspecified),
      ]) {
        final order = await read(
          _answer(6, changes: {'swap_failure_reason': text}),
        );
        expect(order.swapAllowed, isFalse);
        expect(order.swapRefusal, refusal);
      }
    });

    test('a buyer offered a swap gets the rates', () async {
      final order = await read(
        _answer(
          6,
          changes: {
            'swap_allowed': true,
            'swap_failure_reason': null,
            'suggested_mining_fee_rate': 12.5,
            'swap_fee_rate': 1.25,
          },
        ),
      );
      expect(order.swapAllowed, isTrue);
      expect(order.swapRefusal, isNull);
      expect(order.suggestedMiningFeeRate, 12.5);
      expect(order.swapFeeRate, 1.25);
    });

    test('the chat flags of a collaborative cancel', () async {
      final asked = await read(_answer(9, changes: {'asked_for_cancel': true}));
      expect(asked.askedToCancel, isTrue);
      expect(asked.peerAskedToCancel, isNull);
      final pending = await read(
        _answer(9, changes: {'asked_for_cancel': null, 'pending_cancel': true}),
      );
      expect(pending.peerAskedToCancel, isTrue);
    });

    test('the summary of a successful buyer, its own side only', () async {
      final order = await read(_answer(14));
      final summary = order.summary ?? fail('no summary');
      expect(summary.isBuyer, isTrue);
      expect(summary.fiatAmount, 150);
      expect(summary.receivedSats, Sats.fromInt(164126));
      expect(summary.sentSats, isNull);
      expect(summary.tradeFeeSats, 288);
      expect(summary.tradeFeeFraction, 0.00175);
      expect(summary.bondSats, Sats.fromInt(4932));
      expect(summary.bondPercent, 3);
      expect(summary.isSwap, isFalse);
      expect(summary.contractExchangeRate, 91234.56);
      expect(summary.contractTimestamp, DateTime.utc(2026, 11, 13, 8, 3));
      expect(summary.contractTotalTime, const Duration(milliseconds: 1234500));
      expect(summary.routingBudgetSats, Sats.zero);
    });

    test('the summary of a successful seller', () async {
      final summary = (await read(_answer(14, buyer: false))).summary;
      expect(summary?.isBuyer, isFalse);
      expect(summary?.sentSats, Sats.fromInt(164702));
      expect(summary?.fiatAmount, 150);
    });

    test('the on-chain payout of a successful buyer', () async {
      final queued = await read(
        _answer(
          14,
          changes: {
            'num_satoshis': 164126,
            'sent_satoshis': 160000,
            'network': 'testnet',
            'tx_queued': true,
            'address': 'tb1qfakeaddressbuiltbythetest0000000000000',
          },
        ),
      );
      final payout = queued.onchainPayout ?? fail('no payout');
      expect(payout.sentSatoshis, Sats.fromInt(160000));
      expect(payout.numSatoshis, Sats.fromInt(164126));
      expect(payout.network, RobosatsNetwork.testnet);
      expect(payout.queued, isTrue);
      expect(payout.txid, isNull);
      expect(payout.address, 'tb1qfakeaddressbuiltbythetest0000000000000');

      final sent = await read(
        _answer(
          14,
          changes: {
            'num_satoshis': 164126,
            'sent_satoshis': 160000,
            'network': 'mainnet',
            'txid': 'a' * 64,
          },
        ),
      );
      expect(sent.onchainPayout?.txid, 'a' * 64);
      expect(sent.onchainPayout?.queued, isFalse);
      expect(sent.onchainPayout?.network, RobosatsNetwork.mainnet);
    });

    test('a penalty is read as a date', () async {
      final order = await read(
        _answer(
          1,
          role: _Role.outsider,
          changes: {'penalty': '2026-11-13T08:01:00.250Z'},
        ),
      );
      expect(order.penaltyUntil, DateTime.utc(2026, 11, 13, 8, 1, 0, 250));
    });

    test('statuses are numbered as the order model numbers them', () {
      expect(CoordinatorOrderStatus.values, hasLength(19));
      for (final (index, status) in CoordinatorOrderStatus.values.indexed) {
        expect(status.wire, index);
        expect(CoordinatorOrderStatus.fromWire(index), status);
      }
      expect(CoordinatorOrderStatus.fromWire(-1), isNull);
      expect(CoordinatorOrderStatus.fromWire(19), isNull);
      for (final (index, reason) in OrderExpiryReason.values.indexed) {
        expect(reason.wire, index);
      }
    });
  });

  group('Nostr keys', () {
    test('"None", empty and missing are no key', () async {
      for (final value in ['None', '']) {
        final order = await read(
          _answer(
            9,
            changes: {'maker_nostr_pubkey': value, 'taker_nostr_pubkey': value},
          ),
        );
        expect(order.makerNostrPublicKeyHex, isNull);
        expect(order.takerNostrPublicKeyHex, isNull);
      }
      final order = await read(
        _answer(
          9,
          changes: {'maker_nostr_pubkey': null, 'taker_nostr_pubkey': null},
        ),
      );
      expect(order.makerNostrPublicKeyHex, isNull);
    });

    test(
      'the placeholder of a coordinator that lost a key is read as is',
      () async {
        final order = await read(
          _answer(9, changes: {'maker_nostr_pubkey': '0' * 64}),
        );
        expect(order.makerNostrPublicKeyHex, '0' * 64);
      },
    );

    test('anything else rejects the answer', () async {
      for (final key in ['maker_nostr_pubkey', 'taker_nostr_pubkey']) {
        for (final value in <Object>[
          'NONE',
          'none',
          'A' * 64,
          'a' * 63,
          'a' * 65,
          'g' * 64,
          42,
          true,
          <Object?>[],
          ' ${'a' * 63}',
        ]) {
          expect(
            await refuse(_answer(9, changes: {key: value})),
            malformed(key),
            reason: '$key: $value',
          );
        }
      }
    });
  });

  group('the nicknames', () {
    test('must be the ones the hash ids give', () async {
      expect(
        await refuse(_answer(9, changes: {'maker_nick': _us.nickname})),
        malformed('maker_nick'),
      );
      expect(
        await refuse(_answer(9, changes: {'taker_nick': _peer.nickname})),
        malformed('taker_nick'),
      );
    });

    test('with no taker, the taker\'s is "None" or missing', () async {
      final preTake = await read(_answer(1, role: _Role.preTaker));
      expect(preTake.taker, isNull);
      expect(
        await refuse(
          _answer(1, role: _Role.preTaker, changes: {'taker_nick': 'Someone'}),
        ),
        malformed('taker_nick'),
      );
      expect(
        (await read(
          _answer(1, role: _Role.preTaker, changes: {'taker_nick': null}),
        )).taker,
        isNull,
      );
    });

    test('a hash id that gives no robot rejects the answer', () async {
      for (final key in ['maker_hash_id', 'taker_hash_id']) {
        for (final value in <Object>['A' * 64, 'a' * 63, 'zz', 7]) {
          expect(
            await refuse(_answer(9, changes: {key: value})),
            malformed(key),
            reason: '$key: $value',
          );
        }
      }
    });
  });

  group('bounds', () {
    /// For each field, values at its bounds or of odd but valid forms, each accepted.
    final valid = <String, List<Object?>>{
      'id': [_orderId],
      'total_secs_exp': [0, 400 * 24 * 3600],
      'escrow_duration': [1800, 36000],
      'bond_size': ['2', '15', '2.00', '15.00'],
      'premium': ['-100', '999', '-100.00', null],
      'amount': ['0.00000001', '9999999999.99999999'],
      'currency': [1, 1000],
      'payment_method': ['', 'é' * 70, '😀' * 70],
      'description': [null, '', 'é' * 240, '😀' * 240],
      'satoshis_now': [0, 2100000000000000, null],
      'trade_satoshis': [0, 2100000000000000, null],
      'price_now': [0, 1e300, null],
      'premium_now': [-100, 1e6, null],
      'public_duration': [0, 172800, null],
      'chat_last_index': [0, 1 << 53, null],
      'penalty': [
        '2020-01-01T00:00:00Z',
        '2100-12-31T23:59:59.999999+14:00',
        null,
      ],
      'maker_status': ['Unknown label', 'x' * 60000, null],
      'expires_at': ['2026-11-13T11:00:00+01:00', '2026-11-13T11:00:00.1Z'],
    };

    for (final MapEntry(key: field, value: values) in valid.entries) {
      test('$field is read at its bounds', () async {
        for (final value in values) {
          final answer = _answer(9);
          answer[field] = value;
          serveJson(answer);
          expect(
            expectOk(await fetch()),
            isA<CoordinatorOrder>(),
            reason: '$field: $value',
          );
        }
      });
    }

    test(
      'an invoice of 2,000 characters is read, one more rejects the answer',
      () async {
        final at = 'lntb${'q' * 1996}';
        final order = await read(
          _answer(6, buyer: false, changes: {'escrow_invoice': at}),
        );
        expect(order.escrowInvoice?.invoice, hasLength(2000));
        expect(
          await refuse(
            _answer(6, buyer: false, changes: {'escrow_invoice': '${at}q'}),
          ),
          malformed('escrow_invoice'),
        );
        expect(
          await refuse(
            _answer(
              1,
              role: _Role.preTaker,
              changes: {'bond_invoice': 'lntb${'q' * 1997}'},
            ),
          ),
          malformed('bond_invoice'),
        );
      },
    );

    test('a range taken for its very bounds is read', () async {
      for (final amount in ['100.00000000', '300.00000000']) {
        final order = await read(
          _answer(9, range: true, changes: {'amount': amount}),
        );
        expect(order.takenAmount?.value, double.parse(amount));
      }
    });

    /// For each field, the values that must reject the whole answer, named by that field.
    final invalid = <String, List<Object?>>{
      'id': ['42', 42.0, 0, -1, (1 << 53) + 1, true, 43],
      'status': [-1, 19, 3.0, '9', null, 1000],
      'created_at': [
        null,
        'yesterday',
        '2026-11-13T08:00:00',
        '2026-13-13T08:00:00Z',
        '2019-12-31T23:59:59Z',
        '2026-11-13T25:00:00Z',
        1731484800,
      ],
      'expires_at': [
        null,
        '2026-02-30T08:00:00Z',
        '2026-11-13 11:00:00Z',
        '2101-01-01T00:00:00Z',
        'x' * 41,
      ],
      'total_secs_exp': [null, -1, 400 * 24 * 3600 + 1, 1.5, '150'],
      'type': [null, 2, -1, '0', 0.0],
      'currency': [null, 0, 65536, 999, '2'],
      'has_range': [null, 'false', 0],
      'amount': [
        null,
        150,
        '1e2',
        ' 150',
        '+150',
        'NaN',
        '0',
        '-5',
        '10000000000.1',
        '0.0000000000001',
      ],
      'payment_method': [null, 42, 'x' * 71, '😀' * 71],
      'description': [42, 'x' * 241, '😀' * 241, <Object?>[]],
      'is_explicit': [null, 'true'],
      'premium': [-1.5, '-100.01', '1000', 'abc', '1e3'],
      'escrow_duration': [null, 1799, 36001, '10799', 10799.5],
      'bond_size': [null, '1.99', '15.01', 3, '3%'],
      'latitude': ['91', 48.8, 'north'],
      'longitude': ['181', 2.35],
      'has_password': [null, 1],
      'is_maker': [null, 'false'],
      'is_taker': [null, 0],
      'is_participant': [null, 'true'],
      'is_buyer': ['true', 1],
      'is_seller': ['false'],
      'maker_hash_id': [null, 'a' * 65, 7],
      'maker_nick': ['x' * 65, 42],
      'taker_nick': ['x' * 65, 42],
      'maker_status': [42, true],
      'penalty': ['2026-11-13', 42, 'soon'],
      'price_now': [-1, '91234.5', double.nan.toString()],
      'premium_now': [-100.5, '1.5'],
      'satoshis_now': [-1, 2100000000000001, 1.5, '164414'],
      'is_fiat_sent': ['false'],
      'is_disputed': [0],
      'maker_locked': ['true'],
      'taker_locked': [1],
      'escrow_locked': ['yes'],
      'trade_satoshis': [-1, 2100000000000001, '164126'],
      'chat_last_index': [-1, (1 << 53) + 1, '3'],
      'public_duration': [-1, 172801, '86399'],
      'statement_submitted': ['no'],
      'retries': [-1, 32768, '2'],
      'next_retry_time': ['later', 7],
      'failure_reason': [42, 'x' * 501],
      'invoice_expired': ['true'],
      'expiry_reason': [-1, 5, '2'],
      'pending_cancel': ['true'],
      'asked_for_cancel': [1],
      'invoice_amount': [-1, '164126', 2100000000000001],
      'swap_allowed': ['false'],
      'swap_failure_reason': [42, 'x' * 501],
      'suggested_mining_fee_rate': [-1, 1e7, '12'],
      'swap_fee_rate': [-0.1, 100.5, '1'],
      'taker_summary': ['summary', 42, <Object?>[]],
      'platform_summary': [
        'summary',
        <Object?>[1],
      ],
      'sent_satoshis': [-1, '5'],
      'num_satoshis': [-1, '5'],
      'network': ['regtest', 'Mainnet', 7],
      'txid': ['A' * 64, 'a' * 63, 'g' * 64, 64],
      'tx_queued': ['true'],
      'address': ['tb1q address', 'x' * 101, 'tb1q\u202Eevil', '', 5],
    };

    for (final MapEntry(key: field, value: values) in invalid.entries) {
      test('$field rejects the whole answer when invalid', () async {
        for (final value in values) {
          // Status 14 for a buyer with a summary, the on-chain payout's fields sent together, so that each field is the first invalid one.
          final answer = _answer(
            14,
            changes: {
              'num_satoshis': 164126,
              'sent_satoshis': 160000,
              'network': 'testnet',
              'txid': 'b' * 64,
            },
          );
          answer[field] = value;
          serveJson(answer);
          final failure = expectErr(await fetch());
          final expected = field == 'id' && value == 43 ? 'id' : field;
          expect(failure, malformed(expected), reason: '$field: $value');
        }
      });
    }

    test('a field of the own summary is named with its object', () async {
      final answer = _answer(14);
      (answer['taker_summary'] as Map<String, Object?>)['sent_fiat'] = '150';
      expect(await refuse(answer), malformed('taker_summary.sent_fiat'));
      final platform = _answer(14);
      (platform['platform_summary']
              as Map<String, Object?>)['contract_timestamp'] =
          'then';
      expect(
        await refuse(platform),
        malformed('platform_summary.contract_timestamp'),
      );
      final maker = _answer(14, role: _Role.maker);
      (maker['maker_summary'] as Map<String, Object?>)['is_buyer'] = null;
      expect(await refuse(maker), malformed('maker_summary.is_buyer'));
    });

    test('the peer\'s summary is not read', () async {
      final answer = _answer(14);
      answer['maker_summary'] = 'not an object at all';
      expect((await read(answer)).summary?.isBuyer, isTrue);
    });

    test('a hold invoice comes with its amount', () async {
      expect(
        await refuse(
          _answer(1, role: _Role.preTaker, changes: {'bond_satoshis': null}),
        ),
        malformed('bond_satoshis'),
      );
      expect(
        await refuse(
          _answer(1, role: _Role.preTaker, changes: {'bond_invoice': null}),
        ),
        malformed('bond_invoice'),
      );
      expect(
        await refuse(
          _answer(6, buyer: false, changes: {'escrow_satoshis': '164702'}),
        ),
        malformed('escrow_satoshis'),
      );
    });

    test(
      'an invoice of anything but visible ASCII rejects the answer',
      () async {
        for (final invoice in [
          '',
          ' lntb1',
          'lntb 1',
          'lntb1\n',
          'lntb1é',
          'lntb1\u202E',
          'lntb1\u0000',
        ]) {
          expect(
            await refuse(
              _answer(
                1,
                role: _Role.preTaker,
                changes: {'bond_invoice': invoice},
              ),
            ),
            malformed('bond_invoice'),
            reason: jsonEncode(invoice),
          );
        }
      },
    );

    test('a range order needs its bounds, a fixed one its amount', () async {
      expect(
        await refuse(_answer(9, range: true, changes: {'min_amount': null})),
        malformed('min_amount'),
      );
      expect(
        await refuse(_answer(9, range: true, changes: {'max_amount': null})),
        malformed('max_amount'),
      );
      expect(
        await refuse(
          _answer(9, range: true, changes: {'min_amount': '400.00000000'}),
        ),
        malformed('max_amount'),
      );
      expect(
        await refuse(_answer(9, changes: {'amount': null})),
        malformed('amount'),
      );
    });

    test('an order priced in sats needs its sats', () async {
      expect(
        await refuse(_answer(9, changes: {'is_explicit': true})),
        malformed('satoshis'),
      );
      final order = await read(
        _answer(
          9,
          changes: {
            'is_explicit': true,
            'satoshis': 164414,
            'premium': '1500.00',
          },
        ),
      );
      expect(order.explicitSatoshis, Sats.fromInt(164414));
      expect(order.premium?.percent, 1500);
      expect(
        await refuse(_answer(9, changes: {'premium': '1000.00'})),
        malformed('premium'),
      );
    });

    test('a place needs both coordinates', () async {
      expect(
        await refuse(_answer(9, changes: {'latitude': '48.85660000'})),
        malformed('longitude'),
      );
      final order = await read(
        _answer(
          9,
          changes: {'latitude': '48.85660000', 'longitude': '2.35220000'},
        ),
      );
      expect(order.location?.latitude, 48.8566);
    });

    test('an on-chain payout needs its amounts and a known network', () async {
      expect(
        await refuse(_answer(14, changes: {'num_satoshis': 5})),
        malformed('sent_satoshis'),
      );
      expect(
        await refuse(_answer(14, changes: {'sent_satoshis': 5})),
        malformed('num_satoshis'),
      );
      expect(
        await refuse(
          _answer(14, changes: {'sent_satoshis': 5, 'num_satoshis': 6}),
        ),
        malformed('network'),
      );
    });

    test('the maker\'s text is cleaned for display', () async {
      final order = await read(
        _answer(
          9,
          changes: {
            'description': 'Pay\u202Eto\u0000 me\nhere',
            'payment_method': 'SEPA\u200F Revolut\t',
          },
        ),
      );
      expect(order.description, 'Payto me here');
      expect(order.paymentMethods.text, 'SEPA Revolut ');
    });

    test('unknown fields are ignored, whatever they hold', () async {
      final order = await read(
        _answer(
          9,
          changes: {
            'webhook_api_key': 'not-read',
            'new_field': {'deep': List.filled(1000, 'x' * 10)},
            'status_message': 42,
            'ur_nick': <Object?>[],
            'expiry_message': null,
            'maker': 'not an id',
            'taker': <String, Object?>{},
            'created_by': '😀' * 1000,
          },
        ),
      );
      expect(order.status, CoordinatorOrderStatus.sendingFiat);
    });

    test('a body that is not an object is malformed', () async {
      for (final body in <Object?>[
        null,
        42,
        'order',
        <Object?>[],
        <Object?>[_answer(9)],
        true,
      ]) {
        expect(await refuse(body), malformed('order'), reason: '$body');
      }
    });

    test('deeply nested garbage is malformed, not a crash', () async {
      serve(Ok(rawResponse(utf8.encode('${'[' * 30000}${']' * 30000}'))));
      expect(expectErr(await fetch()), malformed('order'));
      serve(
        Ok(rawResponse(utf8.encode('{"a":${'{"a":' * 10000}1${'}' * 10000}}'))),
      );
      expect(expectErr(await fetch()), isA<CoordinatorResponseMalformed>());
    });

    test('a body larger than the bound is refused unread', () async {
      final huge = List<int>.filled(10 * 1024 * 1024, 0x20);
      serve(Ok(rawResponse(huge)));
      expect(expectErr(await fetch()), isA<CoordinatorResponseTooLarge>());
      expect(expectErr(await take()), isA<CoordinatorResponseTooLarge>());
      expect(expectErr(await cancel()), isA<CoordinatorResponseTooLarge>());
    });

    test('a huge string within the bound is refused by its field', () async {
      expect(
        await refuse(_answer(9, changes: {'description': 'x' * 60000})),
        malformed('description'),
      );
    });

    test('an answer that is not JSON is refused', () async {
      for (final response in [
        rawResponse(
          utf8.encode('<html><body>Welcome</body></html>'),
          contentType: 'text/html',
        ),
        rawResponse(utf8.encode('<html></html>')),
        rawResponse(const [0xC3, 0x28]),
        rawResponse(utf8.encode('{"id": 42,')),
        rawResponse(utf8.encode('{}'), contentType: null),
      ]) {
        serve(Ok(response));
        expect(expectErr(await fetch()), isA<CoordinatorNotJson>());
        expect(expectErr(await take()), isA<CoordinatorNotJson>());
        expect(expectErr(await cancel()), isA<CoordinatorNotJson>());
      }
    });
  });

  group('the take', () {
    test('started: the order at status 3 with this robot as taker', () async {
      serveJson(_answer(1, role: _Role.preTaker));
      final outcome = expectOk(await take());
      expect(outcome, isA<OrderTakeStarted>());
      expect(outcome.order.bondInvoice?.invoice, _bondInvoice);
    });

    test(
      'not taken: the order as it is, from a coordinator that took nothing',
      () async {
        // `api/views.py:595-596`: the error 1046 is built and not returned, and the view falls through to the read.
        for (final answer in [
          _answer(6, role: _Role.maker),
          _answer(9),
          _answer(1, role: _Role.outsider),
          _answer(5, role: _Role.taker),
          // A status 3 that does not name this robot is no pre-take of it.
          _answer(
            1,
            role: _Role.preTaker,
            changes: {'is_taker': false, 'is_participant': false},
          ),
          // This robot as the pre-taker, but at another status.
          _answer(1, role: _Role.preTaker, changes: {'status': 1}),
        ]) {
          serveJson(answer);
          final outcome = expectOk(await take());
          expect(outcome, isA<OrderNotTaken>(), reason: '${answer['status']}');
        }
      },
    );

    test('not taken, but already this robot\'s from an earlier take', () async {
      serveJson(_answer(6));
      final outcome = expectOk(await take());
      expect(outcome, isA<OrderNotTaken>());
      expect(outcome.order.isTaker, isTrue);
      expect(
        outcome.order.status,
        CoordinatorOrderStatus.waitingForCollateralAndInvoice,
      );
    });

    test('an answer about another order is malformed', () async {
      serveJson(_answer(1, role: _Role.preTaker, changes: {'id': 43}));
      expect(expectErr(await take()), malformed('id'));
    });
  });

  group('the cancel', () {
    test('that ends the order is read from its short body', () async {
      for (final status in [4, 12]) {
        serveJson(_ended(status));
        final outcome = expectOk(await cancel());
        expect(
          outcome,
          isA<OrderCancelEnded>()
              .having((o) => o.status.wire, 'status', status)
              .having((o) => o.orderId, 'orderId', _orderId),
        );
        expect('$outcome', isNot(contains('This order has been cancelled')));
      }
    });

    test('a short body that ends nothing is malformed', () async {
      for (final (changes, field) in [
        ({'status': 1}, 'status'),
        ({'status': 19}, 'status'),
        ({'status': null}, 'status'),
        ({'id': 43}, 'id'),
        ({'id': '42'}, 'id'),
      ]) {
        serveJson(_apply(_ended(4), changes));
        expect(expectErr(await cancel()), malformed(field), reason: '$changes');
      }
    });

    test('of a pre-take gives the public order back', () async {
      serveJson(_answer(1, role: _Role.outsider));
      final outcome = expectOk(
        await cancel(onlyIfStatus: CoordinatorOrderStatus.public),
      );
      final order = (outcome as OrderCancelAccepted).order;
      expect(order.status, CoordinatorOrderStatus.public);
      expect(order.isTaker, isFalse);
    });

    test('in the chat asks the peer', () async {
      serveJson(_answer(9, changes: {'asked_for_cancel': true}));
      final outcome = expectOk(await cancel());
      expect((outcome as OrderCancelAccepted).order.askedToCancel, isTrue);
    });
  });

  group('refusals', () {
    final codes = <int, Matcher>{
      1000: isA<RobotAlreadyMaker>(),
      1001: isA<RobotAlreadyTaker>(),
      1002: isA<RobotAlreadyTaking>(),
      1003: isA<RobotPayoutPending>(),
      1011: isA<OrderAmountOutOfRange>(),
      1012: isA<OrderTakePenalty>().having(
        (f) => f.secondsLeft,
        'secondsLeft',
        isNull,
      ),
      1020: isA<OrderStatusChanged>(),
      1021: isA<OrderNotCancellable>(),
      1023: isA<CoordinatorNodeUnavailable>(),
      1024: isA<CoordinatorNodeUnavailable>(),
      1025: isA<OrderTakeExpired>(),
      1026: isA<OrderEscrowExpired>(),
      1042: isA<OrderNotFound>(),
      1043: isA<OrderCancelled>(),
      1044: isA<OrderNotAvailable>(),
      1045: isA<OrderWrongPassword>(),
      1046: isA<OrderNotPublic>(),
      7000: isA<RobotCredentialsRejected>(),
      7001: isA<RobotUnknown>(),
      7003: isA<RobotCredentialsRejected>(),
    };
    // The HTTP status of each, as the reference sends it; any status gives the same failure.
    const httpStatuses = [400, 403, 404, 409, 500];

    for (final MapEntry(key: code, value: matcher) in codes.entries) {
      test('error $code', () async {
        for (final httpStatus in httpStatuses) {
          serveJson(_error(code), statusCode: httpStatus);
          expect(expectErr(await fetch()), matcher, reason: '$httpStatus');
          expect(expectErr(await take()), matcher, reason: '$httpStatus');
          expect(expectErr(await cancel()), matcher, reason: '$httpStatus');
        }
      });
    }

    test('the robots in use share one type', () {
      for (final code in [1000, 1001, 1002, 1003]) {
        expect(codes[code], isNotNull);
      }
      expect(const RobotAlreadyTaking(), isA<RobotHasActiveOrder>());
      expect(const OrderWrongPassword(), isA<CoordinatorOrderFailure>());
    });

    test('1012 gives the seconds of the reference\'s message only', () async {
      for (final (message, seconds) in [
        ('You need to wait 60 seconds to take an order', 60),
        ('You need to wait 0 seconds to take an order', 0),
        ('You need to wait 86399 seconds to take an order', 86399),
        ('You need to wait 86400 seconds to take an order', null),
        ('You need to wait 123456 seconds to take an order', null),
        ('You need to wait -5 seconds to take an order', null),
        (
          'You need to wait 60 seconds to take an order. Visit evil.example',
          null,
        ),
        ('Attendez 60 secondes', null),
        ('', null),
        ('x' * 200, null),
      ]) {
        serveJson(_error(1012, message), statusCode: 403);
        expect(
          expectErr(await take()),
          isA<OrderTakePenalty>().having(
            (f) => f.secondsLeft,
            'secondsLeft',
            seconds,
          ),
          reason: message,
        );
      }
      serveJson({'error_code': 1012, 'bad_request': 60}, statusCode: 403);
      expect(
        expectErr(await take()),
        isA<OrderTakePenalty>().having(
          (f) => f.secondsLeft,
          'secondsLeft',
          isNull,
        ),
      );
    });

    test('an unknown code is one refusal that carries the number', () async {
      for (final code in [
        0,
        1004,
        1047,
        1049,
        2000,
        3002,
        6001,
        7002,
        7004,
        99999,
      ]) {
        serveJson(_error(code), statusCode: 400);
        expect(
          expectErr(await take()),
          isA<OrderRequestRefused>().having(
            (f) => f.errorCode,
            'errorCode',
            code,
          ),
        );
      }
    });

    test('a code out of range or of the wrong type is no code', () async {
      for (final code in <Object?>[-1, 100000, '1044', 1044.0, null]) {
        serveJson({'error_code': code, 'bad_request': 'x'}, statusCode: 409);
        expect(
          expectErr(await take()),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            409,
          ),
          reason: '$code',
        );
      }
    });

    test('an empty 400 is the form check of the POST', () async {
      serve(Ok(rawResponse(const [], statusCode: 400)));
      expect(
        expectErr(await take()),
        isA<OrderRequestRefused>().having(
          (f) => f.errorCode,
          'errorCode',
          isNull,
        ),
      );
    });

    test('401 and 403 without a code are the authentication\'s', () async {
      for (final status in [401, 403]) {
        serveJson({
          'detail': 'Authentication credentials were not provided.',
        }, statusCode: status);
        expect(expectErr(await fetch()), isA<RobotCredentialsRejected>());
        expect(expectErr(await take()), isA<RobotCredentialsRejected>());
      }
    });

    test('anything else is the HTTP status alone', () async {
      for (final (response, status) in [
        (
          rawResponse(
            utf8.encode('<html>Server Error (500)</html>'),
            statusCode: 500,
            contentType: 'text/html',
          ),
          500,
        ),
        (
          rawResponse(
            utf8.encode('<html>Bad request</html>'),
            statusCode: 400,
            contentType: 'text/html',
          ),
          400,
        ),
        (jsonResponse({'detail': 'Not found.'}, statusCode: 404), 404),
        (jsonResponse(<Object?>[], statusCode: 409), 409),
        (rawResponse(const [], statusCode: 302, contentType: null), 302),
      ]) {
        serve(Ok(response));
        expect(
          expectErr(await cancel()),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
      }
    });
  });

  group('nothing is printed', () {
    test('by a read, a take and a cancel, nor by what they return', () async {
      final printed = <String>[];
      final secrets = <String>[
        _us.tokenSha256Base91,
        _us.token.reveal(),
        _bondInvoice,
        _escrowInvoice,
        'Revolut only',
        'SECRET-LOOKING-TEXT',
        _peer.nickname,
        _us.nickname,
        _peer.hashId.hex,
        'ba7816bf8f01cfea',
      ];
      await runZoned(
        () async {
          Zone.current.print('print capture works');
          final outputs = <Object?>[];
          serveJson(_answer(1, role: _Role.preTaker));
          outputs
            ..add(await fetch())
            ..add(await take(password: 'abc'));
          serveJson(_answer(6, buyer: false));
          outputs.add(await fetch());
          serveJson(_answer(14));
          outputs.add(await fetch());
          serveJson(_ended(12));
          outputs.add(await cancel());
          serveJson(_answer(9));
          outputs.add(await cancel());
          serveJson(_error(1044, 'SECRET-LOOKING-TEXT'), statusCode: 403);
          outputs
            ..add(await fetch())
            ..add(await take());
          serveJson(
            _error(1012, 'You need to wait 60 seconds to take an order'),
            statusCode: 403,
          );
          outputs.add(await take());
          for (final output in outputs) {
            final shown = switch (output) {
              Ok(:final value) => [
                '$value',
                if (value case final TakeOrderOutcome outcome) ...[
                  '${outcome.order}',
                  '${outcome.order.bondInvoice}',
                  '${outcome.order.summary}',
                ],
                if (value case final CoordinatorOrder order) ...[
                  '${order.escrowInvoice}',
                  '${order.summary}',
                  '${order.onchainPayout}',
                ],
              ],
              Err(:final failure) => ['$failure'],
              _ => ['$output'],
            };
            for (final text in shown) {
              for (final secret in secrets) {
                expect(
                  text.contains(secret),
                  isFalse,
                  reason: text.length.toString(),
                );
              }
            }
          }
          for (final request in transport.requests) {
            final text = '$request';
            for (final secret in secrets) {
              expect(text.contains(secret), isFalse);
            }
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(printed, ['print capture works']);
    });
  });
}
