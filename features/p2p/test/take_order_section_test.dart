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
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, bookOrder, parseOrders;
import 'support/harness.dart';
import 'support/trade_screens.dart';

/// The take, played by the test.
final class _Take {
  final List<TakeAmount?> amounts = [];
  Completer<Result<TakeOutcome, TakeRefusal>>? pending;
  Result<TakeOutcome, TakeRefusal> Function()? answer;

  Future<Result<TakeOutcome, TakeRefusal>> call(
    PublicOrder shown, {
    required RobosatsNetwork network,
    TakeAmount? amount,
    OrderPassword? password,
  }) async {
    amounts.add(amount);
    final waiting = pending;
    if (waiting != null) return waiting.future;
    return (answer ??
        () => Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)))();
  }
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

Future<List<TradeRecord>> _show(
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
    (take ?? _Take()).call,
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
            now: () => DateTime.utc(2026, 11, 14, 9),
            coordinatorDetails: (_) => throw StateError('not opened'),
            canTake: canTake,
            onTaken: taken.add,
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return taken;
}

Finder get _takeButton => find.text('Take Order');

Future<void> _press(WidgetTester tester) async {
  await tester.ensureVisible(_takeButton);
  await tester.tap(_takeButton);
  await settle(tester);
}

void main() {
  testWidgets('a fixed sell order: Store your garage key, then « Done » takes once', (
    tester,
  ) async {
    final take = _Take();
    final taken = await _show(tester, await _order(), take: take);

    await _press(tester);
    expect(find.byType(StoreTokenDialog), findsOneWidget);
    expect(find.text('Store your garage key'), findsOneWidget);
    await tester.tap(find.text('Go back'));
    await settle(tester);
    expect(take.amounts, isEmpty);

    await _press(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(take.amounts, [null]);
    expect(taken, [TradeScreenStatuses.record]);
  });

  testWidgets('no Garage Key: « You do not have a Garage Key », nothing taken', (
    tester,
  ) async {
    final take = _Take();
    await _show(tester, await _order(), take: take, keys: const Ok(false));

    await _press(tester);
    expect(find.byType(NoRobotDialog), findsOneWidget);
    expect(find.byType(StoreTokenDialog), findsNothing);
    expect(take.amounts, isEmpty);
  });

  testWidgets('without robots in the feature: « You do not have a Garage Key »', (
    tester,
  ) async {
    await _show(tester, await _order(), canTake: false);
    await _press(tester);
    expect(find.byType(NoRobotDialog), findsOneWidget);
  });

  testWidgets('while the take runs, the button cannot be pressed again', (
    tester,
  ) async {
    final take = _Take()
      ..pending = Completer<Result<TakeOutcome, TakeRefusal>>();
    await _show(tester, await _order(), take: take);
    await _press(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(_takeButton, warnIfMissed: false);
    await settle(tester);
    expect(find.byType(StoreTokenDialog), findsNothing);
    expect(take.amounts, hasLength(1));

    take.pending?.complete(Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)));
    await settle(tester);
  });

  testWidgets('a take that runs long says it still waits', (tester) async {
    final take = _Take()
      ..pending = Completer<Result<TakeOutcome, TakeRefusal>>();
    await _show(tester, await _order(), take: take);
    await _press(tester);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(seconds: 31));
    expect(
      find.text('Still waiting for Temple of Sats. Tor can take a minute.'),
      findsOneWidget,
    );
    take.pending?.complete(Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)));
    await settle(tester);
  });

  for (final (refusal, text) in <(Result<TakeOutcome, TakeRefusal>, String)>[
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
    testWidgets('« $text »', (tester) async {
      final take = _Take()..answer = () => refusal;
      final taken = await _show(tester, await _order(), take: take);
      await _press(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text(text), findsOneWidget);
      expect(taken, isEmpty);
    });
  }

  testWidgets('a buy order: « Take Order » disabled, selling a later version', (
    tester,
  ) async {
    final take = _Take();
    await _show(tester, await _order(type: 0), take: take);
    expect(find.text('Selling is coming in a later version.'), findsOneWidget);
    await tester.ensureVisible(_takeButton);
    await tester.tap(_takeButton, warnIfMissed: false);
    await settle(tester);
    expect(find.byType(StoreTokenDialog), findsNothing);
    expect(take.amounts, isEmpty);
  });

  testWidgets('a range order: the amount first, « Too low », « Too high », then the estimate', (
    tester,
  ) async {
    final take = _Take();
    await _show(tester, await _order(range: true), take: take);
    expect(find.text('Amount EUR'), findsOneWidget);
    expect(find.byTooltip('You must specify an amount first'), findsOneWidget);
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

    await _press(tester);
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(take.amounts.single?.amount.value, 120.5);
  });

  testWidgets('the estimate is the reference take button\'s: the taker fee off, no routing budget', (
    tester,
  ) async {
    await _show(tester, await _order(range: true));
    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    // 100 of 200 EUR for 106,900 sats: 53,450 sats, the fee unknown (0) until the coordinator answers.
    expect(find.text('You will receive 53,450 Sats (Approx)'), findsOneWidget);
  });

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets('${locale.languageCode} at ×$scale: nothing overflows or is cut', (
          tester,
        ) async {
          void nothingCut(String reason) {
            expect(tester.takeException(), isNull, reason: reason);
            for (final paragraph in tester.renderObjectList<RenderParagraph>(
              find.byType(RichText),
            )) {
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '$reason: ${paragraph.text.toPlainText()}',
              );
            }
          }

          final take = _Take()..answer = () => const Err(TakeOrderChanged());
          await _show(
            tester,
            await _order(range: true),
            take: take,
            locale: locale,
            size: const Size(320, 568),
            textScale: scale,
          );
          nothingCut('range');
          await tester.enterText(find.byType(TextField), '10');
          await tester.pump();
          nothingCut('too low');
          await tester.enterText(find.byType(TextField), '120');
          await tester.pump();
          nothingCut('estimate');
          final button = find.text(
            locale.languageCode == 'fr' ? 'Prendre l\'ordre' : 'Take Order',
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await settle(tester);
          nothingCut('store your garage key');
          await tester.tap(
            find.text(locale.languageCode == 'fr' ? 'Fait' : 'Done'),
          );
          await settle(tester);
          await tester.ensureVisible(button);
          nothingCut('refused');
        });
      }
    }
  });
}
