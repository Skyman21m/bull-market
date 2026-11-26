import 'dart:async';
import 'dart:convert';

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
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/amount_row.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// At 15 (the payout failed, a new invoice asked), the new invoice against the one asked at 6 or 8 for the same contract (#281; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis, point 4), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`) by the user's gestures, in English and in French: the real router, records, use cases, state machine and trade screen; the coordinator played by `ScriptedMakerCoordinator` for an order made here and `ScriptedCoordinator` for an order taken here (never a real one); the wallet `FakeP2pWalletPort` (no price service, no swap service, no money).
///
/// The order made here: 100 EUR (or GBP, which the Bull wallet does not price) bought at a premium of 0, made and taken at the coordinator's 50,000 per bitcoin: 200,000 sats, the maker fee 0.025 %, so the coordinator pays 199,950 at 6 (`round(200,000 − 50)`); the Bull wallet's price 50,000, so a gap of −0.03 % at 6.
const _net = RobosatsNetwork.testnet;

/// The scripted maker coordinator for every robot's request and the anonymous information and limits; the book, anonymous and unknown to it, to an empty fake.
final class _MakerCoordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final FakeTransport rest = FakeTransport(network: _net);

  _MakerCoordinators(this.maker);

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
  final GetIt locator;
  final ScriptedMakerCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  final Locale locale;
  final void Function(Duration) advance;
  late TradeRecord record;

  _App(
    this.tester,
    this.router,
    this.locator,
    this.coordinator,
    this.wallet,
    this.locale,
    this.advance,
  );

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats =>
      P2pFormats.of(tester.element(find.byType(TradeScreen)));

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

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    // A guarded button just shown (« Pay ») ignores taps for a moment (security review of #291, B1): the tap comes later, as a user's.
    if (find
        .ancestor(of: finder, matching: find.byType(MovedTapGuard))
        .evaluate()
        .isNotEmpty) {
      await tester.pump(MovedTapGuard.afterMove);
    }
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

  /// The trade screen closed, back to the tab.
  Future<void> closeTrade() async {
    router.pop();
    await settle(12);
  }

  /// What a restart does to the rule's memory: a new one (in memory only, never on disk, #204).
  void restart() {
    locator
      ..unregister<PayoutRateMemory>()
      ..registerLazySingleton<PayoutRateMemory>(PayoutRateMemory.new);
  }

  /// The order of the tests made in [currency] at 50,000 and bought, its bond locked and taken by robot 5 at the same price: at 6.
  static Future<_App> start(
    WidgetTester tester, {
    String currency = 'EUR',
    P2pWalletBitcoinRate? rate,
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 14, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    final ofOrder =
        RobosatsCurrency.fromCode(currency) ??
        (throw StateError('no currency $currency'));
    coordinator.prices[ofOrder.id] = 50000;
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(50000);
    setUpP2pForTesting(
      locator,
      transport: _MakerCoordinators(coordinator),
      torStates: () => tor.stream,
      clock: () => clock,
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
      locator,
      coordinator,
      wallet,
      locale,
      (by) => clock = clock.add(by),
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
    final request = MakeHarness.request(premium: 0, currency: ofOrder);
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

  /// The order's `last_satoshis`: what the coordinator fixed for the contract, from which it computes what it pays (`Logics.payout_amount`).
  set last(int sats) => coordinator.order(record.orderId).lastSatoshis = sats;

  /// The trade moved by the coordinator to [statuses] in turn, each shown before the next.
  Future<void> moveTo(List<int> statuses, Finder shownLast) async {
    for (final status in statuses) {
      coordinator.order(record.orderId).status = status;
      for (var i = 0; i < 40; i++) {
        advance(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await waitFor(shownLast);
  }

  /// From 6: the escrow locked, the fiat sent, the payout tried (8, 9, 10, 13).
  Future<void> toSending() async {
    coordinator.lockEscrow(record.orderId);
    await moveTo(const [9, 10, 13], find.text(l10n.p2pEndSendingSats));
  }

  /// The payout failed and its invoice expired: 13 → 15, a new invoice asked, the coordinator's `last_satoshis` [last] from then on when given.
  Future<void> failPayout({int? last}) async {
    if (last != null) this.last = last;
    coordinator.failPayout(record.orderId);
    await waitFor(find.text(l10n.p2pPayoutInvoiceExpiredSubmitNew));
    await settle();
  }

  String sats(int value) => formats.bigSats(BigInt.from(value));

  Finder get breakdown => find.byType(PayoutBreakdownView);

  Finder get fewer => find.text(l10n.p2pPayoutFirstFewer);

  Finder figures(int first, int now) =>
      find.text(l10n.p2pPayoutFirstFewerFigures(sats(first), sats(now)));

  Finder get unknown => find.text(l10n.p2pPayoutFirstUnknown);

  Finder get indicative => find.text(l10n.p2pPayoutBreakdownGap);

  Finder get smallGap => find.text(l10n.p2pPayoutBreakdownSmallGap);

  Finder get fewerDetail => find.text(l10n.p2pPayoutFirstFewerDetail);

  Finder get unknownDetail => find.text(l10n.p2pPayoutFirstUnknownDetail);

  Finder get bullRed => find.text(l10n.p2pPayoutBreakdownAgainst);

  Finder inBreakdown(Finder finder) =>
      find.descendant(of: breakdown, matching: finder);

  AmountRowTone get givenTone =>
      tester.widget<AmountRow>(find.byKey(PayoutBreakdownView.givenRow)).tone;

  /// « Show details » of the breakdown.
  Future<void> openDetail() async {
    await tap(find.text(l10n.p2pDetailShow));
    await settle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

/// The order taken here: the book's coordinator played by `ScriptedCoordinator`, its other coordinators' books empty.
final class _TakerCoordinators implements CoordinatorTransport {
  final ScriptedCoordinator temple;
  final Map<String, ScriptedCoordinator> _others = {};

  _TakerCoordinators(this.temple);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    if (alias == temple.coordinator.shortAlias) return temple.send(request);
    if (request.url.path.startsWith('/api/book')) {
      return Ok(
        CoordinatorResponse(
          statusCode: 404,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode(
            jsonEncode({
              'not_found': 'No orders found, be the first to make one',
            }),
          ),
        ),
      );
    }
    final other = _others[alias] ??= ScriptedCoordinator(
      network: _net,
      robots: const [],
      clock: () => DateTime.utc(2026, 11, 20, 9),
      alias: alias,
    );
    return other.send(request);
  }

  static String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(_net)) {
      if (Uri.parse(coordinator.origins(_net).onion ?? '').host == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;

    group('an order made here, EUR, $code', () {
      testWidgets(
        'the security review\'s scenario: honest at 6 (−0.03 %), 9 % fewer sats at 15: the red alert with both figures, visible without a tap, « Paid by the coordinator » in red, no gap « (indicative) », never « A small gap is normal »; its explanation in the detail; « Submit » never blocked',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.settle();
          expect(app.fewer, findsNothing);
          await app.toSending();
          // 182,000 sats fixed: the coordinator pays `round(182,000 − 45.5)` = 181,954, 9.00 % fewer than the 199,950 of 6 (−9.03 % from the Bull price).
          await app.failPayout(last: 182000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.inBreakdown(app.fewer), findsOneWidget);
          expect(app.inBreakdown(app.figures(199950, 181954)), findsOneWidget);
          expect(app.givenTone, AmountRowTone.alert);
          expect(app.indicative, findsNothing);
          expect(app.bullRed, findsNothing);
          expect(app.fewerDetail, findsNothing);
          await app.openDetail();
          expect(app.inBreakdown(app.fewerDetail), findsOneWidget);
          expect(app.smallGap, findsNothing);
          expect(app.wallet.paid, isEmpty);
          // Nothing blocked: the invoice is still asked, « Generate Invoice » offered.
          expect(
            find.text(app.l10n.p2pPayoutInvoiceExpiredSubmitNew),
            findsOneWidget,
          );
          await app.close();
        },
      );

      testWidgets(
        'the same sum at 15: nothing more than before #281 (the gap « (indicative) », « A small gap is normal » in the detail)',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          await app.failPayout();
          await app.waitFor(app.indicative);
          await app.settle();
          expect(app.fewer, findsNothing);
          expect(app.unknown, findsNothing);
          expect(app.givenTone, AmountRowTone.plain);
          await app.openDetail();
          expect(app.smallGap, findsOneWidget);
          expect(app.fewerDetail, findsNothing);
          expect(app.unknownDetail, findsNothing);
          await app.close();
        },
      );

      testWidgets(
        'one sat fewer at 15 (199,949 for 199,950): the alert, no tolerance',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          await app.failPayout(last: 199999);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.figures(199950, 199949), findsOneWidget);
          expect(app.indicative, findsNothing);
          await app.close();
        },
      );

      testWidgets(
        'more than 10 % fewer at 15: the Bull wallet\'s red alert and the new alert, both visible, both explained in the detail',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          // 178,000 sats: `round(177,955.5)` = 177,956, −11.03 % from the 200,000 expected (rounded away from zero).
          await app.failPayout(last: 178000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.inBreakdown(app.bullRed), findsOneWidget);
          expect(app.inBreakdown(app.fewer), findsOneWidget);
          expect(app.figures(199950, 177956), findsOneWidget);
          await app.openDetail();
          expect(app.fewerDetail, findsOneWidget);
          expect(find.byKey(PayoutBreakdownDetail.explanation), findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'the Bull wallet\'s price unreadable: « Amount not checked » with « Retry » and the new alert, neither silencing the other',
        (tester) async {
          final app = await _App.start(
            tester,
            rate: const P2pWalletRateUnavailable(),
            locale: locale,
          );
          await app.openTrade();
          await app.waitFor(
            find.text(app.l10n.p2pPayoutBreakdownUnverifiedLine),
          );
          await app.toSending();
          await app.failPayout(last: 190000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(
            find.text(app.l10n.p2pPayoutBreakdownUnverifiedLine),
            findsOneWidget,
          );
          expect(find.text(app.l10n.p2pCommonRetry), findsOneWidget);
          expect(app.figures(199950, 189952), findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'the coordinator showed the trade once with another premium (the trace of #231 stays to the end), then 5 % fewer at 15, within the Bull wallet\'s threshold: the trace and the new alert both drawn, neither silencing the other (security review C2 of #281, its scenario E5)',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          final changed = find.text(app.l10n.p2pTradeWarnTerms);
          app.coordinator.orderChanges[app.record.orderId] = {
            'premium': '9.00',
          };
          await app.waitFor(changed);
          app.coordinator.orderChanges.remove(app.record.orderId);
          for (var i = 0; i < 240 && changed.evaluate().isNotEmpty; i++) {
            app.advance(const Duration(milliseconds: 250));
            await tester.pump(const Duration(milliseconds: 250));
          }
          expect(changed, findsNothing);
          final trace = find.textContaining(
            code == 'fr'
                ? 'a montré cet échange avec d’autres conditions'
                : 'showed this trade with other terms',
          );
          expect(trace, findsOneWidget);
          await app.toSending();
          await app.failPayout(last: 190000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(trace, findsOneWidget);
          expect(app.inBreakdown(app.fewer), findsOneWidget);
          expect(app.figures(199950, 189952), findsOneWidget);
          // The gap within the threshold beside an alert: not drawn, as everywhere.
          expect(app.indicative, findsNothing);
          await app.close();
        },
      );

      testWidgets(
        '15 → 13 → 15: still compared with the invoice of 6, never with the 15 before',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          await app.failPayout(last: 190000);
          await app.waitFor(app.fewer);
          // A new invoice given, tried again (13), failed again (15).
          await app.moveTo(const [13], find.text(app.l10n.p2pEndSendingSats));
          expect(app.fewer, findsNothing);
          await app.failPayout();
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.figures(199950, 189952), findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'two sums asked at 6 then 8 (189,952 then 199,950): the largest is the reference, so a 15 that asks the smaller again is said',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          app.last = 190000;
          await app.openTrade();
          await app.waitFor(find.textContaining(app.sats(189952)));
          app.last = 200000;
          await app.waitFor(find.textContaining(app.sats(199950)));
          await app.settle();
          app.coordinator.lockEscrow(app.record.orderId);
          await app.moveTo(const [8], app.indicative);
          await app.moveTo(const [
            9,
            10,
            13,
          ], find.text(app.l10n.p2pEndSendingSats));
          await app.failPayout(last: 190000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.figures(199950, 189952), findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'the page closed at 13 and opened again at 15: the sum of 6 still kept, compared',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          await app.closeTrade();
          app
            ..last = 190000
            ..coordinator.failPayout(app.record.orderId);
          await app.openTrade();
          await app.waitFor(app.fewer);
          expect(app.figures(199950, 189952), findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'the app started again between 13 and 15 (nothing kept): no comparison invented, a lower sum not said as fewer; « Not compared with the first invoice », never « A small gap is normal », the reason in the detail',
        (tester) async {
          final app = await _App.start(tester, locale: locale);
          await app.openTrade();
          await app.waitFor(app.indicative);
          await app.toSending();
          await app.closeTrade();
          app
            ..restart()
            ..last = 190000
            ..coordinator.failPayout(app.record.orderId);
          await app.openTrade();
          await app.waitFor(app.unknown);
          await app.settle();
          expect(app.inBreakdown(app.unknown), findsOneWidget);
          expect(app.inBreakdown(app.indicative), findsOneWidget);
          expect(app.fewer, findsNothing);
          expect(app.givenTone, AmountRowTone.plain);
          await app.openDetail();
          expect(app.smallGap, findsNothing);
          expect(app.unknownDetail, findsOneWidget);
          await app.close();
        },
      );
    });

    group('an order made here, GBP (not priced by the Bull wallet), $code', () {
      testWidgets(
        '5 % fewer at 15: the grey « not quoted » line and the new alert',
        (tester) async {
          final app = await _App.start(
            tester,
            currency: 'GBP',
            rate: const P2pWalletRateNotPriced(),
            locale: locale,
          );
          await app.openTrade();
          final notQuoted = find.text(app.l10n.p2pPayoutBreakdownNotPriced);
          await app.waitFor(notQuoted);
          await app.toSending();
          await app.failPayout(last: 190000);
          await app.waitFor(app.fewer);
          await app.settle();
          expect(app.inBreakdown(notQuoted), findsOneWidget);
          expect(app.figures(199950, 189952), findsOneWidget);
          await app.close();
        },
      );
    });

    group('an order taken here, $code', () {
      testWidgets(
        'a taker buyer: its sats 1.36 % lower at 15, within the state machine\'s 2 %: the new alert, the state machine silent',
        (tester) async {
          tester.view
            ..physicalSize = const Size(390 * 3, 3200 * 3)
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          FakeSecureStoragePlatform().install();
          var clock = DateTime.utc(2026, 11, 20, 9);
          void advance(Duration by) => clock = clock.add(by);
          // The owner's example: 100 USD at +3.5 %, 134,834 sats at the coordinator's price, the Bull wallet's 71,657; the taker fee 0.175 %, so 134,598 paid at 6.
          final coordinator =
              ScriptedCoordinator(
                  network: _net,
                  robots: TradeHarness.robotsOf(_net),
                  clock: () => clock,
                  orderType: 1,
                )
                ..currency = 1
                ..premium = 3.5
                ..satoshisNow = 134834
                ..price = double.parse((1e10 / 134834).toStringAsPrecision(5));
          final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
            ..rate = P2pWalletRateRead(71657);
          final locator = GetIt.asNewInstance();
          addTearDown(locator.reset);
          final tor = StreamController<P2pTorState>.broadcast();
          addTearDown(tor.close);
          setUpP2pForTesting(
            locator,
            transport: _TakerCoordinators(coordinator),
            torStates: () => tor.stream,
            clock: () => clock,
            garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
            robotKeys: HarnessKeys(),
            bolt11Decoder: coordinator.decoder,
            wallet: wallet,
          );
          final router = GoRouter(
            initialLocation: P2pFeature.path,
            routes: [const P2pFeature().route(locator, network: (_) => _net)],
          );
          final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          };
          await tester.runAsync(
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
          await settle(tester);
          await settle(tester);
          final l10n = lookupP2pLocalizations(locale);
          Future<void> waitFor(Finder finder) async {
            for (var i = 0; i < 240; i++) {
              if (finder.evaluate().isNotEmpty) return;
              advance(const Duration(milliseconds: 250));
              await tester.pump(const Duration(milliseconds: 250));
            }
            fail('never shown: $finder');
          }

          Future<void> tap(Finder finder) async {
            await tester.ensureVisible(finder);
            await tester.pump();
            // A guarded button just shown (« Pay ») ignores taps for a moment (security review of #291, B1): the tap comes later, as a user's.
            if (find
                .ancestor(of: finder, matching: find.byType(MovedTapGuard))
                .evaluate()
                .isNotEmpty) {
              await tester.pump(MovedTapGuard.afterMove);
            }
            await tester.tap(finder);
            await tester.pump();
          }

          Future<void> pass(int seconds) async {
            for (var i = 0; i < seconds * 4; i++) {
              advance(const Duration(milliseconds: 250));
              await tester.pump(const Duration(milliseconds: 250));
            }
          }

          // The take: the order of the book, « Take Order », « Continue », « Done ».
          await waitFor(find.byType(OfferRow));
          await tap(find.byType(OfferRow).first);
          await settle(tester);
          await waitFor(find.text(l10n.p2pTakeOrder));
          await tap(find.text(l10n.p2pTakeOrder));
          await waitFor(find.text(l10n.p2pTakerBond));
          await tap(find.text(l10n.p2pCommonContinue));
          await settle(tester);
          await tap(find.text(l10n.p2pCommonDone));
          await settle(tester);
          await waitFor(find.byType(TradeScreen));
          final robot = TradeHarness.robotsOf(
            _net,
          ).firstWhere(coordinator.holdsPreTake);
          coordinator.lockBond(robot);
          final formats = P2pFormats.of(
            tester.element(find.byType(TradeScreen)),
          );
          String sats(int value) => formats.bigSats(BigInt.from(value));
          await waitFor(find.textContaining(sats(134598)));
          await waitFor(find.text(l10n.p2pPayoutBreakdownGap));
          coordinator
            ..lockEscrow()
            ..moveTo(9);
          await pass(10);
          coordinator.moveTo(10);
          await pass(10);
          coordinator.moveTo(13);
          await waitFor(find.text(l10n.p2pEndSendingSats));
          // 133,000 sats at 15 (−1.36 %, within the state machine's 2 %): `round(133,000 − 232.75)` = 132,767 paid.
          coordinator
            ..lastSatoshis = 133000
            ..payoutExpired = true
            ..moveTo(15);
          final fewer = find.text(l10n.p2pPayoutFirstFewer);
          await waitFor(fewer);
          await settle(tester);
          expect(
            find.text(
              l10n.p2pPayoutFirstFewerFigures(sats(134598), sats(132767)),
            ),
            findsOneWidget,
          );
          expect(find.text(l10n.p2pTradeWarnPrice), findsNothing);
          expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
          expect(wallet.paid, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.pump(const Duration(seconds: 61));
        },
      );
    });
  }
}
