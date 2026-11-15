import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/chat_cubit.dart';
import 'package:p2p/src/ui/trade/chat_actions.dart';
import 'package:p2p/src/ui/trade/chat_panel.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:robosats/robosats.dart';

import 'support/harness.dart';
import 'support/trade_harness.dart' show otherTradeKey;
import 'support/trade_screens.dart';

/// The `no_screenshot` plugin behind `PrivacyScreen` answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// The chat panel of #93 and its cubit, over chats the tests make and use cases played by fakes that record what they were given: never a coordinator, never a real key, token or message.
void main() {
  final record = TradeScreenStatuses.record;
  const coordinatorName = 'Temple of Sats';
  final at = DateTime.utc(2026, 11, 15, 9, 30);
  late TradeSeen nine;
  late String ownNick;
  late String peerNick;
  late PgpPublicKey peerKey;
  late PgpPublicKey ownKey;
  late PgpPublicKey otherKey;

  PgpPublicKey keyOf(int index, int seed) {
    final identity = switch (NetworkGarageKey(
      RobosatsNetwork.mainnet,
      otherTradeKey,
    ).firstUsableRobot(index)) {
      Ok(:final value) => value.identity,
      Err(:final failure) => throw StateError('$failure'),
    };
    return switch (RobotPgpKey.generateWith(
      identity,
      now: at,
      random: Random(seed),
    )) {
      Ok(:final value) => value.publicKey,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  setUpAll(() async {
    final statuses = await TradeScreenStatuses.make();
    nine = await statuses.chatting();
    final order = nine.order!;
    ownNick = order.taker!.nickname;
    peerNick = order.maker.nickname;
    peerKey = keyOf(0, 931);
    ownKey = keyOf(1, 932);
    otherKey = keyOf(2, 933);
  });

  ChatEntry entry(
    int index,
    String text, {
    bool own = false,
    bool valid = true,
    bool afterGap = false,
    int? repeatOf,
    bool sentTwice = false,
    bool outOfOrder = false,
  }) => ChatEntry(
    index: index,
    time: at.add(Duration(minutes: index)),
    nick: own ? ownNick : peerNick,
    author: own ? ChatAuthor.self : ChatAuthor.peer,
    text: text,
    validSignature: valid,
    signedAt: valid ? at : null,
    afterGap: afterGap,
    repeatOf: repeatOf,
    sentTwice: sentTwice,
    signedOutOfOrder: outOfOrder,
  );

  ChatView pinned({
    List<ChatEntry> entries = const [],
    List<ChatPendingMessage> pending = const [],
    bool peerConnected = true,
  }) => ChatView(
    entries: entries,
    pending: pending,
    peerKey: ChatPeerKeyPinned(peerKey),
    peerConnected: peerConnected,
    connected: true,
    ownKey: ownKey,
  );

  group('the cubit', () {
    testWidgets(
      'shown in the foreground it holds the key and reads at once, then every 5 s, one read at a time; hidden, neither',
      (tester) async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        expect(chat.reads, 0, reason: 'nothing read before it is shown');
        cubit.activate();
        cubit.activate();
        expect(chat.held, 1);
        expect(chat.reads, 1);
        await tester.pump();
        await tester.pump(ChatCubit.pollEvery);
        expect(chat.reads, 2);
        // A read slower than the poll: the next tick asks nothing.
        chat.gate = Completer<void>();
        await tester.pump(ChatCubit.pollEvery);
        expect(chat.reads, 3);
        await tester.pump(ChatCubit.pollEvery);
        expect(chat.reads, 3, reason: 'a read runs: no second one');
        chat.gate!.complete();
        chat.gate = null;
        await tester.pump();
        await tester.pump(ChatCubit.pollEvery);
        expect(chat.reads, 4);
        cubit.deactivate();
        expect(chat.released, 1);
        expect(cubit.holdsKey, isFalse);
        expect(cubit.polling, isFalse);
        await tester.pump(ChatCubit.pollEvery * 3);
        expect(chat.reads, 4, reason: 'no read while hidden');
        cubit.activate();
        expect(chat.held, 2);
        await cubit.close();
        expect(chat.released, 2, reason: 'closing lets the key go');
      },
    );

    testWidgets('a read that fails keeps the chat shown and says why', (
      tester,
    ) async {
      final chat = _Chat()..view = pinned(entries: [entry(1, 'Hello')]);
      final cubit = chat.cubit(record)..show(nine);
      addTearDown(cubit.close);
      cubit.activate();
      await tester.pump();
      expect(cubit.state.view.entries, hasLength(1));
      chat.readAnswer = () =>
          const Err(ChatReadFailed(CoordinatorUnreachable()));
      await tester.pump(ChatCubit.pollEvery);
      await tester.pump();
      expect(cubit.state.view.entries, hasLength(1));
      expect(cubit.state.readFailure, isA<ChatReadFailed>());
      chat.readAnswer = null;
      await tester.pump(ChatCubit.pollEvery);
      await tester.pump();
      expect(cubit.state.readFailure, isNull);
    });

    testWidgets(
      '« Send » sends the text shown, once; a message not confirmed is sent again only by the user, never by a read',
      (tester) async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.activate();
        await tester.pump();
        cubit.edit('Hello, the transfer is on its way');
        expect(cubit.state.canSend, isTrue);
        chat.postGate = Completer<void>();
        chat.postAnswer = (text) {
          final pending = ChatPendingMessage(1, text, at);
          chat.view = pinned(pending: [pending]);
          return Ok(ChatSentNotConfirmed(pending));
        };
        unawaited(cubit.send());
        unawaited(cubit.send());
        expect(cubit.state.sending, 0);
        expect(cubit.state.canSend, isFalse);
        // Typed during the send: kept, not sent.
        cubit.edit('Hello, the transfer is on its way, ref 12');
        chat.postGate!.complete();
        await tester.pump();
        expect(chat.posts, ['Hello, the transfer is on its way']);
        expect(cubit.state.sending, isNull);
        expect(cubit.state.text, 'Hello, the transfer is on its way, ref 12');
        expect(cubit.state.view.pending, hasLength(1));
        // Reads go on: nothing is posted again.
        await tester.pump(ChatCubit.pollEvery * 4);
        expect(chat.posts, hasLength(1));
        expect(chat.reposts, isEmpty);
        chat.repostAnswer = (id) {
          chat.view = pinned(entries: [entry(4, 'Hello', own: true)]);
          return const Ok(ChatSentStored(4));
        };
        await cubit.sendAgain(1);
        expect(chat.reposts, [1]);
        expect(cubit.state.view.pending, isEmpty);
      },
    );

    testWidgets(
      'a text stored empties the field; a refusal keeps it and says why',
      (tester) async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.edit('Sent');
        chat.postAnswer = (_) => const Ok(ChatSentStored(4));
        await cubit.send();
        expect(cubit.state.text, isEmpty);
        cubit.edit('Refused');
        chat.postAnswer = (_) =>
            const Err(ChatSendRefused(CoordinatorUnreachable()));
        await cubit.send();
        expect(cubit.state.text, 'Refused');
        expect(cubit.state.refusal, isA<ChatSendRefused>());
      },
    );

    testWidgets(
      'a text that holds the token is not sent and the field is emptied, as the reference does',
      (tester) async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.edit('my token is x');
        chat.postAnswer = (_) => const Err(ChatTextHoldsToken());
        await cubit.send();
        expect(cubit.state.text, isEmpty);
        expect(cubit.state.refusal, isA<ChatTextHoldsToken>());
      },
    );

    test(
      'what cannot be sent is said as it is typed, and « Send » is off for it',
      () async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.edit('   ');
        expect(cubit.state.refusal, isNull);
        expect(cubit.state.canSend, isFalse);
        cubit.edit('x' * (OutgoingChatMessage.maxTextBytes + 1));
        expect(cubit.state.refusal, isA<ChatTextTooLong>());
        expect(cubit.state.canSend, isFalse);
        cubit.edit('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
        expect(cubit.state.refusal, isA<ChatTextIsPayout>());
        cubit.edit('Send to bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
        expect(cubit.state.refusal, isNull);
        expect(cubit.state.canSend, isTrue);
        chat.view = const ChatView();
        final waiting = chat.cubit(record)..show(nine);
        addTearDown(waiting.close);
        waiting.edit('Hello');
        expect(
          waiting.state.canSend,
          isFalse,
          reason: 'no peer key: the reference sends nothing',
        );
        await waiting.send();
        expect(chat.posts, isEmpty);
      },
    );

    test('its state shows no message, nor the text typed', () {
      final chat = _Chat()
        ..view = pinned(
          entries: [entry(1, 'secret payment details')],
          pending: [ChatPendingMessage(1, 'pending details', at)],
        );
      final cubit = chat.cubit(record);
      addTearDown(cubit.close);
      cubit.edit('typed details');
      final shown = '${cubit.state} ${cubit.state.view.entries.single}';
      expect(shown, isNot(contains('details')));
    });

    test(
      'the export as the reference names it, the keys and messages apart',
      () {
        final chat = _Chat()
          ..exported = {
            'credentials': {'own_public_key': 'own'},
            'messages': [
              {'index': 1},
            ],
          };
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        expect(
          cubit.exportFileName,
          'complete_log_chat_${record.orderId}.json',
        );
        expect(cubit.keysFileName, 'pgp_keys_${record.orderId}.json');
        expect(cubit.messagesFileName, 'pgp_messages_${record.orderId}.json');
        expect(jsonDecode(cubit.exportJson()), chat.exported);
        expect(jsonDecode(cubit.keysJson()), {'own_public_key': 'own'});
        expect(jsonDecode(cubit.messagesJson()), [
          {'index': 1},
        ]);
      },
    );
  });

  group('the panel', () {
    late List<String> privacyCalls;
    late Future<bool> Function() protection;
    late List<String> copied;

    setUp(() {
      privacyCalls = [];
      protection = () async => true;
      copied = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_privacyChannel, (call) async {
        privacyCalls.add(call.method);
        return call.method == 'screenshotOff' ? protection() : true;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add('${(call.arguments as Map)['text']}');
        }
        return null;
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_privacyChannel, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> show(
      WidgetTester tester,
      ChatCubit cubit, {
      Locale locale = const Locale('en'),
      Size size = const Size(390, 844),
      double textScale = 1,
      bool tickers = true,
    }) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
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
            body: TickerMode(
              enabled: tickers,
              child: BlocProvider.value(
                value: cubit,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ChatPanel(
                    request: ChatPanelRequest(
                      record: record,
                      seen: nine,
                      coordinator: coordinatorName,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Finder sendButton() => find.byTooltip('Send');

    bool sendEnabled(WidgetTester tester) =>
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byTooltip('Send'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets(
      'nothing is drawn before the capture protection is on; without it, a line and « Retry »; it is let go with the panel',
      (tester) async {
        final gate = Completer<bool>();
        protection = () => gate.future;
        final chat = _Chat()..view = pinned(entries: [entry(1, 'Hello')]);
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(privacyCalls, contains('screenshotOff'));
        expect(find.text('Hello'), findsNothing);
        expect(find.text('Type a message'), findsNothing);
        gate.complete(false);
        await tester.pump();
        await tester.pump();
        expect(find.text('Hello'), findsNothing);
        expect(
          find.text(
            'Screen protection could not be turned on, so the chat stays hidden.',
          ),
          findsOneWidget,
        );
        protection = () async => true;
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Hello'), findsOneWidget);
        privacyCalls.clear();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(privacyCalls, contains('screenshotOn'));
        expect(cubit.holdsKey, isFalse);
        expect(cubit.polling, isFalse);
      },
    );

    testWidgets(
      'before the peer\'s key: « You: disconnected », « Peer: ...waiting », and « Send » off with « Waiting for peer... »',
      (tester) async {
        final chat = _Chat();
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(find.text('You: disconnected'), findsOneWidget);
        expect(find.text('Peer: ...waiting'), findsOneWidget);
        expect(find.byTooltip('Waiting for peer...'), findsOneWidget);
        await tester.enterText(find.byKey(ChatPanel.field), 'Hello');
        await tester.pump();
        await tester.tap(find.byTooltip('Waiting for peer...'));
        await tester.pump();
        expect(chat.posts, isEmpty);
      },
    );

    testWidgets(
      'the messages as the reference shows them: the author, the tick or the cross with its tooltip, a copy, and the marks of the app',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final chat = _Chat()
          ..view = pinned(
            peerConnected: false,
            entries: [
              entry(1, 'Hello, I am sending the fiat'),
              entry(2, 'Received?', own: true),
              entry(3, 'Unsigned', valid: false, afterGap: true),
              entry(4, 'Hello, I am sending the fiat', repeatOf: 1),
              entry(5, 'Twice', own: true, repeatOf: 2, sentTwice: true),
              entry(6, 'Old', outOfOrder: true),
            ],
          );
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(find.text('You: connected'), findsOneWidget);
        expect(find.text('Peer: disconnected'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Verified signature by $peerNick'),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel('Cannot verify signature of $peerNick'),
          findsOneWidget,
        );
        expect(
          find.text('A message may be missing before this one.'),
          findsOneWidget,
        );
        expect(
          find.text('This message was already shown above.'),
          findsOneWidget,
        );
        expect(find.text('You sent this message twice.'), findsOneWidget);
        expect(
          find.text('This message was signed before an earlier one.'),
          findsOneWidget,
        );
        final copy = find.byTooltip('Copy').first;
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await tester.pump();
        expect(copied, ['Hello, I am sending the fiat']);
        expect(find.text('Copied!'), findsWidgets);
        await tester.pump(const Duration(seconds: 3));
        semantics.dispose();
      },
    );

    testWidgets(
      'a message not confirmed says so, and « Send again » is the user\'s tap',
      (tester) async {
        final chat = _Chat()
          ..view = pinned(pending: [ChatPendingMessage(1, 'Paid', at)]);
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(find.text('Paid'), findsOneWidget);
        expect(
          find.text(
            'Not confirmed by Temple of Sats. It may still reach your peer.',
          ),
          findsOneWidget,
        );
        await tester.pump(ChatCubit.pollEvery * 3);
        expect(chat.reposts, isEmpty);
        chat.repostAnswer = (id) {
          chat.view = pinned(entries: [entry(4, 'Paid', own: true)]);
          return const Ok(ChatSentStored(4));
        };
        final again = find.widgetWithText(TradeButton, 'Send again');
        await tester.ensureVisible(again);
        await tester.tap(again);
        await tester.pump();
        await tester.pump();
        expect(chat.reposts, [1]);
        expect(find.text('Send again'), findsNothing);
      },
    );

    testWidgets(
      'the wait of a send says what it waits for, read out; what it gave is read out too',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        await tester.enterText(find.byKey(ChatPanel.field), 'Hello');
        await tester.pump();
        expect(sendEnabled(tester), isTrue);
        chat.postGate = Completer<void>();
        chat.postAnswer = (_) =>
            const Err(ChatSendRefused(CoordinatorUnreachable()));
        await tester.tap(sendButton());
        await tester.pump();
        const sending = 'Sending the message to Temple of Sats…';
        expect(
          tester.getSemantics(find.text(sending)),
          matchesSemantics(label: sending, isLiveRegion: true),
        );
        chat.postGate!.complete();
        await tester.pump();
        await tester.pump();
        const refused = 'Temple of Sats did not take the message. Try again.';
        expect(
          tester.getSemantics(find.text(refused)),
          matchesSemantics(label: refused, isLiveRegion: true),
        );
        expect(chat.posts, ['Hello']);
        semantics.dispose();
      },
    );

    testWidgets('each refusal before sending is said with its line', (
      tester,
    ) async {
      final chat = _Chat()..view = pinned();
      final cubit = chat.cubit(record);
      addTearDown(cubit.close);
      await show(tester, cubit);
      await tester.enterText(
        find.byKey(ChatPanel.field),
        // The shape of an invoice, not one.
        'lightning:lnbc1${'q' * 60}',
      );
      await tester.pump();
      expect(
        find.text(
          'An invoice or an address is not sent alone. Add a word beside it to send it.',
        ),
        findsOneWidget,
      );
      expect(sendEnabled(tester), isFalse);
      await tester.enterText(
        find.byKey(ChatPanel.field),
        'x' * (OutgoingChatMessage.maxTextBytes + 1),
      );
      await tester.pump();
      expect(
        find.text('This message is too long. Shorten it to send it.'),
        findsOneWidget,
      );
      chat.postAnswer = (_) => const Err(ChatTextHoldsToken());
      await tester.enterText(find.byKey(ChatPanel.field), 'hello');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('So bad your message was blocked.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byKey(ChatPanel.field)).controller?.text,
        isEmpty,
      );
    });

    testWidgets(
      'a peer key that changed, or that is not the peer\'s, is said and nothing more is sent',
      (tester) async {
        for (final (state, line) in [
          (
            ChatPeerKeyBreach(pinned: peerKey),
            'Your peer’s public key changed during this trade, so nothing more is sent in this chat.',
          ),
          (
            const ChatPeerKeyBreach(),
            'Temple of Sats gave a public key that is not your peer’s, so nothing is sent in this chat.',
          ),
        ]) {
          final chat = _Chat()
            ..view = ChatView(peerKey: state, connected: true);
          final cubit = chat.cubit(record);
          addTearDown(cubit.close);
          await tester.pumpWidget(const SizedBox.shrink());
          await show(tester, cubit);
          expect(find.text(line), findsOneWidget);
          await tester.enterText(find.byKey(ChatPanel.field), 'Hello');
          await tester.pump();
          expect(sendEnabled(tester), isFalse);
        }
      },
    );

    testWidgets(
      'a history too long: said, and « Read only the newer messages » on the user\'s choice',
      (tester) async {
        final chat = _Chat()..view = const ChatView(historyTooLarge: true);
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(
          find.text('This chat is too long to be read from its first message.'),
          findsOneWidget,
        );
        final reads = chat.reads;
        chat.skipped = const ChatView(skippedEarlier: true);
        await tester.tap(find.text('Read only the newer messages'));
        await tester.pump();
        expect(chat.skips, 1);
        expect(chat.reads, reads + 1);
        expect(find.text('Earlier messages are not shown.'), findsOneWidget);
      },
    );

    testWidgets(
      'no read and the key let go while another tab of the shell is shown, or the app is in the background',
      (tester) async {
        final chat = _Chat()..view = pinned();
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        expect(cubit.holdsKey, isTrue);
        expect(cubit.polling, isTrue);
        await show(tester, cubit, tickers: false);
        expect(cubit.holdsKey, isFalse);
        expect(cubit.polling, isFalse);
        await show(tester, cubit);
        expect(cubit.holdsKey, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        expect(cubit.holdsKey, isFalse);
        final reads = chat.reads;
        await tester.pump(ChatCubit.pollEvery * 2);
        expect(chat.reads, reads);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(cubit.holdsKey, isTrue);
        expect(chat.reads, reads + 1);
      },
    );

    testWidgets('nothing of a message is printed', (tester) async {
      final printed = <String>[];
      await runZoned(
        () async {
          final chat = _Chat()
            ..view = pinned(
              entries: [entry(1, 'IBAN details')],
              pending: [ChatPendingMessage(1, 'IBAN pending', at)],
            );
          final cubit = chat.cubit(record);
          addTearDown(cubit.close);
          await show(tester, cubit);
          await tester.enterText(find.byKey(ChatPanel.field), 'IBAN typed');
          await tester.pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(printed.join('\n'), isNot(contains('IBAN')));
    });

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          'nothing cut or overflowing on a phone of 320 points, ${locale.languageCode}, text ×$scale',
          (tester) async {
            for (final view in [
              const ChatView(),
              pinned(
                entries: [
                  entry(1, 'Hello, I am sending the fiat now'),
                  entry(2, 'OK', own: true),
                  entry(3, 'Unsigned', valid: false, afterGap: true),
                  entry(4, 'Again', repeatOf: 1, outOfOrder: true),
                ],
                pending: [ChatPendingMessage(1, 'Paid, ref 12', at)],
              ),
              ChatView(
                peerKey: ChatPeerKeyBreach(pinned: peerKey),
                connected: true,
                historyTooLarge: true,
              ),
              const ChatView(
                peerKey: ChatPeerKeyBreach(),
                skippedEarlier: true,
              ),
            ]) {
              final chat = _Chat()
                ..view = view
                ..readAnswer = () =>
                    const Err(ChatReadFailed(CoordinatorUnreachable()));
              final cubit = chat.cubit(record);
              addTearDown(cubit.close);
              await tester.pumpWidget(const SizedBox.shrink());
              await show(
                tester,
                cubit,
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
              );
              await tester.enterText(
                find.byKey(ChatPanel.field),
                'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
              );
              await tester.pump();
              _expectNothingCut(
                tester,
                '${view.peerKey} ${locale.languageCode} $scale',
              );
            }
          },
        );
      }
    }
  });

  group('« Don\'t trust, verify » and « Export »', () {
    late List<(String, String)> shared;

    setUp(() => shared = []);

    Future<void> share(String name, String text) async =>
        shared.add((name, text));

    Future<ChatCubit> showActions(
      WidgetTester tester, {
      ChatView? view,
      Locale locale = const Locale('en'),
      Size size = const Size(390, 844),
      double textScale = 1,
    }) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final chat = _Chat()
        ..view = view ?? pinned()
        ..exported = {
          'credentials': {
            'own_public_key': ownKey.armored,
            'peer_public_key': peerKey.armored,
          },
          'messages': <Object?>[],
        };
      final cubit = chat.cubit(record);
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
          home: Scaffold(
            body: ListView(
              children: [
                ChatAuditButton(cubit: cubit, share: share),
                ChatExportButton(cubit: cubit, share: share),
              ],
            ),
          ),
        ),
      );
      return cubit;
    }

    testWidgets(
      'the public keys with their fingerprints, and the files handed to the share sheet on a tap only',
      (tester) async {
        await showActions(tester);
        expect(shared, isEmpty);
        await tester.tap(find.text('Export'));
        await tester.pump();
        expect(shared.single.$1, 'complete_log_chat_${record.orderId}.json');
        await tester.tap(find.text('Audit Chat'));
        await settle(tester);
        expect(find.text("Don't trust, verify"), findsOneWidget);
        expect(find.text('Your public key'), findsOneWidget);
        expect(find.text('Peer public key'), findsOneWidget);
        String grouped(String fingerprint) => [
          for (var i = 0; i < fingerprint.length; i += 4)
            fingerprint.substring(i, i + 4),
        ].join(' ');
        expect(
          find.text('Fingerprint: ${grouped(ownKey.fingerprint)}'),
          findsOneWidget,
        );
        expect(
          find.text('Fingerprint: ${grouped(peerKey.fingerprint)}'),
          findsOneWidget,
        );
        expect(find.text(otherKey.armored), findsNothing);
        await tester.tap(find.text('Keys'));
        await tester.pump();
        expect(shared.last.$1, 'pgp_keys_${record.orderId}.json');
        expect(shared.last.$2, isNot(contains('PRIVATE')));
        await tester.tap(find.text('Messages'));
        await tester.pump();
        expect(shared.last.$1, 'pgp_messages_${record.orderId}.json');
        await tester.tap(find.text('Go back'));
        await settle(tester);
        expect(find.text("Don't trust, verify"), findsNothing);
        expect(shared, hasLength(3));
      },
    );

    testWidgets('before the peer\'s key: only this robot\'s', (tester) async {
      await showActions(tester, view: ChatView(ownKey: ownKey));
      await tester.tap(find.text('Audit Chat'));
      await settle(tester);
      expect(find.text('Your public key'), findsOneWidget);
      expect(find.text('Peer public key'), findsNothing);
    });

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          'the dialog: nothing cut on a phone of 320 points, ${locale.languageCode}, text ×$scale',
          (tester) async {
            await showActions(
              tester,
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
            );
            await tester.tap(find.byType(ChatAuditButton));
            await settle(tester);
            _expectNothingCut(tester, 'audit ${locale.languageCode} $scale');
          },
        );
      }
    }
  });
}

