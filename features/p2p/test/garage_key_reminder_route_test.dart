import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_keyring.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/usecases/trade/trade_garage_key_usecase.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:p2p/src/ui/widgets/garage_key_view.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/store_token_dialog.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/key_output.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// « Store your garage key » only for the external Garage Key, with its masked « Back it up! » and its copy (#318, decided on 2026-11-28), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`, with a re-authentication of the test as the shell lends the Garage its PIN screen) by the user's gestures: the real router, records, use cases, form, order page and dialog.
///
/// The coordinators are played by `ScriptedMakerCoordinator` for a make and `ScriptedCoordinator` for a take (never a real one); the clipboard is a fake of the platform's; the key is the test key of the trade harness (`tradeKey`), imported as the external Garage Key, or, selected as the internal Garage Key #0, the same key as the test seam gives it for the words (`setUpP2pForTesting`), so that the coordinators know its robots either way. Nothing is paid.
const _net = RobosatsNetwork.testnet;

/// Which Garage Key new trades take.
enum _Key { internal, external }

/// The fake clipboard of the platform: what was written last, `null` until then.
final class _Clipboard {
  String? text;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              text = (call.arguments as Map)['text'] as String?;
            case 'Clipboard.getData':
              return {'text': text};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }
}

/// The re-authentication of the test, in place of the wallet's PIN screen: « test PIN ok » passes it, « test leave » leaves it as the back button does.
final class _Gate {
  int asked = 0;

  Widget call(VoidCallback onAuthenticated) {
    asked++;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onAuthenticated,
              child: const Text('test PIN ok'),
            ),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('test leave'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The books of the other coordinators, empty.
CoordinatorResponse _emptyBook() => CoordinatorResponse(
  statusCode: 404,
  headers: const {'content-type': 'application/json'},
  body: utf8.encode(
    jsonEncode({'not_found': 'No orders found, be the first to make one'}),
  ),
);

String _aliasOf(String host) {
  for (final coordinator in Federation.robosats.on(_net)) {
    if (Uri.parse(coordinator.origins(_net).onion ?? '').host == host) {
      return coordinator.shortAlias;
    }
  }
  throw StateError('unknown host');
}

/// For a make: [maker] answers every robot's request, the limits and the make, whatever the host; each coordinator's `/api/info/` its own; the books empty.
final class _MakeCoordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final Map<String, ScriptedMakerCoordinator> _infos = {};

  _MakeCoordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final path = request.url.path;
    if (path.startsWith('/api/book')) return Ok(_emptyBook());
    if (path == '/api/info/' && request.robot == null) {
      final alias = _aliasOf(request.url.host);
      final info = _infos[alias] ??= ScriptedMakerCoordinator(
        network: _net,
        robots: const [],
        clock: () => DateTime.utc(2026, 11, 20, 9),
        alias: alias,
      );
      return info.send(request);
    }
    return maker.send(request);
  }
}

/// For a take: temple's requests to [temple], whose book holds order 42; the other coordinators' books empty and their `/api/info/` their own.
final class _TakeCoordinators implements CoordinatorTransport {
  final ScriptedCoordinator temple;
  final Map<String, ScriptedCoordinator> _others = {};

  _TakeCoordinators(this.temple);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    if (alias == temple.coordinator.shortAlias) return temple.send(request);
    if (request.url.path.startsWith('/api/book')) return Ok(_emptyBook());
    final other = _others[alias] ??= ScriptedCoordinator(
      network: _net,
      robots: const [],
      clock: () => DateTime.utc(2026, 11, 20, 9),
      alias: alias,
    );
    return other.send(request);
  }
}

final class _App {
  final WidgetTester tester;
  final GetIt locator;
  final _Gate gate;
  final _Clipboard clipboard;
  final void Function(Duration) advance;

  /// The make's coordinator, or the take's.
  final ScriptedMakerCoordinator? maker;
  final ScriptedCoordinator? temple;

  _App(
    this.tester,
    this.locator,
    this.gate,
    this.clipboard,
    this.advance, {
    this.maker,
    this.temple,
  });

  /// The makes the coordinator received.
  int get makes =>
      maker?.received
          .where((kind) => kind == ScriptedMakerRequest.make)
          .length ??
      0;

