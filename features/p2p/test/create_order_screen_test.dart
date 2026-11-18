import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/matching_orders.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/captures.dart';
import 'support/fakes.dart' show bookOrder, parseOrders;
import 'support/harness.dart';
import 'support/make_form.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_screens.dart';

late CurrencyLimits _limits;
late CoordinatorInfo _templeInfo;

/// The form's collaborators, played by the test: the coordinators' information and limits, the Bull wallet's price, the vault and the make.
final class _Form {
  /// What the Bull wallet's price check reads.
  P2pWalletBitcoinRate rate = P2pWalletRateRead(91711.15);

  /// Whether a Garage Key is stored.
  Result<bool, P2pFailure> keys = const Ok(true);

  /// The coordinators whose limits are unreadable.
  final Set<String> unreadable = {};

  /// The makes asked, in order, and the answer of each, held until the test completes it when [holdMakes].
  final List<MakeOrderRequest> made = [];
  final List<Completer<Result<MakeOutcome, MakeRefusal>>> answers = [];
  Result<MakeOutcome, MakeRefusal>? answer;

  /// The prices read of the Bull wallet, held when [holdPrices].
  final List<RobosatsCurrency> pricesAsked = [];
  final List<Completer<MakePriceCheck>> heldPrices = [];
  bool holdPrices = false;

  final List<String> limitsAsked = [];

  /// The limits the coordinators answer, the test's by default.
  CurrencyLimits? limits;

  /// The price checks the makes were sent with.
  final List<MakePriceSeen> seenSent = [];

  /// The coordinators that refuse first contacts in this run.
  final Set<String> refusing = {};

  /// The screen's clock, which a test moves.
  DateTime now = DateTime.utc(2026, 11, 17);

  /// How many times the vault was asked, and its answer held until the test completes it, when set.
  int keysAsked = 0;
  Completer<Result<bool, P2pFailure>>? vault;

  /// The network's pending makes as the records list them (#182): none by default; a test adds to [pendingMakes] and the list follows.
  final pendingMakes =
      StreamController<Result<List<ActivePendingMake>, P2pFailure>>();
  List<ActivePendingMake> listedMakes = const [];

  /// Whether the records list the pending makes at once; `false` keeps them unread until the test adds a list.
  bool listsAtOnce = true;

  /// What a resolution of a pending make gives, and the makes resolved and set aside.
  MakeOutcome Function(PendingMake make)? resolution;
  final List<PendingMake> resolved = [];
  final List<PendingMake> setAside = [];

  PendingMakesCubit pendingCubit() => PendingMakesCubit(
    RobosatsNetwork.mainnet,
    (network) => pendingMakes.stream,
    (make) async {
      resolved.add(make);
      return resolution?.call(make) ??
          MakePending(make, MakePendingReason.unread);
    },
    (make) async {
      setAside.add(make);
      listedMakes = [
        for (final listed in listedMakes)
          if (listed.make.robot != make.robot) listed,
      ];
      pendingMakes.add(Ok(listedMakes));
      return const Ok(true);
    },
  );

  MakeOrderCubit cubit() => MakeOrderCubit(
    RobosatsNetwork.mainnet,
    currency: eur,
    listHosts: (network) => RobotHosts(network, [
      for (final coordinator in Federation.robosats.on(network))
        RobotHost(
          coordinator,
          refusesFirstContacts: refusing.contains(coordinator.shortAlias),
        ),
    ]),
    fetchInfo: (coordinator, network) async =>
        coordinator.shortAlias == 'temple'
        ? Ok(_templeInfo)
        : const Err(CoordinatorUnreachable()),
    fetchLimits: (coordinator, network) async {
      limitsAsked.add(coordinator.shortAlias);
      return unreadable.contains(coordinator.shortAlias)
          ? const Err(CoordinatorUnreachable())
          : Ok(limits ?? _limits);
    },
    make: (request, {required coordinator, required network, required seen}) {
      made.add(request);
      seenSent.add(seen);
      final now = answer;
      if (now != null) return Future.value(now);
      final held = Completer<Result<MakeOutcome, MakeRefusal>>();
      answers.add(held);
      return held.future;
    },
    hasGarageKey: (_) {
      keysAsked++;
      return vault?.future ?? Future.value(keys);
    },
    lottery: CoordinatorLottery(() => 0.5),
    now: () => now,
    checkPrice: (network, currency, price) {
      pricesAsked.add(currency);
      final check = MakePriceCheck.of(
        currency: currency,
        coordinatorPrice: price,
        wallet: rate,
      );
      if (!holdPrices) return Future.value(check);
      final held = Completer<MakePriceCheck>();
      heldPrices.add(held);
      return held.future;
    },
  );
}

/// Shows the form over [form]'s cubit, on a tall phone so that the whole form is built; the trades it opened in the returned list.
Future<(List<TradeRecord>, MakeOrderCubit)> _show(
  WidgetTester tester,
  _Form form, {
  OrderType? initialType,
  Locale locale = const Locale('en'),
  List<PublicOrder>? book,
  ActiveTradesState? activeTrades,
  List<PublicOrder>? openedOrders,
}) async {
  tester.view
    ..physicalSize = const Size(390 * 3, 2400 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = form.cubit();
  addTearDown(cubit.close);
  if (form.listsAtOnce) form.pendingMakes.add(Ok(form.listedMakes));
  final pending = form.pendingCubit()..start();
  addTearDown(pending.close);
  final opened = <TradeRecord>[];
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureFrame,
      child: MaterialApp(
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
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: pending),
            ],
            // A screen of its own at each show, so that a press of a show before is not kept.
            child: CreateOrderScreen(
              key: UniqueKey(),
              initialType: initialType,
              coordinatorDetails: (_) => throw StateError('not opened'),
              onMade: opened.add,
              book: book,
              activeTrades: activeTrades,
              onOpenOrder: openedOrders?.add,
              now: () => form.now,
            ),
          ),
        ),
      ),
    ),
  );
  unawaited(cubit.start());
  unawaited(pending.resolveAll());
  await settle(tester);
  return (opened, cubit);
}

Finder get _amountField => find.byType(TextField).at(0);
Finder get _premiumField => find.byType(TextField).at(1);
Finder get _create => find.text('Create order');

/// Whether « Create order » can be pressed.
bool _createEnabled(WidgetTester tester) {
  final button = tester.widget<TradeButton>(
    find.ancestor(of: _create, matching: find.byType(TradeButton)),
  );
  return button.onPressed != null && !button.busy;
}

/// Adds [text] with « Add custom payment method ».
Future<void> _addMethod(
  WidgetTester tester,
  String text, {
  Locale locale = const Locale('en'),
}) async {
  final l10n = lookupP2pLocalizations(locale);
  await tester.tap(find.byTooltip(l10n.p2pMakeAddCustomMethod));
  await settle(tester);
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.text(l10n.p2pMakeAddPaymentMethod));
  await settle(tester);
}

/// 100 typed in the amount: the Bull wallet's price is read from then on.
Future<void> _typeAmount(WidgetTester tester) async {
  await tester.enterText(_amountField, '100');
  await settle(tester);
}

/// « Buy », 100, Revolut, a premium of 2 %.
Future<void> _fill(
  WidgetTester tester, {
  String amount = '100',
  Locale locale = const Locale('en'),
}) async {
  await tester.tap(find.text(lookupP2pLocalizations(locale).p2pMakeBuy));
  await tester.enterText(_amountField, amount);
  await _addMethod(tester, 'Revolut', locale: locale);
  await tester.enterText(_premiumField, '2');
  await settle(tester);
}

/// The switches and fields of the advanced options (#183), once they are open with a range: « From », « to », the premium, « Description », « Password ».
Finder get _advancedSwitch => find.byType(Switch).first;
Finder get _rangeSwitch => find.byType(Switch).at(1);
Finder get _minField => find.byType(TextField).at(0);
Finder get _maxField => find.byType(TextField).at(1);
Finder get _descriptionField => find.byType(TextField).at(3);

/// Opens the advanced options (#183).
Future<void> _open(WidgetTester tester) async {
  await tester.tap(_advancedSwitch);
  await settle(tester);
}

