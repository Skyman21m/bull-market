import 'dart:async';
import 'dart:convert';

import 'package:bull_ui/bull_ui.dart' show BullTheme;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/price_check_lines.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/lean_confirmation.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// An order of the book taken on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`) by the user's gestures, in English and in French, and the owner's payment rule for a taken order (#249; design note `docs/design/phase-3-taken-order-price-check.md` § 3, § 5): the bond in the confirmation of « Pay with this wallet », a taker seller's escrow in its confirmation, a taker buyer's payout before « Submit » and in « Confirm … sent ».
///
/// The order's coordinator is played by `ScriptedCoordinator` (never a real one): the owner's example, 100 USD at +3.5 %, a bond of 3 %, the taker fee 0.175 %, its sats at the coordinator's price set per test (134,834 when its price is the Bull wallet's, 71,657 USD/BTC); the other coordinators' books are empty. The wallet is `FakeP2pWalletPort`: its price is the test's, a quote is scripted for each invoice offered, and nothing is ever paid (« Pay » is never tapped).
const _net = RobosatsNetwork.testnet;

/// temple's requests to [temple]; the other coordinators' books empty and their `/api/info/` their own.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedCoordinator temple;
  final Map<String, ScriptedCoordinator> _others = {};

  _Coordinators(this.temple);

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

final class _Journey {
  final WidgetTester tester;
  final ScriptedCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  final void Function(Duration) advance;
  final DateTime Function() clock;
  final Locale locale;

  _Journey(
    this.tester,
    this.coordinator,
    this.wallet,
    this.advance,
    this.clock,
    this.locale,
  );

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats =>
      P2pFormats.of(tester.element(find.byType(TradeScreen)));

  /// The robot whose pre-take the coordinator holds: this device's.
  RobotIdentity get robot =>
      TradeHarness.robotsOf(_net).firstWhere(coordinator.holdsPreTake);

  Future<void> waitUntil(bool Function() done, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (done()) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never done');
  }

  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  /// Pumps frames for [seconds] seconds of the screen's clock, the coordinator's moving with it.
  Future<void> pass(int seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  /// [sats]: the order's sats at the coordinator's price now; a buyer takes the sell order, a seller ([seller]) the buy order; [currency], the order's (1, USD; 7, CHF, which the Bull wallet does not price); [rate], the Bull wallet's price.
  static Future<_Journey> start(
    WidgetTester tester,
    Locale locale, {
    bool seller = false,
    int sats = 134834,
    int currency = 1,
    P2pWalletBitcoinRate? rate,
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
          // The coordinator's price with the premium, 5 significant digits, as its sats say it (`api/logics.py:290-293`).
          ..price = double.parse((1e10 / sats).toStringAsPrecision(5));
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(71657);
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
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
      () => clock,
      locale,
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

  /// The order of the book tapped, « Take Order », the robot's read shown, « Continue » and « Done »: the trade screen at the bond.
  Future<void> take() async {
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
    // The order page compared the read with the Bull wallet's price once, at « Take Order » (slice 4, `taken_price_page_route_test.dart`): the payments' own reads are counted from here.
    expect(wallet.ratesAsked, hasLength(1));
    wallet.ratesAsked.clear();
    await waitFor(find.text(l10n.p2pPayWithThisWallet));
  }

  /// A quote of [invoice] scripted, then « Pay with this wallet »: its confirmation.
  Future<P2pWalletQuote> confirm(Bolt11TestInvoice invoice) async {
    final checked = checkedBolt11InvoiceForTesting(
      bolt11: invoice.text,
      amount: invoice.facts.amount,
      network: _net,
      paymentHash: invoice.facts.paymentHash,
      expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
      now: clock(),
    );
    if (checked == null) fail('not a payable invoice');
    final quote = P2pWalletQuote(
      invoice: checked,
      payin: Sats(checked.amount.value + BigInt.from(300)),
      networkFee: Sats.fromInt(27),
      balance: Sats.fromInt(5000000),
      quotedAt: clock(),
    );
    wallet.scriptQuote(Ok(quote));
    await tap(find.text(l10n.p2pPayWithThisWallet));
    await settle(tester);
    await waitFor(find.text(l10n.p2pCommonGoBack));
    // « Pay » just shown ignores taps for a moment (security review of #291, B1): a user's tap comes later.
    await tester.pump(MovedTapGuard.afterMove);
    return quote;
  }

  /// The bond's confirmation.
  Future<P2pWalletQuote> confirmBond() async {
    final bond = coordinator.bondOf(robot);
    if (bond == null) fail('no bond');
    return confirm(bond);
  }

  /// « Go back », then the bond locked: the trade at 6, [shown] on the screen.
  Future<void> lockBond(Finder shown) async {
    await tap(find.text(l10n.p2pCommonGoBack));
    await settle(tester);
    coordinator.lockBond(robot);
    await waitFor(shown);
    await settle(tester);
  }

  /// The escrow's confirmation, at 6, once the coordinator made its invoice at a read of 6.
  Future<P2pWalletQuote> confirmEscrow() async {
    await waitUntil(() => coordinator.escrowInvoice != null);
    await settle(tester);
    await waitFor(find.text(l10n.p2pPayWithThisWallet));
    final escrow = coordinator.escrowInvoice;
    if (escrow == null) fail('no escrow invoice');
    return confirm(escrow);
  }

  /// The coordinator shows the trade with another premium for a read, then puts its own back (#231): its alert comes and goes, the trace of terms shown otherwise stays, in the warning colour.
  Future<void> termsShownOtherwise() async {
    coordinator.premium = 9;
    await waitFor(find.text(l10n.p2pTradeWarnTerms));
    coordinator.premium = 3.5;
    await waitUntil(() => find.text(l10n.p2pTradeWarnTerms).evaluate().isEmpty);
    await settle(tester);
  }

  String price() => formats.orderRate(71657);
  String sats(int value) => formats.bigSats(BigInt.from(value));
  String gap(int hundredths) => formats.gap(BigInt.from(hundredths));
  String get threshold => formats.threshold(TradeTolerances.walletRateGap);

  /// The bond's line: the bond expected at the Bull wallet's price, 4,045 sats, and the invoice's gap.
  String bondLine(int gapHundredths) =>
      l10n.p2pPayRateWallet(price(), 'USD', sats(4045), gap(gapHundredths));

  /// The red alert's line of figures in the confirmation (#250): the bond expected at the Bull wallet's price, 4,045 sats, and the bond asked.
  String bondFigures(int asked) =>
      l10n.p2pPayAgainstFigures(sats(4045), sats(asked));

  /// The escrow's line: 100 USD worth 134,834 sats at the Bull wallet's price, and the gap, the coordinator's fee included.
  String escrowLine(int gapHundredths) => l10n.p2pPayRateWalletEscrow(
    price(),
    'USD',
    formats.amount(_hundred),
    sats(134834),
    gap(gapHundredths),
  );

  /// The red alert's line of figures in the confirmation (#250): 100 USD worth 134,834 sats at the Bull wallet's price, and the escrow asked.
  String escrowFigures(int asked) =>
      l10n.p2pPayAgainstFigures(sats(134834), sats(asked));

  /// The escrow's sentence in the confirmation's detail (#250): the validated one when the coordinator asks more than expected, the earlier one, with the gap's sign, at or below.
  String escrowSentence(int gapHundredths) => gapHundredths > 0
      ? l10n.p2pPayRateDetail(
          formats.amount(_hundred),
          'USD',
          price(),
          sats(134834),
          formats.gapSize(BigInt.from(gapHundredths)),
        )
      : escrowLine(gapHundredths);

  /// The confirmation's card (#250).
  Finder get card => find.byType(PayConfirmationCard);

  Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);

  /// The rule's lines of the confirmation (#250): on arrival the gap « (indicative) », or in its place the red alert's two lines (« Gap against you », then [figures]), never the comparison's sentence; in the detail the comparison's [sentence] and, for a gap within 10 % both ways, « A small gap is normal », or the alert's explanation, never both. The detail closed again after.
  Future<void> expectCheck({
    required int gap,
    required bool warns,
    required String figures,
    required String sentence,
  }) async {
    expect(
      inCard(find.text(l10n.p2pPayoutBreakdownGap)),
      warns ? findsNothing : findsOneWidget,
    );
    expect(
      inCard(find.text(l10n.p2pPayoutBreakdownAgainst)),
      warns ? findsOneWidget : findsNothing,
    );
    expect(inCard(find.text(this.gap(gap))), findsOneWidget);
    expect(find.text(figures), warns ? findsOneWidget : findsNothing);
    expect(find.text(sentence), findsNothing);
    await tap(inCard(find.text(l10n.p2pDetailShow)));
    expect(find.text(sentence), warns ? findsNothing : findsOneWidget);
    // « A small gap is normal » beside a gap within the threshold both ways only (functional review of #268, C1).
    expect(
      find.text(l10n.p2pPayoutBreakdownSmallGap),
      !warns && gap.abs() <= 1000 ? findsOneWidget : findsNothing,
    );
    expect(
      find.text(l10n.p2pPayAgainstDetail(price(), 'USD', threshold)),
      warns ? findsOneWidget : findsNothing,
    );
    await tap(inCard(find.text(l10n.p2pDetailHide)));
  }

  /// The red alert's line of figures (#250), in the breakdown at 6 and 8 and in « Confirm … sent » at 9: 100 USD worth 134,834 sats at the Bull wallet's price, and the sats the coordinator pays.
  String payoutWarning(int received) =>
      l10n.p2pPayoutBreakdownAgainstFigures(sats(134834), sats(received));

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }
}

final FiatAmount _hundred = switch (FiatAmount.tryCreate(100)) {
  final amount? => amount,
  null => throw StateError('no amount'),
};

/// The coordinator's sats for the bond, escrow or payout a test names: the trade's sats at its price, from which it makes the bond (`int(sats × 3 / 100)`), the escrow and the payout (± the taker fee, rounded).
typedef _Case = ({int sats, int asked, int gap, bool warns});

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;

