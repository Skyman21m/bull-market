import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/matching_orders.dart';
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
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_limits_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/check_make_price_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/presentation/renewals_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/renew_check_dialog.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart'
    show FakeTransport, bookOrder, coordinator, parseOrders, testNow;
import 'support/harness.dart';
import 'support/make_form.dart';
import 'support/make_harness.dart';
import 'support/maker_orders.dart';
import 'support/map_tiles.dart';
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
  RenewalsCubit? renewals,
  TradeEndReread? endReread,
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = const Size(390, 1800) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final trade = TradeCubit(record, (
    record, {
    signals = const Stream.empty(),
    onScreen = true,
  }) {
    signals.listen((_) {});
    return watch.stream;
  }, (record, seen, {bondLoss}) => Completer<Never>().future)..start();
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
      locale: locale,
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
            if (renewals != null) BlocProvider.value(value: renewals),
          ],
          // A screen of its own at each show, so that a page opened by a show before is not kept.
          child: TradeScreen(
            key: UniqueKey(),
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            onRenew: pages?.call,
            readsRenewals: renewals != null,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(
    endReread == null
        ? TradeScreenStatuses.watched(seen, of: record)
        : TradeWatchStatus(
            record,
            seen,
            takePending: false,
            endReread: endReread,
          ),
  );
  await tester.pump();
  await tester.pump();
}

Finder get _renewOrder => find.widgetWithText(TradeButton, 'Renew Order');
Finder get _renew => find.widgetWithText(TradeButton, 'Renew');
Finder get _create => find.widgetWithText(TradeButton, 'Create order');

/// « Create order » in [locale].
Finder _createIn(Locale locale) => find.widgetWithText(
  TradeButton,
  lookupP2pLocalizations(locale).p2pMakeCreateOrder,
);

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

  /// Whether an order a resolution confirmed is made with the renewal's request (#217): played by the test, every such order counted as the renewal's own by default, as an earlier try of the same renewal.
  FutureOr<Result<bool, P2pFailure>> Function(
    TradeRecord made,
    OrderRenewal renewal,
  )
  madeAsRenewal = (_, _) => const Ok(true);

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

  /// The limits the coordinator answers, the tests' by default; unreadable while [limitsUnreadable].
  CurrencyLimits? limits;
  bool limitsUnreadable = false;

  /// When set, the limits are answered once it completes: a read of the limits in flight.
  Completer<void>? limitsHeld;

  /// The page's clock, which a test moves.
  DateTime now = DateTime.utc(2026, 11, 17);

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

  /// What a resolution of a pending make gives, a make left pending by default.
  MakeOutcome Function(PendingMake make)? resolveWith;

  /// The last pending makes' cubit [pendingCubit] made.
  PendingMakesCubit? pending;

  PendingMakesCubit pendingCubit() => pending = PendingMakesCubit(
    RobosatsNetwork.mainnet,
    (network) => pendingMakes.stream,
    (make) async =>
        resolveWith?.call(make) ?? MakePending(make, MakePendingReason.unread),
    (make) async => const Ok(true),
  );

  /// The last form's cubit [cubit] made.
  MakeOrderCubit? form;

  MakeOrderCubit cubit() => form = MakeOrderCubit.renewal(
    _madeRecord(),
    placeholder: usd,
    readRenewal: (_) async => read,
    madeAsRenewal: (made, renewal) async => await madeAsRenewal(made, renewal),
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
      if (limitsHeld case final held?) await held.future;
      return limitsUnreadable
          ? const Err(CoordinatorUnreachable())
          : Ok(limits ?? _limits);
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
    now: () => now,
    checkPrice: (network, currency, price) async => MakePriceCheck.of(
      currency: currency,
      coordinatorPrice: price,
      wallet: rate,
    ),
  );
}

