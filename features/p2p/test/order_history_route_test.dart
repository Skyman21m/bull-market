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
import 'package:p2p/src/presentation/order_history_cubit.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/garage/account_navigator.dart';
import 'package:p2p/src/ui/garage/robot_nickname.dart' show RobotNickname;
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
import 'support/lean_confirmation.dart' show loadAppFont;
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
    bool history = true,
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
    // Without the history's cubit, the Garage draws no history at all (`P2pRouter`): the Garage as it was before #253.
    if (!history) locator.unregister<OrderHistoryCubit>();
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

/// Every paragraph of the robot navigator, of the « Last order #N » lines and of the history, its link and « See more » included, breaks its lines between words only, never inside one (#253; the navigator and the lines since #273): an order's number, a coordinator's name and « Robot #N » are never cut.
void _expectNoWordBroken(WidgetTester tester, String reason, {Finder? of}) {
  final ours = find.descendant(
    of:
        of ??
        find.byWidgetPredicate(
          (widget) => widget is LastOrderLines || widget is AccountNavigator,
        ),
    matching: find.byType(RichText),
  );
  expect(ours, findsWidgets);
  for (final paragraph in [
    for (final element in ours.evaluate())
      if (element.renderObject case final RenderParagraph paragraph) paragraph,
  ]) {
    final text = paragraph.text.toPlainText();
    // Drawn whole: neither elided nor cut after its last line.
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$reason: « $text »');
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

/// The requests sent to the coordinators, one line each (method, host, path), sorted: what two Garages may be compared on, whatever the order the requests left in.
List<String> _sentLines(FakeTransport transport) => [
  for (final request in transport.requests)
    '${request.method.name} ${request.url.host}${request.url.path}',
]..sort();

void main() {
  testWidgets(
    'reading the history when the Garage opens asks nothing of any coordinator: the same requests as a Garage without the history (#273)',
    (tester) async {
      final sent = <bool, List<String>>{};
      for (final history in [false, true]) {
        final app = await _App.start(tester, history: history);
        await app.write(_finished);
        await app.openGarage();
        await app.settle(20);
        expect(app.seeHistory, history ? findsOneWidget : findsNothing);
        sent[history] = _sentLines(app.transport);
        await app.close();
        // Its database closed before the next Garage opens its own.
        await app.wait(() => app.locator.reset());
      }
      expect(sent[false], isNotNull);
      expect(sent[true], sent[false]);
    },
  );

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
            // Its key on a line of its own (#81, decided on 2026-11-26): the seam's key 0 of the words is the key the test stored; then its robot.
            expect(
              find.descendant(
                of: line,
                matching: find.text(l10n.p2pGarageKeyNumber(0)),
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
        'the day a line shows is the day its end was read, not the day of the take (#273)',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.write(_finished.sublist(10));
          // Taken on one day, its end read three days later.
          final taken = app.now.add(const Duration(days: 1));
          app.now = taken;
          final record = await app.wait(
            () => app.records.taken(
              app.robot(40),
              orderId: 48001,
              position: 'succeeded',
              beforeClose: () => app.now = app.now.add(const Duration(days: 3)),
            ),
          );
          app.finished.insert(0, record);
          final formats = P2pFormats(app.l10n);
          final closedAt = record.closedAt ?? DateTime(0);
          expect(formats.day(record.takenAt), isNot(formats.day(closedAt)));
          await app.openGarage();
          await app.tap(app.seeHistory);
          final line = app.line(record);
          Finder facts(DateTime day) => find.descendant(
            of: line,
            matching: find.text(
              app.l10n.p2pHistoryFacts(
                app.l10n.p2pHistoryBuy,
                app.l10n.p2pHistoryTakenHere,
                formats.day(day),
              ),
            ),
          );
          expect(facts(closedAt), findsOneWidget);
          expect(facts(record.takenAt), findsNothing);
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
            // Every layout error of the Garage, the robot navigator's included (it overflowed at 320 points from twice the text size before #273).
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
            expect([for (final error in errors) '$error'], isEmpty);
            expect(tester.takeException(), isNull);
            expect(app.lines(), hasLength(20));
            _expectNoWordBroken(tester, '$language ×$textScale');
            // « Robot #N » drawn whole, on one line, between the two arrows.
            final label = tester.getRect(
              find.text('${app.l10n.p2pGarageRobotLabel} #0'),
            );
            final back = tester.getRect(
              find.byTooltip(app.l10n.p2pGaragePreviousAccount),
            );
            final forward = tester.getRect(
              find.byTooltip(app.l10n.p2pGarageNextAccount),
            );
            expect(label.left >= back.right, isTrue, reason: '$label');
            expect(label.right <= forward.left, isTrue, reason: '$label');
            expect(forward.right <= 320, isTrue, reason: '$forward');
            // Every target a finger aims at stays at least 44 points each way: the arrows, the « Last order #N » lines and the history's lines.
            for (final tooltip in [
              app.l10n.p2pGaragePreviousAccount,
              app.l10n.p2pGarageNextAccount,
            ]) {
              final size = tester.getSize(
                find.ancestor(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(IconButton),
                ),
              );
              expect(
                size.width >= 44 && size.height >= 44,
                isTrue,
                reason: '$tooltip $size',
              );
            }
            final rows = [
              ...find.byType(TradeRecordRow).evaluate(),
              for (final record in app.finished.take(20))
                app.line(record).evaluate().single,
            ];
            expect(rows, hasLength(22));
            for (final row in rows) {
              final size = switch (row.renderObject) {
                final RenderBox box => box.size,
                _ => Size.zero,
              };
              expect(
                size.width >= 44 && size.height >= 44,
                isTrue,
                reason: '$size',
              );
            }
            await app.close();
          },
        );
      }

      testWidgets(
        'at 360 points and the normal text size, the robot navigator and the « Last order #N » lines are laid out exactly as before #273',
        (tester) async {
          final app = await _App.start(tester, locale: locale, width: 360);
          await app.write(_finished.sublist(18));
          await app.openGarage();
          expect(tester.takeException(), isNull);
          final l10n = app.l10n;
          // Measured on `main` at 7a15229b9, before #273, with the test font.
          final before = _layoutBefore[language] ?? const <Rect>[];
          final label = find.text('${l10n.p2pGarageRobotLabel} #0');
          final lines = [
            for (final record in app.finished)
              if (find
                  .text(l10n.p2pRobotLastOrder('${record.orderId}'))
                  .evaluate()
                  .isNotEmpty)
                record,
          ];
          expect(lines, hasLength(2));
          final now = [
            tester.getRect(find.byTooltip(l10n.p2pGaragePreviousAccount)),
            tester.getRect(find.byTooltip(l10n.p2pGarageNextAccount)),
            tester.getRect(label),
            for (final record in lines) ...[
              tester.getRect(
                find.ancestor(
                  of: find.text(l10n.p2pRobotLastOrder('${record.orderId}')),
                  matching: find.byType(TradeRecordRow),
                ),
              ),
              tester.getRect(
                find.text(l10n.p2pRobotLastOrder('${record.orderId}')),
              ),
              tester.getRect(
                find.text(
                  CoordinatorText.of(
                    coordinator(record.coordinatorAlias).longAlias,
                    maxCodePoints: CoordinatorText.name,
                  ),
                ),
              ),
            ],
          ];
          expect(now, before);
          await app.close();
        },
      );
    });
  }

  // Follow-ups of #270, #273 and #283: the robot panel's title and the robot's nickname with a large text.
  for (final (locale, language) in const [
    (Locale('en'), 'en'),
    (Locale('fr'), 'fr'),
  ]) {
    group('the robot\'s nickname and its panel\'s title, in $language', () {
      /// The title of the robot's panel and the nickname above the robot's avatar.
      (Finder, Finder) titleAndNickname(_App app) => (
        find.text(app.l10n.p2pRobotCoordinatorTitle),
        find.descendant(
          of: find.byType(RobotNickname),
          matching: find.byType(Text),
        ),
      );

      for (final textScale in [1.0, 2.0, 3.0]) {
        testWidgets(
          'at 320 points and text size $textScale: the title and the nickname break no word that fits a line, elide nothing, and are said as before',
          (tester) async {
            await loadAppFont();
            final app = await _App.start(
              tester,
              locale: locale,
              width: 320,
              textScale: textScale,
            );
            await app.openGarage();
            expect(tester.takeException(), isNull);
            final (title, nickname) = titleAndNickname(app);
            expect(title, findsOneWidget);
            expect(nickname, findsOneWidget);
            final name = tester.widget<Text>(nickname).data ?? '';
            expect(name, isNotEmpty);
            for (final (finder, what) in [
              (title, 'title'),
              (nickname, 'nickname'),
            ]) {
              await tester.ensureVisible(finder);
              await tester.pump();
              _expectNoWordBroken(
                tester,
                '$language ×$textScale, $what',
                of: finder,
              );
              expect(
                tester.getRect(finder).right <= 320,
                isTrue,
                reason: '$what ${tester.getRect(finder)}',
              );
            }
            // A screen reader says the title as a header, and the nickname, in their words.
            expect(
              tester.getSemantics(title),
              isSemantics(
                label: app.l10n.p2pRobotCoordinatorTitle,
                isHeader: true,
              ),
            );
            expect(tester.getSemantics(nickname), isSemantics(label: name));
            await app.close();
          },
        );
      }

      testWidgets(
        'at 360 points and the normal text size, the title, the nickname and « See history » / « Hide history » are laid out exactly as before the follow-ups of #270, #273 and #283',
        (tester) async {
          await loadAppFont();
          final app = await _App.start(tester, locale: locale, width: 360);
          await app.write(_finished.sublist(18));
          await app.openGarage();
          expect(tester.takeException(), isNull);
          final (title, nickname) = titleAndNickname(app);
          Finder buttonOf(Finder text) =>
              find.ancestor(of: text, matching: find.byType(TextButton));
          final folded = [
            tester.getRect(title),
            tester.getRect(nickname),
            tester.getRect(find.byType(RobotNickname)),
            tester.getRect(buttonOf(app.seeHistory)),
            tester.getRect(app.seeHistory),
          ];
          await app.tap(app.seeHistory);
          final open = [
            tester.getRect(buttonOf(app.hideHistory)),
            tester.getRect(app.hideHistory),
          ];
          expect([...folded, ...open], _panelLayoutBefore[language]);
          await app.close();
        },
      );
    });
  }
}

