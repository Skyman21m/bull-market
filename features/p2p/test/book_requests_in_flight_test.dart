import 'dart:async';

import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// The registry of the book requests in flight, on its own: what a join gets at each moment of a request's life.
void main() {
  const mainnet = RobosatsNetwork.mainnet;
  final temple = coordinator('temple');
  late BookRequestsInFlight inFlight;

  setUp(() => inFlight = BookRequestsInFlight());

  /// An outcome of temple that tells [failure] from another.
  CoordinatorBookOutcome failed(CoordinatorFailure failure) =>
      CoordinatorBookOutcome(temple, Err(failure));

  test(
    'a join made while the request runs gets that request, and a join made from a synchronous listener of its end starts a new one',
    () async {
      var sent = 0;
      final firstAnswer = Completer<CoordinatorBookOutcome>();
      Future<CoordinatorBookOutcome> send() {
        sent++;
        return sent == 1
            ? firstAnswer.future
            : Future.value(failed(const CoordinatorUnreachable()));
      }

      Future<CoordinatorBookOutcome>? rejoined;
      final first = inFlight.join(mainnet, temple, send);
      first
          .then((_) => rejoined = inFlight.join(mainnet, temple, send))
          .ignore();
      expect(inFlight.join(mainnet, temple, send), same(first));
      expect(sent, 1);

      firstAnswer.complete(failed(const CoordinatorTimedOut()));
      await Future<void>.delayed(Duration.zero);
      expect(sent, 2);
      final again = rejoined;
      if (again == null) fail('no join from the listener');
      expect(identical(again, first), isFalse);
      expect(
        (await first).result,
        isA<Err<OrderBook, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorTimedOut>(),
        ),
      );
      expect(
        (await again).result,
        isA<Err<OrderBook, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorUnreachable>(),
        ),
      );
      expect(inFlight.isInFlight(mainnet, temple), isFalse);
    },
  );

  test(
    'a send that throws leaves no entry: the next join sends again',
    () async {
      expect(
        () => inFlight.join(
          mainnet,
          temple,
          () => throw StateError('a bug of the caller'),
        ),
        throwsStateError,
      );
      expect(inFlight.isInFlight(mainnet, temple), isFalse);

      final next = inFlight.join(
        mainnet,
        temple,
        () async => failed(const CoordinatorTimedOut()),
      );
      expect(inFlight.isInFlight(mainnet, temple), isTrue);
      expect((await next).result, isA<Err<OrderBook, CoordinatorFailure>>());
      expect(inFlight.isInFlight(mainnet, temple), isFalse);
    },
  );

  test(
    'a request that fails on a bug is forgotten, and the bug reaches whoever joined',
    () async {
      final joined = inFlight.join(
        mainnet,
        temple,
        () => Future.error(StateError('a bug of the request')),
      );
      await expectLater(joined, throwsStateError);
      expect(inFlight.isInFlight(mainnet, temple), isFalse);
    },
  );
}
