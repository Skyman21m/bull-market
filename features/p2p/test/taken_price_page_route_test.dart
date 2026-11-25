import 'dart:async';
import 'dart:convert';

import 'package:bull_ui/bull_ui.dart' show BullTheme;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/take_order_section.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/unlisted_order_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/order_detail_row.dart';
import 'package:p2p/src/ui/widgets/price_check_lines.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/lean_confirmation.dart' show loadAppFont;
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The owner's payment rule on the order page, before the take (#249, slice 4; design note `docs/design/phase-3-taken-order-price-check.md` § 3, first row, § 8 point 4; option B decided on 2026-11-24, the alert only), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`) by the user's gestures, in English and in French, for a taker buyer and a taker seller, from the book and from an order reached by its URL (#245).
///
/// The order's coordinator is played by `ScriptedCoordinator` (never a real one): 100 USD at +3.5 %, its sats at its price set per test (134,834 when its price without the premium is the Bull wallet's, 71,657 USD/BTC; 112,362 for a price 20 % higher, 168,543 for one 20 % lower); the other coordinators' books are empty. The wallet is `FakeP2pWalletPort`, its price the test's; nothing is ever paid.
const _net = RobosatsNetwork.testnet;

/// The Bull wallet's price of the tests.
const _bull = 71657.0;

/// temple's requests to [temple]; the other coordinators' books empty and their `/api/info/` their own; with [bookWithout] temple's book leaves the order out, which is then reached by its URL.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedCoordinator temple;
  final bool bookWithout;
  final Map<String, ScriptedCoordinator> _others = {};

  _Coordinators(this.temple, {this.bookWithout = false});

  static CoordinatorResponse _empty() => CoordinatorResponse(
    statusCode: 404,
    headers: const {'content-type': 'application/json'},
    body: utf8.encode(
      jsonEncode({'not_found': 'No orders found, be the first to make one'}),
    ),
  );

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    final book = request.url.path.startsWith('/api/book');
    if (alias == temple.coordinator.shortAlias) {
      if (bookWithout && book) return Ok(_empty());
      return temple.send(request);
    }
    if (book) return Ok(_empty());
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

final class _Journey {
  final WidgetTester tester;
  final ScriptedCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  final void Function(Duration) advance;
  final Locale locale;
  final int sats;

  _Journey(
    this.tester,
    this.coordinator,
    this.wallet,
    this.advance,
    this.locale,
    this.sats,
  );

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats => P2pFormats(l10n);

  /// The bodies of the takes, as sent, oldest first.
  List<String> get takes => [
    for (final request in coordinator.requests)
      if (request.method == CoordinatorHttpMethod.post &&
          request.url.path == '/api/order/')
        utf8.decode(request.body ?? const []),
  ];

  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  /// A taker buyer takes the sell order, a seller ([seller]) the buy order; [sats], the order's sats at the coordinator's price; [currency], the order's (1, USD; 7, CHF, which the Bull wallet does not price); [rate], the Bull wallet's price; [byUrl], the order left out of the book.
  static Future<_Journey> start(
    WidgetTester tester,
    Locale locale, {
    bool seller = false,
    int sats = 134834,
    int currency = 1,
    P2pWalletBitcoinRate? rate,
    bool byUrl = false,
    int? explicit,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 20, 9);
    final coordinator =
        ScriptedCoordinator(
            network: _net,
            robots: TradeHarness.robotsOf(_net),
            clock: () => clock,
            orderType: seller ? 0 : 1,
          )
          ..currency = currency
          ..premium = 3.5
          ..satoshisNow = sats
          ..price = double.parse((1e10 / sats).toStringAsPrecision(5))
          ..explicitSatoshis = explicit;
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(_bull);
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator, bookWithout: byUrl),
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
    final journey = _Journey(
      tester,
      coordinator,
      wallet,
      (by) => clock = clock.add(by),
      locale,
      sats,
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
    return journey;
  }

  /// The order's page: tapped in the book, or reached by its URL (« Search », its URL, « Search »), the robot reading it then; nothing of the Bull wallet's price read either way.
  Future<void> open({required bool byUrl}) async {
    if (byUrl) {
      await tap(find.text(l10n.p2pCommonSearch));
      await settle(tester);
      final dialog = find.byType(SearchOrderDialog);
      final host = Uri.parse(
        coordinator.coordinator.origins(_net).onion ?? '',
      ).host;
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'http://$host/order/temple/42',
      );
      await tap(
        find.descendant(of: dialog, matching: find.text(l10n.p2pCommonSearch)),
      );
      await waitFor(find.text(l10n.p2pTakeOrder));
      expect(find.byType(UnlistedOrderScreen), findsOneWidget);
    } else {
      await waitFor(find.byType(OfferRow));
      await tap(find.byType(OfferRow).first);
      await settle(tester);
      await waitFor(find.text(l10n.p2pTakeOrder));
    }
    await settle(tester);
    expect(wallet.ratesAsked, isEmpty, reason: 'nothing read at the opening');
  }

  /// « Take Order »: the robot's read shown, its « Taker bond » row with it.
  Future<void> prepare() async {
    await tap(find.text(l10n.p2pTakeOrder));
    await waitFor(find.text(l10n.p2pTakerBond));
    await settle(tester);
  }

  Finder get continueButton => find.byKey(TakeOrderSection.continueButton);

  /// « Continue » then « Done »: the trade's screen.
  Future<void> send() async {
    await tap(continueButton);
    await settle(tester);
    await tap(find.text(l10n.p2pCommonDone));
    await settle(tester);
    await waitFor(find.byType(TradeScreen));
  }

  Finder get alert => find.byKey(TakeOrderDetailsCard.priceAlert);

  /// The comparison of the page for [sats] at the Bull wallet's price of the tests.
  MakePriceCompared compared() => switch (MakePriceCheck.of(
    currency: some(RobosatsCurrency.fromId(1)),
    coordinatorPrice: 1e10 / sats / 1.035,
    wallet: P2pWalletRateRead(_bull),
  )) {
    final MakePriceCompared compared => compared,
    final other => throw StateError('not compared: $other'),
  };

  /// The texts of the comparison's lines, joined.
  String lines() => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: alert, matching: find.byType(Text)),
    ))
      text.data ?? '',
  ].join(' | ');

  /// Nothing under « Price and premium »: no line of the comparison, never a reassuring one.
  void expectNothing() {
    expect(alert, findsNothing);
    for (final text in [
      l10n.p2pTakePriceAgainst,
      l10n.p2pTakePriceFarBelow,
      l10n.p2pTakePriceUnverified,
      l10n.p2pPayoutBreakdownGap,
      l10n.p2pPayoutBreakdownGapNotPriced,
      l10n.p2pPayoutBreakdownSmallGap,
    ]) {
      expect(find.text(text), findsNothing);
    }
  }

  /// The red alert in two lines, its bold line ([farBelow] for a buyer and a price far below), the gap with its sign, the two prices without the premium, then its explanation.
  void expectRed({bool farBelow = false}) {
    final check = compared();
    expect(
      lines(),
      [
        farBelow ? l10n.p2pTakePriceFarBelow : l10n.p2pTakePriceAgainst,
        formats.gap(check.gapHundredths),
        l10n.p2pTakePriceFigures(
          formats.orderRate(_bull),
          'USD',
          formats.orderRate(1e10 / sats / 1.035),
        ),
        l10n.p2pTakePriceDetail(
          formats.threshold(TradeTolerances.walletRateGap),
        ),
      ].join(' | '),
    );
    expect(
      tester.widget<Icon>(
        find.descendant(of: alert, matching: find.byType(Icon)),
      ),
      isA<Icon>().having((i) => i.icon, 'icon', Icons.warning_amber_rounded),
    );
  }

  /// The « Price and premium » row of the read, and whether it is marked as changed.
  OrderDetailRow priceRow() => tester.widget<OrderDetailRow>(
    find.ancestor(
      of: find.text(l10n.p2pOrderPriceAndPremium),
      matching: find.byType(OrderDetailRow),
    ),
  );

  /// The value « Price and premium » shows for a price with the premium of [price] and [premium] %.
  String priceValue(double price, double premium) =>
      l10n.p2pOrderPriceAndPremiumValue(
        formats.price(price),
        'USD',
        formats.premiumNumber(some(Premium.tryCreate(premium))),
      );

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }
}

