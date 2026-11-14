import 'dart:async';

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
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/trade/wallet_payment_section.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/harness.dart';
import 'support/trade_orders.dart';
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

  Future<Result<CancelOutcome, CancelRefusal>> call(
    TradeRecord record,
    TradeSeen seen, {
    BondLossAcknowledged? bondLoss,
  }) async {
    asked.add((seen, bondLoss));
    return (answer ?? (seen) => Ok(CancelDone(record, seen)))(seen);
  }
}

late TradeScreenStatuses _statuses;
late TradeScreenStatuses _wrongNetwork;
late TradeScreenStatuses _wrongAmount;
late Map<String, TradeSeen> _seen;

final _record = TradeScreenStatuses.record;

/// Shows the trade screen over [watch] and [cancels], with [state] emitted once it listens.
Future<TradeCubit> _show(
  WidgetTester tester, {
  required _Watch watch,
  _Cancels? cancels,
  TradeWatchState? state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  WalletPaymentBuilder? walletPayment,
  bool tickerEnabled = true,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = TradeCubit(_record, watch.call, (cancels ?? _Cancels()).call)
    ..start();
  addTearDown(cubit.close);
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
          body: BlocProvider.value(
            value: cubit,
            child: TradeScreen(
              now: () => tradeNow,
              coordinatorDetails: (_) => throw StateError('not opened'),
              walletPayment: walletPayment,
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
    _statuses = await TradeScreenStatuses.make();
    _wrongNetwork = await TradeScreenStatuses.make(
      invoice: bondInvoice(network: Bolt11Network.testnet),
    );
    _wrongAmount = await TradeScreenStatuses.make(
      invoice: bondInvoice(sats: bookBond + 1),
      bondSatoshis: bookBond,
    );
    _seen = {
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

  group('status 3, the bond', () {
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
            return const Text('wallet slot');
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
        await _show(tester, watch: _Watch(), state: _watched('bond'));
        await tester.tap(find.text('Order').last);
        await tester.pump();
        expect(find.text('Order host'), findsOneWidget);
        expect(find.text('Expires in'), findsOneWidget);
        expect(find.text('Deposit'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
      },
    );
  });

  group('cancel', () {
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
          await tester.tap(find.text('Confirm Cancel'));
          await settle(tester);
          expect(cancels.asked, hasLength(1));
          expect(cancels.asked.single.$1, same(_seen[name]));
          expect(cancels.asked.single.$2, isA<BondLossAcknowledged>());
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
    testWidgets('6: payout info, the form a later version, the bond locked', (
      tester,
    ) async {
      await _show(tester, watch: _Watch(), state: _watched('six'));
      expect(find.text('Submit payout info (2/4)'), findsOneWidget);
      expect(
        find.text(
          'Before letting you send 100 EUR, we want to make sure you are able to receive the BTC.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Sending your payout info comes in a later version of Bull Market.',
        ),
        findsOneWidget,
      );
      expect(find.text('Your taker bond is locked'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

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

    testWidgets('9: the reference\'s title, a later version', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('nine'));
      expect(find.text('Chat with the seller (3/4)'), findsOneWidget);
      expect(
        find.text('Bull Market cannot show this step yet.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsNothing);
    });
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
          expect(find.text('Take Order'), findsNothing);
          expect(find.text('Cancel'), findsNothing);
        },
      );
    }

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

    testWidgets('before any read: a spinner, nothing else', (tester) async {
      await _show(tester, watch: _Watch());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

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
      await _show(tester, watch: watch, state: _watched('bond'));
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
