import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;
final _us = interopIdentity;
typedef _Role = OrderRole;

/// The maker's pause and resume (#175): one request with no direction (`Logics.pause_unpause_public_order`, `api/logics.py:1758-1782`, `api/views.py:685-695`, commit ff1998c), what it refuses before sending, and how its answers and failures are read.
///
/// Every answer is built from the reference's code (`test/support/order_answers.dart`), never recorded.
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

  /// The maker's read of its order at [status], a buy order unless [buyer] is false.
  CoordinatorOrder makerAt(int status, {bool buyer = true}) =>
      readOrder(orderAnswer(status, role: _Role.maker, buyer: buyer));

  Map<String, Object?> makerAnswer(int status, {bool buyer = true}) =>
      orderAnswer(status, role: _Role.maker, buyer: buyer);

  Future<Result<TradeActionOutcome, OrderActionFailure>> pause([
    CoordinatorOrder? lastRead,
  ]) => client.pauseOrder(
    identity: _us,
    key: interopUnlockedKey,
    lastRead: lastRead ?? makerAt(1),
  );

  Matcher malformed(String field) => isA<CoordinatorResponseMalformed>().having(
    (f) => f.field,
    'field',
    field,
  );

  group('the request', () {
    test('the reference\'s pause, the same to pause and to resume', () async {
      for (final (from, to) in [(1, 2), (2, 1)]) {
        transport.requests.clear();
        serveJson(makerAnswer(to));
        final outcome = expectOk(await pause(makerAt(from)));
        expect(outcome, isA<TradeActionAccepted>());
        expect(outcome.order.status.wire, to);
        expect(outcome.order.isMaker, isTrue);
        final request = transport.requests.single;
        expect(request.method, CoordinatorHttpMethod.post);
        expect(
          request.url.toString(),
          '${temple.testnet.onion}/api/order/?order_id=$testOrderId',
        );
        expect(request.headers, {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Token ${_us.tokenSha256Base91}',
        });
        // `frontend/src/components/TradeBox/index.tsx:310-313`.
        // Then the signature of `pause:{order_id}:{shortAlias}`, last (GHSA-22q8-9ghc-jg3h).
        expect(
          unsignedBody(request.body, 'pause:$testOrderId:temple'),
          '{"action":"pause"}',
        );
        expect(request.robot, _us.sessionKey);
        expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
      }
    });

    test('a maker seller pauses as a maker buyer', () async {
      serveJson(makerAnswer(2, buyer: false));
      final outcome = expectOk(await pause(makerAt(1, buyer: false)));
      expect(outcome.order.status, CoordinatorOrderStatus.paused);
      expect(outcome.order.isSeller, isTrue);
    });
  });

  group('refused from the last read, nothing sent', () {
    Future<void> refusedLocally(
      CoordinatorOrder lastRead,
      Matcher cause,
    ) async {
      final failure = expectErr(await pause(lastRead));
      expect(failure, isA<OrderActionRefused>());
      expect(failure.cause, cause);
      expect(transport.requests, isEmpty);
    }

    Matcher fromLastRead<T extends TradeActionRefused>() =>
        isA<T>().having((f) => f.fromLastRead, 'fromLastRead', isTrue);

    test('only the maker', () async {
      // Any robot reading a public order, and a pre-taker shown 3.
      await refusedLocally(
        readOrder(orderAnswer(1, role: _Role.outsider)),
        fromLastRead<TradeActionNotMaker>(),
      );
      await refusedLocally(
        readOrder(orderAnswer(1, role: _Role.preTaker)),
        fromLastRead<TradeActionNotMaker>(),
      );
      for (final status in [6, 9, 14]) {
        await refusedLocally(
          readOrder(orderAnswer(status)),
          fromLastRead<TradeActionNotMaker>(),
        );
      }
    });

    test('only at 1 or 2', () async {
      for (final status in [0, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18]) {
        await refusedLocally(
          makerAt(status),
          fromLastRead<TradeActionNotNow>(),
        );
      }
    });

    test('never after a read by another robot', () async {
      final failure = expectErr(
        await client.pauseOrder(
          identity: interopPeerIdentity,
          key: interopPeerUnlockedKey,
          lastRead: makerAt(1),
        ),
      );
      expect(failure, isA<OrderActionRefused>());
      expect(failure.cause, isA<OrderReadElsewhere>());
      expect(transport.requests, isEmpty);
    });
  });

  group('the answers', () {
    test('a status the toggle can lead to is done', () async {
      // Paused or public; expired at its deadline; taken once public again, and the taker's step done.
      for (final status in [1, 2, 5, 6, 7, 8]) {
        for (final buyer in [true, false]) {
          serveJson(makerAnswer(status, buyer: buyer));
          final outcome = expectOk(await pause(makerAt(1, buyer: buyer)));
          expect(outcome.order.status.wire, status, reason: '$status $buyer');
        }
      }
    });

    test('a status no toggle leads to: the outcome is unknown', () async {
      for (final status in [0, 9, 10, 11, 13, 14, 15, 16, 17, 18]) {
        serveJson(makerAnswer(status));
        final failure = expectErr(await pause());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$status');
        expect(failure.cause, malformed('status'), reason: '$status');
      }
    });

    test('this robot in another role: the outcome is unknown', () async {
      serveJson(orderAnswer(1, role: _Role.outsider));
      final failure = expectErr(await pause());
      expect(failure, isA<OrderActionOutcomeUnknown>());
      expect(failure.cause, malformed('is_taker'));
      serveJson(makerAnswer(2, buyer: false));
      final seller = expectErr(await pause());
      expect(seller, isA<OrderActionOutcomeUnknown>());
      expect(seller.cause, malformed('is_buyer'));
    });

    test('an answer of another order: the outcome is unknown', () async {
      serveJson(orderAnswer(2, role: _Role.maker, changes: {'id': 43}));
      final failure = expectErr(await pause());
      expect(failure, isA<OrderActionOutcomeUnknown>());
      expect(failure.cause, malformed('id'));
    });
  });

  group('refusals', () {
    final codes = <int, Matcher>{
      1032: isA<TradeActionNotMaker>(),
      1033: isA<TradeActionNotNow>(),
      1047: isA<OrderNotParticipant>(),
      7000: isA<RobotCredentialsRejected>(),
      7001: isA<RobotUnknown>(),
      7003: isA<RobotCredentialsRejected>(),
    };

    for (final MapEntry(key: code, value: matcher) in codes.entries) {
      test('error $code: refused, nothing done', () async {
        for (final httpStatus in [400, 403, 404, 409]) {
          serveJson(orderError(code), statusCode: httpStatus);
          final failure = expectErr(await pause());
          expect(failure, isA<OrderActionRefused>(), reason: '$httpStatus');
          expect(failure.cause, matcher, reason: '$httpStatus');
          if (failure.cause case final TradeActionRefused refused) {
            expect(refused.fromLastRead, isFalse);
          }
        }
      });
    }

    test('the codes of other actions and of the read: unknown', () async {
      // Another action's refusal is no pause's, and the answer of a pause is the read that follows the toggle (`api/views.py:695`): 1043, 1044, 1022 may come from it.
      for (final code in [
        1013,
        1020,
        1021,
        1022,
        1027,
        1029,
        1030,
        1031,
        1042,
        1043,
        1044,
        1049,
        1054,
      ]) {
        serveJson(orderError(code), statusCode: 400);
        final failure = expectErr(await pause());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$code');
      }
    });

    test('a code on a status that is not 4xx is the status alone', () async {
      for (final status in [500, 501, 302, 201]) {
        serveJson(orderError(1033), statusCode: status);
        final failure = expectErr(await pause());
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
      'nothing done: refused; maybe toggled: unknown, never sent again',
      () async {
        serve(const Err(CoordinatorTransportBusy()));
        expect(expectErr(await pause()), isA<OrderActionRefused>());
        serve(Ok(rawResponse(const [], statusCode: 400, contentType: null)));
        final empty = expectErr(await pause());
        expect(empty, isA<OrderActionRefused>());
        expect(
          empty.cause,
          isA<OrderRequestRefused>().having((f) => f.errorCode, 'code', isNull),
        );
        for (final status in [401, 403]) {
          serveJson({'detail': 'Not authenticated.'}, statusCode: status);
          expect(expectErr(await pause()), isA<OrderActionRefused>());
        }
        for (final answer
            in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
              Ok(
                rawResponse(
                  utf8.encode('<html></html>'),
                  statusCode: 400,
                  contentType: 'text/html',
                ),
              ),
              Ok(rawResponse(utf8.encode('not json'))),
              Ok(
                jsonResponse(
                  orderAnswer(2, role: _Role.maker, changes: {'status': 'two'}),
                ),
              ),
              const Err(CoordinatorUnreachable()),
              const Err(CoordinatorTimedOut()),
              const Err(CoordinatorTransportFailed()),
              const Err(CoordinatorResponseTooLarge()),
            ]) {
          // A coordinator that would answer a second request: the client never sends one, which would undo the first.
          var calls = 0;
          transport
            ..requests.clear()
            ..route(temple, _testnet, '/api/order/', (_) async {
              calls++;
              return calls == 1
                  ? answer
                  : Ok(jsonResponse(orderAnswer(1, role: _Role.maker)));
            });
          final failure = expectErr(await pause());
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: '$answer');
          expect(transport.requests, hasLength(1), reason: '$answer');
        }
      },
    );

    test('a transport that throws: the outcome is unknown', () async {
      transport.route(
        temple,
        _testnet,
        '/api/order/',
        (_) async => throw StateError('broken adapter'),
      );
      final failure = expectErr(await pause());
      expect(failure, isA<OrderActionOutcomeUnknown>());
      expect(failure.cause, isA<CoordinatorTransportFailed>());
    });
  });
}