/// Shows the renewal's page of [renewal] above a page of the test, as the trade's page opens it, by a tap; the trades it opened in the returned list.
Future<List<TradeRecord>> _showRenewal(
  WidgetTester tester,
  _Renewal renewal, {
  Locale locale = const Locale('en'),
}) async {
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
                locationDraws: () => 0.5,
                openTiles: FakeMapTiles().open,
              ),
            ),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      key: UniqueKey(),
      theme: testTheme,
      locale: locale,
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

    for (final made in [true, false]) {
      testWidgets(
        'a tap on « Renew Order » before the records said whether an order with the same terms was made since: their answer awaited, then ${made ? '« Renew this order? » first' : 'the page at once'} (functional review of #220, R3)',
        (tester) async {
          final records = StreamController<Result<OrderRenewals, P2pFailure>>();
          addTearDown(records.close);
          final renewals = RenewalsCubit(_madeRecord(), (_) => records.stream)
            ..start();
          addTearDown(renewals.close);
          final pages = _Pages();
          await _showTrade(
            tester,
            await tester.runAsync(_expired) ?? (throw StateError('none')),
            record: _madeRecord(),
            pages: pages,
            renewals: renewals,
          );
          expect(renewals.state, isA<RenewalsReading>());
          await _tap(tester, _renewOrder);
          await tester.pump();
          // Nothing decided while the records are read: no page, the button busy.
          expect(pages.opened, isEmpty);
          expect(_enabled(tester, _renewOrder), isFalse);
          final since = TradeRecord(
            robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 1),
            coordinatorAlias: 'temple',
            coordinatorOnion: _madeRecord().coordinatorOnion,
            orderId: 777,
            role: TradeRole.buyer,
            origin: TradeOrigin.madeHere,
            takenAt: madeAt.add(const Duration(days: 1)),
            confirmedAt: madeAt.add(const Duration(days: 1)),
            closedAt: null,
          );
          records.add(
            Ok(
              OrderRenewals(_kept, [
                if (made) OrderMadeSince(since, MadeSinceStands.running),
              ]),
            ),
          );
          await tester.pump();
          await tester.pump();
          if (made) {
            expect(find.byType(RenewCheckDialog), findsOneWidget);
            expect(
              find.text(
                'An order with the same terms was already made here after this one: order 777, still running here. Renewing makes one more order, under a new robot, with a new bond to pay.',
              ),
              findsOneWidget,
            );
            expect(pages.opened, isEmpty);
            await tester.tap(find.text('Go back'));
            await tester.pumpAndSettle();
            expect(pages.opened, isEmpty);
          } else {
            expect(find.byType(RenewCheckDialog), findsNothing);
            expect(pages.opened, [_madeRecord()]);
          }
        },
      );
    }

    testWidgets(
      'an expired order opened again whose one read was answered otherwise: the state machine\'s alerts in their usual words, the advice of an order made here, then that the coordinator shows it otherwise; « Renew Order » still offered (functional review of #220, C1)',
      (tester) async {
        final closed = _madeRecord();
        final record = TradeRecord(
          robot: closed.robot,
          coordinatorAlias: closed.coordinatorAlias,
          coordinatorOnion: closed.coordinatorOnion,
          orderId: closed.orderId,
          role: closed.role,
          origin: closed.origin,
          takenAt: closed.takenAt,
          confirmedAt: closed.confirmedAt,
          closedAt: madeAt.add(const Duration(days: 1)),
        );
        await _showTrade(
          tester,
          await tester.runAsync(() => _expired(stored: false)) ??
              (throw StateError('none')),
          record: record,
          pages: _Pages(),
          endReread: TradeEndShownOtherwise(const [TradeStatusRegressed()]),
        );
        final regressed = find.text(
          'Temple of Sats sent a status that does not follow this trade. It was ignored.',
        );
        final advice = find.text(
          'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact Temple of Sats if something looks wrong.',
        );
        final otherwise = find.textContaining(
          'Temple of Sats now shows this order otherwise than this device kept it when it ended, on ',
        );
        expect(regressed, findsOneWidget);
        expect(advice, findsOneWidget);
        expect(otherwise, findsOneWidget);
        expect(
          tester.getTopLeft(regressed).dy,
          lessThan(tester.getTopLeft(otherwise).dy),
        );
        expect(find.textContaining('could not be read again'), findsNothing);
        expect(_renewOrder, findsOneWidget);
      },
    );

    testWidgets(
      'the records cannot tell whether an order with the same terms was made since: said, and « Renew Order » through « Renew this order? » saying it (security review of #220, C3, its mutant M8)',
      (tester) async {
        final renewals = RenewalsCubit(
          _madeRecord(),
          (_) => Stream.value(const Err(P2pStorageFailure())),
        )..start();
        addTearDown(renewals.close);
        final pages = _Pages();
        await _showTrade(
          tester,
          await tester.runAsync(_expired) ?? (throw StateError('none')),
          record: _madeRecord(),
          pages: pages,
          renewals: renewals,
        );
        await tester.pump();
        expect(
          find.text(
            'Bull Market could not read its records to tell whether an order with the same terms was made here since this one.',
          ),
          findsOneWidget,
        );
        await _tap(tester, _renewOrder);
        await tester.pump();
        await tester.pump();
        expect(find.byType(RenewCheckDialog), findsOneWidget);
        expect(
          find.textContaining(
            'Bull Market could not check whether an order with the same terms was already made here.',
          ),
          findsOneWidget,
        );
        expect(pages.opened, isEmpty);
        // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Renew anyway'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(pages.opened, [_madeRecord()]);
      },
    );

    testWidgets(
      'the records not answering within 10 seconds of a tap on « Renew Order »: « Renew this order? » saying the app could not check, never the page at once (security review of #220, R3)',
      (tester) async {
        final records = StreamController<Result<OrderRenewals, P2pFailure>>();
        addTearDown(records.close);
        final renewals = RenewalsCubit(_madeRecord(), (_) => records.stream)
          ..start();
        addTearDown(renewals.close);
        final pages = _Pages();
        await _showTrade(
          tester,
          await tester.runAsync(_expired) ?? (throw StateError('none')),
          record: _madeRecord(),
          pages: pages,
          renewals: renewals,
        );
        await _tap(tester, _renewOrder);
        await tester.pump(const Duration(seconds: 9));
        expect(find.byType(RenewCheckDialog), findsNothing);
        expect(pages.opened, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(find.byType(RenewCheckDialog), findsOneWidget);
        expect(
          find.textContaining(
            'Bull Market could not check whether an order with the same terms was already made here.',
          ),
          findsOneWidget,
        );
        expect(pages.opened, isEmpty);
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
      await _showTrade(
        tester,
        await tester.runAsync(_expired) ?? (throw StateError('none')),
        record: _madeRecord(),
        pages: _Pages(),
        locale: const Locale('fr'),
      );
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
        expect(find.textContaining('above the Bull wallet'), findsWidgets);
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
                    Federation.robosats.byAlias('temple')?.mainnet.onion ?? '',
                role: TradeRole.buyer,
                writtenAt: madeAt,
                closedAt: null,
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

  group(
    'the renewal\'s page: the checks of a creation, and never stuck without a word (functional review of #185, C2, R3)',
    () {
      testWidgets(
        'limits and price read more than 3 minutes ago are read again at « Create order »: a line still within goes on; a line that changed stops the press, said, nothing sent, and a second press sends',
        (tester) async {
          final renewal = _Renewal();
          await _showRenewal(tester, renewal);
          expect(renewal.limitsAsked, ['temple']);
          // Within 3 minutes: nothing read again, the make sent.
          renewal
            ..now = renewal.now.add(const Duration(minutes: 2))
            ..answer = const Err(MakeCoordinatorNotOnNetwork());
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.limitsAsked, ['temple']);
          expect(renewal.made, hasLength(1));
          // 4 minutes on, the Bull wallet's price moved within the margin: read again, the press goes on.
          renewal
            ..now = renewal.now.add(const Duration(minutes: 4))
            ..rate = P2pWalletRateRead(93000);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.limitsAsked, ['temple', 'temple']);
          expect(renewal.made, hasLength(2));
          // 4 more minutes, the Bull wallet's price now more than 10 % away: read again, the press stops on the fresh warning.
          renewal
            ..now = renewal.now.add(const Duration(minutes: 4))
            ..rate = P2pWalletRateRead(110000);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.limitsAsked, ['temple', 'temple', 'temple']);
          expect(renewal.made, hasLength(2));
          expect(
            find.text(
              'The limits and prices were read again and changed. Check the form, then press "Create order" again.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('more than 10% below'), findsOneWidget);
          // Seen: a second press sends the kept request.
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.made, hasLength(3));
          expect(renewal.made.last.$1, _kept);
        },
      );

      testWidgets(
        'the kept amount outside the coordinator\'s limits now: the reason, and what to do, in English and French; nothing to press',
        (tester) async {
          for (final (locale, line) in [
            (
              const Locale('en'),
              'This order can no longer be renewed as it was: create a new order.',
            ),
            (
              const Locale('fr'),
              'Cet ordre ne peut plus être renouvelé tel quel : créez un nouvel ordre.',
            ),
          ]) {
            final renewal = _Renewal()
              ..limits = await tester.runAsync(() => limitsAt({2: 3000000}));
            await _showRenewal(tester, renewal, locale: locale);
            expect(find.textContaining('630'), findsWidgets);
            expect(find.text(line), findsOneWidget);
            expect(_enabled(tester, _createIn(locale)), isFalse);
            await tester.tap(_createIn(locale), warnIfMissed: false);
            await settle(tester);
            expect(renewal.made, isEmpty);
          }
        },
      );

      testWidgets(
        'a currency the coordinator no longer prices: « The Bitcoin price is not synchronized. » and what to do',
        (tester) async {
          final renewal = _Renewal()
            ..limits = await tester.runAsync(() => limitsAt({1: 98000}));
          await _showRenewal(tester, renewal);
          expect(
            find.text('The Bitcoin price is not synchronized.'),
            findsWidgets,
          );
          expect(
            find.text(
              'This order can no longer be renewed as it was: create a new order.',
            ),
            findsOneWidget,
          );
          expect(_enabled(tester, _create), isFalse);
        },
      );

      testWidgets(
        'a make refused for the kept amount (`MakeAmountOutsideLimits`): said, and what to do',
        (tester) async {
          final renewal = _Renewal();
          renewal.next.add(
            Err(
              MakeAmountOutsideLimits(
                MakerAmountLimits.of(
                  _limits[eur] ?? (throw StateError('EUR')),
                  premium: _kept.premium,
                  sizeLimitSats: 1e9,
                ),
              ),
            ),
          );
          await _showRenewal(tester, renewal);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.made, hasLength(1));
          expect(
            find.text(
              'This order can no longer be renewed as it was: create a new order.',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'while the coordinator\'s limits are being read: no « create a new order », nothing to press; read, the page goes on (functional review of #185, R6, its mutant M15)',
        (tester) async {
          final renewal = _Renewal()..limitsHeld = Completer<void>();
          await _showRenewal(tester, renewal);
          expect(renewal.limitsAsked, ['temple']);
          expect(find.textContaining('can no longer be renewed'), findsNothing);
          expect(_enabled(tester, _create), isFalse);
          renewal.limitsHeld?.complete();
          await settle(tester);
          expect(find.textContaining('can no longer be renewed'), findsNothing);
          expect(_enabled(tester, _create), isTrue);
        },
      );

      for (final (name, refusal) in <(String, MakeRefusal Function())>[
        (
          'the price read just before the make changed (`MakePriceCheckChanged`)',
          () => MakePriceCheckChanged(
            _limits,
            MakePriceSeen.of(
              currency: _kept.currency,
              coordinatorPrice: 91711.15,
              check: MakePriceCheck.of(
                currency: _kept.currency,
                coordinatorPrice: 91711.15,
                wallet: P2pWalletRateRead(91711.15),
              ),
            ),
          ),
        ),
        (
          'the coordinator out of reach',
          () => const MakeCoordinatorUnreadable(CoordinatorUnreachable()),
        ),
      ]) {
        testWidgets(
          'a passing refusal, $name: no « create a new order », « Create order » still on, and a second press sends (functional review of #185, R6, its mutant M11)',
          (tester) async {
            final renewal = _Renewal();
            renewal.next.add(Err(refusal()));
            await _showRenewal(tester, renewal);
            await _tap(tester, _create);
            await settle(tester);
            expect(renewal.made, hasLength(1));
            expect(
              find.textContaining('can no longer be renewed'),
              findsNothing,
            );
            expect(_enabled(tester, _create), isTrue);
            renewal.answer = const Err(MakeCoordinatorNotOnNetwork());
            await _tap(tester, _create);
            await settle(tester);
            expect(renewal.made, hasLength(2));
            expect(renewal.made.last.$1, _kept);
          },
        );
      }

      testWidgets(
        'an order of a fixed amount kept with a description alone: the advanced options open, the description\'s text shown, locked, and sent as kept (security review of #185, R2, its mutant M15b)',
        (tester) async {
          final kept = MakeHarness.request(description: 'Bank transfer only');
          final renewal = _Renewal(kept)
            ..answer = const Err(MakeCoordinatorNotOnNetwork());
          await _showRenewal(tester, renewal);
          expect(_fieldEnabled(tester, 'Bank transfer only'), isFalse);
          expect(find.text('Bank transfer only'), findsOneWidget);
          expect(_enabled(tester, _create), isTrue);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.made.single.$1, kept);
        },
      );

      testWidgets(
        'the kept terms read again otherwise once the form was filled (a second start of the form\'s cubit): the screen\'s own guard turns « Create order » off and says why, nothing sent (security review of #185, R2, its mutant M17)',
        (tester) async {
          final renewal = _Renewal();
          await _showRenewal(tester, renewal);
          expect(_enabled(tester, _create), isTrue);
          renewal.read = Ok(
            OrderRenewal(
              orderId: tradeOrderId,
              network: RobosatsNetwork.mainnet,
              coordinator: coordinatorOf('temple'),
              request: MakeHarness.request(premium: 3),
            ),
          );
          await renewal.form?.start();
          await settle(tester);
          // The fields still show the terms filled first: the page sends nothing that is not them.
          expect(
            find.text('Buy BTC for 100 EUR at a 2% premium'),
            findsOneWidget,
          );
          expect(
            find.text(
              'The form does not show exactly the terms kept of this order: nothing can be sent.',
            ),
            findsOneWidget,
          );
          expect(_enabled(tester, _create), isFalse);
          await tester.tap(_create, warnIfMissed: false);
          await settle(tester);
          expect(renewal.made, isEmpty);
        },
      );

      testWidgets(
        'an earlier try of this renewal confirmed while the page is open: while its terms are read, the pending list emptied, a press on « Create order » sends nothing; read, the page closes on that order (security review of #220, R1, its mutant M14)',
        (tester) async {
          final earlier = PendingMake(
            robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 1),
            coordinatorAlias: 'temple',
            coordinatorOnion: _madeRecord().coordinatorOnion,
            role: TradeRole.buyer,
            writtenAt: madeAt,
            closedAt: null,
          );
          final bondStep =
              await tester.runAsync(() => _at([makerOrderJson(0)])) ??
              (throw StateError('none'));
          final made = TradeRecord(
            robot: earlier.robot,
            coordinatorAlias: 'temple',
            coordinatorOnion: earlier.coordinatorOnion,
            orderId: 777,
            role: TradeRole.buyer,
            origin: TradeOrigin.madeHere,
            takenAt: madeAt,
            confirmedAt: madeAt,
            closedAt: null,
          );
          final check = Completer<Result<bool, P2pFailure>>();
          final renewal = _Renewal()
            ..listedMakes = [ActivePendingMake(earlier, neverSent: false)]
            ..resolveWith = ((_) =>
                MakeStarted(made, bondStep.status, stored: true));
          final opened = await _showRenewal(tester, renewal);
          expect(_enabled(tester, _create), isFalse);
          // The check of the confirmed order held; the list empties meanwhile.
          renewal.madeAsRenewal = (_, _) => check.future;
          await renewal.pending?.resolve(earlier);
          await tester.pump();
          renewal.pendingMakes.add(const Ok([]));
          await settle(tester);
          await tester.tap(_create, warnIfMissed: false);
          await settle(tester);
          expect(renewal.made, isEmpty);
          check.complete(const Ok(true));
          await settle(tester);
          expect(opened, [made]);
          expect(renewal.made, isEmpty);
        },
      );

      testWidgets(
        'its own make sent with an outcome unknown, then confirmed by a resolution: the page closes on that order, its robot telling it is this page\'s, with no read to fail; one make (security review of #220, R1, N1)',
        (tester) async {
          final own = PendingMake(
            robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 1),
            coordinatorAlias: 'temple',
            coordinatorOnion: _madeRecord().coordinatorOnion,
            role: TradeRole.buyer,
            writtenAt: madeAt,
            closedAt: null,
          );
          final bondStep =
              await tester.runAsync(() => _at([makerOrderJson(0)])) ??
              (throw StateError('none'));
          final made = TradeRecord(
            robot: own.robot,
            coordinatorAlias: 'temple',
            coordinatorOnion: own.coordinatorOnion,
            orderId: 777,
            role: TradeRole.buyer,
            origin: TradeOrigin.madeHere,
            takenAt: madeAt,
            confirmedAt: madeAt,
            closedAt: null,
          );
          final renewal = _Renewal()
            ..answer = Ok(MakePending(own, MakePendingReason.unread))
            ..madeAsRenewal = ((_, _) => const Err(P2pStorageFailure()))
            ..resolveWith = ((_) =>
                MakeStarted(made, bondStep.status, stored: true));
          final opened = await _showRenewal(tester, renewal);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.made, hasLength(1));
          renewal.pendingMakes.add(
            Ok([ActivePendingMake(own, neverSent: false)]),
          );
          await settle(tester);
          renewal.pendingMakes.add(const Ok([]));
          await settle(tester);
          // The list emptied: still locked, never free for a second make.
          expect(_enabled(tester, _create), isFalse);
          await renewal.pending?.resolve(own);
          await settle(tester);
          expect(opened, [made]);
          expect(renewal.made, hasLength(1));
        },
      );

      testWidgets(
        'an earlier make confirmed while the page is open, whether it is this renewal not readable: the page sends nothing more and says to go back and open the order again; never « check it again below » (security review of #220, R1, N1)',
        (tester) async {
          final earlier = PendingMake(
            robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 1),
            coordinatorAlias: 'temple',
            coordinatorOnion: _madeRecord().coordinatorOnion,
            role: TradeRole.buyer,
            writtenAt: madeAt,
            closedAt: null,
          );
          final bondStep =
              await tester.runAsync(() => _at([makerOrderJson(0)])) ??
              (throw StateError('none'));
          final made = TradeRecord(
            robot: earlier.robot,
            coordinatorAlias: 'temple',
            coordinatorOnion: earlier.coordinatorOnion,
            orderId: 777,
            role: TradeRole.buyer,
            origin: TradeOrigin.madeHere,
            takenAt: madeAt,
            confirmedAt: madeAt,
            closedAt: null,
          );
          final renewal = _Renewal()
            ..listedMakes = [ActivePendingMake(earlier, neverSent: false)]
            ..madeAsRenewal = ((_, _) => const Err(P2pStorageFailure()))
            ..resolveWith = ((_) =>
                MakeStarted(made, bondStep.status, stored: true));
          final opened = await _showRenewal(tester, renewal);
          await renewal.pending?.resolve(earlier);
          renewal.pendingMakes.add(const Ok([]));
          await settle(tester);
          expect(opened, isEmpty);
          expect(
            find.text(
              'Bull Market could not check whether this renewal made an order: nothing more can be sent from this page. Go back, then open the order again from the Garage or « Order ».',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Check it again below'), findsNothing);
          expect(_enabled(tester, _create), isFalse);
          await tester.tap(_create, warnIfMissed: false);
          await settle(tester);
          expect(renewal.made, isEmpty);
        },
      );

      testWidgets(
        'its own make answered as no longer pending (confirmed or closed since): the page says only that it could not check, in English and French, and sends nothing more (security review of #220, N1)',
        (tester) async {
          for (final (locale, line) in [
            (
              const Locale('en'),
              'Bull Market could not check whether this renewal made an order: nothing more can be sent from this page. Go back, then open the order again from the Garage or « Order ».',
            ),
            (
              const Locale('fr'),
              'Bull Market n’a pas pu vérifier si ce renouvellement a créé un ordre : plus rien ne peut être envoyé depuis cette page. Revenez en arrière, puis rouvrez l’ordre depuis le Garage ou « Ordre ».',
            ),
          ]) {
            final renewal = _Renewal()
              ..answer = Ok(
                MakeNoLongerPending(
                  PendingMake(
                    robot: RobotSlot(RobosatsNetwork.mainnet, _fingerprint, 1),
                    coordinatorAlias: 'temple',
                    coordinatorOnion: _madeRecord().coordinatorOnion,
                    role: TradeRole.buyer,
                    writtenAt: madeAt,
                    closedAt: null,
                  ),
                ),
              );
            await _showRenewal(tester, renewal, locale: locale);
            await _tap(tester, _createIn(locale));
            await settle(tester);
            expect(renewal.made, hasLength(1));
            expect(find.text(line), findsOneWidget);
            expect(find.textContaining('confirmed'), findsNothing);
            expect(_enabled(tester, _createIn(locale)), isFalse);
            await tester.tap(_createIn(locale), warnIfMissed: false);
            await settle(tester);
            expect(renewal.made, hasLength(1));
          }
        },
      );

      testWidgets(
        'the coordinator\'s limits not read: no « create a new order », a « Retry » that reads them again, then the page goes on',
        (tester) async {
          final renewal = _Renewal()..limitsUnreadable = true;
          await _showRenewal(tester, renewal);
          expect(
            find.text('The coordinator limits are not available.'),
            findsWidgets,
          );
          expect(find.textContaining('can no longer be renewed'), findsNothing);
          renewal.limitsUnreadable = false;
          await _tap(tester, find.widgetWithText(TradeButton, 'Retry'));
          await settle(tester);
          expect(renewal.limitsAsked, ['temple', 'temple']);
          expect(_enabled(tester, _create), isTrue);
          await _tap(tester, _create);
          await settle(tester);
          expect(renewal.made.single.$1, _kept);
        },
      );
    },
  );

  group(
    'from the trade screen to the coordinator, over the real use cases and the app\'s own navigation (`P2pRouter.openRenewal`, `openMade`)',
    () {
      testWidgets(
        'rich terms read back otherwise by the coordinator: the page shows the kept ones; two quick taps on « Renew Order » open one page, two on « Create order » send one make, field for field the first one\'s, by a fresh robot; the new trade replaces both pages, nothing of the renewed order stays behind (functional review of #185, C1, R4)',
        (tester) async {
          final kept = MakeHarness.request(
            range: (50, 200),
            premium: -1.25,
            publicDuration: const Duration(hours: 2),
            escrowDuration: const Duration(hours: 5),
            bondSize: 5.5,
            description: 'Bank transfer only',
            paymentMethod: 'Revolut Instant SEPA Bizum',
          );
          final app = await _App.start(
            tester,
            request: kept,
            // What the reference's renewal would take (`TradeBox/index.tsx:162-181`): other terms read back before the expiry is read.
            beforeExpiredRead: (harness, record) =>
                harness.coordinator.orderChanges[record.orderId] = {
                  'amount': '900.00000000',
                  'has_range': false,
                  'min_amount': '10.00000000',
                  'max_amount': '20.00000000',
                  'premium': '-20.00',
                  'bond_size': '15.00',
                  'public_duration': 600,
                  'escrow_duration': 36000,
                  'payment_method': 'Cash F2F',
                  'description': 'Pay me elsewhere',
                  'currency': 1,
                },
          );
          expect(find.text('The order has expired'), findsOneWidget);
          await _tap(tester, _renewOrder);
          await tester.tap(_renewOrder, warnIfMissed: false);
          await app.settle();
          await app.settle();
          expect(app.forms, hasLength(1));
          expect(find.byType(CreateOrderScreen), findsOneWidget);
          expect(_fieldEnabled(tester, '50'), isFalse);
          expect(_fieldEnabled(tester, '200'), isFalse);
          expect(_fieldEnabled(tester, '-1.25'), isFalse);
          expect(_fieldEnabled(tester, 'Bank transfer only'), isFalse);
          expect(find.text('Revolut Instant SEPA Bizum'), findsOneWidget);
          expect(find.textContaining('Cash F2F'), findsNothing);
          expect(find.textContaining('Pay me elsewhere'), findsNothing);
          expect(
            find.text('Buy BTC for 50-200 EUR at a 1.25% discount'),
            findsOneWidget,
          );
          await _tap(tester, _create);
          await tester.tap(_create, warnIfMissed: false);
          await app.settle();
          await app.settle();
          expect(app.makes(), 2);
          final orders = app.harness.coordinator.orders.values.toList();
          final first = app.harness.coordinator.order(app.record.orderId);
          final next = orders.singleWhere((o) => o.id != app.record.orderId);
          expect(next.body, first.body);
          expect(next.body, {
            'type': 0,
            'currency': 2,
            'amount': null,
            'has_range': true,
            'min_amount': 50,
            'max_amount': 200,
            'payment_method': 'Revolut Instant SEPA Bizum',
            'is_explicit': false,
            'premium': -1.25,
            'satoshis': null,
            'public_duration': 7200,
            'escrow_duration': 18000,
            'bond_size': 5.5,
            'latitude': null,
            'longitude': null,
            'password': null,
            'description': 'Bank transfer only',
          });
          expect(next.maker.sessionKey, isNot(first.maker.sessionKey));
          // The new trade in place of the renewal's page and of the renewed order's page.
          expect(find.text('the new trade ${next.id}'), findsOneWidget);
          expect(
            find.byType(CreateOrderScreen, skipOffstage: false),
            findsNothing,
          );
          expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
          // Back from it: the tab, never the renewed order's page with a button left spinning.
          GoRouter.of(
            tester.element(find.text('the new trade ${next.id}')),
          ).pop();
          await app.settle();
          expect(find.text('the tab'), findsOneWidget);
          expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
          expect(app.makes(), 2);
          await app.close();
        },
      );

      testWidgets(
        'a renewal searches no order of the book: « Create order » at once, never « Submit », one press sends the make (#186: the reference renews from the order\'s page, without its create page, `TradeBox/index.tsx:146-200`)',
        (tester) async {
          final book = await tester.runAsync(
            () => parseOrders([
              bookOrder(
                id: 7,
                premium: 1.5,
                paymentMethod: 'Revolut Instant SEPA',
              ),
            ]),
          );
          if (book == null) fail('no book');
          // A creation of the kept terms (« Buy », 100 EUR, 2 %, « Revolut Instant SEPA ») would be shown that order.
          expect(
            MatchingOrders(
              type: OrderType.sell,
              currency: eur,
              premium: 2,
              paymentMethods: const ['Revolut Instant SEPA'],
              amount: 100,
            ).apply(book, isOwn: (_) => false),
            hasLength(1),
          );
          final app = await _App.start(tester, book: book);
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.settle();
          expect(find.byType(CreateOrderScreen), findsOneWidget);
          expect(find.text('Submit'), findsNothing);
          expect(find.text('Existing orders match yours!'), findsNothing);
          await _tap(tester, _create);
          await app.settle();
          await app.settle();
          expect(app.makes(), 2);
          await app.close();
        },
      );

      testWidgets(
        'going back from the renewal\'s page with nothing sent: the renewed order\'s page again, its button usable, a new page sends one make',
        (tester) async {
          final app = await _App.start(tester);
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.back();
          expect(find.byType(CreateOrderScreen), findsNothing);
          expect(find.text('The order has expired'), findsOneWidget);
          expect(_enabled(tester, _renewOrder), isTrue);
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.settle();
          await _tap(tester, _create);
          await app.settle();
          await app.settle();
          expect(app.forms, hasLength(2));
          expect(app.makes(), 2);
          await app.close();
        },
      );

      testWidgets(
        'a renewal whose answer is lost: the page says it, sends nothing more; back on the renewed order\'s page its button is usable, and a new page says a make is pending and sends nothing',
        (tester) async {
          final app = await _App.start(tester);
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.settle();
          app.harness.coordinator.failNext(
            ScriptedMakerRequest.make,
            ScriptedFault.answerLost,
          );
          await _tap(tester, _create);
          await app.settle();
          await app.settle();
          expect(app.makes(), 2);
          expect(
            find.textContaining('does not know yet whether'),
            findsOneWidget,
          );
          await tester.tap(_create, warnIfMissed: false);
          await app.settle();
          expect(app.makes(), 2);
          await app.back();
          expect(find.text('The order has expired'), findsOneWidget);
          expect(_enabled(tester, _renewOrder), isTrue);
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.settle();
          expect(_enabled(tester, _create), isFalse);
          await tester.tap(_create, warnIfMissed: false);
          await app.settle();
          expect(app.makes(), 2);
          await app.close();
        },
      );

      testWidgets(
        'kept terms that cannot be read: the page says why; back, the renewed order\'s button usable',
        (tester) async {
          final app = await _App.start(tester);
          app.harness.trails.readBack = (_) => null;
          await _tap(tester, _renewOrder);
          await app.settle();
          await app.settle();
          expect(
            find.text(
              'This order cannot be renewed: the terms this device kept of it could not be read.',
            ),
            findsOneWidget,
          );
          await app.back();
          expect(find.text('The order has expired'), findsOneWidget);
          expect(_enabled(tester, _renewOrder), isTrue);
          expect(app.makes(), 1);
          await app.close();
        },
      );
    },
  );
}

