import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/captures.dart';
import 'support/harness.dart';
import 'support/make_form.dart';
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
}) async {
  tester.view
    ..physicalSize = const Size(390 * 3, 2400 * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = form.cubit();
  addTearDown(cubit.close);
  form.pendingMakes.add(Ok(form.listedMakes));
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
          child: CreateOrderScreen(
            initialType: initialType,
            coordinatorDetails: (_) => throw StateError('not opened'),
            onMade: opened.add,
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
Future<void> _addMethod(WidgetTester tester, String text) async {
  await tester.tap(find.byTooltip('Add custom payment method'));
  await settle(tester);
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.text('Add payment method'));
  await settle(tester);
}

/// 100 typed in the amount: the Bull wallet's price is read from then on.
Future<void> _typeAmount(WidgetTester tester) async {
  await tester.enterText(_amountField, '100');
  await settle(tester);
}

/// « Buy », 100, Revolut, a premium of 2 %.
Future<void> _fill(WidgetTester tester, {String amount = '100'}) async {
  await tester.tap(find.text('Buy'));
  await tester.enterText(_amountField, amount);
  await _addMethod(tester, 'Revolut');
  await tester.enterText(_premiumField, '2');
  await settle(tester);
}

void main() {
  setUpAll(() async {
    _limits = await limitsAt({2: 91711.15, 1: 100000});
    _templeInfo = await infoAt('temple', devfund: 50, makerFee: 0.001);
  });

  group('the form, field by field', () {
    testWidgets(
      'the reference\'s fields and texts, « Sell » and the advanced options disabled with their lines, the reason of the disabled button',
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
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
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
      ('not priced', const P2pWalletRateNotPriced(), MakePriceVerdict.notPriced),
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
          ..answer = Ok(MakePending(_pending, MakePendingReason.outcomeUnknown));
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
            'Wait for the answer of Temple of Sats before leaving: your order is being created.',
          ),
          findsOneWidget,
        );
        form.answers.single.complete(Ok(await _startedOf(tester)));
        await settle(tester);
        expect(opened, [TradeScreenStatuses.record]);
      },
    );
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

          // In French, the pending make above the form; the stops need the English form's labels.
          if (code == 'fr') {
            final pending = _Form()
              ..listedMakes = [ActivePendingMake(_pending, neverSent: false)];
            await _show(tester, pending, locale: locale);
            await capture(tester, '$code-creer-creation-en-attente');
            return;
          }
          // The Bull wallet's price read at the press, a line that warns.
          var form = _Form()..holdPrices = true;
          await _show(tester, form, locale: locale);
          await _fill(tester);
          await tester.tap(_create);
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
          await _fill(tester);
          form
            ..now = form.now.add(const Duration(minutes: 4))
            ..rate = const P2pWalletRateUnavailable();
          await tester.tap(_create);
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
          await _fill(tester);
          await tester.tap(_create);
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
          await _fill(tester);
          await tester.tap(_create);
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
