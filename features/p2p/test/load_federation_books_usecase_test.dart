import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/book_attempts.dart';
import 'support/fakes.dart';

void main() {
  late ScriptedTransport transport;
  late FakeWaits waits;
  late LoadFederationBooksUsecase usecase;

  void build({RobosatsNetwork network = RobosatsNetwork.mainnet}) {
    usecase = LoadFederationBooksUsecase(
      RequestFederationBooksUsecase(
        FederationBookReader(transport, clock: () => testNow),
        Federation.robosats,
      ),
      waits.waits,
    );
  }

  setUp(() {
    transport = ScriptedTransport(
      books: {
        'temple': [bookOrder(id: 1)],
        'lake': [bookOrder(id: 2, makerSeed: 2)],
      },
    );
    waits = FakeWaits();
    build();
  });

  /// Lets the requests of the fake transport and their outcomes run.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// The attempts of [alias] alone on mainnet.
  CoordinatorBookAttempts ask(String alias) =>
      usecase.execute(
        RobosatsNetwork.mainnet,
        only: {coordinator(alias)},
      )[coordinator(alias)] ??
      (throw StateError('no attempts for $alias'));

  /// The orders of a book outcome.
  List<int> idsOf(Result<OrderBook, CoordinatorFailure>? outcome) =>
      switch (outcome) {
        Ok(:final value) => [for (final order in value.orders) order.id],
        _ => throw StateError('no book: $outcome'),
      };

  Future<Result<OrderBook, CoordinatorFailure>?> outcomeNow(
    CoordinatorBookAttempts attempts,
  ) async {
    Result<OrderBook, CoordinatorFailure>? outcome;
    var done = false;
    attempts.outcome.then((value) {
      outcome = value;
      done = true;
    }).ignore();
    await settle();
    if (!done) throw StateError('no outcome yet');
    return outcome;
  }

  group('each failure kind', () {
    for (final failure in const <CoordinatorTransportFailure>[
      CoordinatorUnreachable(),
      CoordinatorTimedOut(),
      CoordinatorTransportFailed(),
      CoordinatorTransportBusy(),
    ]) {
      test(
        '${failure.runtimeType}: asked again after 5 seconds, and its book taken',
        () async {
          transport.script['temple'] = [ScriptedFailure(failure)];
          final attempts = ask('temple');
          await settle();

          expect(transport.requestsTo('temple'), 1);
          expect(waits.pending.map((timer) => timer.duration), [
            const Duration(seconds: 5),
          ]);
          expect(attempts.isWaiting, isTrue);

          waits.fireAll();
          await settle();
          expect(transport.requestsTo('temple'), 2);
          expect(idsOf(await outcomeNow(attempts)), [1]);
          expect(attempts.attempts, 2);
          expect(waits.pending, isEmpty);
        },
      );
    }

    for (final (name, scripted) in const [
      ('not JSON', ScriptedUnusable(contentType: 'text/plain')),
      ('an unexpected status', ScriptedUnusable(status: 500)),
      ('not a book', ScriptedUnusable()),
      ('too large', ScriptedFailure(CoordinatorResponseTooLarge())),
    ]) {
      test(
        'an answer $name is not asked again: the coordinator answered',
        () async {
          transport.script['temple'] = [scripted];
          final attempts = ask('temple');

          final outcome = await outcomeNow(attempts);
          expect(outcome, isA<Err<OrderBook, CoordinatorFailure>>());
          expect(transport.requestsTo('temple'), 1);
          expect(waits.started, isEmpty);
          expect(waits.draws, 0);
        },
      );
    }
  });

  group('a coordinator not reached yet in this book', () {
    test(
      'is asked three times in all, after 5 then 15 seconds, then gives its last failure',
      () async {
        transport.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
          ScriptedFailure(CoordinatorUnreachable()),
          ScriptedFailure(CoordinatorTimedOut()),
        ];
        final attempts = ask('temple');
        var done = false;
        attempts.outcome.then((_) => done = true).ignore();
        await settle();
        expect(waits.pending.single.duration, const Duration(seconds: 5));

        waits.fireAll();
        await settle();
        expect(transport.requestsTo('temple'), 2);
        expect(waits.pending.single.duration, const Duration(seconds: 15));
        expect(done, isFalse);

        waits.fireAll();
        await settle();
        expect(transport.requestsTo('temple'), 3);
        expect(waits.pending, isEmpty);
        expect(done, isTrue);
        expect(
          await attempts.outcome,
          isA<Err<OrderBook, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<CoordinatorTimedOut>(),
          ),
        );
        expect(attempts.attempts, 3);
        expect(waits.started.map((timer) => timer.duration), const [
          Duration(seconds: 5),
          Duration(seconds: 15),
        ]);
      },
    );

    test('gives its book on the third attempt', () async {
      transport.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
        ScriptedFailure(CoordinatorTransportFailed()),
      ];
      final attempts = ask('temple');
      await settle();
      waits.fireAll();
      await settle();
      waits.fireAll();

      expect(idsOf(await outcomeNow(attempts)), [1]);
      expect(attempts.attempts, 3);
    });

    test('each wait is spread by the draw, within its bounds', () async {
      transport.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
        ScriptedFailure(CoordinatorUnreachable()),
        ScriptedFailure(CoordinatorUnreachable()),
      ];
      waits.draw = 0;
      final attempts = ask('temple');
      await settle();
      expect(waits.pending.single.duration, const Duration(seconds: 4));
      waits
        ..draw = 0.999999
        ..fireAll();
      await settle();
      expect(
        waits.pending.single.duration,
        const Duration(microseconds: 17999994),
      );
      // One draw per wait, and none for the last failure.
      waits.fireAll();
      await settle();
      expect(waits.draws, 2);
      expect(await attempts.outcome, isA<Err<OrderBook, CoordinatorFailure>>());
    });
  });

  group('a coordinator that gave its book before in this book', () {
    test('is asked twice in all, the second time after 5 seconds', () async {
      expect(idsOf(await outcomeNow(ask('temple'))), [1]);

      transport.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
        ScriptedFailure(CoordinatorUnreachable()),
      ];
      final attempts = ask('temple');
      await settle();
      expect(waits.pending.single.duration, const Duration(seconds: 5));
      waits.fireAll();

      expect(
        await outcomeNow(attempts),
        isA<Err<OrderBook, CoordinatorFailure>>(),
      );
      expect(transport.requestsTo('temple'), 3);
      expect(waits.started, hasLength(1));
    });

    test(
      'a book of another instance does not count: each book has its own',
      () async {
        expect(idsOf(await outcomeNow(ask('temple'))), [1]);
        build();

        transport.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
          ScriptedFailure(CoordinatorUnreachable()),
        ];
        ask('temple');
        await settle();
        waits.fireAll();
        await settle();
        expect(waits.pending.single.duration, const Duration(seconds: 15));
      },
    );
  });

  group('nothing sent twice at once to one coordinator', () {
    test('a second call joins the request in flight', () async {
      transport.held.add('temple');
      final first = ask('temple');
      final second = ask('temple');
      await settle();
      expect(transport.requestsTo('temple'), 1);

      transport.release('temple');
      expect(idsOf(await outcomeNow(first)), [1]);
      expect(idsOf(await outcomeNow(second)), [1]);
      expect(transport.mostAtOnce['temple'], 1);
    });

    test(
      'an attempt due while another call has a request in flight joins it',
      () async {
        transport.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
        ];
        final waiting = ask('temple');
        await settle();
        expect(waiting.isWaiting, isTrue);

        transport.held.add('temple');
        final other = ask('temple');
        await settle();
        expect(transport.requestsTo('temple'), 2);

        waits.fireAll();
        await settle();
        expect(transport.requestsTo('temple'), 2);
        expect(transport.mostAtOnce['temple'], 1);

        transport.release('temple');
        expect(idsOf(await outcomeNow(waiting)), [1]);
        expect(idsOf(await outcomeNow(other)), [1]);
      },
    );

    test(
      'a call while one coordinator is in flight sends only to the others',
      () async {
        transport.held.add('temple');
        usecase.execute(RobosatsNetwork.mainnet);
        await settle();
        transport.requested.clear();

        usecase.execute(RobosatsNetwork.mainnet);
        await settle();
        expect(transport.requestsTo('temple'), 0);
        expect(
          transport.requested,
          unorderedEquals([
            for (final coordinator in Federation.robosats.on(
              RobosatsNetwork.mainnet,
            ))
              if (coordinator.shortAlias != 'temple')
                '${coordinator.shortAlias}/api/book/',
          ]),
        );
        transport.release('temple');
        await settle();
      },
    );
  });

  group('cancel', () {
    test('ends the wait at once and sends nothing more', () async {
      transport.script['temple'] = const [
        ScriptedFailure(CoordinatorUnreachable()),
      ];
      final attempts = ask('temple');
      await settle();
      final wait = waits.pending.single;

      attempts.cancel();
      expect(wait.cancelled, isTrue);
      expect(await attempts.outcome, isNull);
      wait.fire();
      await settle();
      expect(transport.requestsTo('temple'), 1);
    });

    test('drops the answer of a request in flight', () async {
      transport.held.add('temple');
      final attempts = ask('temple');
      await settle();

      attempts.cancel();
      transport.release('temple');
      await settle();
      expect(await attempts.outcome, isNull);
      expect(waits.started, isEmpty);
    });
  });

  group('stop asking again', () {
    test(
      'while a wait runs: the last failure at once, nothing more sent',
      () async {
        transport.script['temple'] = const [
          ScriptedFailure(CoordinatorTimedOut()),
        ];
        final attempts = ask('temple');
        await settle();
        final wait = waits.pending.single;

        attempts.stopAskingAgain();
        expect(wait.cancelled, isTrue);
        expect(
          await outcomeNow(attempts),
          isA<Err<OrderBook, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<CoordinatorTimedOut>(),
          ),
        );
        expect(transport.requestsTo('temple'), 1);
      },
    );

    test('while a request is in flight: its failure is the last', () async {
      transport
        ..script['temple'] = const [ScriptedFailure(CoordinatorUnreachable())]
        ..held.add('temple');
      final attempts = ask('temple');
      await settle();

      attempts.stopAskingAgain();
      transport.release('temple');
      expect(
        await outcomeNow(attempts),
        isA<Err<OrderBook, CoordinatorFailure>>(),
      );
      expect(waits.started, isEmpty);
    });

    test('while a request is in flight: its book is still taken', () async {
      transport.held.add('temple');
      final attempts = ask('temple');
      await settle();

      attempts.stopAskingAgain();
      transport.release('temple');
      expect(idsOf(await outcomeNow(attempts)), [1]);
    });
  });

  group('the federation', () {
    test(
      'every coordinator is asked at once, and one asked again delays no other',
      () async {
        transport.script['temple'] = const [
          ScriptedFailure(CoordinatorUnreachable()),
        ];
        final all = usecase.execute(RobosatsNetwork.mainnet);
        expect(all.keys, Federation.robosats.on(RobosatsNetwork.mainnet));
        await settle();
        expect(transport.requested, hasLength(all.length));

        final lake = all[coordinator('lake')];
        if (lake == null) fail('no attempts for lake');
        expect(idsOf(await outcomeNow(lake)), [2]);
        expect(all[coordinator('temple')]?.isWaiting, isTrue);
      },
    );

    test(
      'testnet asks its two coordinators, and asks again the same way',
      () async {
        transport = ScriptedTransport(
          network: RobosatsNetwork.testnet,
          script: {
            'lake': const [
              ScriptedFailure(CoordinatorUnreachable()),
              ScriptedFailure(CoordinatorUnreachable()),
              ScriptedFailure(CoordinatorUnreachable()),
            ],
          },
        );
        build(network: RobosatsNetwork.testnet);
        final all = usecase.execute(RobosatsNetwork.testnet);
        expect(all.keys.map((c) => c.shortAlias), ['temple', 'lake']);
        await settle();
        expect(
          transport.requested,
          unorderedEquals(['temple/api/book/', 'lake/api/book/']),
        );
        waits.fireAll();
        await settle();
        waits.fireAll();
        await settle();

        expect(transport.requestsTo('lake'), 3);
        expect(transport.requestsTo('temple'), 1);
        expect(
          await all[coordinator('lake')]?.outcome,
          isA<Err<OrderBook, CoordinatorFailure>>(),
        );
        expect(
          await all[coordinator('temple')]?.outcome,
          isA<Ok<OrderBook, CoordinatorFailure>>(),
        );
      },
    );
  });
}
