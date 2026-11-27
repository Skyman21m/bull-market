import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/trade/wallet_payment_section.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, bookOrder, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/prepared_takes.dart';
import 'support/trade_screens.dart';

/// The watch of the trade, played by the test: what it emits, and what the screen tells it.
final class _Watch {
  final _states = StreamController<TradeWatchState>.broadcast();
  final List<TradeWatchSignal> signals = [];
  final List<bool> startedOnScreen = [];
  int listens = 0;
  int open = 0;

  Stream<TradeWatchState> call(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    startedOnScreen.add(onScreen);
    late final StreamSubscription<TradeWatchSignal> told;
    late final StreamController<TradeWatchState> out;
    StreamSubscription<TradeWatchState>? forwarded;
    out = StreamController(
      onListen: () {
        listens++;
        open++;
        told = signals.listen(this.signals.add);
        forwarded = _states.stream.listen(out.add);
      },
      onCancel: () async {
        open--;
        await told.cancel();
        await forwarded?.cancel();
      },
    );
    return out.stream;
  }

  void emit(TradeWatchState state) => _states.add(state);
}

/// The cancels the screen asks for, answered as the test says.
final class _Cancels {
  final List<(TradeSeen, BondLossAcknowledged?)> asked = [];
  Result<CancelOutcome, CancelRefusal> Function(TradeSeen seen)? answer;

  /// What the cancel waits for before it answers, when given.
  Future<void>? gate;

  Future<Result<CancelOutcome, CancelRefusal>> call(
    TradeRecord record,
    TradeSeen seen, {
    BondLossAcknowledged? bondLoss,
  }) async {
    asked.add((seen, bondLoss));
    if (gate case final gate?) await gate;
    return (answer ?? (seen) => Ok(CancelDone(record, seen)))(seen);
  }
}

late TradeScreenStatuses _statuses;
late TradeScreenStatuses _wrongNetwork;
late TradeScreenStatuses _wrongAmount;
late TradeScreenStatuses _expiredInvoice;
late Map<String, TradeSeen> _seen;

final _record = TradeScreenStatuses.record;

/// The book's order 42 of the tests, of 150 EUR, as the robot that takes it reads it (#119).
late PreparedTake _prepared;

/// A take cubit whose take the test never expects.
TakeOrderCubit _neverTaken(PublicOrder order) => TakeOrderCubit(
  order,
  RobosatsNetwork.mainnet,
  TakeCalls(
    prepare: (shown, {required network, amount, onStep, garageRobot}) =>
        throw StateError('not prepared'),
    confirm: (prepared, {password, onStep}) => throw StateError('not taken'),
    abandon: (prepared) {},
    abandonOrder: (shown, {required network}) {},
  ),
  (network) async => const Ok(true),
);

