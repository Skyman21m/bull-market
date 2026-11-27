import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/testing.dart' show ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show CoordinatorHttpMethod, OrderWrongPassword;
import 'package:test/test.dart';

import 'support/signed_bodies.dart';
import 'support/trade_harness.dart';

/// The take of a password-protected order (#245): read by the robot that will take it, since no book lists it; prepared and confirmed as an order of the book is (#119), every protection kept; the password sent as its SHA-256 only, never kept.
void main() {
  const password = 'sesame';
  final hash = sha256.convert(utf8.encode(password)).toString();

  Matcher refused<T>() => isA<Err<Object?, TakeRefusal>>().having(
    (err) => err.failure,
    'refusal',
    isA<T>(),
  );

  int count(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// The body of the last take sent, before its signature (GHSA-22q8-9ghc-jg3h).
  String takeBody(TradeHarness app) => unsignedBodyOf(
    app.coordinator.requests
        .lastWhere(
          (request) =>
              request.method == CoordinatorHttpMethod.post &&
              request.url.path == '/api/order/',
        )
        .body,
  );

  Future<(TradeHarness, UnlistedOrder)> readOne({
    bool range = false,
    double takerFee = 0.00175,
  }) async {
    final app = await TradeHarness.start(
      password: password,
      range: range,
      takerFee: takerFee,
    );
    app.coordinator
      ..description = 'Cash in hand, near the station.'
      ..meetingPoint = (45.76, 4.83);
    return switch (await app.take.readUnlisted(
      app.coordinator.coordinator,
      42,
      network: app.network,
    )) {
      Ok(:final value) => (app, value),
      Err(:final failure) => fail('not read: $failure'),
    };
  }

  Future<PreparedTake> prepare(
    TradeHarness app,
    UnlistedOrder shown, {
    TakeAmount? amount,
  }) async => switch (await app.take.prepareUnlisted(shown, amount: amount)) {
    Ok(:final value) => value,
    Err(:final failure) => fail('not prepared: $failure'),
  };

  group('a password-protected order (#245)', () {
    test(
      'no book lists it; the robot that will take it reads it, without its description or place, and nothing is taken',
      () async {
        final (app, shown) = await readOne();
        final sent = List.of(app.coordinator.received);
        // The coordinator's book leaves it out (`api/views.py:788-790`).
        await expectLater(app.shownOrder(), throwsStateError);
        expect(shown.order.id, 42);
        expect(shown.order.coordinator, app.coordinator.coordinator);
        expect(
          shown.order.satoshisNow?.value.toInt(),
          app.coordinator.satoshisNow,
        );
        expect(shown.order.location, isNull);
        expect(shown.network, app.network);
        expect(shown.readAt, app.now);
        // The robot read back then its first contact, then its read of the order: no take, no trade.
        expect(sent, [
          ScriptedRequest.robot,
          ScriptedRequest.robot,
          ScriptedRequest.order,
        ]);
        expect(await app.allTrades(), isEmpty);
        expect(app.coordinator.holdsPreTake(app.robot(0)), isFalse);
      },
    );

    test(
      'taken with its password: the same robot reads it twice more, the take sends the SHA-256 and never the text',
      () async {
        final (app, shown) = await readOne();
        final prepared = await prepare(app, shown);
        // Still hidden before the take.
        expect(prepared.description, isNull);
        expect(prepared.order.hasPassword, isTrue);
        expect(
          await app.take.confirm(
            prepared,
            password: OrderPassword.tryCreate(password),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
        expect(count(app, ScriptedRequest.order), 3);
        // Twice for the robot itself, once more for the key its take is signed with (GHSA-22q8-9ghc-jg3h).
        expect(count(app, ScriptedRequest.robot), 3);
        expect(count(app, ScriptedRequest.take), 1);
        final body = takeBody(app);
        expect(body, '{"action":"take","password":"$hash","amount":0}');
        expect(body, isNot(contains(password)));
        expect(app.coordinator.holdsPreTake(app.robot(0)), isTrue);
        final [record] = await app.activeRecords();
        expect(record.orderId, 42);
        // Whether the order had a password is nowhere in the trade's records, nor the password or its hash.
        final rows = [
          ...await app.allTrades(),
          for (final table in ['trade_terms', 'trade_trails'])
            ...(await app.database.customSelect('SELECT * FROM $table').get())
                .map((row) => row.data),
        ];
        expect('$rows', isNot(contains(hash)));
        expect('$rows', isNot(contains(password)));
      },
    );

    test(
      'a wrong password: refused by the coordinator (1045), no trade open, nothing to pay; a new read with a fresh robot takes it with the right one',
      () async {
        final (app, shown) = await readOne();
        final first = await prepare(app, shown);
        expect(
          await app.take.confirm(
            first,
            password: OrderPassword.tryCreate('open'),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeNotMade>().having(
              (n) => n.refusal,
              'refusal',
              isA<OrderWrongPassword>(),
            ),
          ),
        );
        expect(await app.activeRecords(), isEmpty);
        expect(app.coordinator.holdsPreTake(app.robot(0)), isFalse);
        // The robot of the take not made is never used again: the next preparation reserves another.
        final second = await prepare(app, shown);
        expect(
          await app.take.confirm(
            second,
            password: OrderPassword.tryCreate(password),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
        expect(app.coordinator.holdsPreTake(app.robot(1)), isTrue);
        expect(app.coordinator.holdsPreTake(app.robot(0)), isFalse);
        expect(await app.activeRecords(), hasLength(1));
      },
    );

    test(
      'without a password nothing is read again or sent, and the preparation can still be confirmed',
      () async {
        final (app, shown) = await readOne();
        final prepared = await prepare(app, shown);
        final before = List.of(app.coordinator.received);
        expect(OrderPassword.tryCreate(''), isNull);
        expect(
          await app.take.confirm(prepared),
          refused<TakePasswordMissing>(),
        );
        expect(app.coordinator.received, before);
        expect(await app.allTrades(), isEmpty);
        expect(
          await app.take.confirm(
            prepared,
            password: OrderPassword.tryCreate(password),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
      },
    );

    test(
      'every protection of the take holds: an order read otherwise is refused before any take, at the preparation and at the confirmation',
      () async {
        for (final (label, change) in [
          ('premium', {'premium': '5.00', 'premium_now': 5.0}),
          ('bond', {'bond_size': '4.00'}),
          ('escrow', {'escrow_duration': 7200}),
          ('sats', {'satoshis_now': 110107}),
          ('no longer protected', {'has_password': false}),
        ]) {
          final (app, shown) = await readOne();
          app.coordinator.robotView.addAll(change);
          expect(
            await app.take.prepareUnlisted(shown),
            label == 'no longer protected'
                ? refused<TakeOrderGone>()
                : refused<TakeOrderChanged>(),
            reason: label,
          );
          expect(count(app, ScriptedRequest.take), 0, reason: label);
          expect(await app.allTrades(), isEmpty, reason: label);
        }
        for (final (label, change) in [
          ('sats', {'satoshis_now': 110107}),
          ('bond', {'bond_size': '4.00'}),
          ('premium', {'premium': '5.00', 'premium_now': 5.0}),
          ('no longer protected', {'has_password': false}),
        ]) {
          final (app, shown) = await readOne();
          final prepared = await prepare(app, shown);
          app.coordinator.robotView.addAll(change);
          expect(
            await app.take.confirm(
              prepared,
              password: OrderPassword.tryCreate(password),
            ),
            label == 'no longer protected'
                ? refused<TakeOrderGone>()
                : refused<TakeOrderChanged>(),
            reason: label,
          );
          expect(count(app, ScriptedRequest.take), 0, reason: label);
          expect(await app.allTrades(), isEmpty, reason: label);
        }
      },
    );

    test(
      'a taker fee above the ceiling, or an amount outside the range, is refused before the robot reads again',
      () async {
        final (expensive, shown) = await readOne(takerFee: 0.02);
        final reads = count(expensive, ScriptedRequest.order);
        expect(
          await expensive.take.prepareUnlisted(shown),
          isA<Err<PreparedTake, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeTermsRefused>().having(
              (refusal) => refusal.reason,
              'reason',
              isA<TakerFeeTooHigh>(),
            ),
          ),
        );
        expect(count(expensive, ScriptedRequest.order), reads);
        final (range, ranged) = await readOne(range: true);
        expect(
          await range.take.prepareUnlisted(ranged),
          refused<TakeAmountRefused>(),
        );
        expect(
          await range.take.prepareUnlisted(
            ranged,
            amount: TakeAmount.tryCreate(250),
          ),
          refused<TakeAmountRefused>(),
        );
        final prepared = await prepare(
          range,
          ranged,
          amount: TakeAmount.tryCreate(120),
        );
        expect(
          await range.take.confirm(
            prepared,
            password: OrderPassword.tryCreate(password),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>(),
        );
        expect(
          takeBody(range),
          '{"action":"take","password":"$hash","amount":120}',
        );
      },
    );

    test(
      'a public order without a password reached by its URL: read, prepared and taken with every comparison of the take, never with a password',
      () async {
        final app = await TradeHarness.start();
        final shown = switch (await app.take.readUnlisted(
          app.coordinator.coordinator,
          42,
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not read: $failure'),
        };
        expect(shown.hasPassword, isFalse);
        // Read again otherwise than the page shows it: refused, nothing taken.
        app.coordinator.robotView['bond_size'] = '4.00';
        expect(
          await app.take.prepareUnlisted(shown),
          refused<TakeOrderChanged>(),
        );
        app.coordinator.robotView.clear();
        final prepared = await prepare(app, shown);
        expect(prepared.order.hasPassword, isFalse);
        // At the confirmation too.
        app.coordinator.robotView['premium'] = '5.00';
        app.coordinator.robotView['premium_now'] = 5.0;
        expect(
          await app.take.confirm(
            prepared,
            password: OrderPassword.tryCreate(password),
          ),
          refused<TakeOrderChanged>(),
        );
        expect(count(app, ScriptedRequest.take), 0);
        app.coordinator.robotView.clear();
        final again = await prepare(app, shown);
        expect(
          await app.take.confirm(
            again,
            password: OrderPassword.tryCreate(password),
          ),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
        // A password given for an order without one is never sent.
        expect(takeBody(app), '{"action":"take","amount":0}');
      },
    );

    test(
      'an order no longer takeable reached by its URL: « not available », its robot forgotten',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.takenByAnother();
        expect(
          await app.take.readUnlisted(
            app.coordinator.coordinator,
            42,
            network: app.network,
          ),
          refused<TakeOrderGone>(),
        );
      },
    );

    test('an order of the book: its take never carries a password', () async {
      final public = await TradeHarness.start();
      final prepared = switch (await public.take.prepare(
        await public.shownOrder(),
        network: public.network,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('not prepared: $failure'),
      };
      expect(
        await public.take.confirm(
          prepared,
          password: OrderPassword.tryCreate(password),
        ),
        isA<Ok<TakeOutcome, TakeRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<TakeStarted>(),
        ),
      );
      expect(takeBody(public), '{"action":"take","amount":0}');
    });

    test(
      'a protected order is never prepared through the book, which does not list it',
      () async {
        final (app, shown) = await readOne();
        expect(
          await app.take.prepare(shown.order, network: app.network),
          refused<TakeOrderGone>(),
        );
        expect(count(app, ScriptedRequest.take), 0);
      },
    );

    test('the password is never printed', () {
      final typed = OrderPassword.tryCreate(password);
      expect('$typed', isNot(contains(password)));
      expect('$typed', isNot(contains(hash)));
      expect(typed?.hash.hex, hash);
    });
  });
}