void main() {
  setUpAll(() async {
    _limits = await limitsAt({2: 91711.15, 1: 100000});
    _templeInfo = await infoAt('temple', devfund: 50, makerFee: 0.001);
  });

  group('the form, field by field', () {
    testWidgets(
      'the reference\'s fields and texts, « Sell » and the location disabled with their lines, the reason of the disabled button',
      (tester) async {
        await _show(tester, _Form());
        for (final text in [
          'Enable advanced options',
          'Coming in a later version.',
          'Buy or Sell Bitcoin? *',
          'Buy',
          'Sell',
          'Selling as maker is coming in a later version.',
          'Amount *',
          'EUR',
          'Fiat Payment Method(s) *',
          'Premium over Market (%) *',
          'Temple of Sats',
          'Order for 0 EUR at market price',
          'Create order',
          'Please select if you want to buy or sell.',
          'Order current rate: 91,711 EUR/BTC',
          'Face to Face Location',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        // « Enable advanced options » can be used once the limits are read (#183), and is off.
        final advanced = tester.widget<Switch>(find.byType(Switch));
        expect(advanced.value, isFalse);
        expect(advanced.onChanged, isNotNull);
        // Nothing of the advanced options while they are closed.
        for (final text in [
          'Amount Range',
          'Description',
          'Password',
          'Public Duration (HH:mm)',
          'Fidelity Bond Size',
        ]) {
          expect(find.text(text), findsNothing, reason: text);
        }
        expect(_createEnabled(tester), isFalse);
        // « Sell » cannot be chosen.
        expect(
          tester
              .widget<TradeButton>(
                find.ancestor(
                  of: find.text('Sell'),
                  matching: find.byType(TradeButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Sell'), warnIfMissed: false);
        await tester.pump();
        expect(find.text('Order for 0 EUR at market price'), findsOneWidget);
      },
    );

    testWidgets('« Buy » chosen from the book\'s side', (tester) async {
      await _show(tester, _Form(), initialType: OrderType.buy);
      expect(find.text('Buy BTC for 0 EUR at market price'), findsOneWidget);
      expect(find.text('Please enter an amount.'), findsOneWidget);
    });

    testWidgets('« Buy » is a choice, never a toggle', (tester) async {
      await _show(tester, _Form());
      await tester.tap(find.text('Buy'));
      await tester.pump();
      await tester.tap(find.text('Buy'));
      await tester.pump();
      expect(find.text('Buy BTC for 0 EUR at market price'), findsOneWidget);
    });

    testWidgets(
      '« Clear form »: no side, USD, the amount, the methods and the premium emptied, the coordinator kept',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Clear form'));
        await settle(tester);
        expect(find.text('Order for 0 USD at market price'), findsOneWidget);
        expect(find.text('USD'), findsOneWidget);
        expect(find.byType(InputChip), findsNothing);
        expect(tester.widget<TextField>(_amountField).controller?.text, '');
        expect(tester.widget<TextField>(_premiumField).controller?.text, '');
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(
          find.text('Please select if you want to buy or sell.'),
          findsOneWidget,
        );
        // « Clear form » reads no price: the amount is emptied (security review of #181).
        expect(form.pricesAsked, [eur]);
        expect(
          find.text('Order current rate: 100,000 USD/BTC'),
          findsOneWidget,
        );
      },
    );

    testWidgets('« Clear form » is disabled while a make runs', (tester) async {
      final form = _Form();
      await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.delete_sweep_outlined),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'no coordinator takes a new robot: said, « Retry » lists them again',
      (tester) async {
        final form = _Form();
        for (final coordinator in Federation.robosats.on(
          RobosatsNetwork.mainnet,
        )) {
          form.refusing.add(coordinator.shortAlias);
        }
        await _show(tester, form);
        expect(
          find.text('No coordinator can be chosen right now.'),
          findsOneWidget,
        );
        expect(find.text('Loading...'), findsNothing);
        await tester.tap(find.text('Buy'));
        await settle(tester);
        expect(
          find.text('The coordinator limits are not available.'),
          findsOneWidget,
        );
        form.refusing.clear();
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(
          find.text('No coordinator can be chosen right now.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'limits and price read more than 3 minutes ago are read again at « Create order »; the same form goes on',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        expect(form.limitsAsked, ['temple']);
        // Within 3 minutes: nothing read again.
        form.now = form.now.add(const Duration(minutes: 2));
        await tester.tap(_create);
        await settle(tester);
        expect(form.limitsAsked, ['temple']);
        await tester.tap(find.text('Go back'));
        await settle(tester);
        // The Bull wallet's price moved, the line still within: the press goes on, with the line read again.
        form
          ..now = form.now.add(const Duration(minutes: 2))
          ..rate = P2pWalletRateRead(100000);
        await tester.tap(_create);
        await settle(tester);
        expect(form.limitsAsked, ['temple', 'temple']);
        expect(form.pricesAsked, [eur, eur]);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.seenSent.single.walletPrice, 100000);
        expect(form.seenSent.single.verdict, MakePriceVerdict.within);
      },
    );

    testWidgets(
      'read again at « Create order », a price now beyond 10 %: no dialog, the fresh warning shown, nothing sent',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        form
          ..now = form.now.add(const Duration(minutes: 4))
          ..rate = P2pWalletRateRead(110000);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(find.textContaining('more than 10% below'), findsOneWidget);
        expect(form.made, isEmpty);
        // Pressed again, the warning seen: the dialog.
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
      },
    );

    testWidgets(
      'a filled form: the summary, the estimate, the rate and the comparison, from the values sent',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        expect(find.text('Estimated Bond: 3,207 Sats'), findsOneWidget);
        expect(find.text('Order current rate: 93,545 EUR/BTC'), findsOneWidget);
        expect(
          find.text(
            'For comparison, the Bull wallet\'s indicative price: 91,711 EUR/BTC (Temple of Sats: 91,711, gap 0.00%).',
          ),
          findsOneWidget,
        );
        expect(_createEnabled(tester), isTrue);
        await tester.enterText(_premiumField, '-5.5');
        await settle(tester);
        expect(
          find.text('Buy BTC for 100 EUR at a 5.5% discount'),
          findsOneWidget,
        );
      },
    );

    testWidgets('each reason of the disabled button, in the reference\'s words', (
      tester,
    ) async {
      await _show(tester, _Form());
      await _fill(tester);
      Future<void> typed(Finder field, String text) async {
        await tester.enterText(field, text);
        await settle(tester);
      }

      await typed(_amountField, '5');
      expect(find.text('Must be more than 19'), findsOneWidget);
      expect(
        find.text('The amount is outside the allowed limits.'),
        findsOneWidget,
      );
      await typed(_amountField, '9000');
      expect(find.text('Must be less than 4,600'), findsOneWidget);
      await typed(_amountField, '');
      expect(find.text('Please enter an amount.'), findsOneWidget);
      await typed(_amountField, '0');
      expect(find.text('The amount must be greater than 0.'), findsOneWidget);
      await typed(_amountField, '100');
      await typed(_premiumField, '1000');
      expect(find.text('Must be less than 999%'), findsOneWidget);
      await typed(_premiumField, '-100');
      expect(find.text('Must be more than -100%'), findsOneWidget);
      // At the premium kept, -99.99 %, 100 EUR is far above the largest order: the amount is said first, as the reference orders its reasons.
      expect(
        find.text('The amount is outside the allowed limits.'),
        findsOneWidget,
      );
      await typed(_amountField, '0.1');
      expect(find.text('The premium is not valid.'), findsOneWidget);
      await typed(_amountField, '100');
      await typed(_premiumField, '-');
      expect(find.text('The premium must be a number.'), findsOneWidget);
      await typed(_premiumField, '');
      expect(find.text('Buy BTC for 100 EUR at market price'), findsOneWidget);
      expect(_createEnabled(tester), isTrue);
      await tester.tap(find.byTooltip('Remove Revolut'));
      await settle(tester);
      expect(find.text('Please select a payment method.'), findsOneWidget);
      expect(_createEnabled(tester), isFalse);
    });

    testWidgets(
      'hostile numbers: nothing crashes, nothing is sent that the summary does not show',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        for (final text in [
          '1,000.5',
          '1 000',
          'NaN',
          'Infinity',
          '1e5',
          '0x10',
          '+5',
          '--5',
          '1${char(0x200B)}00',
        ]) {
          await tester.enterText(_amountField, text);
          await settle(tester);
          expect(
            find.text('Please enter an amount.'),
            findsOneWidget,
            reason: text,
          );
          expect(_createEnabled(tester), isFalse, reason: text);
        }
        // The comma and the Arabic-Indic digits read as the summary shows them.
        await tester.enterText(_amountField, '150,5');
        await settle(tester);
        expect(
          find.text('Buy BTC for 150.5 EUR at a 2% premium'),
          findsOneWidget,
        );
        await tester.enterText(_amountField, chars([0x0661, 0x0662, 0x0660]));
        await settle(tester);
        expect(
          find.text('Buy BTC for 120 EUR at a 2% premium'),
          findsOneWidget,
        );
        // A huge figure is said outside the limits.
        // A figure a double cannot hold as typed is not taken: the field keeps what it had (security review of #181).
        await tester.enterText(_amountField, '9' * 20);
        await settle(tester);
        expect(
          tester.widget<TextField>(_amountField).controller?.text,
          chars([0x0661, 0x0662, 0x0660]),
        );
        await tester.enterText(_amountField, '1${'0' * 18}');
        await settle(tester);
        expect(
          find.text('The amount is outside the allowed limits.'),
          findsOneWidget,
        );
        // More decimals than kept are not taken: the field keeps what it had.
        await tester.enterText(_amountField, '100.5');
        await tester.enterText(_amountField, '100.123456789');
        await settle(tester);
        expect(
          tester.widget<TextField>(_amountField).controller?.text,
          '100.5',
        );
        // The same with the full-width full stop (second functional pass of #181, R13).
        await tester.enterText(_amountField, '100${chars([0xFF0E])}${'1' * 9}');
        await settle(tester);
        expect(
          tester.widget<TextField>(_amountField).controller?.text,
          '100.5',
        );
        await tester.enterText(_premiumField, '1.234');
        await settle(tester);
        expect(tester.widget<TextField>(_premiumField).controller?.text, '2');
      },
    );

    testWidgets(
      'payment methods: the reference\'s list, a custom one kept as seen, an invisible one refused, a text too long said',
      (tester) async {
        await _show(tester, _Form());
        // The list: a tap on the field opens it.
        await tester.tap(
          find.byTooltip(
            'Enter your preferred fiat payment methods. Fast methods are highly recommended.',
          ),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField).last, 'Revolut');
        await settle(tester);
        await tester.tap(find.text('Revolut').last);
        await settle(tester);
        await tester.tap(find.byTooltip('Close'));
        await settle(tester);
        expect(find.byType(InputChip), findsOneWidget);
        // A custom method: its ends trimmed, its spaces single.
        await _addMethod(tester, '  Bank   transfer  ');
        expect(find.text('Bank transfer'), findsOneWidget);
        // A method already chosen is not added twice.
        await _addMethod(tester, 'Bank transfer');
        expect(find.byType(InputChip), findsNWidgets(2));
        // Nor the same with or without its variation selector (security review of #181).
        await _addMethod(tester, 'Pay ${chars([0x2764, 0xFE0F])}');
        await _addMethod(tester, 'Pay ${chars([0x2764])}');
        expect(find.byType(InputChip), findsNWidgets(3));
        // Spaces only: « Can't be empty »; a zero width space: refused, said. Nothing is said before anything is typed.
        await tester.tap(find.byTooltip('Add custom payment method'));
        await settle(tester);
        expect(find.text('Can\'t be empty'), findsNothing);
        await tester.enterText(find.byType(TextField).last, '   ');
        await tester.pump();
        expect(find.text('Can\'t be empty'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, char(0x200B));
        await tester.pump();
        expect(
          find.text(
            'Others would not see this text as you typed it. Use visible characters only.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Add payment method'));
        await tester.pump();
        expect(find.text('Add payment method'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.byType(InputChip), findsNWidgets(3));
        // Too long: the reference's line.
        await _addMethod(tester, 'x' * 40);
        expect(find.text('Must be at most 50 characters'), findsOneWidget);
        await tester.tap(find.text('Buy'));
        await tester.enterText(_amountField, '100');
        await settle(tester);
        expect(find.text('The payment method is not valid.'), findsOneWidget);
      },
    );

    testWidgets(
      'the coordinator unreadable, then another chosen: its limits read again',
      (tester) async {
        final form = _Form()..unreadable.add('temple');
        await _show(tester, form);
        expect(
          find.text('The coordinator limits are not available.'),
          findsOneWidget,
        );
        // The line stays, its figure waiting, as the reference's skeleton.
        expect(find.text('Order current rate:'), findsOneWidget);
        expect(find.text('EUR/BTC'), findsOneWidget);
        expect(find.textContaining('Order current rate: '), findsNothing);
        form.unreadable.clear();
        await tester.tap(find.text('Temple of Sats'));
        await settle(tester);
        await tester.tap(find.text('Temple of Sats').last);
        await settle(tester);
        expect(form.limitsAsked, ['temple', 'temple']);
        expect(find.text('Order current rate: 91,711 EUR/BTC'), findsOneWidget);
      },
    );

    testWidgets(
      'a currency without a price: « The Bitcoin price is not synchronized. », no figure',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await tester.tap(find.text('EUR'));
        await settle(tester);
        await tester.tap(find.text('GBP'));
        await settle(tester);
        await tester.tap(find.text('Buy'));
        await settle(tester);
        expect(
          find.text('The Bitcoin price is not synchronized.'),
          findsOneWidget,
        );
        expect(find.text('Order current rate:'), findsOneWidget);
        expect(find.text('GBP/BTC'), findsOneWidget);
        expect(find.textContaining('Order current rate: '), findsNothing);
        expect(find.textContaining('For comparison'), findsNothing);
        // No amount typed: nothing read (security review of #181).
        expect(form.pricesAsked, isEmpty);
      },
    );
  });

  group('the price check (the owner\'s decision of 2026-11-17)', () {
    testWidgets(
      'beyond 10 % below: the line in red and the warning, « Create order » still sends',
      (tester) async {
        final form = _Form()..rate = P2pWalletRateRead(110000);
        await _show(tester, form);
        await _fill(tester);
        final line = find.text(
          'For comparison, the Bull wallet\'s indicative price: 110,000 EUR/BTC (Temple of Sats: 91,711, gap -16.63%).',
        );
        expect(line, findsOneWidget);
        expect(
          tester.widget<Text>(line).style?.color,
          tester.element(line).bull.error,
        );
        expect(
          find.text(
            'Temple of Sats\'s price is more than 10% below the Bull wallet\'s: your bond would be larger than it should be. Check it before creating the order.',
          ),
          findsOneWidget,
        );
        expect(_createEnabled(tester), isTrue);
        form.answer = const Err(MakePriceUnknown());
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
      },
    );

    testWidgets('beyond 10 % above: the warning of fewer sats', (tester) async {
      final form = _Form()..rate = P2pWalletRateRead(80000);
      await _show(tester, form);
      await _typeAmount(tester);
      expect(
        find.text(
          'For comparison, the Bull wallet\'s indicative price: 80,000 EUR/BTC (Temple of Sats: 91,711, gap +14.64%).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Temple of Sats\'s price is more than 10% above the Bull wallet\'s: you would receive fewer sats when the order is taken. Check it before creating the order.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('within 10 %: no warning', (tester) async {
      final form = _Form()..rate = P2pWalletRateRead(100000);
      await _show(tester, form);
      await _typeAmount(tester);
      expect(find.textContaining('gap -8.29%'), findsOneWidget);
      expect(find.textContaining('more than 10%'), findsNothing);
    });

    testWidgets(
      'a currency the Bull wallet does not price: one line, no figure, no « Retry »',
      (tester) async {
        final form = _Form()..rate = const P2pWalletRateNotPriced();
        await _show(tester, form);
        await _typeAmount(tester);
        expect(
          find.text(
            'The Bull wallet has no price for EUR: rate not checked. You are trusting Temple of Sats\'s price: check it yourself before creating the order.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('For comparison'), findsNothing);
        expect(find.text('Retry'), findsNothing);
      },
    );

    testWidgets(
      'a price that could not be read: « rate not checked », « Retry » reads it again',
      (tester) async {
        final form = _Form()..rate = const P2pWalletRateUnavailable();
        await _show(tester, form);
        await _typeAmount(tester);
        expect(
          find.text(
            'The Bull wallet\'s price of a bitcoin in EUR could not be read: rate not checked.',
          ),
          findsOneWidget,
        );
        form.rate = P2pWalletRateRead(91711.15);
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(form.pricesAsked, [eur, eur]);
        expect(find.textContaining('For comparison'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      },
    );

    testWidgets(
      'another currency: read once for it, a late answer for the former never shown',
      (tester) async {
        final form = _Form()..holdPrices = true;
        await _show(tester, form);
        await _typeAmount(tester);
        expect(
          find.text('Reading the Bull wallet\'s price for comparison…'),
          findsOneWidget,
        );
        await tester.tap(find.text('EUR'));
        await settle(tester);
        await tester.tap(find.text('USD'));
        await settle(tester);
        expect(form.pricesAsked, [eur, usd]);
        form.heldPrices.first.complete(
          MakePriceCheck.of(
            currency: eur,
            coordinatorPrice: 91711.15,
            wallet: P2pWalletRateRead(91711.15),
          ),
        );
        await settle(tester);
        expect(find.textContaining('For comparison'), findsNothing);
        form.heldPrices.last.complete(
          MakePriceCheck.of(
            currency: usd,
            coordinatorPrice: 100000,
            wallet: P2pWalletRateRead(100000),
          ),
        );
        await settle(tester);
        expect(find.textContaining('100,000 USD/BTC'), findsWidgets);
      },
    );

    testWidgets('no amount typed: no price read, no comparison line', (
      tester,
    ) async {
      final form = _Form();
      await _show(tester, form);
      expect(form.pricesAsked, isEmpty);
      expect(find.textContaining('For comparison'), findsNothing);
      expect(find.text('Order current rate: 91,711 EUR/BTC'), findsOneWidget);
      await _typeAmount(tester);
      expect(form.pricesAsked, [eur]);
      expect(find.textContaining('For comparison'), findsOneWidget);
    });

    testWidgets(
      'read again at the press, a comparison gone « rate not checked »: no dialog, said, nothing sent (security review of #181, C2)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        form
          ..now = form.now.add(const Duration(minutes: 4))
          ..rate = const P2pWalletRateUnavailable();
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(
          find.text(
            'The limits and prices were read again and changed. Check the form, then press "Create order" again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('could not be read'), findsOneWidget);
        expect(form.made, isEmpty);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
      },
    );

    testWidgets(
      'pressed while the Bull wallet\'s price is being read, a line that warns: the read awaited, the fields locked, then the line it shows and no dialog; a second press goes on (second security review of #181, R8)',
      (tester) async {
        final form = _Form()..holdPrices = true;
        await _show(tester, form);
        await _fill(tester);
        expect(
          find.text('Reading the Bull wallet\'s price for comparison…'),
          findsOneWidget,
        );
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(tester.widget<TextField>(_amountField).enabled, isFalse);
        expect(form.keysAsked, 0);
        form.heldPrices.single.complete(
          MakePriceCheck.of(
            currency: eur,
            coordinatorPrice: 91711.15,
            wallet: P2pWalletRateRead(110000),
          ),
        );
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(
          find.text(
            'The price comparison has just been updated. Check it, then press "Create order" again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('more than 10% below'), findsOneWidget);
        expect(tester.widget<TextField>(_amountField).enabled, isTrue);
        expect(form.made, isEmpty);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.seenSent.single.verdict, MakePriceVerdict.below);
      },
    );

    for (final (name, wallet, verdict) in [
      (
        'not priced',
        const P2pWalletRateNotPriced(),
        MakePriceVerdict.notPriced,
      ),
      (
        'not read',
        const P2pWalletRateUnavailable(),
        MakePriceVerdict.unverified,
      ),
    ]) {
      testWidgets(
        'pressed while the Bull wallet\'s price is being read, a line $name: stopped, said (third functional pass of #181)',
        (tester) async {
          final form = _Form()..holdPrices = true;
          await _show(tester, form);
          await _fill(tester);
          await tester.tap(_create);
          await settle(tester);
          form.heldPrices.single.complete(
            MakePriceCheck.of(
              currency: eur,
              coordinatorPrice: 91711.15,
              wallet: wallet,
            ),
          );
          await settle(tester);
          expect(find.byType(StoreTokenDialog), findsNothing);
          expect(
            find.text(
              'The price comparison has just been updated. Check it, then press "Create order" again.',
            ),
            findsOneWidget,
          );
          await tester.tap(_create);
          await settle(tester);
          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(form.seenSent.single.verdict, verdict);
        },
      );
    }

    testWidgets(
      'pressed while the Bull wallet\'s price is being read, a line with no warning: no stop, straight to « Store your garage key » with that line (third functional pass of #181)',
      (tester) async {
        final form = _Form()..holdPrices = true;
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        form.heldPrices.single.complete(
          MakePriceCheck.of(
            currency: eur,
            coordinatorPrice: 91711.15,
            wallet: P2pWalletRateRead(92000),
          ),
        );
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        expect(
          find.textContaining('The price comparison has just been updated'),
          findsNothing,
        );
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
        expect(form.seenSent.single.verdict, MakePriceVerdict.within);
      },
    );

    testWidgets(
      'the English stop lines write "Create order" in straight quotes, as the rest of the app\'s English',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        final l10n = lookupP2pLocalizations(const Locale('en'));
        for (final text in [
          l10n.p2pMakePriceCheckChanged('Temple of Sats'),
          l10n.p2pMakePricesReadAgain,
          l10n.p2pMakePriceReadAtPress,
        ]) {
          expect(text, contains('"Create order"'));
          expect(text, isNot(contains('«')));
        }
      },
    );

    testWidgets(
      'read again at the press, limits that now refuse the amount: no dialog, the reason shown (functional review of #181, R14)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        form
          ..now = form.now.add(const Duration(minutes: 4))
          ..limits = await tester.runAsync(
            () => limitsOf({2: (91711.15, 150, 4000)}),
          );
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(
          find.text('The amount is outside the allowed limits.'),
          findsOneWidget,
        );
        expect(form.made, isEmpty);
      },
    );

    testWidgets(
      'a make refused because the price changed at the make: the app\'s words, the new check shown, a second press possible',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        final lower = await tester.runAsync(() => limitsAt({2: 9171.115}));
        form.answer = Err(
          MakePriceCheckChanged(
            lower ?? (throw StateError('no limits')),
            MakePriceSeen.of(currency: eur, coordinatorPrice: 9171.115),
          ),
        );
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(
          find.text(
            'Temple of Sats\'s price changed since it was shown. Check the comparison, then press "Create order" again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('more than 10% below'), findsOneWidget);
        expect(form.seenSent.single.verdict, MakePriceVerdict.within);
        expect(_createEnabled(tester), isTrue);
      },
    );

    testWidgets('the fields are locked while the press waits for the vault', (
      tester,
    ) async {
      final form = _Form()..vault = Completer();
      await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await tester.pump();
      expect(tester.widget<TextField>(_amountField).enabled, isFalse);
      expect(tester.widget<TextField>(_premiumField).enabled, isFalse);
      form.vault?.complete(const Ok(true));
      await settle(tester);
    });
  });

  group('the confirmation and the make', () {
    testWidgets(
      '« Store your garage key », then « Done » sends the request of the summary once, the fields locked',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        expect(form.made, isEmpty);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
        final request = form.made.single;
        expect(request.type, OrderType.buy);
        expect(request.currency, eur);
        expect(request.amount.max.value, 100);
        expect(request.premium.percent, 2);
        expect(request.paymentMethod, 'Revolut');
        expect(find.text('Creating your order…'), findsOneWidget);
        // A second press, and typing, change nothing while it runs.
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(tester.widget<TextField>(_amountField).enabled, isFalse);
        expect(form.made, hasLength(1));
      },
    );

    testWidgets('« Go back » sends nothing', (tester) async {
      final form = _Form();
      await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await settle(tester);
      await tester.tap(find.text('Go back'));
      await settle(tester);
      expect(form.made, isEmpty);
      expect(_createEnabled(tester), isTrue);
    });

    testWidgets(
      'a second tap while the first press still waits for the vault does nothing: the press\'s own guard',
      (tester) async {
        final form = _Form()..vault = Completer();
        await _show(tester, form);
        await _fill(tester);
        // No frame between the two taps: the second reaches the button's handler, which the press's guard stops.
        await tester.tap(_create);
        await tester.tap(_create);
        expect(form.keysAsked, 1);
        form.vault?.complete(const Ok(true));
        await settle(tester);
        expect(
          find.byType(StoreTokenDialog, skipOffstage: false),
          findsOneWidget,
        );
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
      },
    );

    testWidgets(
      'a tap once « Store your garage key » is up lands on its barrier: one dialog, one make',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        // The vault answers at once: the dialog is pushed before the second tap, whose point is then the dialog's barrier, not the button (functional review of #181, R3).
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(form.keysAsked, 1);
        expect(
          find.byType(StoreTokenDialog, skipOffstage: false),
          findsOneWidget,
        );
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
      },
    );

    testWidgets(
      'without a Garage Key: « You do not have a Garage Key », nothing sent',
      (tester) async {
        final form = _Form()..keys = const Ok(false);
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(NoRobotDialog), findsOneWidget);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(form.made, isEmpty);
      },
    );

    testWidgets('a made order opens its trade', (tester) async {
      final status = await tester.runAsync(() async {
        final statuses = await TradeScreenStatuses.make();
        return (await statuses.bondStep()).status;
      });
      final form = _Form()
        ..answer = Ok(
          MakeStarted(
            TradeScreenStatuses.record,
            status ?? (throw StateError('no status')),
            stored: true,
          ),
        );
      final (opened, _) = await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(opened, [TradeScreenStatuses.record]);
    });

    testWidgets(
      'refused before any robot: said in the app\'s words, the form free again',
      (tester) async {
        final form = _Form()
          ..answer = const Err(MakeTermsRefused(MakerFeeTooHigh()));
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(
          find.text(
            'Temple of Sats asks for a maker fee above 1 %. The order was not created.',
          ),
          findsOneWidget,
        );
        expect(_createEnabled(tester), isTrue);
      },
    );

    testWidgets('not made by the coordinator: said without its text', (
      tester,
    ) async {
      final form = _Form()
        ..answer = Ok(
          MakeNotMade(
            _pending,
            refusal: const OrderSizeRefused(OrderSizeRefusal.tooBig),
          ),
        );
      await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(
        find.text('Your order is too big. The order was not created.'),
        findsOneWidget,
      );
    });

    for (final (reason, text) in [
      (
        OrderSizeRefusal.rangeTooNarrow,
        'Maximum range amount must be at least 50 percent higher than the minimum amount. The order was not created.',
      ),
      (
        OrderSizeRefusal.rangeMaximumTooBig,
        'Your order maximum amount is too big. The order was not created.',
      ),
      (
        OrderSizeRefusal.rangeMinimumTooSmall,
        'Your order minimum amount is too small. The order was not created.',
      ),
      (
        OrderSizeRefusal.rangeTooWide,
        'Your order amount range is too large. Max amount can only be 15 times bigger than min amount. The order was not created.',
      ),
    ]) {
      testWidgets(
        'a range refused by the coordinator (${reason.code}): its message, as the reference shows it (#183)',
        (tester) async {
          final form = _Form()
            ..answer = Ok(
              MakeNotMade(_pending, refusal: OrderSizeRefused(reason)),
            );
          await _show(tester, form);
          await _fill(tester);
          await _open(tester);
          await tester.ensureVisible(_create);
          await tester.pump();
          await tester.tap(_create);
          await settle(tester);
          await tester.tap(find.text('Done'));
          await settle(tester);
          expect(find.text(text), findsOneWidget);
        },
      );
    }

    testWidgets('an outcome unknown: said, the form locked, nothing made again', (
      tester,
    ) async {
      final form = _Form()
        ..answer = Ok(MakePending(_pending, MakePendingReason.outcomeUnknown));
      await _show(tester, form);
      await _fill(tester);
      await tester.tap(_create);
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(
        find.text(
          'Bull Market does not know yet whether Temple of Sats made your order. Check it again below, or set it aside.',
        ),
        findsOneWidget,
      );
      expect(_createEnabled(tester), isFalse);
      expect(tester.widget<TextField>(_amountField).enabled, isFalse);
      await tester.tap(_create, warnIfMissed: false);
      await settle(tester);
      expect(form.made, hasLength(1));
    });

    testWidgets(
      'the make written pending shows above the form, resolved there; a resolution that confirms it opens its trade',
      (tester) async {
        final form = _Form()
          ..answer = Ok(
            MakePending(_pending, MakePendingReason.outcomeUnknown),
          );
        final (opened, _) = await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        form.listedMakes = [ActivePendingMake(_pending, neverSent: false)];
        form.pendingMakes.add(Ok(form.listedMakes));
        await settle(tester);
        expect(find.text('Creating your order…'), findsWidgets);
        expect(find.text('Retry'), findsOneWidget);
        expect(
          find.text(
            'An order of yours is still being created. Check it again or set it aside before creating another.',
          ),
          findsOneWidget,
        );
        final started = await _startedOf(tester);
        form.resolution = (make) => started;
        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(form.resolved, [_pending]);
        expect(opened, [TradeScreenStatuses.record]);
      },
    );

    for (final setAside in [true, false]) {
      testWidgets(
        'an outcome unknown, then its pending make ${setAside ? 'set aside' : 'found not made'}: the form free again on the same page, « Creating your order… » gone (functional review C1)',
        (tester) async {
          final form = _Form()
            ..answer = Ok(
              MakePending(_pending, MakePendingReason.outcomeUnknown),
            );
          await _show(tester, form);
          await _fill(tester);
          await tester.tap(_create);
          await settle(tester);
          await tester.tap(find.text('Done'));
          await settle(tester);
          form.listedMakes = [ActivePendingMake(_pending, neverSent: false)];
          form.pendingMakes.add(Ok(form.listedMakes));
          await settle(tester);
          expect(_createEnabled(tester), isFalse);
          form.resolution = setAside
              ? (make) => MakePending(make, MakePendingReason.notRecognized)
              : (make) {
                  form.listedMakes = [];
                  form.pendingMakes.add(const Ok([]));
                  return MakeNotMade(make);
                };
          await tester.tap(find.text('Retry'));
          await settle(tester);
          if (setAside) {
            await tester.tap(find.text('Set aside'));
            await settle(tester);
            await tester.tap(find.text('Set aside').last);
            await settle(tester);
          } else {
            expect(find.text('The order was not created.'), findsOneWidget);
          }
          expect(find.text('Creating your order…'), findsNothing);
          expect(find.textContaining('Check it again below'), findsNothing);
          expect(tester.widget<TextField>(_amountField).enabled, isTrue);
          expect(_createEnabled(tester), isTrue);
          // Nothing was made beside it, nor in its place.
          expect(form.made, hasLength(1));
        },
      );
    }

    testWidgets(
      'the make being sent, the network\'s pending makes emptied (the make confirmed or closed meanwhile): the form stays locked, no second make (security review of #182, M17)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.answers, hasLength(1));
        // The make written pending, then confirmed or closed before its answer reaches the form.
        form.pendingMakes.add(
          Ok([ActivePendingMake(_pending, neverSent: false)]),
        );
        await settle(tester);
        form.pendingMakes.add(const Ok([]));
        await settle(tester);
        expect(_createEnabled(tester), isFalse);
        expect(tester.widget<TextField>(_amountField).enabled, isFalse);
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(form.made, hasLength(1));
      },
    );

    testWidgets(
      'a press drawn before a pending make of the network reached the button: the press\'s own guard sends nothing (security review of #182, M04)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        expect(_createEnabled(tester), isTrue);
        form.pendingMakes.add(
          Ok([ActivePendingMake(_pending, neverSent: false)]),
        );
        // The list reaches the cubit, not yet a frame: the button drawn is still the enabled one.
        await tester.idle();
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(form.keysAsked, 0);
        expect(form.made, isEmpty);
      },
    );

    testWidgets(
      'while the records are not read yet: « Create order » off, and no line says a make is pending (functional review R6)',
      (tester) async {
        final form = _Form()..listsAtOnce = false;
        await _show(tester, form);
        await _fill(tester);
        expect(_createEnabled(tester), isFalse);
        expect(find.textContaining('still being created'), findsNothing);
        form.pendingMakes.add(const Ok([]));
        await settle(tester);
        expect(_createEnabled(tester), isTrue);
      },
    );

    testWidgets(
      'opened again with a pending make of the network: « Create order » disabled until it is resolved or set aside, never made beside it (security review of #181, S2)',
      (tester) async {
        final form = _Form()
          ..listedMakes = [ActivePendingMake(_pending, neverSent: false)];
        await _show(tester, form);
        // Resolved once when the form opens, left pending.
        expect(form.resolved, [_pending]);
        await _fill(tester);
        expect(_createEnabled(tester), isFalse);
        expect(
          find.text(
            'An order of yours is still being created. Check it again or set it aside before creating another.',
          ),
          findsWidgets,
        );
        await tester.tap(_create, warnIfMissed: false);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsNothing);
        expect(form.made, isEmpty);
        // Set aside: the form is free again, and nothing was made in its place.
        await tester.tap(find.text('Set aside'));
        await settle(tester);
        await tester.tap(find.text('Set aside').last);
        await settle(tester);
        expect(form.setAside, [_pending]);
        expect(_createEnabled(tester), isTrue);
        expect(form.made, isEmpty);
      },
    );

    testWidgets(
      'going back while the make is sent: the page stays and says to wait; the answer then opens the trade (security review of #181, S1)',
      (tester) async {
        final form = _Form();
        final (opened, _) = await _show(tester, form);
        await _fill(tester);
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.answers, hasLength(1));
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        await navigator.maybePop();
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(
          find.text(
            'Wait for Temple of Sats\'s answer before leaving: your order is being created.',
          ),
          findsOneWidget,
        );
        // Under « Create order », where the user is, not at the top of the page (functional review R7).
        expect(
          tester
              .getTopLeft(find.textContaining('before leaving: your order'))
              .dy,
          greaterThan(tester.getTopLeft(_create).dy),
        );
        form.answers.single.complete(Ok(await _startedOf(tester)));
        await settle(tester);
        expect(opened, [TradeScreenStatuses.record]);
      },
    );
  });

  group('the advanced options (#183)', () {
    Future<void> tapShown(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await settle(tester);
    }

    testWidgets(
      'not usable before the limits are read, as the reference\'s switch (`MakerForm.tsx:710`)',
      (tester) async {
        final form = _Form()..unreadable.add('temple');
        await _show(tester, form);
        expect(tester.widget<Switch>(_advancedSwitch).onChanged, isNull);
      },
    );

    testWidgets(
      'opened: « Amount Range » on, the range from the amount typed (half and the amount), the reference\'s defaults, the bond on the maximum',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        await _open(tester);
        for (final text in [
          'Amount Range',
          'From',
          'to',
          'Description',
          'Password',
          'Public Duration (HH:mm)',
          '23:59',
          'Escrow/Invoice Timer (HH:mm)',
          '03:00',
          'Fidelity Bond Size',
          'Buy BTC for 50-100 EUR at a 2% premium',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        // Under « Face to Face Location » and « Password ».
        expect(find.text('Coming in a later version.'), findsNWidgets(2));
        expect(tester.widget<TextField>(_minField).controller?.text, '50');
        expect(tester.widget<TextField>(_maxField).controller?.text, '100');
        // The password cannot be typed before #189.
        expect(
          tester.widget<TextField>(find.byType(TextField).at(4)).enabled,
          isFalse,
        );
        // The bond on the maximum, as with 100 typed: (100 / 93,545) × 10^8 × 3 %.
        expect(find.text('Estimated Bond: 3,207 Sats'), findsOneWidget);
        expect(tester.widget<Slider>(find.byType(Slider)).value, 3);
        expect(find.byType(RangeSlider), findsOneWidget);
        expect(_createEnabled(tester), isTrue);
      },
    );

    testWidgets(
      'without an amount typed: a quarter and three quarters of the coordinator\'s largest order',
      (tester) async {
        final form = _Form()..limits = await limitsOf({2: (50000, 100, 1000)});
        await _show(tester, form);
        await _open(tester);
        expect(tester.widget<TextField>(_minField).controller?.text, '250');
        expect(tester.widget<TextField>(_maxField).controller?.text, '750');
      },
    );

    testWidgets(
      '« Exact Amount »: the amount field again, the range\'s bounds kept for later',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        await _open(tester);
        await tester.tap(_rangeSwitch);
        await settle(tester);
        expect(find.text('Exact Amount'), findsOneWidget);
        expect(find.text('From'), findsNothing);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        await tester.tap(_rangeSwitch);
        await settle(tester);
        expect(
          find.text('Buy BTC for 50-100 EUR at a 2% premium'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a range out of the form\'s rules: the fields in error and the reference\'s reason',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_minField, '90');
        await settle(tester);
        expect(find.text('The amount range is not valid.'), findsWidgets);
        expect(_createEnabled(tester), isFalse);
        await tester.enterText(_minField, '62.5');
        await settle(tester);
        expect(_createEnabled(tester), isTrue);
      },
    );

    testWidgets(
      'a range typed: the Bull wallet\'s price read for its maximum, with no exact amount typed (functional review of #183, C6, M1)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        expect(form.pricesAsked, isEmpty);
        // Opened with no amount: the range from the coordinator's largest order, its maximum above 0.
        await _open(tester);
        expect(form.pricesAsked, [eur]);
      },
    );

    testWidgets(
      'another currency whose orders exclude the range: the range set again, as the reference (functional review of #183, C6, M2)',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_minField, '15');
        await settle(tester);
        final expected = MakerRange.afterCurrency(
          min: 15,
          max: 100,
          limit: _limits[usd],
        );
        expect(expected, isNotNull);
        await tester.tap(find.text('EUR'));
        await settle(tester);
        await tester.tap(find.text('USD'));
        await settle(tester);
        double fieldOf(Finder field) => double.parse(
          tester.widget<TextField>(field).controller?.text ?? '',
        );
        expect(fieldOf(_minField), expected?.min);
        expect(fieldOf(_maxField), expected?.max);
        // Within the new currency's orders, a range is kept as typed.
        await tester.enterText(_minField, '50');
        await tester.enterText(_maxField, '100');
        await settle(tester);
        await tester.tap(find.text('USD'));
        await settle(tester);
        await tester.tap(find.text('EUR'));
        await settle(tester);
        expect(fieldOf(_minField), 50);
        expect(fieldOf(_maxField), 100);
      },
    );

    testWidgets(
      'the options sent are said under the summary: as information while open, in the warning colour once closed; nothing at the defaults (security review of #183, C1)',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        expect(find.textContaining('sent with this order'), findsNothing);
        await _open(tester);
        // Opened, all at their defaults: no line either.
        expect(find.textContaining('sent with this order'), findsNothing);
        await tester.enterText(_descriptionField, 'Call me');
        await settle(tester);
        tester.widget<Slider>(find.byType(Slider)).onChanged?.call(15);
        await settle(tester);
        // The escrow timer at 01:00, typed in the picker's keyboard mode.
        await tester.ensureVisible(find.text('03:00'));
        await tester.pump();
        await tester.tap(find.text('03:00'));
        await settle(tester);
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await settle(tester);
        final picker = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(picker.at(0), '01');
        await tester.enterText(picker.at(1), '00');
        await tester.tap(find.text('OK'));
        await settle(tester);
        const open =
            'Advanced options sent with this order: a description, escrow/invoice timer 01:00, fidelity bond 15%.';
        expect(find.text(open), findsOneWidget);
        final colors = tester.element(find.text(open)).bull;
        expect(
          tester.widget<Text>(find.text(open)).style?.color,
          colors.textMuted,
        );
        await tester.ensureVisible(_advancedSwitch);
        await tester.pump();
        await tester.tap(_advancedSwitch);
        await settle(tester);
        const closed =
            'Advanced options closed, but still sent with this order: a description, escrow/invoice timer 01:00, fidelity bond 15%.';
        expect(find.text(closed), findsOneWidget);
        expect(
          tester.widget<Text>(find.text(closed)).style?.color,
          colors.warning,
        );
        // The description itself is never repeated there.
        expect(find.textContaining('Call me'), findsNothing);
        // « Clear form »: the defaults again, no line.
        await tester.tap(find.byTooltip('Clear form'));
        await settle(tester);
        expect(find.textContaining('sent with this order'), findsNothing);
      },
    );

    group('the slider, by a real drag (functional review of #183, C1)', () {
      /// Drags the thumb of [from] to [to], values of the slider over the form's limits 105.06 to 999.6 (100 to 1,000 EUR at 2 %); the track taken to run inside 24 points at each end, the drag starting on the thumb.
      Future<void> drag(WidgetTester tester, double from, double to) async {
        final slider = find.byType(RangeSlider);
        await tester.ensureVisible(slider);
        await tester.pump();
        final rect = tester.getRect(slider);
        const low = 105.06;
        const high = 999.6;
        double x(double value) =>
            rect.left + 24 + (rect.width - 48) * (value - low) / (high - low);
        final y = rect.center.dy;
        final gesture = await tester.startGesture(Offset(x(from), y));
        await tester.pump();
        for (var i = 1; i <= 10; i++) {
          await gesture.moveTo(Offset(x(from + (to - from) * i / 10), y));
          await tester.pump();
        }
        await gesture.up();
        await settle(tester);
      }

      double fieldOf(WidgetTester tester, Finder field) =>
          double.parse(tester.widget<TextField>(field).controller?.text ?? '');

      Future<void> start(WidgetTester tester) async {
        final form = _Form()..limits = await limitsOf({2: (50000, 100, 1000)});
        await _show(tester, form);
        await _fill(tester, amount: '400');
        await _open(tester);
        expect(fieldOf(tester, _minField), 200);
        expect(fieldOf(tester, _maxField), 400);
      }

      testWidgets('« to » pulled down to about 280: « From » follows, at 1.6', (
        tester,
      ) async {
        await start(tester);
        await drag(tester, 400, 280);
        final min = fieldOf(tester, _minField);
        final max = fieldOf(tester, _maxField);
        // The reference: 175-280 (`AmountRange.tsx:101-102`); the drag lands within a few euros.
        expect(max, inInclusiveRange(260, 300));
        expect(min, lessThan(200));
        expect(max / min, closeTo(1.6, 0.02));
        expect(_createEnabled(tester), isTrue);
      });

      testWidgets('« From » pulled up to about 300: « to » follows, at 1.6', (
        tester,
      ) async {
        await start(tester);
        await drag(tester, 200, 300);
        final min = fieldOf(tester, _minField);
        final max = fieldOf(tester, _maxField);
        // The reference: 300-480.
        expect(min, inInclusiveRange(280, 320));
        expect(max, greaterThan(400));
        expect(max / min, closeTo(1.6, 0.02));
        expect(_createEnabled(tester), isTrue);
      });
    });

    testWidgets(
      'the description: the reference\'s line when too long, the app\'s when not seen as written',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_descriptionField, 'x' * 241);
        await settle(tester);
        expect(
          find.text('Must be equal to or shorter than 240 characters'),
          findsOneWidget,
        );
        expect(find.text('The description is not valid.'), findsWidgets);
        expect(_createEnabled(tester), isFalse);
        await tester.enterText(_descriptionField, 'a${char(0x200B)}b');
        await settle(tester);
        expect(
          find.text(
            'Others would not see this text as you typed it. Use visible characters only.',
          ),
          findsOneWidget,
        );
        expect(_createEnabled(tester), isFalse);
      },
    );

    testWidgets(
      '« Create order » sends the range, the description, the durations and the bond size shown',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_descriptionField, '  Revolut only  ');
        await settle(tester);
        final bond = tester.widget<Slider>(find.byType(Slider)).onChanged;
        bond?.call(5.1);
        await settle(tester);
        expect(tester.widget<Slider>(find.byType(Slider)).value, 5);
        // The public duration chosen in the picker, typed in its keyboard mode: 00:05 becomes the reference's shortest, 00:10.
        await tapShown(tester, find.text('23:59'));
        expect(find.text('Public order length'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await settle(tester);
        final picker = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(picker.at(0), '00');
        await tester.enterText(picker.at(1), '05');
        await tester.tap(find.text('OK'));
        await settle(tester);
        expect(find.text('00:10'), findsOneWidget);
        expect(find.text('Estimated Bond: 5,345 Sats'), findsOneWidget);
        await tapShown(tester, _create);
        await tester.tap(find.text('Done'));
        await settle(tester);
        final request = form.made.single;
        final amount = request.amount;
        expect(amount, isA<RangeOrderAmount>());
        expect(amount.min.value, 50);
        expect(amount.max.value, 100);
        expect(request.description, 'Revolut only');
        expect(request.publicDuration, const Duration(minutes: 10));
        expect(request.escrowDuration, const Duration(hours: 3));
        expect(request.bondSize.percent, 5);
        // Locked while it is sent.
        expect(tester.widget<Switch>(_advancedSwitch).onChanged, isNull);
        expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      },
    );

    testWidgets(
      'closed again: the exact amount, the other options kept and sent, as the reference sends them',
      (tester) async {
        final form = _Form();
        await _show(tester, form);
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_descriptionField, 'Fast');
        await settle(tester);
        tester.widget<Slider>(find.byType(Slider)).onChanged?.call(10);
        await settle(tester);
        await tester.tap(_advancedSwitch);
        await settle(tester);
        expect(find.text('Description'), findsNothing);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        // The estimate shows the bond size kept: (100 / 93,545) × 10^8 × 10 %.
        expect(find.text('Estimated Bond: 10,690 Sats'), findsOneWidget);
        await tapShown(tester, _create);
        await tester.tap(find.text('Done'));
        await settle(tester);
        final request = form.made.single;
        expect(request.amount, isA<FixedOrderAmount>());
        expect(request.description, 'Fast');
        expect(request.bondSize.percent, 10);
      },
    );

    testWidgets(
      '« Clear form »: the options closed and at their defaults, « Amount Range » as it was',
      (tester) async {
        await _show(tester, _Form());
        await _fill(tester);
        await _open(tester);
        await tester.tap(_rangeSwitch);
        await settle(tester);
        await tester.enterText(find.byType(TextField).at(2), 'Fast');
        tester.widget<Slider>(find.byType(Slider)).onChanged?.call(10);
        await settle(tester);
        await tester.tap(find.byTooltip('Clear form'));
        await settle(tester);
        expect(tester.widget<Switch>(_advancedSwitch).value, isFalse);
        expect(find.text('Description'), findsNothing);
        await _fill(tester);
        await _open(tester);
        expect(find.text('Exact Amount'), findsOneWidget);
        expect(tester.widget<Slider>(find.byType(Slider)).value, 3);
        expect(find.text('23:59'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(2))
              .controller
              ?.text,
          '',
        );
      },
    );

    testWidgets('the French texts of the options', (tester) async {
      await _show(tester, _Form(), locale: const Locale('fr'));
      await _fill(tester, locale: const Locale('fr'));
      await _open(tester);
      for (final text in [
        'Activer les options avancées',
        'Plage de montant',
        'De',
        'à',
        'Description',
        'Mot de passe',
        'Durée publique (HH:mm)',
        'Minuterie de dépôt de garantie/facture (HH:mm)',
        'Taille de la caution de fidélité',
        'Emplacement face à face',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });
  });

  testWidgets('the French texts', (tester) async {
    final form = _Form();
    await _show(tester, form, locale: const Locale('fr'));
    await tester.tap(find.text('Acheter'));
    await tester.enterText(_amountField, '100');
    await settle(tester);
    expect(
      find.text('Acheter BTC pour 100 EUR au prix du marché'),
      findsOneWidget,
    );
    expect(
      find.text('Veuillez sélectionner un mode de paiement.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Pour comparaison, prix indicatif du portefeuille Bull',
      ),
      findsOneWidget,
    );
  });

  group('« Existing orders match yours! » (#186)', () {
    // The book the tab received, read by the package's parser (`support/fakes.dart`): EUR sell orders but #2 (a buy order) and #5 (USD); #1, #3, #4 and #6 match « Buy », 100 EUR, Revolut, 2 %; #7 is at 2.5 %.
    late List<PublicOrder> book;
    setUpAll(() async {
      book = await parseOrders([
        bookOrder(id: 1, premium: 1.5),
        bookOrder(id: 2, type: 0),
        bookOrder(id: 3, premium: 0.5, paymentMethod: 'Revolut'),
        bookOrder(id: 4, premium: 2),
        bookOrder(id: 5, currency: 1),
        bookOrder(
          id: 6,
          premium: 1,
          amount: null,
          minAmount: 50,
          maxAmount: 500,
        ),
        bookOrder(id: 7, premium: 2.5),
      ]);
    });

    /// No trade of the device: every order of the book can be offered.
    const none = ActiveTradesListed([]);

    /// The device holds a trade of order [id] of temple, taken here.
    ActiveTradesListed holding(int id) => ActiveTradesListed([
      ActiveTrade(
        TradeRecord(
          robot: RobotSlot(
            RobosatsNetwork.mainnet,
            switch (GarageKeyFingerprint.of(tradeKey)) {
              Ok(:final value) => value,
              Err(:final failure) => throw StateError('$failure'),
            },
            1,
          ),
          coordinatorAlias: 'temple',
          coordinatorOnion:
              Federation.robosats.byAlias('temple')?.mainnet.onion ??
              (throw StateError('temple')),
          orderId: id,
          role: TradeRole.buyer,
          origin: TradeOrigin.takenHere,
          takenAt: DateTime.utc(2026, 11, 17),
          confirmedAt: DateTime.utc(2026, 11, 17),
          closedAt: null,
        ),
        const ActiveTradeTakeNeverSent(),
      ),
    ]);

    /// The ids of the orders shown, top to bottom.
    List<int> shown(WidgetTester tester) => [
      for (final row in tester.widgetList<OfferRow>(find.byType(OfferRow)))
        row.order.id,
    ];

    Finder submit() => find.text('Submit');
    Finder title() => find.text('Existing orders match yours!');
    Finder edit() => find.byTooltip('Edit order');

    /// What the form asked of anyone so far: the limits, the Bull wallet's prices, the vault, the makes.
    List<int> asked(_Form form) => [
      form.limitsAsked.length,
      form.pricesAsked.length,
      form.keysAsked,
      form.made.length,
    ];

    testWidgets(
      'orders match: « Submit » shows them above the summary, the fields folded away, asking nothing; « Edit order » unfolds them (`MakerPage/index.tsx:106-146`, `MakerForm.tsx:1286-1330`)',
      (tester) async {
        final form = _Form();
        await _show(tester, form, book: book, activeTrades: none);
        // Nothing typed: no amount, so nothing matches (`Number(null)`).
        expect(find.text('Create order'), findsOneWidget);
        expect(submit(), findsNothing);
        await _fill(tester);
        expect(submit(), findsOneWidget);
        expect(_create, findsNothing);
        expect(title(), findsNothing);
        final before = asked(form);
        final comparison = tester
            .widget<Text>(find.textContaining('Bull wallet'))
            .data;
        await tester.tap(submit());
        await settle(tester);
        expect(title(), findsOneWidget);
        // Four match (#3, #6, #1, #4, the lowest premium first): on the tall test screen (2,400 points) the reference's table shows three, its pagination hiding the rest (`MatchingOrders.rowsShown`).
        expect(MatchingOrders.rowsShown(4, 2400), 3);
        expect(shown(tester), [3, 6, 1]);
        // Folded away as in the reference: the side, the amount, the methods, the premium, « Clear form » and the options' switch.
        for (final text in [
          'Buy or Sell Bitcoin? *',
          'Amount *',
          'Fiat Payment Method(s) *',
          'Premium over Market (%) *',
          'Enable advanced options',
        ]) {
          expect(find.text(text), findsNothing, reason: text);
        }
        // What stays, as it was: the coordinator, the summary, the rate and the Bull wallet's comparison.
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        expect(find.textContaining('Order current rate:'), findsOneWidget);
        expect(
          tester.widget<Text>(find.textContaining('Bull wallet')).data,
          comparison,
        );
        // « Create order » now, with « Edit order » beside it.
        expect(_create, findsOneWidget);
        expect(_createEnabled(tester), isTrue);
        expect(submit(), findsNothing);
        expect(edit(), findsOneWidget);
        // Nothing asked of anyone by the search or by « Submit ».
        expect(asked(form), before);

        await tester.tap(edit());
        await settle(tester);
        expect(title(), findsNothing);
        expect(find.byType(OfferRow), findsNothing);
        expect(find.text('Premium over Market (%) *'), findsOneWidget);
        expect(submit(), findsOneWidget);
        expect(edit(), findsNothing);
        // Typing changes what matches: at 1 %, #3 and #6, of which the table shows one.
        await tester.enterText(_premiumField, '1');
        await settle(tester);
        await tester.tap(submit());
        await settle(tester);
        expect(shown(tester), [3]);
        expect(asked(form), before);
      },
    );

    testWidgets(
      '« Create order » after « Submit » goes on as before: « Store your garage key », then the make of the form as typed',
      (tester) async {
        final form = _Form()..answer = const Err(MakePriceUnknown());
        await _show(tester, form, book: book, activeTrades: none);
        await _fill(tester);
        await tester.tap(submit());
        await settle(tester);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
        expect(form.made.single.premium.percent, 2);
        expect(form.made.single.paymentMethod, 'Revolut');
      },
    );

    testWidgets(
      'no order matches: « Create order » at once, with no title, as the reference\'s',
      (tester) async {
        final form = _Form();
        await _show(tester, form, book: book, activeTrades: none);
        await _fill(tester, amount: '2000');
        expect(submit(), findsNothing);
        expect(_createEnabled(tester), isTrue);
        await tester.tap(_create);
        await settle(tester);
        expect(find.byType(StoreTokenDialog), findsOneWidget);
        expect(title(), findsNothing);
      },
    );

    testWidgets(
      'an order this device holds a trade of is never offered; while the device\'s trades are not listed, none is',
      (tester) async {
        // Only #3 matches at 0.5 %: held, it is not offered, and the button reads « Create order ».
        await _show(tester, _Form(), book: book, activeTrades: holding(3));
        await _fill(tester);
        await tester.enterText(_premiumField, '0.5');
        await settle(tester);
        expect(submit(), findsNothing);
        expect(_create, findsOneWidget);
        // With #1 held instead, the others are offered and #1 is not.
        await _show(tester, _Form(), book: book, activeTrades: holding(1));
        await _fill(tester);
        await tester.tap(submit());
        await settle(tester);
        expect(shown(tester), [3, 6]);
        for (final active in [
          const ActiveTradesLoading(),
          const ActiveTradesUnreadable(),
        ]) {
          await _show(tester, _Form(), book: book, activeTrades: active);
          await _fill(tester);
          expect(submit(), findsNothing, reason: '$active');
        }
      },
    );

    testWidgets(
      'a tap on an order shown opens it; while the make runs, a tap opens nothing',
      (tester) async {
        final form = _Form();
        final opened = <PublicOrder>[];
        await _show(
          tester,
          form,
          book: book,
          activeTrades: none,
          openedOrders: opened,
        );
        await _fill(tester);
        await tester.tap(submit());
        await settle(tester);
        await tester.tap(find.byType(OfferRow).at(1));
        await settle(tester);
        expect([for (final order in opened) order.id], [6]);
        // The make held: the form locked, the orders shown stay but open nothing.
        await tester.tap(_create);
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(form.made, hasLength(1));
        await tester.tap(find.byType(OfferRow).first);
        await settle(tester);
        expect([for (final order in opened) order.id], [6]);
        form.answers.single.complete(const Err(MakePriceUnknown()));
        await settle(tester);
      },
    );

    testWidgets(
      'the advanced options\' line stays as it is while the orders are shown',
      (tester) async {
        final form = _Form();
        await _show(tester, form, book: book, activeTrades: none);
        await _fill(tester);
        await _open(tester);
        await tester.enterText(_descriptionField, 'Fast');
        await settle(tester);
        // Closed again: the description is still sent, said in the warning colour.
        await _open(tester);
        const closed =
            'Advanced options closed, but still sent with this order: a description.';
        expect(find.text(closed), findsOneWidget);
        await tester.tap(submit());
        await settle(tester);
        expect(find.text(closed), findsOneWidget);
        expect(shown(tester), [3, 6, 1]);
      },
    );
  });

  group('captures (with P2P_CAPTURE_DIR)', () {
    setUpAll(loadCaptureFonts);
    for (final locale in const [Locale('fr'), Locale('en')]) {
      testWidgets(
        'the stop lines, the pending make and the wait of the form in ${locale.languageCode}',
        skip: captureDirectory == null,
        (tester) async {
          final code = locale.languageCode;
          Future<void> bottom() async {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -3000),
            );
            await settle(tester);
          }

          // The Bull wallet's price read at the press, a line that warns.
          var form = _Form()..holdPrices = true;
          await _show(tester, form, locale: locale);
          await _fill(tester, locale: locale);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pMakeCreateOrder),
          );
          await settle(tester);
          form.heldPrices.single.complete(
            MakePriceCheck.of(
              currency: eur,
              coordinatorPrice: 91711.15,
              wallet: P2pWalletRateRead(110000),
            ),
          );
          await settle(tester);
          await capture(tester, '$code-creer-arret-prix-lu');
          // Limits read again and changed.
          form = _Form();
          await _show(tester, form, locale: locale);
          await _fill(tester, locale: locale);
          form
            ..now = form.now.add(const Duration(minutes: 4))
            ..rate = const P2pWalletRateUnavailable();
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pMakeCreateOrder),
          );
          await settle(tester);
          await capture(tester, '$code-creer-arret-relu');
          // The price changed at the make.
          form = _Form()
            ..answer = Err(
              MakePriceCheckChanged(
                await tester.runAsync(() => limitsAt({2: 9171.115})) ??
                    (throw StateError('no limits')),
                MakePriceSeen.of(currency: eur, coordinatorPrice: 9171.115),
              ),
            );
          await _show(tester, form, locale: locale);
          await _fill(tester, locale: locale);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pMakeCreateOrder),
          );
          await settle(tester);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pCommonDone),
          );
          await settle(tester);
          await capture(tester, '$code-creer-arret-prix-change');
          // A pending make of the network above the form.
          form = _Form()
            ..listedMakes = [ActivePendingMake(_pending, neverSent: false)];
          await _show(tester, form, locale: locale);
          await capture(tester, '$code-creer-creation-en-attente');
          // Going back while the make is sent.
          form = _Form();
          await _show(tester, form, locale: locale);
          await _fill(tester, locale: locale);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pMakeCreateOrder),
          );
          await settle(tester);
          await tester.tap(
            find.text(lookupP2pLocalizations(locale).p2pCommonDone),
          );
          await settle(tester);
          await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
          await settle(tester);
          await capture(tester, '$code-creer-envoi-attendre');
          await bottom();
          await capture(tester, '$code-creer-envoi-attendre-bas');
        },
      );
    }
  });
}

final PendingMake _pending = PendingMake(
  robot: TradeScreenStatuses.record.robot,
  coordinatorAlias: 'temple',
  coordinatorOnion: TradeScreenStatuses.record.coordinatorOnion,
  role: TradeRole.buyer,
  writtenAt: DateTime.utc(2026, 11, 17),
  closedAt: null,
);

/// A make confirmed: the trade of the tests at its first status.
Future<MakeStarted> _startedOf(WidgetTester tester) async {
  final status = await tester.runAsync(() async {
    final statuses = await TradeScreenStatuses.make();
    return (await statuses.bondStep()).status;
  });
  return MakeStarted(
    TradeScreenStatuses.record,
    status ?? (throw StateError('no status')),
    stored: true,
  );
}
