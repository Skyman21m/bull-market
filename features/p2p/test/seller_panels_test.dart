import 'dart:async';

import 'package:bull_ui/bull_ui.dart' show BullThemeX;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The seller's screens (#96): the bond's « You are SELLING BTC », the escrow to lock at 6 and 7, the wait at 8, the chat's lines and « Confirm {{amount}} {{currencyCode}} received » at 9 and 10 with the reference's dialog, and « Trade finished! » at 13 and 15; each drawn from statuses the state machine made from the reference coordinator's answers.
void main() {
  final record = TradeScreenStatuses.recordFor(TradeRole.seller);
  late TradeScreenStatuses statuses;
  late Map<String, TradeSeen> seen;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make(role: TradeRole.seller);
    final eight = await statuses.waitingForPayout();
    final ten = await statuses.fiatSent();
    final badEscrow = await TradeScreenStatuses.make(
      role: TradeRole.seller,
      escrow: escrowInvoice(sats: escrowOf(bookSats) + 500),
    );
    seen = {
      'three': await statuses.bondStep(),
      'six': await statuses.waitingForBoth(),
      'seven': await statuses.waitingForEscrow(),
      'sixBad': await badEscrow.waitingForBoth(),
      'eight': eight,
      'nine': await statuses.chatting(),
      'ten': ten,
      'thirteen': await statuses.sendingSats(),
      'fifteen': await statuses.read(
        ten,
        orderJson(15, role: TradeRole.seller),
      ),
    };
  });

  TradeSeen at(String name) => seen[name] ?? (throw StateError(name));

  Future<(TradeCubit, List<TradeSeen>, List<TradeSeen>)> show(
    WidgetTester tester,
    String status, {
    Completer<Result<ChatStepOutcome, ChatStepRefusal>>? received,
    Locale locale = const Locale('en'),
    double textScale = 1,
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final asked = <TradeSeen>[];
    final cancels = <TradeSeen>[];
    final watch = _Watch();
    final cubit = TradeCubit(
      record,
      watch.call,
      (record, seen, {bondLoss}) async {
        cancels.add(seen);
        return Ok(CancelDone(record, seen));
      },
      confirmFiatSent: (record, seen, {onProgress}) async =>
          throw StateError('the seller never sends « fiat sent »'),
      confirmFiatReceived: (record, seen, {onProgress}) {
        asked.add(seen);
        return (received ?? Completer()).future;
      },
      rate: (record, seen, rating, {onProgress}) async =>
          Ok(ChatStepDone(record, seen)),
    )..start();
    addTearDown(cubit.close);
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
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: page),
            ],
            child: TradeScreen(
              now: () => tradeNow.add(const Duration(minutes: 1)),
              coordinatorDetails: (_) => throw StateError('not opened'),
              moneyActionRunning: (_) => false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    watch.emit(TradeScreenStatuses.watched(at(status), of: record));
    await tester.pump();
    await tester.pump();
    return (cubit, asked, cancels);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  void expectNothingCut(WidgetTester tester, String reason) {
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

  TradeButton button(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(TradeButton)),
  );

  const received = 'Confirm 100 EUR received';

  testWidgets('3: the bond, « You are SELLING BTC »', (tester) async {
    await show(tester, 'three');
    expect(find.text('You are SELLING BTC'), findsOneWidget);
    expect(find.text('You are BUYING BTC'), findsNothing);
  });

  for (final status in ['six', 'seven']) {
    testWidgets(
      '$status: « Lock … Sats as collateral », the reference\'s lines, the QR code and the copy; no other wallet\'s section',
      (tester) async {
        await show(tester, status);
        expect(find.textContaining('Sats as collateral'), findsOneWidget);
        expect(
          find.text(
            'You risk losing your bond if you do not lock the collateral. Total time available is 3h 0m.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the EUR.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('QR code of the escrow invoice'),
          findsOneWidget,
        );
        expect(find.text('Copy to clipboard'), findsOneWidget);
        expect(find.text('Pay with another wallet'), findsNothing);
        expect(find.text('See Compatible Wallets'), findsNothing);
        // The bond is locked, and lost if the seller cancels now.
        expect(find.text('Your taker bond is locked'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'the « Order » tab for the seller: the sats sent over Lightning, the fiat received',
    (tester) async {
      await show(tester, 'six');
      await tester.tap(find.text('Order').last);
      await tester.pump();
      expect(find.textContaining('You send via Lightning'), findsOneWidget);
      expect(find.textContaining('You receive via'), findsOneWidget);
      expect(find.textContaining('You receive '), findsOneWidget);
    },
  );

  testWidgets(
    'the escrow\'s title is in the warning colour and states the escrow',
    (tester) async {
      await show(tester, 'six');
      final title = tester.widget<Text>(
        find.textContaining('Sats as collateral'),
      );
      expect(
        title.style?.color,
        tester.element(find.textContaining('Sats as collateral')).bull.warning,
      );
      final sats = escrowOf(bookSats);
      expect(
        title.data,
        contains('${sats ~/ 1000},${'${sats % 1000}'.padLeft(3, '0')}'),
      );
    },
  );

  testWidgets(
    'an escrow invoice not of the trade\'s sats and fee: no QR code, no copy, only « Show anyway » and the warning',
    (tester) async {
      await show(tester, 'sixBad');
      expect(
        find.bySemanticsLabel('QR code of the escrow invoice'),
        findsNothing,
      );
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(find.text('Show anyway'), findsOneWidget);
    },
  );

  testWidgets(
    'an escrow from a status not marked stored: no QR code, no copy',
    (tester) async {
      seen['sixUnstored'] = TradeSeen(at('six').status, order: at('six').order);
      await show(tester, 'sixUnstored');
      expect(find.textContaining('Sats as collateral'), findsOneWidget);
      expect(
        find.bySemanticsLabel('QR code of the escrow invoice'),
        findsNothing,
      );
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(find.text('Show anyway'), findsNothing);
    },
  );

  testWidgets(
    'Cancel at 6 is the reference\'s loss of the bond, never a free cancel',
    (tester) async {
      final (_, _, cancels) = await show(tester, 'six');
      await reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Go back'));
      expect(
        find.text('If the order is cancelled now you will lose your bond.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'If the order is cancelled now but you already tried to pay the invoice, you might lose your bond.',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(cancels, isEmpty);
    },
  );

  testWidgets('8: the collateral locked, the wait, no Cancel', (tester) async {
    await show(tester, 'eight');
    expect(
      find.textContaining('The trade collateral is locked!'),
      findsOneWidget,
    );
    expect(
      find.text(
        'We are waiting for the buyer to post a lightning invoice. Once he does, you will be able to directly communicate the payment details.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets(
    '9: « Chat with the buyer », the seller\'s line, the button shown off',
    (tester) async {
      await show(tester, 'nine');
      expect(find.textContaining('Chat with the buyer'), findsOneWidget);
      expect(
        find.text(
          'Say hi! Be helpful and concise. Let them know how to send you 100 EUR.',
        ),
        findsOneWidget,
      );
      expect(button(tester, received).onPressed, isNull);
      expect(find.textContaining('Confirm 100 EUR sent'), findsNothing);
      expect(find.text('Payment failed?'), findsNothing);
    },
  );

  testWidgets(
    '10: the button on; the reference\'s dialog; « Go back » sends nothing; « Confirm » sends once',
    (tester) async {
      final answer = Completer<Result<ChatStepOutcome, ChatStepRefusal>>();
      final (_, asked, _) = await show(tester, 'ten', received: answer);
      expect(
        find.text(
          "The buyer has sent the fiat. Click 'Confirm Received' once you receive it.",
        ),
        findsOneWidget,
      );
      await reveal(tester, find.text(received));
      expect(button(tester, received).onPressed, isNotNull);
      await tester.tap(find.text(received));
      await tester.pumpAndSettle();
      expect(find.text('✅ Confirm you received 100 EUR?'), findsOneWidget);
      for (final line in [
        'Confirming will finalize the trade.',
        '⚠️ This action cannot be undone!',
        'The satoshis in the escrow will be released to the buyer:',
        'Only confirm after 100 EUR have arrived to your account.',
        'If you have received the payment and do not click confirm, you risk losing your bond.',
        'Some fiat payment methods might reverse their transactions up to 80 days after they are completed. Please keep this token and your order data in case you need to use them as proof.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      await reveal(tester, find.text('Go back'));
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(asked, isEmpty);

      await reveal(tester, find.text(received));
      await tester.tap(find.text(received));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump();
      expect(asked, hasLength(1));
      expect(asked.single.status, isA<Chatting>());
      // While it runs, the button is busy: a second tap sends nothing.
      await tester.tap(find.byType(TradeButton).last, warnIfMissed: false);
      await tester.pump();
      expect(asked, hasLength(1));
      answer.complete(Ok(ChatStepOutcomeUnknown(record, at('ten'))));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Bull Market does not know yet whether your confirmation went through. It keeps checking.',
        ),
        findsOneWidget,
      );
      expect(asked, hasLength(1));
    },
  );

  testWidgets('10 from a status not marked stored: the button off, and why', (
    tester,
  ) async {
    seen['tenUnstored'] = TradeSeen(at('ten').status, order: at('ten').order);
    await show(tester, 'tenUnstored');
    expect(button(tester, received).onPressed, isNull);
    expect(find.text('Wait until the order is read again.'), findsOneWidget);
  });

  for (final status in ['thirteen', 'fifteen']) {
    testWidgets(
      '$status: « Trade finished! » for the seller, the stars, no bond line',
      (tester) async {
        await show(tester, status);
        expect(find.text('Trade finished!'), findsOneWidget);
        expect(find.text('Rate your trade experience'), findsOneWidget);
        expect(find.text('Attempting Lightning Payment'), findsNothing);
        expect(find.textContaining('bond is'), findsNothing);
      },
    );
  }

  testWidgets('the French of the seller\'s panels', (tester) async {
    await show(tester, 'six', locale: const Locale('fr'));
    expect(find.textContaining('sats en garantie'), findsOneWidget);
    expect(
      find.text(
        "Ceci est une facture en attente, elle sera gelée dans votre portefeuille. Elle sera remise à l'acheteur une fois que vous aurez confirmé avoir reçu les EUR.",
      ),
      findsOneWidget,
    );
    await show(tester, 'ten', locale: const Locale('fr'));
    expect(find.text('Confirmer la réception de 100 EUR'), findsOneWidget);
  });

  for (final locale in const [Locale('en'), Locale('fr')]) {
    for (final scale in const [2.0, 3.0]) {
      testWidgets(
        'at ${scale}x in ${locale.languageCode}: the escrow, the wait, the chat step and the dialog, nothing cut',
        (tester) async {
          for (final status in ['six', 'eight', 'thirteen', 'ten']) {
            await show(
              tester,
              status,
              locale: locale,
              textScale: scale,
              size: const Size(320, 640),
            );
            expectNothingCut(tester, '$status ${scale}x');
          }
          final label = locale.languageCode == 'fr'
              ? 'Confirmer la réception de 100 EUR'
              : received;
          await reveal(tester, find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expectNothingCut(tester, 'dialog ${scale}x');
        },
      );
    }
  }
}

/// The watch of the trade, played by the test, as `chat_step_panel_test.dart`'s.
final class _Watch {
  final _states = StreamController<TradeWatchState>.broadcast();

  Stream<TradeWatchState> call(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    late final StreamController<TradeWatchState> out;
    StreamSubscription<TradeWatchState>? forwarded;
    StreamSubscription<TradeWatchSignal>? told;
    out = StreamController(
      onListen: () {
        told = signals.listen((_) {});
        forwarded = _states.stream.listen(out.add);
      },
      onCancel: () async {
        await told?.cancel();
        await forwarded?.cancel();
      },
    );
    return out.stream;
  }

  void emit(TradeWatchState state) => _states.add(state);
}