T some<T>(T? value) => value ?? (throw StateError('missing'));

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;

    group('the order page before the take, $code', () {
      for (final byUrl in const [false, true]) {
        final from = byUrl ? 'by its URL' : 'from the book';

        for (final seller in const [false, true]) {
          final who = seller ? 'a taker seller' : 'a taker buyer';

          testWidgets(
            '$who, $from, the coordinator\'s price that of the Bull wallet: nothing shown, one read at « Take Order », the take sent on the terms compared',
            (tester) async {
              final journey = await _Journey.start(
                tester,
                locale,
                seller: seller,
                byUrl: byUrl,
              );
              await journey.open(byUrl: byUrl);
              await journey.prepare();
              expect(journey.wallet.ratesAsked, hasLength(1));
              expect(journey.wallet.ratesAsked.single.$2.code, 'USD');
              journey.expectNothing();
              await journey.send();
              // Not compared again at the confirmation: the take is the one of the read compared.
              expect(journey.wallet.ratesAsked, hasLength(1));
              expect(journey.takes, ['{"action":"take","amount":0}']);
              await journey.close();
            },
          );

          testWidgets(
            '$who, $from, the coordinator\'s price 20 % above the Bull wallet\'s: ${seller ? 'nothing (fewer sats to lock)' : 'the red alert « against you »'}; « Continue » offered',
            (tester) async {
              final journey = await _Journey.start(
                tester,
                locale,
                seller: seller,
                sats: 112362,
                byUrl: byUrl,
              );
              await journey.open(byUrl: byUrl);
              await journey.prepare();
              if (seller) {
                journey.expectNothing();
              } else {
                journey.expectRed();
              }
              // Never a lock: « Continue » and « Done » take it.
              await tester.pump(MovedTapGuard.afterMove);
              await journey.send();
              expect(journey.takes, hasLength(1));
              await journey.close();
            },
          );

          testWidgets(
            '$who, $from, the coordinator\'s price 20 % below the Bull wallet\'s: the red alert ${seller ? '« against you »' : '« far below the Bull price »'}',
            (tester) async {
              final journey = await _Journey.start(
                tester,
                locale,
                seller: seller,
                sats: 168543,
                byUrl: byUrl,
              );
              await journey.open(byUrl: byUrl);
              await journey.prepare();
              journey.expectRed(farBelow: !seller);
              await tester.pump(MovedTapGuard.afterMove);
              await journey.send();
              expect(journey.takes, hasLength(1));
              await journey.close();
            },
          );
        }
      }

      testWidgets(
        'a market order\'s read: « Price and premium » from the terms, the alert\'s coordinator price that price without the premium',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 112362);
          await journey.open(byUrl: false);
          await journey.prepare();
          final row = journey.priceRow();
          expect(row.value, journey.priceValue(1e10 / 112362, 3.5));
          expect(row.changed, isFalse);
          // The figure the alert names is the one shown, the premium taken off.
          journey.expectRed();
          await journey.close();
        },
      );

      testWidgets(
        'an order priced in sats whose robot\'s read gives no price and a premium of 39.55 % where the book said 3.5 %: « Price and premium » shows it, marked; nothing is compared beyond the threshold; « Continue » stays offered',
        (tester) async {
          // 100 USD for 100,000 sats: 100,000 USD/BTC, 39.55 % above the Bull wallet's 71,657; without that premium, 71,659: within the threshold.
          final journey = await _Journey.start(
            tester,
            locale,
            sats: 100000,
            explicit: 100000,
          );
          journey.coordinator.robotView
            ..['price_now'] = null
            ..['premium_now'] = 39.55;
          await journey.open(byUrl: false);
          await journey.prepare();
          final row = journey.priceRow();
          expect(row.value, journey.priceValue(100000, 39.55));
          expect(row.changed, isTrue);
          expect(
            find.text(journey.l10n.p2pOrderAmountOfSatoshis),
            findsOneWidget,
          );
          expect(find.text(journey.formats.sats(100000)), findsWidgets);
          journey.expectNothing();
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.takes, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        'an honest order priced in sats: its premium shown with its price, not marked, its sats under them, nothing else',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            sats: 134834,
            explicit: 134834,
          );
          await journey.open(byUrl: false);
          await journey.prepare();
          final row = journey.priceRow();
          expect(row.value, journey.priceValue(1e10 / 134834, 3.5));
          expect(row.changed, isFalse);
          expect(
            find.text(journey.l10n.p2pOrderAmountOfSatoshis),
            findsOneWidget,
          );
          journey.expectNothing();
          await journey.send();
          expect(journey.takes, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        'an order public again, taken from its trade screen: compared as from the book and by its URL, once at its « Take Order »',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 112362);
          final l10n = journey.l10n;
          await journey.open(byUrl: false);
          await journey.prepare();
          journey.expectRed();
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.wallet.ratesAsked, hasLength(1));
          // The taker gone, the order is public again: its trade screen offers « Take Order », read anew by a fresh robot.
          journey.coordinator.backToPublic();
          await journey.waitFor(find.text(l10n.p2pTakeOrder));
          expect(find.byType(TradeScreen), findsOneWidget);
          expect(journey.alert, findsNothing);
          expect(journey.wallet.ratesAsked, hasLength(1));
          await journey.prepare();
          expect(journey.wallet.ratesAsked, hasLength(2));
          journey.expectRed();
          await journey.close();
        },
      );

      testWidgets(
        'the Bull wallet\'s price unreadable: « Price not checked » in orange with « Retry », in two lines and its explanation; « Retry » reads again, the alert gone within the threshold',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            rate: const P2pWalletRateUnavailable(),
          );
          final l10n = journey.l10n;
          await journey.open(byUrl: false);
          await journey.prepare();
          expect(
            journey.lines(),
            [
              l10n.p2pTakePriceUnverified,
              l10n.p2pCommonRetry,
              l10n.p2pPayoutBreakdownUnverifiedLine,
              l10n.p2pTakePriceUnverifiedDetail,
            ].join(' | '),
          );
          expect(
            tester
                .widget<Text>(find.text(l10n.p2pPayoutBreakdownUnverifiedLine))
                .style
                ?.color,
            Theme.of(
              tester.element(journey.alert),
            ).extension<BullTheme>()?.warning,
          );
          journey.wallet.rate = P2pWalletRateRead(_bull);
          await journey.tap(find.byKey(PriceCheckLines.retryButton));
          await settle(tester);
          expect(journey.wallet.ratesAsked, hasLength(2));
          journey.expectNothing();
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          await journey.close();
        },
      );

      testWidgets(
        'a currency the Bull wallet does not price: the grey « not quoted » line, nothing else',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            currency: 7,
            rate: const P2pWalletRateNotPriced(),
          );
          final l10n = journey.l10n;
          await journey.open(byUrl: false);
          await journey.prepare();
          expect(
            journey.lines(),
            '${l10n.p2pPayoutBreakdownGapNotPriced} | ${l10n.p2pPayoutBreakdownNotPriced}',
          );
          expect(find.byKey(PriceCheckLines.retryButton), findsNothing);
          expect(
            find.descendant(
              of: journey.alert,
              matching: find.byIcon(Icons.warning_amber_rounded),
            ),
            findsNothing,
          );
          await journey.close();
        },
      );

      testWidgets(
        '« Continue » pressed while the Bull wallet\'s price is read: it waits, then stops once with « This page has changed » when the red alert came; a press again goes on',
        (tester) async {
          final journey = await _Journey.start(tester, locale);
          final l10n = journey.l10n;
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          expect(journey.wallet.ratesAsked, hasLength(1));
          journey.expectNothing();
          await journey.tap(journey.continueButton);
          await settle(tester);
          // Waiting: no dialog yet.
          expect(find.byType(StoreTokenDialog), findsNothing);
          // The Bull wallet's price read 20 % below the coordinator's: red for a buyer.
          journey.wallet.rate = P2pWalletRateRead(_bull / 1.2);
          held.complete();
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsOneWidget);
          expect(find.text(l10n.p2pTakePageChangedTitle), findsOneWidget);
          expect(find.text(l10n.p2pTakePageChangedLine), findsOneWidget);
          expect(find.text(l10n.p2pTakePriceAgainst), findsOneWidget);
          expect(journey.takes, isEmpty);
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.takes, hasLength(1));
          expect(journey.wallet.ratesAsked, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        '« Continue » pressed while the first read fails: one stop, « This page has changed » over « Price not checked »; a press again goes on',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            rate: const P2pWalletRateUnavailable(),
          );
          final l10n = journey.l10n;
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          await journey.tap(journey.continueButton);
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          held.complete();
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsOneWidget);
          expect(find.text(l10n.p2pTakePriceUnverified), findsOneWidget);
          // The stop's block is over « Continue », under the card that holds « Price not checked ».
          expect(
            tester.getTopLeft(find.byKey(TakeOrderSection.pageChangedBlock)).dy,
            greaterThan(
              tester.getTopLeft(find.text(l10n.p2pTakePriceUnverified)).dy,
            ),
          );
          expect(journey.takes, isEmpty);
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.takes, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        '« Continue » pressed while the Bull wallet\'s price is read, a currency it does not price: one stop for the « not quoted » line',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            currency: 7,
            rate: const P2pWalletRateNotPriced(),
          );
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          await journey.tap(journey.continueButton);
          await settle(tester);
          held.complete();
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsOneWidget);
          expect(
            find.text(journey.l10n.p2pPayoutBreakdownNotPriced),
            findsOneWidget,
          );
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.takes, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        '« Retry », then « Continue » pressed while the price is read again: it waits; back within the threshold, nothing new to read, it goes on with no stop and the take is sent once',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            rate: const P2pWalletRateUnavailable(),
          );
          await journey.open(byUrl: false);
          await journey.prepare();
          expect(
            find.text(journey.l10n.p2pTakePriceUnverified),
            findsOneWidget,
          );
          journey.wallet.rate = P2pWalletRateRead(_bull);
          final held = journey.wallet.rateHeld = Completer();
          await journey.tap(find.byKey(PriceCheckLines.retryButton));
          await tester.pump(MovedTapGuard.afterMove);
          await journey.tap(journey.continueButton);
          await settle(tester);
          // It waits for the read « Retry » started: no dialog meanwhile.
          expect(find.byType(StoreTokenDialog), findsNothing);
          held.complete();
          await settle(tester);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsNothing);
          journey.expectNothing();
          expect(find.byType(StoreTokenDialog), findsOneWidget);
          await journey.tap(find.text(journey.l10n.p2pCommonDone));
          await journey.waitFor(find.byType(TradeScreen));
          expect(journey.takes, hasLength(1));
          expect(journey.wallet.ratesAsked, hasLength(2));
          await journey.close();
        },
      );

      testWidgets(
        '« Continue » pressed while the price is read, then the take gone back and prepared again meanwhile: the press is for a read no longer shown, nothing opens',
        (tester) async {
          final journey = await _Journey.start(tester, locale);
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          await journey.tap(journey.continueButton);
          await settle(tester);
          // The page's own « Take Order » is not offered while a « Continue » waits (one dialog of the take at a time): the take is moved on by its cubit, as any later path could move it.
          final cubit = BlocProvider.of<TakeOrderCubit>(
            tester.element(find.byType(TakeOrderSection)),
          );
          final first = (cubit.state as TakeReady).prepared;
          cubit.back();
          await settle(tester);
          unawaited(cubit.take());
          await journey.waitFor(find.text(journey.l10n.p2pTakerBond));
          await settle(tester);
          expect(
            identical((cubit.state as TakeReady).prepared, first),
            isFalse,
          );
          held.complete();
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsNothing);
          expect(journey.takes, isEmpty);
          // The new read's own « Continue » goes on.
          await tester.pump(MovedTapGuard.afterMove);
          await journey.send();
          expect(journey.takes, hasLength(1));
          await journey.close();
        },
      );

      testWidgets(
        '« Continue » pressed while the Bull wallet\'s price is read, within the threshold: it waits, then goes on with no stop',
        (tester) async {
          final journey = await _Journey.start(tester, locale);
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          await journey.tap(journey.continueButton);
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          held.complete();
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsOneWidget);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsNothing);
          await journey.tap(find.text(journey.l10n.p2pCommonDone));
          await journey.waitFor(find.byType(TradeScreen));
          await journey.close();
        },
      );

      testWidgets(
        'the red alert that arrives moves « Continue »: a tap at once is ignored, the next one after the delay goes on',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 112362);
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          final before = tester.getTopLeft(journey.continueButton);
          held.complete();
          await tester.pump();
          await tester.pump();
          expect(journey.alert, findsOneWidget);
          expect(tester.getTopLeft(journey.continueButton), isNot(before));
          // Aimed at what stood there a moment before: nothing opens.
          await tester.tap(journey.continueButton);
          await tester.pump();
          expect(find.byType(StoreTokenDialog), findsNothing);
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tap(journey.continueButton);
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsOneWidget);
          await journey.close();
        },
      );

      testWidgets(
        'on a phone of 320 points, at the text size ×1, ×2 and ×3: the alerts and « This page has changed » cut nothing',
        (tester) async {
          await loadAppFont();
          final journey = await _Journey.start(tester, locale, sats: 168543);
          final held = journey.wallet.rateHeld = Completer();
          await journey.open(byUrl: false);
          await journey.prepare();
          await journey.tap(journey.continueButton);
          held.complete();
          await settle(tester);
          expect(journey.alert, findsOneWidget);
          expect(find.byKey(TakeOrderSection.pageChangedBlock), findsOneWidget);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.view
            ..physicalSize = const Size(320 * 3, 6000 * 3)
            ..devicePixelRatio = 3;
          for (final scale in const [1.0, 2.0, 3.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pump();
            _expectNothingCut(tester, journey.alert, 'red ×$scale');
            _expectNothingCut(
              tester,
              find.byKey(TakeOrderSection.pageChangedBlock),
              'changed ×$scale',
            );
          }
          await journey.close();
        },
      );

      testWidgets(
        'on a phone of 320 points, at the text size ×1, ×2 and ×3: « Price not checked » and « Retry » cut nothing',
        (tester) async {
          await loadAppFont();
          final journey = await _Journey.start(
            tester,
            locale,
            rate: const P2pWalletRateUnavailable(),
          );
          await journey.open(byUrl: false);
          await journey.prepare();
          expect(
            find.text(journey.l10n.p2pTakePriceUnverified),
            findsOneWidget,
          );
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.view
            ..physicalSize = const Size(320 * 3, 6000 * 3)
            ..devicePixelRatio = 3;
          for (final scale in const [1.0, 2.0, 3.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pump();
            _expectNothingCut(tester, journey.alert, 'unverified ×$scale');
            expect(find.byKey(PriceCheckLines.retryButton), findsOneWidget);
          }
          await journey.close();
        },
      );
    });
  }
}

/// Nothing overflows under [scope], no paragraph exceeds its lines, and no line breaks between two letters (as `LeanConfirmation.expectNothingCut` checks the confirmations).
void _expectNothingCut(WidgetTester tester, Finder scope, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: scope, matching: find.byType(RichText)),
  )) {
    expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
    final text = paragraph.text.toPlainText();
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
    )..layout(maxWidth: paragraph.size.width);
    var offset = 0;
    while (offset < text.length) {
      final end = painter.getLineBoundary(TextPosition(offset: offset)).end;
      if (end <= offset) break;
      if (end < text.length) {
        expect(
          _letter(text[end - 1]) && _letter(text[end]),
          isFalse,
          reason: '$reason: a word cut in « $text » at $end',
        );
      }
      offset = end;
    }
    painter.dispose();
  }
}

bool _letter(String char) =>
    RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char);
