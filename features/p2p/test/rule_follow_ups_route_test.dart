import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// Follow-ups of the owner's payment rule (#283; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis, « As #283 wrote it ») on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), by the user's gestures, in English and in French, on a phone of 320 points with a text at three times its size: the real router, records, use cases, state machine and trade screen; the coordinator played by `ScriptedMakerCoordinator` (never a real one), the wallet `FakeP2pWalletPort` (no price service, no swap service, no money).
///
/// (1) « Submit », « Generate Invoice », « Confirm … sent » and its dialog's « Confirm » ignore a tap just after the rule's lines moved them ([MovedTapGuard]), and take the next one. (2) After a read of the Bull wallet's price that failed, a status the coordinator makes come and go (15 ↔ 13) reads it again only once that read is 3 minutes old; « Retry » always reads.
///
/// The order: 100 EUR bought at a premium of 0, made and taken at the coordinator's 50,000 per bitcoin: 200,000 sats, the maker fee 0.025 %, so the coordinator pays 199,950 at 6, an invoice of 199,750 with the default routing budget; the Bull wallet's price 50,000.
const _net = RobosatsNetwork.testnet;

/// The scripted maker coordinator for every robot's request and the anonymous information and limits; the book, anonymous and unknown to it, to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final FakeTransport rest = FakeTransport(network: _net);

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final path = request.url.path;
    if (request.robot != null ||
        path == '/api/info/' ||
        path == '/api/limits/' ||
        path == '/api/make/') {
      return maker.send(request);
    }
    return rest.send(request);
  }
}

final class _App {
  final WidgetTester tester;
  final GoRouter router;
  final ScriptedMakerCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  final Locale locale;
  final void Function(Duration) advance;
  final DateTime Function() clock;
  late TradeRecord record;

  _App(
    this.tester,
    this.router,
    this.coordinator,
    this.wallet,
    this.locale,
    this.advance,
    this.clock,
  );

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats =>
      P2pFormats.of(tester.element(find.byType(TradeScreen)));

  ScriptedMadeOrder get order => coordinator.order(record.orderId);

