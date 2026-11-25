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
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/price_check_lines.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The three gaps of the owner's payment rule (#237; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis) on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the real router, records, use cases, state machine and trade screen, the coordinator played by `ScriptedMakerCoordinator` (never a real one), the wallet `FakeP2pWalletPort` (no price service, no swap service, no money).
///
/// The order: 100 GBP (a currency the Bull wallet does not price) or 100 EUR, at a premium of 0, made at the coordinator's 50,000 per bitcoin: 200,000 sats at the rate of the creation.
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
  final FakeSecureStoragePlatform vault;
  final Locale locale;
  final void Function(Duration) advance;
  late TradeRecord record;

  _App(
    this.tester,
    this.router,
    this.coordinator,
    this.wallet,
    this.vault,
    this.locale,
    this.advance,
  );

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  P2pFormats get formats =>
      P2pFormats.of(tester.element(find.byType(TradeScreen)));

  /// The size of a gap of [hundredths] of a percent as the screen writes it.
  String size(int hundredths) => formats.gapSize(BigInt.from(hundredths));

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

  /// The order of the tests made in [currency] at 50,000 (bought, or [sell] sold), its bond locked and, unless [taken] is false, taken by robot 5 at the coordinator's [at] (its sats [sats] when given): at 6.
  static Future<_App> start(
    WidgetTester tester, {
    String currency = 'GBP',
    bool sell = false,
    double at = 50000,
    int? sats,
    bool taken = true,
    P2pWalletBitcoinRate rate = const P2pWalletRateNotPriced(),
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vault = FakeSecureStoragePlatform().install();
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
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))..rate = rate;
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
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
      coordinator,
      wallet,
      vault,
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
    final request = MakeHarness.request(
      sell: sell,
      premium: 0,
      currency: ofOrder,
    );
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
    coordinator.lockMakerBond(app.record.orderId);
    if (taken) app.take(at: at, sats: sats);
    return app;
  }

  /// Robot 5 takes the order at the coordinator's [at] for its currency, its sats [sats] when given.
  void take({required double at, int? sats}) {
    final made = coordinator.order(record.orderId);
    coordinator
      ..prices[made.body['currency'] as int? ?? 0] = at
      ..take(record.orderId, TradeHarness.robotsOf(_net)[5]);
    if (sats != null) made.lastSatoshis = sats;
  }

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

  /// The payout failed and its invoice expired: 13 → 15, a new invoice asked.
  Future<void> failPayout() async {
    coordinator.failPayout(record.orderId);
    await waitFor(find.text(l10n.p2pPayoutInvoiceExpiredSubmitNew));
    await settle();
  }

  /// The orange alert of a gap of [hundredths] against the user since the order was made.
  Finder against(int hundredths) =>
      find.text(l10n.p2pRateAgainstSinceMade(size(hundredths)));

  Finder get anyAgainst => find.byKey(PriceCheckLines.againstSinceMadeRow);

  Finder get explanation =>
      find.text(l10n.p2pRateAgainstSinceMadeDetail('GBP'));

  Finder get notQuoted => find.text(l10n.p2pPayoutBreakdownNotPriced);

  Finder get breakdown => find.byType(PayoutBreakdownView);

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

