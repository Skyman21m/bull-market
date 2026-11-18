import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_renewal.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_limits_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/check_make_price_usecase.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/make_form.dart';
import 'support/make_harness.dart';
import 'support/maker_orders.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// « Renew Order » at 5 and « Renew » at « Trade finished! » of an order made here, and the renewal's page they open (#185, `TradeBox/Prompts/Expired.tsx:40-97`, `Prompts/Successful.tsx:276-287`, `TradeBox/index.tsx:146-200`), by real gestures: a tap, two quick taps, going back; what each gesture asks counted, up to the makes that reach the coordinator played by the tests (never a real one).
///
/// Every status comes from the state machine reading the reference's answers to a maker (`support/maker_orders.dart`), never built by hand.

final _fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

/// The order made here, as the repository gives it once confirmed, of [role].
TradeRecord _madeRecord({TradeRole role = TradeRole.buyer}) => TradeRecord(
  robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 0),
  coordinatorAlias: 'temple',
  coordinatorOnion:
      Federation.robosats.byAlias('temple')?.mainnet.onion ??
      (throw StateError('temple')),
  orderId: tradeOrderId,
  role: role,
  origin: TradeOrigin.madeHere,
  takenAt: madeAt,
  confirmedAt: madeAt,
  closedAt: null,
);

/// The statuses of the reference's answers read one after the other by the state machine, from the order's first read, each marked [stored] as the reader stores it, for a maker of [role].
Future<TradeSeen> _at(
  List<Map<String, Object?>> answers, {
  TradeRole role = TradeRole.buyer,
  bool stored = true,
}) async {
  final made = madeTerms(role: role);
  final reader = Bolt11Reader(
    Bolt11TestDecoder([makerBondInvoice(), makerEscrowInvoice()]),
  );
  TradeStatus? status;
  CoordinatorOrder? last;
  for (final json in answers) {
    final order = await readOrder(json);
    final answer = TradeOrderRead(order);
    status = status == null
        ? TradeStatus.afterMake(
            answer,
            terms: made,
            now: tradeNow,
            reader: reader,
          )
        : TradeStatus.from(
            previous: status,
            answer: answer,
            terms: made,
            now: tradeNow,
            reader: reader,
          );
    last = order;
  }
  return TradeSeen(
    status ?? (throw StateError('no answer')),
    order: last,
    stored: stored,
    asked: switch (made.side) {
      MadeSide(:final maker) => maker.amount,
    },
  );
}

/// A maker buyer's order expired untaken, as read.
Future<TradeSeen> _expired({bool stored = true}) => _at([
  makerOrderJson(0),
  makerOrderJson(1),
  makerOrderJson(5),
], stored: stored);

/// A maker's trade to [last] through the chat, for [role].
Future<TradeSeen> _afterTrade(int last, {TradeRole role = TradeRole.buyer}) =>
    _at([
      for (final status in [0, 1, 6, 8, 9, 10, 13, if (last != 13) last])
        makerOrderJson(status, role: role),
    ], role: role);

/// What the trade screen asked to open: the record of each renewal's page, held open until the test completes it.
final class _Pages {
  final List<TradeRecord> opened = [];
  final List<Completer<void>> open = [];

  Future<void> call(TradeRecord record) {
    opened.add(record);
    final page = Completer<void>();
    open.add(page);
    return page.future;
  }
}

/// Shows the trade screen of [record] at [seen], over a cubit whose watch the test feeds, with « Renew » opening [pages] (none when `null`).
Future<void> _showTrade(
  WidgetTester tester,
  TradeSeen seen, {
  required TradeRecord record,
  _Pages? pages,
}) async {
  tester.view
    ..physicalSize = const Size(390, 1800) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final trade = TradeCubit(
    record,
    (record, {signals = const Stream.empty(), onScreen = true}) {
      signals.listen((_) {});
      return watch.stream;
    },
    (record, seen, {bondLoss}) => Completer<Never>().future,
  )..start();
  addTearDown(trade.close);
  final reads = FakeTransport();
  final page = TradeOrderPageCubit(
    coordinator('temple'),
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
    FindPublicOrderUsecase(
      CoordinatorClient(reads, clock: () => testNow),
    ).execute,
  );
  addTearDown(page.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: testTheme,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: trade),
            BlocProvider.value(value: page),
          ],
          child: TradeScreen(
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            onRenew: pages?.call,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(TradeScreenStatuses.watched(seen, of: record));
  await tester.pump();
  await tester.pump();
}

