import 'dart:async';
import 'dart:convert';

import 'package:bull_ui/bull_ui.dart' show BullSegmented;
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
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/lean_confirmation.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// #288 on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`; the coordinators played by `ScriptedMakerCoordinator` and `ScriptedCoordinator`, never real ones; the wallet `FakeP2pWalletPort`, which pays nothing): on the confirmation of « Pay with this wallet », with its detail open and the page scrolled within the detail's height of its end, a tap on « Hide details » folds the detail, the page goes back to its new end without a scroll and « Pay » can come under the finger; a second tap at the same place never pays, the next tap after `MovedTapGuard.afterMove` does (independent review of #287).
///
/// The three confirmations where the review reached « Pay »: a maker's bond, a maker seller's collateral and a taker's bond; in English and in French, at 320 and 390 points, the text ×1 and ×3. The ordinary gestures around « Pay » are pinned by the number of taps they have ignored, none but after a move the user did not make (#286's lesson).
const _net = RobosatsNetwork.testnet;

final _toggle = find.byKey(PayConfirmationCard.detailToggle);
final _link = find.descendant(of: _toggle, matching: find.byType(TextButton));
final _detail = find.byKey(PayConfirmationCard.detail);
final _goBack = find.byKey(PayConfirmationCard.goBack);

/// A quote of [invoice] for the fake wallet: its sats, 500 of swap fees and 27 of network fee.
P2pWalletQuote _quoteOf(Bolt11TestInvoice invoice, DateTime now) {
  final checked = checkedBolt11InvoiceForTesting(
    bolt11: invoice.text,
    amount: invoice.facts.amount,
    network: _net,
    paymentHash: invoice.facts.paymentHash,
    expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
    now: now,
  );
  if (checked == null) fail('not a payable invoice');
  return P2pWalletQuote(
    invoice: checked,
    payin: Sats(checked.amount.value + BigInt.from(500)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: now,
  );
}

/// A confirmation of « Pay with this wallet » in the app: its wallet, and how to open it again (« Pay with this wallet », a quote scripted).
final class _Confirmation {
  final WidgetTester tester;
  final Locale locale;
  final FakeP2pWalletPort wallet;
  final Bolt11TestInvoice invoice;
  final DateTime Function() clock;
  final Future<void> Function() close;

  /// How many requests the order's coordinator has received.
  final int Function() requests;

  _Confirmation(
    this.tester,
    this.locale,
    this.wallet,
    this.invoice,
    this.clock,
    this.close, {
    this.requests = _none,
  }) {
    wallet.scriptPayment(
      Ok(P2pWalletPayment(id: 'fold', paymentHash: invoice.facts.paymentHash)),
    );
  }

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  late P2pWalletQuote quote = _quoteOf(invoice, clock());

  /// « Pay {total} sats ».
  Finder get pay => LeanConfirmation(tester, locale).payOf(quote);

  /// « Pay with this wallet » tapped, the confirmation drawn.
  Future<void> open() async {
    wallet.scriptQuote(Ok(quote));
    final payWith = find.text(l10n.p2pPayWithThisWallet);
    await tester.ensureVisible(payWith);
    await tester.pump();
    await tester.tap(payWith);
    for (var i = 0; i < 100 && pay.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pay, findsOneWidget);
    await tester.pump(MovedTapGuard.afterMove);
  }
}

int _none() => 0;

ScrollPosition _position(WidgetTester tester) =>
    Scrollable.of(tester.element(_toggle)).position;

Rect _viewport(WidgetTester tester) => tester.getRect(
  find.ancestor(of: _toggle, matching: find.byType(Scrollable)).first,
);

/// What lies under [point]: « Pay », « Go back », « Hide details » / « Show details », or something else.
String _under(WidgetTester tester, Offset point, _Confirmation confirmation) {
  final path = {
    for (final entry in tester.hitTestOnBinding(point).path) entry.target,
  };
  for (final (name, finder) in [
    ('pay', confirmation.pay),
    ('goBack', _goBack),
    ('link', _link),
  ]) {
    for (final element in finder.evaluate()) {
      if (path.contains(element.renderObject)) return name;
    }
  }
  return 'other';
}

/// The detail opened, if closed.
Future<void> _openDetail(WidgetTester tester) async {
  if (_detail.evaluate().isNotEmpty) return;
  await tester.ensureVisible(_link);
  await tester.pump();
  await tester.tap(_link);
  await tester.pump();
  expect(_detail, findsOneWidget);
}

/// The view at [width] × [height] points, the text at [scale].
Future<void> _size(
  WidgetTester tester, {
  double width = 390,
  double height = 490,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  await tester.pump();
  await tester.pump(MovedTapGuard.afterMove);
}

/// With the detail open and the page [back] points before its end, a tap at the middle of « Hide details »: its place, and what lies there [after] it, the page still. `null` when the link is not on the screen there.
Future<(Offset, String)?> _fold(
  WidgetTester tester,
  _Confirmation confirmation,
  double back, {
  Duration after = const Duration(milliseconds: 16),
}) async {
  await _openDetail(tester);
  final position = _position(tester);
  final offset = position.maxScrollExtent - back;
  if (offset < 0) return null;
  position.jumpTo(offset);
  await tester.pump(MovedTapGuard.afterMove);
  final point = tester.getCenter(_link);
  if (!_viewport(tester).deflate(2).contains(point)) return null;
  await tester.tapAt(point);
  var waited = Duration.zero;
  while (waited < after) {
    await tester.pump(const Duration(milliseconds: 16));
    waited += const Duration(milliseconds: 16);
  }
  expect(_detail, findsNothing);
  return (point, _under(tester, point, confirmation));
}

/// The places before the page's end where the fold brings « Pay » under the finger, every [step] points up to the detail's height and 40 more.
Future<List<double>> _band(
  WidgetTester tester,
  _Confirmation confirmation, {
  double step = 4,
}) async {
  await _openDetail(tester);
  final reach = tester.getSize(_detail).height + 40;
  final found = <double>[];
  for (var back = 0.0; back <= reach; back += step) {
    final folded = await _fold(tester, confirmation, back);
    if (folded?.$2 == 'pay') found.add(back);
  }
  return found;
}

/// With the detail open at every place within its height of the page's end, a fold and a second tap at the same place 16 ms later, at 320 and 390 points wide, [heights] high, the text ×1 and ×3: what lay under the finger, counted; nothing paid ever. « Go back » taken closes the confirmation, opened again.
Future<Map<String, int>> _sweep(
  WidgetTester tester,
  _Confirmation confirmation, {
  required List<double> heights,
}) async {
  final counts = <String, int>{};
  for (final (width, height, scale) in [
    for (final width in const [320.0, 390.0])
      for (final height in heights)
        for (final scale in const [1.0, 3.0]) (width, height, scale),
  ]) {
    {
      await _size(tester, width: width, height: height, scale: scale);
      if (confirmation.pay.evaluate().isEmpty) await confirmation.open();
      await _openDetail(tester);
      final reach = tester.getSize(_detail).height + 40;
      for (var back = 0.0; back <= reach; back += 8 * scale) {
        if (confirmation.pay.evaluate().isEmpty) await confirmation.open();
        final folded = await _fold(tester, confirmation, back);
        if (folded == null) continue;
        final (point, under) = folded;
        counts[under] = (counts[under] ?? 0) + 1;
        await tester.tapAt(point);
        await tester.pump();
        expect(
          confirmation.wallet.paid,
          isEmpty,
          reason: '$width × $height ×$scale',
        );
        if (under == 'goBack') {
          expect(confirmation.pay, findsNothing, reason: 'Go back taken');
        }
        await tester.pump(MovedTapGuard.afterMove);
      }
    }
  }
  return counts;
}

/// Taps « Pay » where it is, a new tap every half second (a user who taps again), until it pays: how many taps were ignored.
Future<int> _ignoredBeforePaying(
  WidgetTester tester,
  _Confirmation confirmation, {
  Duration every = const Duration(milliseconds: 500),
}) async {
  for (var ignored = 0; ignored < 20; ignored++) {
    await tester.tapAt(tester.getCenter(confirmation.pay));
    await tester.pump();
    if (confirmation.wallet.paid.isNotEmpty) {
      expect(confirmation.wallet.paid, hasLength(1));
      return ignored;
    }
    await tester.pump(every);
  }
  fail('« Pay » never paid');
}

/// « Pay with this wallet » placed with its bottom [under] points below the page's edge (negative: above it), or at the top of the page's view when `null` (as `ensureVisible` leaves it), then tapped at the middle of its visible part, the quote scripted, the Bull wallet's price read held [hold] when given: the test is left at the first frame of the confirmation. The point tapped, and whether the page scrolled to bring « Pay » into view.
Future<(Offset, bool)> _openPlaced(
  WidgetTester tester,
  _Confirmation confirmation, {
  double? under,
  Duration hold = Duration.zero,
}) async {
  final payWith = find.text(confirmation.l10n.p2pPayWithThisWallet);
  await tester.ensureVisible(payWith);
  await tester.pump();
  final position = Scrollable.of(tester.element(payWith)).position;
  final page = tester.getRect(
    find.ancestor(of: payWith, matching: find.byType(Scrollable)).first,
  );
  if (under != null) {
    final below = page.bottom - tester.getRect(payWith).bottom;
    position.jumpTo(
      (position.pixels - below - under).clamp(0, position.maxScrollExtent),
    );
  }
  await tester.pump(MovedTapGuard.afterMove);
  final button = tester.getRect(
    find.ancestor(of: payWith, matching: find.byType(TradeButton)).first,
  );
  final point = button.intersect(page).center;
  final before = position.pixels;
  final held = hold == Duration.zero ? null : Completer<void>();
  confirmation.wallet
    ..rateHeld = held
    ..scriptQuote(Ok(confirmation.quote));
  await tester.tapAt(point);
  await tester.pump();
  if (held != null) {
    for (var waited = Duration.zero; waited < hold;) {
      await tester.pump(const Duration(milliseconds: 16));
      waited += const Duration(milliseconds: 16);
    }
    held.complete();
  }
  for (var i = 0; i < 200 && confirmation.pay.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(confirmation.pay, findsOneWidget);
  // The reveal of « Pay » runs after this first frame: one more frame shows it.
  await tester.pump(const Duration(milliseconds: 16));
  return (point, _position(tester).pixels != before);
}

// The maker's side: an order made here, at its bond (0) or, sold and taken, at its collateral (6).

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

/// Runs [run] outside the frames, pumping until it ends.
Future<T> _wait<T>(WidgetTester tester, Future<T> Function() run) async {
  T? value;
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
  if (value case final T value) return value;
  throw StateError('never done');
}

Future<void> _imported(WidgetTester tester, GetIt locator) async {
  final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  await _wait(
    tester,
    () async => (
      await locator<GarageKeyRepository>().import(_net, tradeKey),
      await locator<RobotBindingRepository>().recordGeneratedKey(
        _net,
        fingerprint,
      ),
    ),
  );
}

/// A sell order of 100 EUR made here at 50,000 EUR/BTC, on its trade screen: at its bond ([collateral] false), or its bond locked and taken by robot 5, at its collateral; the view at 390 × 490, the confirmation not yet opened.
Future<_Confirmation> _maker(
  WidgetTester tester, {
  bool collateral = false,
  Locale locale = const Locale('en'),
}) async {
  await loadAppFont();
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view
    ..physicalSize = const Size(390 * 3, 2600 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  FakeSecureStoragePlatform().install();
  final clock = DateTime.utc(2026, 11, 14, 9);
  final coordinator = ScriptedMakerCoordinator(
    network: _net,
    robots: TradeHarness.robotsOf(_net),
    clock: () => clock,
  );
  final euro = switch (RobosatsCurrency.fromCode('EUR')) {
    final found? => found,
    null => throw StateError('no EUR'),
  };
  coordinator.prices[euro.id] = 50000;
  final locator = GetIt.asNewInstance();
  addTearDown(locator.reset);
  final tor = StreamController<P2pTorState>.broadcast();
  addTearDown(tor.close);
  final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
    ..rate = P2pWalletRateRead(50000);
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
  await _imported(tester, locator);
  await tester.pumpWidget(routerHarness(router, locale: locale));
  tor.add(P2pTorState.ready);
  await settle(tester);
  final request = MakeHarness.request(sell: true, currency: euro);
  final TradeRecord record = switch (await _wait(
    tester,
    () => locator<MakeOrderUsecase>().execute(
      request,
      coordinator: coordinator.coordinator,
      network: _net,
      seen: MakePriceSeen.of(currency: euro, coordinatorPrice: 50000),
    ),
  )) {
    Ok(value: MakeStarted(:final record)) => record,
    final other => throw StateError('$other'),
  };
  if (collateral) {
    coordinator
      ..lockMakerBond(record.orderId)
      ..take(record.orderId, TradeHarness.robotsOf(_net)[5]);
  }
  unawaited(
    router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(record)),
  );
  for (var i = 0; i < 3; i++) {
    await settle(tester);
  }
  final order = coordinator.order(record.orderId);
  final invoice = collateral ? order.escrow : order.bond;
  if (invoice == null) fail('no invoice');
  var requests = 0;
  coordinator.onRequest = (_) => requests++;
  await _size(tester);
  return _Confirmation(tester, locale, wallet, invoice, () => clock, () async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }, requests: () => requests);
}

// The taker's side: an order of the book taken by the user's gestures, at its bond (3).

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

/// A buy order of the book, 100 USD at +3.5 %, taken by the user's gestures (the order tapped, « Take Order », « Continue », « Done »): its trade screen at the taker's bond; the view at 390 × 490, the confirmation not yet opened.
Future<_Confirmation> _taker(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Future<void> Function(P2pLocalizations l10n, void Function(Duration) advance)?
  atContinue,
}) async {
  await loadAppFont();
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
  await _imported(tester, locator);
  await tester.pumpWidget(routerHarness(router, locale: locale));
  tor.add(P2pTorState.ready);
  await settle(tester);
  await settle(tester);
  final l10n = lookupP2pLocalizations(locale);
  Future<void> waitFor(Finder finder) async {
    for (var i = 0; i < 240; i++) {
      if (finder.evaluate().isNotEmpty) return;
      clock = clock.add(const Duration(milliseconds: 250));
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

  await waitFor(find.byType(OfferRow));
  await tap(find.byType(OfferRow).first);
  await settle(tester);
  await waitFor(find.text(l10n.p2pTakeOrder));
  await tap(find.text(l10n.p2pTakeOrder));
  if (atContinue != null) {
    await atContinue(l10n, (by) => clock = clock.add(by));
  } else {
    await waitFor(find.text(l10n.p2pTakerBond));
    await tap(find.text(l10n.p2pCommonContinue));
  }
  await settle(tester);
  await tap(find.text(l10n.p2pCommonDone));
  await settle(tester);
  await waitFor(find.byType(TradeScreen));
  await waitFor(find.text(l10n.p2pPayWithThisWallet));
  final robot = TradeHarness.robotsOf(
    _net,
  ).firstWhere(coordinator.holdsPreTake);
  final invoice = coordinator.bondOf(robot);
  if (invoice == null) fail('no bond');
  await _size(tester);
  return _Confirmation(tester, locale, wallet, invoice, () => clock, () async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  });
}

void main() {
  group('#288: a second tap at the place of « Hide details »', () {
    testWidgets(
      'the review\'s case, a maker\'s bond in English at 390 × 490, the text ×1: the fold brings « Pay » under the finger between 140 and 188 points before the page\'s end; a second tap there after 16, 100, 300 and 700 ms pays nothing, the next one after the delay pays',
      (tester) async {
        final confirmation = await _maker(tester);
        await confirmation.open();
        final band = await _band(tester, confirmation);
        expect(band, isNotEmpty);
        expect(band.first, inInclusiveRange(132, 148));
        expect(band.last, inInclusiveRange(180, 196));
        final back = band[band.length ~/ 2];
        for (final ms in const [16, 100, 300, 700]) {
          final folded = await _fold(
            tester,
            confirmation,
            back,
            after: Duration(milliseconds: ms),
          );
          if (folded == null) fail('the link off the screen');
          final (point, under) = folded;
          expect(under, 'pay', reason: '$ms ms');
          await tester.tapAt(point);
          await tester.pump();
          expect(confirmation.wallet.paid, isEmpty, reason: '$ms ms');
          await tester.pump(MovedTapGuard.afterMove);
        }
        // Never a dead button: once the delay has passed, the tap at the same place pays, once.
        final folded = await _fold(
          tester,
          confirmation,
          back,
          after: MovedTapGuard.afterMove + const Duration(milliseconds: 16),
        );
        if (folded == null) fail('the link off the screen');
        await tester.tapAt(folded.$1);
        await tester.pump();
        expect(confirmation.wallet.paid, hasLength(1));
        await confirmation.close();
      },
    );

    for (final (name, heights, start)
        in <
          (
            String,
            List<double>,
            Future<_Confirmation> Function(WidgetTester, Locale),
          )
        >[
          (
            'a maker\'s bond',
            const [490],
            (tester, locale) => _maker(tester, locale: locale),
          ),
          // Its invoice's facts under the card: « Pay » is reached on taller screens.
          (
            'a maker seller\'s collateral',
            const [800, 1000],
            (tester, locale) =>
                _maker(tester, collateral: true, locale: locale),
          ),
          (
            'a taker\'s bond',
            const [490],
            (tester, locale) => _taker(tester, locale: locale),
          ),
        ]) {
      testWidgets(
        '$name, in English and in French, at 320 and 390 points × ${heights.join(' and ')}, the text ×1 and ×3: wherever the fold brings « Pay » or « Go back » under the finger, a second tap 16 ms later pays nothing; « Go back » closes the confirmation, as before',
        (tester) async {
          final total = <String, int>{};
          for (final locale in const [Locale('en'), Locale('fr')]) {
            final confirmation = await start(tester, locale);
            final counts = await _sweep(tester, confirmation, heights: heights);
            debugPrint('SWEEP $name ${locale.languageCode}: $counts');
            for (final MapEntry(:key, :value) in counts.entries) {
              total[key] = (total[key] ?? 0) + value;
            }
            expect(confirmation.wallet.paid, isEmpty);
            await confirmation.close();
          }
          expect(total['pay'], isNonZero, reason: '« Pay » reached: $total');
        },
      );
    }
  });

  group(
    'a second tap on « Pay with this wallet » at the page\'s bottom edge (security review of #291, B1)',
    () {
      for (final (width, height, scale, locale, under, hold) in const [
        (320.0, 490.0, 3.0, Locale('fr'), 4.0, Duration.zero),
        (320.0, 490.0, 3.0, Locale('fr'), 4.0, Duration(seconds: 1)),
        (390.0, 490.0, 2.0, Locale('en'), 4.0, Duration.zero),
        (360.0, 640.0, 2.0, Locale('fr'), 4.0, Duration.zero),
        (390.0, 600.0, 3.0, Locale('en'), 4.0, Duration(seconds: 2)),
      ]) {
        testWidgets(
          '$width × $height, the text ×$scale, ${locale.languageCode}, the button $under points under the edge, the price read held ${hold.inSeconds} s: « Pay » is brought where the finger was; a second tap there 100, 300 and 600 ms after the confirmation\'s first frame pays nothing, one at 750 ms pays',
          (tester) async {
            final confirmation = await _maker(tester, locale: locale);
            await _size(tester, width: width, height: height, scale: scale);
            final (point, scrolled) = await _openPlaced(
              tester,
              confirmation,
              under: under,
              hold: hold,
            );
            expect(scrolled, isTrue);
            var elapsed = 16;
            for (final ms in const [100, 300, 600]) {
              await tester.pump(Duration(milliseconds: ms - elapsed));
              elapsed = ms;
              expect(
                _under(tester, point, confirmation),
                'pay',
                reason: '$ms ms',
              );
              await tester.tapAt(point);
              await tester.pump();
              expect(confirmation.wallet.paid, isEmpty, reason: '$ms ms');
            }
            await tester.pump(Duration(milliseconds: 750 - elapsed));
            await tester.tapAt(point);
            await tester.pump();
            expect(confirmation.wallet.paid, hasLength(1));
            await confirmation.close();
          },
        );
      }

      testWidgets(
        'the confirmation opened with « Pay » brought into view (the guard\'s first measure skipped), then the review\'s case of #288: the second tap on « Hide details » pays nothing, the guard still measuring (both reviews of #291, C1)',
        (tester) async {
          final confirmation = await _maker(tester);
          final (_, scrolled) = await _openPlaced(
            tester,
            confirmation,
            under: -4,
          );
          expect(scrolled, isTrue);
          await tester.pump(MovedTapGuard.afterMove);
          final band = await _band(tester, confirmation, step: 8);
          expect(band, isNotEmpty);
          final folded = await _fold(
            tester,
            confirmation,
            band[band.length ~/ 2],
            after: const Duration(milliseconds: 100),
          );
          if (folded == null) fail('the link off the screen');
          expect(folded.$2, 'pay');
          await tester.tapAt(folded.$1);
          await tester.pump();
          expect(confirmation.wallet.paid, isEmpty);
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tapAt(folded.$1);
          await tester.pump();
          expect(confirmation.wallet.paid, hasLength(1));
          await confirmation.close();
        },
      );
    },
  );

  group('the ordinary gestures around « Pay », a maker\'s bond: the taps ignored', () {
    const configs = [
      (390.0, 1.0, Locale('en')),
      (320.0, 3.0, Locale('fr')),
      (390.0, 3.0, Locale('en')),
      (320.0, 1.0, Locale('fr')),
    ];

    /// The confirmation opened at [width] × [height], the text at [scale], « Pay » brought near the top of the page, the guard idle.
    Future<_Confirmation> opened(
      WidgetTester tester,
      double width,
      double scale,
      Locale locale, {
      double height = 490,
    }) async {
      final confirmation = await _maker(tester, locale: locale);
      await _size(tester, width: width, height: height, scale: scale);
      await confirmation.open();
      await tester.ensureVisible(confirmation.pay);
      unawaited(
        Scrollable.ensureVisible(
          tester.element(confirmation.pay),
          alignment: 0.2,
        ),
      );
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      return confirmation;
    }

    void count(String gesture, int ignored) =>
        debugPrint('GESTURE $gesture: $ignored ignored');

    for (final (width, scale, locale) in configs) {
      final at = '$width points ×$scale ${locale.languageCode}';
      for (final edge in const [false, true]) {
        testWidgets(
          'the confirmation opened, « Pay with this wallet » ${edge ? 'at the page\'s bottom edge, so that `ensureVisible` scrolls to « Pay »' : 'at the top of the page\'s view'}, then « Pay » tapped 300, 500, 700 and 900 ms after the card\'s first frame ($at): a button that just appeared ignores the taps within 0.7 s (security review of #291, B1), the first after pays',
          (tester) async {
            final confirmation = await _maker(tester, locale: locale);
            await _size(tester, width: width, scale: scale);
            final (_, scrolled) = await _openPlaced(
              tester,
              confirmation,
              under: edge ? -4 : null,
            );
            if (edge) expect(scrolled, isTrue, reason: 'brought into view');
            final outcomes = <int, bool>{};
            var elapsed = 16;
            for (final ms in const [300, 500, 700, 900]) {
              await tester.pump(Duration(milliseconds: ms - elapsed));
              elapsed = ms;
              await tester.tapAt(tester.getCenter(confirmation.pay));
              await tester.pump();
              outcomes[ms] = confirmation.wallet.paid.isNotEmpty;
              if (outcomes[ms] ?? false) break;
            }
            count(
              'open (edge: $edge, $at, scrolled: $scrolled): paid at $outcomes',
              outcomes.values.where((paid) => !paid).length,
            );
            expect(outcomes[300], isFalse);
            expect(outcomes[500], isFalse);
            // The delay starts at the guard's first measure: at the card's first frame, or one frame later when the reveal scrolled after it.
            expect(outcomes[700] ?? true, scrolled ? isFalse : isTrue);
            expect(confirmation.wallet.paid, hasLength(1));
            await confirmation.close();
          },
        );
      }

      testWidgets('the page dragged, then « Pay » ($at): none ignored', (
        tester,
      ) async {
        final confirmation = await opened(tester, width, scale, locale);
        final position = _position(tester);
        final before = position.pixels;
        await tester.drag(
          find.ancestor(of: _toggle, matching: find.byType(Scrollable)).first,
          Offset(0, before > 40 ? 30 : -30),
        );
        await tester.pump();
        expect(position.pixels, isNot(before));
        await tester.pump(const Duration(milliseconds: 100));
        final ignored = await _ignoredBeforePaying(tester, confirmation);
        count('drag ($at)', ignored);
        expect(ignored, 0);
        await confirmation.close();
      });

      testWidgets(
        'the page flung, then « Pay » as soon as it is still ($at): none ignored',
        (tester) async {
          final confirmation = await opened(tester, width, scale, locale);
          final position = _position(tester);
          final before = position.pixels;
          await tester.fling(
            find.ancestor(of: _toggle, matching: find.byType(Scrollable)).first,
            Offset(0, before > 40 ? 20 : -20),
            300,
          );
          await tester.pump();
          for (var i = 0; i < 200 && position.isScrollingNotifier.value; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(position.pixels, isNot(before));
          expect(
            _viewport(tester).contains(tester.getCenter(confirmation.pay)),
            isTrue,
          );
          final ignored = await _ignoredBeforePaying(tester, confirmation);
          count('fling ($at)', ignored);
          expect(ignored, 0);
          await confirmation.close();
        },
      );

      testWidgets(
        'the detail opened, then « Pay » 300 ms later ($at): none ignored',
        (tester) async {
          final confirmation = await opened(tester, width, scale, locale);
          unawaited(
            Scrollable.ensureVisible(tester.element(_link), alignment: 0.9),
          );
          await tester.pump();
          await tester.pump(MovedTapGuard.afterMove);
          expect(
            _viewport(tester).contains(tester.getCenter(confirmation.pay)),
            isTrue,
          );
          await tester.tapAt(tester.getCenter(_link));
          await tester.pump();
          expect(_detail, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 300));
          final ignored = await _ignoredBeforePaying(tester, confirmation);
          count('detail opened ($at)', ignored);
          expect(ignored, 0);
          await confirmation.close();
        },
      );

      testWidgets(
        'the detail folded away from the page\'s end, then « Pay » 300 ms later ($at): none ignored',
        (tester) async {
          final confirmation = await opened(tester, width, scale, locale);
          await _openDetail(tester);
          final position = _position(tester);
          final room = tester.getSize(_detail).height;
          unawaited(
            Scrollable.ensureVisible(tester.element(_link), alignment: 0.8),
          );
          await tester.pump();
          await tester.pump(MovedTapGuard.afterMove);
          expect(
            position.pixels + room,
            lessThanOrEqualTo(position.maxScrollExtent),
            reason: 'not within the detail\'s height of the end',
          );
          final payBefore = tester.getTopLeft(confirmation.pay);
          await tester.tapAt(tester.getCenter(_link));
          await tester.pump();
          expect(_detail, findsNothing);
          expect(tester.getTopLeft(confirmation.pay), payBefore);
          await tester.pump(const Duration(milliseconds: 300));
          final ignored = await _ignoredBeforePaying(tester, confirmation);
          count('fold away from the end ($at)', ignored);
          expect(ignored, 0);
          await confirmation.close();
        },
      );

      // At ×3 the link is on the screen only beyond the detail's height of the page's end, where the fold moves nothing.
      if (scale == 1) {
        testWidgets(
          'the detail folded at the page\'s end, « Pay » moved down, then tapped where it now is 300 ms later ($at): one ignored, the cost of the guard',
          (tester) async {
            final confirmation = await opened(tester, width, scale, locale);
            await _openDetail(tester);
            // The first place before the page's end where the fold moves « Pay » down without bringing it under the finger.
            for (var back = 0.0; ; back += 8) {
              expect(back, lessThan(400));
              await _openDetail(tester);
              final position = _position(tester);
              position.jumpTo(position.maxScrollExtent - back);
              await tester.pump(MovedTapGuard.afterMove);
              final point = tester.getCenter(_link);
              if (!_viewport(tester).deflate(2).contains(point)) continue;
              final payBefore = tester.getTopLeft(confirmation.pay);
              await tester.tapAt(point);
              await tester.pump(const Duration(milliseconds: 16));
              if (_under(tester, point, confirmation) != 'pay' &&
                  tester.getTopLeft(confirmation.pay).dy > payBefore.dy) {
                break;
              }
              await tester.pump(MovedTapGuard.afterMove);
            }
            await tester.pump(const Duration(milliseconds: 284));
            final ignored = await _ignoredBeforePaying(tester, confirmation);
            count('fold at the end ($at)', ignored);
            expect(ignored, 1);
            await confirmation.close();
          },
        );
      }
    }

    testWidgets(
      'the screen built again without moving « Pay » (the app sent to the background and back, a read of the coordinator that changes nothing, the balance that changes), then « Pay » 100 ms later: none ignored',
      (tester) async {
        final confirmation = await opened(tester, 390, 1, const Locale('en'));
        Future<int> payAfter(Duration wait) async {
          await tester.pump(wait);
          final ignored = await _ignoredBeforePaying(tester, confirmation);
          return ignored;
        }

        // Back from the background.
        for (final state in const [
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
        await tester.pump(const Duration(milliseconds: 16));
        // A read of the coordinator, answered with nothing new.
        final before = confirmation.requests();
        for (var i = 0; i < 400 && confirmation.requests() == before; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(confirmation.requests(), greaterThan(before));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        // The balance after a sync of the wallet.
        confirmation.wallet.setBalance(Ok(Sats.fromInt(4900000)));
        await tester.pump();
        final rebuilt = await payAfter(const Duration(milliseconds: 100));
        count('rebuilt in place (background, read, balance)', rebuilt);
        expect(rebuilt, 0);
        await confirmation.close();
      },
    );

    testWidgets(
      'the tab « Order » then « Contract », then « Pay » 300 ms later: the card is built anew, as a button that appears',
      (tester) async {
        final confirmation = await opened(tester, 390, 1, const Locale('en'));
        Finder tab(String label) => find.descendant(
          of: find.byType(BullSegmented),
          matching: find.text(label),
        );
        await tester.tap(tab(confirmation.l10n.p2pNavOrder));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(confirmation.pay, findsNothing);
        await tester.tap(tab(confirmation.l10n.p2pTradeTabContract));
        await tester.pump();
        expect(confirmation.pay, findsOneWidget);
        expect(
          _viewport(tester).contains(tester.getCenter(confirmation.pay)),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 300));
        final ignored = await _ignoredBeforePaying(tester, confirmation);
        count('tab Order then Contract, Pay at 300 ms', ignored);
        expect(ignored, 1);
        await confirmation.close();
      },
    );

    for (final (gesture, from, to, expected) in const [
      (
        'the view grows by 40 points (a system bar that goes)',
        Size(390, 490),
        Size(390, 530),
        1,
      ),
      (
        'the view shrinks by 40 points (a system bar that comes)',
        Size(390, 490),
        Size(390, 450),
        0,
      ),
      (
        'the phone turned (390 × 490 to 490 × 390)',
        Size(390, 490),
        Size(490, 390),
        0,
      ),
      (
        'the phone turned back (490 × 390 to 390 × 490)',
        Size(490, 390),
        Size(390, 490),
        1,
      ),
    ]) {
      testWidgets(
        '$gesture, the page at its end, then « Pay » where it now is 300 ms later: $expected ignored',
        (tester) async {
          final confirmation = await opened(
            tester,
            from.width,
            1,
            const Locale('en'),
            height: from.height,
          );
          final position = _position(tester);
          position.jumpTo(position.maxScrollExtent);
          await tester.pump(MovedTapGuard.afterMove);
          tester.view.physicalSize = to * 3;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            _viewport(tester).contains(tester.getCenter(confirmation.pay)),
            isTrue,
          );
          final ignored = await _ignoredBeforePaying(tester, confirmation);
          count(gesture, ignored);
          expect(ignored, expected);
          await confirmation.close();
        },
      );
    }
  });

  group('« Continue » before a take (security review of #291, B1)', () {
    // At ×2 « Continue » is below the screen once the read's card is brought into view: the user scrolls to it first.
    for (final (height, scale) in const [(800.0, 1.0)]) {
      testWidgets(
        '390 × $height, the text ×$scale: the robot\'s read shown (the card brought into view, 300 ms), then « Continue » tapped 300 ms after the read goes on: « Continue » starts no delay when it appears (`armsWhenShown: false`)',
        (tester) async {
          await _taker(
            tester,
            atContinue: (l10n, advance) async {
              await _size(tester, height: height, scale: scale);
              final go = find.byWidgetPredicate(
                (widget) =>
                    widget is TradeButton &&
                    widget.label == l10n.p2pCommonContinue,
              );
              // From the frame « Continue » is shown, the read with it.
              var frames = 0;
              while (go.evaluate().isEmpty) {
                advance(const Duration(milliseconds: 16));
                await tester.pump(const Duration(milliseconds: 16));
                frames++;
                if (frames > 4000) fail('no read');
              }
              final busyAtFirst = tester.widget<TradeButton>(go).busy;
              final outcomes = <int, bool>{};
              var elapsed = 0;
              for (final ms in const [300, 500, 700, 900]) {
                await tester.pump(Duration(milliseconds: ms - elapsed));
                if (ms == 300) {
                  await tester.ensureVisible(go);
                  await tester.pump();
                }
                await tester.tapAt(tester.getCenter(go));
                await tester.pump(const Duration(milliseconds: 16));
                await tester.pump(const Duration(milliseconds: 16));
                elapsed = ms + 32;
                // Gone on: « Store your garage key » shown over the page, or « Continue » gone.
                final went =
                    go.evaluate().isEmpty ||
                    find.text(l10n.p2pCommonDone).evaluate().isNotEmpty ||
                    find.byType(BottomSheet).evaluate().isNotEmpty ||
                    find.byType(Dialog).evaluate().isNotEmpty;
                outcomes[ms] = went;
                if (went) break;
              }
              debugPrint(
                'GESTURE continue 390 × $height ×$scale: busy when shown: $busyAtFirst, went at $outcomes',
              );
              expect(outcomes[300], isTrue);
              // Back to the size the rest of the take is played at.
              await _size(tester, height: 3200);
            },
          );
        },
      );
    }
  });
}
