import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/bech32_encode.dart';
import '../support/coordinator.dart';
import '../support/make_answers.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;
final _us = interopIdentity;

/// The signature of every request of a robot that changes a state (GHSA-22q8-9ghc-jg3h, RoboSats pull request 2955, head `0943c97`): the texts, byte for byte as `frontend/src/utils/actionSignature.ts`, the inventory of what this client signs, and the refusals the fix adds.
void main() {
  final temple = coordinatorNamed('temple');
  // 2026-11-12 17:00 UTC: the dispute of the fixtures' chat is open, and the time has no millisecond of its own.
  var now = DateTime.utc(2026, 11, 12, 17);
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;

  setUp(() {
    now = DateTime.utc(2026, 11, 12, 17);
    transport = FakeCoordinatorTransport();
    client = CoordinatorClient(transport, clock: () => now);
  });

  group('the signed texts', () {
    test('an action on an order: {action}:{order_id}:{shortAlias}', () {
      expect(orderActionContent('confirm', 93, 'bazaar'), 'confirm:93:bazaar');
      expect(orderActionContent('take', 1, 'robosats'), 'take:1:robosats');
      expect(
        orderActionContent('update_invoice', 42, 'temple'),
        'update_invoice:42:temple',
      );
    });

    test('a timed action: {action}:{shortAlias}:{unix_ts}, in seconds', () {
      final at = DateTime.fromMillisecondsSinceEpoch(
        1700000000999,
        isUtc: true,
      );
      expect(
        timedActionContent('make', 'bazaar', at),
        'make:bazaar:1700000000',
      );
      expect(
        timedActionContent('stealth', 'lake', at),
        'stealth:lake:1700000000',
      );
      expect(
        timedActionContent('robot', 'temple', at),
        'robot:temple:1700000000',
      );
      // Rounded down as `Math.floor(Date.now() / 1000)`, never in milliseconds, whatever the time zone of the value.
      expect(unixSeconds(at.toLocal()), 1700000000);
      expect(
        unixSeconds(DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true)),
        -1,
      );
    });

    test('the token to rate a coordinator: review:{pubkey}, no time', () {
      expect(reviewActionContent('abc123'), 'review:abc123');
    });

    test('the window is 300 seconds', () {
      expect(actionSignatureWindow, const Duration(seconds: 300));
    });
  });

  // Every request of a robot that changes a state this client can send, and the text it must sign: the inventory of the pull request.
  final testnetAddress = expectOk(
    BitcoinAddress.check(
      'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
      _testnet,
    ),
  );
  final signedInvoice = expectOk(
    interopUnlockedKey.signPayoutInvoice(
      invoiceShaped('lntb1639610n'),
      _testnet,
      now: interopNow,
    ),
  );
  final signedAddress = expectOk(
    interopUnlockedKey.signPayoutAddress(testnetAddress, now: interopNow),
  );
  final fee = MiningFeeRate.of(2.05);
  if (fee == null) fail('2.05 sat/vB is a rate');
  final pubkey = _us.nostrKeyPair().publicKeyHex;
  final inventory =
      <
        String,
        ({
          String path,
          String signed,
          Future<Object?> Function(UnlockedRobotPgpKey key) send,
        })
      >{
        'make': (
          path: '/api/make/',
          signed: 'make:temple:${unixSeconds(now)}',
          send: (key) => client.makeOrder(
            temple,
            _testnet,
            identity: _us,
            key: key,
            request: testMakeRequest(),
          ),
        ),
        'take': (
          path: '/api/order/',
          signed: 'take:$testOrderId:temple',
          send: (key) => client.takeOrder(
            temple,
            _testnet,
            identity: _us,
            key: key,
            orderId: testOrderId,
          ),
        ),
        'cancel': (
          path: '/api/order/',
          signed: 'cancel:$testOrderId:temple',
          send: (key) => client.cancelOrder(
            identity: _us,
            key: key,
            lastRead: readOrderAt(9),
          ),
        ),
        'pause': (
          path: '/api/order/',
          signed: 'pause:$testOrderId:temple',
          send: (key) => client.pauseOrder(
            identity: _us,
            key: key,
            lastRead: readOrderAt(1, role: OrderRole.maker),
          ),
        ),
        'confirm (fiat sent)': (
          path: '/api/order/',
          signed: 'confirm:$testOrderId:temple',
          send: (key) => client.confirmFiat(
            identity: _us,
            key: key,
            lastRead: readOrderAt(9),
          ),
        ),
        'confirm (fiat received)': (
          path: '/api/order/',
          signed: 'confirm:$testOrderId:temple',
          send: (key) => client.releaseEscrow(
            identity: _us,
            key: key,
            lastRead: readOrder(orderAnswer(10, buyer: false)),
          ),
        ),
        'undo_confirm': (
          path: '/api/order/',
          signed: 'undo_confirm:$testOrderId:temple',
          send: (key) => client.undoConfirmFiat(
            identity: _us,
            key: key,
            lastRead: readOrderAt(10),
          ),
        ),
        'dispute': (
          path: '/api/order/',
          signed: 'dispute:$testOrderId:temple',
          send: (key) => client.openDispute(
            identity: _us,
            key: key,
            lastRead: readOrderAt(9),
          ),
        ),
        'rate_platform': (
          path: '/api/order/',
          signed: 'rate_platform:$testOrderId:temple',
          send: (key) => client.ratePlatform(
            identity: _us,
            key: key,
            lastRead: readOrderAt(14),
            rating: PlatformRating.of(5) ?? fail('5 stars'),
          ),
        ),
        'update_invoice': (
          path: '/api/order/',
          signed: 'update_invoice:$testOrderId:temple',
          send: (key) => client.submitPayoutInvoice(
            identity: _us,
            key: key,
            lastRead: readOrderAt(6),
            invoice: signedInvoice,
            routingBudget: RoutingBudgetPpm.referenceDefault,
          ),
        ),
        'update_address': (
          path: '/api/order/',
          signed: 'update_address:$testOrderId:temple',
          send: (key) => client.submitPayoutAddress(
            identity: _us,
            key: key,
            lastRead: readOrder(
              orderAnswer(
                6,
                changes: {
                  'swap_allowed': true,
                  'swap_failure_reason': null,
                  'suggested_mining_fee_rate': 2.05,
                  'swap_fee_rate': 1.0,
                },
              ),
            ),
            address: signedAddress,
            miningFeeRate: fee,
          ),
        ),
        'review': (
          path: '/api/review/',
          signed: 'review:$pubkey',
          send: (key) => client.fetchReviewToken(
            identity: _us,
            key: key,
            coordinator: temple,
            network: _testnet,
            nostrPublicKeyHex: pubkey,
          ),
        ),
      };

  group('every request of a robot that changes a state', () {
    for (final MapEntry(key: name, value: entry) in inventory.entries) {
      test('$name is signed by the robot\'s key, the signature last', () async {
        transport.answer(
          temple,
          _testnet,
          entry.path,
          Ok(jsonResponse(orderError(1049), statusCode: 501)),
        );
        await entry.send(interopUnlockedKey);
        final request = transport.requests.single;
        expect(request.method, CoordinatorHttpMethod.post);
        expect(request.url.path, entry.path);
        // The signature verifies with the robot's public key and signs exactly the text of the table.
        final unsigned = unsignedBody(request.body, entry.signed);
        expect(jsonDecode(unsigned), isNot(contains('signature')));
      });
    }

    test(
      'none leaves without a signature: every POST of the inventory carries one',
      () async {
        for (final entry in inventory.values) {
          transport.answer(
            temple,
            _testnet,
            entry.path,
            Ok(jsonResponse(orderError(1049), statusCode: 501)),
          );
          await entry.send(interopUnlockedKey);
        }
        expect(transport.requests, hasLength(inventory.length));
        for (final request in transport.requests) {
          final body = jsonDecode(utf8.decode(request.body ?? const []));
          expect(body, isA<Map<String, Object?>>());
          expect(
            (body as Map<String, Object?>)['signature'],
            startsWith('-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n'),
            reason: request.url.toString(),
          );
        }
      },
    );

    test('the key of another robot sends nothing', () async {
      for (final MapEntry(key: name, value: entry) in inventory.entries) {
        final failure = await entry.send(interopPeerUnlockedKey);
        expect(
          switch (failure) {
            Err(failure: OrderActionRefused(:final cause)) => cause,
            Err(:final failure) => failure,
            _ => failure,
          },
          isA<ActionSignatureRefused>().having(
            (f) => f.reason,
            'reason',
            ActionSignatureRefusal.notSigned,
          ),
          reason: name,
        );
      }
      expect(transport.requests, isEmpty);
    });

    test('a timed text carries the client\'s clock, in seconds', () async {
      now = DateTime.utc(2026, 11, 12, 17, 0, 41, 999);
      transport.answer(
        temple,
        _testnet,
        '/api/make/',
        Ok(jsonResponse(orderError(1049), statusCode: 501)),
      );
      await inventory['make']?.send(interopUnlockedKey);
      unsignedBody(
        transport.requests.single.body,
        'make:temple:${unixSeconds(DateTime.utc(2026, 11, 12, 17, 0, 41))}',
      );
    });

    test(
      'the alias signed is the coordinator\'s of the embedded list',
      () async {
        final lake = coordinatorNamed('lake');
        transport.answer(
          lake,
          RobosatsNetwork.mainnet,
          '/api/order/',
          Ok(jsonResponse(orderError(1049), statusCode: 501)),
        );
        await client.cancelOrder(
          identity: _us,
          key: interopUnlockedKey,
          lastRead: readOrder(
            orderAnswer(9),
            alias: 'lake',
            network: RobosatsNetwork.mainnet,
          ),
        );
        unsignedBody(
          transport.requests.single.body,
          'cancel:$testOrderId:lake',
        );
      },
    );
  });

  group('the refusals of the fix', () {
    Matcher refused(ActionSignatureRefusal reason) =>
        isA<OrderActionRefused>().having(
          (f) => f.cause,
          'cause',
          isA<ActionSignatureRefused>().having(
            (f) => f.reason,
            'reason',
            reason,
          ),
        );

    for (final (code, reason) in [
      (1059, ActionSignatureRefusal.missing),
      (1060, ActionSignatureRefusal.clockSkew),
      (1061, ActionSignatureRefusal.otherCoordinator),
    ]) {
      test(
        '$code is a refusal before anything was done, for every action',
        () async {
          for (final MapEntry(key: name, value: entry) in inventory.entries) {
            transport.answer(
              temple,
              _testnet,
              entry.path,
              Ok(jsonResponse(orderError(code), statusCode: 400)),
            );
            final result = await entry.send(interopUnlockedKey);
            if (name == 'review') {
              expect(
                result,
                isA<Err<HostReviewToken, CoordinatorFailure>>().having(
                  (r) => r.failure,
                  'failure',
                  isA<ActionSignatureRefused>().having(
                    (f) => f.reason,
                    'reason',
                    reason,
                  ),
                ),
              );
              continue;
            }
            expect(
              switch (result) {
                Err(:final failure) => failure,
                _ => result,
              },
              refused(reason),
              reason: name,
            );
          }
        },
      );
    }

    test(
      '1048 is a refusal of the signature, and still a payout\'s own refusal for a payout',
      () async {
        for (final MapEntry(key: name, value: entry) in inventory.entries) {
          transport.answer(
            temple,
            _testnet,
            entry.path,
            Ok(jsonResponse(orderError(1048), statusCode: 400)),
          );
          final result = await entry.send(interopUnlockedKey);
          final failure = switch (result) {
            Err(:final failure) => failure,
            _ => fail('$name gave no failure'),
          };
          if (name == 'review') {
            expect(failure, isA<ActionSignatureRefused>(), reason: name);
          } else if (name.startsWith('update_')) {
            expect(
              failure,
              isA<OrderActionRefused>().having(
                (f) => f.cause,
                'cause',
                isA<PayoutSignatureRefused>(),
              ),
              reason: name,
            );
          } else {
            expect(
              failure,
              refused(ActionSignatureRefusal.invalid),
              reason: name,
            );
          }
        }
      },
    );
  });
}
