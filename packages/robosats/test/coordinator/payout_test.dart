import 'dart:async';
import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/bech32_encode.dart';
import '../support/coordinator.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

// Every coordinator answer here is derived from the reference code (commit ff1998c) and built by the test: no trade was made, so nothing could be recorded, and no invoice or address belongs to anyone.

const _testnet = RobosatsNetwork.testnet;
const _mainnet = RobosatsNetwork.mainnet;

/// This device's robot, the buyer: index 0 of the example Garage Key of the RoboSats repository.
final _us = interopIdentity;

/// What a buyer at 6 or 8 reads when the coordinator offers the swap (`Logics.payout_amount`, `api/logics.py:724-730`): the rates are a `float` and a `Decimal`, both numbers.
const _swapOffered = <String, Object?>{
  'swap_allowed': true,
  'swap_failure_reason': null,
  'suggested_mining_fee_rate': 2.05,
  'swap_fee_rate': 1.0,
};

/// The header and the footer the coordinator splits a clear-signed message on (`api/utils.py:642-643`).
const _header = '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n';
const _footer = '-----BEGIN PGP SIGNATURE-----';

/// The characters Python's `str.strip()` with no argument removes: those `str.isspace()` is true for (Unicode White_Space and the bidirectional classes B, S and WS).
final _pythonWhitespace = {
  for (var unit = 0x09; unit <= 0x0d; unit++) unit,
  for (var unit = 0x1c; unit <= 0x20; unit++) unit,
  0x85,
  0xa0,
  0x1680,
  for (var unit = 0x2000; unit <= 0x200a; unit++) unit,
  0x2028,
  0x2029,
  0x202f,
  0x205f,
  0x3000,
};

