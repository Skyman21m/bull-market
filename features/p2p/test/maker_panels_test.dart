import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/public_wait.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/src/ui/trade/confirm_cancel_dialog.dart';
import 'package:p2p/src/ui/trade/confirm_fiat_sent_dialog.dart';
import 'package:p2p/src/ui/trade/rate_gap_line.dart';
import 'package:p2p/src/ui/trade/trade_order_details.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart'
    show FakeTransport, bookOrder, coordinator, parseOrders, testNow;
import 'support/captures.dart';
import 'support/harness.dart';
import 'support/make_form.dart' show infoAt;
import 'support/maker_orders.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The trade screen of an order made here, buy side (#182): the reference's `TradeBox` for a maker (`TradeBox/index.tsx:359-457`, `Prompts/PublicWait.tsx`, `Prompts/Paused.tsx`, `Prompts/Expired.tsx`, `CancelButton.tsx`, `BondStatus.tsx:39`, `stepXofY.ts`), then the buyer's panels of phase 2 with a maker's variants (the gap before « Submit » and in « Confirm … sent », 17 and 18 by side, back in the book, a next contract), in the wallet's look.
///
/// Every status comes from the state machine, from the reference's answers to a maker (`support/maker_orders.dart`) read in sequence, never built by hand.

/// The order made here, as the repository gives it once confirmed.
final _record = TradeRecord(
  robot: RobotSlot(RobosatsNetwork.mainnet, switch (GarageKeyFingerprint.of(
    tradeKey,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  }, 0),
  coordinatorAlias: 'temple',
  coordinatorOnion:
      Federation.robosats.byAlias('temple')?.mainnet.onion ??
      (throw StateError('temple')),
  orderId: tradeOrderId,
  role: TradeRole.buyer,
  origin: TradeOrigin.madeHere,
  takenAt: madeAt,
  confirmedAt: madeAt,
  closedAt: null,
);

final _reader = Bolt11Reader(Bolt11TestDecoder([makerBondInvoice()]));

/// The statuses of the reference's answers [answers] read one after the other by the state machine, from the order's first read (`TradeStatus.afterMake`): an order's JSON, or an answer of another kind ([TradeAnswer]).
Future<List<TradeSeen>> _chain(List<Object> answers) async {
  final terms = madeTerms();
  final seen = <TradeSeen>[];
  TradeStatus? status;
  for (final given in answers) {
    final order = given is Map<String, Object?> ? await readOrder(given) : null;
    final answer = order != null
        ? TradeOrderRead(order)
        : given is TradeAnswer
        ? given
        : throw StateError('$given');
    status = status == null
        ? TradeStatus.afterMake(
            answer,
            terms: terms,
            now: tradeNow,
            reader: _reader,
          )
        : TradeStatus.from(
            previous: status,
            answer: answer,
            terms: terms,
            now: tradeNow,
            reader: _reader,
          );
    seen.add(TradeSeen(status, order: order, stored: true));
  }
  return seen;
}

/// The last status of [answers] read in sequence.
Future<TradeSeen> _at(List<Object> answers) async =>
    (await _chain(answers)).last;

/// A contract fixed for 101,000 sats where the creation's rate gave 106,900: a rate higher by 5.85 %, fewer sats for the maker buyer.
const _lowSats = 101000;

/// What the screen asked of the trade's cubit.
final class _Asked {
  final List<(TradeSeen, BondLossAcknowledged?)> cancels = [];
  final List<TradeSeen> fiatSent = [];
}

/// Shows the trade screen of [_record] at [seen], over a cubit whose watch the test feeds, with [book] for the figures of a public order; the cancel answers [cancel].
Future<(_Asked, StreamController<TradeWatchState>)> _show(
  WidgetTester tester,
  TradeSeen seen, {
  List<PublicOrder>? book,
  Locale locale = const Locale('en'),
  Future<Result<CancelOutcome, CancelRefusal>> Function(TradeSeen seen)? cancel,
  PayoutRateCubit? rate,
}) async {
  tester.view
    ..physicalSize = const Size(390, 1600) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final asked = _Asked();
  final trade = TradeCubit(
    _record,
    (record, {signals = const Stream.empty(), onScreen = true}) {
      signals.listen((_) {});
      return watch.stream;
    },
    (record, seen, {bondLoss}) {
      asked.cancels.add((seen, bondLoss));
      return cancel?.call(seen) ?? Completer<Never>().future;
    },
    confirmFiatSent: (record, seen, {onProgress}) {
      asked.fiatSent.add(seen);
      return Completer<Never>().future;
    },
  )..start();
  addTearDown(trade.close);
  final reads = FakeTransport();
  final page = TradeOrderPageCubit(
    coordinator('temple'),
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
    FindPublicOrderUsecase(
      CoordinatorClient(reads, clock: () => testNow),
    ).execute,
  );
  addTearDown(page.close);
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
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: trade),
              BlocProvider.value(value: page),
              if (rate != null) BlocProvider.value(value: rate),
            ],
            // A screen of its own at each show, so that a tab chosen in a show before is not kept.
            child: TradeScreen(
              key: UniqueKey(),
              now: () => tradeNow,
              coordinatorDetails: (_) => throw StateError('not opened'),
              book: book,
              checksPayoutRate: rate != null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(TradeScreenStatuses.watched(seen, of: _record));
  await tester.pump();
  await tester.pump();
  return (asked, watch);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Every text shown: none names the project's internal name nor the swap engine.
void _noInternalNames(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(contains('Troc')));
    expect(text.data ?? '', isNot(contains('Boltz')));
  }
}