/// The places of the robot panel's title, of the robot's nickname (its words, then with its two bolts), of « See history » (its button, its words), then of « Hide history » (its button, its words), at 360 points and the normal text size, with the app's font, as `main` drew them before the follow-ups of #270, #273 and #283 (0e8bb8a84).
const _panelLayoutBefore = <String, List<Rect>>{
  'en': [
    Rect.fromLTWH(33.0, 616.0, 294.0, 21.0),
    Rect.fromLTWH(97.55850219726562, 147.0, 164.88299560546875, 20.0),
    Rect.fromLTWH(73.55850219726562, 145.0, 212.88299560546875, 24.0),
    Rect.fromLTWH(122.68976211547852, 535.0, 114.62047576904297, 48.0),
    Rect.fromLTWH(134.68976211547852, 550.5, 66.62047576904297, 17.0),
    Rect.fromLTWH(120.14974212646484, 535.0, 119.70051574707031, 48.0),
    Rect.fromLTWH(132.14974212646484, 550.5, 71.70051574707031, 17.0),
  ],
  'fr': [
    Rect.fromLTWH(33.0, 616.0, 294.0, 21.0),
    Rect.fromLTWH(97.55850219726562, 147.0, 164.88299560546875, 20.0),
    Rect.fromLTWH(73.55850219726562, 145.0, 212.88299560546875, 24.0),
    Rect.fromLTWH(109.51966857910156, 535.0, 140.96066284179688, 48.0),
    Rect.fromLTWH(121.51966857910156, 550.5, 92.96066284179688, 17.0),
    Rect.fromLTWH(95.68958282470703, 535.0, 168.62083435058594, 48.0),
    Rect.fromLTWH(107.68958282470703, 550.5, 120.62083435058594, 17.0),
  ],
};