Finder get _renewOrder => find.widgetWithText(TradeButton, 'Renew Order');
Finder get _renew => find.widgetWithText(TradeButton, 'Renew');
Finder get _create => find.widgetWithText(TradeButton, 'Create order');

Future<void> _tap(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
}

/// Whether [button] can be pressed.
bool _enabled(WidgetTester tester, Finder button) {
  final widget = tester.widget<TradeButton>(button);
  return widget.onPressed != null && !widget.busy;
}

/// Every text shown: none names the project's internal name nor the swap engine.
void _noInternalNames(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(contains('Troc')));
    expect(text.data ?? '', isNot(contains('Boltz')));
  }
}

late CurrencyLimits _limits;
late CoordinatorInfo _templeInfo;

/// The kept request of the tests' order: 100 EUR, Revolut Instant SEPA, 2 %, the defaults.
final MakeOrderRequest _kept = MakeHarness.request();

/// The renewal page's collaborators, played by the test: the read of the kept terms, the coordinator's information and limits, the Bull wallet's price, the vault and the make.
final class _Renewal {
  /// What the read of the order's kept terms gives.
  Result<OrderRenewal, RenewalRefusal> read;

  /// What the Bull wallet's price check reads.
  P2pWalletBitcoinRate rate = P2pWalletRateRead(91711.15);

  /// Whether a Garage Key is stored.
  Result<bool, P2pFailure> keys = const Ok(true);

  /// The makes asked, with the coordinator each was asked for, and the answer of each, held until the test completes it unless [answer] is set.
  final List<(MakeOrderRequest, Coordinator)> made = [];
  final List<Completer<Result<MakeOutcome, MakeRefusal>>> answers = [];
  Result<MakeOutcome, MakeRefusal>? answer;

  /// What the next makes answer at once, in order, before [answer].
  final List<Result<MakeOutcome, MakeRefusal>> next = [];

  final List<String> limitsAsked = [];
  final List<String> infosAsked = [];

  /// The network's pending makes as the records list them.
  final pendingMakes =
      StreamController<Result<List<ActivePendingMake>, P2pFailure>>();
  List<ActivePendingMake> listedMakes = const [];

  _Renewal([MakeOrderRequest? request])
    : read = Ok(
        OrderRenewal(
          orderId: tradeOrderId,
          network: RobosatsNetwork.mainnet,
          coordinator: coordinatorOf('temple'),
          request: request ?? _kept,
        ),
      );

  PendingMakesCubit pendingCubit() => PendingMakesCubit(
    RobosatsNetwork.mainnet,
    (network) => pendingMakes.stream,
    (make) async => MakePending(make, MakePendingReason.unread),
    (make) async => const Ok(true),
  );

  MakeOrderCubit cubit() => MakeOrderCubit.renewal(
    _madeRecord(),
    placeholder: usd,
    readRenewal: (_) async => read,
    listHosts: (network) => RobotHosts(network, [
      for (final coordinator in Federation.robosats.on(network))
        RobotHost(coordinator, refusesFirstContacts: false),
    ]),
    fetchInfo: (coordinator, network) async {
      infosAsked.add(coordinator.shortAlias);
      return coordinator.shortAlias == 'temple'
          ? Ok(_templeInfo)
          : const Err(CoordinatorUnreachable());
    },
    fetchLimits: (coordinator, network) async {
      limitsAsked.add(coordinator.shortAlias);
      return Ok(_limits);
    },
    make: (request, {required coordinator, required network, required seen}) {
      made.add((request, coordinator));
      if (next.isNotEmpty) return Future.value(next.removeAt(0));
      final now = answer;
      if (now != null) return Future.value(now);
      final held = Completer<Result<MakeOutcome, MakeRefusal>>();
      answers.add(held);
      return held.future;
    },
    hasGarageKey: (_) async => keys,
    lottery: CoordinatorLottery(() => 0.5),
    now: () => DateTime.utc(2026, 11, 17),
    checkPrice: (network, currency, price) async =>
        MakePriceCheck.of(currency: currency, coordinatorPrice: price, wallet: rate),
  );
}

