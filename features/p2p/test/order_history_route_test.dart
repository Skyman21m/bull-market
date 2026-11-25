import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/coordinator_text.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/garage/last_order_lines.dart';
import 'package:p2p/src/ui/trade/trade_record_row.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport, coordinator;
import 'support/harness.dart' show testTheme;
import 'support/history_records.dart';
import 'support/trade_harness.dart' show HarnessKeys, tradeKey;

/// The history of finished orders in the Garage (#253, design note `docs/design/phase-3-order-history.md`), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the real router, records, use cases and pages, by real gestures, the records written through the feature's own repositories, nothing asked of a real coordinator.
const _net = RobosatsNetwork.testnet;

/// The `no_screenshot` plugin behind the Garage's `PrivacyScreen`: the protection is said on, so the Garage draws.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// One order the tests write: made or taken here, its coordinator, its side, where its trail stopped.
typedef _Seed = ({bool made, String alias, TradeRole role, String? position});

/// Twenty-three finished orders, the newest end last: each kind of line among the newest ten.
final List<_Seed> _finished = [
  for (var i = 0; i < 13; i++)
    (
      made: i.isEven,
      alias: i % 3 == 0 ? 'lake' : 'temple',
      role: i.isEven ? TradeRole.seller : TradeRole.buyer,
      position: switch (i % 4) {
        0 => 'succeeded',
        1 => 'expired',
        2 => 'cancelled',
        _ => 'succeeded',
      },
    ),
  // The newest ten, the newest last: the mock-up's lines, then the other ends.
  (
    made: true,
    alias: 'temple',
    role: TradeRole.seller,
    position: 'notAvailable',
  ),
  (made: false, alias: 'lake', role: TradeRole.buyer, position: null),
  (
    made: false,
    alias: 'temple',
    role: TradeRole.buyer,
    position: 'makerLostDispute',
  ),
  (made: false, alias: 'lake', role: TradeRole.buyer, position: 'publicAgain'),
  (
    made: true,
    alias: 'temple',
    role: TradeRole.seller,
    position: 'takerLostDispute',
  ),
  (made: false, alias: 'lake', role: TradeRole.buyer, position: 'cancelled'),
  (made: false, alias: 'lake', role: TradeRole.buyer, position: 'succeeded'),
  (made: true, alias: 'temple', role: TradeRole.seller, position: 'expired'),
  (made: true, alias: 'temple', role: TradeRole.buyer, position: 'cancelled'),
  (made: true, alias: 'temple', role: TradeRole.seller, position: 'succeeded'),
];

final class _App {
  final WidgetTester tester;
  final GetIt locator;
  final GoRouter router;
  final FakeTransport transport;
  final P2pLocalizations l10n;
  final GarageKeyFingerprint fingerprint;

  /// The finished orders written, the newest end first.
  final List<TradeRecord> finished = [];

  /// The screen's clock, moved a day before each record is closed.
  DateTime now;

  _App(
    this.tester,
    this.locator,
    this.router,
    this.transport,
    this.l10n,
    this.fingerprint,
    this.now,
  );