  Future<void> settle([int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

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
    for (var i = 0; i < 400 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (error case final error?) throw error;
    if (!done) throw StateError('never done');
    return value;
  }

  /// Waits, the clock running, until [finder] shows.
  Future<void> waitFor(Finder finder) async {
    for (var i = 0; i < 240; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  /// Waits, the clock running, until [done] holds.
  Future<void> waitUntil(bool Function() done, String what) async {
    for (var i = 0; i < 240; i++) {
      if (done()) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never: $what');
  }

  /// [finder] brought into view by a scroll (which never sets the guard off), then tapped at once: no time passes, so a move of the layout just before is less than [MovedTapGuard.afterMove] old.
  Future<void> tapNow(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  /// [finder] tapped once the guard's delay has passed since anything moved.
  Future<void> tapLater(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump(MovedTapGuard.afterMove);
    await tester.tap(finder);
    await tester.pump();
  }

  /// The trade screen of the order, opened as « Active trades » opens it.
  Future<void> openTrade() async {
    unawaited(
      router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(record)),
    );
    await settle(12);
  }

  /// The order of the tests made in EUR at 50,000 and bought, its bond locked and taken by robot 5 at the same price: at 6; on a phone of 320 points, the text at three times its size.
  static Future<_App> start(
    WidgetTester tester, {
    required P2pWalletBitcoinRate rate,
    required Locale locale,
  }) async {
    tester.view
      ..physicalSize = const Size(320 * 3, 2400 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    FakeSecureStoragePlatform().install();
    var now = DateTime.utc(2026, 11, 14, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => now,
    );
    final euro =
        RobosatsCurrency.fromCode('EUR') ?? (throw StateError('no EUR'));
    coordinator.prices[euro.id] = 50000;
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))..rate = rate;
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
      torStates: () => tor.stream,
      clock: () => now,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: wallet,
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final app = _App(
      tester,
      router,
      coordinator,
      wallet,
      locale,
      (by) => now = now.add(by),
      () => now,
    );
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await app.wait(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    await tester.pumpWidget(routerHarness(router, locale: locale));
    tor.add(P2pTorState.ready);
    await app.settle();
    final request = MakeHarness.request(premium: 0, currency: euro);
    app.record = switch (await app.wait(
      () => locator<MakeOrderUsecase>().execute(
        request,
        coordinator: coordinator.coordinator,
        network: _net,
        seen: MakePriceSeen.of(
          currency: request.currency,
          coordinatorPrice: 50000,
        ),
      ),
    )) {
      Ok(value: MakeStarted(:final record)) => record,
      final other => throw StateError('$other'),
    };
    coordinator
      ..lockMakerBond(app.record.orderId)
      ..take(app.record.orderId, TradeHarness.robotsOf(_net)[5]);
    return app;
  }

  /// The trade moved by the coordinator to [statuses] in turn, each shown for 10 seconds before the next.
  Future<void> moveTo(List<int> statuses) async {
    for (final status in statuses) {
      order.status = status;
      for (var i = 0; i < 40; i++) {
        advance(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
  }

  /// An invoice of the test for what the coordinator asks at 6 with the default routing budget (199,750 sats), known to its decoder, typed into the payout field; then the guard's delay, so that the check's table it brought above « Submit » is past.
  Future<void> enterInvoice() async {
    final invoice = Bolt11TestInvoice(
      network: Bolt11Network.testnet,
      sats: 199750,
      seed: 83,
      createdAt: clock(),
      expiry: const Duration(days: 2),
    );
    coordinator.decoder.add(invoice);
    final field = find.byKey(PayoutPanel.invoiceField);
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, invoice.text);
    await settle();
    await waitFor(find.text(l10n.p2pTradeInvoiceExpires));
    await tester.pump(MovedTapGuard.afterMove);
  }

  Finder get submit => find.widgetWithText(TradeButton, l10n.p2pPayoutSubmit);

  Finder get generate =>
      find.widgetWithText(TradeButton, l10n.p2pPayoutWalletGenerateInvoice);

  Finder get gapLine => find.text(l10n.p2pPayoutBreakdownGap);

  Finder get reading => find.text(l10n.p2pPayoutRateReading);

  Finder get confirmSent => find.widgetWithText(
    TradeButton,
    l10n.p2pEndConfirmSent(
      formats.amount(FiatAmount.tryCreate(100) ?? fail('100')),
      'EUR',
    ),
  );

  Finder get dialog => find.byType(Dialog);

  Finder get dialogConfirm => find.descendant(
    of: dialog,
    matching: find.widgetWithText(TradeButton, l10n.p2pEndConfirm),
  );

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;

    group('point 1, a tap just after the rule\'s lines moved a button, $code', () {
      testWidgets(
        'at 6, the Bull wallet\'s price read while an invoice waits in the field: when its answer brings the gap line into the breakdown, a tap on « Submit » at once gives nothing, the button still enabled; the next tap gives the payout',
        (tester) async {
          final app = await _App.start(
            tester,
            rate: P2pWalletRateRead(50000),
            locale: locale,
          );
          final held = Completer<void>();
          app.wallet.rateHeld = held;
          await app.openTrade();
          await app.waitFor(app.reading);
          await app.enterInvoice();
          expect(app.gapLine, findsNothing);
          final before = tester.getTopLeft(app.submit);
          held.complete();
          await tester.pump();
          await tester.pump();
          expect(app.gapLine, findsOneWidget);
          expect(app.reading, findsNothing);
          expect(tester.getTopLeft(app.submit), isNot(before));
          // Aimed at what stood there a moment before: nothing given; the button still enabled.
          await app.tapNow(app.submit);
          await app.settle(2);
          expect(app.order.payoutHash, isNull);
          expect(app.order.status, 6);
          expect(tester.widget<TradeButton>(app.submit).onPressed, isNotNull);
          await app.tapLater(app.submit);
          await app.waitUntil(() => app.order.payoutHash != null, 'given');
          expect(app.order.status, 7);
          expect(app.wallet.paid, isEmpty);
          await app.close();
        },
      );

      testWidgets(
        'at 6, « Generate Invoice » just after the gap line came: the tap at once asks the wallet nothing, the next one asks it',
        (tester) async {
          final app = await _App.start(
            tester,
            rate: P2pWalletRateRead(50000),
            locale: locale,
          );
          final held = Completer<void>();
          app.wallet
            ..rateHeld = held
            ..scriptInvoice(const Err(P2pWalletUnavailable()));
          await app.openTrade();
          await app.waitFor(app.reading);
          await tester.ensureVisible(app.generate);
          await app.settle();
          await tester.pump(MovedTapGuard.afterMove);
          held.complete();
          await tester.pump();
          await tester.pump();
          expect(app.gapLine, findsOneWidget);
          await app.tapNow(app.generate);
          await app.settle(2);
          expect(app.wallet.invoicesAsked, isEmpty);
          await app.tapLater(app.generate);
          await app.settle();
          expect(app.wallet.invoicesAsked, hasLength(1));
          await app.close();
        },
      );

      testWidgets(
        'at 9 with the price read anew: when its answer takes « Reading… » away, a tap on « Confirm … sent » at once opens nothing, the next one opens the dialog; there, when the app comes back 4 minutes later and the rule\'s lines (« Reading… ») move « Confirm », a tap on it at once sends nothing, the next one sends « fiat sent »',
        (tester) async {
          final app = await _App.start(
            tester,
            rate: P2pWalletRateRead(50000),
            locale: locale,
          );
          await app.openTrade();
          await app.waitFor(app.gapLine);
          await app.enterInvoice();
          await app.tapLater(app.submit);
          await app.waitUntil(() => app.order.payoutHash != null, 'given');
          // The escrow locked (7 → 9), the price 4 minutes old: 9 reads it again, held.
          app.advance(const Duration(minutes: 4));
          final held = Completer<void>();
          app.wallet.rateHeld = held;
          app.coordinator.lockEscrow(app.record.orderId);
          await app.waitFor(app.reading);
          await app.waitFor(app.confirmSent);
          // The page scrolled up to « Reading… », not at its end: the line that goes then moves the button on the screen (at the page's end the scroll would follow it, the button staying in place, #267).
          await tester.ensureVisible(app.reading);
          await app.settle();
          final before = tester.getTopLeft(app.confirmSent);
          held.complete();
          await tester.pump();
          await tester.pump();
          expect(app.reading, findsNothing);
          expect(tester.getTopLeft(app.confirmSent), isNot(before));
          await app.tapNow(app.confirmSent);
          await app.settle(2);
          expect(app.dialog, findsNothing);
          await app.tapLater(app.confirmSent);
          await app.waitFor(app.dialogConfirm);
          await app.settle();
          await tester.ensureVisible(app.dialogConfirm);
          await tester.pump(MovedTapGuard.afterMove);
          final shown = tester.getTopLeft(app.dialogConfirm);
          // The app left with the dialog open and back 4 minutes later: the step appears anew with a price 3 minutes old, read again (held), and the dialog's lines, which follow the rule's state, say « Reading… ».
          final again = Completer<void>();
          app.wallet.rateHeld = again;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          app.advance(const Duration(minutes: 4));
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.pump();
          expect(
            find.descendant(of: app.dialog, matching: app.reading),
            findsOneWidget,
          );
          expect(tester.getTopLeft(app.dialogConfirm), isNot(shown));
          await app.tapNow(app.dialogConfirm);
          await app.settle(2);
          expect(app.dialog, findsOneWidget);
          expect(app.order.fiatSent, isFalse);
          again.complete();
          await app.settle(2);
          await app.tapLater(app.dialogConfirm);
          await app.waitUntil(() => app.order.fiatSent, 'fiat sent');
          await app.settle();
          expect(app.dialog, findsNothing);
          expect(app.order.status, 10);
          await app.close();
        },
      );

      testWidgets(
        'nothing moved: « Submit », « Confirm … sent » and « Confirm » each take the first tap',
        (tester) async {
          final app = await _App.start(
            tester,
            rate: P2pWalletRateRead(50000),
            locale: locale,
          );
          await app.openTrade();
          await app.waitFor(app.gapLine);
          await app.enterInvoice();
          await app.settle();
          await tester.ensureVisible(app.submit);
          await tester.pump();
          await tester.tap(app.submit);
          await tester.pump();
          await app.waitUntil(() => app.order.payoutHash != null, 'given');
          app.coordinator.lockEscrow(app.record.orderId);
          await app.waitFor(app.confirmSent);
          await app.settle();
          await tester.pump(MovedTapGuard.afterMove);
          await tester.ensureVisible(app.confirmSent);
          await tester.pump();
          await tester.tap(app.confirmSent);
          await tester.pump();
          await app.waitFor(app.dialogConfirm);
          await app.settle();
          await tester.ensureVisible(app.dialogConfirm);
          await tester.pump();
          await tester.tap(app.dialogConfirm);
          await tester.pump();
          await app.waitUntil(() => app.order.fiatSent, 'fiat sent');
          expect(app.order.status, 10);
          await app.close();
        },
      );
    });

  }
}