/// An order made on the coordinator played by the tests, expired, and the app's navigation over it, as `P2pRouter` builds it: the tab, the page of the trade (« Renew Order » through `P2pRouter.openRenewal`), the renewal's page (the made order through `P2pRouter.openMade`), and, for any other trade, a page that names it.
final class _App {
  final WidgetTester tester;
  final MakeHarness harness;
  final TradeRecord record;
  final TradeCubit trade;
  final TradeOrderPageCubit page;

  /// The renewal pages' cubits, in the order they were built.
  final List<MakeOrderCubit> forms = [];

  _App._(this.tester, this.harness, this.record, this.trade, this.page);

  int makes() => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.make)
      .length;

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(harness.settle);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The top bar's back of the renewal's page.
  Future<void> back() async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(CreateOrderScreen),
            matching: find.byType(IconButton),
          )
          .first,
    );
    await settle();
    await settle();
  }

  /// The pages' cubits closed with their providers, then the trade's.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.runAsync(() async {
      await trade.close();
      await page.close();
    });
  }

  static Future<_App> start(
    WidgetTester tester, {
    MakeOrderRequest? request,
    void Function(MakeHarness harness, TradeRecord record)? beforeExpiredRead,
    List<PublicOrder>? book,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2400 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final harness = await tester.runAsync(MakeHarness.start);
    if (harness == null) fail('no harness');
    final record = await tester.runAsync(() async {
      final made = await harness.makeOrder(request);
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
      beforeExpiredRead?.call(harness, record);
      return record;
    });
    if (record == null) fail('no record');
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
    final app = _App._(tester, harness, record, trade, page);
    final client = CoordinatorClient(harness.coordinator);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(0)))
      ..rate = P2pWalletRateRead(91711.15);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  context.pushNamed<Object>(
                    P2pRouter.tradeName,
                    extra: P2pTradeRouteArgs(record),
                  ),
                ),
                child: const Text('the tab'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              name: P2pRouter.tradeName,
              path: 'trade',
              builder: (context, state) {
                final args = state.extra as P2pTradeRouteArgs;
                if (args.record.orderId != record.orderId) {
                  return Scaffold(
                    body: Text('the new trade ${args.record.orderId}'),
                  );
                }
                return MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: trade),
                    BlocProvider.value(value: page),
                  ],
                  child: TradeScreen(
                    now: () => harness.now,
                    coordinatorDetails: (_) => throw StateError('not opened'),
                    onRenew: (renewed) => P2pRouter.openRenewal(
                      context,
                      renewed,
                      book: args.book,
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              name: P2pRouter.createName,
              path: 'create',
              builder: (context, state) {
                final args = state.extra as P2pCreateRouteArgs;
                final renewing = args.renewing;
                if (renewing == null) throw StateError('a creation');
                return MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (_) {
                        final form = MakeOrderCubit.renewal(
                          renewing,
                          placeholder: usd,
                          readRenewal: harness.make.renewal,
                          madeAsRenewal: harness.make.madeAsRenewal,
                          listHosts: (network) => RobotHosts(network, [
                            RobotHost(
                              harness.host,
                              refusesFirstContacts: false,
                            ),
                          ]),
                          fetchInfo: FetchCoordinatorInfoUsecase(
                            client,
                          ).execute,
                          fetchLimits: FetchCoordinatorLimitsUsecase(
                            client,
                          ).execute,
                          make: harness.make.execute,
                          hasGarageKey: (_) async => const Ok(true),
                          lottery: CoordinatorLottery(() => 0.5),
                          now: () => harness.now,
                          checkPrice: CheckMakePriceUsecase(wallet).execute,
                        );
                        app.forms.add(form);
                        return form..start();
                      },
                    ),
                    BlocProvider(
                      create: (_) => PendingMakesCubit(
                        harness.network,
                        harness.make.pendingMakes,
                        harness.make.resolve,
                        harness.make.dismiss,
                      )..start(),
                    ),
                  ],
                  child: CreateOrderScreen(
                    coordinatorDetails: (_) => throw StateError('not opened'),
                    onMade: (made) => P2pRouter.openMade(context, args, made),
                    locationDraws: () => 0.5,
                    openTiles: FakeMapTiles().open,
                    // A book to search, which a renewal never searches (#186).
                    book: book,
                    activeTrades: const ActiveTradesListed([]),
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
    await tester.tap(find.text('the tab'));
    await app.settle();
    return app;
  }
}