/// Shows the renewal's page of [renewal] above a page of the test, as the trade's page opens it, by a tap; the trades it opened in the returned list.
Future<List<TradeRecord>> _showRenewal(
  WidgetTester tester,
  _Renewal renewal,
) async {
  tester.view
    ..physicalSize = const Size(390 * 3, 2400 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = renewal.cubit();
  addTearDown(cubit.close);
  renewal.pendingMakes.add(Ok(renewal.listedMakes));
  final pending = renewal.pendingCubit()..start();
  addTearDown(pending.close);
  final opened = <TradeRecord>[];
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => unawaited(context.push('/renew')),
              child: const Text('the trade'),
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'renew',
            builder: (context, _) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: cubit),
                BlocProvider.value(value: pending),
              ],
              child: CreateOrderScreen(
                coordinatorDetails: (_) => throw StateError('not opened'),
                onMade: opened.add,
              ),
            ),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: testTheme,
      routerConfig: router,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
  await tester.tap(find.text('the trade'));
  unawaited(cubit.start());
  await settle(tester);
  return opened;
}

/// The text field showing [text], if one does, and whether it can be typed in.
bool? _fieldEnabled(WidgetTester tester, String text) {
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    if (field.controller?.text == text) return field.enabled ?? true;
  }
  return null;
}

