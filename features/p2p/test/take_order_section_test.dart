import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart'
    show lookupP2pLocalizations;
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/presentation/order_details_cubit.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/take_order_section.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/order_detail_row.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, bookOrder, parseOrders;
import 'support/harness.dart';
import 'support/prepared_takes.dart';
import 'support/trade_screens.dart';

/// The maker's description of the tests.
const _description = 'Revolut only, no notes in the transfer.';

/// The longest description the package lets through, 240 code points, of long words that cannot break between spaces.
final _longDescription = List.filled(
  6,
  'Bankueberweisungsbestaetigungsreferenznummer',
).join(' ').padRight(240, 'x').substring(0, 240);

/// The order as the robot reads it: with the description, with none, with fresh figures (a price of 95,000 EUR, 105,263 sats), of a range order, and with the longest description.
late PreparedTake _read;
late PreparedTake _readWithout;
late PreparedTake _readFresh;
late PreparedTake _readRange;
late PreparedTake _readLong;

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
    prepare: (shown, {required network, amount, onStep, garageRobot}) async {
      amounts.add(amount);
      preparingSteps.forEach(onStep ?? (_) {});
      final waiting = preparing;
      if (waiting != null) return waiting.future;
      return prepared.length > 1 ? prepared.removeAt(0) : prepared.single;
    },
    confirm: (prepared, {password, onStep}) async {
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

/// What temple says of itself on mainnet, its fees included (a taker fee of 0.175 %).
Map<String, Object?> _templeInfo() =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

Future<(List<TradeRecord>, TakeOrderCubit)> _show(
  WidgetTester tester,
  PublicOrder order, {
  _Take? take,
  Result<bool, P2pFailure> keys = const Ok(true),
  Future<Result<bool, P2pFailure>> Function()? vault,
  bool withFees = false,
  bool canTake = true,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  TakeOrderCubit Function(TakeCalls calls, HasGarageKey keys)? cubit,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final details = OrderDetailsCubit(
    order,
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(
      CoordinatorClient(
        FakeTransport(infos: {if (withFees) 'temple': _templeInfo()}),
      ),
    ),
  );
  addTearDown(details.close);
  if (withFees) await tester.runAsync(details.load);
  final calls = (take ?? _Take()).calls;
  Future<Result<bool, P2pFailure>> hasKey(RobosatsNetwork network) =>
      vault?.call() ?? Future.value(keys);
  final taking =
      cubit?.call(calls, hasKey) ??
      TakeOrderCubit(order, RobosatsNetwork.mainnet, calls, hasKey);
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
Finder get _continueButton => find.text('Continue');
Finder get _backButton => find.text('Go back');
Finder get _readLine => find.text('Read by your robot at 08:00:30');

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

/// Scrolls the order details up until [finder] is built and in view.
Future<void> _revealAbove(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, -150, scrollable: _details);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder button) async {
  await _reveal(tester, button);
  await tester.tap(button);
  await settle(tester);
}

/// « Take Order »: the take prepared, the robot reading the order.
Future<void> _prepare(WidgetTester tester) => _tap(tester, _takeButton);

/// « Continue », then « Done » of « Store your garage key »: the take sent.
Future<void> _confirm(WidgetTester tester) async {
  await _tap(tester, _continueButton);
  expect(find.byType(StoreTokenDialog), findsOneWidget);
  await tester.tap(find.text('Done'));
  await settle(tester);
}

/// The style of the value of the row of [label].
TextStyle? _valueStyleOf(WidgetTester tester, String label) {
  final row = find.ancestor(
    of: find.text(label),
    matching: find.byType(OrderDetailRow),
  );
  final value = tester.widget<OrderDetailRow>(row).value;
  return tester
      .widget<Text>(find.descendant(of: row, matching: find.text(value)))
      .style;
}

void main() {
  setUpAll(() async {
    _read = await preparedTake(description: _description);
    _readWithout = await preparedTake();
    _readFresh = await preparedTake(
      description: 'Revolut only. Pay within 30 minutes.',
      changes: {'price_now': 95000.0, 'satoshis_now': 105263},
    );
    _readRange = await preparedTake(
      range: true,
      amount: TakeAmount.tryCreate(120.5),
      changes: {'satoshis_now': 100000},
    );
    _readLong = await preparedTake(description: _longDescription);
  });

  testWidgets(
    'the reference\'s order: « Take Order » reads the order, « Continue » opens « Store your garage key », whose « Done » takes once',
    (tester) async {
      final take = _Take();
      final (taken, _) = await _show(tester, await _order(), take: take);

      await _prepare(tester);
      // The order read at « Take Order », with no dialog first.
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.amounts, [null]);
      expect(take.confirmed, isEmpty);
      expect(_takeButton, findsNothing);

      // « Go back » of the dialog only closes it, as the reference's does: the order as read stays, its take prepared, nothing sent nor abandoned.
      await _tap(tester, _continueButton);
      expect(find.text('Store your garage key'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(StoreTokenDialog),
          matching: _backButton,
        ),
      );
      await settle(tester);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.abandoned, isEmpty);
      expect(take.abandonedOrders, 0);
      expect(take.confirmed, isEmpty);
      expect(_takeButton, findsNothing);
      await _reveal(tester, _readLine);

      // « Done » after the dialog opened again sends the take of the read still shown, with no new preparation.
      await _confirm(tester);
      expect(take.amounts, [null]);
      expect(take.confirmed, [_read]);
      expect(take.abandoned, isEmpty);
      expect(taken, [TradeScreenStatuses.record]);
    },
  );

  testWidgets(
    'a tap outside « Store your garage key » only closes it: the order as read stays, and « Done » then takes it',
    (tester) async {
      final take = _Take();
      final (taken, cubit) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _tap(tester, _continueButton);
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.abandoned, isEmpty);
      expect(take.abandonedOrders, 0);
      expect(take.confirmed, isEmpty);
      expect(taken, isEmpty);
      expect(cubit.state, isA<TakeReady>());
      await _reveal(tester, _readLine);

      await _confirm(tester);
      expect(take.amounts, [null]);
      expect(take.confirmed, [_read]);
      expect(taken, [TradeScreenStatuses.record]);
    },
  );

  group(
    '« Store your garage key » closed without « Done » (second interface review of #133, I-A): what stays safe',
    () {
      /// Closes the open dialog by [exit]: its « Go back », a tap beside it, or a system back.
      Future<void> close(WidgetTester tester, String exit) async {
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        switch (exit) {
          case 'its « Go back »':
            await tester.tap(
              find.descendant(
                of: find.byType(StoreTokenDialog),
                matching: _backButton,
              ),
            );
          case 'a tap beside it':
            await tester.tapAt(const Offset(4, 4));
          default:
            await tester.binding.handlePopRoute();
        }
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
      }

      const exits = ['its « Go back »', 'a tap beside it', 'a system back'];
      for (final exit in exits) {
        testWidgets(
          'closed by $exit: nothing sent nor abandoned, then « Go back » of the order details abandons the read',
          (tester) async {
            final take = _Take();
            final (taken, cubit) = await _show(
              tester,
              await _order(),
              take: take,
            );
            await _prepare(tester);
            await _tap(tester, _continueButton);
            await close(tester, exit);
            expect(cubit.state, isA<TakeReady>());
            expect(take.abandoned, isEmpty);
            expect(take.abandonedOrders, 0);
            expect(take.confirmed, isEmpty);

            await _tap(tester, _backButton);
            expect(take.abandoned, [_read]);
            expect(take.confirmed, isEmpty);
            expect(taken, isEmpty);
          },
        );

        testWidgets(
          'closed by $exit, then the page left (its cubit closed): the read abandoned, nothing sent',
          (tester) async {
            final take = _Take();
            final (taken, cubit) = await _show(
              tester,
              await _order(),
              take: take,
            );
            await _prepare(tester);
            await _tap(tester, _continueButton);
            await close(tester, exit);
            await tester.runAsync(cubit.close);
            expect(take.abandoned, [_read]);
            expect(take.abandonedOrders, 0);
            expect(take.confirmed, isEmpty);
            expect(taken, isEmpty);
          },
        );
      }

      testWidgets(
        '« Done » after the dialog opened again sends nothing before the confirmation reads the order again: changed meanwhile, the new read shown with « The order changed. », nothing taken',
        (tester) async {
          final take = _Take(prepared: [Ok(_read), Ok(_readFresh)])
            ..answer = () => const Err(TakeOrderChanged());
          final (taken, cubit) = await _show(
            tester,
            await _order(),
            take: take,
          );
          await _prepare(tester);
          await _tap(tester, _continueButton);
          await close(tester, 'a tap beside it');

          await _confirm(tester);
          // The confirmation is the use case's, of the read still shown, which reads the order again before anything is sent.
          expect(take.confirmed, [_read]);
          expect(
            cubit.state,
            isA<TakeReady>()
                .having((s) => s.changed, 'changed', isTrue)
                .having((s) => s.previous, 'previous', same(_read))
                .having((s) => s.prepared, 'prepared', same(_readFresh)),
          );
          await _reveal(tester, find.text('The order changed.'));
          expect(find.text('The order changed.'), findsOneWidget);
          expect(taken, isEmpty);

          // The new read is taken only by « Continue » and « Done » again, once « The order changed. » that moved « Continue » has been seen ([MovedTapGuard], #249).
          take.answer = null;
          await tester.pump(MovedTapGuard.afterMove);
          await _confirm(tester);
          expect(take.confirmed, [_read, _readFresh]);
          expect(taken, [TradeScreenStatuses.record]);
        },
      );

      testWidgets(
        '« Continue » tapped twice opens one dialog at most, sending and abandoning nothing, and « Done » tapped three times confirms once',
        (tester) async {
          final take = _Take()
            ..confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
          final (taken, _) = await _show(tester, await _order(), take: take);
          await _prepare(tester);
          await _tap(tester, _continueButton);
          await close(tester, 'its « Go back »');

          await _reveal(tester, _continueButton);
          final go = tester.getCenter(_continueButton);
          await tester.tapAt(go);
          await tester.pump(const Duration(milliseconds: 16));
          await tester.tapAt(go);
          await settle(tester);
          // The second tap opens no second dialog: it lands on the first one's barrier, which closes it, and that only closes it.
          expect(
            find.byType(StoreTokenDialog).evaluate().length,
            lessThanOrEqualTo(1),
          );
          expect(take.confirmed, isEmpty);
          expect(take.abandoned, isEmpty);
          if (find.byType(StoreTokenDialog).evaluate().isEmpty) {
            await _tap(tester, _continueButton);
          }
          expect(find.byType(StoreTokenDialog), findsOneWidget);

          final done = tester.getCenter(find.text('Done'));
          await tester.tapAt(done);
          await tester.pump(const Duration(milliseconds: 16));
          await tester.tapAt(done);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tapAt(done);
          await settle(tester);
          expect(take.confirmed, [_read]);
          expect(find.byType(OrderDetailsScreen), findsOneWidget);

          take.confirming?.complete(
            Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
          );
          await settle(tester);
          expect(take.confirmed, [_read]);
          expect(taken, [TradeScreenStatuses.record]);
        },
      );

      testWidgets(
        'a dialog opened over the read, whose order is read again meanwhile: its « Done » cannot confirm the old read',
        (tester) async {
          final take = _Take(prepared: [Ok(_read), Ok(_readFresh)])
            ..answer = () => const Err(TakeOrderChanged());
          final (taken, cubit) = await _show(
            tester,
            await _order(),
            take: take,
          );
          await _prepare(tester);
          await _tap(tester, _continueButton);
          expect(find.byType(StoreTokenDialog), findsOneWidget);

          // The order read again under the open dialog (here started by the test, as no gesture of the page can while the dialog is open).
          final again = Completer<Result<PreparedTake, TakeRefusal>>();
          take.preparing = again;
          unawaited(cubit.confirm());
          await tester.pump();
          expect(cubit.state, isA<TakePreparing>());
          expect(take.confirmed, [_read]);

          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(take.confirmed, [_read]);

          take.preparing = null;
          again.complete(Ok(_readFresh));
          await settle(tester);
          expect(cubit.state, isA<TakeReady>());
          expect(take.confirmed, [_read]);
          expect(taken, isEmpty);
        },
      );
    },
  );

  testWidgets(
    'the order read: its description in the order details, as plain text, then the read\'s figures, the bond and the time of the read',
    (tester) async {
      await _show(
        tester,
        await _order(),
        take: _Take(prepared: [Ok(_readFresh)]),
      );
      // Before « Take Order », no robot read anything: no description, the book's price.
      expect(find.text('Order description'), findsNothing);
      expect(find.textContaining('95,000'), findsNothing);

      await _prepare(tester);

      expect(find.text('Order description'), findsOneWidget);
      final words = find.text('Revolut only. Pay within 30 minutes.');
      expect(words, findsOneWidget);
      // Shown as text that cannot be selected, copied or opened.
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.widget<Text>(words).textSpan, isNull);
      expect(find.textContaining('95,000'), findsOneWidget);
      // The bond at the robot's read: 3 % of its 105,263 sats, 3,157.89, and at most that and 2 % of it, plus one sat (the state machine's tolerance).
      expect(find.text('Taker bond'), findsOneWidget);
      expect(find.text('3,158 Sats, at most 3,222 Sats'), findsOneWidget);
      // A row of its own, before « Expires in » and the time left.
      expect(
        tester.getTopLeft(find.text('Taker bond')).dy,
        lessThan(tester.getTopLeft(find.text('Expires in')).dy),
      );
      expect(_readLine, findsOneWidget);
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
    expect(find.text('Order description'), findsNothing);
    expect(_readLine, findsOneWidget);
    await _reveal(tester, _continueButton);
    expect(_continueButton, findsOneWidget);
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

  testWidgets('the maker\'s activity is the read\'s once the order is read', (
    tester,
  ) async {
    final read = await tester.runAsync(
      () => preparedTake(changes: {'maker_status': 'Inactive'}),
    );
    await _show(tester, await _order(), take: _Take(prepared: [Ok(read!)]));
    await _reveal(tester, find.textContaining('Order maker'));
    expect(find.textContaining('Active'), findsOneWidget);
    await _prepare(tester);
    await _reveal(tester, find.textContaining('Order maker'));
    expect(find.textContaining('Inactive'), findsOneWidget);
  });

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
    'the order changed at « Done »: « The order changed. » from the start of the new read, the read seen kept meanwhile, then the rows that changed marked; « Continue » and « Done » again',
    (tester) async {
      final take = _Take()..answer = () => const Err(TakeOrderChanged());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      final again = Completer<Result<PreparedTake, TakeRefusal>>();
      take.preparing = again;

      await _confirm(tester);

      // Read again: said at once, the read seen kept, « Continue » running, no « Take Order ».
      expect(take.confirmed, [_read]);
      expect(take.amounts, hasLength(2));
      await _reveal(tester, find.text('The order changed.'));
      expect(find.text('The order changed.'), findsOneWidget);
      expect(_takeButton, findsNothing);
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('The order changed.'),
                    matching: find.byWidgetPredicate(
                      (w) =>
                          w is Semantics && (w.properties.liveRegion ?? false),
                    ),
                  )
                  .first,
            )
            .properties
            .liveRegion,
        isTrue,
      );
      await _revealAbove(tester, find.text(_description));
      expect(find.text(_description), findsOneWidget);
      expect(find.textContaining('95,000'), findsNothing);

      take.preparing = null;
      again.complete(Ok(_readFresh));
      await settle(tester);

      // The new read, the rows that changed marked as the reference marks the time left: price, sats and description.
      expect(find.textContaining('95,000'), findsOneWidget);
      final style = _valueStyleOf(tester, 'Price and Premium');
      expect(style?.fontWeight, FontWeight.w700);
      final amountStyle = _valueStyleOf(tester, 'Amount');
      expect(amountStyle?.fontWeight, isNot(FontWeight.w700));
      final words = tester.widget<Text>(
        find.text('Revolut only. Pay within 30 minutes.'),
      );
      expect(words.style?.fontWeight, FontWeight.w700);
      // Said to a screen reader, not by the colour alone, and the label marked too (second interface review of #133, M1).
      final price = tester.widget<Text>(find.textContaining('95,000'));
      expect(price.semanticsLabel, 'New value: ${price.data}');
      final amount = tester.widget<OrderDetailRow>(
        find.ancestor(
          of: find.text('Amount'),
          matching: find.byType(OrderDetailRow),
        ),
      );
      expect(amount.changed, isFalse);
      expect(
        tester.widget<Text>(find.text('Price and Premium')).style?.color,
        price.style?.color,
      );
      expect(
        tester.widget<Text>(find.text('Amount')).style?.color,
        isNot(price.style?.color),
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('Revolut only. Pay within 30 minutes.'),
                    matching: find.byWidgetPredicate(
                      (w) => w is Semantics && w.properties.value != null,
                    ),
                  )
                  .first,
            )
            .properties
            .value,
        'New value: Revolut only. Pay within 30 minutes.',
      );
      await _reveal(tester, find.text('The order changed.'));
      expect(taken, isEmpty);

      // « The order changed. » moved « Continue »: a tap at once is aimed at what stood there ([MovedTapGuard], #249).
      take.answer = null;
      await tester.pump(MovedTapGuard.afterMove);
      await _confirm(tester);
      expect(take.confirmed, [_read, _readFresh]);
      expect(taken, [TradeScreenStatuses.record]);
    },
  );

  testWidgets(
    'the order changed at « Done » with a new expiry: the expiry row is marked as changed, the amount is not',
    (tester) async {
      final later = await preparedTake(
        description: _description,
        changes: {
          'expires_at': _read.order.expiresAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
      final take = _Take(prepared: [Ok(_read), Ok(later)])
        ..answer = () => const Err(TakeOrderChanged());
      await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _confirm(tester);
      await _reveal(tester, find.text('The order changed.'));
      OrderDetailRow row(String label) => tester.widget<OrderDetailRow>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OrderDetailRow),
        ),
      );
      await _revealAbove(tester, find.text('Expires in'));
      expect(row('Expires in').changed, isTrue);
      await _revealAbove(tester, find.text('Amount'));
      expect(row('Amount').changed, isFalse);
    },
  );

  testWidgets(
    'a changed expiry is told apart from a near one: its label marked and « New value » said, a near one marks its value only',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  OrderDetailRow(
                    'Near',
                    '1h 00m 00s',
                    color: Theme.of(context).colorScheme.tertiary,
                    bold: true,
                  ),
                  const OrderDetailRow('Changed', '20h 00m 00s', changed: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final near = tester.widget<Text>(find.text('Near'));
      final changed = tester.widget<Text>(find.text('Changed'));
      final changedValue = tester.widget<Text>(find.text('20h 00m 00s'));
      expect(changed.style?.color, changedValue.style?.color);
      expect(near.style?.color, isNot(changed.style?.color));
      expect(changedValue.style?.fontWeight, FontWeight.w700);
      expect(find.bySemanticsLabel('New value: 20h 00m 00s'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('New value: 1h')), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the order gone at « Done »: « This order is not available », and « Take Order » stays disabled',
    (tester) async {
      final take = _Take()..answer = () => const Err(TakeOrderGone());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _confirm(tester);
      await _reveal(tester, find.text('This order is not available'));
      expect(find.text('This order is not available'), findsOneWidget);
      expect(taken, isEmpty);
      expect(find.text(_description), findsNothing);
      await tester.tap(_takeButton, warnIfMissed: false);
      await settle(tester);
      expect(take.amounts, hasLength(1));
    },
  );

  for (final (label, again, changed)
      in <(String, PreparedTake Function(), bool)>[
        ('showing the order as before', () => _read, false),
        ('showing it otherwise (no description now)', () => _readWithout, true),
      ]) {
    testWidgets(
      'the preparation gone at « Done », read again $label: waiting for « Continue »${changed ? ', « The order changed. » said (security review of #133, M3)' : ''}',
      (tester) async {
        final take = _Take(prepared: [Ok(_read), Ok(again())])
          ..answer = () => const Err(TakePreparationGone());
        final (taken, _) = await _show(tester, await _order(), take: take);
        await _prepare(tester);
        await _confirm(tester);
        expect(take.amounts, hasLength(2));
        await _reveal(tester, _continueButton);
        expect(
          find.text('The order changed.'),
          changed ? findsOneWidget : findsNothing,
        );
        expect(_continueButton, findsOneWidget);
        expect(taken, isEmpty);
      },
    );
  }

  testWidgets(
    'the preparation gone at « Done », read again with its figures alone changed: « The order changed. », the price and sats rows marked, the description not (second security review of #133)',
    (tester) async {
      final figures = await tester.runAsync(
        () => preparedTake(
          description: _description,
          changes: {'price_now': 95000.0, 'satoshis_now': 105263},
        ),
      );
      final take = _Take(prepared: [Ok(_read), Ok(figures!)])
        ..answer = () => const Err(TakePreparationGone());
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _confirm(tester);
      await _reveal(tester, find.text('The order changed.'));
      expect(find.text('The order changed.'), findsOneWidget);
      OrderDetailRow row(String label) => tester.widget<OrderDetailRow>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OrderDetailRow),
        ),
      );
      await _revealAbove(tester, find.text('Price and Premium'));
      expect(row('Price and Premium').changed, isTrue);
      await _revealAbove(tester, find.text(_description));
      expect(
        tester
            .widget<OrderDescriptionRow>(find.byType(OrderDescriptionRow))
            .changed,
        isFalse,
      );
      await _revealAbove(tester, find.text('You receive'));
      expect(row('You receive').changed, isTrue);
      expect(row('Amount').changed, isFalse);
      expect(taken, isEmpty);
    },
  );

  testWidgets(
    'the preparation gone at « Done », read again with another taker fee alone: « The order changed. », the fee and the sats marked (second security review of #133)',
    (tester) async {
      final fee = await tester.runAsync(
        () => preparedTake(description: _description, fee: 0.002),
      );
      final take = _Take(prepared: [Ok(_read), Ok(fee!)])
        ..answer = () => const Err(TakePreparationGone());
      final (taken, _) = await _show(
        tester,
        await _order(),
        take: take,
        withFees: true,
      );
      await _prepare(tester);
      await _confirm(tester);
      await _reveal(tester, find.text('The order changed.'));
      expect(find.text('The order changed.'), findsOneWidget);
      await _revealAbove(tester, find.textContaining('0.200'));
      final shown = tester.widget<Text>(find.textContaining('0.200'));
      expect(shown.semanticsLabel, 'New value: ${shown.data}');
      expect(shown.style?.fontWeight, FontWeight.w700);
      OrderDetailRow row(String label) => tester.widget<OrderDetailRow>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OrderDetailRow),
        ),
      );
      await _reveal(tester, find.text('You receive'));
      expect(row('You receive').changed, isTrue);
      await _reveal(tester, find.text('Price and Premium'));
      expect(row('Price and Premium').changed, isFalse);
      expect(taken, isEmpty);
    },
  );

  testWidgets(
    'the payment methods, the « You send via » sentence and the maker shown are the read\'s, those the take goes out on (security review of #133, I1)',
    (tester) async {
      final maker = switch (RobotHashId.parse(
        '0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0',
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      final read = await tester.runAsync(
        () => preparedTake(
          description: 'Wise only, no notes in the transfer.',
          changes: {
            'payment_method': 'Wise',
            'maker_hash_id': maker.hex,
            'maker_nick': maker.nickname,
          },
        ),
      );
      await _show(tester, await _order(), take: _Take(prepared: [Ok(read!)]));
      expect(find.textContaining('Wise'), findsNothing);
      await _prepare(tester);
      await _revealAbove(tester, find.text('You send via Wise'));
      expect(find.text('You send via Wise'), findsOneWidget);
      expect(find.textContaining('Revolut'), findsNothing);
      await _reveal(tester, find.text(maker.nickname));
      expect(find.text(maker.nickname), findsOneWidget);
    },
  );

  testWidgets(
    'a range order: the amount field locked from « Take Order » while the vault is read, the amount prepared the one shown (security review of #133, I2)',
    (tester) async {
      final vault = Completer<Result<bool, P2pFailure>>();
      final take = _Take(prepared: [Ok(_readRange)]);
      await _show(
        tester,
        await _order(range: true),
        take: take,
        vault: () => vault.future,
      );
      await _reveal(tester, _takeButton);
      final field = find.byType(TextField);
      await tester.enterText(field, '100');
      await tester.pump();
      await tester.tap(_takeButton);
      await tester.pump();
      expect(tester.widget<TextField>(field).enabled, isFalse);
      vault.complete(const Ok(true));
      await settle(tester);
      expect(take.amounts.single?.amount.value, 100);
      await _reveal(tester, field);
      expect(find.text('100'), findsOneWidget);
    },
  );

  testWidgets(
    'a range order prepared again after « The order changed. » keeps its amount, and its estimate is the amount prepared at the read\'s rate',
    (tester) async {
      final take = _Take(prepared: [Ok(_readRange), Ok(_readRange)])
        ..answer = () => const Err(TakeOrderChanged());
      await _show(tester, await _order(range: true), take: take);
      await _reveal(tester, _takeButton);
      await tester.enterText(find.byType(TextField), '120,5');
      await tester.pump();
      await _prepare(tester);
      await _confirm(tester);
      expect(take.amounts.map((a) => a?.amount.value), [120.5, 120.5]);
      await _reveal(tester, find.byType(TextField));
      expect(
        find.text('You will receive 60,145 Sats (Approx)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the sats the order details say are the read\'s, at its terms\' taker fee, also while the take is sent (security review of #133, M5)',
    (tester) async {
      final take = _Take(prepared: [Ok(_readFresh)])
        ..confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      await _show(tester, await _order(), take: take);
      // The book's: 106,900 sats, no fee known, the routing budget off.
      expect(find.textContaining('106,793'), findsOneWidget);
      await _prepare(tester);
      // The read's: 105,263 sats, its taker fee of 0.175 % on, the routing budget off.
      await _revealAbove(tester, find.textContaining('105,342'));
      expect(find.textContaining('105,342'), findsOneWidget);
      expect(find.textContaining('106,793'), findsNothing);
      await _confirm(tester);
      await _revealAbove(tester, find.textContaining('105,342'));
      expect(find.textContaining('105,342'), findsOneWidget);
      expect(find.textContaining('95,000'), findsOneWidget);
      take.confirming?.complete(
        Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
      );
      await settle(tester);
    },
  );

  testWidgets(
    'the taker fee shown is the terms\' once the order is read (security review of #133, M2)',
    (tester) async {
      final read = await tester.runAsync(() => preparedTake(fee: 0.002));
      await _show(
        tester,
        await _order(),
        take: _Take(prepared: [Ok(read!)]),
        withFees: true,
      );
      expect(find.textContaining('0.175'), findsOneWidget);
      await _prepare(tester);
      await _revealAbove(tester, find.textContaining('0.200'));
      expect(find.textContaining('0.200'), findsOneWidget);
      expect(find.textContaining('0.175'), findsNothing);
    },
  );

  testWidgets(
    'the take sent: the read stays shown and « Take Order » does not come back while the trade\'s screen opens',
    (tester) async {
      final take = _Take()
        ..confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _confirm(tester);
      take.confirming?.complete(
        Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
      );
      await settle(tester);
      expect(taken, [TradeScreenStatuses.record]);
      await _reveal(tester, _continueButton);
      expect(_takeButton, findsNothing);
      await _revealAbove(tester, find.text(_description));
      expect(find.text(_description), findsOneWidget);
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

      await _prepare(tester);
      expect(find.byType(NoRobotDialog), findsOneWidget);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.amounts, isEmpty);
    },
  );

  testWidgets(
    'without robots in the feature: « You do not have a Garage Key »',
    (tester) async {
      await _show(tester, await _order(), canTake: false);
      await _prepare(tester);
      expect(find.byType(NoRobotDialog), findsOneWidget);
    },
  );

  testWidgets(
    'while the order is read, « Take Order » cannot be pressed again; while the take is sent, neither « Continue » nor « Go back »',
    (tester) async {
      final take = _Take()
        ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
      await _show(tester, await _order(), take: take);
      await _prepare(tester);
      // The bar of the step, under the button, with the bar of the order's time left.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      await tester.tap(_takeButton, warnIfMissed: false);
      await settle(tester);
      expect(take.amounts, hasLength(1));

      take.preparing?.complete(Ok(_read));
      take.preparing = null;
      await settle(tester);
      take.confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      await _confirm(tester);
      await _reveal(tester, _backButton);
      await tester.tap(_continueButton, warnIfMissed: false);
      await tester.tap(_backButton, warnIfMissed: false);
      await settle(tester);
      expect(find.byType(StoreTokenDialog), findsNothing);
      expect(take.confirmed, hasLength(1));
      expect(take.abandoned, isEmpty);

      take.confirming?.complete(
        Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
      );
      await settle(tester);
    },
  );

  testWidgets('a read that runs long says it still waits', (tester) async {
    final take = _Take()
      ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
    await _show(tester, await _order(), take: take);
    await _reveal(tester, _takeButton);
    await tester.tap(_takeButton);
    await tester.pump(const Duration(seconds: 31));
    expect(
      find.text('Still waiting for Temple of Sats. Tor can take a minute.'),
      findsOneWidget,
    );
    take.preparing?.complete(Ok(_read));
    await settle(tester);
  });

  testWidgets(
    'the wait says the step that runs under the bar, and none that has not started',
    (tester) async {
      final take = _Take()
        ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
      await _show(tester, await _order(), take: take);
      await _reveal(tester, _takeButton);
      await tester.tap(_takeButton);
      await tester.pump();
      // Before any step starts: the bar only.
      expect(find.text('Checking the order with Temple of Sats'), findsNothing);
      expect(find.text('Building your robot!'), findsNothing);
      expect(find.text('Your robot is reading the order'), findsNothing);
      take.preparing?.complete(Ok(_read));
      take.preparing = null;
      await settle(tester);

      // The steps a preparation says are shown one at a time, the latest only.
      final steps = Completer<Result<PreparedTake, TakeRefusal>>();
      take
        ..preparing = steps
        ..preparingSteps = [TakeStep.checkingOrder];
      await _tap(tester, _backButton);
      await _reveal(tester, _takeButton);
      await tester.tap(_takeButton);
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
      expect(find.text('Your robot is reading the order'), findsNothing);
      steps.complete(Ok(_read));
      await settle(tester);
      expect(find.text('Checking the order with Temple of Sats'), findsNothing);

      final confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
      take
        ..confirming = confirming
        ..confirmingSteps = [TakeStep.readingOrderAgain, TakeStep.sendingTake];
      await _confirm(tester);
      await _reveal(tester, find.text('Taking the order with Temple of Sats'));
      expect(find.text('Taking the order with Temple of Sats'), findsOneWidget);
      expect(find.text('Your robot is reading the order again'), findsNothing);
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
      'Your robot is reading the order',
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
        final takeOrder = find.text(
          locale.languageCode == 'fr' ? 'Prendre l\'ordre' : 'Take Order',
        );
        await _reveal(tester, takeOrder);
        await tester.tap(takeOrder);
        await tester.pump();
        final line = find.text(locale.languageCode == 'fr' ? fr : en);
        await _reveal(tester, line);
        expect(line, findsOneWidget);
        expect(tester.getSemantics(line), isSemantics(isLiveRegion: true));
        take.preparing?.complete(Ok(_read));
        await settle(tester);
        semantics.dispose();
      }
    });
  }

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
  ]) {
    testWidgets('a preparation refused: « $text »', (tester) async {
      final take = _Take(prepared: [refusal]);
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
      expect(taken, isEmpty);
      expect(_continueButton, findsNothing);
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
    testWidgets('a take not made: « $text »', (tester) async {
      final take = _Take()..answer = () => answer;
      final (taken, _) = await _show(tester, await _order(), take: take);
      await _prepare(tester);
      await _confirm(tester);
      await _reveal(tester, find.text(text));
      expect(find.text(text), findsOneWidget);
      expect(taken, isEmpty);
    });
  }

  testWidgets(
    'a buy order is taken as a sell order is: its taker sells (#96)',
    (tester) async {
      final take = _Take();
      await _show(tester, await _order(type: 0), take: take);
      expect(find.text('Selling is coming in a later version.'), findsNothing);
      await _prepare(tester);
      expect(take.amounts, hasLength(1));
    },
  );

  testWidgets(
    'a buy order: the same « You send via Lightning » figure before and after its robot reads it, the seller\'s (#96)',
    (tester) async {
      final read = await preparedTake(changes: {'type': 0});
      expect(read.terms.role, TradeRole.seller);
      await _show(
        tester,
        await _order(type: 0),
        take: _Take(prepared: [Ok(read)]),
        withFees: true,
      );
      // The reference's seller estimate: 106,900 sats with the taker fee (0.175 %) off, no routing budget (`OrderDetails/index.tsx:237-258`).
      await _reveal(tester, find.textContaining('106,713'));
      expect(find.textContaining('106,713'), findsOneWidget);
      await _prepare(tester);
      await _revealAbove(tester, find.textContaining('You send via Lightning'));
      expect(find.textContaining('106,713'), findsOneWidget);
      // The buyer's formula (the fee counted against the coordinator, the routing budget off) would give 106,980.
      expect(find.textContaining('106,980'), findsNothing);
    },
  );

  testWidgets(
    'a range buy order read by its robot: the line under the amount and the read\'s figures both the seller\'s (#96)',
    (tester) async {
      final read = await preparedTake(
        range: true,
        amount: TakeAmount.tryCreate(120.5),
        changes: {'satoshis_now': 100000, 'type': 0},
      );
      await _show(
        tester,
        await _order(type: 0, range: true),
        take: _Take(prepared: [Ok(read)]),
        withFees: true,
      );
      await _reveal(tester, _takeButton);
      await tester.enterText(find.byType(TextField), '120,5');
      await tester.pump();
      await _prepare(tester);
      await _reveal(tester, find.text('You will send 60,145 Sats (Approx)'));
      expect(find.text('You will send 60,145 Sats (Approx)'), findsOneWidget);
      // The read's range at the seller's formula: 24,956 to 99,825; the buyer's would end at 100,074.
      await _revealAbove(tester, find.textContaining('99,825'));
      expect(find.textContaining('99,825'), findsOneWidget);
      expect(find.textContaining('100,074'), findsNothing);
    },
  );

  testWidgets(
    'a range buy order: « You will send … Sats (Approx) », the same figure (#96)',
    (tester) async {
      await _show(tester, await _order(type: 0, range: true));
      await _reveal(tester, _takeButton);
      await tester.enterText(find.byType(TextField), '100');
      await tester.pump();
      expect(find.text('You will send 53,450 Sats (Approx)'), findsOneWidget);
      expect(find.textContaining('You will receive'), findsNothing);
    },
  );

  testWidgets(
    'a range order: the amount first, « Too low », « Too high », the estimate, then the read with the amount kept and its own estimate',
    (tester) async {
      final take = _Take(prepared: [Ok(_readRange)]);
      await _show(tester, await _order(range: true), take: take);
      await _reveal(tester, _takeButton);
      expect(find.text('Amount EUR'), findsOneWidget);
      expect(
        find.byTooltip('You must specify an amount first'),
        findsOneWidget,
      );
      await tester.tap(_takeButton, warnIfMissed: false);
      await settle(tester);
      expect(take.amounts, isEmpty);

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
      // The book's estimate: 120.5 of 200 EUR for 106,900 sats, the fee unknown.
      expect(
        find.text('You will receive 64,407 Sats (Approx)'),
        findsOneWidget,
      );

      await _prepare(tester);
      expect(take.amounts.single?.amount.value, 120.5);
      // The amount chosen stays shown, and cannot be changed while the read is shown.
      await _reveal(tester, field);
      expect(tester.widget<TextField>(field).enabled, isFalse);
      expect(find.text('120,5'), findsOneWidget);
      // The read's estimate: 120.5 of 200 EUR for its 100,000 sats, its taker fee off.
      expect(
        find.text('You will receive 60,145 Sats (Approx)'),
        findsOneWidget,
      );
      await _revealAbove(tester, find.text('Amount Range'));
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
    'a screen reader hears the description with its label, the read when it arrives, and both buttons',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _show(tester, await _order(), take: _Take());
      await _prepare(tester);
      await _revealAbove(tester, find.text(_description));
      expect(find.bySemanticsLabel('Order description'), findsOneWidget);
      final node = tester.getSemantics(find.byType(OrderDescriptionRow));
      expect(node.value, _description);
      await _reveal(tester, _readLine);
      expect(
        tester.getSemantics(_readLine),
        isSemantics(
          label: 'Read by your robot at 08:00:30',
          isLiveRegion: true,
        ),
      );
      await _reveal(tester, _backButton);
      expect(
        tester.getSemantics(_continueButton),
        isSemantics(label: 'Continue', isButton: true, isEnabled: true),
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
          await _confirm(tester);
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
    void nothingCut(WidgetTester tester, String reason) {
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

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: nothing overflows or is cut',
          (tester) async {
            final fr = locale.languageCode == 'fr';
            final take = _Take(prepared: [Ok(_readRange), Ok(_readLong)])
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
            nothingCut(tester, 'range');
            await tester.enterText(find.byType(TextField), '10');
            await tester.pump();
            nothingCut(tester, 'too low');
            await tester.enterText(find.byType(TextField), '120');
            await tester.pump();
            nothingCut(tester, 'estimate');
            await _reveal(tester, button);
            await tester.tap(button);
            await settle(tester);
            nothingCut(tester, 'read');
            final go = find.text(fr ? 'Continuer' : 'Continue');
            await _reveal(tester, go);
            nothingCut(tester, 'continue');
            await tester.tap(go);
            await settle(tester);
            nothingCut(tester, 'store your garage key');
            // The dialog scrolls at this size: « Done » is brought into view, then pressed.
            final done = find.text(fr ? 'Fait' : 'Done');
            await tester.ensureVisible(done);
            await tester.pump();
            await tester.tap(done);
            await settle(tester);
            await _reveal(tester, go);
            nothingCut(tester, 'changed');
            // The longest description, of long words.
            await _revealAbove(tester, find.text(_longDescription));
            nothingCut(tester, 'description');
          },
        );

        testWidgets(
          '${locale.languageCode} at ×$scale: the lines of a step and « Still waiting » are not cut',
          (tester) async {
            final fr = locale.languageCode == 'fr';
            final take = _Take()
              ..preparingSteps = [TakeStep.creatingRobot]
              ..preparing = Completer<Result<PreparedTake, TakeRefusal>>();
            await _show(
              tester,
              await _order(),
              take: take,
              locale: locale,
              size: const Size(320, 568),
              textScale: scale,
            );
            final button = find.text(fr ? 'Prendre l\'ordre' : 'Take Order');
            await _reveal(tester, button);
            await tester.tap(button);
            await tester.pump(const Duration(seconds: 31));
            final still = find.text(
              fr
                  ? 'Toujours en attente de Temple of Sats. Tor peut prendre une minute.'
                  : 'Still waiting for Temple of Sats. Tor can take a minute.',
            );
            await _reveal(tester, still);
            nothingCut(tester, 'still waiting');
            take.preparing?.complete(Ok(_read));
            await settle(tester);
          },
        );

        testWidgets(
          '${locale.languageCode} at ×$scale: after « Done », the lines of a step and « Still waiting » are not cut',
          (tester) async {
            final fr = locale.languageCode == 'fr';
            final take = _Take()
              ..confirmingSteps = [
                TakeStep.readingOrderAgain,
                TakeStep.sendingTake,
              ]
              ..confirming = Completer<Result<TakeOutcome, TakeRefusal>>();
            await _show(
              tester,
              await _order(),
              take: take,
              locale: locale,
              size: const Size(320, 568),
              textScale: scale,
            );
            final button = find.text(fr ? 'Prendre l\'ordre' : 'Take Order');
            await _reveal(tester, button);
            await tester.tap(button);
            await settle(tester);
            final go = find.text(fr ? 'Continuer' : 'Continue');
            await _reveal(tester, go);
            await tester.tap(go);
            await settle(tester);
            final done = find.text(fr ? 'Fait' : 'Done');
            await tester.ensureVisible(done);
            await tester.pump();
            await tester.tap(done);
            await tester.pump(const Duration(seconds: 31));
            final step = find.text(
              fr
                  ? 'Prise de l’ordre auprès de Temple of Sats'
                  : 'Taking the order with Temple of Sats',
            );
            await _reveal(tester, step);
            nothingCut(tester, 'step after « Done »');
            final still = find.text(
              fr
                  ? 'Toujours en attente de Temple of Sats. Tor peut prendre une minute.'
                  : 'Still waiting for Temple of Sats. Tor can take a minute.',
            );
            await _reveal(tester, still);
            nothingCut(tester, 'still waiting after « Done »');
            take.confirming?.complete(
              Ok(TakeOutcomeUnknown(TradeScreenStatuses.record)),
            );
            await settle(tester);
          },
        );
      }
    }
  });

  testWidgets(
    'a read of the Bull wallet\'s price that ends in an error while « Continue » waits: « Continue » is busy no more (security review of #249\'s slice 4, R3)',
    (tester) async {
      final order = await _order();
      final (_, cubit) = await _show(
        tester,
        order,
        cubit: (calls, hasKey) =>
            _FailingPriceCubit(order, RobosatsNetwork.mainnet, calls, hasKey),
      );
      await _prepare(tester);
      (cubit as _FailingPriceCubit).reading();
      await settle(tester);
      await _reveal(tester, _continueButton);
      // The error is the price service's bug, never caught by the page: it is caught here, in the zone the tap starts « Continue » in.
      Object? caught;
      final pressed = tester
          .widget<TradeButton>(
            find.ancestor(
              of: _continueButton,
              matching: find.byType(TradeButton),
            ),
          )
          .onPressed;
      expect(pressed, isNotNull);
      runZonedGuarded(() => pressed?.call(), (error, _) => caught = error);
      await tester.pump();
      await settle(tester);
      expect(caught, isA<StateError>());
      expect(find.byType(StoreTokenDialog), findsNothing);
      final button = tester.widget<TradeButton>(
        find.ancestor(of: _continueButton, matching: find.byType(TradeButton)),
      );
      expect(button.busy, isFalse);
    },
  );

  group('« A fresh robot for this order » (#251)', () {
    // A fictional nickname, as on the owner's mock-up: never a real robot.
    const nickname = 'SilentOtter218';
    PreparedTake fresh() => PreparedTake(
      order: _read.order,
      terms: _read.terms,
      amount: _read.amount,
      readAt: _read.readAt,
      freshRobot: nickname,
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'said under « Read by your robot » only when the read says the robot changed, in ${locale.languageCode}',
        (tester) async {
          final l10n = lookupP2pLocalizations(locale);
          await _show(tester, await _order(), locale: locale);
          await _tap(tester, find.text(l10n.p2pTakeOrder));
          expect(find.text(l10n.p2pTakeFreshRobot(nickname)), findsNothing);

          await _show(
            tester,
            await _order(),
            locale: locale,
            take: _Take(prepared: [Ok(fresh())]),
          );
          await _tap(tester, find.text(l10n.p2pTakeOrder));
          final line = find.text(l10n.p2pTakeFreshRobot(nickname));
          await _reveal(tester, line);
          expect(line, findsOneWidget);
          final readAt = find.textContaining(l10n.p2pTakeReadAt('').trim());
          expect(
            tester.getTopLeft(line).dy,
            greaterThan(tester.getTopLeft(readAt).dy),
          );
          // Read out when it appears.
          expect(
            tester
                .widget<Semantics>(
                  find
                      .ancestor(of: line, matching: find.byType(Semantics))
                      .first,
                )
                .properties
                .liveRegion,
            isTrue,
          );
        },
      );

      for (final scale in const [1.0, 2.0, 3.0]) {
        testWidgets(
          'at 320 points, text ×${scale.toInt()}, in ${locale.languageCode}: the whole line, no overflow',
          (tester) async {
            final l10n = lookupP2pLocalizations(locale);
            await _show(
              tester,
              await _order(),
              locale: locale,
              size: const Size(320, 844),
              textScale: scale,
              take: _Take(prepared: [Ok(fresh())]),
            );
            await _tap(tester, find.text(l10n.p2pTakeOrder));
            final line = find.text(l10n.p2pTakeFreshRobot(nickname));
            await _reveal(tester, line);
            expect(line, findsOneWidget);
            expect(tester.takeException(), isNull);
            final paragraph = tester.renderObject<RenderParagraph>(line);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(tester.getRect(line).right, lessThanOrEqualTo(320 + 0.5));
          },
        );
      }
    }

    testWidgets(
      'the Garage\'s robot read before the preparation, and handed to it',
      (tester) async {
        final events = <String>[];
        final robot = RobotSlot(
          RobosatsNetwork.mainnet,
          switch (GarageKeyFingerprint.of(switch (GarageKey.fromBytes(
            Uint8List.fromList(List<int>.generate(32, (i) => i + 3)),
          )) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          })) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          },
          4,
        );
        final order = await _order();
        await _show(
          tester,
          order,
          cubit: (calls, keys) => TakeOrderCubit(
            order,
            RobosatsNetwork.mainnet,
            TakeCalls(
              prepare:
                  (
                    shown, {
                    required network,
                    amount,
                    onStep,
                    garageRobot,
                  }) async {
                    events.add('prepare ${garageRobot?.accountIndex}');
                    return Ok(_read);
                  },
              confirm: calls.confirm,
              abandon: calls.abandon,
              abandonOrder: calls.abandonOrder,
              garageRobot: (network) async {
                events.add('garage ${network.name}');
                return robot;
              },
            ),
            keys,
          ),
        );
        await _tap(tester, _takeButton);
        expect(events, ['garage mainnet', 'prepare 4']);
      },
    );

    testWidgets(
      'the page left while the Garage\'s robot is read: nothing prepared, so no robot reserved and no order read',
      (tester) async {
        final events = <String>[];
        final reading = Completer<RobotSlot?>();
        final order = await _order();
        final cubit = TakeOrderCubit(
          order,
          RobosatsNetwork.mainnet,
          TakeCalls(
            prepare:
                (shown, {required network, amount, onStep, garageRobot}) async {
                  events.add('prepare');
                  return Ok(_read);
                },
            confirm: (prepared, {password, onStep}) =>
                throw StateError('not taken'),
            abandon: (_) => events.add('abandon'),
            abandonOrder: (shown, {required network}) =>
                events.add('abandon order'),
            garageRobot: (network) {
              events.add('garage');
              return reading.future;
            },
          ),
          (network) async => const Ok(true),
        );
        final taking = cubit.take();
        await tester.pump();
        expect(events, ['garage']);
        await cubit.close();
        reading.complete(null);
        await taking;
        await tester.pump(const Duration(minutes: 1));
        expect(events, isNot(contains('prepare')));
      },
    );
  });
}

/// A take whose Bull wallet's price is said read, and whose read ends in an error (an `Error`, a bug, as the price's service would throw one).
final class _FailingPriceCubit extends TakeOrderCubit {
  _FailingPriceCubit(super.order, super.network, super.calls, super.hasKey);

  /// The read shown, its price said being read.
  void reading() => emit(
    TakeReady((state as TakeReady).prepared, price: const TakePriceReading()),
  );

  @override
  Future<void> priceSettled() async => throw StateError('a bug of the read');
}
