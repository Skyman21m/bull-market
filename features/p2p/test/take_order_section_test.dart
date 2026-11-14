import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/order_details_cubit.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/take_order_section.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/order_detail_row.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, bookOrder, parseOrders;
import 'support/harness.dart';
import 'support/prepared_takes.dart';
import 'support/trade_screens.dart';

/// The maker's description of the tests.
const _description = 'Revolut only, no notes in the transfer.';

/// The order as the robot reads it: with the description, with none, and with fresh figures (a price of 95,000 EUR, 105,263 sats).
late PreparedTake _read;
late PreparedTake _readWithout;
late PreparedTake _readFresh;
late PreparedTake _readRange;

/// The take in two steps, played by the test.
final class _Take {
  /// The amounts of the preparations asked, in order.
  final List<TakeAmount?> amounts = [];
  final List<PreparedTake> confirmed = [];
  final List<PreparedTake> abandoned = [];
  int abandonedOrders = 0;

  /// The steps each preparation and confirmation says, before it waits for [preparing] or [confirming].
  List<TakeStep> preparingSteps = const [];
  List<TakeStep> confirmingSteps = const [];

  /// The answers of the preparations, in turn; the last one stays.
  List<Result<PreparedTake, TakeRefusal>> prepared;
  Completer<Result<PreparedTake, TakeRefusal>>? preparing;
  Result<TakeOutcome, TakeRefusal> Function()? answer;
  Completer<Result<TakeOutcome, TakeRefusal>>? confirming;

  _Take({List<Result<PreparedTake, TakeRefusal>>? prepared})
    : prepared = prepared ?? [Ok(_read)];

  TakeCalls get calls => TakeCalls(
    prepare: (shown, {required network, amount, onStep}) async {
      amounts.add(amount);
      preparingSteps.forEach(onStep ?? (_) {});
      final waiting = preparing;
      if (waiting != null) return waiting.future;
      return prepared.length > 1 ? prepared.removeAt(0) : prepared.single;
    },
    confirm: (prepared, {onStep}) async {
      confirmed.add(prepared);
      confirmingSteps.forEach(onStep ?? (_) {});
      final waiting = confirming;
      if (waiting != null) return waiting.future;
      return (answer ??
          () => Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)))();
    },
    abandon: abandoned.add,
    abandonOrder: (shown, {required network}) => abandonedOrders++,
  );
}

Future<PublicOrder> _order({
  int type = 1,
  bool range = false,
  int currency = 2,
}) async => (await parseOrders([
  bookOrder(
    id: 42,
    type: type,
    currency: currency,
    amount: range ? null : 100,
    minAmount: range ? 50 : null,
    maxAmount: range ? 200 : null,
  ),
])).single;

Future<(List<TradeRecord>, TakeOrderCubit)> _show(
  WidgetTester tester,
  PublicOrder order, {
  _Take? take,
  Result<bool, P2pFailure> keys = const Ok(true),
  bool canTake = true,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final details = OrderDetailsCubit(
    order,
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(FakeTransport())),
  );
  addTearDown(details.close);
  final taking = TakeOrderCubit(
    order,
    RobosatsNetwork.mainnet,
    (take ?? _Take()).calls,
    (network) async => keys,
  );
  addTearDown(taking.close);
  final taken = <TradeRecord>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: testTheme,
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: details),
            BlocProvider.value(value: taking),
          ],
          child: OrderDetailsScreen(
            now: () => DateTime.utc(2026, 11, 13, 8),
            coordinatorDetails: (_) => throw StateError('not opened'),
            canTake: canTake,
            onTaken: taken.add,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return (taken, taking);
}

Finder get _takeButton => find.text('Take Order');
Finder get _confirmButton => find.text('Confirm');
Finder get _backButton => find.text('Go back');

/// The list of the order details, built lazily: what is below the screen is built once scrolled to.
Finder get _details => find
    .descendant(
      of: find.byType(OrderDetailsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the order details until [finder] is built and in view.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 150, scrollable: _details);
  await tester.pump();
}

Future<void> _press(WidgetTester tester) async {
  await _reveal(tester, _takeButton);
  await tester.tap(_takeButton);
  await settle(tester);
}