  /// The takes temple received: before the trade, its only `POST /api/order/`.
  int get takes =>
      temple?.requests
          .where(
            (request) =>
                request.method == CoordinatorHttpMethod.post &&
                request.url.path == '/api/order/',
          )
          .length ??
      0;

  Finder get dialog => find.byType(StoreTokenDialog);

  Finder inDialog(Finder finder) =>
      find.descendant(of: dialog, matching: finder);

  /// The copy button of « Back it up! ».
  Finder get copyButton => inDialog(find.byType(IconButton));

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  /// Every text the screen draws, the dialog's included, and its semantics labels: where a key shown in clear would be.
  String drawn() {
    final texts = [
      for (final element in find.byType(Text).evaluate())
        (element.widget as Text).data ?? '',
      for (final element in find.byType(RichText).evaluate())
        (element.widget as RichText).text.toPlainText(),
    ];
    // The semantics are on in every widget test (`testWidgets`, `semanticsEnabled`): an empty dump would check nothing, so the dialog's label must be in it (security review of #320, R5).
    final semantics = switch (tester
        .binding
        .renderViews
        .first
        .owner
        ?.semanticsOwner
        ?.rootSemanticsNode) {
      final root? => root.toStringDeep(),
      null => '',
    };
    expect(semantics, contains('Back it up!'));
    return [...texts, semantics].join('\n');
  }

  /// The copy of « Back it up! », then « test PIN ok » when [pass], else « test leave ».
  Future<void> copy({required bool pass}) async {
    await tap(copyButton);
    await settle(tester);
    expect(find.text('test PIN ok'), findsOneWidget);
    await tap(find.text(pass ? 'test PIN ok' : 'test leave'));
    await settle(tester);
    await settle(tester);
  }