    group('a taker buyer, $code', () {
      for (final bond in <_Case>[
        // The owner's example: the coordinator's price is the Bull wallet's.
        (sats: 134834, asked: 4045, gap: -1, warns: false),
        // Its bounds.
        (sats: 148300, asked: 4449, gap: 999, warns: false),
        (sats: 148334, asked: 4450, gap: 1002, warns: true),
        // The coordinator's price 20 % too high, then ten times too low.
        (sats: 112362, asked: 3370, gap: -1669, warns: false),
        (sats: 1348344, asked: 40450, gap: 90000, warns: true),
      ]) {
        testWidgets(
          'the bond of ${bond.asked} sats: the line at the Bull wallet\'s price${bond.warns ? ' and the red warning' : ', no warning'}',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              sats: bond.sats,
            );
            await journey.take();
            await journey.confirmBond();
            await journey.expectCheck(
              gap: bond.gap,
              warns: bond.warns,
              figures: journey.bondFigures(bond.asked),
              sentence: journey.bondLine(bond.gap),
            );
            // « Pay » stays offered: never a lock.
            expect(
              find.text(
                journey.l10n.p2pPayConfirm(
                  journey.formats.sats(bond.asked + 327),
                ),
              ),
              findsOneWidget,
            );
            expect(journey.wallet.ratesAsked.single.$2.code, 'USD');
            expect(journey.wallet.paid, isEmpty);
            await journey.close();
          },
        );
      }