void main() {
  group('the panels\' model, by the reference\'s `statusToContract`', () {
    test(
      'the step « (x/5) » of a maker: 0 → 1, 1 and 2 → 2, 6 to 8 → 3, 9 → 4, 10 → 5, none elsewhere (`stepXofY.ts:15-26`)',
      () async {
        final seen = await _chain([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(2),
          makerOrderJson(1),
          makerOrderJson(6),
          makerOrderJson(8),
          makerOrderJson(9),
          makerOrderJson(10),
          makerOrderJson(13),
        ]);
        expect(
          [for (final s in seen) TradeContract(s, order: s.order).step],
          [
            (1, 5),
            (2, 5),
            (2, 5),
            (2, 5),
            (3, 5),
            (3, 5),
            (4, 5),
            (5, 5),
            null,
          ],
        );
        final expired = await _at([makerOrderJson(0), makerOrderJson(5)]);
        expect(TradeContract(expired, order: expired.order).step, isNull);
      },
    );

    test(
      'status 1: « Your order is public », the reference\'s prompt, the bond locked, « Cancel » at once; 2: paused, the same bond and cancel',
      () async {
        final public = await _at([makerOrderJson(0), makerOrderJson(1)]);
        final contract = TradeContract(public, order: public.order);
        expect(public.status, isA<MakerOrderPublic>());
        expect(contract.title, TradeTitle.orderPublic);
        expect(contract.prompt, TradePrompt.publicWait);
        expect(contract.bondLine, TradeBondLine.locked);
        expect(contract.cancel, TradeCancelOffer.immediate);
        expect(contract.maker, isTrue);
        final paused = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(2),
        ]);
        final pausedContract = TradeContract(paused, order: paused.order);
        expect(pausedContract.title, TradeTitle.orderPaused);
        expect(pausedContract.prompt, TradePrompt.paused);
        expect(pausedContract.bondLine, TradeBondLine.locked);
        expect(pausedContract.cancel, TradeCancelOffer.immediate);
      },
    );

    test(
      '« Public orders for … » counts every order of the currency, « Premium rank » the share of the same side below the premium (`Prompts/PublicWait.tsx:52-78`)',
      () async {
        final order = (await _at([makerOrderJson(0), makerOrderJson(1)])).order;
        if (order == null) throw StateError('no order');
        final book = await parseOrders([
          // The maker's own order, in the book: a buy order at 2 %.
          bookOrder(id: tradeOrderId, type: 0),
          bookOrder(id: 1, type: 0, premium: 1),
          bookOrder(id: 2, type: 0, premium: 1.5),
          bookOrder(id: 3, type: 0, premium: 3),
          // A sell order of the same currency: counted, not ranked.
          bookOrder(id: 4, type: 1, premium: -5),
          // Another currency: neither.
          bookOrder(id: 5, type: 0, currency: 1, premium: -9),
        ]);
        final standing = PublicWaitStanding.of(order, book: book);
        expect(standing.similarOrders, 5);
        // 2 of the 4 buy orders in EUR are below 2 %: 50 %.
        expect(standing.premiumRank, 50);
        // At most one such order: the reference's 0.5.
        expect(
          PublicWaitStanding.of(
            order,
            book: await parseOrders([bookOrder(id: tradeOrderId, type: 0)]),
          ).premiumRank,
          0.5,
        );
        expect(PublicWaitStanding.of(order, book: const []).similarOrders, 0);
        // 1 of 3 below: 33.33 %, floored to 33.
        expect(
          PublicWaitStanding.of(
            order,
            book: await parseOrders([
              bookOrder(id: 1, type: 0, premium: 1),
              bookOrder(id: 2, type: 0, premium: 2),
              bookOrder(id: 3, type: 0, premium: 4),
            ]),
          ).premiumRank,
          33,
        );
        // 2 of 3 below: 66.67 %, floored to 66, not rounded.
        expect(
          PublicWaitStanding.of(
            order,
            book: await parseOrders([
              bookOrder(id: 1, type: 0, premium: 1),
              bookOrder(id: 2, type: 0, premium: 1.5),
              bookOrder(id: 3, type: 0, premium: 4),
            ]),
          ).premiumRank,
          66,
        );
      },
    );

    test(
      'the gap in hundredths of a percent, rounded away from zero, exactly none at 0',
      () {
        expect(RateGapLine.hundredthsOf(0), BigInt.zero);
        expect(RateGapLine.hundredthsOf(5.8406), BigInt.from(585));
        expect(RateGapLine.hundredthsOf(-5.8406), BigInt.from(-585));
        expect(RateGapLine.hundredthsOf(2.5), BigInt.from(250));
        expect(RateGapLine.hundredthsOf(0.00001), BigInt.one);
      },
    );
  });

  group('the panels of a maker buyer', () {
    testWidgets(
      'status 1: « Your order is public (2/5) », the reference\'s lines, the figures of the book, « Your maker bond is locked », « Copy URL » and « Cancel »',
      (tester) async {
        final seen = await _at([makerOrderJson(0), makerOrderJson(1)]);
        await _show(
          tester,
          seen,
          book: await parseOrders([
            bookOrder(id: tradeOrderId, type: 0),
            bookOrder(id: 1, type: 0, premium: 1),
            bookOrder(id: 4, type: 1),
          ]),
        );
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        expect(
          find.text(
            'Be patient while robots check the book. This box will ring 🔊 once a robot takes your order, then you will have 3h 0m to reply. If you do not reply, you risk losing your bond.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'If the order expires untaken, your bond will return to you (no action needed).',
          ),
          findsOneWidget,
        );
        expect(find.text('3'), findsOneWidget);
        expect(find.text('Public orders for EUR'), findsOneWidget);
        expect(find.text('Premium rank 50%'), findsOneWidget);
        expect(
          find.text('Among public EUR orders (higher is cheaper)'),
          findsOneWidget,
        );
        expect(find.text('Your maker bond is locked'), findsOneWidget);
        expect(find.text('Your taker bond is locked'), findsNothing);
        await _reveal(tester, find.text('Copy URL'));
        expect(find.text('Copy URL'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        // No pause button in this slice (#184).
        expect(find.text('Pause the public order'), findsNothing);
        _noInternalNames(tester);
      },
    );

    testWidgets('status 1 without a book received: the lines, no figure', (
      tester,
    ) async {
      final seen = await _at([makerOrderJson(0), makerOrderJson(1)]);
      await _show(tester, seen);
      expect(find.text('Your order is public (2/5)'), findsOneWidget);
      expect(find.text('Public orders for EUR'), findsNothing);
      expect(find.textContaining('Premium rank'), findsNothing);
    });

    testWidgets(
      '« Cancel » at 1 cancels at once, with no dialog, for the status shown (`CancelButton.tsx:30`, `:79-80`)',
      (tester) async {
        final seen = await _at([makerOrderJson(0), makerOrderJson(1)]);
        final (asked, _) = await _show(
          tester,
          seen,
          cancel: (seen) async =>
              Ok(CancelDone(_record, seen, makerBondReturned: true)),
        );
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(find.text('Cancel the order?'), findsNothing);
        expect(find.byType(ConfirmCancelDialog), findsNothing);
        expect(asked.cancels, hasLength(1));
        expect(asked.cancels.single.$1.status, same(seen.status));
        expect(asked.cancels.single.$2, isNull);
        await tester.pump(const Duration(seconds: 31));
      },
    );

    testWidgets(
      'a cancel answered with the order unchanged keeps the panel: the screen judges by the status it reads, never by the outcome, and says nothing of a bond returned',
      (tester) async {
        final seen = await _at([makerOrderJson(0), makerOrderJson(1)]);
        final (_, watch) = await _show(
          tester,
          seen,
          cancel: (seen) async =>
              Ok(CancelDone(_record, seen, makerBondReturned: true)),
        );
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump();
        watch.add(TradeScreenStatuses.watched(seen, of: _record));
        await tester.pump();
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        expect(find.textContaining('returned'), findsNothing);
        expect(find.textContaining('Nothing was taken'), findsNothing);
      },
    );

    testWidgets(
      'cancelled at 1: « This order has been cancelled », alone, and never « nothing was taken »',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          const TradeOrderCancelled(),
        ]);
        expect(seen.status, isA<Cancelled>());
        await _show(tester, seen);
        expect(find.text('This order has been cancelled'), findsOneWidget);
        expect(find.textContaining('Nothing was taken'), findsNothing);
        expect(find.textContaining('returned'), findsNothing);
      },
    );

    testWidgets(
      'status 2, paused from another app: « Your order is paused (2/5) », the reference\'s text, unpausing coming later',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(2),
        ]);
        await _show(tester, seen);
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(
          find.text(
            'Your public order has been paused. At the moment it cannot be seen or taken by other robots. You can choose to unpause it at any time.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('"Unpause Order" is coming in a later version.'),
          findsOneWidget,
        );
        expect(find.text('Your maker bond is locked'), findsOneWidget);
      },
    );

    testWidgets(
      'status 5 from 1: « The order has expired », its reason « Expired not taken », no step, no bond line, no cancel',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(5),
        ]);
        await _show(tester, seen);
        expect(find.text('The order has expired'), findsOneWidget);
        expect(find.text('Expired not taken'), findsOneWidget);
        expect(find.textContaining('bond is'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
      },
    );

    testWidgets('status 5 from 0: the reason « Maker bond not locked »', (
      tester,
    ) async {
      final seen = await _at([
        makerOrderJson(0),
        makerOrderJson(
          5,
          changes: {
            'expiry_reason': 1,
            'expiry_message': 'Maker bond not locked',
          },
        ),
      ]);
      await _show(tester, seen);
      expect(find.text('The order has expired'), findsOneWidget);
      expect(find.text('Maker bond not locked'), findsOneWidget);
    });

    testWidgets(
      'status 6, taken: « Submit payout info (3/5) », the maker\'s bond line, the gap before « Submit » in the warning colour, « Cancel » with the bond at risk',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: _lowSats),
        ]);
        final status = seen.status;
        expect(status, isA<WaitingForBoth>());
        final gap = (status as WaitingForBoth).rateGap;
        expect(gap?.effectFor(TradeRole.buyer), RateGapEffect.unfavourable);
        final (asked, _) = await _show(tester, seen);
        expect(find.textContaining('(3/5)'), findsOneWidget);
        expect(find.text('Your maker bond is locked'), findsOneWidget);
        expect(
          find.text(
            'Temple of Sats fixed 101,000 sats for 100 EUR when your order was taken: a rate of 99,010 EUR/BTC, +5.85% from the rate when you made it (93,545).',
          ),
          findsOneWidget,
        );
        final line = tester.widget<RateGapLine>(find.byType(RateGapLine));
        expect(line.role, TradeRole.buyer);
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(ConfirmCancelDialog), findsOneWidget);
        expect(asked.cancels, isEmpty);
      },
    );

    testWidgets(
      'a gap in the maker buyer\'s favour is said in the text colour, never as a warning',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: 110000),
        ]);
        await _show(tester, seen);
        expect(find.textContaining('-2.82% from the rate'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(RateGapLine),
            matching: find.byIcon(Icons.info_outline),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'status 7: « Your info looks good! (3/5) », « Cancel » at risk',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
          makerOrderJson(7),
        ]);
        await _show(tester, seen);
        expect(find.textContaining('(3/5)'), findsOneWidget);
        await _reveal(tester, find.text('Cancel'));
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Your maker bond is locked'), findsOneWidget);
      },
    );

    testWidgets(
      'status 9: « (4/5) », and « Confirm … sent » says the gap in its dialog before « Confirm »',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: _lowSats),
          makerOrderJson(8, last: _lowSats),
          makerOrderJson(9, last: _lowSats),
        ]);
        expect(seen.status, isA<Chatting>());
        final (asked, _) = await _show(tester, seen);
        expect(find.textContaining('(4/5)'), findsOneWidget);
        final confirm = find.textContaining('Confirm 100 EUR sent');
        await _reveal(tester, confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ConfirmFiatSentDialog),
            matching: find.textContaining('+5.85% from the rate'),
          ),
          findsOneWidget,
        );
        expect(asked.fiatSent, isEmpty);
      },
    );

    testWidgets('status 10: « (5/5) »', (tester) async {
      final seen = await _at([
        makerOrderJson(0),
        makerOrderJson(1),
        makerOrderJson(6),
        makerOrderJson(8),
        makerOrderJson(9),
        makerOrderJson(10),
      ]);
      await _show(tester, seen);
      expect(find.textContaining('(5/5)'), findsOneWidget);
    });

    testWidgets(
      '17 is a maker\'s loss, 18 its win (`TradeBox/index.tsx:703-717`)',
      (tester) async {
        final before = [
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
          makerOrderJson(8),
          makerOrderJson(9),
          makerOrderJson(11),
          makerOrderJson(16),
        ];
        final lost = await _at([...before, makerOrderJson(17)]);
        expect(lost.status, isA<DisputeLost>());
        await _show(tester, lost);
        expect(find.text('You have lost the dispute'), findsOneWidget);
        expect(find.text('Your maker bond is settled'), findsOneWidget);
        final won = await _at([...before, makerOrderJson(18)]);
        expect(won.status, isA<DisputeWon>());
        await _show(tester, won);
        expect(find.text('You have won the dispute'), findsOneWidget);
      },
    );

    testWidgets(
      'back in the book after a taker\'s default: the order public again, its maker bond still locked; then a next contract taken by another robot, with its own gap',
      (tester) async {
        final chain = await _chain([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
          makerOrderJson(1),
          makerOrderJson(6, taker: third, deadline: deadline1, last: _lowSats),
        ]);
        final back = chain[3];
        expect(back.status, isA<MakerOrderPublic>());
        expect((back.status as MakerOrderPublic).backInBook, isTrue);
        await _show(tester, back);
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        expect(find.text('Your maker bond is locked'), findsOneWidget);
        final next = chain[4];
        expect(next.status.trail.take, 1);
        expect(next.status.warnings, isEmpty);
        await _show(tester, next);
        expect(find.textContaining('(3/5)'), findsOneWidget);
        expect(find.textContaining('+5.85% from the rate'), findsOneWidget);
      },
    );

    testWidgets(
      'a next contract seen late: its own words, in the text colour, not « Unexpected change »',
      (tester) async {
        // Back in the book after contract 0, then read in the chat with another taker: the order was taken again unseen.
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
          makerOrderJson(1),
          makerOrderJson(9, taker: third),
        ]);
        expect(seen.status.has<ContractSeenLate>(), isTrue);
        await _show(tester, seen);
        expect(
          find.text(
            'Your order was taken again and this trade moved on without Bull Market seeing its steps, as when your Garage Key is used in another app. Check the trade in that app before acting here.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Unexpected change on the coordinator\'s side.'),
          findsNothing,
        );
        // Information, in the text colour with the info icon, not an alert.
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
        expect(find.byIcon(Icons.info_outline), findsOneWidget);
        // Nothing to pay from this wallet at 9 and after, so nothing offered that the warning would refuse.
        expect(find.text('Pay with this wallet'), findsNothing);
      },
    );

    testWidgets(
      'the « Order » tab of a maker buyer: « You send via … » the fiat and « You receive … » the sats, with the maker fee (`OrderDetails/index.tsx:193-229`)',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
        ]);
        await _show(tester, seen);
        await tester.tap(find.text('Order').last);
        await tester.pump();
        expect(find.text('You send via Revolut Instant SEPA'), findsOneWidget);
        expect(find.text('You receive Lightning'), findsNothing);
        expect(find.textContaining('You receive'), findsOneWidget);
        // The payout the coordinator gives (`invoice_amount`): the sats less the maker fee.
        expect(makerPayoutOf(makerSats), 106873);
        expect(
          find.textContaining('106,873', findRichText: true),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'the « Order » tab before the sats are fixed: the reference\'s estimate with the maker fee, not the taker\'s (`OrderDetails/index.tsx:194-196`)',
      (tester) async {
        final seen = await _at([makerOrderJson(0), makerOrderJson(1)]);
        final order = seen.order;
        if (order == null) throw StateError('no order');
        // temple announces a maker fee of 0.025 % and a taker fee of 0.175 %.
        final info = await tester.runAsync(
          () => infoAt('temple', makerFee: 0.00025),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: ListView(
                children: [
                  TradeOrderDetails(order: order, now: tradeNow, info: info),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        // 106,900 sats × (1 + 0.025 %) × (1 − 0.1 % of routing budget).
        expect(find.textContaining('106,820'), findsOneWidget);
        expect(find.textContaining('106,980'), findsNothing);
      },
    );

    testWidgets('the French texts of the maker\'s panels', (tester) async {
      final public = await _at([makerOrderJson(0), makerOrderJson(1)]);
      await _show(
        tester,
        public,
        locale: const Locale('fr'),
        book: await parseOrders([bookOrder(id: tradeOrderId, type: 0)]),
      );
      expect(find.text('Votre ordre est public (2/5)'), findsOneWidget);
      expect(
        find.text(
          'Si l’ordre expire sans être pris, votre caution vous sera rendue (aucune action nécessaire).',
        ),
        findsOneWidget,
      );
      expect(find.text('Ordres publics pour EUR'), findsOneWidget);
      expect(find.text('Classement de prime 0,5 %'), findsOneWidget);
      expect(
        find.text('Votre caution de créateur est bloquée'),
        findsOneWidget,
      );
      final taken = await _at([
        makerOrderJson(0),
        makerOrderJson(1),
        makerOrderJson(6, last: _lowSats),
      ]);
      await _show(tester, taken, locale: const Locale('fr'));
      expect(find.textContaining('a fixé 101'), findsOneWidget);
      expect(
        find.textContaining('par rapport au taux à sa création'),
        findsOneWidget,
      );
      _noInternalNames(tester);
    });
  });

  group('the owner\'s payment rule on a maker buyer\'s side (#182, design note § 3.3)', () {
    /// The rule's cubit over the terms of the tests, the Bull wallet's price being [wallet] at each read, its reads counted in [reads].
    PayoutRateCubit rateOf(
      P2pWalletBitcoinRate Function() wallet, {
      List<TradeSeen>? reads,
    }) {
      final maker = switch (madeTerms().side) {
        MadeSide(:final maker) => maker,
      };
      final cubit = PayoutRateCubit(_record, (record, seen) async {
        reads?.add(seen);
        final contract = CheckPayoutRateUsecase.contractOf(seen);
        if (contract == null) return null;
        return WalletRateCheck.ofMakerPayout(
          maker,
          amount: maker.contractAmount(contract.rangeAmount) ??
              (throw StateError('no amount')),
          received: contract.received,
          wallet: wallet(),
        );
      });
      addTearDown(cubit.close);
      return cubit;
    }

    // At the creation's price the contract of 90,000 sats gives the buyer 89,978 sats, where 100 EUR are worth 106,899.996 at the Bull wallet's 91,711.15 EUR/BTC with +2 %: more than 10 % fewer.
    final atWallet = P2pWalletRateRead(91711.15);

    testWidgets(
      'at 6, more than 10 % fewer sats: the line and the red warning with both amounts before « Submit », read once',
      (tester) async {
        final reads = <TradeSeen>[];
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: 90000),
        ]);
        await _show(tester, seen, rate: rateOf(() => atWallet, reads: reads));
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining(
            'At the Bull wallet\'s price, 91,711 EUR/BTC, with the order\'s premium, 100 EUR are worth 106,899 sats. You receive 89,978 sats: gap -15.83%.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'You receive more than 10% fewer sats than that: 89,978 sats received, 106,899 sats expected. Check it before going on.',
          ),
          findsOneWidget,
        );
        expect(reads, hasLength(1));
      },
    );

    testWidgets('within 10 %: the line alone, no warning', (tester) async {
      final seen = await _at([
        makerOrderJson(0),
        makerOrderJson(1),
        makerOrderJson(6),
      ]);
      await _show(tester, seen, rate: rateOf(() => atWallet));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('At the Bull wallet\'s price'), findsOneWidget);
      expect(find.textContaining('fewer sats than that'), findsNothing);
    });

    testWidgets(
      'a currency the Bull wallet does not price: one line, no figure, no « Retry »',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
        ]);
        await _show(
          tester,
          seen,
          rate: rateOf(() => const P2pWalletRateNotPriced()),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'The Bull wallet has no price for EUR: rate not checked. You are trusting Temple of Sats\'s price: check it yourself before going on.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsNothing);
      },
    );

    testWidgets(
      'a price that could not be read: « rate not checked », « Retry » reads it again',
      (tester) async {
        var wallet = const P2pWalletRateUnavailable() as P2pWalletBitcoinRate;
        final reads = <TradeSeen>[];
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: 90000),
        ]);
        await _show(tester, seen, rate: rateOf(() => wallet, reads: reads));
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'The Bull wallet\'s price of a bitcoin in EUR could not be read: rate not checked. You can try again, or go on without the check.',
          ),
          findsOneWidget,
        );
        wallet = atWallet;
        await _reveal(tester, find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump();
        expect(reads, hasLength(2));
        expect(find.textContaining('fewer sats than that'), findsOneWidget);
      },
    );

    testWidgets(
      'at 9, the red warning in « Confirm … sent », and « Confirm » still sends',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6, last: 90000),
          makerOrderJson(8, last: 90000),
          makerOrderJson(9, last: 90000),
        ]);
        final (asked, _) = await _show(
          tester,
          seen,
          rate: rateOf(() => atWallet),
        );
        await tester.pump();
        await tester.pump();
        // Before the chat step too, with its « Retry » when it has one.
        expect(find.textContaining('fewer sats than that'), findsOneWidget);
        final confirm = find.textContaining('Confirm 100 EUR sent');
        await _reveal(tester, confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ConfirmFiatSentDialog),
            matching: find.textContaining('fewer sats than that'),
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmFiatSentDialog),
            matching: find.text('Confirm'),
          ),
        );
        await tester.pump();
        expect(asked.fiatSent, hasLength(1));
        await tester.pump(const Duration(seconds: 31));
      },
    );

    testWidgets(
      'an order made here whose coordinator contradicted the trade: what to do',
      (tester) async {
        final seen = await _at([
          makerOrderJson(0),
          makerOrderJson(1),
          makerOrderJson(6),
          // Another taker under the same deadline: a breach.
          makerOrderJson(7, taker: third),
        ]);
        expect(seen.status.trail.breached, isTrue);
        await _show(tester, seen);
        expect(
          find.text(
            'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact Temple of Sats if something looks wrong.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('captures (with P2P_CAPTURE_DIR)', () {
    setUpAll(loadCaptureFonts);
    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets(
        'the maker\'s panels in ${locale.languageCode}',
        skip: captureDirectory == null,
        (tester) async {
          final code = locale.languageCode;
          final book = await tester.runAsync(
            () => parseOrders([
              bookOrder(id: tradeOrderId, type: 0),
              bookOrder(id: 1, type: 0, premium: 1),
              bookOrder(id: 2, type: 0, premium: 3),
              bookOrder(id: 4, type: 1),
            ]),
          );
          Future<void> shoot(
            String name,
            List<Object> answers, {
            List<PublicOrder>? withBook,
            P2pWalletBitcoinRate? wallet,
          }) async {
            final seen = await tester.runAsync(() => _at(answers));
            if (seen == null) throw StateError(name);
            final maker = switch (madeTerms().side) {
              MadeSide(:final maker) => maker,
            };
            final rate = wallet == null
                ? null
                : PayoutRateCubit(_record, (record, seen) async {
                    final contract = CheckPayoutRateUsecase.contractOf(seen);
                    if (contract == null) return null;
                    return WalletRateCheck.ofMakerPayout(
                      maker,
                      amount:
                          maker.contractAmount(contract.rangeAmount) ??
                          (throw StateError('no amount')),
                      received: contract.received,
                      wallet: wallet,
                    );
                  });
            if (rate != null) addTearDown(rate.close);
            await _show(
              tester,
              seen,
              locale: locale,
              book: withBook,
              rate: rate,
            );
            await tester.pump();
            await tester.pump();
            await capture(tester, '$code-createur-$name');
          }

          await shoot('public', [
            makerOrderJson(0),
            makerOrderJson(1),
          ], withBook: book);
          await shoot('public-sans-carnet', [
            makerOrderJson(0),
            makerOrderJson(1),
          ]);
          await shoot('pause', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(2),
          ]);
          await shoot('expire-0', [
            makerOrderJson(0),
            makerOrderJson(
              5,
              changes: {
                'expiry_reason': 1,
                'expiry_message': 'Maker bond not locked',
              },
            ),
          ]);
          await shoot('expire-1', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(5),
          ]);
          await shoot('annule', [
            makerOrderJson(0),
            makerOrderJson(1),
            const TradeOrderCancelled(),
          ]);
          await shoot('6-ecart', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6, last: _lowSats),
          ]);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pNavOrder).last,
          );
          await tester.pump();
          await capture(tester, '$code-createur-6-onglet-ordre');
          await shoot('6-ecart-favorable', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6, last: 110000),
          ]);
          await shoot('7', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(7),
          ]);
          await shoot('retour-carnet', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(1),
          ]);
          await shoot('nouveau-contrat', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(1),
            makerOrderJson(
              6,
              taker: third,
              deadline: deadline1,
              last: _lowSats,
            ),
          ]);
          await shoot('contrat-vu-tard', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(1),
            makerOrderJson(9, taker: third),
          ]);
          await shoot('9', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6, last: _lowSats),
            makerOrderJson(8, last: _lowSats),
            makerOrderJson(9, last: _lowSats),
          ]);
          final confirm = find.text(
            lookupP2pLocalizations(locale).p2pEndConfirmSent('100', 'EUR'),
          );
          if (confirm.evaluate().isNotEmpty) {
            await tester.ensureVisible(confirm.last);
            await tester.pump();
            await tester.tap(confirm.last);
            await tester.pumpAndSettle();
            final dialog = find.byType(ConfirmFiatSentDialog);
            if (dialog.evaluate().isNotEmpty) {
              await capture(tester, '$code-createur-9-dialogue-ecart');
              Navigator.of(tester.element(dialog)).pop(false);
              await tester.pumpAndSettle();
            }
          }
          // The owner's payment rule on the buyer's side (#182): red, within, not priced, not read; and in « Confirm … sent ».
          final low = [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6, last: 90000),
          ];
          await shoot(
            '6-regle-rouge',
            low,
            wallet: P2pWalletRateRead(91711.15),
          );
          await shoot('6-regle-info', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
          ], wallet: P2pWalletRateRead(91711.15));
          await shoot(
            '6-regle-non-cote',
            low,
            wallet: const P2pWalletRateNotPriced(),
          );
          await shoot(
            '6-regle-illisible',
            low,
            wallet: const P2pWalletRateUnavailable(),
          );
          await shoot('9-regle', [
            ...low,
            makerOrderJson(8, last: 90000),
            makerOrderJson(9, last: 90000),
          ], wallet: P2pWalletRateRead(91711.15));
          final confirmRule = find.text(
            lookupP2pLocalizations(locale).p2pEndConfirmSent('100', 'EUR'),
          );
          if (confirmRule.evaluate().isNotEmpty) {
            await tester.ensureVisible(confirmRule.last);
            await tester.pump();
            await tester.tap(confirmRule.last);
            await tester.pumpAndSettle();
            final dialog = find.byType(ConfirmFiatSentDialog);
            if (dialog.evaluate().isNotEmpty) {
              await capture(tester, '$code-createur-9-dialogue-regle');
              Navigator.of(tester.element(dialog)).pop(false);
              await tester.pumpAndSettle();
            }
          }
          await shoot('rupture', [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(7, taker: third),
          ]);
          final before = [
            makerOrderJson(0),
            makerOrderJson(1),
            makerOrderJson(6),
            makerOrderJson(8),
            makerOrderJson(9),
            makerOrderJson(11),
            makerOrderJson(16),
          ];
          await shoot('17', [...before, makerOrderJson(17)]);
          await shoot('18', [...before, makerOrderJson(18)]);
        },
      );
    }
  });
}
