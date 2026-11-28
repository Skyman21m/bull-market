import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/ui/trade/active_trades_sheet.dart';
import 'package:p2p/src/ui/trade/pending_make_lines.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestDecoder, ScriptedFault, ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show bookOrder, parseOrders;
import 'support/captures.dart';
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/maker_orders.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart';

/// The pending makes on the screens (#182, design note § 3.4, « The screens of a pending make »): their line « Creating your order… » in « Active trades », resolved when the sheet opens and on « Retry », never in a loop; « Set aside » for a make that does not resolve, which closes it in the records and sends nothing, never making it again (reviews of #179); « Create order » at the top of the sheet (design note § 7, proposal 9); and the book opening an order this device made as its trade (§ 3.7).

final _slot = RobotSlot(
  RobosatsNetwork.mainnet,
  switch (GarageKeyFingerprint.of(tradeKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  },
  3,
);

final _onion =
    Federation.robosats.byAlias('temple')?.mainnet.onion ??
    (throw StateError('temple'));

final _make = PendingMake(
  robot: _slot,
  coordinatorAlias: 'temple',
  coordinatorOnion: _onion,
  role: TradeRole.buyer,
  writtenAt: madeAt,
  closedAt: null,
);

final _record = TradeRecord(
  robot: _slot,
  coordinatorAlias: 'temple',
  coordinatorOnion: _onion,
  orderId: tradeOrderId,
  role: TradeRole.buyer,
  origin: TradeOrigin.madeHere,
  takenAt: madeAt,
  confirmedAt: madeAt,
  closedAt: null,
);

/// What the cubit's use cases were asked, and what they answer.
final class _Makes {
  final list = StreamController<Result<List<ActivePendingMake>, P2pFailure>>();
  List<ActivePendingMake> listed = [ActivePendingMake(_make, neverSent: false)];
  final List<PendingMake> resolved = [];
  final List<PendingMake> dismissed = [];
  Future<MakeOutcome> Function(PendingMake make) resolution = (make) async =>
      MakePending(make, MakePendingReason.notRecognized);
  Result<bool, P2pFailure> dismissal = const Ok(true);

  /// The cubit, the records' first list [listed] already given.
  PendingMakesCubit cubit() {
    list.add(Ok(listed));
    return _cubit();
  }

  PendingMakesCubit _cubit() => PendingMakesCubit(
    RobosatsNetwork.mainnet,
    (network) => list.stream,
    (make) {
      resolved.add(make);
      return resolution(make);
    },
    (make) async {
      dismissed.add(make);
      if (dismissal case Ok(value: true)) {
        listed = [];
        list.add(Ok(listed));
      }
      return dismissal;
    },
  );
}

Future<MakeStarted> _started() async {
  final invoice = makerBondInvoice();
  final status = TradeStatus.afterMake(
    TradeOrderRead(await readOrder(makerOrderJson(0, bond: invoice))),
    terms: madeTerms(),
    now: tradeNow,
    reader: Bolt11Reader(Bolt11TestDecoder([invoice])),
  );
  return MakeStarted(_record, status, stored: true);
}

/// Opens « Active trades » over [makes] from a button, the trades opened and the form asked for in the returned lists.
Future<(List<TradeRecord>, List<void>, PendingMakesCubit)> _sheet(
  WidgetTester tester,
  _Makes makes, {
  List<ActiveTrade> active = const [],
  Locale locale = const Locale('en'),
}) async {
  usePhoneScreen(tester);
  final cubit = makes.cubit()..start();
  addTearDown(cubit.close);
  final opened = <TradeRecord>[];
  final created = <void>[];
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureFrame,
      child: MaterialApp(
        theme: testTheme,
        locale: locale,
        localizationsDelegates: P2pLocalizations.localizationsDelegates,
        supportedLocales: P2pLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                ActiveTradesSheet.show(
                  context,
                  active: active,
                  onOpen: opened.add,
                  onCreate: () => created.add(null),
                  pending: cubit,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await settle(tester);
  return (opened, created, cubit);
}

T _value<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

void main() {
  group('« Set aside » in the make use case', () {
    test(
      'a make that does not resolve is closed in the records: nothing sent, nothing made again, its robot never used again',
      () async {
        final harness = await MakeHarness.start();
        final other = harness.coordinator.inventOrder(
          harness.robot(5),
          status: 1,
        );
        var makes = 0;
        var requests = 0;
        harness.coordinator
          ..failNext(ScriptedMakerRequest.make, ScriptedFault.answerLost)
          ..onRequest = (request) {
            requests++;
            if (request.url.path == '/api/make/') {
              makes++;
              harness.coordinator.robotAnswerHas(harness.robot(0), {
                'active_order_id': other.id,
              });
            }
          };
        expect(_value(await harness.makeOrder()), isA<MakePending>());
        final pending = (await harness.pendingMakes()).single;
        expect(
          (await harness.make.resolve(pending) as MakePending).reason,
          MakePendingReason.notRecognized,
        );
        final sent = requests;
        expect(_value(await harness.make.dismiss(pending)), isTrue);
        expect(requests, sent);
        expect(makes, 1);
        expect(await harness.pendingMakes(), isEmpty);
        expect(await harness.activeRecords(), isEmpty);
        // Listed before it was set aside: no longer pending, nothing written, nothing sent.
        expect(_value(await harness.make.dismiss(pending)), isFalse);
        expect(await harness.make.resolve(pending), isA<MakeNoLongerPending>());
        expect(requests, sent);
        // Its row is closed, never deleted.
        expect((await harness.allTrades()).single['closed_at'], isNotNull);
      },
    );

    test(
      'a make an outcome unknown left pending is set aside the same way; the next make is another robot\'s',
      () async {
        final harness = await MakeHarness.start();
        harness.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.timedOut,
        );
        final first = _value(await harness.makeOrder());
        if (first is MakePending) {
          final pending = (await harness.pendingMakes()).single;
          expect(_value(await harness.make.dismiss(pending)), isTrue);
        }
        expect(await harness.pendingMakes(), isEmpty);
        expect(_value(await harness.makeOrder()), isA<MakeStarted>());
        final records = await harness.activeRecords();
        expect(records.single.robot.accountIndex, isNot(0));
      },
    );
  });

  group('the pending makes\' cubit', () {
    test(
      'resolves each listed make once at a time, asked before the records answered too, never by itself',
      () async {
        final makes = _Makes();
        final held = Completer<MakeOutcome>();
        makes.resolution = (_) => held.future;
        final cubit = makes.cubit();
        addTearDown(cubit.close);
        unawaited(cubit.resolveAll());
        cubit.start();
        await pumpEventQueue();
        expect(makes.resolved, [_make]);
        expect(cubit.state.steps[_slot], isA<PendingMakeChecking>());
        // A second ask while it runs sends nothing more.
        await cubit.resolve(_make);
        expect(makes.resolved, hasLength(1));
        held.complete(MakePending(_make, MakePendingReason.unread));
        await pumpEventQueue();
        expect(cubit.state.steps[_slot], isA<PendingMakeLeftPending>());
        await pumpEventQueue(times: 50);
        expect(makes.resolved, hasLength(1));
      },
    );

    test('a records list that cannot be read blocks the form', () async {
      final makes = _Makes();
      final cubit = makes.cubit()..start();
      addTearDown(cubit.close);
      await pumpEventQueue();
      expect(cubit.state.blocksMaking, isTrue);
      makes.list.add(const Ok([]));
      await pumpEventQueue();
      expect(cubit.state.blocksMaking, isFalse);
      makes.list.add(const Err(P2pStorageFailure()));
      await pumpEventQueue();
      expect(cubit.state.blocksMaking, isTrue);
    });

    test(
      'a new make sent (`forgetClosed`): only why the closed make made no order goes; a make still pending, its step and the robot of the make that ended stay',
      () async {
        final other = PendingMake(
          robot: RobotSlot(_slot.network, _slot.keyFingerprint, 4),
          coordinatorAlias: 'temple',
          coordinatorOnion: _onion,
          role: TradeRole.buyer,
          writtenAt: madeAt,
          closedAt: null,
        );
        final makes = _Makes()
          ..listed = [
            ActivePendingMake(_make, neverSent: false),
            ActivePendingMake(other, neverSent: false),
          ]
          ..resolution = (make) async => make == _make
              ? MakeNotMade(make)
              : MakePending(make, MakePendingReason.notRecognized);
        final cubit = makes.cubit()..start();
        addTearDown(cubit.close);
        await pumpEventQueue();
        await cubit.resolveAll();
        makes.list.add(Ok([ActivePendingMake(other, neverSent: false)]));
        await pumpEventQueue();
        final before = cubit.state;
        expect(before.closed, isA<MakeWasNotMade>());
        expect(before.closedAlias, 'temple');
        cubit.forgetClosed();
        final after = cubit.state;
        expect(after.closed, isNull);
        expect(after.closedAlias, isNull);
        expect(after.makes, same(before.makes));
        expect(after.makes?.single.make, other);
        expect(after.steps, before.steps);
        expect(after.steps[other.robot], isA<PendingMakeLeftPending>());
        expect(after.ended, _slot);
        expect(after.unreadable, isFalse);
        expect(after.blocksMaking, isTrue);
      },
    );
  });

  group('« Active trades »', () {
    testWidgets(
      'the sheet opens on « Create order », then the pending make, resolved once: « Not known yet … », « Retry », « Set aside »',
      (tester) async {
        final makes = _Makes();
        final (_, created, _) = await _sheet(tester, makes);
        expect(makes.resolved, [_make]);
        expect(find.text('Creating your order…'), findsOneWidget);
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(
          find.text(
            'Bull Market does not know yet whether Temple of Sats made this order. No bond is asked until it knows.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Set aside'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Create order')).dy,
          lessThan(tester.getTopLeft(find.text('Creating your order…')).dy),
        );
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(makes.resolved, hasLength(2));
        await tester.tap(find.text('Create order'));
        await settle(tester);
        expect(created, hasLength(1));
        expect(find.text('Creating your order…'), findsNothing);
      },
    );

    testWidgets(
      '« Set aside » asks first, says an order may still exist, unpaid, then closes it; « Go back » does nothing',
      (tester) async {
        final makes = _Makes();
        await _sheet(tester, makes);
        await tester.tap(find.text('Set aside'));
        await settle(tester);
        expect(find.text('Set this order aside?'), findsOneWidget);
        expect(
          find.text(
            'Bull Market will stop checking it. An order may still exist at Temple of Sats: no bond was paid for it from this app, and it expires on its own a few minutes after it was made.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Go back'));
        await settle(tester);
        expect(makes.dismissed, isEmpty);
        await tester.tap(find.text('Set aside'));
        await settle(tester);
        await tester.tap(find.text('Set aside').last);
        await settle(tester);
        expect(makes.dismissed, [_make]);
        expect(find.text('Creating your order…'), findsNothing);
        // Never made again in its place.
        expect(makes.resolved, hasLength(1));
      },
    );

    testWidgets('a set aside that cannot be written is said, the make kept', (
      tester,
    ) async {
      final makes = _Makes()..dismissal = const Err(P2pStorageFailure());
      await _sheet(tester, makes);
      await tester.tap(find.text('Set aside'));
      await settle(tester);
      await tester.tap(find.text('Set aside').last);
      await settle(tester);
      expect(find.text('Creating your order…'), findsOneWidget);
      expect(find.textContaining('records'), findsWidgets);
    });

    testWidgets(
      'before any resolution left it pending, no « Set aside »: a make is resolved before it can be set aside',
      (tester) async {
        final makes = _Makes();
        final held = Completer<MakeOutcome>();
        makes.resolution = (_) => held.future;
        await _sheet(tester, makes);
        expect(find.text('Checking with Temple of Sats…'), findsOneWidget);
        expect(find.text('Set aside'), findsNothing);
        held.complete(MakePending(_make, MakePendingReason.outcomeUnknown));
        await settle(tester);
        expect(find.text('Set aside'), findsOneWidget);
      },
    );

    testWidgets('a make no resolution has read yet shows no « Set aside »', (
      tester,
    ) async {
      usePhoneScreen(tester);
      final makes = _Makes();
      final cubit = makes.cubit()..start();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const PendingMakeLines(),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Creating your order…'), findsOneWidget);
      expect(makes.resolved, isEmpty);
      expect(find.text('Set aside'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a resolution that confirms the make opens its trade', (
      tester,
    ) async {
      final started = await _started();
      final makes = _Makes()..resolution = (_) async => started;
      final (opened, _, _) = await _sheet(tester, makes);
      expect(opened, [_record]);
      expect(find.text('Create order'), findsNothing);
    });

    testWidgets(
      'a resolution that finds no order: the line goes, « The order was not created. » said',
      (tester) async {
        final makes = _Makes();
        makes.resolution = (make) async {
          makes.listed = [];
          makes.list.add(const Ok([]));
          return MakeNotMade(make);
        };
        await _sheet(tester, makes);
        expect(find.text('Creating your order…'), findsNothing);
        expect(find.text('The order was not created.'), findsOneWidget);
      },
    );

    testWidgets('the French texts', (tester) async {
      final makes = _Makes();
      await _sheet(tester, makes, locale: const Locale('fr'));
      expect(find.text('Créer l’ordre'), findsOneWidget);
      expect(find.text('Création de votre ordre…'), findsOneWidget);
      expect(find.text('Écarter'), findsOneWidget);
      await tester.tap(find.text('Écarter'));
      await settle(tester);
      expect(find.text('Écarter cet ordre ?'), findsOneWidget);
    });
  });

  group('the book recognizes an order this device made (§ 3.7)', () {
    test(
      'an open record made here of the same network, coordinator and number is that order\'s trade; nothing else is',
      () async {
        final book = await parseOrders([
          bookOrder(id: tradeOrderId, type: 0),
          bookOrder(id: tradeOrderId + 1, type: 0),
        ]);
        final listed = ActiveTradesListed([
          ActiveTrade(_record, const ActiveTradeTakeNeverSent()),
        ]);
        expect(listed.madeHere(book[0], RobosatsNetwork.mainnet), _record);
        expect(listed.madeHere(book[1], RobosatsNetwork.mainnet), isNull);
        expect(listed.madeHere(book[0], RobosatsNetwork.testnet), isNull);
        final taken = TradeRecord(
          robot: _slot,
          coordinatorAlias: 'temple',
          coordinatorOnion: _onion,
          orderId: tradeOrderId,
          role: TradeRole.seller,
          origin: TradeOrigin.takenHere,
          takenAt: madeAt,
          confirmedAt: madeAt,
          closedAt: null,
        );
        expect(
          ActiveTradesListed([
            ActiveTrade(taken, const ActiveTradeTakeNeverSent()),
          ]).madeHere(book[0], RobosatsNetwork.mainnet),
          isNull,
        );
      },
    );
  });

  group('captures (with P2P_CAPTURE_DIR)', () {
    setUpAll(loadCaptureFonts);
    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets(
        '« Active trades » with a pending make in ${locale.languageCode}',
        skip: captureDirectory == null,
        (tester) async {
          final code = locale.languageCode;
          final makes = _Makes();
          await _sheet(tester, makes, locale: locale);
          await capture(tester, '$code-creation-en-attente');
          await tester.tap(find.text(code == 'fr' ? 'Écarter' : 'Set aside'));
          await settle(tester);
          await capture(tester, '$code-creation-en-attente-ecarter');
        },
      );
    }
  });
}
