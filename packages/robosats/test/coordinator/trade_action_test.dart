import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

const _testnet = RobosatsNetwork.testnet;
final _us = interopIdentity;
final _peer = interopPeerIdentity;
typedef _Role = OrderRole;
const _answer = orderAnswer;
const _error = orderError;
const _read = readOrder;
const _readAt = readOrderAt;

/// The four actions of the trade's chat step (#95): what each sends, what it refuses before sending, and how its answers and failures are read (`api/views.py:651-695`, `api/logics.py:485-533`, `:1686-1789`, commit ff1998c).
void main() {
  final temple = coordinatorNamed('temple');
  // The fixtures' chat ends at 11:00 on 2026-11-13: a dispute opens from 17:00 the day before.
  final disputeOpens = DateTime.utc(2026, 11, 12, 17);
  late FakeCoordinatorTransport transport;
  late CoordinatorClient client;
  late DateTime now;

  setUp(() {
    transport = FakeCoordinatorTransport();
    now = disputeOpens;
    client = CoordinatorClient(transport, clock: () => now);
  });

  void serve(Result<CoordinatorResponse, CoordinatorTransportFailure> answer) =>
      transport.answer(temple, _testnet, '/api/order/', answer);

  void serveJson(Object? json, {int statusCode = 200}) =>
      serve(Ok(jsonResponse(json, statusCode: statusCode)));

  Future<Result<TradeActionOutcome, OrderActionFailure>> confirm([
    CoordinatorOrder? lastRead,
  ]) => client.confirmFiat(identity: _us, lastRead: lastRead ?? _readAt(9));

  Future<Result<TradeActionOutcome, OrderActionFailure>> undo([
    CoordinatorOrder? lastRead,
  ]) =>
      client.undoConfirmFiat(identity: _us, lastRead: lastRead ?? _readAt(10));

  Future<Result<TradeActionOutcome, OrderActionFailure>> dispute([
    CoordinatorOrder? lastRead,
  ]) => client.openDispute(identity: _us, lastRead: lastRead ?? _readAt(9));

  Future<Result<TradeActionOutcome, OrderActionFailure>> rate([
    CoordinatorOrder? lastRead,
    int stars = 5,
  ]) => client.ratePlatform(
    identity: _us,
    lastRead: lastRead ?? _readAt(14),
    rating: PlatformRating.of(stars)!,
  );

  /// Each action from a last read at which it is sent.
  final actions =
      <
        String,
        Future<Result<TradeActionOutcome, OrderActionFailure>> Function()
      >{
        'confirm': confirm,
        'undo_confirm': undo,
        'dispute': dispute,
        'rate_platform': rate,
      };

  void expectPost(String body) {
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
    expect(request.body, utf8.encode(body));
    expect(request.robot, _us.sessionKey);
    expect(request.maxResponseBytes, CoordinatorReadBounds.orderBytes);
  }

  group('the requests', () {
    test('« fiat sent » is the reference\'s confirm', () async {
      serveJson(_answer(10));
      final outcome = expectOk(await confirm());
      expectPost('{"action":"confirm"}');
      expect(outcome.order.status, CoordinatorOrderStatus.fiatSent);
      expect(outcome.order.isFiatSent, isTrue);
    });

    test('its undo is the reference\'s undo_confirm', () async {
      serveJson(_answer(9));
      final outcome = expectOk(await undo());
      expectPost('{"action":"undo_confirm"}');
      expect(outcome.order.status, CoordinatorOrderStatus.sendingFiat);
      expect(outcome.order.isFiatSent, isFalse);
    });

    test('a dispute is the reference\'s dispute', () async {
      for (final status in [9, 10]) {
        transport.requests.clear();
        serveJson(_answer(11));
        final outcome = expectOk(await dispute(_readAt(status)));
        expectPost('{"action":"dispute"}');
        expect(outcome.order.status, CoordinatorOrderStatus.inDispute);
      }
    });

    test('a rating sends its stars as a number, as the reference', () async {
      for (final stars in [1, 2, 3, 4, 5]) {
        transport.requests.clear();
        serveJson(_answer(14));
        expectOk(await rate(null, stars));
        expectPost('{"action":"rate_platform","rating":$stars}');
      }
    });

    test('a rating is 1 to 5 stars', () {
      expect(PlatformRating.of(0), isNull);
      expect(PlatformRating.of(6), isNull);
      expect(PlatformRating.of(-1), isNull);
      expect(PlatformRating.of(3)?.stars, 3);
      expect(PlatformRating.of(3), PlatformRating.of(3));
    });

    test(
      'an action goes to the order, coordinator and network of its last read',
      () async {
        final lake = coordinatorNamed('lake');
        final lastRead = _read(
          _answer(9, changes: {'id': 43}),
          alias: 'lake',
          network: RobosatsNetwork.mainnet,
        );
        transport.answer(
          lake,
          RobosatsNetwork.mainnet,
          '/api/order/',
          Ok(jsonResponse(_answer(10, changes: {'id': 43}))),
        );
        expectOk(await confirm(lastRead));
        expect(
          transport.requests.single.url.toString(),
          '${lake.mainnet.onion}/api/order/?order_id=43',
        );
      },
    );
  });

  group('refused from the last read, nothing sent', () {
    Future<void> refusedLocally(
      Future<Result<TradeActionOutcome, OrderActionFailure>> action,
      Matcher cause,
    ) async {
      final failure = expectErr(await action);
      expect(failure, isA<OrderActionRefused>());
      expect(failure.cause, cause);
      expect(transport.requests, isEmpty);
    }

    Matcher fromLastRead<T extends TradeActionRefused>() =>
        isA<T>().having((f) => f.fromLastRead, 'fromLastRead', isTrue);

    test('« fiat sent » only by the buyer, only at 9', () async {
      final seller = _read(_answer(9, buyer: false));
      await refusedLocally(
        confirm(seller),
        fromLastRead<TradeActionNotBuyer>(),
      );
      for (final status in [6, 8, 10, 11, 13, 14]) {
        await refusedLocally(
          confirm(_readAt(status)),
          fromLastRead<TradeActionNotNow>(),
        );
      }
      await refusedLocally(
        confirm(_readAt(1, role: _Role.preTaker)),
        fromLastRead<TradeActionNotNow>(),
      );
    });

    test('its undo only by the buyer, only at 10', () async {
      final seller = _read(_answer(10, buyer: false));
      await refusedLocally(undo(seller), fromLastRead<TradeActionNotBuyer>());
      for (final status in [8, 9, 11, 13]) {
        await refusedLocally(
          undo(_readAt(status)),
          fromLastRead<TradeActionNotNow>(),
        );
      }
    });

    test('a dispute only at 9 or 10, by a participant', () async {
      for (final status in [6, 7, 8, 11, 13, 14, 15, 16]) {
        await refusedLocally(
          dispute(_readAt(status)),
          fromLastRead<TradeActionNotNow>(),
        );
      }
      await refusedLocally(
        dispute(_readAt(1, role: _Role.outsider)),
        isA<OrderNotParticipant>(),
      );
    });

    test(
      'a dispute not before 18 hours before the chat ends, by this clock',
      () async {
        now = disputeOpens.subtract(const Duration(microseconds: 1));
        for (final status in [9, 10]) {
          await refusedLocally(
            dispute(_readAt(status)),
            fromLastRead<DisputeTooEarly>(),
          );
        }
        now = disputeOpens;
        serveJson(_answer(11));
        expectOk(await dispute());
        expect(transport.requests, hasLength(1));
      },
    );

    test('a rating only by a participant', () async {
      await refusedLocally(
        rate(_readAt(1, role: _Role.outsider)),
        isA<OrderNotParticipant>(),
      );
    });

    test('no action after a read by another robot', () async {
      for (final status in [9, 10, 14]) {
        final theirs = _read(
          _answer(
            status,
            changes: {
              'ur_nick': _peer.nickname,
              'taker_hash_id': _peer.hashId.hex,
              'taker_nick': _peer.nickname,
              'maker_hash_id': _us.hashId.hex,
              'maker_nick': _us.nickname,
            },
          ),
          identity: _peer,
        );
        for (final action in [
          confirm(theirs),
          undo(theirs),
          dispute(theirs),
          rate(theirs),
        ]) {
          await refusedLocally(action, isA<OrderReadElsewhere>());
        }
      }
    });
  });

  group('the answers', () {
    test('an answer for this robot in another role is malformed', () async {
      for (final (role, buyer, field) in [
        // Still the buyer, but as the maker of a buy order, not the taker of the sell order read last.
        (_Role.maker, true, 'is_taker'),
        // Still the taker, but of a buy order: the seller.
        (_Role.taker, false, 'is_buyer'),
      ]) {
        for (final MapEntry(key: name, value: action) in actions.entries) {
          final status = name == 'undo_confirm' ? 9 : 10;
          serveJson(_answer(status, role: role, buyer: buyer));
          final failure = expectErr(await action());
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: name);
          expect(
            failure.cause,
            isA<CoordinatorResponseMalformed>().having(
              (f) => f.field,
              'field',
              field,
            ),
            reason: '$name $role $buyer',
          );
        }
      }
    });

    test('an answer of another order is malformed', () async {
      serveJson(_answer(10, changes: {'id': 43}));
      final failure = expectErr(await confirm());
      expect(failure, isA<OrderActionOutcomeUnknown>());
      expect(failure.cause, isA<CoordinatorResponseMalformed>());
    });
  });

  group('refusals', () {
    // The codes each action's `Logics` answers before it changes anything.
    final codes = <int, Matcher>{
      1013: isA<TradeActionNotNow>(),
      1027: isA<TradeActionNotNow>(),
      1029: isA<TradeActionNotNow>(),
      1030: isA<TradeActionNotBuyer>(),
      1031: isA<TradeActionNotNow>(),
      1054: isA<DisputeTooEarly>(),
      1047: isA<OrderNotParticipant>(),
      7000: isA<RobotCredentialsRejected>(),
      7001: isA<RobotUnknown>(),
      7003: isA<RobotCredentialsRejected>(),
    };
    const httpStatuses = [400, 403, 404, 409];

    for (final MapEntry(key: code, value: matcher) in codes.entries) {
      test('error $code: refused, nothing done', () async {
        for (final httpStatus in httpStatuses) {
          for (final MapEntry(key: name, value: action) in actions.entries) {
            serveJson(_error(code), statusCode: httpStatus);
            final failure = expectErr(await action());
            expect(failure, isA<OrderActionRefused>(), reason: '$name $code');
            expect(failure.cause, matcher, reason: '$name $code');
            if (failure.cause case final TradeActionRefused refused) {
              expect(refused.fromLastRead, isFalse);
            }
          }
        }
      });
    }

    test(
      'the codes of the reads and the other actions: the outcome is unknown',
      () async {
        // A code that is not one of these actions' refusals may come from the read that follows the action (`api/views.py:695`): 1043 if the order was cancelled meanwhile, 1044, 1042; or it is one the reference never answers to them.
        for (final code in [1020, 1021, 1042, 1043, 1044, 1048, 1049, 3001]) {
          for (final MapEntry(key: name, value: action) in actions.entries) {
            serveJson(_error(code), statusCode: 400);
            final failure = expectErr(await action());
            expect(
              failure,
              isA<OrderActionOutcomeUnknown>(),
              reason: '$name $code',
            );
          }
        }
      },
    );

    test('a code on a status that is not 4xx is the status alone', () async {
      for (final status in [500, 501, 502, 302, 201]) {
        for (final MapEntry(key: name, value: action) in actions.entries) {
          serveJson(_error(1029), statusCode: status);
          final failure = expectErr(await action());
          expect(failure, isA<OrderActionOutcomeUnknown>(), reason: name);
          expect(
            failure.cause,
            isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              status,
            ),
          );
        }
      }
    });

    test(
      'the failures that say nothing was done, and those that do not',
      () async {
        for (final MapEntry(key: name, value: action) in actions.entries) {
          // Nothing sent, or refused before the action.
          serve(const Err(CoordinatorTransportBusy()));
          expect(
            expectErr(await action()),
            isA<OrderActionRefused>(),
            reason: name,
          );
          serve(Ok(rawResponse(const [], statusCode: 400)));
          expect(
            expectErr(await action()),
            isA<OrderActionRefused>(),
            reason: name,
          );
          for (final status in [401, 403]) {
            serveJson({'detail': 'Not authenticated.'}, statusCode: status);
            expect(
              expectErr(await action()),
              isA<OrderActionRefused>(),
              reason: '$name $status',
            );
          }
          // Anything that may come after the action.
          for (final answer
              in <Result<CoordinatorResponse, CoordinatorTransportFailure>>[
                Ok(
                  rawResponse(
                    utf8.encode('<html></html>'),
                    statusCode: 400,
                    contentType: 'text/html',
                  ),
                ),
                Ok(jsonResponse(_answer(10, changes: {'status': 'ten'}))),
                Ok(rawResponse(utf8.encode('not json'))),
                const Err(CoordinatorUnreachable()),
                const Err(CoordinatorTimedOut()),
                const Err(CoordinatorTransportFailed()),
                const Err(CoordinatorResponseTooLarge()),
              ]) {
            serve(answer);
            expect(
              expectErr(await action()),
              isA<OrderActionOutcomeUnknown>(),
              reason: '$name $answer',
            );
          }
        }
      },
    );

    test('a transport that throws: the outcome is unknown', () async {
      for (final MapEntry(key: name, value: action) in actions.entries) {
        transport.route(
          temple,
          _testnet,
          '/api/order/',
          (_) async => throw StateError('broken adapter'),
        );
        final failure = expectErr(await action());
        expect(failure, isA<OrderActionOutcomeUnknown>(), reason: name);
        expect(failure.cause, isA<CoordinatorTransportFailed>());
      }
    });
  });

  test('nothing of the answer is printed', () async {
    serveJson(_answer(10));
    final outcome = expectOk(await confirm());
    expect('$outcome', isNot(contains(_us.nickname)));
    expect('$outcome', isNot(contains('Revolut')));
  });
}