/// What temple says of itself on mainnet, its fees included.
Map<String, Object?> _templeInfo() =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// Shows the trade screen over [watch] and [cancels], with [state] emitted once it listens; the order's side reads [transport] (nothing answers by default), and an order public again is taken with [takeCubitFor], its trade given to [taken].
Future<TradeCubit> _show(
  WidgetTester tester, {
  required _Watch watch,
  _Cancels? cancels,
  TradeWatchState? state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  WalletPaymentBuilder? walletPayment,
  PayoutPanelBuilder? payout,
  bool moneyActionRunning = false,
  bool tickerEnabled = true,
  FakeTransport? transport,
  TakeOrderCubit Function(PublicOrder order)? takeCubitFor,
  List<TradeRecord>? taken,
  DateTime Function()? now,
  TradeLastStored? lastStored,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = TradeCubit(
    _record,
    watch.call,
    (cancels ?? _Cancels()).call,
    lastStored: lastStored,
  )..start();
  addTearDown(cubit.close);
  final reads = transport ?? FakeTransport();
  final page = TradeOrderPageCubit(
    coordinator('temple'),
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
    FindPublicOrderUsecase(
      CoordinatorClient(reads, clock: () => testNow),
    ).execute,
  );
  addTearDown(page.close);
  unawaited(page.loadInfo());
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
      home: TickerMode(
        enabled: tickerEnabled,
        child: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: page),
            ],
            child: TradeScreen(
              now: now ?? () => tradeNow,
              coordinatorDetails: (_) => throw StateError('not opened'),
              walletPayment: walletPayment,
              payout: payout,
              moneyActionRunning: (_) => moneyActionRunning,
              takeCubitFor: takeCubitFor,
              onTaken: taken?.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (state != null) {
    watch.emit(state);
    await tester.pump();
    await tester.pump();
  }
  return cubit;
}

TradeWatchStatus _watched(String name, {int failedReads = 0}) =>
    TradeScreenStatuses.watched(
      _seen[name] ?? (throw StateError(name)),
      failedReads: failedReads,
    );

/// Scrolls [finder] into view, and lays the screen out again so that a tap finds it where it is.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Every paragraph on the screen, laid out without being cut.
void _expectNothingCut(WidgetTester tester, String reason) {
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

void main() {
  setUpAll(() async {
    _prepared = await preparedTake(changes: {'amount': '150.00000000'});
    _statuses = await TradeScreenStatuses.make();
    _wrongNetwork = await TradeScreenStatuses.make(
      invoice: bondInvoice(network: Bolt11Network.testnet),
    );
    _wrongAmount = await TradeScreenStatuses.make(
      invoice: bondInvoice(sats: bookBond + 1),
      bondSatoshis: bookBond,
    );
    _expiredInvoice = await TradeScreenStatuses.make(
      invoice: bondInvoice(age: const Duration(minutes: 10)),
    );
    _seen = {
      'bondExpiredInvoice': await _expiredInvoice.bondStep(),
      'bond': await _statuses.bondStep(),
      'bondWrongNetwork': await _wrongNetwork.bondStep(),
      'bondWrongAmount': await _wrongAmount.bondStep(),
      'six': await _statuses.waitingForBoth(),
      'seven': await _statuses.waitingForEscrow(),
      'eight': await _statuses.waitingForPayout(),
      'nine': await _statuses.chatting(),
      'expired': await _statuses.expired(),
      'cancelled': await _statuses.cancelled(),
      'cancelledBondLost': await _statuses.cancelled(bondLost: true),
      'preTakeUnavailable': await _statuses.preTakeUnavailable(),
      'takenByAnother': await _statuses.takenByAnother(),
      'publicAgain': await _statuses.publicAgain(),
      'bondForfeited': await _statuses.bondForfeited(),
      'pending': _statuses.pending(),
      'swapBond': await _statuses.read(
        await _statuses.bondStep(),
        orderJson(3, bond: _statuses.invoice, changes: {'currency': 1000}),
      ),
      'sixCents': await _statuses.read(
        await _statuses.bondStep(),
        orderJson(6, changes: {'amount': '123.45000000'}),
      ),
      'sixSwap': await _statuses.read(
        await _statuses.bondStep(),
        orderJson(6, changes: {'currency': 1000, 'amount': '0.00100000'}),
      ),
      'sixRegressed': await _statuses.refusedRead(
        await _statuses.waitingForBoth(),
        orderJson(3, bond: _statuses.invoice),
      ),
    };
  });

  test('the statuses are those the state machine gives', () {
    expect(_seen['bond']?.status, isA<WaitingForTakerBond>());
    expect(_seen['bondWrongNetwork']?.status.invoice, isA<UnusableInvoice>());
    expect(_seen['six']?.status, isA<WaitingForBoth>());
    expect(_seen['seven']?.status, isA<WaitingForEscrow>());
    expect(_seen['eight']?.status, isA<WaitingForPayout>());
    expect(_seen['nine']?.status, isA<Chatting>());
    expect(_seen['expired']?.status, isA<Expired>());
    expect(_seen['cancelled']?.status, isA<Cancelled>());
    expect(
      (_seen['cancelledBondLost']?.status as Cancelled).bondMayHaveBeenLost,
      isTrue,
    );
    expect(_seen['preTakeUnavailable']?.status, isA<PreTakeUnavailable>());
    expect(_seen['takenByAnother']?.status, isA<TakenByAnother>());
    expect(_seen['publicAgain']?.status, isA<PreTakeEnded>());
    expect(_seen['bondForfeited']?.status, isA<BondForfeited>());
    expect(_seen['pending']?.status, isA<StatusUnknown>());
  });

  test(
    'an invoice the read found expired stays hidden, « Show anyway » or not, even on a clock before its end',
    () {
      final invoice =
          _seen['bondExpiredInvoice']?.status.invoice ??
          (throw StateError('no invoice'));
      for (final shownAnyway in [false, true]) {
        expect(
          invoiceDisplayOf(
            invoice,
            shownAnyway: shownAnyway,
            now: DateTime.utc(2000),
          ),
          InvoiceDisplay.hidden,
        );
      }
    },
  );

  group('status 3, the bond', () {
    testWidgets('an order in bitcoin: « SWAPPING INTO Lightning »', (
      tester,
    ) async {
      await _show(tester, watch: _Watch(), state: _watched('swapBond'));
      expect(find.text('SWAPPING INTO Lightning'), findsOneWidget);
      expect(find.text('You are BUYING BTC'), findsNothing);
    });

    testWidgets(
      '« Copy URL » copies the order\'s address and says « Copied! »',
      (tester) async {
        final copied = <String?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String?);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await _show(tester, watch: _Watch(), state: _watched('bond'));
        await _reveal(tester, find.text('Copy URL'));
        await tester.tap(find.text('Copy URL'));
        await tester.pump();
        expect(copied, [
          '${_record.coordinatorOnion}/order/temple/$tradeOrderId',
        ]);
        expect(find.text('Copied!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        expect(find.text('Copy URL'), findsOneWidget);
      },
    );

    testWidgets('the reference\'s contract with the QR code and the facts', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _show(tester, watch: _Watch(), state: _watched('bond'));

      expect(find.text('Lock 3,207 Sats to TAKE order (1/4)'), findsOneWidget);
      expect(find.text('You are BUYING BTC'), findsOneWidget);
      expect(find.text('Pay with another wallet'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(QrImageView)),
        isSemantics(label: 'QR code of the bond invoice', isImage: true),
      );
      expect(find.text('3,207 Sats'), findsWidgets);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('Copy to clipboard'), findsOneWidget);
      expect(
        find.text(
          'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.',
        ),
        findsOneWidget,
      );
      // No bond line at 3, « Copy URL » and « Cancel » under the contract.
      expect(find.textContaining('Your taker bond'), findsNothing);
      await _reveal(tester, find.text('Cancel'));
      expect(find.text('Copy URL'), findsOneWidget);
      expect(find.byTooltip('Cancel order'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('« Copy to clipboard » copies the invoice decoded', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _show(tester, watch: _Watch(), state: _watched('bond'));
      await _reveal(tester, find.text('Copy to clipboard'));
      await tester.tap(find.text('Copy to clipboard'));
      await tester.pump();
      expect(copied, [_statuses.invoice.text]);
      expect(find.text('Copied!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Copy to clipboard'), findsOneWidget);
    });

    testWidgets(
      'an invoice for another network: no QR code, no copy, the warning',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('bondWrongNetwork'),
        );

        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Copy to clipboard'), findsNothing);
        expect(find.text('Show anyway'), findsNothing);
        expect(
          find.text(
            'The invoice Temple of Sats sent is for another network. It is not shown.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('an amount that differs: hidden behind « Show anyway »', (
      tester,
    ) async {
      await _show(tester, watch: _Watch(), state: _watched('bondWrongAmount'));

      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(
        find.text('The invoice amount is not the amount the order asks for.'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Show anyway'));
      await tester.tap(find.text('Show anyway'));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Copy to clipboard'), findsOneWidget);
    });

    testWidgets('an expired invoice: no QR code, no copy, no « Show anyway »', (
      tester,
    ) async {
      await _show(
        tester,
        watch: _Watch(),
        state: _watched('bondExpiredInvoice'),
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(find.text('Show anyway'), findsNothing);
      expect(find.text('This invoice has expired.'), findsOneWidget);
    });

    testWidgets('« Pay with another wallet » closes and opens', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('bond'));
      await tester.tap(find.text('Pay with another wallet'));
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.text('Pay with another wallet'));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
      'the wallet slot: given the status and the bond, other wallet closed when it offers something',
      (tester) async {
        final requests = <WalletPaymentRequest>[];
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('bond'),
          walletPayment: (context, request) {
            requests.add(request);
            return const WalletPaymentSlot(Text('wallet slot'));
          },
        );
        expect(find.text('wallet slot'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
        expect(requests.last.amount, Sats(BigInt.from(bookBond)));
        expect(requests.last.status, same(_seen['bond']?.status));
        expect(requests.last.record, _record);
      },
    );

    testWidgets('a wallet slot with nothing to offer: other wallet open', (
      tester,
    ) async {
      await _show(
        tester,
        watch: _Watch(),
        state: _watched('bond'),
        walletPayment: (context, request) => null,
      );
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('« See Compatible Wallets » shows the link, never opens it', (
      tester,
    ) async {
      await _show(tester, watch: _Watch(), state: _watched('bond'));
      await tester.tap(find.text('See Compatible Wallets'));
      await settle(tester);
      expect(
        find.text('https://learn.robosats.org/docs/wallets/'),
        findsOneWidget,
      );
    });

    testWidgets(
      'the « Order » tab: the order with « Expires in » and « Deposit »',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('bond'),
          transport: FakeTransport(infos: {'temple': _templeInfo()}),
        );
        await settle(tester);
        await tester.tap(find.text('Order').last);
        await tester.pump();
        expect(find.text('Order host'), findsOneWidget);
        expect(find.text('Expires in'), findsOneWidget);
        expect(find.text('Deposit'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
        // The coordinator's fees, the reference's estimate with its taker fee while the coordinator gives no sats yet, and the maker.
        expect(find.text('M 0.025%'), findsOneWidget);
        expect(find.text('T 0.175%'), findsOneWidget);
        expect(find.text('You receive'), findsOneWidget);
        expect(find.textContaining('111,304'), findsOneWidget);
        await _reveal(tester, find.textContaining('Order maker'));
        expect(find.text('Order maker · Active'), findsOneWidget);
      },
    );
  });

  group('cancel', () {
    testWidgets('a double tap on « Cancel » opens one dialog', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('bond'));
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.tap(find.text('Cancel'), warnIfMissed: false);
      await settle(tester);
      expect(find.text('Cancel the order?'), findsOneWidget);
      // One « Back » closes it: no second dialog was waiting under it.
      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(find.text('Cancel the order?'), findsNothing);
    });

    testWidgets(
      'the status moves from 3 to 6 while the free dialog is open: the cancel is the one of 3, never an agreement for 6',
      (tester) async {
        final watch = _Watch();
        final cancels = _Cancels();
        await _show(
          tester,
          watch: watch,
          cancels: cancels,
          state: _watched('bond'),
        );
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        watch.emit(_watched('six'));
        await tester.pump();
        await tester.pump();
        // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Confirm cancellation'));
        await settle(tester);
        final (seen, bondLoss) = cancels.asked.single;
        expect(seen, same(_seen['bond']));
        expect(bondLoss, isNull);
      },
    );

    testWidgets(
      'at 6 and 7, « Go back » is the filled button and « Confirm Cancel » the outlined one, in the reference\'s order',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('six'));
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        final back = tester.widget<TradeButton>(
          find.widgetWithText(TradeButton, 'Go back'),
        );
        final go = tester.widget<TradeButton>(
          find.widgetWithText(TradeButton, 'Confirm Cancel'),
        );
        expect(back.outlined, isFalse);
        expect(go.outlined, isTrue);
        expect(
          tester.getTopLeft(find.text('Go back')).dy,
          lessThan(tester.getTopLeft(find.text('Confirm Cancel')).dy),
        );
      },
    );

    testWidgets(
      'at 3: « Back » sends nothing, « Confirm cancellation » one free cancel',
      (tester) async {
        final cancels = _Cancels();
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('bond'),
        );
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.text('Cancel the order?'), findsOneWidget);
        expect(
          find.text(
            'If the order is cancelled now but you already tried to pay the invoice, you might lose your bond.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Back'));
        await settle(tester);
        expect(cancels.asked, isEmpty);

        await tester.tap(find.text('Cancel'));
        await settle(tester);
        // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Confirm cancellation'));
        await settle(tester);
        expect(cancels.asked, hasLength(1));
        expect(cancels.asked.single.$1, same(_seen['bond']));
        expect(cancels.asked.single.$2, isNull);
      },
    );

    for (final name in ['six', 'seven']) {
      testWidgets(
        'at ${name == 'six' ? 6 : 7}: « Go back » and a tap outside send nothing, « Confirm Cancel » sends the acknowledgement',
        (tester) async {
          final cancels = _Cancels();
          await _show(
            tester,
            watch: _Watch(),
            cancels: cancels,
            state: _watched(name),
          );
          expect(
            find.byTooltip('Unilateral cancelation (bond at risk!)'),
            findsOneWidget,
          );
          await _reveal(tester, find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await settle(tester);
          expect(
            find.text('If the order is cancelled now you will lose your bond.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Go back'));
          await settle(tester);
          await tester.tap(find.text('Cancel'));
          await settle(tester);
          await tester.tapAt(const Offset(5, 5));
          await settle(tester);
          expect(find.text('Confirm Cancel'), findsNothing);
          expect(cancels.asked, isEmpty);

          await tester.tap(find.text('Cancel'));
          await settle(tester);
          // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tap(find.text('Confirm Cancel'));
          await settle(tester);
          expect(cancels.asked, hasLength(1));
          expect(cancels.asked.single.$1, same(_seen[name]));
          expect(cancels.asked.single.$2, isA<BondLossAcknowledged>());
          // Bound to this trade and the status the dialog was opened for.
          expect(
            cancels.asked.single.$2?.covers(
              _record,
              _seen[name] ?? (throw StateError(name)),
            ),
            isTrue,
          );
        },
      );
    }

    testWidgets('a cancel refused: its text under the button', (tester) async {
      final cancels = _Cancels()
        ..answer = (_) => const Err(CancelNotPossible());
      await _show(
        tester,
        watch: _Watch(),
        cancels: cancels,
        state: _watched('bond'),
      );
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(find.text('Confirm cancellation'));
      await settle(tester);
      expect(find.text('You cannot cancel this order'), findsOneWidget);
    });

    testWidgets('a cancel whose outcome is unknown says so', (tester) async {
      final cancels = _Cancels()
        ..answer = (seen) => Ok(CancelOutcomeUnknown(_record, seen));
      await _show(
        tester,
        watch: _Watch(),
        cancels: cancels,
        state: _watched('bond'),
      );
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(find.text('Confirm cancellation'));
      await settle(tester);
      expect(
        find.text(
          'Bull Market does not know yet whether the cancel went through. It keeps checking.',
        ),
        findsOneWidget,
      );
    });
  });

  group('statuses 6 to 9', () {
    testWidgets(
      '6: payout info and the bond locked; the form only from the payout panel given (#91)',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('six'));
        expect(find.text('Submit payout info (2/4)'), findsOneWidget);
        expect(
          find.text(
            'Before letting you send 100 EUR, we want to make sure you are able to receive the BTC.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('later version'), findsNothing);
        expect(find.byKey(const ValueKey('payout panel')), findsNothing);
        expect(find.text('Your taker bond is locked'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
      },
    );

    testWidgets(
      'the payout panel under the prompt at 6 and 8, given the shown status, stored; none at 7 and 9',
      (tester) async {
        final requests = <PayoutPanelRequest>[];
        Widget panel(BuildContext context, PayoutPanelRequest request) {
          requests.add(request);
          return const SizedBox(key: ValueKey('payout panel'), height: 10);
        }

        for (final (name, shown) in [
          ('six', true),
          ('eight', true),
          ('seven', false),
          ('nine', false),
        ]) {
          requests.clear();
          await _show(
            tester,
            watch: _Watch(),
            state: _watched(name),
            payout: panel,
          );
          expect(
            find.byKey(const ValueKey('payout panel')),
            shown ? findsOneWidget : findsNothing,
            reason: name,
          );
          if (shown) {
            expect(identical(requests.last.seen, _seen[name]), isTrue);
            expect(requests.last.seen.stored, isTrue);
            expect(requests.last.record, _record);
            expect(requests.last.cancelling, isFalse);
          }
        }
      },
    );

    testWidgets(
      'while a cancel runs, the payout panel is told so, and « Submit » goes off (review of #132)',
      (tester) async {
        final gate = Completer<void>();
        final cancels = _Cancels()..gate = gate.future;
        final requests = <PayoutPanelRequest>[];
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('six'),
          payout: (context, request) {
            requests.add(request);
            return const SizedBox(height: 10);
          },
        );
        expect(requests.last.cancelling, isFalse);
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Confirm Cancel'));
        await tester.pump();
        await tester.pump();
        expect(cancels.asked, hasLength(1));
        expect(requests.last.cancelling, isTrue);
        gate.complete();
        await settle(tester);
      },
    );

    testWidgets('« Cancel » is off while a payout is being given (#91)', (
      tester,
    ) async {
      await _show(
        tester,
        watch: _Watch(),
        state: _watched('six'),
        moneyActionRunning: true,
      );
      final cancel = find.widgetWithText(TradeButton, 'Cancel');
      await _reveal(tester, cancel);
      expect(tester.widget<TradeButton>(cancel).onPressed, isNull);
      // Why, for a screen reader and a long press.
      expect(
        find.byTooltip('Cancel is off while your payout info is being sent.'),
        findsOneWidget,
      );
      await tester.tap(cancel, warnIfMissed: false);
      await settle(tester);
      expect(find.text('Cancel the order?'), findsNothing);
    });

    for (final (name, sent) in [
      ('sixCents', '123.45 EUR'),
      ('sixSwap', '100,000 Sats'),
    ]) {
      testWidgets(
        '6: the amount to send at most 4 decimals, an order in bitcoin in Sats ($name)',
        (tester) async {
          await _show(tester, watch: _Watch(), state: _watched(name));
          expect(
            find.text(
              'Before letting you send $sent, we want to make sure you are able to receive the BTC.',
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      '6 kept from no order (an answer refused as a whole): « Cancel » opens no dialog and says to wait for a read',
      (tester) async {
        final cancels = _Cancels()
          ..answer = (seen) => const Err(CancelNeedsARead());
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('sixRegressed'),
        );
        expect(_seen['sixRegressed']?.status, isA<WaitingForBoth>());
        expect(
          _seen['sixRegressed']?.status.warnings,
          contains(isA<TradeStatusRegressed>()),
        );
        await _reveal(tester, find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.text('Confirm Cancel'), findsNothing);
        expect(tester.takeException(), isNull);
        expect(cancels.asked.single.$2, isNull);
        expect(
          find.text('Wait until the order is read again before cancelling.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('7: the wait for the escrow', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('seven'));
      expect(find.text('Your info looks good! (2/4)'), findsOneWidget);
      expect(
        find.text('We are waiting for the seller to lock the trade amount.'),
        findsOneWidget,
      );
      expect(find.text('Your taker bond is locked'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('8: payout info, no cancel', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('eight'));
      expect(find.text('Submit payout info (2/4)'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Copy URL'), findsNothing);
    });

    testWidgets(
      '9: the reference\'s title and the chat step (#95), no « Cancel »',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('nine'));
        expect(find.text('Chat with the seller (3/4)'), findsOneWidget);
        expect(find.text('⚠️ Beware scams'), findsOneWidget);
        expect(
          find.text('Bull Market cannot show this step yet.'),
          findsNothing,
        );
        expect(find.text('Cancel'), findsNothing);
      },
    );
  });

  group('ends and states the reference has no screen for', () {
    testWidgets('expired, with its reason', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('expired'));
      expect(find.text('The order has expired'), findsOneWidget);
      expect(
        find.text('Neither escrow locked or invoice submitted'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsNothing);
    });

    for (final name in ['cancelled', 'cancelledBondLost']) {
      testWidgets(
        '$name: the reference\'s message alone, never that nothing was lost',
        (tester) async {
          await _show(tester, watch: _Watch(), state: _watched(name));
          expect(find.text('This order has been cancelled'), findsOneWidget);
          expect(find.textContaining('Nothing was taken'), findsNothing);
          expect(find.textContaining('nothing was lost'), findsNothing);
          expect(find.text('Contract'), findsNothing);
        },
      );
    }

    for (final name in ['preTakeUnavailable', 'takenByAnother']) {
      testWidgets('$name: « This order is not available »', (tester) async {
        await _show(tester, watch: _Watch(), state: _watched(name));
        expect(find.text('This order is not available'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Cancel'), findsNothing);
      });
    }

    for (final name in ['publicAgain', 'bondForfeited']) {
      testWidgets(
        '$name: the order alone, as to a robot that is no participant',
        (tester) async {
          await _show(tester, watch: _Watch(), state: _watched(name));
          expect(find.text('Order host'), findsOneWidget);
          expect(find.text('Contract'), findsNothing);
          // Without robots in the feature, nothing takes it.
          expect(find.text('Take Order'), findsNothing);
          expect(find.text('Cancel'), findsNothing);
        },
      );
    }

    testWidgets(
      'an order public again, listed by the book: « Take Order » takes it anew, its trade opened',
      (tester) async {
        final takes = <PublicOrder>[];
        final taken = <TradeRecord>[];
        final transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: tradeOrderId, amount: 150)],
          },
        );
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('publicAgain'),
          transport: transport,
          taken: taken,
          takeCubitFor: (order) => TakeOrderCubit(
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
                    takes.add(shown);
                    return Ok(_prepared);
                  },
              confirm: (prepared, {password, onStep}) async =>
                  Ok(TakeOutcomeUnknown(_record)),
              abandon: (prepared) {},
              abandonOrder: (shown, {required network}) {},
            ),
            (network) async => const Ok(true),
          ),
        );
        await settle(tester);
        expect(transport.requested, contains('temple/api/book/'));
        // The order shown is the book's, the one « Take Order » takes, not the trade's last read (100 EUR).
        expect(find.text('150 EUR'), findsWidgets);
        expect(find.text('100 EUR'), findsNothing);
        await _reveal(tester, find.text('Take Order'));
        await tester.tap(find.text('Take Order'));
        await settle(tester);
        expect(takes.single.id, tradeOrderId);
        // The order details show the robot's read, then « Continue » and « Done » of « Store your garage key » take it (#119).
        expect(find.text('Read by your robot at 08:00:30'), findsOneWidget);
        expect(taken, isEmpty);
        await _reveal(tester, find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(taken, [_record]);
      },
    );

    testWidgets(
      'an order public again whose book could not be read: no claim on the order, « Retry » reads it once more',
      (tester) async {
        final transport = FakeTransport(
          books: {
            'temple': [bookOrder(id: tradeOrderId)],
          },
          failures: {'temple': const CoordinatorTimedOut()},
        );
        int bookReads() =>
            transport.requested.where((r) => r == 'temple/api/book/').length;
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('publicAgain'),
          transport: transport,
          takeCubitFor: _neverTaken,
          taken: [],
        );
        await settle(tester);
        await _reveal(tester, find.text('Retry'));
        expect(find.text('Coordinator offline'), findsOneWidget);
        expect(find.text('This order is not available'), findsNothing);
        expect(bookReads(), 1);
        await tester.pump(const Duration(seconds: 30));
        expect(bookReads(), 1);

        transport.failures.remove('temple');
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(bookReads(), 2);
        expect(find.text('Coordinator offline'), findsNothing);
      },
    );

    testWidgets(
      'an order public again whose earlier trade here is the one shown, still open: the refusal said, no trade opened over itself',
      (tester) async {
        final taken = <TradeRecord>[];
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('publicAgain'),
          transport: FakeTransport(
            books: {
              'temple': [bookOrder(id: tradeOrderId)],
            },
          ),
          taken: taken,
          takeCubitFor: (order) => TakeOrderCubit(
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
                  }) async => Err(TakeOrderAlreadyTraded(_record)),
              confirm: (prepared, {password, onStep}) =>
                  throw StateError('not taken'),
              abandon: (prepared) {},
              abandonOrder: (shown, {required network}) {},
            ),
            (network) async => const Ok(true),
            shownTrade: _record,
          ),
        );
        await settle(tester);
        await _reveal(tester, find.text('Take Order'));
        await tester.tap(find.text('Take Order'));
        await settle(tester);
        expect(taken, isEmpty);
        await _reveal(tester, find.text('The order was not taken.'));
        expect(find.text('The order was not taken.'), findsOneWidget);
      },
    );

    testWidgets(
      'an end shown with « Take Order »: paused then resumed, nothing is read again and the screen stays',
      (tester) async {
        final watch = _Watch();
        expect(_seen['publicAgain']?.status.isTerminal, isTrue);
        await _show(
          tester,
          watch: watch,
          state: _watched('publicAgain'),
          transport: FakeTransport(
            books: {
              'temple': [bookOrder(id: tradeOrderId)],
            },
          ),
          takeCubitFor: _neverTaken,
          taken: [],
        );
        await settle(tester);
        expect(find.text('Take Order'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        expect(watch.listens, 1);
        expect(find.text('Take Order'), findsOneWidget);
      },
    );

    testWidgets(
      'an order public again the book no longer lists: « This order is not available »',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('publicAgain'),
          takeCubitFor: _neverTaken,
          taken: [],
        );
        await settle(tester);
        await _reveal(tester, find.text('This order is not available'));
        expect(find.text('This order is not available'), findsOneWidget);
        expect(find.text('Take Order'), findsNothing);
      },
    );

    testWidgets('a take whose answer is unknown: it keeps checking, no action', (
      tester,
    ) async {
      await _show(
        tester,
        watch: _Watch(),
        state: TradeScreenStatuses.watched(
          _seen['pending'] ?? (throw StateError('pending')),
          takePending: true,
        ),
      );
      expect(
        find.text(
          'Bull Market does not know yet whether the take went through. It keeps checking with Temple of Sats.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TradeButton), findsNothing);
    });

    testWidgets(
      'before any read: a spinner, what it waits for, then that it still waits; nothing else',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _show(tester, watch: _Watch());
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
        final line = find.text(
          'Your robot is reading the order from Temple of Sats',
        );
        expect(line, findsOneWidget);
        expect(tester.getSemantics(line), isSemantics(isLiveRegion: true));
        final still = find.text(
          'Still waiting for Temple of Sats. Tor can take a minute.',
        );
        expect(still, findsNothing);
        await tester.pump(const Duration(seconds: 29));
        expect(still, findsNothing);
        await tester.pump(const Duration(seconds: 2));
        expect(still, findsOneWidget);
        semantics.dispose();
      },
    );

    for (final (state, text) in <(TradeWatchState, String)>[
      (
        TradeWatchTakeNeverSent(_record, closed: false),
        'This take was never sent to Temple of Sats.',
      ),
      (
        TradeWatchUnrestorable(_record, const TradeRecordMalformed()),
        'Bull Market cannot read the records of this trade. Nothing is sent.',
      ),
      (
        TradeWatchUnrestorable(_record, const TradeCoordinatorGone()),
        'Temple of Sats is no longer in the list of coordinators. Nothing is sent.',
      ),
      (
        TradeWatchUnavailable(_record, const TradeKeyMissingFailure()),
        'The Garage Key of this trade is not on this device. Nothing is sent.',
      ),
      (
        TradeWatchUnavailable(_record, const RobotCoordinatorChangedFailure()),
        'Bull Market cannot open this trade now. Nothing is sent.',
      ),
    ]) {
      testWidgets('${state.runtimeType}: « $text »', (tester) async {
        await _show(tester, watch: _Watch(), state: state);
        expect(find.text(text), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
      });
    }

    for (final (state, text) in <(TradeWatchState, String)>[
      (
        TradeWatchTakeNotMade(_record, closed: true),
        'The order was not taken.',
      ),
    ]) {
      testWidgets('${state.runtimeType}: « $text », no action', (tester) async {
        await _show(tester, watch: _Watch(), state: state);
        expect(find.text(text), findsOneWidget);
        expect(find.byType(TradeButton), findsNothing);
        expect(find.textContaining('bond'), findsNothing);
      });
    }

    testWidgets(
      'the stored trail re-read at the same position keeps the status shown; an unmarked one does not',
      (tester) async {
        final watch = _Watch();
        final bond = _seen['bond'] ?? (throw StateError('bond'));
        final restored = TradeSeen(
          TradeStatus.beforeFirstRead(bond.status.trail),
          order: null,
          stored: true,
        );
        // The run's memory holds the bond step shown (#152): the newest status stored.
        await _show(
          tester,
          watch: watch,
          state: _watched('bond'),
          lastStored: (_) => bond,
        );
        expect(find.byType(QrImageView), findsOneWidget);

        watch.emit(TradeScreenStatuses.watched(restored));
        await tester.pump();
        await tester.pump();
        expect(find.byType(QrImageView), findsOneWidget);

        watch.emit(
          TradeScreenStatuses.watched(
            TradeSeen(restored.status, order: null),
            recordProblem: const P2pStorageFailure(),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(QrImageView), findsNothing);
        expect(
          find.text(
            'Bull Market could not write the records of this trade on this device.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a stored status not understood at another position than the one shown keeps nothing: the QR code goes',
      (tester) async {
        final watch = _Watch();
        final six = _seen['six'] ?? (throw StateError('six'));
        await _show(tester, watch: watch, state: _watched('bond'));
        expect(find.byType(QrImageView), findsOneWidget);
        watch.emit(
          TradeScreenStatuses.watched(
            TradeSeen(
              TradeStatus.beforeFirstRead(six.status.trail),
              order: null,
              stored: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(QrImageView), findsNothing);
      },
    );

    testWidgets(
      'a status not marked stored: nothing payable, the records said unwritten',
      (tester) async {
        final bond = _seen['bond'] ?? (throw StateError('bond'));
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(
            // The bond's status in memory, with its invoice, but not marked stored.
            TradeSeen(bond.status, order: bond.order),
            recordProblem: const P2pStorageFailure(),
          ),
          walletPayment: (context, request) =>
              const WalletPaymentSlot(Text('wallet slot')),
        );
        expect(
          find.text(
            'Bull Market could not write the records of this trade on this device.',
          ),
          findsOneWidget,
        );
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Copy to clipboard'), findsNothing);
        expect(find.text('Show anyway'), findsNothing);
        expect(find.text('wallet slot'), findsNothing);
      },
    );

    testWidgets(
      'a stored status with a record problem (the confirmation failed): its QR code stays',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(
            _seen['bond'] ?? (throw StateError('bond')),
            recordProblem: const P2pStorageFailure(),
          ),
        );
        expect(
          find.text(
            'Bull Market could not write the records of this trade on this device.',
          ),
          findsOneWidget,
        );
        expect(find.byType(QrImageView), findsOneWidget);
      },
    );

    testWidgets(
      'superseded by a newer watch of the trade: no error, the cubit stops',
      (tester) async {
        final watch = _Watch();
        final cubit = await _show(
          tester,
          watch: watch,
          state: _watched('bond'),
        );
        watch.emit(TradeWatchSuperseded(_record));
        await tester.pump();
        await tester.pump();
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.textContaining('cannot'), findsNothing);
        expect(cubit.state.watch, isA<TradeWatchStatus>());
      },
    );

    testWidgets(
      'reads that keep failing: the last status kept, with its time',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('six', failedReads: 3),
        );
        expect(
          find.textContaining('Cannot reach Temple of Sats.'),
          findsOneWidget,
        );
        expect(find.text('Submit payout info (2/4)'), findsOneWidget);
      },
    );

    testWidgets('two failed reads say nothing yet', (tester) async {
      await _show(
        tester,
        watch: _Watch(),
        state: _watched('six', failedReads: 2),
      );
      expect(find.textContaining('Cannot reach'), findsNothing);
    });

    testWidgets(
      'records that could not be written, and a closed trade the coordinator still shows',
      (tester) async {
        final watch = _Watch();
        await _show(
          tester,
          watch: watch,
          state: TradeScreenStatuses.watched(
            _seen['six'] ?? (throw StateError('six')),
            recordProblem: const P2pStorageFailure(),
          ),
        );
        expect(
          find.text(
            'Bull Market could not write the records of this trade on this device.',
          ),
          findsOneWidget,
        );
        watch.emit(
          TradeScreenStatuses.watched(
            _seen['six'] ?? (throw StateError('six')),
            recordProblem: const TradeClosedFailure(),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'This trade was closed on this device, but Temple of Sats shows this robot as its taker.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('the watch of the shown trade', () {
    testWidgets('one subscription, closed with the screen', (tester) async {
      final watch = _Watch();
      await _show(tester, watch: watch, state: _watched('bond'));
      expect(watch.listens, 1);
      expect(watch.open, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // The cubit is closed by the test's tear-down, as the route closes it: the subscription goes with it.
    });

    testWidgets('hidden or paused, the watch stops; back, it reads again', (
      tester,
    ) async {
      final watch = _Watch();
      var clock = tradeNow;
      await _show(
        tester,
        watch: watch,
        state: _watched('bond'),
        now: () => clock,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(watch.open, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(watch.listens, 2);
      expect(watch.open, 1);
      // Still on the bond panel: the last status stays while the watch reads again.
      expect(find.byType(QrImageView), findsOneWidget);
      // Back after the invoice could no longer be paid: the QR code and the copy are gone at once, without waiting for a read, and the line says why.
      clock = tradeNow.add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(find.text('This invoice has expired.'), findsOneWidget);
    });

    testWidgets('back from a short absence: read now', (tester) async {
      final watch = _Watch();
      await _show(tester, watch: watch, state: _watched('bond'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(watch.signals, [TradeWatchSignal.readNow]);
      expect(watch.listens, 1);
    });

    testWidgets('its route not shown: off screen', (tester) async {
      final watch = _Watch();
      await _show(
        tester,
        watch: watch,
        state: _watched('bond'),
        tickerEnabled: false,
      );
      expect(watch.signals, [TradeWatchSignal.offScreen]);
    });
  });

  group('on a phone of 320 points, the text larger', () {
    final screens = [
      'bond',
      'bondWrongAmount',
      'six',
      'seven',
      'eight',
      'nine',
      'expired',
      'cancelled',
      'publicAgain',
    ];
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: before any read, the line of what it waits for and « Still waiting » are not cut',
          (tester) async {
            await _show(
              tester,
              watch: _Watch(),
              locale: locale,
              size: const Size(320, 568),
              textScale: scale,
            );
            final fr = locale.languageCode == 'fr';
            expect(
              find.text(
                fr
                    ? 'Votre robot lit l’ordre chez Temple of Sats'
                    : 'Your robot is reading the order from Temple of Sats',
              ),
              findsOneWidget,
            );
            _expectNothingCut(tester, 'first read');
            await tester.pump(const Duration(seconds: 31));
            expect(
              find.text(
                fr
                    ? 'Toujours en attente de Temple of Sats. Tor peut prendre une minute.'
                    : 'Still waiting for Temple of Sats. Tor can take a minute.',
              ),
              findsOneWidget,
            );
            _expectNothingCut(tester, 'first read, still waiting');
          },
        );

        testWidgets(
          '${locale.languageCode} at ×$scale: nothing overflows or is cut',
          (tester) async {
            final watch = _Watch();
            await _show(
              tester,
              watch: watch,
              locale: locale,
              size: const Size(320, 568),
              textScale: scale,
            );
            for (final name in screens) {
              watch.emit(_watched(name));
              await tester.pump();
              _expectNothingCut(tester, name);
              // Every part of the screen, scrolled through.
              final list = find.byType(Scrollable).first;
              for (var i = 0; i < 30; i++) {
                await tester.drag(list, const Offset(0, -300));
                await tester.pump();
                _expectNothingCut(tester, '$name, scrolled');
              }
              await tester.drag(list, const Offset(0, 20000));
              await tester.pump();
            }
            // The « Order » tab.
            watch.emit(_watched('bond'));
            await tester.pump();
            await tester.tap(
              find.text(locale.languageCode == 'fr' ? 'Ordre' : 'Order').last,
            );
            await tester.pump();
            _expectNothingCut(tester, 'order tab');
            await tester.tap(
              find.text(locale.languageCode == 'fr' ? 'Contrat' : 'Contract'),
            );
            await tester.pump();

            // The dialogs.
            for (final name in ['bond', 'six']) {
              watch.emit(_watched(name));
              await tester.pump();
              final cancel = find.text(
                locale.languageCode == 'fr' ? 'Annuler' : 'Cancel',
              );
              await _reveal(tester, cancel);
              await tester.tap(cancel);
              await settle(tester);
              _expectNothingCut(tester, '$name dialog');
              await tester.tapAt(const Offset(5, 5));
              await settle(tester);
            }
          },
        );
      }
    }
  });
}
