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
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/presentation/p2p_formats.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
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
    await waitFor(find.text(l10n.p2pPayWithThisWallet));
  }

  /// A quote of [invoice] scripted, then « Pay with this wallet »: its confirmation.
  Future<void> confirm(Bolt11TestInvoice invoice) async {
    final checked = checkedBolt11InvoiceForTesting(
      bolt11: invoice.text,
      amount: invoice.facts.amount,
      network: _net,
      paymentHash: invoice.facts.paymentHash,
      expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
      now: clock(),
    );
    if (checked == null) fail('not a payable invoice');
    wallet.scriptQuote(
      Ok(
        P2pWalletQuote(
          invoice: checked,
          payin: Sats(checked.amount.value + BigInt.from(300)),
          networkFee: Sats.fromInt(27),
          balance: Sats.fromInt(5000000),
          quotedAt: clock(),
        ),
      ),
    );
    await tap(find.text(l10n.p2pPayWithThisWallet));
    await settle(tester);
    await waitFor(find.text(l10n.p2pCommonGoBack));
  }

  /// The bond's confirmation.
  Future<void> confirmBond() async {
    final bond = coordinator.bondOf(robot);
    if (bond == null) fail('no bond');
    await confirm(bond);
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
  Future<void> confirmEscrow() async {
    await waitUntil(() => coordinator.escrowInvoice != null);
    await settle(tester);
    await waitFor(find.text(l10n.p2pPayWithThisWallet));
    final escrow = coordinator.escrowInvoice;
    if (escrow == null) fail('no escrow invoice');
    await confirm(escrow);
  }

  String price() => formats.orderRate(71657);
  String sats(int value) => formats.bigSats(BigInt.from(value));
  String gap(int hundredths) => formats.gap(BigInt.from(hundredths));
  String get threshold => formats.threshold(TradeTolerances.walletRateGap);

  /// The bond's line: the bond expected at the Bull wallet's price, 4,045 sats, and the invoice's gap.
  String bondLine(int gapHundredths) =>
      l10n.p2pPayRateWallet(price(), 'USD', sats(4045), gap(gapHundredths));

  String bondWarning(int asked) =>
      l10n.p2pPayRateWarning(threshold, sats(asked), sats(4045));

  /// The escrow's line: 100 USD worth 134,834 sats at the Bull wallet's price, and the gap, the coordinator's fee included.
  String escrowLine(int gapHundredths) => l10n.p2pPayRateWalletEscrow(
    price(),
    'USD',
    formats.amount(_hundred),
    sats(134834),
    gap(gapHundredths),
  );

  String escrowWarning(int asked) =>
      l10n.p2pPayRateWarningEscrow(threshold, sats(asked), sats(134834));

  String payoutWarning(int received) =>
      l10n.p2pPayoutRateWarning(threshold, sats(received), sats(134834));

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
            expect(find.text(journey.bondLine(bond.gap)), findsOneWidget);
            expect(
              find.text(journey.bondWarning(bond.asked)),
              bond.warns ? findsOneWidget : findsNothing,
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
          await journey.close();
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
            expect(find.text(journey.bondLine(bond.gap)), findsOneWidget);
            expect(
              find.text(journey.bondWarning(bond.asked)),
              bond.warns ? findsOneWidget : findsNothing,
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
            final line = journey.escrowLine(escrow.gap);
            final warning = journey.escrowWarning(escrow.asked);
            if (escrow.warns) {
              expect(find.text('$line $warning'), findsOneWidget);
              expect(find.text(line), findsNothing);
            } else {
              expect(find.text(line), findsOneWidget);
              expect(find.textContaining(warning), findsNothing);
            }
            expect(journey.wallet.ratesAsked, hasLength(2));
            expect(journey.wallet.paid, isEmpty);
            await journey.close();
          },
        );
      }
    });

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
        expect(find.text(l10n.p2pPayRateUnverified('USD')), findsOneWidget);
        expect(find.text(journey.bondLine(-1)), findsNothing);
        journey.wallet.rate = P2pWalletRateRead(71657);
        await journey.tap(find.text(l10n.p2pCommonRetry));
        await settle(tester);
        expect(find.text(l10n.p2pPayRateUnverified('USD')), findsNothing);
        expect(find.text(journey.bondLine(-1)), findsOneWidget);
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
        expect(
          find.text(l10n.p2pPayRateNotPriced('CHF', 'Temple of Sats')),
          findsOneWidget,
        );
        expect(find.text(l10n.p2pCommonRetry), findsNothing);
        expect(journey.wallet.ratesAsked.single.$2.code, 'CHF');
        await journey.lockBond(
          find.text(l10n.p2pPayoutRateNotPriced('CHF', 'Temple of Sats')),
        );
        expect(find.textContaining(journey.sats(134834)), findsNothing);
        await journey.close();
      },
    );
  }
}