  Future<void> settle([int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Runs [run] outside the fake clock's frames, pumping until it ends.
  Future<T> wait<T>(Future<T> Function() run) async {
    late T value;
    Object? error;
    var done = false;
    unawaited(
      run().then(
        (v) {
          value = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var i = 0; i < 2000 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (error case final error?) throw error;
    if (!done) throw StateError('never done');
    return value;
  }

  HistoryRecords get records => HistoryRecords(
    locator<TradeRecordRepository>(),
    locator<TradeTrailRepository>(),
    _net,
  );

  RobotSlot robot(int index) => RobotSlot(_net, fingerprint, index);

  /// Writes [seeds], a day apart, the newest end last, robots from [firstIndex] on.
  Future<void> write(List<_Seed> seeds, {int firstIndex = 1}) => wait(() async {
    for (final (i, seed) in seeds.indexed) {
      now = now.add(const Duration(days: 1));
      final index = firstIndex + i;
      final orderId = 47000 + index * 7;
      finished.insert(
        0,
        seed.made
            ? await records.made(
                robot(index),
                orderId: orderId,
                alias: seed.alias,
                role: seed.role,
                position: seed.position ?? 'succeeded',
              )
            : await records.taken(
                robot(index),
                orderId: orderId,
                alias: seed.alias,
                role: seed.role,
                position: seed.position,
              ),
      );
    }
  });

  /// The system's back, as Android's back gesture.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle(12);
  }

  /// « Garage » of the tab, the vault read.
  Future<void> openGarage() async {
    await tester.tap(find.text(l10n.p2pNavGarage));
    await settle();
    await tester.pump(const Duration(seconds: 6));
    await settle();
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle();
  }

  Finder get seeHistory => find.text(l10n.p2pHistoryShow);
  Finder get hideHistory => find.text(l10n.p2pHistoryHide);
  Finder get seeMore => find.text(l10n.p2pHistorySeeMore);

  /// The line of [record] in the history: its first line, « #N · coordinator ».
  Finder title(TradeRecord record) => find.text(
    l10n.p2pHistoryTitle(
      '${record.orderId}',
      CoordinatorText.of(
        coordinator(record.coordinatorAlias).longAlias,
        maxCodePoints: CoordinatorText.name,
      ),
    ),
  );

  /// The whole line of [record]: what a tap reaches.
  Finder line(TradeRecord record) =>
      find.ancestor(of: title(record), matching: find.byType(InkWell)).first;

  /// The order numbers of the lines of the history shown, top to bottom.
  List<int> lines() => [
    for (final record in finished)
      if (title(record).evaluate().isNotEmpty) record.orderId,
  ];

  /// The order numbers of the trade screens in the tree, shown or not.
  List<int> tradePages() => [
    for (final element
        in find.byType(TradeScreen, skipOffstage: false).evaluate())
      BlocProvider.of<TradeCubit>(element).state.record.orderId,
  ];

  /// The nickname of robot [index] as the Garage derives it.
  String nicknameOf(int index) =>
      NetworkGarageKey(
        _net,
        tradeKey,
      ).robotOf(robot(index))?.identity.nickname ??
      (throw StateError('no robot $index'));

  static Future<_App> start(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double width = 390,
    double textScale = 1,
    bool databaseUnavailable = false,
  }) async {
    tester.view
      ..physicalSize = Size(width * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_privacyChannel, (call) async => true);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_privacyChannel, null),
    );
    final transport = FakeTransport(network: _net);
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    late final _App app;
    setUpP2pForTesting(
      locator,
      transport: transport,
      // Tor heard ready by each new listener: a request asked of a coordinator would leave.
      torStates: () => Stream.value(P2pTorState.ready),
      clock: () => app.now,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      robotKeys: HarnessKeys(),
      databaseUnavailable: databaseUnavailable,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    app = _App(
      tester,
      locator,
      router,
      transport,
      lookupP2pLocalizations(locale),
      fingerprint,
      DateTime.utc(2026, 11, 1, 9),
    );
    final imported = await app.wait(() async {
      final imported = await locator<GarageKeyRepository>().import(
        _net,
        tradeKey,
      );
      // Recorded as drawn here, so that its robots may hold trades; refused, as written, over a database that cannot be opened.
      final recorded = await locator<RobotBindingRepository>()
          .recordGeneratedKey(_net, fingerprint);
      return (imported, recorded);
    });
    expect(imported.$1, isA<Ok<void, Failure>>());
    expect(
      imported.$2,
      databaseUnavailable
          ? isA<Err<void, P2pFailure>>()
          : isA<Ok<void, P2pFailure>>(),
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
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
      ),
    );
    await app.settle();
    return app;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

/// Every paragraph of the history, its link and « See more » included, breaks its lines between words only, never inside one; the « Last order #N » lines above it are not this change's (they are left as they are).
void _expectNoWordBroken(WidgetTester tester, String reason) {
  final ours = find.descendant(
    of: find.byType(LastOrderLines),
    matching: find.byType(RichText),
  );
  final lastOrderLines = find
      .descendant(
        of: find.byType(TradeRecordRow),
        matching: find.byType(RichText),
      )
      .evaluate()
      .toSet();
  for (final paragraph in [
    for (final element in ours.evaluate())
      if (!lastOrderLines.contains(element))
        if (element.renderObject case final RenderParagraph paragraph)
          paragraph,
  ]) {
    final text = paragraph.text.toPlainText();
    final style = paragraph.text.style;
    final room = paragraph.constraints.maxWidth;
    for (final word in text.split(RegExp(r'[ \t\n]+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      expect(
        width <= room + 0.5,
        isTrue,
        reason: '$reason: « $word » ($width > $room) of « $text »',
      );
    }
  }
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final language = locale.languageCode;

    group('the history of finished orders, in $language', () {
      testWidgets(
        'the Garage arrives folded; « See history » opens ten lines, the newest end first, each kind of line with its robot; « See more » ten more, no line skipped; nothing asked of a coordinator; « Hide history » folds it',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          final l10n = app.l10n;
          await app.write(_finished);
          // Not finished, never in the history: a trade in progress, and a take that never happened.
          await app.wait(() async {
            await app.records.taken(app.robot(60), orderId: 1, closed: false);
            await app.records.taken(
              app.robot(61),
              orderId: 2,
              position: 'publicAgain',
              confirmed: false,
            );
          });
          await app.openGarage();
          // Folded: the link, no line of the history.
          expect(app.seeHistory, findsOneWidget);
          expect(app.lines(), isEmpty);
          expect(find.text(l10n.p2pHistoryTraded), findsNothing);
          await app.settle(20);
          final sent = app.transport.requests.length;

          await app.tap(app.seeHistory);
          expect(app.hideHistory, findsOneWidget);
          expect(app.seeHistory, findsNothing);
          expect(app.lines(), [
            for (final record in app.finished.take(10)) record.orderId,
          ]);
          // Each line in order, top to bottom.
          final tops = [
            for (final record in app.finished.take(10))
              tester.getTopLeft(app.title(record)).dy,
          ];
          expect(tops, [...tops]..sort());
          // What each line says: its side, made or taken here, the day of its end, its own robot, how it ended.
          final formats = P2pFormats(l10n);
          final ends = {
            'succeeded': l10n.p2pHistoryTraded,
            'expired': l10n.p2pHistoryExpired,
            'cancelled': l10n.p2pHistoryCancelled,
            'makerLostDispute': l10n.p2pHistoryDispute,
            'takerLostDispute': l10n.p2pHistoryDispute,
            'publicAgain': l10n.p2pHistoryEndUnknown,
            'notAvailable': l10n.p2pHistoryEndUnknown,
            null: l10n.p2pHistoryEndUnknown,
          };
          final newest = _finished.reversed.take(10).toList();
          for (final (i, record) in app.finished.take(10).indexed) {
            final seed = newest[i];
            final line = app.line(record);
            final index = record.robot.accountIndex;
            expect(
              find.descendant(
                of: line,
                matching: find.text(
                  l10n.p2pHistoryFacts(
                    seed.role == TradeRole.seller
                        ? l10n.p2pHistorySell
                        : l10n.p2pHistoryBuy,
                    seed.made
                        ? l10n.p2pHistoryMadeHere
                        : l10n.p2pHistoryTakenHere,
                    formats.day(record.closedAt ?? DateTime(0)),
                  ),
                ),
              ),
              findsOneWidget,
              reason: '${record.orderId}',
            );
            expect(
              find.descendant(
                of: line,
                matching: find.text(
                  l10n.p2pHistoryRobotNamed(
                    '${l10n.p2pGarageRobotLabel} #$index',
                    app.nicknameOf(index),
                  ),
                ),
              ),
              findsOneWidget,
              reason: '${record.orderId}',
            );
            expect(
              find.descendant(
                of: line,
                matching: find.text(ends[seed.position] ?? ''),
              ),
              findsOneWidget,
              reason: '${record.orderId} ${seed.position}',
            );
          }
          // Opening asked nothing of any coordinator.
          await app.settle(20);
          expect(app.transport.requests.length, sent);

          await app.tap(app.seeMore);
          expect(app.lines(), [
            for (final record in app.finished.take(20)) record.orderId,
          ]);
          await app.tap(app.seeMore);
          expect(app.lines(), [
            for (final record in app.finished) record.orderId,
          ]);
          expect(app.lines(), hasLength(23));
          expect(app.seeMore, findsNothing);
          expect(tester.takeException(), isNull);

          await app.tap(app.hideHistory);
          expect(app.lines(), isEmpty);
          expect(app.seeHistory, findsOneWidget);
          // Opened again: the first ten only.
          await app.tap(app.seeHistory);
          expect(app.lines(), hasLength(10));
          expect(app.transport.requests.length, sent);
          await app.close();
        },
      );

      testWidgets(
        'a line tapped twice opens its order once; coming back, the history is folded; left and shown again, folded',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.write(_finished.sublist(10));
          await app.openGarage();
          await app.tap(app.seeHistory);
          // An expired order made here: the third line.
          final expired = app.finished[2];
          expect(app.lines(), contains(expired.orderId));
          final at = tester.getCenter(app.title(expired));
          await tester.tapAt(at);
          await tester.pump(const Duration(milliseconds: 16));
          await tester.tapAt(at);
          await app.settle(12);
          expect(app.tradePages(), [expired.orderId]);
          await app.back();
          expect(app.tradePages(), isEmpty);
          expect(app.seeHistory, findsOneWidget);
          expect(app.lines(), isEmpty);
          // Opened again, a tap opens again.
          await app.tap(app.seeHistory);
          await tester.tap(app.title(app.finished.first));
          await app.settle(12);
          expect(app.tradePages(), [app.finished.first.orderId]);
          await app.back();
          // The app hidden and shown again: folded, as the Garage Key shown is hidden then.
          await app.tap(app.seeHistory);
          expect(app.lines(), isNotEmpty);
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
            await tester.pump();
          }
          await app.settle();
          expect(app.lines(), isEmpty);
          expect(app.seeHistory, findsOneWidget);
          // The Garage left for the offers, then shown again: folded.
          await app.tap(app.seeHistory);
          expect(app.lines(), isNotEmpty);
          await tester.tap(find.text(app.l10n.p2pNavOffers));
          await app.settle();
          await app.openGarage();
          expect(app.lines(), isEmpty);
          expect(app.seeHistory, findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'nothing more than the two « Last order #N » lines: no link; no finished order: neither',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openGarage();
          expect(app.seeHistory, findsNothing);
          expect(find.text(app.l10n.p2pRobotLastOrder('47007')), findsNothing);
          await app.write([
            (
              made: true,
              alias: 'temple',
              role: TradeRole.seller,
              position: 'expired',
            ),
            (
              made: false,
              alias: 'lake',
              role: TradeRole.buyer,
              position: 'succeeded',
            ),
          ]);
          await app.settle();
          for (final record in app.finished) {
            expect(
              find.text(app.l10n.p2pRobotLastOrder('${record.orderId}')),
              findsOneWidget,
            );
          }
          expect(app.seeHistory, findsNothing);
          // A third: the link.
          await app.write([
            (
              made: true,
              alias: 'temple',
              role: TradeRole.seller,
              position: 'succeeded',
            ),
          ], firstIndex: 3);
          await app.settle();
          expect(app.seeHistory, findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'records that cannot be read: said once, no link, never « no order »',
        (tester) async {
          final app = await _App.start(
            tester,
            locale: locale,
            databaseUnavailable: true,
          );
          await app.openGarage();
          expect(find.text(app.l10n.p2pRobotRecordsUnreadable), findsOneWidget);
          expect(app.seeHistory, findsNothing);
          await app.close();
        },
      );

      for (final textScale in [1.0, 2.0, 3.0]) {
        testWidgets(
          'it fits at 320 points and text size $textScale: no overflow, no word cut',
          (tester) async {
            final app = await _App.start(
              tester,
              locale: locale,
              width: 320,
              textScale: textScale,
            );
            await app.write(_finished);
            // Every layout error of the Garage, but the account navigator's above the lines, which overflows at 320 points from twice the text size before this change (not this change's).
            final errors = <FlutterErrorDetails>[];
            final previous = FlutterError.onError;
            FlutterError.onError = errors.add;
            try {
              await app.openGarage();
              await app.tap(app.seeHistory);
              await app.tap(app.seeMore);
              for (final record in app.finished.take(20)) {
                await tester.ensureVisible(app.title(record));
                await tester.pump();
              }
            } finally {
              FlutterError.onError = previous;
            }
            expect([
              for (final error in errors)
                if (!'$error'.contains('account_navigator.dart')) '$error',
            ], isEmpty);
            expect(app.lines(), hasLength(20));
            _expectNoWordBroken(tester, '$language ×$textScale');
            await app.close();
          },
        );
      }
    });
  }
}