void main() {
  setUpAll(() async {
    _limits = await limitsAt({2: 91711.15, 1: 98000});
    _templeInfo = await infoAt('temple');
  });

  group('« Renew Order » and « Renew » on the trade screen, by real gestures', () {
    testWidgets(
      '5, an order made here: « Renew Order » under the expiry\'s reason; a tap opens one page, two quick taps one, a tap while it is open none, a tap once it is left another',
      (tester) async {
        final pages = _Pages();
        await _showTrade(
          tester,
          await tester.runAsync(_expired) ?? (throw StateError('none')),
          record: _madeRecord(),
          pages: pages,
        );
        expect(find.text('Expired not taken'), findsOneWidget);
        expect(_renewOrder, findsOneWidget);
        expect(
          tester.getTopLeft(_renewOrder).dy,
          greaterThan(tester.getTopLeft(find.text('Expired not taken')).dy),
        );
        await _tap(tester, _renewOrder);
        await tester.tap(_renewOrder, warnIfMissed: false);
        await tester.pump();
        expect(pages.opened, [_madeRecord()]);
        // Open: spinning and off.
        expect(_enabled(tester, _renewOrder), isFalse);
        await tester.tap(_renewOrder, warnIfMissed: false);
        await tester.pump();
        expect(pages.opened, hasLength(1));
        // Left: a tap opens it again.
        pages.open.single.complete();
        await tester.pump();
        expect(_enabled(tester, _renewOrder), isTrue);
        await _tap(tester, _renewOrder);
        await tester.pump();
        expect(pages.opened, hasLength(2));
        _noInternalNames(tester);
      },
    );

    testWidgets(
      '5 not marked stored, or a screen that cannot make an order: no « Renew Order »',
      (tester) async {
        await _showTrade(
          tester,
          await tester.runAsync(() => _expired(stored: false)) ??
              (throw StateError('none')),
          record: _madeRecord(),
          pages: _Pages(),
        );
        expect(find.text('Expired not taken'), findsOneWidget);
        expect(_renewOrder, findsNothing);
        await _showTrade(
          tester,
          await tester.runAsync(_expired) ?? (throw StateError('none')),
          record: _madeRecord(),
        );
        expect(find.text('Expired not taken'), findsOneWidget);
        expect(_renewOrder, findsNothing);
      },
    );

    testWidgets(
      'an order taken here, at 5 and at 14: neither button, as the reference shows them to its maker only',
      (tester) async {
        final statuses =
            await tester.runAsync(TradeScreenStatuses.make) ??
            (throw StateError('none'));
        final expired =
            await tester.runAsync(statuses.expired) ??
            (throw StateError('none'));
        await _showTrade(
          tester,
          expired,
          record: TradeScreenStatuses.record,
          pages: _Pages(),
        );
        expect(find.text('The order has expired'), findsOneWidget);
        expect(_renewOrder, findsNothing);
        final succeeded =
            await tester.runAsync(statuses.succeeded) ??
            (throw StateError('none'));
        await _showTrade(
          tester,
          succeeded,
          record: TradeScreenStatuses.record,
          pages: _Pages(),
        );
        expect(find.textContaining('Trade finished!'), findsOneWidget);
        expect(_renew, findsNothing);
      },
    );

    testWidgets(
      '14, a maker buyer: « Renew » in « Trade finished! », one page for two quick taps; 13, a maker buyer being paid: none (`TradeBox/index.tsx:603-608`)',
      (tester) async {
        final pages = _Pages();
        await _showTrade(
          tester,
          await tester.runAsync(() => _afterTrade(14)) ??
              (throw StateError('none')),
          record: _madeRecord(),
          pages: pages,
        );
        expect(find.textContaining('Trade finished!'), findsOneWidget);
        expect(_renew, findsOneWidget);
        await _tap(tester, _renew);
        await tester.tap(_renew, warnIfMissed: false);
        await tester.pump();
        expect(pages.opened, hasLength(1));
        await _showTrade(
          tester,
          await tester.runAsync(() => _afterTrade(13)) ??
              (throw StateError('none')),
          record: _madeRecord(),
          pages: _Pages(),
        );
        expect(find.textContaining('Trade finished!'), findsNothing);
        expect(_renew, findsNothing);
      },
    );

    testWidgets(
      '13 and 15, a maker seller: « Trade finished! » with « Renew », as the reference (`TradeBox/index.tsx:609-629`, `:663-690`)',
      (tester) async {
        for (final status in [13, 15]) {
          final pages = _Pages();
          await _showTrade(
            tester,
            await tester.runAsync(
                  () => _afterTrade(status, role: TradeRole.seller),
                ) ??
                (throw StateError('none')),
            record: _madeRecord(role: TradeRole.seller),
            pages: pages,
          );
          expect(find.textContaining('Trade finished!'), findsOneWidget);
          await _tap(tester, _renew);
          await tester.pump();
          expect(pages.opened, hasLength(1), reason: '$status');
        }
      },
    );

    testWidgets('in French: « Renouveler l’ordre »', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 1800) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final seen = await tester.runAsync(_expired) ?? (throw StateError('x'));
      final watch = StreamController<TradeWatchState>.broadcast();
      addTearDown(watch.close);
      final trade = TradeCubit(
        _madeRecord(),
        (record, {signals = const Stream.empty(), onScreen = true}) =>
            watch.stream,
        (record, seen, {bondLoss}) => Completer<Never>().future,
      )..start();
      addTearDown(trade.close);
      final reads = FakeTransport();
      final page = TradeOrderPageCubit(
        coordinator('temple'),
        RobosatsNetwork.mainnet,
        FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
        FindPublicOrderUsecase(CoordinatorClient(reads)).execute,
      );
      addTearDown(page.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          locale: const Locale('fr'),
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: trade),
                BlocProvider.value(value: page),
              ],
              child: TradeScreen(
                now: () => tradeNow,
                coordinatorDetails: (_) => throw StateError('not opened'),
                onRenew: _Pages().call,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      watch.add(TradeScreenStatuses.watched(seen, of: _madeRecord()));
      await tester.pump();
      await tester.pump();
      expect(
        find.widgetWithText(TradeButton, 'Renouveler l’ordre'),
        findsOneWidget,
      );
    });
  });

  group('the renewal\'s page, by real gestures', () {
    testWidgets(
      'the kept terms shown locked on the order\'s coordinator, the summary, the bond estimated, the Bull wallet\'s comparison; « Create order » sends exactly the kept request, once, with no « Store your garage key »',
      (tester) async {
        final renewal = _Renewal();
        final opened = await _showRenewal(tester, renewal);
        expect(find.text('Renew Order'), findsOneWidget);
        expect(
          find.text(
            'Renewing order $tradeOrderId: a new order is made with the terms this device kept of it, under a new robot, and asks for a new bond.',
          ),
          findsOneWidget,
        );
        // The fields, locked.
        expect(_fieldEnabled(tester, '100'), isFalse);
        expect(_fieldEnabled(tester, '2'), isFalse);
        expect(find.text('Revolut Instant SEPA'), findsOneWidget);
        // The order's coordinator only: its information and limits read, no other, no « Select Host ».
        expect(renewal.infosAsked, ['temple']);
        expect(renewal.limitsAsked, ['temple']);
        expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
        // The summary and the figures of a creation.
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        expect(find.textContaining('Estimated Bond: '), findsOneWidget);
        expect(find.textContaining('Order current rate: '), findsOneWidget);
        expect(
          find.textContaining('For comparison, the Bull wallet'),
          findsOneWidget,
        );
        expect(_enabled(tester, _create), isTrue);
        await _tap(tester, _create);
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(renewal.made, hasLength(1));
        expect(renewal.made.single.$1, _kept);
        expect(renewal.made.single.$2, coordinatorOf('temple'));
        // Sent: the page cannot be left, nothing more can be pressed.
        expect(_enabled(tester, _create), isFalse);
        final bondStep =
            await tester.runAsync(() => _at([makerOrderJson(0)])) ??
            (throw StateError('x'));
        renewal.answers.single.complete(
          Ok(MakeStarted(_madeRecord(), bondStep.status, stored: true)),
        );
        await settle(tester);
        expect(opened, hasLength(1));
        _noInternalNames(tester);
      },
    );

    testWidgets(
      'a range and advanced options kept: the options open, the range and the options shown, the line of the options sent; the request sent is the kept one',
      (tester) async {
        final kept = MakeHarness.request(
          range: (50, 200),
          description: 'Bank transfer only',
          publicDuration: const Duration(hours: 2),
          escrowDuration: const Duration(hours: 5),
          bondSize: 5.5,
          premium: -1.25,
        );
        final renewal = _Renewal(kept);
        await _showRenewal(tester, renewal);
        expect(_fieldEnabled(tester, '50'), isFalse);
        expect(_fieldEnabled(tester, '200'), isFalse);
        expect(_fieldEnabled(tester, 'Bank transfer only'), isFalse);
        expect(_fieldEnabled(tester, '-1.25'), isFalse);
        expect(
          find.text('Buy BTC for 50-200 EUR at a 1.25% discount'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Advanced options sent with this order: a description, public duration 02:00, escrow/invoice timer 05:00, fidelity bond 5.5%.',
          ),
          findsOneWidget,
        );
        await _tap(tester, _create);
        await settle(tester);
        expect(renewal.made.single.$1, kept);
      },
    );

    testWidgets(
      'the coordinator\'s price 20 % above the Bull wallet\'s: the red comparison, « Create order » still on, the order sent as shown',
      (tester) async {
        final renewal = _Renewal()..rate = P2pWalletRateRead(76000);
        await _showRenewal(tester, renewal);
        expect(
          find.textContaining('above the Bull wallet'),
          findsWidgets,
        );
        expect(_enabled(tester, _create), isTrue);
        await _tap(tester, _create);
        await settle(tester);
        expect(renewal.made.single.$1, _kept);
      },
    );

    testWidgets(
      'a price changed before any robot (`MakePriceCheckChanged`): said, nothing more sent; a second press sends again, as a creation',
      (tester) async {
        final renewal = _Renewal();
        final moved = await tester.runAsync(() => limitsAt({2: 110053.38}));
        if (moved == null) fail('no limits');
        renewal.next.add(
          Err(
            MakePriceCheckChanged(
              moved,
              MakePriceSeen.of(
                currency: eur,
                coordinatorPrice: 110053.38,
                check: MakePriceCheck.of(
                  currency: eur,
                  coordinatorPrice: 110053.38,
                  wallet: P2pWalletRateRead(91711.15),
                ),
              ),
            ),
          ),
        );
        await _showRenewal(tester, renewal);
        await _tap(tester, _create);
        await settle(tester);
        expect(renewal.made, hasLength(1));
        expect(
          find.textContaining('price changed since it was shown'),
          findsOneWidget,
        );
        expect(_enabled(tester, _create), isTrue);
        await _tap(tester, _create);
        await settle(tester);
        expect(renewal.made, hasLength(2));
        expect(renewal.made.last.$1, _kept);
      },
    );

    testWidgets(
      'going back before « Create order »: nothing sent, the page left',
      (tester) async {
        final renewal = _Renewal();
        await _showRenewal(tester, renewal);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        await tester.tap(
          find
              .descendant(
                of: find.byType(CreateOrderScreen),
                matching: find.byType(IconButton),
              )
              .first,
        );
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsNothing);
        expect(find.text('the trade'), findsOneWidget);
        expect(renewal.made, isEmpty);
      },
    );

    testWidgets(
      'without a Garage Key: « You do not have a Garage Key », nothing sent',
      (tester) async {
        final renewal = _Renewal()..keys = const Ok(false);
        await _showRenewal(tester, renewal);
        await _tap(tester, _create);
        await settle(tester);
        expect(find.byType(NoRobotDialog), findsOneWidget);
        expect(renewal.made, isEmpty);
      },
    );

    testWidgets(
      'a pending make of the network listed: « Create order » off with its reason, nothing sent, as a creation',
      (tester) async {
        final renewal = _Renewal()
          ..listedMakes = [
            ActivePendingMake(
              PendingMake(
                robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 3),
                coordinatorAlias: 'temple',
                coordinatorOnion:
                    Federation.robosats.byAlias('temple')?.mainnet.onion ??
                    '',
                role: TradeRole.buyer,
                writtenAt: madeAt,
              ),
              neverSent: false,
            ),
          ];
        await _showRenewal(tester, renewal);
        expect(_enabled(tester, _create), isFalse);
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(renewal.made, isEmpty);
      },
    );

    for (final (refusal, text) in [
      (
        const RenewalTermsUnreadable(),
        'This order cannot be renewed: the terms this device kept of it could not be read.',
      ),
      (
        const RenewalNotEnded(),
        'This order cannot be renewed: this device has not seen it expired or finished.',
      ),
      (
        const RenewalCoordinatorGone(),
        'This order cannot be renewed: its coordinator is no longer in the list, or has moved.',
      ),
    ]) {
      testWidgets(
        'kept terms that cannot be renewed (${refusal.runtimeType}): said, no form, no coordinator read, nothing to press',
        (tester) async {
          final renewal = _Renewal()..read = Err(refusal);
          await _showRenewal(tester, renewal);
          expect(find.text(text), findsOneWidget);
          expect(_create, findsNothing);
          expect(renewal.limitsAsked, isEmpty);
          expect(renewal.infosAsked, isEmpty);
        },
      );
    }
  });

  group('from the trade screen to the coordinator, over the real use cases', () {
    testWidgets(
      'expired: two quick taps on « Renew Order » open one page; two quick taps on « Create order » send one make, by a fresh robot, the kept terms; the new trade opened',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390 * 3, 2400 * 3)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final harness = await tester.runAsync(MakeHarness.start);
        if (harness == null) fail('no harness');
        final record = await tester.runAsync(() async {
          final made = await harness.makeOrder();
          final record = switch (made) {
            Ok(value: MakeStarted(:final record)) => record,
            _ => throw StateError('$made'),
          };
          final first = harness.watchOf(record);
          await harness.settle();
          await first.subscription.cancel();
          harness.coordinator
            ..lockMakerBond(record.orderId)
            ..expire(record.orderId);
          return record;
        });
        if (record == null) fail('no record');
        int makes() => harness.coordinator.received
            .where((kind) => kind == ScriptedMakerRequest.make)
            .length;
        expect(makes(), 1);
        final trade = TradeCubit(
          record,
          harness.watch.execute,
          harness.cancel.execute,
          lastStored: harness.watch.lastStored,
        )..start();
        final reads = FakeTransport();
        final page = TradeOrderPageCubit(
          coordinator('temple'),
          RobosatsNetwork.testnet,
          FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
          FindPublicOrderUsecase(
            CoordinatorClient(reads, clock: () => testNow),
          ).execute,
        );
        final client = CoordinatorClient(harness.coordinator);
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
          ..rate = P2pWalletRateRead(91711.15);
        final forms = <MakeOrderCubit>[];
        final pendings = <PendingMakesCubit>[];
        final opened = <TradeRecord>[];
        var renewPages = 0;
        Future<void> settleBoth() async {
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(harness.settle);
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: trade),
                  BlocProvider.value(value: page),
                ],
                child: TradeScreen(
                  now: () => harness.now,
                  coordinatorDetails: (_) => throw StateError('not opened'),
                  onRenew: (record) async {
                    renewPages++;
                    await context.push('/renew', extra: record);
                  },
                ),
              ),
              routes: [
                GoRoute(
                  path: 'renew',
                  builder: (context, state) {
                    final renewing = state.extra as TradeRecord;
                    final form = MakeOrderCubit.renewal(
                      renewing,
                      placeholder: usd,
                      readRenewal: harness.make.renewal,
                      listHosts: (network) => RobotHosts(network, [
                        RobotHost(harness.host, refusesFirstContacts: false),
                      ]),
                      fetchInfo: FetchCoordinatorInfoUsecase(client).execute,
                      fetchLimits: FetchCoordinatorLimitsUsecase(
                        client,
                      ).execute,
                      make: harness.make.execute,
                      hasGarageKey: (_) async => const Ok(true),
                      lottery: CoordinatorLottery(() => 0.5),
                      now: () => harness.now,
                      checkPrice: CheckMakePriceUsecase(wallet).execute,
                    );
                    forms.add(form);
                    final pending = PendingMakesCubit(
                      harness.network,
                      harness.make.pendingMakes,
                      harness.make.resolve,
                      harness.make.dismiss,
                    );
                    pendings.add(pending);
                    return MultiBlocProvider(
                      providers: [
                        BlocProvider(create: (_) => form..start()),
                        BlocProvider(create: (_) => pending..start()),
                      ],
                      child: CreateOrderScreen(
                        coordinatorDetails: (_) =>
                            throw StateError('not opened'),
                        onMade: opened.add,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: testTheme,
            routerConfig: router,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
        await settleBoth();
        expect(find.text('The order has expired'), findsOneWidget);
        await _tap(tester, _renewOrder);
        await tester.tap(_renewOrder, warnIfMissed: false);
        await settleBoth();
        expect(renewPages, 1);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(forms, hasLength(1));
        await settleBoth();
        expect(find.text('Buy BTC for 100 EUR at a 2% premium'), findsOneWidget);
        expect(_enabled(tester, _create), isTrue);
        await _tap(tester, _create);
        await tester.tap(_create, warnIfMissed: false);
        await settleBoth();
        await settleBoth();
        expect(makes(), 2);
        expect(opened, hasLength(1));
        final next = opened.single;
        expect(next.orderId, isNot(record.orderId));
        expect(next.robot, isNot(record.robot));
        expect(
          harness.coordinator.order(next.orderId).body,
          harness.coordinator.order(record.orderId).body,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await trade.close();
          await page.close();
          for (final form in forms) {
            await form.close();
          }
          for (final pending in pendings) {
            await pending.close();
          }
        });
      },
    );
  });
}