/// « Take Order », then « Done » of « Store your garage key »: the take prepared.
Future<void> _prepare(WidgetTester tester) async {
  await _press(tester);
  await tester.tap(find.text('Done'));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder button) async {
  await _reveal(tester, button);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  setUpAll(() async {
    _read = await preparedTake(description: _description);
    _readWithout = await preparedTake();
    _readFresh = await preparedTake(
      description: _description,
      changes: {'price_now': 95000.0, 'satoshis_now': 105263},
    );
    _readRange = await preparedTake(
      range: true,
      amount: TakeAmount.tryCreate(120.5),
    );
  });

  testWidgets(
    'a fixed sell order: Store your garage key, « Done » prepares once, « Confirm » takes once',
    (tester) async {
      final take = _Take();
      final (taken, _) = await _show(tester, await _order(), take: take);

      await _press(tester);
      expect(find.byType(StoreTokenDialog), findsOneWidget);
      expect(find.text('Store your garage key'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await settle(tester);
      expect(take.amounts, isEmpty);

      await _prepare(tester);
      expect(take.amounts, [null]);
      expect(take.confirmed, isEmpty);
      expect(taken, isEmpty);
      expect(_takeButton, findsNothing);

      await _tap(tester, _confirmButton);
      expect(take.confirmed, [_read]);
      expect(taken, [TradeScreenStatuses.record]);
    },
  );

  testWidgets(
    'the order read: the maker\'s description in the order details, as plain text, then the read\'s figures, the bond and the time of the read',
    (tester) async {
      await _show(
        tester,
        await _order(),
        take: _Take(prepared: [Ok(_readFresh)]),
      );
      // Before « Take Order », no robot read anything: no description, the book's price.
      expect(find.text('Description'), findsNothing);
      expect(find.text(_description), findsNothing);
      expect(find.textContaining('95,000'), findsNothing);

      await _prepare(tester);

      expect(find.text('Description'), findsOneWidget);
      expect(find.text(_description), findsOneWidget);
      // Shown as text that cannot be selected, copied or opened.
      expect(find.byType(SelectableText), findsNothing);
      final words = tester.widget<Text>(find.text(_description));
      expect(words.textSpan, isNull);
      expect(find.textContaining('95,000'), findsOneWidget);
      // The robot's sats: 100 EUR at 95,000 EUR per bitcoin.
      expect(find.text('Taker bond'), findsOneWidget);
      expect(
        find.text(
          '${_readFresh.expectedBond.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} Sats, at most ${_readFresh.bondCeiling.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}',
        ),
        findsOneWidget,
      );
      expect(find.text('Read at 08:00:30'), findsOneWidget);
    },
  );

  testWidgets('a read with no description shows no description row', (
    tester,
  ) async {
    await _show(
      tester,
      await _order(),
      take: _Take(prepared: [Ok(_readWithout)]),
    );
    await _prepare(tester);
    expect(find.byType(OrderDescriptionRow), findsNothing);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Read at 08:00:30'), findsOneWidget);
    await _reveal(tester, _confirmButton);
    expect(_confirmButton, findsOneWidget);
  });

  testWidgets(
    'a description with controls and invisible characters is shown cleaned, on one paragraph',
    (tester) async {
      final read = await tester.runAsync(
        () => preparedTake(description: 'Pay\u200b first\u202e to lnbc1x'),
      );
      await _show(tester, await _order(), take: _Take(prepared: [Ok(read!)]));
      await _prepare(tester);
      expect(find.text('Pay first to lnbc1x'), findsOneWidget);
    },
  );

  testWidgets(
    '« Go back » abandons the preparation: nothing taken, « Take Order » again',
    (tester) async {
      final take = _Take();
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);

      await _tap(tester, _backButton);

      expect(take.abandoned, [_read]);
      expect(take.confirmed, isEmpty);
      expect(taken, isEmpty);
      expect(find.text(_description), findsNothing);
      await _reveal(tester, _takeButton);
      expect(_takeButton, findsOneWidget);
    },
  );

  testWidgets(
    'the page left with the take prepared (a system back closes its cubit): abandoned',
    (tester) async {
      final take = _Take();
      final (_, cubit) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await tester.runAsync(cubit.close);
      expect(take.abandoned, [_read]);
      expect(take.abandonedOrders, 0);
    },
  );

  testWidgets(
    'the page left after a preparation that failed: the order abandoned, so that no robot stays kept',
    (tester) async {
      final take = _Take(
        prepared: [
          const Err(TakeCoordinatorUnreadable(CoordinatorUnreachable())),
        ],
      );
      final (_, cubit) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      expect(
        find.text('Could not reach Temple of Sats. The order was not taken.'),
        findsOneWidget,
      );
      await tester.runAsync(cubit.close);
      expect(take.abandonedOrders, 1);
      expect(take.abandoned, isEmpty);
    },
  );

  testWidgets(
    'the order changed at the confirmation: its new figures shown with « The order changed. », never confirmed by itself',
    (tester) async {
      final take = _Take(prepared: [Ok(_read), Ok(_readFresh)])
        ..answer = () => const Err(TakeOrderChanged());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      expect(find.textContaining('95,000'), findsNothing);

      await _tap(tester, _confirmButton);

      expect(take.confirmed, [_read]);
      expect(take.amounts, hasLength(2));
      // The order details are brought into view with the new figures.
      expect(find.textContaining('95,000'), findsOneWidget);
      await _reveal(tester, find.text('The order changed.'));
      expect(find.text('The order changed.'), findsOneWidget);
      expect(taken, isEmpty);
      expect(_confirmButton, findsOneWidget);
    },
  );

  testWidgets(
    'the order gone at the confirmation: « This order is not available », nothing taken',
    (tester) async {
      final take = _Take()..answer = () => const Err(TakeOrderGone());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _tap(tester, _confirmButton);
      await _reveal(tester, find.text('This order is not available'));
      expect(find.text('This order is not available'), findsOneWidget);
      expect(taken, isEmpty);
      expect(find.text(_description), findsNothing);
    },
  );

  testWidgets(
    'the preparation gone at the confirmation: prepared again, waiting for the user',
    (tester) async {
      final take = _Take(prepared: [Ok(_read), Ok(_readWithout)])
        ..answer = () => const Err(TakePreparationGone());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _tap(tester, _confirmButton);
      expect(take.amounts, hasLength(2));
      await _reveal(tester, _confirmButton);
      expect(find.text('The order changed.'), findsNothing);
      expect(_confirmButton, findsOneWidget);
      expect(taken, isEmpty);
    },
  );

  testWidgets(
    'a range order with no amount: a tap on « Take Order » shows « You must specify an amount first »',
    (tester) async {
      final take = _Take();
      await _show(tester, await _order(range: true), take: take);
      await _reveal(tester, _takeButton);
      expect(find.text('You must specify an amount first'), findsNothing);
      await tester.tap(_takeButton, warnIfMissed: false);
      await tester.pump();
      expect(find.text('You must specify an amount first'), findsOneWidget);
      expect(take.amounts, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
    },
  );

  testWidgets('an order with an open trade here: that trade opens', (
    tester,
  ) async {
    final take = _Take(
      prepared: [Err(TakeOrderAlreadyTraded(TradeScreenStatuses.record))],
    );
    final (taken, _) = await _show(tester, await _order(), take: take);
    await _prepare(tester);
    expect(taken, [TradeScreenStatuses.record]);
  });

  testWidgets(
    'no Garage Key: « You do not have a Garage Key », nothing prepared',
    (tester) async {
      final take = _Take();
      await _show(tester, await _order(), take: take, keys: const Ok(false));

      await _press(tester);
      expect(find.byType(NoRobotDialog), findsOneWidget);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.amounts, isEmpty);
    },
  );

  testWidgets(
    'without robots in the feature: « You do not have a Garage Key »',
    (tester) async {
      await _show(tester, await _order(), canTake: false);
      await _press(tester);
      expect(find.byType(NoRobotDialog), findsOneWidget);
    },
  );

  testWidgets(
    'while the order is read, « Take Order » cannot be pressed again; while the take is confirmed, neither button',
    (tester) async {
      final take = _Take()
        ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
      await _show(tester, await _order(), take: take);
      await _prepare(tester);
      // The bar of the step, under the button, with the bar of the order's time left.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      await tester.tap(_takeButton, warnIfMissed: false);
      await settle(tester);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.amounts, hasLength(1));

      take.preparing?.complete(Ok(_read));
      take.preparing = null;
      await settle(tester);
      take.confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      await _tap(tester, _confirmButton);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      await tester.tap(_confirmButton, warnIfMissed: false);
      await tester.tap(_backButton, warnIfMissed: false);
      await settle(tester);
      expect(take.confirmed, hasLength(1));
      expect(take.abandoned, isEmpty);

      take.confirming?.complete(
        Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
      );
      await settle(tester);
    },
  );

  testWidgets(
    'the wait says the step that runs under the bar, and none that has not started',
    (tester) async {
      final take = _Take()
        ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
      await _show(tester, await _order(), take: take);
      await _press(tester);
      await tester.tap(find.text('Done'));
      await tester.pump();
      // Before any step starts: the bar only.
      expect(find.text('Checking the order with Temple of Sats'), findsNothing);
      expect(find.text('Building your robot!'), findsNothing);
      expect(find.text('Your robot reads the order'), findsNothing);
      await tester.runAsync(() async {});
      take.preparing?.complete(Ok(_read));
      take.preparing = null;
      await settle(tester);

      // The steps a preparation says are shown one at a time, the latest only.
      final steps = Completer<Result<PreparedTake, TakeRefusal>>();
      take
        ..preparing = steps
        ..preparingSteps = [TakeStep.checkingOrder];
      await _tap(tester, _backButton);
      await _press(tester);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await _reveal(
        tester,
        find.text('Checking the order with Temple of Sats'),
      );
      expect(
        find.text('Checking the order with Temple of Sats'),
        findsOneWidget,
      );
      expect(find.text('Building your robot!'), findsNothing);
      expect(find.text('Your robot reads the order'), findsNothing);
      steps.complete(Ok(_read));
      await settle(tester);
      expect(find.text('Checking the order with Temple of Sats'), findsNothing);

      final confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      take
        ..confirming = confirming
        ..confirmingSteps = [TakeStep.readingOrderAgain, TakeStep.sendingTake];
      await _tap(tester, _confirmButton);
      await _reveal(tester, find.text('Taking the order with Temple of Sats'));
      expect(find.text('Taking the order with Temple of Sats'), findsOneWidget);
      expect(find.text('Your robot reads the order again'), findsNothing);
      confirming.complete(Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)));
      await settle(tester);
    },
  );

  for (final (step, en, fr) in [
    (
      TakeStep.checkingOrder,
      'Checking the order with Temple of Sats',
      'Vérification de l’ordre auprès de Temple of Sats',
    ),
    (
      TakeStep.creatingRobot,
      'Building your robot!',
      'Construction de votre robot !',
    ),
    (
      TakeStep.readingOrder,
      'Your robot reads the order',
      'Votre robot lit l’ordre',
    ),
  ]) {
    testWidgets('« $en » / « $fr », read out when it shows', (tester) async {
      for (final locale in const [Locale('en'), Locale('fr')]) {
        final semantics = tester.ensureSemantics();
        final take = _Take()
          ..preparingSteps = [step]
          ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
        await _show(tester, await _order(), take: take, locale: locale);
        final fr0 = locale.languageCode == 'fr';
        await _reveal(
          tester,
          find.text(fr0 ? 'Prendre l\'ordre' : 'Take Order'),
        );
        await tester.tap(find.text(fr0 ? 'Prendre l\'ordre' : 'Take Order'));
        await settle(tester);
        await tester.tap(find.text(fr0 ? 'Fait' : 'Done'));
        await tester.pump();
        final line = find.text(fr0 ? fr : en);
        await _reveal(tester, line);
        expect(line, findsOneWidget);
        expect(
          tester.getSemantics(line),
          isSemantics(isLiveRegion: true),
        );
        take.preparing?.complete(Ok(_read));
        await settle(tester);
        semantics.dispose();
      }
    });
  }

  testWidgets('a read that runs long says it still waits', (tester) async {
    final take = _Take()
      ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
    await _show(tester, await _order(), take: take);
    await _press(tester);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(seconds: 31));
    expect(
      find.text('Still waiting for Temple of Sats. Tor can take a minute.'),
      findsOneWidget,
    );
    take.preparing?.complete(Ok(_read));
    await settle(tester);
  });

  for (final (refusal, text) in <(Result<PreparedTake, TakeRefusal>, String)>[
    (const Err(TakeOrderGone()), 'This order is not available'),
    (
      const Err(TakeOrderChanged()),
      'This order changed since it was shown. It was not taken: open it again from the book.',
    ),
    (
      const Err(TakeNotRecorded(P2pStorageFailure())),
      'Bull Market could not write its records on this device. The order was not taken.',
    ),
    (
      const Err(TakeCoordinatorUnreadable(CoordinatorUnreachable())),
      'Could not reach Temple of Sats. The order was not taken.',
    ),
    (
      const Err(TakeRobotRefused(GarageKeyNotForTradesFailure())),
      'The robots of a pasted Garage Key cannot take orders here. Generate a new Garage Key in the Garage.',
    ),
  ]) {
    testWidgets('a preparation refused: « $text »', (tester) async {
      final take = _Take(prepared: [refusal]);
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
      expect(taken, isEmpty);
      expect(_confirmButton, findsNothing);
    });
  }

  for (final (answer, text) in <(Result<TakeOutcome, TakeRefusal>, String)>[
    (
      Ok(TakeNotMade(TradeScreenStatuses.record, refusal: null)),
      'The order was not taken.',
    ),
    (
      Ok(
        TakeNotMade(
          TradeScreenStatuses.record,
          refusal: const OrderTakePenalty(42),
        ),
      ),
      'You need to wait 42 seconds to take an order',
    ),
  ]) {
    testWidgets('a confirmation not made: « $text »', (tester) async {
      final take = _Take()..answer = () => answer;
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _tap(tester, _confirmButton);
      await _reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
      expect(taken, isEmpty);
    });
  }

  testWidgets('a buy order: « Take Order » disabled, selling a later version', (
    tester,
  ) async {
    final take = _Take();
    await _show(tester, await _order(type: 0), take: take);
    await _reveal(tester, find.text('Selling is coming in a later version.'));
    expect(find.text('Selling is coming in a later version.'), findsOneWidget);
    await tester.tap(_takeButton, warnIfMissed: false);
    await settle(tester);
    expect(find.byType(StoreTokenDialog), findsNothing);
    expect(take.amounts, isEmpty);
  });

  testWidgets(
    'a range order: the amount first, « Too low », « Too high », the estimate, then the read with the amount kept',
    (tester) async {
      final take = _Take(prepared: [Ok(_readRange)]);
      await _show(tester, await _order(range: true), take: take);
      await _reveal(tester, _takeButton);
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(find.text('Amount EUR'), findsOneWidget);
      expect(
        find.byTooltip('You must specify an amount first'),
        findsOneWidget,
      );
      await tester.tap(_takeButton, warnIfMissed: false);
      await settle(tester);
      expect(find.byType(StoreTokenDialog), findsNothing);

      final field = find.byType(TextField);
      await tester.enterText(field, '10');
      await tester.pump();
      expect(find.text('Too low'), findsOneWidget);
      await tester.enterText(field, '300');
      await tester.pump();
      expect(find.text('Too high'), findsOneWidget);
      await tester.enterText(field, '120,5');
      await tester.pump();
      expect(find.text('Too high'), findsNothing);
      expect(find.textContaining('You will receive'), findsOneWidget);
      expect(find.byTooltip('You must specify an amount first'), findsNothing);

      await _prepare(tester);
      expect(take.amounts.single?.amount.value, 120.5);
      // The amount chosen stays shown, and cannot be changed while the read is shown.
      await _reveal(tester, field);
      expect(tester.widget<TextField>(field).enabled, isFalse);
      expect(find.text('120,5'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Amount Range'),
        -150,
        scrollable: _details,
      );
      expect(find.text('Amount Range'), findsOneWidget);
    },
  );

  testWidgets(
    'the estimate is the reference take button\'s: the taker fee off, no routing budget',
    (tester) async {
      await _show(tester, await _order(range: true));
      await _reveal(tester, _takeButton);
      await tester.enterText(find.byType(TextField), '100');
      await tester.pump();
      // 100 of 200 EUR for 106,900 sats: 53,450 sats, the fee unknown (0) until the coordinator answers.
      expect(
        find.text('You will receive 53,450 Sats (Approx)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a screen reader hears the description with its label, the time of the read, and both buttons',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _show(tester, await _order(), take: _Take());
      await _prepare(tester);
      await _reveal(tester, find.text(_description));
      expect(find.bySemanticsLabel('Description'), findsOneWidget);
      final node = tester.getSemantics(find.byType(OrderDescriptionRow));
      expect(node.value, _description);
      await _reveal(tester, find.text('Read at 08:00:30'));
      expect(find.bySemanticsLabel(RegExp('Read at 08:00:30')), findsOneWidget);
      await _reveal(tester, _backButton);
      expect(
        tester.getSemantics(_confirmButton),
        isSemantics(label: 'Confirm', isButton: true, isEnabled: true),
      );
      expect(
        tester.getSemantics(_backButton),
        isSemantics(label: 'Go back', isButton: true, isEnabled: true),
      );
      semantics.dispose();
    },
  );

  testWidgets('nothing is printed through a take in two steps', (tester) async {
    // The logger's file, written to disk, cannot be read back in a widget test: the cubit's test captures it (`trade_screen_cubits_test.dart`).
    final printed = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add('$message');
    try {
      await runZoned(
        () async {
          final take = _Take(prepared: [Ok(_read), Ok(_readFresh)])
            ..answer = () => const Err(TakeOrderChanged());
          final (_, cubit) = await _show(tester, await _order(), take: take);
          await _prepare(tester);
          await _tap(tester, _confirmButton);
          await _tap(tester, _backButton);
          await tester.runAsync(cubit.close);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
    } finally {
      debugPrint = previous;
    }
    expect(printed, isEmpty);
  });

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: nothing overflows or is cut',
          (tester) async {
            final fr = locale.languageCode == 'fr';
            void nothingCut(String reason) {
              expect(tester.takeException(), isNull, reason: reason);
              for (final paragraph in tester.renderObjectList<RenderParagraph>(
                find.descendant(
                  of: find.byWidgetPredicate(
                    (widget) =>
                        widget is TakeOrderSection ||
                        widget is StoreTokenDialog ||
                        widget is PublicOrderDetailsCard,
                  ),
                  matching: find.byType(RichText),
                ),
              )) {
                expect(
                  paragraph.didExceedMaxLines,
                  isFalse,
                  reason: '$reason: ${paragraph.text.toPlainText()}',
                );
              }
            }

            final take = _Take(prepared: [Ok(_readRange), Ok(_readFresh)])
              ..answer = () => const Err(TakeOrderChanged());
            await _show(
              tester,
              await _order(range: true),
              take: take,
              locale: locale,
              size: const Size(320, 568),
              textScale: scale,
            );
            final button = find.text(fr ? 'Prendre l\'ordre' : 'Take Order');
            await _reveal(tester, button);
            nothingCut('range');
            await tester.enterText(find.byType(TextField), '10');
            await tester.pump();
            nothingCut('too low');
            await tester.enterText(find.byType(TextField), '120');
            await tester.pump();
            nothingCut('estimate');
            await _reveal(tester, button);
            await tester.tap(button);
            await settle(tester);
            nothingCut('store your garage key');
            // The dialog scrolls at this size: « Done » is brought into view, then pressed.
            final done = find.text(fr ? 'Fait' : 'Done');
            await tester.ensureVisible(done);
            await tester.pump();
            await tester.tap(done);
            await settle(tester);
            nothingCut('read');
            final confirm = find.text(fr ? 'Confirmer' : 'Confirm');
            await _reveal(tester, confirm);
            nothingCut('confirm');
            await tester.tap(confirm);
            await settle(tester);
            await _reveal(tester, confirm);
            nothingCut('changed');
            final description = find.text(_description);
            await tester.scrollUntilVisible(
              description,
              -150,
              scrollable: _details,
            );
            await tester.pump();
            nothingCut('description');
          },
        );
      }
    }
  });
}