/// The places of the robot navigator's arrows and label, then of each « Last order #N » line, its label and its coordinator's name, top to bottom, at 360 points and the normal text size, as `main` drew them before #273 (7a15229b9).
const _layoutBefore = {
  'en': [
    Rect.fromLTWH(78, 373, 40, 40),
    Rect.fromLTWH(242, 373, 40, 40),
    Rect.fromLTWH(122, 382.5, 116, 21),
    Rect.fromLTWH(16, 429, 328, 61),
    Rect.fromLTWH(60, 441, 246.5, 21),
    Rect.fromLTWH(60, 462, 175, 16),
    Rect.fromLTWH(16, 490, 328, 61),
    Rect.fromLTWH(60, 502, 246.5, 21),
    Rect.fromLTWH(60, 523, 125, 16),
  ],
  'fr': [
    Rect.fromLTWH(78, 389, 40, 40),
    Rect.fromLTWH(242, 389, 40, 40),
    Rect.fromLTWH(122, 398.5, 116, 21),
    Rect.fromLTWH(16, 445, 328, 82),
    Rect.fromLTWH(60, 457, 260, 42),
    Rect.fromLTWH(60, 499, 175, 16),
    Rect.fromLTWH(16, 527, 328, 82),
    Rect.fromLTWH(60, 539, 260, 42),
    Rect.fromLTWH(60, 581, 125, 16),
  ],
};
