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
import 'package:p2p/src/ui/coordinator_details_dialog.dart'
    show CoordinatorBadge;
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/order_detail_row.dart' show OrderHostRow;
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

  /// For an order made here, its coordinator and its id, for a test that moves it on.
  final ScriptedMakerCoordinator? maker;
  final int? orderId;

  /// Moves the clock of the app and of its coordinator on, for an order made here.
  final void Function(Duration by) advance;

  _Confirmation(
    this.tester,
    this.locale,
    this.wallet,
    this.invoice,
    this.clock,
    this.close, {
    this.requests = _none,
    this.maker,
    this.orderId,
    this.advance = _stillClock,
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

void _stillClock(Duration by) => fail('no clock to move');

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

/// A sell order of 100 EUR made here at 50,000 EUR/BTC, on its trade screen: at its bond ([collateral] false), or its bond locked and taken by robot 5, at its collateral; the view at 390 × 490, the confirmation not yet opened. With [shell], the P2P pages are in a navigator nested in the root one, as the app's `ShellRoute` places them (`lib/router.dart`), so that the dialogs, opened on the root navigator, are on another navigator than the trade screen (#294).
Future<_Confirmation> _maker(
  WidgetTester tester, {
  bool collateral = false,
  Locale locale = const Locale('en'),
  bool shell = false,
}) async {
  await loadAppFont();
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
  final feature = const P2pFeature().route(locator, network: (_) => _net);
  final router = GoRouter(
    initialLocation: P2pFeature.path,
    routes: [
      if (shell)
        ShellRoute(builder: (_, _, child) => child, routes: [feature])
      else
        feature,
    ],
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
  return _Confirmation(
    tester,
    locale,
    wallet,
    invoice,
    () => clock,
    () async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
    requests: () => requests,
    maker: coordinator,
    orderId: record.orderId,
    advance: (by) => clock = clock.add(by),
  );
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

/// « Cancel » of the trade screen (`_CancelRow`).
Finder _cancelOf(P2pLocalizations l10n) => find.byWidgetPredicate(
  (widget) => widget is TradeButton && widget.label == l10n.p2pCommonCancel,
);

/// « Pay with this wallet » tapped, the Bull wallet's price read held; « Cancel » tapped while it is read, « Cancel the order? » opened over the screen; then the read let go: the confirmation is built and brought into view behind the dialog, and [behind] passes with the dialog still open (second security pass of #291, P7). Where « Pay » now stands.
Future<Offset> _builtBehindTheDialog(
  WidgetTester tester,
  _Confirmation confirmation, {
  Duration behind = const Duration(milliseconds: 1600),
}) async {
  final l10n = confirmation.l10n;
  final held = Completer<void>();
  confirmation.wallet
    ..rateHeld = held
    ..scriptQuote(Ok(confirmation.quote));
  final payWith = find.text(l10n.p2pPayWithThisWallet);
  await tester.ensureVisible(payWith);
  await tester.pump();
  await tester.tap(payWith);
  await tester.pump();
  final cancel = _cancelOf(l10n);
  await tester.ensureVisible(cancel);
  await tester.pump();
  await tester.tap(cancel);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text(l10n.p2pTradeCancelTitle), findsOneWidget);
  held.complete();
  for (var i = 0; i < 200 && confirmation.pay.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(confirmation.pay, findsOneWidget);
  // Frame by frame, as the screen's clock draws one every second at least.
  for (var waited = Duration.zero; waited < behind;) {
    await tester.pump(const Duration(milliseconds: 100));
    waited += const Duration(milliseconds: 100);
  }
  expect(find.text(l10n.p2pTradeCancelTitle), findsOneWidget);
  return _payOnTheBarrier(tester, confirmation);
}

/// The open dialog's card, not the `Dialog`, whose insets fill the screen.
Finder _dialogCard() => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

/// A point of « Pay » on the screen that the open dialog's card does not cover: its middle, or the middle of its part above or under the card (the barrier at the bottom of the screen, where the dialog is taller than the screen).
Offset _payOnTheBarrier(WidgetTester tester, _Confirmation confirmation) {
  final pay = tester.getRect(confirmation.pay).intersect(_viewport(tester));
  final card = tester.getRect(_dialogCard());
  if (!card.contains(pay.center)) return pay.center;
  if (pay.top < card.top - 2) {
    return Offset(pay.center.dx, (pay.top + card.top) / 2);
  }
  expect(pay.bottom, greaterThan(card.bottom + 2), reason: 'off the card');
  return Offset(pay.center.dx, (card.bottom + pay.bottom) / 2);
}

/// The open dialog closed by a double tap at [point], on its barrier, the second tap [gap] after the first: what lay under the finger at the second tap.
Future<String> _doubleTapOnTheBarrier(
  WidgetTester tester,
  _Confirmation confirmation,
  Offset point, {
  Duration gap = const Duration(milliseconds: 100),
}) async {
  expect(
    tester.getRect(_dialogCard()).contains(point),
    isFalse,
    reason: 'on the barrier',
  );
  await tester.tapAt(point);
  await tester.pump();
  await tester.pump(gap);
  final under = _under(tester, point, confirmation);
  await tester.tapAt(point);
  await tester.pump();
  // A payment, had the tap gone through, is asked of the wallet within these frames.
  await _answered(tester);
  return under;
}

/// « Confirm {amount} EUR received », the seller's button of the chat step.
Finder _receivedOf(P2pLocalizations l10n) {
  final pattern = RegExp(
    '^${RegExp.escape(l10n.p2pEndConfirmReceived('<a>', '<c>')).replaceFirst('<a>', '.+').replaceFirst('<c>', 'EUR')}\$',
  );
  return find.byWidgetPredicate(
    (widget) => widget is TradeButton && pattern.hasMatch(widget.label),
  );
}

/// The « Confirm » of the open dialog.
Finder _confirmIn(P2pLocalizations l10n) => find.descendant(
  of: find.byType(Dialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is TradeButton && widget.label == l10n.p2pEndConfirm,
  ),
);

/// The order made here as a seller, taken, its escrow locked, the buyer's invoice given and the fiat said sent: 10, its trade screen showing « Confirm … received ».
Future<_Confirmation> _sellerAt10(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final confirmation = await _maker(tester, collateral: true, locale: locale);
  final maker = confirmation.maker;
  final id = confirmation.orderId;
  if (maker == null || id == null) fail('no order made here');
  maker
    ..lockEscrow(id)
    ..buyerGivesInvoice(id)
    ..buyerSentFiat(id);
  final received = _receivedOf(confirmation.l10n);
  for (var i = 0; i < 120 && received.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(received, findsOneWidget);
  await tester.pump(MovedTapGuard.afterMove);
  return confirmation;
}

/// Whether the seller's confirmation of the fiat received reached the coordinator.
bool _released(_Confirmation confirmation) {
  final maker = confirmation.maker;
  final id = confirmation.orderId;
  if (maker == null || id == null) fail('no order made here');
  return maker.sellerConfirmations > 0;
}

/// A few frames for an answer of the coordinator to come.
Future<void> _answered(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// « Confirm … received » tapped, its dialog shown: at its first frame.
Future<void> _openReceived(
  WidgetTester tester,
  _Confirmation confirmation,
) async {
  final received = _receivedOf(confirmation.l10n);
  await tester.ensureVisible(received);
  await tester.pump();
  await tester.tap(received);
  await tester.pump();
  expect(find.byType(Dialog), findsOneWidget);
}

/// The open dialog's button labelled [label].
Finder _goIn(String label) => find.descendant(
  of: find.byType(Dialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is TradeButton && widget.label == label,
  ),
);

/// How many cancels (a cancel alone, or an ask or acceptance of a collaborative cancel) the order made here has received.
int _cancelsSent(_Confirmation confirmation) {
  final maker = confirmation.maker;
  if (maker == null) fail('no order made here');
  return maker.requests.where((request) {
    if (request.method != CoordinatorHttpMethod.post) return false;
    final body = jsonDecode(utf8.decode(request.body ?? const []));
    return body is Map<String, Object?> && body['action'] == 'cancel';
  }).length;
}

/// The status the coordinator stores for the order made here.
int _statusAt(_Confirmation confirmation) {
  final maker = confirmation.maker;
  final id = confirmation.orderId;
  if (maker == null || id == null) fail('no order made here');
  return maker.order(id).status;
}

/// Every list of the screen scrolled to its end, so that [finder], at the page's end, is built.
Future<void> _builtAtTheEnd(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 6 && finder.evaluate().isEmpty; i++) {
    for (final element in find.byType(Scrollable).evaluate().toList()) {
      if (element case StatefulElement(:final ScrollableState state)) {
        state.position.jumpTo(state.position.maxScrollExtent);
      }
    }
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

/// [opener] tapped twice at the middle of its part in view, the second tap [gap] after the first, as a finger that taps twice: whether the second tap landed on [go], the button that goes on of the dialog the first tap opened.
Future<bool> _doubleTap(
  WidgetTester tester,
  Finder opener,
  Finder go, {
  required Duration gap,
}) async {
  final viewport = tester.getRect(
    find.ancestor(of: opener, matching: find.byType(Scrollable)).first,
  );
  final point = tester.getRect(opener).intersect(viewport).center;
  await tester.tapAt(point);
  await tester.pump();
  await tester.pump(gap);
  final path = {
    for (final entry in tester.hitTestOnBinding(point).path) entry.target,
  };
  final onGo = go.evaluate().any(
    (element) => path.contains(element.renderObject),
  );
  await tester.tapAt(point);
  await tester.pump();
  await _answered(tester);
  return onGo;
}

/// The order made here as a seller, taken, its escrow locked and the buyer's invoice given: 9, the chat open, « … » (« Order options ») shown.
Future<_Confirmation> _sellerAt9(WidgetTester tester) async {
  final confirmation = await _maker(tester, collateral: true);
  final maker = confirmation.maker;
  final id = confirmation.orderId;
  if (maker == null || id == null) fail('no order made here');
  maker
    ..lockEscrow(id)
    ..buyerGivesInvoice(id);
  for (var i = 0; i < 120 && _options.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(_options, findsOneWidget);
  await tester.pump(MovedTapGuard.afterMove);
  return confirmation;
}

/// « … » of the chat step, which opens « Order options ».
final _options = find.byIcon(Icons.more_horiz);

/// « Order options » opened, its dialog shown: its « Collaborative Cancel ».
Future<Finder> _openOptions(WidgetTester tester, P2pLocalizations l10n) async {
  await tester.ensureVisible(_options);
  await tester.pump();
  await tester.tap(_options);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final collaborative = _goIn(l10n.p2pEndCollabCancel);
  expect(collaborative, findsOneWidget);
  return collaborative;
}

/// Taps [go] where it is [at] these times after the dialog's first frame, until [acted]: what each tap did.
Future<Map<int, bool>> _goneOnAt(
  WidgetTester tester,
  Finder go,
  bool Function() acted, {
  List<int> at = const [300, 500, 700, 900],
}) async {
  final outcomes = <int, bool>{};
  var elapsed = 0;
  for (final ms in at) {
    if (ms > elapsed) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
    }
    await tester.tapAt(tester.getCenter(go));
    await tester.pump();
    await _answered(tester);
    elapsed += 100;
    outcomes[ms] = acted();
    if (outcomes[ms] ?? false) break;
  }
  return outcomes;
}

/// How many disputes the order made here has received.
int _disputesSent(_Confirmation confirmation) {
  final maker = confirmation.maker;
  if (maker == null) fail('no order made here');
  return maker.requests.where((request) {
    if (request.method != CoordinatorHttpMethod.post) return false;
    final body = jsonDecode(utf8.decode(request.body ?? const []));
    return body is Map<String, Object?> && body['action'] == 'dispute';
  }).length;
}

/// The order made here as a seller, taken, its escrow locked and the buyer's invoice given: 9, or with [fiatSent] 10, its trade screen showing « … »; then the clock moved 7 hours on, so that « Open Dispute » of « Order options » is on (18 hours before the chat's end of 24).
Future<_Confirmation> _sellerInChat(
  WidgetTester tester, {
  required bool fiatSent,
  Locale locale = const Locale('en'),
}) async {
  final confirmation = await _maker(tester, collateral: true, locale: locale);
  final maker = confirmation.maker;
  final id = confirmation.orderId;
  if (maker == null || id == null) fail('no order made here');
  maker
    ..lockEscrow(id)
    ..buyerGivesInvoice(id);
  if (fiatSent) maker.buyerSentFiat(id);
  final shown = fiatSent ? _receivedOf(confirmation.l10n) : _options;
  for (var i = 0; i < 120 && shown.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  expect(shown, findsOneWidget);
  expect(_options, findsOneWidget);
  confirmation.advance(const Duration(hours: 7));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(MovedTapGuard.afterMove);
  return confirmation;
}

/// « Order options » opened, its dialog shown: its « Open Dispute », on.
Future<Finder> _openDisputeOption(
  WidgetTester tester,
  P2pLocalizations l10n,
) async {
  await tester.ensureVisible(_options);
  await tester.pump();
  await tester.tap(_options);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  final dispute = _goIn(l10n.p2pEndOpenDispute);
  expect(dispute, findsOneWidget);
  expect(tester.widget<TradeButton>(dispute).onPressed, isNotNull);
  return dispute;
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

  group('#294: « Pay » shown again from under a dialog', () {
    for (final (width, height, scale, locale) in const [
      (320.0, 490.0, 3.0, Locale('fr')),
      (390.0, 490.0, 2.0, Locale('en')),
    ]) {
      for (final shell in const [false, true]) {
        testWidgets(
          '$width × $height, the text ×$scale, ${locale.languageCode}${shell ? ', the app\'s nested navigator' : ''}: « Cancel » tapped while the quote is asked, the confirmation built behind « Cancel the order? » and its delay spent there; the dialog closed by a double tap on its barrier where « Pay » stands, the second tap 100 ms later on « Pay » pays nothing; the tap after the delay pays (second security pass of #291, P7)',
          (tester) async {
            final confirmation = await _maker(
              tester,
              locale: locale,
              shell: shell,
            );
            await _size(tester, width: width, height: height, scale: scale);
            final point = await _builtBehindTheDialog(tester, confirmation);
            final under = await _doubleTapOnTheBarrier(
              tester,
              confirmation,
              point,
            );
            expect(under, 'pay');
            expect(confirmation.wallet.paid, isEmpty);
            await tester.pump(MovedTapGuard.afterMove);
            expect(find.byType(Dialog), findsNothing);
            await tester.tapAt(point);
            await tester.pump();
            await _answered(tester);
            expect(confirmation.wallet.paid, hasLength(1));
            await confirmation.close();
          },
        );
      }
    }

    for (final shell in const [false, true]) {
      testWidgets(
        '390 × 490, the text ×2${shell ? ', the app\'s nested navigator' : ''}: the confirmation shown before the dialog, its delay long spent, « Cancel the order? » opened over it and the page behind it brought so that « Pay » stands at its bottom edge, on the barrier (a scroll, which sets no guard off): closed by a double tap there, the second tap pays nothing at 100, 300 and 500 ms; the tap after the delay pays',
        (tester) async {
          final confirmation = await _maker(tester, shell: shell);
          await _size(tester, scale: 2);
          await confirmation.open();
          final l10n = confirmation.l10n;
          for (final gap in const [100, 300, 500]) {
            final cancel = _cancelOf(l10n);
            await tester.ensureVisible(cancel);
            await tester.pump();
            await tester.pump(MovedTapGuard.afterMove);
            await tester.tap(cancel);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            unawaited(
              Scrollable.ensureVisible(
                tester.element(confirmation.pay),
                alignment: 1,
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final point = _payOnTheBarrier(tester, confirmation);
            final under = await _doubleTapOnTheBarrier(
              tester,
              confirmation,
              point,
              gap: Duration(milliseconds: gap),
            );
            expect(under, 'pay', reason: '$gap ms');
            expect(confirmation.wallet.paid, isEmpty, reason: '$gap ms');
            await tester.pump(MovedTapGuard.afterMove);
          }
          await tester.tapAt(tester.getCenter(confirmation.pay));
          await tester.pump();
          await _answered(tester);
          expect(confirmation.wallet.paid, hasLength(1));
          await confirmation.close();
        },
      );
    }

    void count(String gesture, int ignored) =>
        debugPrint('GESTURE $gesture: $ignored ignored');

    for (final (width, height, scale, locale) in const [
      (390.0, 490.0, 1.0, Locale('en')),
      (320.0, 800.0, 2.0, Locale('fr')),
    ]) {
      for (final read in const [false, true]) {
        final at = '$width × $height ×$scale ${locale.languageCode}';
        testWidgets(
          '« Cancel the order? » opened over the confirmation, the page at its end${read ? ', a read of the coordinator while it is open' : ''}, closed by its « Back », then « Pay » tapped on purpose 300, 500, 684 and 716 ms after that tap ($at): the taps within 0.7 s are ignored, the first after pays',
          (tester) async {
            final confirmation = await _maker(tester, locale: locale);
            await _size(tester, width: width, height: height, scale: scale);
            await confirmation.open();
            final l10n = confirmation.l10n;
            final cancel = _cancelOf(l10n);
            final position = _position(tester);
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            await tester.pump(MovedTapGuard.afterMove);
            for (final shown in [cancel, confirmation.pay]) {
              expect(
                _viewport(tester).contains(tester.getCenter(shown)),
                isTrue,
              );
            }
            await tester.tap(cancel);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            if (read) {
              final before = confirmation.requests();
              for (
                var i = 0;
                i < 400 && confirmation.requests() == before;
                i++
              ) {
                await tester.pump(const Duration(milliseconds: 50));
              }
              expect(confirmation.requests(), greaterThan(before));
              await _answered(tester);
            }
            final back = find.descendant(
              of: find.byType(Dialog),
              matching: find.text(l10n.p2pTradeCancelBack),
            );
            await tester.ensureVisible(back);
            await tester.pump();
            await tester.tap(back);
            await tester.pump();
            final outcomes = <int, bool>{};
            var elapsed = 0;
            // One frame before the delay's end and one after, so that no tap falls on its very end (functional review of #296, R5).
            for (final ms in const [300, 500, 684, 716]) {
              await tester.pump(Duration(milliseconds: ms - elapsed));
              elapsed = ms;
              await tester.tapAt(tester.getCenter(confirmation.pay));
              await tester.pump();
              outcomes[ms] = confirmation.wallet.paid.isNotEmpty;
              if (outcomes[ms] ?? false) break;
            }
            count(
              'dialog closed${read ? ' after a read' : ''} ($at): paid at $outcomes',
              outcomes.values.where((paid) => !paid).length,
            );
            expect(outcomes[300], isFalse);
            expect(outcomes[500], isFalse);
            expect(outcomes[684], isFalse);
            expect(outcomes[716], isTrue);
            await confirmation.close();
          },
        );
      }
    }
  });

  group('#293: the seller\'s « Confirm » of « Confirm … received »', () {
    void count(String gesture, int ignored) =>
        debugPrint('GESTURE $gesture: $ignored ignored');

    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'a second tap at the place of the panel\'s « Confirm … received » as its dialog opens, ${locale.languageCode}, at 320 and 390 points × 490, 640 and 800, the text ×1, ×2 and ×3, the button at the top, middle and bottom of the page\'s view, 16, 100, 300 and 600 ms after the first: nothing released; what lay under the finger counted',
        (tester) async {
          final confirmation = await _sellerAt10(tester, locale: locale);
          final l10n = confirmation.l10n;
          final received = _receivedOf(l10n);
          final counts = <String, int>{};
          for (final width in const [320.0, 390.0]) {
            for (final height in const [490.0, 640.0, 800.0]) {
              for (final scale in const [1.0, 2.0, 3.0]) {
                await _size(tester, width: width, height: height, scale: scale);
                for (final place in const [0.0, 0.5, 1.0]) {
                  for (final gap in const [16, 100, 300, 600]) {
                    await tester.ensureVisible(received);
                    unawaited(
                      Scrollable.ensureVisible(
                        tester.element(received),
                        alignment: place,
                      ),
                    );
                    await tester.pump();
                    await tester.pump(MovedTapGuard.afterMove);
                    final page = tester.getRect(
                      find
                          .ancestor(
                            of: received,
                            matching: find.byType(Scrollable),
                          )
                          .first,
                    );
                    final point = tester
                        .getRect(received)
                        .intersect(page)
                        .center;
                    await tester.tapAt(point);
                    await tester.pump();
                    await tester.pump(Duration(milliseconds: gap));
                    final path = {
                      for (final entry in tester.hitTestOnBinding(point).path)
                        entry.target,
                    };
                    final confirm = _confirmIn(l10n);
                    final under =
                        confirm.evaluate().any(
                          (element) => path.contains(element.renderObject),
                        )
                        ? 'confirm'
                        : find.byType(Dialog).evaluate().isEmpty
                        ? 'no dialog'
                        : 'other';
                    counts[under] = (counts[under] ?? 0) + 1;
                    await tester.tapAt(point);
                    await tester.pump();
                    await _answered(tester);
                    expect(
                      _released(confirmation),
                      isFalse,
                      reason: '$width × $height ×$scale $place $gap ms',
                    );
                    // Closed by its « Go back » when still open.
                    final goBack = find.descendant(
                      of: find.byType(Dialog),
                      matching: find.text(l10n.p2pCommonGoBack),
                    );
                    if (goBack.evaluate().isNotEmpty) {
                      await tester.ensureVisible(goBack);
                      await tester.pump();
                      await tester.tap(goBack);
                      await tester.pump();
                    }
                    await tester.pump(MovedTapGuard.afterMove);
                    expect(find.byType(Dialog), findsNothing);
                  }
                }
              }
            }
          }
          debugPrint('SECOND TAP ${locale.languageCode}: $counts');
          await confirmation.close();
        },
      );
    }

    for (final (width, height, scale) in const [
      (390.0, 700.0, 1.0),
      (360.0, 800.0, 1.0),
      (320.0, 800.0, 1.0),
    ]) {
      testWidgets(
        '$width × $height, the text ×$scale: the chat\'s keyboard of 280 points open, the dialog opened, the keyboard going in a quarter of a second: « Confirm » moves down; a tap at its new place 136 and 420 ms after the keyboard went is ignored, one at 880 ms releases',
        (tester) async {
          final confirmation = await _sellerAt10(tester);
          addTearDown(tester.view.resetViewInsets);
          await _size(tester, width: width, height: height, scale: scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280 * 3);
          await tester.pump();
          await tester.pump(MovedTapGuard.afterMove);
          await _openReceived(tester, confirmation);
          final confirm = _confirmIn(confirmation.l10n);
          final before = tester.getCenter(confirm);
          for (var frame = 1; frame <= 16; frame++) {
            tester.view.viewInsets = FakeViewPadding(
              bottom: 280 * 3 * (1 - frame / 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          // The dialog's padding follows the insets in 100 ms.
          await tester.pump(const Duration(milliseconds: 120));
          final after = tester.getCenter(confirm);
          debugPrint(
            'KEYBOARD $width × $height ×$scale: « Confirm » from ${before.dy} to ${after.dy}',
          );
          var elapsed = 120;
          final outcomes = <int, bool>{};
          for (final ms in const [136, 420, 880]) {
            if (ms > elapsed) {
              await tester.pump(Duration(milliseconds: ms - elapsed));
              elapsed = ms;
            }
            await tester.tapAt(tester.getCenter(confirm));
            await tester.pump();
            await _answered(tester);
            elapsed += 100;
            outcomes[ms] = _released(confirmation);
            if (outcomes[ms] ?? false) break;
          }
          count(
            'keyboard going under the seller\'s dialog ($width × $height ×$scale, « Confirm » ${before.dy.round()} → ${after.dy.round()}): released at $outcomes',
            outcomes.values.where((released) => !released).length,
          );
          if ((after.dy - before.dy).abs() > 0.5) {
            expect(outcomes[136], isFalse);
            expect(outcomes[420], isFalse);
          }
          expect(_released(confirmation), isTrue);
          await confirmation.close();
        },
      );
    }

    for (final (width, height, scale, locale) in const [
      (390.0, 800.0, 1.0, Locale('en')),
      (320.0, 640.0, 3.0, Locale('fr')),
      (320.0, 490.0, 3.0, Locale('en')),
    ]) {
      final at = '$width × $height ×$scale ${locale.languageCode}';
      testWidgets(
        'the dialog opened, brought to its end by a jump when taller than the screen (a scroll, which sets no guard off; a fling that hits the end would, by Android\'s stretch), then « Confirm » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame ($at): the taps within 0.7 s are ignored, the first after releases',
        (tester) async {
          final confirmation = await _sellerAt10(tester, locale: locale);
          await _size(tester, width: width, height: height, scale: scale);
          await _openReceived(tester, confirmation);
          final confirm = _confirmIn(confirmation.l10n);
          final dialogPosition = Scrollable.of(
            tester.element(confirm),
          ).position;
          final taller = dialogPosition.maxScrollExtent > 0;
          dialogPosition.jumpTo(dialogPosition.maxScrollExtent);
          await tester.pump();
          final outcomes = <int, bool>{};
          var elapsed = 0;
          for (final ms in const [300, 500, 700, 900]) {
            await tester.pump(Duration(milliseconds: ms - elapsed));
            elapsed = ms;
            await tester.tapAt(tester.getCenter(confirm));
            await tester.pump();
            await _answered(tester);
            elapsed += 100;
            outcomes[ms] = _released(confirmation);
            if (outcomes[ms] ?? false) break;
          }
          count(
            'seller\'s dialog opened ($at, taller than the screen: $taller): released at $outcomes',
            outcomes.values.where((released) => !released).length,
          );
          expect(outcomes[300], isFalse);
          expect(outcomes[500], isFalse);
          expect(_released(confirmation), isTrue);
          await confirmation.close();
        },
      );
    }

    testWidgets(
      'a read of the coordinator while the seller\'s dialog is open, then « Confirm » 100 ms after its answer: none ignored',
      (tester) async {
        final confirmation = await _sellerAt10(tester);
        await _openReceived(tester, confirmation);
        final confirm = _confirmIn(confirmation.l10n);
        // Taller than the screen of 490 points: brought to its end by a scroll.
        final dialogPosition = Scrollable.of(tester.element(confirm)).position;
        dialogPosition.jumpTo(dialogPosition.maxScrollExtent);
        await tester.pump(const Duration(seconds: 1));
        final before = confirmation.requests();
        for (var i = 0; i < 400 && confirmation.requests() == before; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(confirmation.requests(), greaterThan(before));
        await _answered(tester);
        await tester.pump(const Duration(milliseconds: 100));
        var ignored = 0;
        while (!_released(confirmation)) {
          expect(ignored, lessThan(5));
          await tester.tapAt(tester.getCenter(confirm));
          await tester.pump();
          await _answered(tester);
          if (!_released(confirmation)) {
            ignored++;
            await tester.pump(const Duration(milliseconds: 500));
          }
        }
        count('a read with the seller\'s dialog open', ignored);
        expect(ignored, 0);
        await confirmation.close();
      },
    );
  });
  group(
    '#298: a second tap on the button that opens a dialog whose « go » costs or cannot be undone',
    () {
      void count(String gesture, int ignored) =>
          debugPrint('GESTURE $gesture: $ignored ignored');

      for (final (width, height, scale) in const [
        (390.0, 800.0, 3.0),
        (360.0, 800.0, 3.0),
      ]) {
        for (final gap in const [100, 250]) {
          testWidgets(
            '$width × $height, the text ×$scale: a seller who made the order, at the escrow (6), the page at its end, « Cancel » tapped twice $gap ms apart: the second tap lands on « Confirm Cancel » and cancels nothing, the bond kept; a tap on it after the delay cancels (security review of #296, R1)',
            (tester) async {
              final confirmation = await _maker(tester, collateral: true);
              await _size(tester, width: width, height: height, scale: scale);
              final l10n = confirmation.l10n;
              final cancel = _cancelOf(l10n);
              await _builtAtTheEnd(tester, cancel);
              final position = Scrollable.of(tester.element(cancel)).position;
              position.jumpTo(position.maxScrollExtent);
              await tester.pump();
              await tester.pump(MovedTapGuard.afterMove);
              final go = _goIn(l10n.p2pTradeConfirmCancel);
              expect(
                await _doubleTap(
                  tester,
                  cancel,
                  go,
                  gap: Duration(milliseconds: gap),
                ),
                isTrue,
              );
              expect(_cancelsSent(confirmation), 0);
              expect(_statusAt(confirmation), 6);
              expect(go, findsOneWidget);
              await tester.pump(MovedTapGuard.afterMove);
              // Into view when the dialog is taller than the screen: a scroll, which sets no guard off.
              await tester.ensureVisible(go);
              await tester.pump();
              await tester.tapAt(tester.getCenter(go));
              await tester.pump();
              await _answered(tester);
              expect(_cancelsSent(confirmation), 1);
              expect(_statusAt(confirmation), 4);
              await confirmation.close();
            },
          );
        }
      }

      for (final gap in const [100, 250]) {
        testWidgets(
          '390 × 800, the text ×1: a maker at its bond (0), « Cancel » at the top of the page\'s view tapped twice $gap ms apart: the second tap lands on « Confirm cancellation » and cancels nothing; a tap on it after the delay cancels',
          (tester) async {
            final confirmation = await _maker(tester);
            await _size(tester, width: 390, height: 800);
            final l10n = confirmation.l10n;
            final cancel = _cancelOf(l10n);
            await _builtAtTheEnd(tester, cancel);
            unawaited(
              Scrollable.ensureVisible(tester.element(cancel), alignment: 0),
            );
            await tester.pump();
            await tester.pump(MovedTapGuard.afterMove);
            final go = _goIn(l10n.p2pTradeConfirmCancellation);
            expect(
              await _doubleTap(
                tester,
                cancel,
                go,
                gap: Duration(milliseconds: gap),
              ),
              isTrue,
            );
            expect(_cancelsSent(confirmation), 0);
            expect(_statusAt(confirmation), 0);
            expect(go, findsOneWidget);
            await tester.pump(MovedTapGuard.afterMove);
            // Into view when the dialog is taller than the screen: a scroll, which sets no guard off.
            await tester.ensureVisible(go);
            await tester.pump();
            await tester.tapAt(tester.getCenter(go));
            await tester.pump();
            await _answered(tester);
            expect(_cancelsSent(confirmation), 1);
            expect(_statusAt(confirmation), 4);
            await confirmation.close();
          },
        );

        testWidgets(
          '390 × 800, the text ×1: a seller at the chat (9), « Order options » opened, « Collaborative Cancel » tapped twice $gap ms apart: the second tap lands on « Ask for Cancel » and asks nothing; a tap on it after the delay asks',
          (tester) async {
            final confirmation = await _sellerAt9(tester);
            await _size(tester, width: 390, height: 800);
            final l10n = confirmation.l10n;
            final collaborative = await _openOptions(tester, l10n);
            final go = _goIn(l10n.p2pEndCollabAsk);
            expect(
              await _doubleTap(
                tester,
                collaborative,
                go,
                gap: Duration(milliseconds: gap),
              ),
              isTrue,
            );
            expect(_cancelsSent(confirmation), 0);
            expect(go, findsOneWidget);
            await tester.pump(MovedTapGuard.afterMove);
            // Into view when the dialog is taller than the screen: a scroll, which sets no guard off.
            await tester.ensureVisible(go);
            await tester.pump();
            await tester.tapAt(tester.getCenter(go));
            await tester.pump();
            await _answered(tester);
            expect(_cancelsSent(confirmation), 1);
            await confirmation.close();
          },
        );
      }

      for (final (width, height, scale, locale) in const [
        (390.0, 800.0, 1.0, Locale('en')),
        (360.0, 800.0, 3.0, Locale('fr')),
      ]) {
        final at = '$width × $height ×$scale ${locale.languageCode}';
        testWidgets(
          'the seller at the escrow (6): « Cancel » tapped once, then « Confirm Cancel » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame ($at): the taps within 0.7 s are ignored, the first after cancels',
          (tester) async {
            final confirmation = await _maker(
              tester,
              collateral: true,
              locale: locale,
            );
            await _size(tester, width: width, height: height, scale: scale);
            final l10n = confirmation.l10n;
            final cancel = _cancelOf(l10n);
            await _builtAtTheEnd(tester, cancel);
            await tester.ensureVisible(cancel);
            await tester.pump();
            await tester.pump(MovedTapGuard.afterMove);
            await tester.tap(cancel);
            await tester.pump();
            final go = _goIn(l10n.p2pTradeConfirmCancel);
            expect(go, findsOneWidget);
            await tester.ensureVisible(go);
            final outcomes = await _goneOnAt(
              tester,
              go,
              () => _cancelsSent(confirmation) > 0,
            );
            count(
              '« Confirm Cancel » after « Cancel » ($at): cancelled at $outcomes',
              outcomes.values.where((done) => !done).length,
            );
            expect(outcomes[300], isFalse);
            expect(outcomes[500], isFalse);
            expect(_cancelsSent(confirmation), 1);
            expect(_statusAt(confirmation), 4);
            await confirmation.close();
          },
        );
      }

      testWidgets(
        'a maker at its bond (0): « Cancel » tapped once, then « Confirm cancellation » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame (390 × 800 ×1 en): the taps within 0.7 s are ignored, the first after cancels',
        (tester) async {
          final confirmation = await _maker(tester);
          await _size(tester, width: 390, height: 800);
          final l10n = confirmation.l10n;
          final cancel = _cancelOf(l10n);
          await _builtAtTheEnd(tester, cancel);
          await tester.ensureVisible(cancel);
          await tester.pump();
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tap(cancel);
          await tester.pump();
          final go = _goIn(l10n.p2pTradeConfirmCancellation);
          expect(go, findsOneWidget);
          final outcomes = await _goneOnAt(
            tester,
            go,
            () => _cancelsSent(confirmation) > 0,
          );
          count(
            '« Confirm cancellation » at 0 (390 × 800 ×1 en): cancelled at $outcomes',
            outcomes.values.where((done) => !done).length,
          );
          expect(outcomes[300], isFalse);
          expect(outcomes[500], isFalse);
          expect(_cancelsSent(confirmation), 1);
          expect(_statusAt(confirmation), 4);
          await confirmation.close();
        },
      );

      testWidgets(
        'a seller at the chat (9): « Collaborative Cancel » tapped once, then « Ask for Cancel » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame (390 × 800 ×1 en): the taps within 0.7 s are ignored, the first after asks',
        (tester) async {
          final confirmation = await _sellerAt9(tester);
          await _size(tester, width: 390, height: 800);
          final l10n = confirmation.l10n;
          final collaborative = await _openOptions(tester, l10n);
          await tester.tap(collaborative);
          await tester.pump();
          final go = _goIn(l10n.p2pEndCollabAsk);
          expect(go, findsOneWidget);
          final outcomes = await _goneOnAt(
            tester,
            go,
            () => _cancelsSent(confirmation) > 0,
          );
          count(
            '« Ask for Cancel » after « Collaborative Cancel » (390 × 800 ×1 en): asked at $outcomes',
            outcomes.values.where((done) => !done).length,
          );
          expect(outcomes[300], isFalse);
          expect(outcomes[500], isFalse);
          expect(_cancelsSent(confirmation), 1);
          await confirmation.close();
        },
      );
    },
  );

  group('#301: « Agree and open dispute » of « Do you want to open a dispute? »', () {
    void count(String gesture, int ignored) =>
        debugPrint('GESTURE $gesture: $ignored ignored');

    for (final (fiatSent, width, height, scale, locale) in const [
      (true, 390.0, 800.0, 1.0, Locale('en')),
      (true, 320.0, 640.0, 3.0, Locale('fr')),
      (false, 360.0, 800.0, 2.0, Locale('en')),
    ]) {
      final at = '$width × $height ×$scale ${locale.languageCode}';
      final who = fiatSent ? 'a seller at 10 (fiat sent)' : 'a seller at 9';
      testWidgets(
        '$who, « Open Dispute » on: « Open Dispute » tapped once, then « Agree and open dispute » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame ($at): the taps at 300 and 500 ms are ignored, the one at 700 ms opens the dispute, once',
        (tester) async {
          final confirmation = await _sellerInChat(
            tester,
            fiatSent: fiatSent,
            locale: locale,
          );
          await _size(tester, width: width, height: height, scale: scale);
          final l10n = confirmation.l10n;
          final dispute = await _openDisputeOption(tester, l10n);
          await tester.tap(dispute);
          await tester.pump();
          final go = _goIn(l10n.p2pEndAgreeDispute);
          expect(go, findsOneWidget);
          // Into view when the dialog is taller than the screen: a scroll, which sets no guard off.
          await tester.ensureVisible(go);
          final outcomes = await _goneOnAt(
            tester,
            go,
            () => _disputesSent(confirmation) > 0,
          );
          count(
            '« Agree and open dispute » after « Open Dispute » ($who, $at): opened at $outcomes',
            outcomes.values.where((done) => !done).length,
          );
          // Ignored before 0.7 s, opened by the first tap after it (security review of #301, R3).
          expect(outcomes, {300: false, 500: false, 700: true});
          expect(_disputesSent(confirmation), 1);
          await confirmation.close();
        },
      );
    }

    for (final (width, height, scale, locale) in const [
      (320.0, 640.0, 3.0, Locale('fr')),
      (390.0, 800.0, 1.0, Locale('en')),
    ]) {
      final at = '$width × $height ×$scale ${locale.languageCode}';
      testWidgets(
        'a seller at 10 (fiat sent), « Open Dispute » on ($at): « Open Dispute » tapped twice 16, 100, 250 and 600 ms apart: the second tap never lands on « Agree and open dispute », no dispute sent (the sweep of #301)',
        (tester) async {
          final confirmation = await _sellerInChat(
            tester,
            fiatSent: true,
            locale: locale,
          );
          await _size(tester, width: width, height: height, scale: scale);
          final l10n = confirmation.l10n;
          final go = _goIn(l10n.p2pEndAgreeDispute);
          for (final gap in const [16, 100, 250, 600]) {
            final dispute = await _openDisputeOption(tester, l10n);
            expect(
              await _doubleTap(
                tester,
                dispute,
                go,
                gap: Duration(milliseconds: gap),
              ),
              isFalse,
              reason: '$gap ms',
            );
            expect(_disputesSent(confirmation), 0, reason: '$gap ms');
            await tester.pump(const Duration(milliseconds: 400));
            final disagree = _goIn(l10n.p2pEndDisagree);
            if (disagree.evaluate().isNotEmpty) {
              await tester.ensureVisible(disagree);
              await tester.pump();
              await tester.tap(disagree);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
            }
            expect(find.byType(Dialog), findsNothing);
            await tester.pump(MovedTapGuard.afterMove);
          }
          expect(_disputesSent(confirmation), 0);
          await confirmation.close();
        },
      );
    }
  });

  group('#300: the coordinator\'s dialog under the tab « Order »', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'a maker\'s bond, ${locale.languageCode}: the tab « Order », the host tapped; at 320 points (640 high, the text ×1, ×2 and ×3, and 800 high ×2) nothing overflows and the four badges fit the dialog\'s card, each 48 points wide at least, the last one\'s explanation shown on a tap; at 360 and 390 points each badge keeps its 56 points, side by side and centred, as before',
        (tester) async {
          final confirmation = await _maker(tester, locale: locale);
          final l10n = confirmation.l10n;
          await tester.tap(
            find.descendant(
              of: find.byType(BullSegmented),
              matching: find.text(l10n.p2pNavOrder),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final host = find.byType(OrderHostRow);
          await tester.ensureVisible(host);
          await tester.pump();
          await tester.tap(host);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          final badges = find.byType(CoordinatorBadge);
          expect(badges, findsNWidgets(4));
          for (final (width, height, scale) in const [
            (320.0, 640.0, 1.0),
            (320.0, 640.0, 2.0),
            (320.0, 640.0, 3.0),
            (320.0, 800.0, 2.0),
            (360.0, 640.0, 1.0),
            (390.0, 800.0, 1.0),
            (390.0, 800.0, 3.0),
          ]) {
            final at = '$width × $height ×$scale';
            await _size(tester, width: width, height: height, scale: scale);
            expect(tester.takeException(), isNull, reason: at);
            final card = tester.getRect(_dialogCard());
            final rects = [
              for (var index = 0; index < 4; index++)
                tester.getRect(badges.at(index)),
            ];
            for (final rect in rects) {
              expect(rect.left, greaterThanOrEqualTo(card.left), reason: at);
              expect(rect.right, lessThanOrEqualTo(card.right), reason: at);
              expect(rect.width, greaterThanOrEqualTo(48 - 0.01), reason: at);
            }
            if (width >= 360) {
              for (final (index, rect) in rects.indexed) {
                expect(
                  rect.width,
                  moreOrLessEquals(56, epsilon: 0.01),
                  reason: at,
                );
                if (index > 0) {
                  expect(
                    rect.left,
                    moreOrLessEquals(rects[index - 1].right, epsilon: 0.01),
                    reason: at,
                  );
                }
              }
              expect(
                (rects.first.left + rects.last.right) / 2,
                moreOrLessEquals(card.center.dx, epsilon: 0.01),
                reason: at,
              );
            }
          }
          await _size(tester, width: 320, height: 640, scale: 2);
          final last = tester.widget<CoordinatorBadge>(badges.last);
          await tester.ensureVisible(badges.last);
          await tester.pump();
          await tester.tap(badges.last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(last.explanation), findsOneWidget);
          await tester.pump(const Duration(seconds: 3));
          await confirmation.close();
        },
      );
    }
  });
}
