import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bull_ui/bull_ui.dart' show BullTheme;
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
  late TradeSeen nineAgain;
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
    nineAgain = await statuses.chatting();
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
        cubit.deactivate();
      },
    );

    test('closing it stops the reads and lets the key go', () async {
      final chat = _Chat()..view = pinned();
      final cubit = chat.cubit(record)..show(nine);
      cubit.activate();
      await cubit.close();
      expect(chat.released, 1);
      expect(cubit.polling, isFalse);
    });

    testWidgets(
      'hidden, a skip that waits for a newer order reads nothing; it is done when the panel is shown again (review of #93)',
      (tester) async {
        final chat = _Chat()
          ..view = const ChatView(historyTooLarge: true)
          ..skipRefused = true;
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.activate();
        await tester.pump();
        cubit.readNewerOnly();
        expect(cubit.state.skipAwaited, isTrue);
        cubit.deactivate();
        final reads = chat.reads;
        final skips = chat.skips;
        chat
          ..skipRefused = false
          ..skipped = const ChatView(skippedEarlier: true);
        cubit.show(nineAgain);
        await tester.pump();
        expect(chat.reads, reads, reason: 'no read while hidden');
        expect(chat.skips, skips);
        expect(cubit.holdsKey, isFalse);
        cubit.activate();
        await tester.pump();
        expect(chat.skips, skips + 1);
        expect(chat.reads, reads + 1);
        expect(cubit.state.view.skippedEarlier, isTrue);
        cubit.deactivate();
      },
    );

    test(
      'inactive, « Read only the newer messages » skips but reads nothing (review of #93)',
      () async {
        final chat = _Chat()
          ..view = const ChatView(historyTooLarge: true)
          ..skipped = const ChatView(skippedEarlier: true);
        final cubit = chat.cubit(record)..show(nine);
        addTearDown(cubit.close);
        cubit.readNewerOnly();
        await Future<void>.delayed(Duration.zero);
        expect(chat.skips, 1);
        expect(chat.reads, 0);
        expect(cubit.holdsKey, isFalse);
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
      cubit.deactivate();
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
        cubit.deactivate();
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
        // An address alone is sent, as the reference sends it.
        cubit.edit('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4');
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
      'the export as the reference copies it on a phone: the whole, indented; the keys and the messages apart, compact; nothing when it could not be made',
      () async {
        final chat = _Chat()
          ..exported = {
            'credentials': {'own_public_key': 'own', 'passphrase': 'p'},
            'messages': [
              {'index': 1},
            ],
          };
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        final exported = await cubit.exported();
        expect(exported, chat.exported);
        expect(
          ChatCubit.exportText(exported!),
          const JsonEncoder.withIndent('  ').convert(chat.exported),
        );
        expect(
          ChatCubit.keysText(exported),
          '{"own_public_key":"own","passphrase":"p"}',
        );
        expect(ChatCubit.messagesText(exported), '[{"index":1}]');
        chat.exportFails = true;
        expect(await cubit.exported(), isNull);
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

    /// Presses the copy of a message, whose row a box of 258 points may show only in part.
    Future<void> pressCopy(WidgetTester tester, Finder copy) async {
      tester
          .widget<IconButton>(
            find.ancestor(of: copy, matching: find.byType(IconButton)).first,
          )
          .onPressed!();
      await tester.pump();
      await tester.pump();
    }

    /// Scrolls the box of the messages until [finder] is built and shown.
    Future<void> seeMessage(
      WidgetTester tester,
      Finder finder, {
      double delta = 80,
    }) async {
      await tester.scrollUntilVisible(
        finder,
        delta,
        scrollable: find
            .descendant(
              of: find.byType(ChatPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
    }

    /// The send button: the only filled icon button of the panel.
    bool sendEnabled(WidgetTester tester) =>
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.icon is Icon &&
                    (widget.icon as Icon).icon == Icons.send,
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
        // Nothing is read, and the key is not held, while the protection is awaited or refused (review of #93).
        expect(cubit.holdsKey, isFalse);
        expect(chat.reads, 0);
        gate.complete(false);
        await tester.pump();
        await tester.pump();
        expect(find.text('Hello'), findsNothing);
        expect(cubit.holdsKey, isFalse);
        expect(cubit.polling, isFalse);
        await tester.pump(ChatCubit.pollEvery * 2);
        expect(chat.reads, 0);
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
        expect(cubit.holdsKey, isTrue);
        expect(cubit.polling, isTrue);
        expect(chat.reads, 1);
        privacyCalls.clear();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(privacyCalls, contains('screenshotOn'));
        expect(cubit.holdsKey, isFalse);
        expect(cubit.polling, isFalse);
      },
    );

    testWidgets(
      'the first read is said while it runs, read out, and gone once a read succeeded (review of #93)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final chat = _Chat()..gate = Completer<void>();
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        const reading = 'Reading the chat from Temple of Sats…';
        expect(
          tester.getSemantics(find.text(reading)),
          matchesSemantics(label: reading, isLiveRegion: true),
        );
        chat.view = pinned();
        chat.gate!.complete();
        chat.gate = null;
        await tester.pump();
        await tester.pump();
        expect(find.text(reading), findsNothing);
        semantics.dispose();
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
        // The tick for a valid signature, the cross in the error colour for one that is not, each with the reference's words.
        final valid = find.byTooltip('Verified signature by $peerNick').first;
        final invalid = find.byTooltip('Cannot verify signature of $peerNick');
        expect(invalid, findsOneWidget);
        Icon markOf(Finder tooltip) => tester.widget<Icon>(
          find.descendant(of: tooltip, matching: find.byType(Icon)),
        );
        expect(markOf(valid).icon, Icons.check);
        expect(markOf(valid).color, testTheme.extension<BullTheme>()!.success);
        expect(markOf(invalid).icon, Icons.close);
        expect(markOf(invalid).color, testTheme.extension<BullTheme>()!.error);
        expect(
          find.text('A message may be missing before this one.'),
          findsOneWidget,
        );
        for (final mark in [
          'This message was already shown above.',
          'You sent this message twice.',
          'This message may be older than it looks.',
        ]) {
          await seeMessage(tester, find.text(mark));
          expect(find.text(mark), findsOneWidget);
        }
        await seeMessage(
          tester,
          find.text('Hello, I am sending the fiat').first,
          delta: -80,
        );
        await pressCopy(tester, find.byTooltip('Copy').first);
        expect(copied, ['Hello, I am sending the fiat']);
        expect(find.text('Copied!'), findsWidgets);
        await tester.pump(const Duration(seconds: 3));
        semantics.dispose();
      },
    );

    testWidgets(
      'a message is plain text in a forced direction: no markup, nothing tappable, an image\'s metadata not read, and a copy without hidden characters (review of #93)',
      (tester) async {
        const markup = '**bold** [pay here](https://example.invalid) <b>x</b>';
        const link =
            'lightning:lnbc1qqqq bitcoin:bc1qqqq https://example.invalid';
        const image =
            '{"type":"image","url":"https://example.invalid/a.png","sha256":"00"}';
        final cleaned = ChatEntry.displayable('IBAN FR76\u200B 3000\u202E6');
        final chat = _Chat()
          ..view = pinned(
            entries: [
              entry(1, markup),
              entry(2, link),
              entry(3, image),
              entry(4, cleaned),
            ],
          );
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        for (final text in [markup, link, image, cleaned]) {
          final shown = find.text(text);
          await seeMessage(tester, shown);
          expect(shown, findsOneWidget, reason: text);
          expect(
            tester
                .widget<SelectableText>(
                  find.ancestor(
                    of: shown,
                    matching: find.byType(SelectableText),
                  ),
                )
                .textDirection,
            TextDirection.ltr,
          );
        }
        expect(find.byType(Image), findsNothing);
        // No span of the messages answers a tap: each is a plain string, never a span of its own.
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.byType(RichText),
        )) {
          paragraph.text.visitChildren((span) {
            expect(span is TextSpan ? span.recognizer : null, isNull);
            return true;
          });
        }
        for (final message in tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        )) {
          expect(message.data, isNotNull);
          expect(message.textSpan, isNull);
        }
        final copies = find.byTooltip('Copy');
        await seeMessage(tester, find.text(cleaned));
        await pressCopy(tester, copies.last);
        expect(copied, ['IBAN FR76 30006']);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      '« Read only the newer messages » chosen on an order read before them waits for the next read of the order, then skips',
      (tester) async {
        final chat = _Chat()
          ..view = const ChatView(historyTooLarge: true)
          ..skipRefused = true;
        final cubit = chat.cubit(record);
        addTearDown(cubit.close);
        await show(tester, cubit);
        await tester.tap(find.text('Read only the newer messages'));
        await tester.pump();
        expect(find.text('Reading the newer messages…'), findsOneWidget);
        expect(find.text('Read only the newer messages'), findsNothing);
        chat
          ..skipRefused = false
          ..skipped = const ChatView(skippedEarlier: true);
        // The trade screen shows a newer read of the order.
        cubit.show(nineAgain);
        await tester.pump();
        expect(chat.skips, 2);
        expect(find.text('Earlier messages are not shown.'), findsOneWidget);
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
        // One wording for both: what it means and what to do.
        const line =
            'This chat is no longer secure: your peer’s key changed. Nothing more is sent here. Do not trust payment details received from now on.';
        for (final state in [
          ChatPeerKeyBreach(pinned: peerKey),
          const ChatPeerKeyBreach(),
        ]) {
          final chat = _Chat()
            ..view = ChatView(
              peerKey: state,
              connected: true,
              pending: [ChatPendingMessage(1, 'Paid', at)],
            );
          final cubit = chat.cubit(record);
          addTearDown(cubit.close);
          await tester.pumpWidget(const SizedBox.shrink());
          await show(tester, cubit);
          expect(find.text(line), findsOneWidget);
          await tester.enterText(find.byKey(ChatPanel.field), 'Hello');
          await tester.pump();
          expect(sendEnabled(tester), isFalse);
          // The greyed « Send » says why, and « Send again » is off too.
          expect(find.byTooltip(line), findsOneWidget);
          expect(
            tester
                .widget<TradeButton>(
                  find.widgetWithText(TradeButton, 'Send again'),
                )
                .onPressed,
            isNull,
          );
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
                  // A long word without spaces, emoji, right-to-left text.
                  entry(5, 'FR7630006000011234567890189${'X' * 60}'),
                  entry(6, 'Merci 🙏👍🏽 ok'),
                  entry(7, 'شكرا جزيلا، تم الدفع'),
                  // Many messages.
                  for (var i = 8; i < 40; i++) entry(i, 'Message $i'),
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
    // Test values, not a robot's: the export's four credentials as the use case gives them.
    const encryptedKey = '-----BEGIN PGP PRIVATE KEY BLOCK-----test';
    const passphrase = 'test-passphrase-not-a-token';
    late List<String> copied;
    late List<String> privacyCalls;
    late Future<bool> Function() protection;
    late _Chat lastChat;

    setUp(() {
      copied = [];
      privacyCalls = [];
      protection = () async => true;
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

    Map<String, Object?> exportOf({bool peer = true}) => {
      'credentials': {
        'own_public_key': ownKey.armored,
        'peer_public_key': peer ? peerKey.armored : null,
        'encrypted_private_key': encryptedKey,
        'passphrase': passphrase,
      },
      'messages': [
        {'index': 1, 'plainTextMessage': 'Hello'},
      ],
    };

    Future<ChatCubit> showActions(
      WidgetTester tester, {
      ChatView? view,
      Map<String, Object?>? exported,
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
        ..exported = exported ?? exportOf();
      lastChat = chat;
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
                ChatAuditButton(cubit: cubit, coordinator: coordinatorName),
                ChatExportButton(cubit: cubit, coordinator: coordinatorName),
              ],
            ),
          ),
        ),
      );
      return cubit;
    }

    testWidgets(
      '« Export » waits busy; the dialog says the key\'s unlock while it waits, under its title (review of #93)',
      (tester) async {
        await showActions(tester);
        final gate = Completer<void>();
        lastChat.exportGate = gate;
        await tester.tap(find.text('Export'));
        await tester.pump();
        expect(
          tester
              .widget<TradeButton>(find.widgetWithText(TradeButton, 'Export'))
              .busy,
          isTrue,
        );
        // Under « Export », the wait said as « Don't trust, verify » says it (review of #161).
        const unlocking =
            'Reading your robot from Temple of Sats and unlocking its key. The first time takes a few seconds.';
        expect(find.text(unlocking), findsOneWidget);
        await tester.tap(find.text('Audit Chat'));
        await tester.pump();
        await tester.pump();
        expect(find.text("Don't trust, verify"), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ChatAuditDialog),
            matching: find.text(unlocking),
          ),
          findsOneWidget,
        );
        expect(find.text(passphrase), findsNothing);
        gate.complete();
        await settle(tester);
        expect(find.text(passphrase), findsOneWidget);
      },
    );

    testWidgets(
      '« Export » that cannot have the robot\'s key says so, as « Don\'t trust, verify » does; copied nothing, no « Copied! »; a second tap tries again (review of #161)',
      (tester) async {
        await showActions(tester);
        lastChat.exportFails = true;
        await tester.tap(find.text('Export'));
        await settle(tester);
        const failed =
            'The key of your robot could not be read from Temple of Sats.';
        expect(find.text(failed), findsOneWidget);
        expect(find.text('Copied!'), findsNothing);
        expect(copied, isEmpty);
        expect(find.textContaining('Reading your robot from'), findsNothing);
        lastChat.exportFails = false;
        await tester.tap(find.text('Export'));
        await settle(tester);
        expect(find.text(failed), findsNothing);
        expect(find.text('Copied!'), findsOneWidget);
        expect(copied, hasLength(1));
      },
    );

    testWidgets(
      '« Export » left while it waits for the key (« Order options » closed): nothing is copied, then or later; what the user copied meanwhile stays (security review of #161)',
      (tester) async {
        await showActions(tester);
        final gate = Completer<void>();
        lastChat.exportGate = gate;
        await tester.tap(find.text('Export'));
        await tester.pump();
        expect(find.textContaining('Reading your robot from'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(find.byType(ChatExportButton), findsNothing);
        await Clipboard.setData(const ClipboardData(text: 'test-iban'));
        gate.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(copied, ['test-iban']);
      },
    );

    testWidgets(
      '« Export » the clipboard refuses: said, no « Copied! » (review of #161)',
      (tester) async {
        await showActions(tester, locale: const Locale('fr'));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                throw PlatformException(code: 'refused');
              }
              return null;
            });
        await tester.tap(find.text('Exporter'));
        await settle(tester);
        expect(
          find.text('Le journal du chat n’a pas pu être copié.'),
          findsOneWidget,
        );
        expect(find.textContaining('Copié'), findsNothing);
      },
    );

    Future<void> tapInDialog(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pump();
      await tester.tap(find.text(text));
      await tester.pump();
    }

    testWidgets(
      'as the reference on a phone: « Export » copies the whole; the dialog shows the four fields, the public keys with their fingerprints, and « Keys » and « Messages » copy their JSON, on a tap only',
      (tester) async {
        await showActions(tester);
        expect(copied, isEmpty);
        await tester.tap(find.text('Export'));
        await tester.pump();
        await tester.pump();
        expect(copied, [
          const JsonEncoder.withIndent('  ').convert(exportOf()),
        ]);
        expect(find.text('Copied!'), findsOneWidget);
        await tester.tap(find.text('Audit Chat'));
        await settle(tester);
        expect(privacyCalls, contains('screenshotOff'));
        expect(find.text("Don't trust, verify"), findsOneWidget);
        for (final label in [
          'Your public key',
          'Peer public key',
          'Your encrypted private key',
          'Your private key passphrase (keep secure!)',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text(passphrase), findsOneWidget);
        expect(find.text(encryptedKey), findsOneWidget);
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
        await tapInDialog(tester, 'Keys');
        await tester.pump();
        expect(copied.last, jsonEncode(exportOf()['credentials']));
        expect(
          find.descendant(
            of: find.byType(ChatAuditDialog),
            matching: find.text('Copied!'),
          ),
          findsOneWidget,
        );
        await tapInDialog(tester, 'Messages');
        expect(copied.last, jsonEncode(exportOf()['messages']));
        privacyCalls.clear();
        await tapInDialog(tester, 'Go back');
        await settle(tester);
        expect(find.text("Don't trust, verify"), findsNothing);
        expect(privacyCalls, contains('screenshotOn'));
        expect(copied, hasLength(3));
      },
    );

    testWidgets(
      'the dialog shows nothing without the capture protection, and no peer key before the peer\'s is known',
      (tester) async {
        protection = () async => false;
        await showActions(
          tester,
          view: ChatView(ownKey: ownKey),
          exported: exportOf(peer: false),
        );
        await tester.tap(find.text('Audit Chat'));
        await settle(tester);
        expect(find.text(passphrase), findsNothing);
        expect(
          find.text(
            'Screen protection could not be turned on, so the chat stays hidden.',
          ),
          findsOneWidget,
        );
        protection = () async => true;
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(find.text('Your public key'), findsOneWidget);
        expect(find.text('Peer public key'), findsNothing);
        expect(find.text(passphrase), findsOneWidget);
      },
    );

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
  bool skipRefused = false;
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
  bool exportFails = false;
  Completer<void>? exportGate;

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
      if (skipRefused) return const Err(ChatSkipNeedsOrderRead());
      view = skipped;
      return Ok(skipped);
    },
    (record) => view,
    (record) async {
      await exportGate?.future;
      return exportFails
          ? const Err<Map<String, Object?>, ChatReadFailure>(ChatNotOpen())
          : Ok(exported);
    },
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