/// `str.strip()` of Python, with no argument.
String _pythonStrip(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _pythonWhitespace.contains(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _pythonWhitespace.contains(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

/// The text a coordinator takes from a clear-signed message once GnuPG said its signature is valid: `signed_message.split(header)[1].split(footer)[0].strip()` (`api/utils.py:642-644`), or `null` where Python raises `IndexError` (no header), which the view turns into a `500`.
///
/// Python's `str.split(sep)` with a separator keeps the empty pieces, as Dart's `String.split` does with a non-empty pattern.
String? _coordinatorCleartext(String signedMessage) {
  final pieces = signedMessage.split(_header);
  if (pieces.length < 2) return null;
  return _pythonStrip(pieces[1].split(_footer)[0]);
}

void main() {
  final temple = coordinatorNamed('temple');
  final key = generateInteropKey();
  final unlocked = expectOk(key.unlock(_us));
  final peerUnlocked = expectOk(
    generateInteropPeerKey().unlock(interopPeerIdentity),
  );
  final testnetInvoice = invoiceShaped('lntb1639610n');
  final mainnetInvoice = invoiceShaped('lnbc1639610n');
  final testnetAddress = expectOk(
    BitcoinAddress.check(
      'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
      _testnet,
    ),
  );
  final mainnetAddress = expectOk(
    BitcoinAddress.check(
      'bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0',
      _mainnet,
    ),
  );
  final signedInvoice = expectOk(
    unlocked.signPayoutInvoice(testnetInvoice, _testnet, now: interopNow),
  );
  final signedAddress = expectOk(
    unlocked.signPayoutAddress(testnetAddress, now: interopNow),
  );
  final budget = RoutingBudgetPpm.referenceDefault;
  final fee = MiningFeeRate.of(2.05);
  if (fee == null) fail('2.05 sat/vB is a rate');

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

  CoordinatorOrder lastReadAt(
    int status, {
    Map<String, Object?> changes = const {},
    bool buyer = true,
  }) => readOrder(orderAnswer(status, buyer: buyer, changes: changes));

  Future<Result<PayoutOutcome, OrderActionFailure>> submitInvoice({
    CoordinatorOrder? lastRead,
    SignedPayoutInvoice? invoice,
    RoutingBudgetPpm? routingBudget,
    RobotIdentity? identity,
  }) => client.submitPayoutInvoice(
    identity: identity ?? _us,
    lastRead: lastRead ?? lastReadAt(6),
    invoice: invoice ?? signedInvoice,
    routingBudget: routingBudget ?? budget,
  );

  Future<Result<PayoutOutcome, OrderActionFailure>> submitAddress({
    CoordinatorOrder? lastRead,
    SignedPayoutAddress? address,
    MiningFeeRate? miningFeeRate,
    RobotIdentity? identity,
  }) => client.submitPayoutAddress(
    identity: identity ?? _us,
    lastRead: lastRead ?? lastReadAt(6, changes: _swapOffered),
    address: address ?? signedAddress,
    miningFeeRate: miningFeeRate ?? fee,
  );

  group('the signed text', () {
    test('of an invoice is the invoice, as the coordinator splits it', () {
      for (final invoice in [
        testnetInvoice,
        testnetInvoice.toUpperCase(),
        invoiceShaped('lntb', seed: 'no amount', wordCount: 111),
        invoiceShaped('lntb25m', seed: 'long', wordCount: 3000),
      ]) {
        final signed = expectOk(
          unlocked.signPayoutInvoice(invoice, _testnet, now: interopNow),
        );
        expect(signed.text, invoice);
        expect(signed.network, _testnet);
        expect(signed.signer, _us.hashId);
        expect(signed.signedMessage, startsWith(_header + invoice));
        expect(_coordinatorCleartext(signed.signedMessage), invoice);
        expect(
          expectOk(key.publicKey.verifyCleartext(signed.signedMessage)),
          invoice,
        );
      }
      final mainnet = expectOk(
        unlocked.signPayoutInvoice(mainnetInvoice, _mainnet, now: interopNow),
      );
      expect(_coordinatorCleartext(mainnet.signedMessage), mainnetInvoice);
    });

    test('of an address is the address, as the coordinator splits it', () {
      for (final address in [
        testnetAddress,
        mainnetAddress,
        expectOk(
          BitcoinAddress.check(
            'BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4',
            _mainnet,
          ),
        ),
        expectOk(
          BitcoinAddress.check('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', _mainnet),
        ),
        expectOk(
          BitcoinAddress.check('2NCefBbdbkb9sxfEHW3UbU3VQPVwWBa25YB', _testnet),
        ),
      ]) {
        final signed = expectOk(
          unlocked.signPayoutAddress(address, now: interopNow),
        );
        expect(signed.text, address.text);
        expect(signed.address, address);
        expect(signed.network, address.network);
        expect(signed.signer, _us.hashId);
        expect(_coordinatorCleartext(signed.signedMessage), address.text);
        expect(
          expectOk(key.publicKey.verifyCleartext(signed.signedMessage)),
          address.text,
        );
      }
    });

    test(
      'of any text signCleartext accepts comes back intact from the coordinator\'s split',
      () {
        // Pieces chosen for the split: whitespace Python strips and Dart keeps or the reverse, dashes, line breaks, and the armor lines themselves.
        const pieces = [
          'a',
          'lnbc1',
          ' ',
          '\t',
          '\n',
          '\n\n',
          '-',
          '- ',
          '\u001c',
          '\u001f',
          ' ',
          '\u0085',
          ' ',
          '﻿',
          '​',
          'é',
          '-----BEGIN PGP SIGNATURE-----',
          '-----BEGIN PGP SIGNED MESSAGE-----',
          'Hash: SHA512',
          '-----END PGP SIGNATURE-----',
        ];
        final random = DeterministicRandom('coordinator split');
        var accepted = 0;
        var refused = 0;
        for (var i = 0; i < 600; i++) {
          final text = [
            for (var j = 0; j < 1 + random.nextInt(256) % 6; j++)
              pieces[random.nextInt(256) % pieces.length],
          ].join();
          switch (unlocked.signCleartext(text, now: interopNow)) {
            case Ok(value: final signed):
              accepted++;
              expect(
                _coordinatorCleartext(signed),
                text,
                reason: jsonEncode(text),
              );
            case Err(:final failure):
              refused++;
              expect(failure, isA<PgpCleartextUnsuitable>());
          }
        }
        expect(accepted, greaterThan(50));
        expect(refused, greaterThan(50));
      },
    );

    test('a text the split would cut or shorten is refused', () {
      for (final text in [
        'lnbc1\n',
        'lnbc1 ',
        '-lnbc1',
        'lnbc1\n- x',
        'x-----BEGIN PGP SIGNATURE-----y',
        'x-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\ny',
        '\u001clnbc1',
        'lnbc1\u001f',
      ]) {
        expect(
          expectErr(unlocked.signCleartext(text, now: interopNow)),
          isA<PgpCleartextUnsuitable>(),
          reason: jsonEncode(text),
        );
      }
      // What the guard prevents: the coordinator would read another text.
      const cut = 'x-----BEGIN PGP SIGNATURE-----y';
      expect(_coordinatorCleartext('$_header$cut\n$_footer\n…'), 'x');
      expect(_pythonStrip('\u001clnbc1'), 'lnbc1');
      expect('\u001clnbc1'.trim(), '\u001clnbc1');
    });

    test('a message without the exact header has no text for the coordinator', () {
      final signed = expectOk(
        unlocked.signCleartext(testnetInvoice, now: interopNow),
      );
      expect(
        _coordinatorCleartext(signed.replaceFirst('Hash: SHA512', 'Hash: SHA256')),
        isNull,
      );
    });
  });

  group('the invoice signed for a payout', () {
    test('has the shape of an invoice of the trade\'s network', () {
      final cases = <String, (RobosatsNetwork, Matcher)>{
        mainnetInvoice: (_testnet, isA<PayoutDestinationWrongNetwork>()),
        testnetInvoice: (_mainnet, isA<PayoutDestinationWrongNetwork>()),
        // Signet and regtest.
        invoiceShaped('lntbs1639610n'): (
          _testnet,
          isA<PayoutDestinationWrongNetwork>(),
        ),
        invoiceShaped('lnbcrt1639610n'): (
          _mainnet,
          isA<PayoutDestinationWrongNetwork>(),
        ),
        invoiceShaped('lnbcrt1639610n', seed: 'regtest'): (
          _testnet,
          isA<PayoutDestinationWrongNetwork>(),
        ),
        // One character changed: a typo.
        '${testnetInvoice.substring(0, 40)}${testnetInvoice[40] == 'q' ? 'p' : 'q'}${testnetInvoice.substring(41)}':
            (_testnet, isA<PayoutDestinationBadChecksum>()),
        invoiceShaped('lntb1639610n', bech32m: true): (
          _testnet,
          isA<PayoutDestinationBadChecksum>(),
        ),
        // Too long, too short, not an invoice's prefix, mixed case, whitespace.
        invoiceShaped('lntb1639610n', wordCount: 2000): (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        invoiceShaped('lntb1639610n', wordCount: 110): (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        invoiceShaped('lnxy1639610n'): (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        invoiceShaped('lntb16x'): (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        invoiceShaped('lno'): (_testnet, isA<PayoutDestinationMalformed>()),
        'LNTB${testnetInvoice.substring(4)}': (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        ' $testnetInvoice': (_testnet, isA<PayoutDestinationMalformed>()),
        '$testnetInvoice\n': (_testnet, isA<PayoutDestinationMalformed>()),
        'lightning:$testnetInvoice': (
          _testnet,
          isA<PayoutDestinationMalformed>(),
        ),
        testnetAddress.text: (_testnet, isA<PayoutDestinationMalformed>()),
        '': (_testnet, isA<PayoutDestinationMalformed>()),
      };
      for (final MapEntry(key: text, value: (network, matcher))
          in cases.entries) {
        expect(
          expectErr(unlocked.signPayoutInvoice(text, network, now: interopNow)),
          matcher,
          reason: text.length > 60 ? text.substring(0, 60) : text,
        );
      }
      expect(testnetInvoice.length, lessThan(CoordinatorOrder.maxInvoiceLength));
    });

    test('says only its network', () {
      expect('$signedInvoice', 'SignedPayoutInvoice(testnet)');
      expect('$signedAddress', 'SignedPayoutAddress(BitcoinAddress(p2wsh, testnet))');
    });
  });

  group('the routing budget', () {
    test('is 0 to 99,998 ppm, 1,000 by default, as the reference client', () {
      expect(RoutingBudgetPpm.referenceDefault.ppm, 1000);
      expect(RoutingBudgetPpm.of(0)?.ppm, 0);
      expect(RoutingBudgetPpm.of(99998)?.ppm, 99998);
      expect(RoutingBudgetPpm.of(99999), isNull);
      expect(RoutingBudgetPpm.of(100001), isNull);
      expect(RoutingBudgetPpm.of(-1), isNull);
    });

    test('gives the invoice amount the coordinator computes', () {
      // `int(n - float(n) * (float(ppm) / 1_000_000))`, `api/logics.py:868-872`, worked by hand and checked with CPython 3.
      for (final (buyer, ppm, invoice) in [
        (164126, 1000, 163961), // 164,126 − 164.126
        (164126, 0, 164126),
        (164126, 99998, 147713), // 164,126 − 16,412.271748
        (1000000, 1000, 999000),
        (20000, 1000, 19980),
        (19999, 1, 19998), // 19,999 − 0.019999
        (1, 1000, 0),
        (0, 1000, 0),
        (2100000000000000, 99998, 1890004200000000),
        (2100000000000000, 1000, 2097900000000000),
      ]) {
        final routingBudget = RoutingBudgetPpm.of(ppm);
        if (routingBudget == null) fail('$ppm is a budget');
        expect(
          routingBudget.invoiceSats(Sats.fromInt(buyer)),
          Sats.fromInt(invoice),
          reason: '$buyer at $ppm ppm',
        );
      }
      expect(
        budget.invoiceSats(Sats(BigInt.from(CoordinatorReadBounds.maxSats) + BigInt.one)),
        isNull,
      );
    });

    test(
      'is the exact amount rounded down, but within 10 µsat of a whole sat, where double precision decides as for the coordinator',
      () {
        final random = DeterministicRandom('routing budget');
        int draw(int bytes) {
          var value = 0;
          for (var i = 0; i < bytes; i++) {
            value = value << 8 | random.nextInt(256);
          }
          return value;
        }

        for (var i = 0; i < 5000; i++) {
          final buyer = draw(4);
          final ppm = draw(3) % (RoutingBudgetPpm.maxPpm + 1);
          final routingBudget = RoutingBudgetPpm.of(ppm);
          if (routingBudget == null) fail('$ppm is a budget');
          final invoice = routingBudget.invoiceSats(Sats.fromInt(buyer));
          if (invoice == null) fail('$buyer is an amount');
          // Exactly, in integers: n − n × ppm / 10⁶ = n × (10⁶ − ppm) / 10⁶.
          final exact = BigInt.from(buyer) * BigInt.from(1000000 - ppm);
          final floor = (exact ~/ BigInt.from(1000000)).toInt();
          final remainder = (exact % BigInt.from(1000000)).toInt();
          expect(
            invoice.value.toInt(),
            switch (remainder) {
              < 10 => anyOf(floor, floor - 1),
              > 999990 => anyOf(floor, floor + 1),
              _ => floor,
            },
            reason: '$buyer at $ppm ppm',
          );
        }
      },
    );
  });

  group('the mining fee rate', () {
    test('is 2 to 500 sat/vB with at most 3 decimals', () {
      for (final (rate, wire) in <(double, num)>[
        (2, 2),
        (2.05, 2.05),
        (10, 10),
        (12.345, 12.345),
        (499.999, 499.999),
        (500, 500),
      ]) {
        final value = MiningFeeRate.of(rate);
        expect(value?.satPerVbyte, rate);
        expect(value?.wire, wire);
        expect(value?.wire, wire is int ? isA<int>() : isA<double>());
      }
      for (final rate in [
        1.999,
        0,
        -5,
        500.001,
        1000,
        2.0505,
        12.3456,
        double.nan,
        double.infinity,
      ]) {
        expect(MiningFeeRate.of(rate), isNull, reason: '$rate');
      }
    });

    test('gives what the address receives as the coordinator computes it', () {
      // `api/logics.py:806-813`, worked by hand and checked with CPython 3: 2.05 × 280 is 574 in double precision, 10.001 × 280 is 2,800.28.
      for (final (buyer, swap, rate, sent) in [
        (164126, 1.0, 2.05, 161910), // 164,126 − 1,641.26 − 574
        (164126, 0.0, 10.001, 161326), // 164,126 − 2,800
        (20000, 1.0, 2.0, 19240), // 20,000 − 200 − 560
        (1000, 5.0, 500.0, -139050), // 1,000 − 50 − 140,000
      ]) {
        final value = MiningFeeRate.of(rate);
        if (value == null) fail('$rate is a rate');
        expect(
          value.sentSats(buyerSats: Sats.fromInt(buyer), swapFeePercent: swap),
          sent,
        );
      }
      expect(
        fee.sentSats(buyerSats: Sats.fromInt(1000), swapFeePercent: 101),
        isNull,
      );
      expect(
        fee.sentSats(buyerSats: Sats.fromInt(1000), swapFeePercent: double.nan),
        isNull,
      );
      expect(MiningFeeRate.minimumSentSats, 20000);
      expect(MiningFeeRate.chargedVbytes, 280);
    });
  });

  group('the requests', () {
    // What the reference client sends (`frontend/src/components/TradeBox/index.tsx:276-308`, `models/Order.model.ts:245-262`): `JSON.stringify` of the action, with the short header.
    void expectPost(Map<String, Object?> body, {RobosatsNetwork network = _testnet}) {
      final request = transport.requests.single;
      expect(request.method, CoordinatorHttpMethod.post);
      expect(
        request.url.toString(),
        '${temple.origins(network).onion}/api/order/?order_id=42',
      );
      expect(request.headers, {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Token ${_us.tokenSha256Base91}',
      });
      expect(request.body, utf8.encode(jsonEncode(body)));
      expect(request.robot, _us.sessionKey);
      expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
    }

    test('an invoice is update_invoice with the signed invoice and the budget', () async {
      serveJson(orderAnswer(7));
      await submitInvoice();
      expectPost({
        'action': 'update_invoice',
        'invoice': signedInvoice.signedMessage,
        'routing_budget_ppm': 1000,
      });
      final body = utf8.decode(transport.requests.single.body ?? []);
      expect(body, startsWith('{"action":"update_invoice","invoice":"-----BEGIN PGP SIGNED MESSAGE-----\\nHash: SHA512\\n\\n'));
      expect(body, endsWith('"routing_budget_ppm":1000}'));
    });

    test('a budget of 0 is sent as 0', () async {
      serveJson(orderAnswer(7));
      await submitInvoice(routingBudget: RoutingBudgetPpm.of(0));
      expectPost({
        'action': 'update_invoice',
        'invoice': signedInvoice.signedMessage,
        'routing_budget_ppm': 0,
      });
    });

    test('an address is update_address with the signed address and the rate', () async {
      serveJson(orderAnswer(7));
      await submitAddress();
      expectPost({
        'action': 'update_address',
        'address': signedAddress.signedMessage,
        'mining_fee_rate': 2.05,
      });
      expect(utf8.decode(transport.requests.single.body ?? []), endsWith('"mining_fee_rate":2.05}'));
    });

    test('a whole rate is sent as an integer, as JavaScript writes it', () async {
      serveJson(orderAnswer(7));
      await submitAddress(miningFeeRate: MiningFeeRate.of(15));
      expect(utf8.decode(transport.requests.single.body ?? []), endsWith('"mining_fee_rate":15}'));
    });

    test('a mainnet trade goes to the mainnet instance', () async {
      final lastRead = readOrder(orderAnswer(8), network: _mainnet);
      transport.answer(temple, _mainnet, '/api/order/', Ok(jsonResponse(orderAnswer(9))));
      final signed = expectOk(
        unlocked.signPayoutInvoice(mainnetInvoice, _mainnet, now: interopNow),
      );
      expect(
        await submitInvoice(lastRead: lastRead, invoice: signed),
        isA<Ok<PayoutOutcome, OrderActionFailure>>(),
      );
      expectPost({
        'action': 'update_invoice',
        'invoice': signed.signedMessage,
        'routing_budget_ppm': 1000,
      }, network: _mainnet);
    });

    test('is sent once, whatever happens', () async {
      for (final answer in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
        const Err(CoordinatorTimedOut()),
        const Err(CoordinatorUnreachable()),
        Ok(rawResponse(utf8.encode('<html>502</html>'), statusCode: 502, contentType: 'text/html')),
      ]) {
        transport.requests.clear();
        serve(answer);
        await submitInvoice();
        await submitAddress();
        expect(transport.requests, hasLength(2));
      }
    });
  });

  group('an accepted payout', () {
    test('gives the order as it then is', () async {
      for (final (from, to, submit) in [
        (6, 7, 'invoice'),
        (8, 9, 'invoice'),
        (6, 9, 'address'),
        (8, 9, 'address'),
      ]) {
        serveJson(orderAnswer(to));
        final lastRead = lastReadAt(
          from,
          changes: submit == 'address' ? _swapOffered : const {},
        );
        final outcome = expectOk(
          submit == 'invoice'
              ? await submitInvoice(lastRead: lastRead)
              : await submitAddress(lastRead: lastRead),
        );
        expect(outcome, isA<PayoutAccepted>());
        expect(outcome.order.status.wire, to);
        expect(outcome.order.isBuyer, isTrue);
        expect(outcome.order.id, testOrderId);
      }
    });

    test('a new invoice after a failed payout whose invoice expired', () async {
      serveJson(orderAnswer(13));
      final outcome = expectOk(await submitInvoice(lastRead: lastReadAt(15)));
      expect(outcome.order.status, CoordinatorOrderStatus.sendingSats);
    });

    test('an answer that is not this buyer\'s order is an outcome unknown', () async {
      for (final answer in [
        orderAnswer(7, buyer: false),
        orderAnswer(7, changes: {'id': 43}),
        orderAnswer(7, changes: {'is_buyer': false, 'is_seller': true}),
        orderAnswer(7, changes: {'status': 'seven'}),
        orderAnswer(1, role: OrderRole.outsider),
        <String, Object?>{},
      ]) {
        serveJson(answer);
        final failure = expectErr(await submitInvoice());
        expect(failure, isA<OrderActionOutcomeUnknown>());
        expect(failure.cause, isA<CoordinatorResponseMalformed>());
      }
    });
  });

  group('refused before anything is sent', () {
    test('a last read of another robot', () async {
      for (final submit in [
        () => submitInvoice(identity: interopPeerIdentity),
        () => submitAddress(identity: interopPeerIdentity),
      ]) {
        serveJson(orderAnswer(7));
        final failure = expectErr(await submit());
        expect(failure, isA<OrderActionRefused>());
        expect(failure.cause, isA<OrderReadElsewhere>());
      }
      expect(transport.requests, isEmpty);
    });

    test('each case, with nothing sent', () async {
      final peerInvoice = expectOk(
        peerUnlocked.signPayoutInvoice(testnetInvoice, _testnet, now: interopNow),
      );
      final peerAddress = expectOk(
        peerUnlocked.signPayoutAddress(testnetAddress, now: interopNow),
      );
      final mainnetSigned = expectOk(
        unlocked.signPayoutInvoice(mainnetInvoice, _mainnet, now: interopNow),
      );
      final mainnetAddressSigned = expectOk(
        unlocked.signPayoutAddress(mainnetAddress, now: interopNow),
      );
      final cases = <(String, Future<Result<PayoutOutcome, OrderActionFailure>> Function(), Matcher)>[
        ('invoice signed by the peer', () => submitInvoice(invoice: peerInvoice), isA<PayoutSignedByAnotherRobot>()),
        ('address signed by the peer', () => submitAddress(address: peerAddress), isA<PayoutSignedByAnotherRobot>()),
        ('mainnet invoice, testnet order', () => submitInvoice(invoice: mainnetSigned), isA<PayoutInvoiceRefused>().having((f) => f.reason, 'reason', PayoutInvoiceRefusal.wrongNetwork)),
        ('mainnet address, testnet order', () => submitAddress(address: mainnetAddressSigned), isA<PayoutAddressRefused>().having((f) => f.reason, 'reason', PayoutAddressRefusal.wrongNetwork)),
        ('invoice of a seller', () => submitInvoice(lastRead: lastReadAt(6, buyer: false)), isA<PayoutNotBuyer>()),
        ('address of a seller', () => submitAddress(lastRead: lastReadAt(7, buyer: false)), isA<PayoutNotBuyer>()),
        ('invoice at 7', () => submitInvoice(lastRead: lastReadAt(7)), isA<PayoutNotNow>()),
        ('invoice at 9', () => submitInvoice(lastRead: lastReadAt(9)), isA<PayoutNotNow>()),
        ('invoice at 3', () => submitInvoice(lastRead: readOrder(orderAnswer(1, role: OrderRole.preTaker))), isA<PayoutNotNow>()),
        ('invoice at 15, not expired', () => submitInvoice(lastRead: lastReadAt(15, changes: {'invoice_expired': null, 'trade_satoshis': null})), isA<PayoutNotNow>()),
        ('invoice at 14', () => submitInvoice(lastRead: lastReadAt(14)), isA<PayoutNotNow>()),
        ('address at 15', () => submitAddress(lastRead: lastReadAt(15)), isA<PayoutNotNow>()),
        ('address at 9', () => submitAddress(lastRead: lastReadAt(9)), isA<PayoutNotNow>()),
        ('address without the swap', () => submitAddress(lastRead: lastReadAt(6)), isA<PayoutSwapUnavailable>()),
        ('address with the swap unsaid', () => submitAddress(lastRead: lastReadAt(8, changes: {'swap_allowed': null, 'swap_failure_reason': null})), isA<PayoutSwapUnavailable>()),
      ];
      for (final (name, submit, matcher) in cases) {
        transport.requests.clear();
        serveJson(orderAnswer(7));
        final failure = expectErr(await submit());
        expect(failure, isA<OrderActionRefused>(), reason: name);
        expect(failure.cause, matcher, reason: name);
        expect(transport.requests, isEmpty, reason: name);
      }
    });

  });

  group('refusals of the coordinator', () {
    // Derived from the reference code, not recorded: `api/views.py:617-649`, `api/logics.py:752-880`, `api/lightning/lnd.py:451-539`, `api/utils.py:106-121`, the codes of `api/errors.py`.
    Map<String, Object?> coded(int code, {String key = 'bad_request', String text = 'Some text.'}) => {'error_code': code, key: text};

    final invoiceCodes = <int, (Matcher, int)>{
      1047: (isA<OrderNotParticipant>(), 403),
      1048: (isA<PayoutSignatureRefused>(), 400),
      1017: (isA<PayoutNotBuyer>(), 400),
      1018: (isA<PayoutNotNow>(), 400),
      1019: (isA<PayoutNotNow>(), 400),
      3001: (isA<PayoutNotNow>(), 400),
      3000: (isA<PayoutInvoiceRefused>().having((f) => f.reason, 'reason', PayoutInvoiceRefusal.empty), 400),
      3002: (isA<PayoutInvoiceRefused>().having((f) => f.reason, 'reason', PayoutInvoiceRefusal.alreadySubmitted), 400),
    };
    final addressCodes = <int, (Matcher, int)>{
      1047: (isA<OrderNotParticipant>(), 403),
      1048: (isA<PayoutSignatureRefused>(), 400),
      1015: (isA<PayoutNotBuyer>(), 400),
      1016: (isA<PayoutNotNow>(), 400),
      4000: (isA<PayoutAddressRefused>().having((f) => f.reason, 'reason', PayoutAddressRefusal.empty), 400),
      4001: (isA<PayoutMiningFeeTooLow>().having((f) => f.minimumSatPerVbyte, 'minimum', isNull), 400),
      4002: (isA<PayoutMiningFeeTooHigh>(), 400),
      4003: (isA<PayoutBelowDustLimit>(), 400),
      4004: (isA<PayoutAddressRefused>().having((f) => f.reason, 'reason', PayoutAddressRefusal.invalid), 400),
      4005: (isA<PayoutAddressRefused>().having((f) => f.reason, 'reason', PayoutAddressRefusal.unverifiable), 400),
    };

    String keyOf(int code) => switch (code) {
      >= 3000 && < 4000 => 'bad_invoice',
      >= 4000 && < 5000 => 'bad_address',
      _ => 'bad_request',
    };

    for (final MapEntry(key: code, value: (matcher, httpStatus)) in invoiceCodes.entries) {
      test('of an invoice: $code', () async {
        for (final status in {httpStatus, 400, 403, 409}) {
          serveJson(coded(code, key: keyOf(code)), statusCode: status);
          final failure = expectErr(await submitInvoice());
          expect(failure, isA<OrderActionRefused>(), reason: '$code on $status');
          expect(failure.cause, matcher, reason: '$code on $status');
        }
      });
    }

    for (final MapEntry(key: code, value: (matcher, httpStatus)) in addressCodes.entries) {
      test('of an address: $code', () async {
        for (final status in {httpStatus, 400, 403, 409}) {
          serveJson(coded(code, key: keyOf(code)), statusCode: status);
          final failure = expectErr(await submitAddress());
          expect(failure, isA<OrderActionRefused>(), reason: '$code on $status');
          expect(failure.cause, matcher, reason: '$code on $status');
        }
      });
    }

    test('a code of the other payout, or of another action, is an outcome unknown', () async {
      for (final code in addressCodes.keys.where((code) => !invoiceCodes.containsKey(code))) {
        serveJson(coded(code, key: keyOf(code)), statusCode: 400);
        final failure = expectErr(await submitInvoice());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
        expect(failure.cause, isA<OrderRequestRefused>().having((f) => f.errorCode, 'errorCode', code));
      }
      for (final code in invoiceCodes.keys.where((code) => !addressCodes.containsKey(code))) {
        serveJson(coded(code, key: keyOf(code)), statusCode: 400);
        final failure = expectErr(await submitAddress());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
        expect(failure.cause, isA<OrderRequestRefused>().having((f) => f.errorCode, 'errorCode', code));
      }
      // The codes of a take or a cancel, which the reference never answers to a payout.
      for (final (code, cause) in [
        (1000, isA<RobotAlreadyMaker>()),
        (1003, isA<RobotPayoutPending>()),
        (1011, isA<OrderAmountOutOfRange>()),
        (1012, isA<OrderTakePenalty>()),
        (1020, isA<OrderStatusChanged>()),
        (1045, isA<OrderWrongPassword>()),
        (1049, isA<OrderRequestRefused>()),
        (3003, isA<OrderRequestRefused>()),
      ]) {
        serveJson(coded(code), statusCode: 400);
        for (final failure in [expectErr(await submitInvoice()), expectErr(await submitAddress())]) {
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
          expect(failure.cause, cause, reason: '$code');
        }
      }
    });

    test('the errors of the read after the action are an outcome unknown', () async {
      for (final (code, status, cause) in [
        (1043, 400, isA<OrderCancelled>()),
        (1044, 403, isA<OrderNotAvailable>()),
        (1042, 404, isA<OrderNotFound>()),
        (1023, 400, isA<CoordinatorNodeUnavailable>()),
      ]) {
        serveJson(coded(code), statusCode: status);
        for (final failure in [expectErr(await submitInvoice()), expectErr(await submitAddress())]) {
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
          expect(failure.cause, cause, reason: '$code');
        }
      }
    });

    test('the invoice texts of the Lightning node, with no code', () async {
      final texts = <String, PayoutInvoiceRefusal>{
        'Does not look like a valid lightning invoice': PayoutInvoiceRefusal.notAnInvoice,
        'The invoice hinted private routes are not payable within the submitted routing budget. This can be adjusted with Advanced Options enabled.': PayoutInvoiceRefusal.routeHintsUnpayable,
        'The invoice provided has no explicit amount': PayoutInvoiceRefusal.noAmount,
        // `"{:,}".format(num_satoshis)`.
        'The invoice provided is not for 163,961 Sats': PayoutInvoiceRefusal.wrongAmount,
        'The invoice provided is not for 999 Sats': PayoutInvoiceRefusal.wrongAmount,
        'The invoice provided is not for 0 Sats': PayoutInvoiceRefusal.wrongAmount,
        'The invoice provided is not for 1,890,004,200,000,000 Sats': PayoutInvoiceRefusal.wrongAmount,
        'The invoice provided has already expired': PayoutInvoiceRefusal.expired,
        // Near misses and other texts.
        'The invoice provided is not for 1,00 Sats': PayoutInvoiceRefusal.unspecified,
        'The invoice provided is not for 163961 Sats': PayoutInvoiceRefusal.unspecified,
        'The invoice provided is not for 163,961 Sats. Visit evil.example': PayoutInvoiceRefusal.unspecified,
        'The invoice provided has already expired ': PayoutInvoiceRefusal.unspecified,
        'the invoice provided has already expired': PayoutInvoiceRefusal.unspecified,
        'Invoice expired, send a new one to evil.example': PayoutInvoiceRefusal.unspecified,
        '': PayoutInvoiceRefusal.unspecified,
      };
      for (final MapEntry(key: text, value: reason) in texts.entries) {
        serveJson({'bad_invoice': text}, statusCode: 400);
        final failure = expectErr(await submitInvoice());
        expect(failure, isA<OrderActionRefused>(), reason: text);
        expect(failure.cause, isA<PayoutInvoiceRefused>().having((f) => f.reason, 'reason', reason), reason: text);
      }
    });

    test('the address texts of the coordinator\'s bitcoind, with no code', () async {
      final texts = <String, PayoutAddressRefusal>{
        'Invalid address': PayoutAddressRefusal.invalid,
        'Unable to validate address, check bitcoind backend': PayoutAddressRefusal.unverifiable,
        'Invalid address!': PayoutAddressRefusal.unspecified,
        'Use bc1qevil instead': PayoutAddressRefusal.unspecified,
      };
      for (final MapEntry(key: text, value: reason) in texts.entries) {
        serveJson({'bad_address': text}, statusCode: 400);
        final failure = expectErr(await submitAddress());
        expect(failure, isA<OrderActionRefused>(), reason: text);
        expect(failure.cause, isA<PayoutAddressRefused>().having((f) => f.reason, 'reason', reason), reason: text);
      }
    });

    test('a text of the other payout, or out of bounds, is no refusal of this one', () async {
      for (final (body, submit) in [
        ({'bad_address': 'Invalid address'}, submitInvoice),
        ({'bad_invoice': 'Does not look like a valid lightning invoice'}, submitAddress),
        ({'bad_invoice': 'x' * 501}, submitInvoice),
        ({'bad_invoice': 42}, submitInvoice),
        ({'bad_request': 'Some text'}, submitInvoice),
      ]) {
        serveJson(body, statusCode: 400);
        final failure = expectErr(await submit());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$body');
        expect(failure.cause, isA<CoordinatorUnexpectedStatus>().having((f) => f.statusCode, 'statusCode', 400));
      }
      // A text with no code is read on a `400` only.
      serveJson({'bad_invoice': 'Does not look like a valid lightning invoice'}, statusCode: 409);
      expect(expectErr(await submitInvoice()), isA<OrderActionOutcomeUnknown>());
    });

    test('4001 gives the minimum of the reference\'s message only', () async {
      for (final (message, minimum) in <(Object?, double?)>[
        ('The mining fee is too low. Must be higher than 2 Sat/vbyte', 2),
        ('The mining fee is too low. Must be higher than 12 Sat/vbyte', 12),
        ('The mining fee is too low. Must be higher than 12.345 Sat/vbyte', 12.345),
        ('The mining fee is too low. Must be higher than 1000 Sat/vbyte', 1000),
        ('The mining fee is too low. Must be higher than 1001 Sat/vbyte', null),
        ('The mining fee is too low. Must be higher than 1.5 Sat/vbyte', null),
        ('The mining fee is too low. Must be higher than -3 Sat/vbyte', null),
        ('The mining fee is too low. Must be higher than 2 Sat/vbyte. Visit evil.example', null),
        ('Fee too low', null),
        (42, null),
        (null, null),
      ]) {
        serveJson({'error_code': 4001, 'bad_address': message}, statusCode: 400);
        final failure = expectErr(await submitAddress());
        expect(failure, isA<OrderActionRefused>());
        expect(failure.cause, isA<PayoutMiningFeeTooLow>().having((f) => f.minimumSatPerVbyte, 'minimum', minimum), reason: '$message');
      }
    });

    test('the form check, the authentication and a busy transport are refusals', () async {
      for (final answer in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
        Ok(rawResponse(const [], statusCode: 400)),
        Ok(jsonResponse({'detail': 'Authentication credentials were not provided.'}, statusCode: 401)),
        Ok(jsonResponse({'detail': 'Not authenticated.'}, statusCode: 403)),
        Ok(jsonResponse(coded(7000), statusCode: 400)),
        Ok(jsonResponse(coded(7001), statusCode: 400)),
        const Err(CoordinatorTransportBusy()),
      ]) {
        serve(answer);
        expect(expectErr(await submitInvoice()), isA<OrderActionRefused>());
        expect(expectErr(await submitAddress()), isA<OrderActionRefused>());
      }
    });

    test('everything else is an outcome unknown', () async {
      for (final answer in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
        // The `500` of an on-chain payout the coordinator does not offer (`api/logics.py:800-803`), of an unknown order (`api/views.py:542`), of anything.
        Ok(rawResponse(utf8.encode('<h1>Server Error (500)</h1>'), statusCode: 500, contentType: 'text/html')),
        Ok(jsonResponse(coded(1048), statusCode: 500)),
        Ok(jsonResponse({'bad_invoice': 'Does not look like a valid lightning invoice'}, statusCode: 502)),
        Ok(jsonResponse(coded(1049), statusCode: 501)),
        Ok(rawResponse(utf8.encode('<html></html>'), statusCode: 400, contentType: 'text/html')),
        Ok(jsonResponse(<Object?>[], statusCode: 400)),
        Ok(jsonResponse({'error_code': '1048', 'bad_request': 'x'}, statusCode: 400)),
        Ok(rawResponse(const [], statusCode: 302, contentType: null)),
        Ok(rawResponse(utf8.encode('not json'))),
        Ok(rawResponse(List.filled(CoordinatorReadBounds.orderBytes + 1, 0x20))),
        const Err(CoordinatorUnreachable()),
        const Err(CoordinatorTimedOut()),
        const Err(CoordinatorTransportFailed()),
        const Err(CoordinatorResponseTooLarge()),
      ]) {
        serve(answer);
        expect(expectErr(await submitInvoice()), isA<OrderActionOutcomeUnknown>());
        expect(expectErr(await submitAddress()), isA<OrderActionOutcomeUnknown>());
      }
    });

    test('no failure carries the coordinator\'s text, whatever it sends', () async {
      const marker = 'MARKER-0f1e2d';
      final random = DeterministicRandom('payout bodies');
      int pick(int count) => random.nextInt(256) % count;
      final codes = [...invoiceCodes.keys, ...addressCodes.keys, 1043, 1044, 7000, 7001, 7003, 1012, 0, 99999];
      const keys = ['bad_request', 'bad_invoice', 'bad_address', 'detail', 'error_code', 'status'];
      const statuses = [200, 400, 401, 403, 404, 409, 500, 502];
      final texts = [
        marker,
        'The invoice provided is not for 1,000 Sats $marker',
        'The mining fee is too low. Must be higher than $marker Sat/vbyte',
        'Invalid address $marker',
        '$marker‮',
      ];
      for (var i = 0; i < 400; i++) {
        final body = <String, Object?>{
          if (pick(4) != 0) 'error_code': codes[pick(codes.length)],
          for (var j = 0; j < 1 + pick(3); j++) keys[pick(keys.length)]: texts[pick(texts.length)],
        };
        serveJson(body, statusCode: statuses[pick(statuses.length)]);
        for (final result in [await submitInvoice(), await submitAddress()]) {
          final failure = expectErr(result);
          for (final shown in ['$failure', '${failure.cause}', failure.cause.logMessage ?? '']) {
            expect(shown, isNot(contains(marker)), reason: jsonEncode(body));
          }
        }
      }
    });
  });

  group('nothing is printed', () {
    test('by signing, checking and submitting a payout, nor by what they return', () async {
      final printed = <String>[];
      final secrets = <String>[
        _us.tokenSha256Base91,
        _us.token.reveal(),
        testnetInvoice,
        testnetAddress.text,
        'SECRET-LOOKING-TEXT',
      ];
      await runZoned(
        () async {
          Zone.current.print('print capture works');
          final outputs = <Object?>[
            BitcoinAddress.check(testnetAddress.text, _testnet),
            BitcoinAddress.check(testnetAddress.text, _mainnet),
            unlocked.signPayoutInvoice(testnetInvoice, _testnet),
            unlocked.signPayoutAddress(testnetAddress),
            unlocked.signPayoutInvoice(testnetInvoice, _mainnet),
          ];
          serveJson(orderAnswer(7));
          outputs
            ..add(await submitInvoice())
            ..add(await submitAddress());
          serveJson({'bad_invoice': 'SECRET-LOOKING-TEXT'}, statusCode: 400);
          outputs.add(await submitInvoice());
          serveJson({'error_code': 4001, 'bad_address': 'SECRET-LOOKING-TEXT'}, statusCode: 400);
          outputs.add(await submitAddress());
          for (final output in outputs) {
            final shown = switch (output) {
              Ok(:final value) => [
                '$value',
                if (value case final PayoutOutcome outcome) '${outcome.order}',
              ],
              Err(:final failure) => [
                '$failure',
                if (failure case final OrderActionFailure action) '${action.cause}',
              ],
              _ => ['$output'],
            };
            for (final text in shown) {
              for (final secret in secrets) {
                expect(text.contains(secret), isFalse, reason: text);
              }
            }
          }
          for (final request in transport.requests) {
            for (final secret in secrets) {
              expect('$request'.contains(secret), isFalse);
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