/// The use cases of the chat, played: what they were given, and what the test says they answer.
final class _Chat {
  ChatView view = const ChatView();
  ChatView skipped = const ChatView();
  int reads = 0;
  int skips = 0;
  int held = 0;
  int released = 0;
  Completer<void>? gate;
  Result<ChatView, ChatReadFailure> Function()? readAnswer;
  final List<String> posts = [];
  Completer<void>? postGate;
  Result<ChatSent, ChatSendRefusal> Function(String text)? postAnswer;
  final List<int> reposts = [];
  Result<ChatSent, ChatSendRefusal> Function(int id)? repostAnswer;
  Map<String, Object?> exported = const {};

  ChatCubit cubit(TradeRecord record) => ChatCubit(
    record,
    (record, seen) async {
      reads++;
      await gate?.future;
      return readAnswer?.call() ?? Ok(view);
    },
    (record, seen, text) async {
      posts.add(text);
      await postGate?.future;
      return postAnswer?.call(text) ?? const Ok(ChatSentStored(1));
    },
    (record, seen, id) async {
      reposts.add(id);
      return repostAnswer?.call(id) ?? const Ok(ChatSentStored(1));
    },
    (record, seen) {
      skips++;
      view = skipped;
      return skipped;
    },
    (record) => view,
    (record) => exported,
    (record) {
      held++;
      return () => released++;
    },
  );
}

/// Every paragraph on the screen laid out without being cut, and no overflow.
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