  /// The tree left and the clipboard's clearing run: nothing of the app's runs after the test.
  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }

  /// The key of the app: [key] selected for new trades; the tab open.
  static Future<_App> start(
    WidgetTester tester,
    _Key key, {
    bool take = false,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final clipboard = _Clipboard()..install();
    var clock = DateTime.utc(2026, 11, 20, 9);
    ScriptedMakerCoordinator? maker;
    ScriptedCoordinator? temple;
    final CoordinatorTransport transport;
    if (take) {
      temple = ScriptedCoordinator(
        network: _net,
        robots: TradeHarness.robotsOf(_net),
        clock: () => clock,
      );
      transport = _TakeCoordinators(temple);
    } else {
      maker = ScriptedMakerCoordinator(
        network: _net,
        robots: TradeHarness.robotsOf(_net),
        clock: () => clock,
      );
      maker.prices[1] = 50000;
      transport = _MakeCoordinators(maker);
    }
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
        ..rate = P2pWalletRateRead(50000),
      robotKeys: HarnessKeys(),
      bolt11Decoder: maker?.decoder ?? temple?.decoder,
    );
    final gate = _Gate();
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [
        const P2pFeature().route(
          locator,
          network: (_) => _net,
          reauthenticate: gate.call,
        ),
      ],
    );
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await tester.runAsync(() async {
      final keys = locator<GarageKeyRepository>();
      expect(await keys.import(_net, tradeKey), isA<Ok>());
      expect(
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
        isA<Ok>(),
      );
      if (key == _Key.internal) {
        // Key 0 of the words activated, as the Garage's first opening does, and selected: new trades take it.
        expect(await keys.keyring(_net), isA<Ok>());
        expect(await keys.select(_net, const SelectedWordsKey(0)), isA<Ok>());
      }
      // The key new trades take is the one asked: without an index for the external Garage Key.
      expect(switch (await keys.forNewTrade(_net)) {
        Ok(:final value) => (value.index == null) == (key == _Key.external),
        Err() => false,
      }, isTrue);
    });
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    return _App(
      tester,
      locator,
      gate,
      clipboard,
      (by) => clock = clock.add(by),
      maker: maker,
      temple: temple,
    );
  }

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

  /// « Create », then the form filled: « Buy », 100 USD, « Revolut » as a custom method, 2 %.
  Future<void> openForm() async {
    await tap(find.text('Create'));
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    await tap(inForm(find.text('Buy')));
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tap(inForm(find.byTooltip('Add custom payment method')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Revolut');
    await tester.pump();
    await tap(find.text('Add payment method'));
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
  }

  /// The order of the book tapped, « Take Order », the robot's read shown: « Continue » ready.
  Future<void> prepareTake() async {
    await waitFor(find.byType(OfferRow));
    await tap(find.byType(OfferRow).first);
    await settle(tester);
    await waitFor(find.text('Take Order'));
    await tap(find.text('Take Order'));
    await waitFor(find.text('Continue'));
    await settle(tester);
  }
}

void main() {
  group('an internal Garage Key: no « Store your garage key »', () {
    testWidgets(
      'the make leaves at « Create order », once even when it is tapped twice',
      (tester) async {
        final app = await _App.start(tester, _Key.internal);
        await app.openForm();
        expect(app.makes, 0);

        final create = app.inForm(find.text('Create order'));
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.pump(const Duration(milliseconds: 16));
        if (create.evaluate().isNotEmpty) {
          await tester.tap(create, warnIfMissed: false);
        }
        for (var i = 0; i < 4; i++) {
          expect(app.dialog, findsNothing);
          await settle(tester);
        }

        expect(app.dialog, findsNothing);
        expect(app.makes, 1);
        expect(app.gate.asked, 0);
        expect(app.clipboard.text, isNull);
        expect(tester.takeException(), isNull);
        await app.close();
      },
    );

    testWidgets(
      'the take leaves at « Continue », once even when it is tapped twice',
      (tester) async {
        final app = await _App.start(tester, _Key.internal, take: true);
        await app.prepareTake();
        expect(app.takes, 0);

        final next = find.text('Continue');
        await tester.ensureVisible(next);
        await tester.pump();
        await tester.tap(next);
        await tester.pump(const Duration(milliseconds: 16));
        if (next.evaluate().isNotEmpty) {
          await tester.tap(next, warnIfMissed: false);
        }
        for (var i = 0; i < 4; i++) {
          expect(app.dialog, findsNothing);
          await settle(tester);
        }

        expect(app.dialog, findsNothing);
        expect(app.takes, 1);
        expect(app.gate.asked, 0);
        expect(tester.takeException(), isNull);
        await app.close();
      },
    );
  });

  group('the external Garage Key: « Store your garage key » with « Back it up! »', () {
    testWidgets(
      'before a make: masked, « Go back » sends nothing, a copy whose re-authentication is left copies nothing, a copy passed puts the key on the clipboard and says « Copied! », « Done » sends once',
      (tester) async {
        final app = await _App.start(tester, _Key.external);
        await app.openForm();

        // « Go back »: nothing sent, the form as it was.
        await app.tap(app.inForm(find.text('Create order')));
        await settle(tester);
        expect(app.dialog, findsOneWidget);
        expect(
          app.inDialog(find.text('Store your garage key')),
          findsOneWidget,
        );
        expect(app.inDialog(find.text('Back it up!')), findsOneWidget);
        // The field holds a fixed row of dots, never the key, nor its length.
        expect(app.inDialog(find.text('••••••••••••••••')), findsOneWidget);
        expect(app.drawn().contains('robo1'), isFalse);
        expect(app.drawn().contains(tradeKey.revealBech32()), isFalse);
        await app.tap(app.inDialog(find.text('Go back')));
        await settle(tester);
        expect(app.dialog, findsNothing);
        expect(app.makes, 0);

        // The copy, its re-authentication left: nothing on the clipboard, no « Copied! ».
        await app.tap(app.inForm(find.text('Create order')));
        await settle(tester);
        expect(app.dialog, findsOneWidget);
        await app.copy(pass: false);
        expect(app.gate.asked, 1);
        expect(app.dialog, findsOneWidget);
        expect(app.clipboard.text, isNull);
        expect(app.inDialog(find.text('Copied!')), findsNothing);
        expect(app.makes, 0);

        // The copy passed: the key on the clipboard, « Copied! », the key still drawn nowhere.
        await app.copy(pass: true);
        expect(app.gate.asked, 2);
        expect(app.clipboard.text == tradeKey.revealBech32(), isTrue);
        expect(app.drawn().contains(tradeKey.revealBech32()), isFalse);
        expect(app.drawn().contains('robo1'), isFalse);
        expect(app.inDialog(find.text('Copied!')), findsOneWidget);
        expect(app.makes, 0);
        // The cubit's state never holds it.
        final form = tester.element(find.byType(CreateOrderScreen));
        expect(
          '${BlocProvider.of<MakeOrderCubit>(form).state}'.contains('robo1'),
          isFalse,
        );

        // « Done »: the make, once.
        await app.tap(app.inDialog(find.text('Done')));
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        expect(app.dialog, findsNothing);
        expect(app.makes, 1);

        // The Garage's clearing: 30 seconds later the clipboard no longer holds the key.
        await tester.pump(GarageKeyClipboard.clearAfter);
        await settle(tester);
        expect(app.clipboard.text, '');
        expect(tester.takeException(), isNull);
        await app.close();
      },
    );

    testWidgets(
      'the dialog gone while the re-authentication is asked, then the re-authentication passed: nothing copied, nothing sent (security review of #320, R1)',
      (tester) async {
        final app = await _App.start(tester, _Key.external);
        await app.openForm();
        await app.tap(app.inForm(find.text('Create order')));
        await settle(tester);
        expect(app.dialog, findsOneWidget);
        await app.tap(app.copyButton);
        await settle(tester);
        expect(find.text('test PIN ok'), findsOneWidget);

        // The dialog's route taken away under the re-authentication.
        final dialog = tester.element(
          find.byType(StoreTokenDialog, skipOffstage: false),
        );
        switch (ModalRoute.of(dialog)) {
          case final route?:
            Navigator.of(dialog).removeRoute(route);
          case null:
            fail('the dialog has no route');
        }
        await settle(tester);
        expect(
          find.byType(StoreTokenDialog, skipOffstage: false),
          findsNothing,
        );

        await app.tap(find.text('test PIN ok'));
        await settle(tester);
        await settle(tester);
        expect(app.gate.asked, 1);
        expect(app.clipboard.text, isNull);
        expect(app.makes, 0);
        expect(tester.takeException(), isNull);
        await app.close();
      },
    );

    testWidgets(
      'before a take: the copy passed puts the key of the take\'s robot on the clipboard; « Go back » sends nothing; « Done » sends once',
      (tester) async {
        final app = await _App.start(tester, _Key.external, take: true);
        await app.prepareTake();

        await app.tap(find.text('Continue'));
        await settle(tester);
        expect(app.dialog, findsOneWidget);
        expect(app.inDialog(find.text('••••••••••••••••')), findsOneWidget);
        await app.copy(pass: false);
        expect(app.clipboard.text, isNull);
        await app.copy(pass: true);
        expect(app.clipboard.text == tradeKey.revealBech32(), isTrue);
        expect(app.drawn().contains('robo1'), isFalse);
        expect(app.inDialog(find.text('Copied!')), findsOneWidget);

        await app.tap(app.inDialog(find.text('Go back')));
        await settle(tester);
        expect(app.dialog, findsNothing);
        expect(app.takes, 0);

        await app.tap(find.text('Continue'));
        await settle(tester);
        await app.tap(app.inDialog(find.text('Done')));
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        expect(app.takes, 1);
        expect(tester.takeException(), isNull);
        await app.close();
      },
    );

    testWidgets(
      'nothing printed or logged while the key of a make is read and copied holds the key',
      (tester) async {
        final app = await _App.start(tester, _Key.external);
        final output = await tester.runAsync(
          () => captureKeyOutput(() async {
            final keys = app.locator<TradeGarageKeyUsecase>();
            expect(await keys.makeUsesExternalKey(_net), isTrue);
            final key = await keys.externalKeyOfMake(_net);
            expect(key, isNotNull);
            if (key == null) return;
            expect(
              await GarageKeyView.copy(
                app.locator<GarageKeyClipboard>(),
                key.key,
              ),
              isTrue,
            );
            // What the values print: never the key.
            Zone.current.print('$key ${key.key}');
          }),
        );
        expect(app.clipboard.text == tradeKey.revealBech32(), isTrue);
        expect(output, isNotNull);
        expect(output?.contains(tradeKey.revealBech32()), isFalse);
        expect(output?.contains('robo1'), isFalse);
        await app.close();
      },
    );
  });
}