      for (final payout in <_Case>[
        (sats: 134834, asked: 134598, gap: -18, warns: false),
        (sats: 121565, asked: 121352, gap: -1000, warns: false),
        (sats: 121564, asked: 121351, gap: -1001, warns: true),
        (sats: 112362, asked: 112165, gap: -1682, warns: true),
        (sats: 1348344, asked: 1345984, gap: 89825, warns: false),
      ]) {
        testWidgets(
          'the payout of ${payout.asked} sats before « Submit »: compared with the Bull wallet\'s price${payout.warns ? ', the red warning' : ', no warning'}',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              sats: payout.sats,
            );
            await journey.take();
            await journey.confirmBond();
            await journey.lockBond(
              find.textContaining(journey.sats(payout.asked)),
            );
            await journey.waitFor(find.textContaining(journey.gap(payout.gap)));
            expect(
              find.text(journey.payoutWarning(payout.asked)),
              payout.warns ? findsOneWidget : findsNothing,
            );
            // The breakdown's gap line, « (indicative) », or in its place the red alert's bold line (#250).
            expect(
              find.text(journey.l10n.p2pPayoutBreakdownAgainst),
              payout.warns ? findsOneWidget : findsNothing,
            );
            expect(
              find.text(journey.l10n.p2pPayoutBreakdownGap),
              payout.warns ? findsNothing : findsOneWidget,
            );
            expect(journey.wallet.paid, isEmpty);
            await journey.close();
          },
        );
      }

      testWidgets(
        '« Confirm … sent » at 9: the dialog says the red warning of a price 20 % too high',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 112362);
          await journey.take();
          await journey.confirmBond();
          final warning = journey.payoutWarning(112165);
          await journey.lockBond(find.text(warning));
          journey.coordinator
            ..lockEscrow()
            ..moveTo(9);
          final confirm = find.text(
            journey.l10n.p2pEndConfirmSent(
              journey.formats.amount(_hundred),
              'USD',
            ),
          );
          await journey.waitFor(confirm);
          await journey.tap(confirm);
          await settle(tester);
          expect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.text(warning),
            ),
            findsOneWidget,
          );
          // Its explanation as a third line, there being no detail here (security review of #250, R4).
          expect(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.text(
                journey.l10n.p2pPayoutBreakdownAgainstDetail(journey.threshold),
              ),
            ),
            findsOneWidget,
          );
          await journey.close();
        },
      );
    });

    group('a taker buyer\'s lean breakdown at 6 (#228, #250), $code', () {
      String row(WidgetTester tester, Key key) => [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        ))
          text.data ?? '',
      ].last;
      Color? colourOf(WidgetTester tester, Key key) => tester
          .widgetList<Text>(
            find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          )
          .last
          .style
          ?.color;

      /// « Show details » then « Hide details » (#250, the owner's decision of 2026-11-24: the validated mock-up): the link in the breakdown's card under the rule's lines, seen on arrival on a phone of 720 × 1280 pixels; the detail opens in the card under it, the buttons moving down; closed, everything back in its place; [open] checks the detail while it is open.
      Future<void> detail(
        _Journey journey,
        void Function() open, {
        bool arrival = true,
      }) async {
        final tester = journey.tester;
        final l10n = journey.l10n;
        final card = find.byType(PayoutBreakdownView);
        final toggle = find.byKey(PayoutPanel.detailToggle);
        final buttons = [
          find.text(l10n.p2pPayoutWalletGenerateInvoice),
          find.widgetWithText(TradeButton, l10n.p2pPayoutSubmit),
        ];
        expect(find.descendant(of: card, matching: toggle), findsOneWidget);
        final checks = find.descendant(
          of: card,
          matching: find.byType(PayoutCheckLines),
        );
        if (checks.evaluate().isNotEmpty) {
          expect(
            tester.getTopLeft(toggle).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(checks).dy),
          );
        }
        // Seen without scrolling on a phone of 720 × 1280 pixels; with an alert's two lines, the tests' font (wider than the app's) wraps them further down, so the arrival with an alert is checked on the captures, drawn with the app's font.
        final alert =
            find.byKey(PayoutCheckLines.alertRow).evaluate().isNotEmpty ||
            find.byKey(PayoutCheckLines.unverifiedRow).evaluate().isNotEmpty;
        if (!alert && arrival) {
          final size = tester.view.physicalSize;
          final ratio = tester.view.devicePixelRatio;
          tester.view
            ..physicalSize = const Size(720, 1280)
            ..devicePixelRatio = 2;
          await tester.pump();
          expect(tester.getBottomLeft(toggle).dy, lessThanOrEqualTo(640));
          tester.view
            ..physicalSize = size
            ..devicePixelRatio = ratio;
          await tester.pump();
        }
        final before = [for (final b in buttons) tester.getTopLeft(b)];
        expect(find.byKey(PayoutPanel.detail), findsNothing);
        await tester.tap(find.text(l10n.p2pDetailShow));
        await tester.pump();
        final detail = find.byKey(PayoutPanel.detail);
        expect(find.descendant(of: card, matching: detail), findsOneWidget);
        expect(
          tester.getTopLeft(detail).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(toggle).dy),
        );
        expect(
          tester.getTopLeft(buttons.first).dy,
          greaterThan(before.first.dy),
        );
        open();
        await tester.tap(find.text(l10n.p2pDetailHide));
        await tester.pump();
        expect(find.byKey(PayoutPanel.detail), findsNothing);
        expect([for (final b in buttons) tester.getTopLeft(b)], before);
      }

      testWidgets(
        'the coordinator\'s price as the Bull wallet\'s: the sats paid, the routing fees, what will be received, the gap « (indicative) »; in the detail what Bull Wallet expected and « A small gap is normal »',
        (tester) async {
          final journey = await _Journey.start(tester, locale);
          final l10n = journey.l10n;
          await journey.take();
          await journey.confirmBond();
          await journey.lockBond(find.byKey(PayoutCheckLines.gapRow));
          expect(
            row(tester, PayoutBreakdownView.givenRow),
            journey.sats(134598),
          );
          // 1,000 ppm of 134,598 is 134.598: an invoice of 134,463 (`api/logics.py:869-872`).
          expect(row(tester, PayoutBreakdownView.feesRow), journey.sats(-135));
          expect(
            row(tester, PayoutBreakdownView.receivedRow),
            journey.sats(134463),
          );
          expect(find.text(l10n.p2pPayoutBreakdownGap), findsOneWidget);
          expect(row(tester, PayoutCheckLines.gapRow), journey.gap(-18));
          // No sentence of the rule above the breakdown, nor « Submit invoice for … » beside « You will receive ».
          expect(find.textContaining(journey.sats(134834)), findsNothing);
          expect(
            find.text(l10n.p2pPayoutSubmitInvoiceFor(journey.sats(134463))),
            findsNothing,
          );
          await detail(journey, () {
            expect(
              row(tester, PayoutBreakdownDetail.valueRow),
              journey.sats(134834),
            );
            expect(
              find.text(
                l10n.p2pPayoutBreakdownPrice(
                  journey.formats.amount(_hundred),
                  'USD',
                  journey.price(),
                ),
              ),
              findsOneWidget,
            );
            expect(
              row(tester, PayoutBreakdownDetail.invoiceRow),
              journey.sats(134463),
            );
            expect(find.text(l10n.p2pPayoutBreakdownSmallGap), findsOneWidget);
          });
          expect(journey.wallet.paid, isEmpty);
          await journey.close();
        },
      );

      testWidgets(
        'a coordinator\'s price ten times too low, so ten times the sats paid: the gap « (indicative) » alone, never « A small gap is normal » beside a gap that large (functional review of #268, C1)',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 1348344);
          final l10n = journey.l10n;
          await journey.take();
          await journey.confirmBond();
          await journey.lockBond(find.byKey(PayoutCheckLines.gapRow));
          expect(row(tester, PayoutCheckLines.gapRow), journey.gap(89825));
          expect(find.text(l10n.p2pPayoutBreakdownAgainst), findsNothing);
          await detail(journey, () {
            expect(find.byKey(PayoutBreakdownDetail.valueRow), findsOneWidget);
            expect(find.text(l10n.p2pPayoutBreakdownSmallGap), findsNothing);
          }, arrival: false);
          await journey.close();
        },
      );

      testWidgets(
        'a coordinator\'s price 20 % too high: the red alert in the breakdown, the figure paid in red, the two figures, no « (indicative) » and never « A small gap is normal »; nothing blocked',
        (tester) async {
          final journey = await _Journey.start(tester, locale, sats: 112362);
          final l10n = journey.l10n;
          await journey.take();
          await journey.confirmBond();
          await journey.lockBond(find.byKey(PayoutCheckLines.alertRow));
          final error = Theme.of(
            tester.element(find.byKey(PayoutBreakdownView.givenRow)),
          ).extension<BullTheme>()?.error;
          expect(find.text(l10n.p2pPayoutBreakdownAgainst), findsOneWidget);
          expect(row(tester, PayoutCheckLines.alertRow), journey.gap(-1682));
          expect(colourOf(tester, PayoutCheckLines.alertRow), error);
          expect(colourOf(tester, PayoutBreakdownView.givenRow), error);
          expect(find.text(journey.payoutWarning(112165)), findsOneWidget);
          expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
          // « You will receive » 112,052 and nothing else of the invoice on arrival (#249's functional review: never beside « Submit invoice for 112,052 Sats »).
          expect(
            row(tester, PayoutBreakdownView.receivedRow),
            journey.sats(112052),
          );
          expect(
            find.text(l10n.p2pPayoutSubmitInvoiceFor(journey.sats(112052))),
            findsNothing,
          );
          expect(
            find.textContaining(
              // « Submit invoice for » / « Soumettre la facture pour »: the reference's line, whatever its figure and its unit's case.
              l10n.p2pPayoutSubmitInvoiceFor('').split('  ').first,
            ),
            findsNothing,
          );
          await detail(journey, () {
            expect(find.text(l10n.p2pPayoutBreakdownSmallGap), findsNothing);
            expect(
              find.text(
                l10n.p2pPayoutBreakdownAgainstDetail(journey.threshold),
              ),
              findsOneWidget,
            );
          });
          final submit = find.widgetWithText(TradeButton, l10n.p2pPayoutSubmit);
          expect(submit, findsOneWidget);
          expect(journey.wallet.paid, isEmpty);
          await journey.close();
        },
      );

      testWidgets(
        'the Bull wallet\'s price not read: « Amount not checked » in orange with its line, then « Retry » reads it and the gap takes its place',
        (tester) async {
          final journey = await _Journey.start(
            tester,
            locale,
            rate: const P2pWalletRateUnavailable(),
          );
          final l10n = journey.l10n;
          await journey.take();
          await journey.confirmBond();
          await journey.tap(find.text(l10n.p2pCommonGoBack));
          await settle(tester);
          journey.coordinator.lockBond(journey.robot);
          await journey.waitFor(find.byKey(PayoutCheckLines.unverifiedRow));
          await settle(tester);
          final warning = Theme.of(
            tester.element(find.byKey(PayoutBreakdownView.givenRow)),
          ).extension<BullTheme>()?.warning;
          expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsOneWidget);
          expect(
            tester
                .widget<Text>(find.text(l10n.p2pPayoutBreakdownUnverified))
                .style
                ?.color,
            warning,
          );
          expect(
            find.text(l10n.p2pPayoutBreakdownUnverifiedLine),
            findsOneWidget,
          );
          expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
          await detail(journey, () {
            expect(
              find.text(l10n.p2pPayoutBreakdownUnverifiedDetail),
              findsOneWidget,
            );
            expect(find.text(l10n.p2pPayoutBreakdownSmallGap), findsNothing);
          });
          final asks = journey.wallet.ratesAsked.length;
          journey.wallet.rate = P2pWalletRateRead(71657);
          await journey.tap(find.text(l10n.p2pCommonRetry));
          await journey.waitFor(find.byKey(PayoutCheckLines.gapRow));
          expect(journey.wallet.ratesAsked, hasLength(asks + 1));
          expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
          expect(row(tester, PayoutCheckLines.gapRow), journey.gap(-18));
          await journey.close();
        },
      );

      testWidgets(
        'beside the trace of terms shown otherwise (#231): a gap within the threshold leaves the breakdown, and « A small gap is normal » its detail; a red alert stays',
        (tester) async {
          for (final (sats, red) in [(134834, false), (112362, true)]) {
            final journey = await _Journey.start(tester, locale, sats: sats);
            final l10n = journey.l10n;
            await journey.take();
            await journey.confirmBond();
            await journey.lockBond(find.byKey(PayoutBreakdownView.givenRow));
            await journey.termsShownOtherwise();
            await journey.pass(1);
            expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
            expect(
              find.text(l10n.p2pPayoutBreakdownAgainst),
              red ? findsOneWidget : findsNothing,
            );
            // The trace's line above the breakdown: not an arrival.
            await detail(journey, () {
              expect(find.text(l10n.p2pPayoutBreakdownSmallGap), findsNothing);
              expect(
                find.byKey(PayoutBreakdownDetail.valueRow),
                red ? findsOneWidget : findsNothing,
              );
            }, arrival: false);
            await journey.close();
          }
        },
      );
    });

    group('a taker seller, $code', () {
      for (final bond in <_Case>[
        (sats: 134834, asked: 4045, gap: -1, warns: false),
        (sats: 112362, asked: 3370, gap: -1669, warns: false),
        (sats: 1348344, asked: 40450, gap: 90000, warns: true),
      ]) {
        testWidgets(
          'the bond of ${bond.asked} sats${bond.warns ? ': the red warning' : ': no warning'}',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              seller: true,
              sats: bond.sats,
            );
            await journey.take();
            await journey.confirmBond();
            await journey.expectCheck(
              gap: bond.gap,
              warns: bond.warns,
              figures: journey.bondFigures(bond.asked),
              sentence: journey.bondLine(bond.gap),
            );
            await journey.close();
          },
        );
      }

      for (final escrow in <_Case>[
        (sats: 134834, asked: 135070, gap: 18, warns: false),
        (sats: 148058, asked: 148317, gap: 1000, warns: false),
        (sats: 148059, asked: 148318, gap: 1001, warns: true),
        (sats: 112362, asked: 112559, gap: -1653, warns: false),
        (sats: 1348344, asked: 1350704, gap: 90175, warns: true),
      ]) {
        testWidgets(
          'the escrow of ${escrow.asked} sats: the escrow\'s line${escrow.warns ? ' and its warning, one red alert' : ', no warning'}',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              seller: true,
              sats: escrow.sats,
            );
            await journey.take();
            await journey.confirmBond();
            await journey.lockBond(
              find.text(journey.l10n.p2pPayWithThisWallet),
            );
            await journey.confirmEscrow();
            await journey.expectCheck(
              gap: escrow.gap,
              warns: escrow.warns,
              figures: journey.escrowFigures(escrow.asked),
              sentence: journey.escrowSentence(escrow.gap),
            );
            expect(journey.wallet.ratesAsked, hasLength(2));
            expect(journey.wallet.paid, isEmpty);
            await journey.close();
          },
        );
      }
    });

    testWidgets(
      'a taker seller\'s escrow confirmation open, then the coordinator\'s amounts no longer agree, $code: the state machine\'s alert alone, no comparison beside it, « Pay » still offered',
      (tester) async {
        final journey = await _Journey.start(tester, locale, seller: true);
        await journey.take();
        await journey.confirmBond();
        await journey.lockBond(find.text(journey.l10n.p2pPayWithThisWallet));
        await journey.confirmEscrow();
        final line = journey.inCard(find.byKey(PriceCheckLines.gapRow));
        expect(line, findsOneWidget);
        // `trade_satoshis` no longer the escrow's (`EscrowAmountMismatch`).
        journey.coordinator.tradeSatoshisAnswered = 100000;
        await journey.waitUntil(() => line.evaluate().isEmpty);
        await settle(tester);
        expect(find.text(journey.l10n.p2pCommonGoBack), findsOneWidget);
        expect(line, findsNothing);
        // Nor in the detail: neither the comparison's sentence nor « A small gap is normal ».
        await journey.tap(find.text(journey.l10n.p2pDetailShow));
        expect(find.text(journey.escrowSentence(18)), findsNothing);
        expect(
          find.text(journey.l10n.p2pPayoutBreakdownSmallGap),
          findsNothing,
        );
        expect(find.textContaining(journey.sats(134834)), findsNothing);
        expect(journey.wallet.paid, isEmpty);
        await journey.close();
      },
    );

    group(
      'beside the trace of terms shown otherwise (#231) or of a payout not given from this wallet (#204), $code: a comparison within the threshold is not drawn, a red one is (security review, C1 and C2)',
      () {
        testWidgets('a taker buyer\'s bond', (tester) async {
          final journey = await _Journey.start(tester, locale);
          await journey.take();
          await journey.termsShownOtherwise();
          await journey.confirmBond();
          expect(journey.wallet.ratesAsked, hasLength(1));
          expect(
            journey.inCard(find.byKey(PriceCheckLines.gapRow)),
            findsNothing,
          );
          expect(find.textContaining(journey.sats(4045)), findsWidgets);
          await journey.tap(find.text(journey.l10n.p2pDetailShow));
          expect(find.text(journey.bondLine(-1)), findsNothing);
          expect(
            find.text(journey.l10n.p2pPayoutBreakdownSmallGap),
            findsNothing,
          );
          expect(journey.wallet.paid, isEmpty);
          await journey.close();
        });

        testWidgets(
          'a taker buyer\'s bond ten times too large: the red lines stay',
          (tester) async {
            final journey = await _Journey.start(tester, locale, sats: 1348344);
            await journey.take();
            await journey.termsShownOtherwise();
            await journey.confirmBond();
            await journey.expectCheck(
              gap: 90000,
              warns: true,
              figures: journey.bondFigures(40450),
              sentence: journey.bondLine(90000),
            );
            await journey.close();
          },
        );

        testWidgets('a taker seller\'s escrow', (tester) async {
          final journey = await _Journey.start(tester, locale, seller: true);
          await journey.take();
          await journey.confirmBond();
          await journey.lockBond(find.text(journey.l10n.p2pPayWithThisWallet));
          await journey.waitUntil(
            () => journey.coordinator.escrowInvoice != null,
          );
          await journey.termsShownOtherwise();
          await journey.confirmEscrow();
          expect(journey.wallet.ratesAsked, hasLength(2));
          expect(
            journey.inCard(find.byKey(PriceCheckLines.gapRow)),
            findsNothing,
          );
          await journey.tap(find.text(journey.l10n.p2pDetailShow));
          expect(find.text(journey.escrowSentence(18)), findsNothing);
          expect(
            find.text(journey.l10n.p2pPayoutBreakdownSmallGap),
            findsNothing,
          );
          expect(journey.wallet.paid, isEmpty);
          await journey.close();
        });

        testWidgets('a taker buyer\'s payout before « Submit »', (
          tester,
        ) async {
          final journey = await _Journey.start(tester, locale);
          await journey.take();
          await journey.confirmBond();
          await journey.lockBond(find.textContaining(journey.sats(134598)));
          await journey.waitFor(find.textContaining(journey.gap(-18)));
          await journey.termsShownOtherwise();
          await journey.waitUntil(
            () => find.textContaining(journey.gap(-18)).evaluate().isEmpty,
          );
          expect(find.textContaining(journey.gap(-18)), findsNothing);
          await journey.close();
        });

        testWidgets(
          'a taker buyer at 9, its payout not given from Bull Market: no comparison within the threshold, on the screen nor in « Confirm … sent »',
          (tester) async {
            final journey = await _Journey.start(tester, locale);
            await journey.take();
            await journey.confirmBond();
            await journey.lockBond(find.textContaining(journey.gap(-18)));
            journey.coordinator
              ..lockEscrow()
              ..moveTo(9);
            final confirm = find.text(
              journey.l10n.p2pEndConfirmSent(
                journey.formats.amount(_hundred),
                'USD',
              ),
            );
            await journey.waitFor(confirm);
            await journey.waitFor(
              find.text(journey.l10n.p2pPayoutTraceNotGivenHere),
            );
            await settle(tester);
            expect(find.textContaining(journey.gap(-18)), findsNothing);
            await journey.tap(confirm);
            await settle(tester);
            expect(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.textContaining(journey.gap(-18)),
              ),
              findsNothing,
            );
            await journey.close();
          },
        );
      },
    );

    testWidgets(
      'a taker seller\'s red escrow confirmation open, then an alert of the amounts, then one that is not about them, then a clean read, $code: the red comparison stays throughout, never silenced by another alert, and « Pay » pays (security review, C5)',
      (tester) async {
        final journey = await _Journey.start(
          tester,
          locale,
          seller: true,
          sats: 1348344,
        );
        final l10n = journey.l10n;
        await journey.take();
        await journey.confirmBond();
        await journey.lockBond(find.text(l10n.p2pPayWithThisWallet));
        await journey.confirmEscrow();
        final red = find.text(journey.escrowFigures(1350704));
        expect(red, findsOneWidget);
        expect(
          journey.inCard(find.text(l10n.p2pPayoutBreakdownAgainst)),
          findsOneWidget,
        );
        // `trade_satoshis` no longer the escrow's (`EscrowAmountMismatch`).
        journey.coordinator.tradeSatoshisAnswered = 100000;
        final amounts = find.text(l10n.p2pTradeWarnAmounts('Temple of Sats'));
        await journey.waitFor(amounts);
        await settle(tester);
        expect(red, findsOneWidget);
        // The amounts agree again; the order shown with another premium (`TradeTermsChanged`), then its own: the trace of terms shown otherwise stays.
        journey.coordinator.tradeSatoshisAnswered = null;
        await journey.waitUntil(() => amounts.evaluate().isEmpty);
        await journey.termsShownOtherwise();
        expect(red, findsOneWidget);
        // « Pay » pays the invoice confirmed: no lock.
        final pay = find.text(
          l10n.p2pPayConfirm(journey.formats.sats(1350704 + 327)),
        );
        expect(pay, findsOneWidget);
        final invoice = journey.coordinator.escrowInvoice;
        if (invoice == null) fail('no escrow invoice');
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-escrow',
              paymentHash: invoice.facts.paymentHash,
            ),
          ),
        );
        // The trace of terms shown otherwise has just moved the card: « Pay » ignores a tap for a moment (security review of #268, C1), then pays.
        await tester.pump(MovedTapGuard.afterMove);
        await journey.tap(pay);
        await journey.waitUntil(() => journey.wallet.paid.isNotEmpty);
        expect(journey.wallet.paid, hasLength(1));
        await journey.close();
      },
    );

    testWidgets(
      'a taker buyer\'s red bond, then « rate not checked », beside the alert of terms changed and its trace, $code: each stays, « Pay » offered (security review, C5)',
      (tester) async {
        final journey = await _Journey.start(tester, locale, sats: 1348344);
        final l10n = journey.l10n;
        await journey.take();
        await journey.confirmBond();
        final warning = find.text(journey.bondFigures(40450));
        expect(warning, findsOneWidget);
        journey.coordinator.premium = 9;
        await journey.waitFor(find.text(l10n.p2pTradeWarnTerms));
        await settle(tester);
        expect(warning, findsOneWidget);
        expect(
          journey.inCard(find.text(l10n.p2pPayoutBreakdownAgainst)),
          findsOneWidget,
        );
        journey.coordinator.premium = 3.5;
        await journey.waitUntil(
          () => find.text(l10n.p2pTradeWarnTerms).evaluate().isEmpty,
        );
        await settle(tester);
        expect(warning, findsOneWidget);
        expect(
          find.text(l10n.p2pPayConfirm(journey.formats.sats(40450 + 327))),
          findsOneWidget,
        );
        await journey.close();
      },
    );

    testWidgets(
      'a taker buyer\'s bond whose price could not be read, beside the alert of terms changed, $code: « rate not checked » and « Retry » stay (security review, C5)',
      (tester) async {
        final journey = await _Journey.start(
          tester,
          locale,
          rate: const P2pWalletRateUnavailable(),
        );
        final l10n = journey.l10n;
        await journey.take();
        await journey.confirmBond();
        final unverified = journey.inCard(
          find.text(l10n.p2pPayoutBreakdownUnverified),
        );
        expect(unverified, findsOneWidget);
        expect(
          find.text(l10n.p2pPayoutBreakdownUnverifiedLine),
          findsOneWidget,
        );
        journey.coordinator.premium = 9;
        await journey.waitFor(find.text(l10n.p2pTradeWarnTerms));
        await settle(tester);
        expect(unverified, findsOneWidget);
        expect(find.text(l10n.p2pCommonRetry), findsOneWidget);
        await journey.close();
      },
    );

    testWidgets(
      'the Bull wallet\'s price unreadable at the bond, $code: « rate not checked » and « Retry », then the comparison',
      (tester) async {
        final journey = await _Journey.start(
          tester,
          locale,
          rate: const P2pWalletRateUnavailable(),
        );
        await journey.take();
        await journey.confirmBond();
        final l10n = journey.l10n;
        expect(
          journey.inCard(find.text(l10n.p2pPayoutBreakdownUnverified)),
          findsOneWidget,
        );
        expect(
          journey.inCard(find.byKey(PriceCheckLines.gapRow)),
          findsNothing,
        );
        journey.wallet.rate = P2pWalletRateRead(71657);
        await journey.tap(find.text(l10n.p2pCommonRetry));
        await settle(tester);
        expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
        await journey.expectCheck(
          gap: -1,
          warns: false,
          figures: journey.bondFigures(4045),
          sentence: journey.bondLine(-1),
        );
        expect(journey.wallet.ratesAsked, hasLength(2));
        await journey.close();
      },
    );

    testWidgets(
      'a currency the Bull wallet does not price (CHF), $code: the « not priced » line alone at the bond and before « Submit », no figure',
      (tester) async {
        final journey = await _Journey.start(
          tester,
          locale,
          currency: 7,
          rate: const P2pWalletRateNotPriced(),
        );
        await journey.take();
        await journey.confirmBond();
        final l10n = journey.l10n;
        // The grey « not quoted » line, nothing else: no line naming the coordinator (#250).
        expect(
          journey.inCard(find.text(l10n.p2pPayoutBreakdownGapNotPriced)),
          findsOneWidget,
        );
        expect(
          journey.inCard(find.text(l10n.p2pPayoutBreakdownNotPriced)),
          findsOneWidget,
        );
        expect(
          journey.inCard(find.textContaining('Temple of Sats')),
          findsNothing,
        );
        expect(find.text(l10n.p2pCommonRetry), findsNothing);
        expect(journey.wallet.ratesAsked.single.$2.code, 'CHF');
        // At the payout, the breakdown's grey « not quoted » line, nothing else (#250).
        await journey.lockBond(find.text(l10n.p2pPayoutBreakdownNotPriced));
        expect(find.text(l10n.p2pPayoutBreakdownGapNotPriced), findsOneWidget);
        expect(
          find.text(l10n.p2pPayoutRateNotPriced('CHF', 'Temple of Sats')),
          findsNothing,
        );
        expect(find.textContaining(journey.sats(134834)), findsNothing);
        await journey.close();
      },
    );
    group('the lean confirmation of a take (#250), $code', () {
      /// The bond's confirmation of a taker buyer, or of a taker seller ([seller]).
      Future<(_Journey, LeanConfirmation, P2pWalletQuote)> bond(
        WidgetTester tester, {
        bool seller = false,
        int sats = 134834,
      }) async {
        final journey = await _Journey.start(
          tester,
          locale,
          seller: seller,
          sats: sats,
        );
        await journey.take();
        final quote = await journey.confirmBond();
        return (journey, LeanConfirmation(tester, locale), quote);
      }

      /// A taker seller's escrow confirmation.
      Future<(_Journey, LeanConfirmation, P2pWalletQuote)> escrow(
        WidgetTester tester, {
        int sats = 134834,
        int currency = 1,
        P2pWalletBitcoinRate? rate,
      }) async {
        final journey = await _Journey.start(
          tester,
          locale,
          seller: true,
          sats: sats,
          currency: currency,
          rate: rate,
        );
        await journey.take();
        await journey.confirmBond();
        await journey.lockBond(find.text(journey.l10n.p2pPayWithThisWallet));
        final quote = await journey.confirmEscrow();
        return (journey, LeanConfirmation(tester, locale), quote);
      }

      /// Two taps on « Pay » in a row: one payment, of the quote shown, its total the card's.
      Future<void> payOnce(
        _Journey journey,
        LeanConfirmation lean,
        P2pWalletQuote quote,
        Bolt11TestInvoice invoice,
      ) async {
        final tester = journey.tester;
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-lean',
              paymentHash: invoice.facts.paymentHash,
            ),
          ),
        );
        final pay = lean.payOf(quote);
        await tester.ensureVisible(pay);
        await tester.pump();
        await tester.tap(pay);
        await tester.tap(pay, warnIfMissed: false);
        await tester.pump();
        await journey.waitUntil(() => journey.wallet.paid.isNotEmpty);
        await journey.pass(2);
        expect(journey.wallet.paid, hasLength(1));
        final (paidInvoice, paidQuote) = journey.wallet.paid.single;
        expect(paidInvoice.paymentHash, invoice.facts.paymentHash);
        expect(paidQuote.total, quote.total);
        expect(paidQuote.amount, quote.amount);
        expect(paidQuote.serviceFee, quote.serviceFee);
        expect(paidQuote.networkFee, quote.networkFee);
      }

      testWidgets(
        'a taker buyer\'s bond: the card on arrival, the gap « (indicative) » above the buttons, the detail opened and closed with the buttons still; « Pay » pays the quote shown, once',
        (tester) async {
          final (journey, lean, quote) = await bond(tester);
          final l10n = journey.l10n;
          lean.expectArrival(quote, escrow: false);
          expect(
            lean.row(PriceCheckLines.gapRow),
            '${l10n.p2pPayoutBreakdownGap} | ${journey.gap(-1)}',
          );
          lean.expectAboveButtons(find.byKey(PriceCheckLines.gapRow));
          await lean.toggleDetail(
            quote,
            whileOpen: () {
              lean.expectDetailRows(quote);
              final sentence = find.text(journey.bondLine(-1));
              final small = find.text(l10n.p2pPayoutBreakdownSmallGap);
              final hold = find.text(l10n.p2pTradeHoldInvoiceBond);
              expect(sentence, findsOneWidget);
              expect(small, findsOneWidget);
              expect(hold, findsOneWidget);
              // A bond's detail says nothing of the swap service holding the sats.
              expect(find.text(l10n.p2pPayEscrowHeld), findsNothing);
              expect(
                tester.getTopLeft(sentence).dy,
                lessThan(tester.getTopLeft(small).dy),
              );
              expect(
                tester.getTopLeft(small).dy,
                lessThan(tester.getTopLeft(hold).dy),
              );
            },
          );
          final invoice = journey.coordinator.bondOf(journey.robot);
          if (invoice == null) fail('no bond');
          await payOnce(journey, lean, quote, invoice);
          await journey.close();
        },
      );

      testWidgets(
        'a taker seller\'s collateral: the card on arrival, the detail with the validated sentence, the swap service\'s facts and the reference\'s line; « Pay » pays the quote shown, once',
        (tester) async {
          final (journey, lean, quote) = await escrow(tester);
          final l10n = journey.l10n;
          lean.expectArrival(quote, escrow: true);
          expect(
            lean.row(PriceCheckLines.gapRow),
            '${l10n.p2pPayoutBreakdownGap} | ${journey.gap(18)}',
          );
          await lean.toggleDetail(
            quote,
            whileOpen: () {
              lean.expectDetailRows(quote);
              final sentence = find.text(journey.escrowSentence(18));
              final small = find.text(l10n.p2pPayoutBreakdownSmallGap);
              final held = find.text(l10n.p2pPayEscrowHeld);
              final hold = find.text(l10n.p2pTradeHoldInvoiceEscrow('USD'));
              for (final finder in [sentence, small, held, hold]) {
                expect(finder, findsOneWidget);
              }
              for (final (a, b) in [
                (sentence, small),
                (small, held),
                (held, hold),
              ]) {
                expect(
                  tester.getTopLeft(a).dy,
                  lessThan(tester.getTopLeft(b).dy),
                );
              }
            },
          );
          final invoice = journey.coordinator.escrowInvoice;
          if (invoice == null) fail('no escrow invoice');
          await payOnce(journey, lean, quote, invoice);
          await journey.close();
        },
      );

      for (final payment in ['bond', 'escrow']) {
        testWidgets(
          'a taker\'s $payment ten times too large: the red alert\'s two lines above the buttons, its explanation in the detail, the buttons still; « Pay » offered',
          (tester) async {
            final (journey, lean, quote) = payment == 'bond'
                ? await bond(tester, sats: 1348344)
                : await escrow(tester, sats: 1348344);
            final l10n = journey.l10n;
            lean.expectArrival(quote, escrow: payment == 'escrow');
            if (payment == 'bond') {
              lean.expectRed(journey.gap(90000), journey.bondFigures(40450));
            } else {
              lean.expectRed(
                journey.gap(90175),
                journey.escrowFigures(1350704),
              );
            }
            await lean.toggleDetail(
              quote,
              whileOpen: () {
                final explanation = find.text(
                  l10n.p2pPayAgainstDetail(
                    journey.price(),
                    'USD',
                    journey.threshold,
                  ),
                );
                expect(explanation, findsOneWidget);
                expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
                expect(find.text(journey.bondLine(90000)), findsNothing);
                expect(find.text(journey.escrowSentence(90175)), findsNothing);
              },
            );
            expect(
              tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
              isNotNull,
            );
            await journey.close();
          },
        );
      }

      testWidgets(
        'a taker seller\'s collateral, the Bull wallet\'s price not read: « Amount not checked » and its line above the buttons, « Retry » beside it, the explanation in the detail; « Retry » brings the comparison',
        (tester) async {
          final (journey, lean, quote) = await escrow(
            tester,
            rate: const P2pWalletRateUnavailable(),
          );
          final l10n = journey.l10n;
          lean.expectArrival(quote, escrow: true);
          expect(
            lean.row(PriceCheckLines.unverifiedRow),
            '${l10n.p2pPayoutBreakdownUnverified} | ${l10n.p2pCommonRetry}',
          );
          final line = lean.inCard(
            find.text(l10n.p2pPayoutBreakdownUnverifiedLine),
          );
          lean.expectAboveButtons(line);
          final colors = Theme.of(tester.element(line)).extension<BullTheme>();
          expect(tester.widget<Text>(line).style?.color, colors?.warning);
          expect(lean.inCard(find.byKey(PriceCheckLines.gapRow)), findsNothing);
          await lean.toggleDetail(
            quote,
            whileOpen: () {
              expect(find.text(l10n.p2pPayUnverifiedDetail), findsOneWidget);
              expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
            },
          );
          expect(
            tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
            isNotNull,
          );
          journey.wallet.rate = P2pWalletRateRead(71657);
          await journey.tap(lean.inCard(find.text(l10n.p2pCommonRetry)));
          await settle(tester);
          expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
          await journey.expectCheck(
            gap: 18,
            warns: false,
            figures: journey.escrowFigures(135070),
            sentence: journey.escrowSentence(18),
          );
          expect(journey.wallet.paid, isEmpty);
          await journey.close();
        },
      );

      testWidgets(
        'a taker seller\'s collateral in a currency the Bull wallet does not price (CHF): the grey « not quoted » line alone, nothing in the detail but the fees and the facts',
        (tester) async {
          final (journey, lean, quote) = await escrow(
            tester,
            currency: 7,
            rate: const P2pWalletRateNotPriced(),
          );
          final l10n = journey.l10n;
          lean.expectArrival(quote, escrow: true);
          expect(
            lean.row(PriceCheckLines.notPricedRow),
            '${l10n.p2pPayoutBreakdownGapNotPriced} | ${l10n.p2pPayoutBreakdownNotPriced}',
          );
          final value = lean.inCard(
            find.text(l10n.p2pPayoutBreakdownNotPriced),
          );
          final colors = Theme.of(tester.element(value)).extension<BullTheme>();
          expect(tester.widget<Text>(value).style?.color, colors?.textMuted);
          expect(
            lean.inCard(find.textContaining('Temple of Sats')),
            findsNothing,
          );
          expect(
            lean.inCard(find.byIcon(Icons.warning_amber_rounded)),
            findsNothing,
          );
          await lean.toggleDetail(
            quote,
            whileOpen: () {
              expect(
                find.byKey(PayConfirmationCard.rateParagraph),
                findsNothing,
              );
              expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
              expect(
                find.text(l10n.p2pTradeHoldInvoiceEscrow('CHF')),
                findsOneWidget,
              );
            },
          );
          await journey.close();
        },
      );

      /// A phone of 320 × 568 points, the card's link brought into view.
      Future<void> smallPhone(WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568) * 3;
        await tester.pump();
        await settle(tester);
        await tester.ensureVisible(
          find.byKey(PayConfirmationCard.detailToggle),
        );
        await tester.pump();
        await settle(tester);
      }

      /// The script of the payment of [invoice], for a « Pay » that goes through.
      void payable(_Journey journey, Bolt11TestInvoice invoice) =>
          journey.wallet.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-guard',
                paymentHash: invoice.facts.paymentHash,
              ),
            ),
          );

      /// « Pay » tapped once, now: it pays the quote shown, once.
      Future<void> paysNow(
        _Journey journey,
        LeanConfirmation lean,
        P2pWalletQuote quote,
      ) async {
        final tester = journey.tester;
        await tester.tap(lean.payOf(quote));
        await tester.pump();
        await journey.waitUntil(() => journey.wallet.paid.isNotEmpty);
        expect(journey.wallet.paid, hasLength(1));
        expect(journey.wallet.paid.single.$2.total, quote.total);
      }

      testWidgets(
        'an alert of the screen that comes, then goes, while the card is open (a coordinator showing other terms for a read): a tap aimed at what stood where « Pay » now is pays nothing; « Pay » a moment later pays the quote shown, once (security review of #268, C1)',
        (tester) async {
          final (journey, lean, quote) = await bond(tester);
          final l10n = journey.l10n;
          await smallPhone(tester);
          final invoice = journey.coordinator.bondOf(journey.robot);
          if (invoice == null) fail('no bond');
          payable(journey, invoice);
          final pay = lean.payOf(quote);
          final toggle = find.byKey(PayConfirmationCard.detailToggle);
          // The alert comes: the card moves; a tap on « Pay » at once was aimed at what stood there before.
          var before = tester.getRect(pay);
          journey.coordinator.premium = 9;
          await journey.waitFor(find.text(l10n.p2pTradeWarnTerms));
          await tester.pump();
          expect(tester.getRect(pay), isNot(before));
          // A tenth of a second later, as a finger already on its way.
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tapAt(tester.getRect(pay).center);
          await tester.pump();
          expect(journey.wallet.paid, isEmpty);
          // The alert goes, its trace stays: the card moves down by the trace's line, « Pay » onto what stood under it (« Show details », or the space under « Pay »).
          await tester.pump(
            MovedTapGuard.afterMove + const Duration(milliseconds: 50),
          );
          before = tester.getRect(pay);
          final link = tester.getRect(toggle).center;
          journey.coordinator.premium = 3.5;
          await journey.waitUntil(
            () => find.text(l10n.p2pTradeWarnTerms).evaluate().isEmpty,
          );
          await tester.pump();
          final after = tester.getRect(pay);
          expect(after.top, greaterThan(before.top));
          await tester.pump(const Duration(milliseconds: 100));
          // Where « Pay » now covers the link's old place, the tap aimed at the link; else a tap on « Pay » itself, as soon.
          await tester.tapAt(after.contains(link) ? link : after.center);
          await tester.pump();
          expect(journey.wallet.paid, isEmpty);
          // A moment later « Pay » pays, never a lock.
          await tester.pump(
            MovedTapGuard.afterMove + const Duration(milliseconds: 50),
          );
          await paysNow(journey, lean, quote);
          await journey.close();
        },
      );

      testWidgets(
        '« Retry » that brings the Bull price while the user goes for « Go back »: the tap where « Go back » was, now under « Pay », pays nothing; « Pay » a moment later pays (security review of #268, C2)',
        (tester) async {
          final (journey, lean, quote) = await escrow(
            tester,
            rate: const P2pWalletRateUnavailable(),
          );
          final l10n = journey.l10n;
          await smallPhone(tester);
          final invoice = journey.coordinator.escrowInvoice;
          if (invoice == null) fail('no escrow invoice');
          payable(journey, invoice);
          // « Retry » in view, under the tabs.
          final retry = lean.inCard(find.text(l10n.p2pCommonRetry));
          unawaited(
            Scrollable.ensureVisible(tester.element(retry), alignment: 0.3),
          );
          await tester.pump();
          await settle(tester);
          final back = tester.getRect(lean.goBack).center;
          expect(back.dy, lessThan(568));
          journey.wallet.rate = P2pWalletRateRead(71657);
          await tester.tap(retry);
          await journey.waitUntil(
            () =>
                find.text(l10n.p2pPayoutBreakdownUnverified).evaluate().isEmpty,
          );
          expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
          expect(tester.getRect(lean.payOf(quote)).contains(back), isTrue);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tapAt(back);
          await tester.pump();
          expect(journey.wallet.paid, isEmpty);
          expect(lean.card, findsOneWidget);
          await tester.pump(
            MovedTapGuard.afterMove + const Duration(milliseconds: 50),
          );
          await paysNow(journey, lean, quote);
          await journey.close();
        },
      );

      testWidgets(
        'the page scrolled, then « Pay » tapped at once: it pays, a scroll never sets the guard off (security review of #268)',
        (tester) async {
          final (journey, lean, quote) = await bond(tester);
          await smallPhone(tester);
          final invoice = journey.coordinator.bondOf(journey.robot);
          if (invoice == null) fail('no bond');
          payable(journey, invoice);
          final before = tester.getRect(lean.payOf(quote));
          // The page scrolled by 80 points, as a finger would.
          final position = Scrollable.of(tester.element(lean.card)).position;
          final up = position.pixels - 80;
          position.jumpTo(
            up >= position.minScrollExtent ? up : position.pixels + 80,
          );
          await tester.pump();
          expect(tester.getRect(lean.payOf(quote)), isNot(before));
          await paysNow(journey, lean, quote);
          await journey.close();
        },
      );

      testWidgets(
        'the detail opened and closed, then « Pay » tapped at once: it pays, the detail never moves « Pay » (security review of #268)',
        (tester) async {
          final (journey, lean, quote) = await bond(tester);
          final invoice = journey.coordinator.bondOf(journey.robot);
          if (invoice == null) fail('no bond');
          payable(journey, invoice);
          await lean.toggleDetail(quote);
          await tester.tap(lean.inCard(find.text(journey.l10n.p2pDetailShow)));
          await tester.pump();
          expect(find.byKey(PayConfirmationCard.detail), findsOneWidget);
          await paysNow(journey, lean, quote);
          await journey.close();
        },
      );

      testWidgets(
        'a taker seller\'s red collateral beside the screen\'s alert of terms changed: both visible, the red lines above the buttons, « Pay » offered',
        (tester) async {
          final (journey, lean, quote) = await escrow(tester, sats: 1348344);
          final l10n = journey.l10n;
          journey.coordinator.premium = 9;
          await journey.waitFor(find.text(l10n.p2pTradeWarnTerms));
          await settle(tester);
          expect(find.text(l10n.p2pTradeWarnTerms), findsOneWidget);
          lean.expectRed(journey.gap(90175), journey.escrowFigures(1350704));
          expect(
            tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
            isNotNull,
          );
          await journey.close();
        },
      );
    });
  }

  // Last in the file: the app's font, loaded here, stays loaded for the tests after it.
  group(
    'the lean confirmation of a take on a phone of 320 points, in the app\'s font (#250)',
    () {
      for (final locale in const [Locale('en'), Locale('fr')]) {
        for (final payment in ['bond', 'escrow']) {
          testWidgets(
            '${locale.languageCode}: a taker\'s $payment, its red alert, the text at ×1, ×2 and ×3: the card and its detail overflow nothing, no word cut',
            (tester) async {
              await tester.runAsync(loadAppFont);
              final journey = await _Journey.start(
                tester,
                locale,
                seller: payment == 'escrow',
                sats: 1348344,
              );
              await journey.take();
              if (payment == 'bond') {
                await journey.confirmBond();
              } else {
                await journey.confirmBond();
                await journey.lockBond(
                  find.text(journey.l10n.p2pPayWithThisWallet),
                );
                await journey.confirmEscrow();
              }
              final lean = LeanConfirmation(tester, locale);
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              tester.view
                ..physicalSize = const Size(320 * 3, 4000 * 3)
                ..devicePixelRatio = 3;
              for (final scale in const [1.0, 2.0, 3.0]) {
                tester.platformDispatcher.textScaleFactorTestValue = scale;
                await tester.pump();
                lean.expectNothingCut('$payment ×$scale, on arrival');
                final toggle = find.byKey(PayConfirmationCard.detailToggle);
                await tester.ensureVisible(toggle);
                await tester.pump();
                await tester.tap(toggle);
                await tester.pump();
                expect(find.byKey(PayConfirmationCard.detail), findsOneWidget);
                lean.expectNothingCut('$payment ×$scale, the detail open');
                await tester.tap(toggle);
                await tester.pump();
              }
              await journey.close();
            },
          );
        }
      }
    },
  );
}