/// The confirmation of « Pay with this wallet » for [invoice], scripted.
Future<void> _confirm(_App app, Bolt11TestInvoice invoice) async {
  final checked = checkedBolt11InvoiceForTesting(
    bolt11: invoice.text,
    amount: invoice.facts.amount,
    network: _net,
    paymentHash: invoice.facts.paymentHash,
    expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
    now: DateTime.utc(2026, 11, 14, 9),
  );
  if (checked == null) fail('not a payable invoice');
  app.wallet.scriptQuote(
    Ok(
      P2pWalletQuote(
        invoice: checked,
        payin: Sats(checked.amount.value + BigInt.from(500)),
        networkFee: Sats.fromInt(27),
        balance: Sats.fromInt(5000000),
        quotedAt: DateTime.utc(2026, 11, 14, 9),
      ),
    ),
  );
  await app.tap(find.text(app.l10n.p2pPayWithThisWallet));
  await app.settle();
  await app.waitFor(find.text(app.l10n.p2pCommonGoBack));
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;

    group(
      'point 2, a maker buyer in a currency the Bull wallet does not price, $code',
      () {
        testWidgets(
          'taken at 56,000 (178,571 sats, 10.72 % fewer): at 6 the grey « not quoted » line, the orange alert under it, its explanation behind « Show details »',
          (tester) async {
            final app = await _App.start(tester, at: 56000, locale: locale);
            await app.openTrade();
            await app.waitFor(app.notQuoted);
            await app.settle();
            expect(
              find.descendant(of: app.breakdown, matching: app.notQuoted),
              findsOneWidget,
            );
            expect(
              find.descendant(of: app.breakdown, matching: app.against(1072)),
              findsOneWidget,
            );
            expect(app.explanation, findsNothing);
            await app.tap(find.text(app.l10n.p2pDetailShow));
            await app.settle();
            expect(
              find.descendant(of: app.breakdown, matching: app.explanation),
              findsOneWidget,
            );
            expect(
              find.text(app.l10n.p2pPayoutBreakdownNotCompared),
              findsNothing,
            );
            expect(app.wallet.paid, isEmpty);
            await app.close();
          },
        );

        for (final (label, at, sats) in <(String, double, int?)>[
          ('taken at 55,500 (180,180 sats, 9.91 % fewer)', 55500, null),
          ('180,000 sats, exactly 10 % fewer', 56000, 180000),
          ('taken at 45,000 (222,222 sats, more for the buyer)', 45000, null),
        ]) {
          testWidgets(
            '$label: the grey line alone, no percentage, nothing in the detail',
            (tester) async {
              final app = await _App.start(
                tester,
                at: at,
                sats: sats,
                locale: locale,
              );
              await app.openTrade();
              await app.waitFor(app.notQuoted);
              await app.settle();
              expect(app.anyAgainst, findsNothing);
              expect(
                find.descendant(
                  of: app.breakdown,
                  matching: find.textContaining('%'),
                ),
                findsNothing,
              );
              await app.tap(find.text(app.l10n.p2pDetailShow));
              await app.settle();
              expect(app.explanation, findsNothing);
              await app.close();
            },
          );
        }

        testWidgets(
          'at 9 beside the alert of a payout not given from Bull Market: both said, neither silencing the other; the same in « Confirm … sent », the explanation under the alert there',
          (tester) async {
            final app = await _App.start(tester, at: 56000, locale: locale);
            await app.openTrade();
            await app.waitFor(app.notQuoted);
            app.coordinator.lockEscrow(app.record.orderId);
            final trace = find.text(app.l10n.p2pPayoutTraceNotGivenHere);
            await app.moveTo(const [9], trace);
            await app.waitFor(app.against(1072));
            await app.settle();
            expect(trace, findsOneWidget);
            expect(app.against(1072), findsOneWidget);
            expect(app.explanation, findsOneWidget);
            expect(find.textContaining('GBP'), findsWidgets);
            final confirm = find.text(
              app.l10n.p2pEndConfirmSent(
                app.formats.amount(FiatAmount.tryCreate(100) ?? fail('100')),
                'GBP',
              ),
            );
            await app.tap(confirm);
            await app.settle();
            final dialog = find.byType(Dialog);
            expect(
              find.descendant(of: dialog, matching: app.against(1072)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: dialog, matching: app.explanation),
              findsOneWidget,
            );
            expect(
              find.descendant(of: dialog, matching: trace),
              findsOneWidget,
            );
            await app.close();
          },
        );
      },
    );

    group(
      'point 2, a maker seller\'s collateral in a currency the Bull wallet does not price, $code',
      () {
        testWidgets(
          'taken at 45,000 (222,222 sats to lock, 11.12 % more): the grey line and the orange alert in the card, the explanation in its detail; « Pay » offered',
          (tester) async {
            final app = await _App.start(
              tester,
              sell: true,
              at: 45000,
              locale: locale,
            );
            await app.openTrade();
            final escrow = app.coordinator.order(app.record.orderId).escrow;
            if (escrow == null) fail('no escrow invoice');
            await _confirm(app, escrow);
            final card = find.byType(PayConfirmationCard);
            expect(
              find.descendant(of: card, matching: app.notQuoted),
              findsOneWidget,
            );
            expect(
              find.descendant(of: card, matching: app.against(1112)),
              findsOneWidget,
            );
            expect(app.explanation, findsNothing);
            await app.tap(find.text(app.l10n.p2pDetailShow));
            await app.settle();
            expect(
              find.descendant(of: card, matching: app.explanation),
              findsOneWidget,
            );
            // « Pay » offered: nothing is blocked.
            final pay = find
                .descendant(of: card, matching: find.byType(TradeButton))
                .last;
            expect(tester.widget<TradeButton>(pay).onPressed, isNotNull);
            expect(app.wallet.paid, isEmpty);
            await app.close();
          },
        );

        for (final (label, at) in <(String, double)>[
          ('taken at 45,500 (219,780 sats, 9.89 % more)', 45500),
          ('taken at 56,000 (fewer sats to lock)', 56000),
        ]) {
          testWidgets('$label: the grey line alone, nothing in the detail', (
            tester,
          ) async {
            final app = await _App.start(
              tester,
              sell: true,
              at: at,
              locale: locale,
            );
            await app.openTrade();
            final escrow = app.coordinator.order(app.record.orderId).escrow;
            if (escrow == null) fail('no escrow invoice');
            await _confirm(app, escrow);
            expect(app.notQuoted, findsOneWidget);
            expect(app.anyAgainst, findsNothing);
            await app.tap(find.text(app.l10n.p2pDetailShow));
            await app.settle();
            expect(app.explanation, findsNothing);
            await app.close();
          });
        }
      },
    );

    group('point 1, the trade\'s records cannot be read now, $code', () {
      /// The order public, its trade screen open (the watch opened its records, the vault readable), then the vault locked and the order taken: the rule opens the records at the payout's step and is refused.
      Future<_App> lockedAtTheTake(WidgetTester tester) async {
        final app = await _App.start(
          tester,
          currency: 'EUR',
          rate: P2pWalletRateRead(50000),
          locale: locale,
          taken: false,
        );
        await app.openTrade();
        app.vault.locked = true;
        app.take(at: 50000);
        await app.waitFor(find.text(app.l10n.p2pPayoutRateTermsUnreadLine));
        await app.settle();
        return app;
      }

      testWidgets(
        'at 6: « Amount not checked » with its own second line and « Retry », never silence, the Bull wallet\'s price never asked; « Retry » with the vault still locked changes nothing; the vault back, « Retry » compares',
        (tester) async {
          final app = await lockedAtTheTake(tester);
          final unread = find.text(app.l10n.p2pPayoutRateTermsUnreadLine);
          expect(
            find.text(app.l10n.p2pPayoutBreakdownUnverified),
            findsOneWidget,
          );
          expect(
            find.text(app.l10n.p2pPayoutBreakdownUnverifiedLine),
            findsNothing,
          );
          expect(app.wallet.ratesAsked, isEmpty);
          final retry = find.text(app.l10n.p2pCommonRetry);
          expect(retry, findsOneWidget);
          await app.tap(retry);
          await app.settle();
          expect(unread, findsOneWidget);
          expect(app.wallet.ratesAsked, isEmpty);
          app.vault.locked = false;
          await app.tap(retry);
          await app.settle();
          await app.waitFor(find.text(app.l10n.p2pPayoutBreakdownGap));
          expect(unread, findsNothing);
          expect(app.wallet.ratesAsked, hasLength(1));
          await app.close();
        },
      );

      testWidgets(
        'at 9, the vault still locked: the same lines on the screen and in « Confirm … sent », which opens: nothing blocked',
        (tester) async {
          final app = await lockedAtTheTake(tester);
          final unread = find.text(app.l10n.p2pPayoutRateTermsUnreadLine);
          app.coordinator.lockEscrow(app.record.orderId);
          final confirm = find.text(
            app.l10n.p2pEndConfirmSent(
              app.formats.amount(FiatAmount.tryCreate(100) ?? fail('100')),
              'EUR',
            ),
          );
          await app.moveTo(const [9], confirm);
          await app.waitFor(unread);
          await app.settle();
          expect(
            find.text(app.l10n.p2pPayoutBreakdownUnverified),
            findsOneWidget,
          );
          expect(
            find.text(app.l10n.p2pPayoutRateTermsUnreadDetail),
            findsOneWidget,
          );
          await app.tap(confirm);
          await app.settle();
          final dialog = find.byType(Dialog);
          expect(find.descendant(of: dialog, matching: unread), findsOneWidget);
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(app.l10n.p2pPayoutBreakdownUnverified),
            ),
            findsOneWidget,
          );
          expect(app.wallet.ratesAsked, isEmpty);
          await app.close();
        },
      );
    });

    group('point 3, status 15, $code', () {
      testWidgets(
        'a maker buyer, the Bull wallet\'s price far below the coordinator\'s (40,000 for 50,000: 250,000 sats expected, about 200,000 paid): the same red alert at 15 as at 6, for the same sats; « No Bull Wallet check at this step » no longer said',
        (tester) async {
          final app = await _App.start(
            tester,
            currency: 'EUR',
            rate: P2pWalletRateRead(40000),
            locale: locale,
          );
          await app.openTrade();
          final red = find.text(app.l10n.p2pPayoutBreakdownAgainst);
          await app.waitFor(red);
          await app.settle();
          String figuresIn(Finder finder) =>
              tester
                  .widget<Text>(
                    find.descendant(
                      of: find.byKey(PriceCheckLines.alertFigures),
                      matching: find.byType(Text),
                    ),
                  )
                  .data ??
              '';
          final atSix = figuresIn(find.byKey(PriceCheckLines.alertFigures));
          final gapAtSix = tester
              .widget<Text>(
                find
                    .descendant(
                      of: find.byKey(PriceCheckLines.alertRow),
                      matching: find.byType(Text),
                    )
                    .last,
              )
              .data;
          app.coordinator.lockEscrow(app.record.orderId);
          await app.moveTo(const [
            9,
            10,
            13,
          ], find.text(app.l10n.p2pEndSendingSats));
          await app.failPayout();
          await app.waitFor(red);
          await app.settle();
          expect(red, findsOneWidget);
          expect(figuresIn(find.byKey(PriceCheckLines.alertFigures)), atSix);
          expect(
            tester
                .widget<Text>(
                  find
                      .descendant(
                        of: find.byKey(PriceCheckLines.alertRow),
                        matching: find.byType(Text),
                      )
                      .last,
                )
                .data,
            gapAtSix,
          );
          expect(
            find.text(app.l10n.p2pPayoutBreakdownNotCompared),
            findsNothing,
          );
          await app.close();
        },
      );

      testWidgets(
        'the Bull wallet\'s price unreadable at 15: « Amount not checked » with « Retry »',
        (tester) async {
          final app = await _App.start(
            tester,
            currency: 'EUR',
            rate: const P2pWalletRateUnavailable(),
            locale: locale,
          );
          await app.openTrade();
          await app.waitFor(
            find.text(app.l10n.p2pPayoutBreakdownUnverifiedLine),
          );
          app.coordinator.lockEscrow(app.record.orderId);
          await app.moveTo(const [
            9,
            10,
            13,
          ], find.text(app.l10n.p2pEndSendingSats));
          await app.failPayout();
          await app.waitFor(
            find.text(app.l10n.p2pPayoutBreakdownUnverifiedLine),
          );
          expect(find.text(app.l10n.p2pCommonRetry), findsOneWidget);
          expect(
            find.text(app.l10n.p2pPayoutBreakdownNotCompared),
            findsNothing,
          );
          await app.close();
        },
      );

      testWidgets(
        'a currency the Bull wallet does not price, taken at 56,000: at 15 the grey line and the orange alert since the order was made',
        (tester) async {
          final gbp = await _App.start(tester, at: 56000, locale: locale);
          await gbp.openTrade();
          await gbp.waitFor(gbp.notQuoted);
          gbp.coordinator.lockEscrow(gbp.record.orderId);
          await gbp.moveTo(const [
            9,
            10,
            13,
          ], find.text(gbp.l10n.p2pEndSendingSats));
          await gbp.failPayout();
          await gbp.waitFor(gbp.against(1072));
          expect(gbp.notQuoted, findsOneWidget);
          expect(
            find.text(gbp.l10n.p2pPayoutBreakdownNotCompared),
            findsNothing,
          );
          await gbp.close();
        },
      );
    });
  }

  testWidgets(
    'a currency the Bull wallet prices, the coordinator\'s rate 12 % worse than at the creation: the Bull wallet\'s comparison, never the gap since the order was made',
    (tester) async {
      final app = await _App.start(
        tester,
        currency: 'EUR',
        at: 56000,
        rate: P2pWalletRateRead(50000),
      );
      await app.openTrade();
      await app.waitFor(find.text(app.l10n.p2pPayoutBreakdownAgainst));
      await app.settle();
      expect(app.anyAgainst, findsNothing);
      expect(app.notQuoted, findsNothing);
      await app.close();
    },
  );
}
