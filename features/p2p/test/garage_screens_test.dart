import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/list_robot_hosts_usecase.dart';
import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_standing_usecase.dart';
import 'package:p2p/src/domain/usecases/release_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/retry_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/start_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'package:p2p/src/presentation/book_cubit.dart';
import 'package:p2p/src/presentation/coordinator_details_cubit.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/src/presentation/robot_coordinator_cubit.dart';
import 'package:p2p/src/ui/coordinator_details_dialog.dart';
import 'package:p2p/src/ui/garage/garage_view.dart';
import 'package:p2p/src/ui/garage/robot_nickname.dart';
import 'package:p2p/src/ui/garage/robot_coordinator_panel.dart';
import 'package:p2p/src/ui/garage/robot_history_dialog.dart';
import 'package:p2p/src/ui/garage/select_host_sheet.dart';
import 'package:p2p/src/ui/garage/send_robot_dialog.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/unlisted_order_screen.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:p2p/src/ui/widgets/garage_key_field.dart';
import 'package:p2p/src/ui/widgets/garage_key_view.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/order_search_miss_dialog.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart' show Failure;
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'migrations_test/p2p_database/generated/schema_v9.dart' as v9;
import 'support/book_attempts.dart';
import 'support/fakes.dart';
import 'support/garage_words.dart';
import 'support/harness.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';
import 'support/robot_coordinators.dart';

/// The `no_screenshot` plugin behind `PrivacyScreen` answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

const _mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
const _testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';

/// The network the tab reads, which a test can change while the tab is shown.
/// A keystore whose writes take two seconds, as a slow device's could: long enough to leave the Garage while a key is stored.
final class _SlowWrites extends FakeSecureStoragePlatform {
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await super.write(key: key, value: value, options: options);
  }
}

final class _NetworkCubit extends Cubit<RobosatsNetwork> {
  _NetworkCubit(super.network);

  void switchTo(RobosatsNetwork network) => emit(network);
}

/// The Garage of the P2P tab, on the real vault over its in-memory keystore, the real screens and the real cubit; Tor, the coordinators, the clipboard, the capture protection and the re-authentication are fakes.
void main() {
  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fixedKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final fixedNickname = switch (fixedKey.deriveIdentity(0)) {
    Ok(:final value) => value.nickname,
    Err(:final failure) => throw StateError('$failure'),
  };

  // The example key of the RoboSats frontend tests, the only real key the tests type, as `packages/robosats` records it.
  final vector =
      (jsonDecode(
                File(
                  '../../packages/robosats/test/fixtures/robot-identity-vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['garage_key']
          as Map<String, dynamic>;
  final exampleText = vector['garage_key'] as String;
  final exampleNickname =
      ((vector['derived'] as List).first as Map<String, dynamic>)['nickname']
          as String;

  late GetIt locator;
  late StreamController<P2pTorState> tor;
  late FakeSecureStoragePlatform storage;
  late Map<String, String> storedFixedKeys;
  late _NetworkCubit network;
  late FakeTransport transport;

  /// What the fake plugin answers when the Garage asks for capture protection: `true`, `false`, or a future the test completes.
  late Future<bool> Function() protection;
  late List<String> privacyCalls;

  /// The text on the fake clipboard, every text written to it, how many times it was read, and whether it refuses writes or reads.
  String? clipboard;
  late List<String?> clipboardWrites;
  late int clipboardReads;
  late bool clipboardWriteFails;
  late bool clipboardUnreadable;

  /// What the fake re-authentication was asked, and how it ends.
  late int reauthentications;

  Widget reauthenticate(VoidCallback onAuthenticated) {
    reauthentications++;
    return Scaffold(
      body: Builder(
        builder: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: onAuthenticated, child: const Text('PIN ok')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('PIN back'),
            ),
            // A gate that calls back twice, and one that calls back while a dialog of its own covers it.
            TextButton(
              onPressed: () {
                onAuthenticated();
                onAuthenticated();
              },
              child: const Text('PIN twice'),
            ),
            TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const Dialog(child: Text('over the PIN')),
                );
                onAuthenticated();
              },
              child: const Text('PIN under a dialog'),
            ),
          ],
        ),
      ),
    );
  }

  setUpAll(() async {
    final setup = FakeSecureStoragePlatform()..install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    for (final slot in GarageKeySlot.values) {
      expect(
        await vault.import(slot: slot, bytes: fixedKey.revealBytes()),
        isA<Ok<Object?, Failure>>(),
      );
    }
    storedFixedKeys = Map.of(setup.entries);
  });

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = StreamController<P2pTorState>.broadcast();
    network = _NetworkCubit(RobosatsNetwork.testnet);
    storage = FakeSecureStoragePlatform();
    protection = () async => true;
    privacyCalls = [];
    clipboard = null;
    clipboardWrites = [];
    clipboardReads = 0;
    clipboardWriteFails = false;
    clipboardUnreadable = false;
    reauthentications = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_privacyChannel, (call) async {
      privacyCalls.add(call.method);
      return call.method == 'screenshotOff' ? protection() : true;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          if (clipboardWriteFails) throw PlatformException(code: 'clipboard');
          clipboard = (call.arguments as Map)['text'] as String?;
          clipboardWrites.add(clipboard);
        case 'Clipboard.getData':
          clipboardReads++;
          return clipboardUnreadable ? null : {'text': clipboard};
      }
      return null;
    });
    // Android lists the activities that take selected text (Translate and the like): a field with a selection would offer them.
    messenger.setMockMethodCallHandler(SystemChannels.processText, (
      call,
    ) async {
      if (call.method == 'ProcessText.queryTextActions') {
        return <String, String>{'translate': 'Translate'};
      }
      return null;
    });
  });

  tearDown(() async {
    await tor.close();
    await network.close();
    await locator.reset();
  });

  /// The keystore holds the fixed key in [entries], or what [entries] maps them to.
  void keystoreHolding(
    Map<String, String?> entries, {
    bool locked = false,
    List<Object?>? scripted,
    List<Object?>? scriptedWrites,
  }) => storage = FakeSecureStoragePlatform(
    entries: {
      for (final MapEntry(:key, :value) in entries.entries)
        key: value ?? storedFixedKeys[key] ?? '',
    },
    locked: locked,
    writesFail: locked,
    scripted: scripted,
    scriptedWrites: scriptedWrites,
  );

  /// Shows the P2P tab, the Garage registered over the keystore of the test unless [withGarage] is false.
  Future<void> openTab(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool withGarage = true,
    bool withReauthentication = true,
    bool databaseUnavailable = false,
    Map<String, List<Map<String, Object?>>>? books,
    Set<String>? held,
    Map<String, CoordinatorTransportFailure>? failures,
    P2pGarageKeyPort? words,
    QueryExecutor Function()? databaseOpener,
  }) async {
    usePhoneScreen(tester);
    storage.install();
    transport = FakeTransport(
      network: network.state,
      books: books,
      held: held,
      failures: failures,
    );
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: withGarage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
      derivedGarageKeys: withGarage ? words : null,
      databaseUnavailable: databaseUnavailable,
      databaseOpener: databaseOpener,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [
        const P2pFeature().route(
          locator,
          network: (context) => context.select((_NetworkCubit c) => c.state),
          reauthenticate: withReauthentication ? reauthenticate : null,
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: network,
        child: routerHarness(router, locale: locale),
      ),
    );
    await settle(tester);
  }

  /// Lets the vault settle: an empty slot is believed only after its full read budget, about 4.5 s.
  Future<void> letTheVaultSettle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
  }

  /// Taps « Delete All » of the profile, [label] in the language shown, scrolled to first: the robot panel makes the profile taller than the screen.
  Future<void> tapDeleteAll(
    WidgetTester tester, {
    String label = 'Delete All',
    bool warnIfMissed = true,
  }) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label), warnIfMissed: warnIfMissed);
  }

  /// Lets a page that was pushed or popped finish its transition.
  Future<void> afterRoute(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  }

  Future<void> openGarage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    P2pGarageKeyPort? words,
    QueryExecutor Function()? databaseOpener,
  }) async {
    await openTab(
      tester,
      locale: locale,
      words: words,
      databaseOpener: databaseOpener,
    );
    await tester.tap(find.text('Garage'));
    await settle(tester);
    await letTheVaultSettle(tester);
  }

  /// Every label, value, hint and tooltip of the semantics tree.
  List<String> semanticsTexts(WidgetTester tester) {
    var root = tester.getSemantics(find.byType(GarageView));
    for (var parent = root.parent; parent != null; parent = parent.parent) {
      root = parent;
    }
    final texts = <String>[];
    void visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      texts.addAll([data.label, data.value, data.hint, data.tooltip]);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    return texts;
  }

  /// The key is drawn by `GarageKeyView` alone, and nothing of the semantics tree holds a key.
  void expectKeyOnlyInView(WidgetTester tester) {
    final outside = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('robo1') &&
          !_isInside<GarageKeyView>(tester, widget),
    );
    expect(outside, findsNothing);
    // A boolean, so that a failure does not print the key it found.
    expect(
      semanticsTexts(tester).any((text) => text.contains('robo1')),
      isFalse,
    );
  }

  String shownKey(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byType(GarageKeyView),
          matching: find.byType(Text),
        ),
      )
      .data
      .toString();

  testWidgets('with the P2P gate closed, nothing of the Garage is built', (
    tester,
  ) async {
    keystoreHolding({_testnetEntry: null});
    storage.install();
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(network: network.state),
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      // The shell's redirect, for a user who is not a superuser in developer mode.
      redirect: (context, state) => P2pFeature.redirect(
        state.uri.path,
        isSuperuser: false,
        isDevModeEnabled: true,
        gateClosedRedirectPath: '/wallet',
      ),
      routes: [
        GoRoute(path: '/wallet', builder: (_, _) => const Text('wallet')),
        const P2pFeature().route(
          locator,
          network: (_) => network.state,
          reauthenticate: reauthenticate,
        ),
      ],
    );
    await tester.pumpWidget(routerHarness(router));
    await letTheVaultSettle(tester);
    router.go('${P2pFeature.path}/order');
    await letTheVaultSettle(tester);

    expect(find.text('wallet'), findsOneWidget);
    expect(find.byType(GarageView), findsNothing);
    expect(storage.reads, 0);
    expect(privacyCalls, isEmpty);
  });

  group('the Garage entry', () {
    testWidgets('is disabled, and reads nothing, without the vault handle', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openTab(tester, withGarage: false);

      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      expect(find.byType(GarageView), findsNothing);
      expect(storage.reads, 0);
      expect(privacyCalls, isEmpty);
    });

    testWidgets('reads the vault only once the Garage is opened', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openTab(tester);

      expect(find.text('Offers'), findsOneWidget);
      expect(storage.reads, 0);
      expect(privacyCalls, isEmpty);

      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      expect(storage.readKeys.toSet(), {_testnetEntry});
      expect(privacyCalls, contains('screenshotOff'));
    });

    testWidgets('draws nothing until the capture protection is on', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      final answer = Completer<bool>();
      protection = () => answer.future;
      await openTab(tester);
      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      expect(find.byType(GarageView), findsOneWidget);
      expect(find.text(fixedNickname), findsNothing);
      expect(find.text('Show Garage Key'), findsNothing);

      answer.complete(true);
      await settle(tester);

      expect(find.text(fixedNickname), findsOneWidget);
    });

    testWidgets('releases the protection when the Garage is left', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);

      await tester.tap(find.text('Offers'));
      await settle(tester);

      expect(find.byType(GarageView), findsNothing);
      expect(privacyCalls.last, 'screenshotOn');
    });
  });

  group('« Search order », for an order the book does not hold', () {
    final missDialog = find.byType(OrderSearchMissDialog);
    final wait = find.descendant(
      of: missDialog,
      matching: find.byType(CircularProgressIndicator),
    );

    /// Opens the book, Tor ready, and searches an order of temple that it does not hold, with the labels of [locale]; leaves the wait of the answer on screen.
    Future<void> searchMissingOrder(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      String search = 'Search',
      Map<String, List<Map<String, Object?>>>? books,
      Set<String>? held,
      Map<String, CoordinatorTransportFailure>? failures,
    }) async {
      await openTab(
        tester,
        locale: locale,
        books: books,
        held: held,
        failures: failures,
      );
      tor.add(P2pTorState.ready);
      await settle(tester);
      await tester.tap(find.text(search));
      await settle(tester);
      final searchDialog = find.byType(SearchOrderDialog);
      await tester.enterText(
        find.descendant(of: searchDialog, matching: find.byType(TextField)),
        'http://${hostOf('temple', network.state)}/order/temple/1/',
      );
      await tester.tap(
        find.descendant(of: searchDialog, matching: find.text(search)),
      );
      await settle(tester);
    }

    testWidgets(
      'a Garage Key stored: the order\'s page opens for its robot to read it (#245), where the official client reads it with its robot; this key of unknown history gives no robot, and nothing is sent',
      (tester) async {
        network.switchTo(RobosatsNetwork.mainnet);
        keystoreHolding({_mainnetEntry: null});
        await searchMissingOrder(tester);
        final requests = List.of(transport.requested);

        // The dialog closed with no answer of its own: the order's page, its host and number, and why its robot cannot read it.
        expect(missDialog, findsNothing);
        expect(find.byType(NoRobotDialog), findsNothing);
        expect(find.byType(UnlistedOrderScreen), findsOneWidget);
        expect(find.text('# 1'), findsOneWidget);
        expect(
          find.text(
            'The robots of a pasted Garage Key cannot take orders here. Generate a new Garage Key in the Garage.',
          ),
          findsOneWidget,
        );
        // Asked whether the key of the network of the book is stored: no robot reserved, nothing sent, the keystore unchanged.
        expect(storage.entries, {
          _mainnetEntry: storedFixedKeys[_mainnetEntry],
        });
        expect(transport.requested, requests);
        expect(find.byType(GarageView), findsNothing);
      },
    );

    testWidgets('a Garage Key stored, in French', (tester) async {
      keystoreHolding({_testnetEntry: null});
      await searchMissingOrder(
        tester,
        locale: const Locale('fr'),
        search: 'Rechercher',
      );

      expect(find.byType(UnlistedOrderScreen), findsOneWidget);
      expect(
        find.text(
          'Les robots d’une clé de garage collée ne peuvent pas prendre d’ordre ici. Générez une nouvelle clé de garage dans le Garage.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vous n\'avez pas de clé de garage'), findsNothing);
    });

    // A failure is not an absence: « You do not have a Garage Key » would invite to make a key over one that may well be there.
    for (final (name, held, locked, scripted) in [
      ('the keystore locked', {_testnetEntry: null}, true, null),
      ('a damaged entry', {_testnetEntry: 'not json at all'}, false, null),
      (
        'an entry the keystore keeps failing to read',
        {_testnetEntry: null},
        false,
        List<Object?>.generate(5, (_) => PlatformException(code: 'read')),
      ),
    ]) {
      testWidgets(
        'a Garage Key that cannot be read, $name: « This order is not available »',
        (tester) async {
          keystoreHolding(held, locked: locked, scripted: scripted);
          final stored = Map.of(storage.entries);
          await searchMissingOrder(tester);
          final requests = List.of(transport.requested);
          await letTheVaultSettle(tester);

          expect(wait, findsNothing);
          expect(find.text('This order is not available'), findsOneWidget);
          expect(find.text('Acknowledged'), findsOneWidget);
          expect(find.byType(NoRobotDialog), findsNothing);
          expect(find.text('You do not have a Garage Key'), findsNothing);
          expect(storage.readKeys.toSet(), {_testnetEntry});
          expect(storage.entries, stored);
          expect(transport.requested, requests);
        },
      );
    }

    testWidgets(
      'the wait is as tall as « This order is not available », which comes without a jump, and is announced',
      (tester) async {
        // An entry the keystore keeps failing to read: about 4.5 s of retries, then « This order is not available ».
        keystoreHolding(
          {_testnetEntry: null},
          scripted: List<Object?>.generate(
            5,
            (_) => PlatformException(code: 'read'),
          ),
        );
        await searchMissingOrder(tester);
        final card = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first;
        expect(wait, findsOneWidget);
        final waiting = tester.getSize(card);

        await letTheVaultSettle(tester);

        expect(wait, findsNothing);
        expect(find.text('This order is not available'), findsOneWidget);
        expect(tester.getSize(card), waiting);
        // Far from the height of the screen, 844 points.
        expect(waiting.height, lessThan(300));
        expect(
          tester
              .widgetList<Semantics>(
                find.ancestor(
                  of: find.text('This order is not available'),
                  matching: find.byType(Semantics),
                ),
              )
              .any((semantics) => semantics.properties.liveRegion ?? false),
          isTrue,
        );
      },
    );

    testWidgets(
      'the invisible copy that sizes the wait is not read, not tapped and not focused',
      (tester) async {
        final semantics = tester.ensureSemantics();
        keystoreHolding(
          {_testnetEntry: null},
          scripted: List<Object?>.generate(
            5,
            (_) => PlatformException(code: 'read'),
          ),
        );
        await searchMissingOrder(tester);
        expect(wait, findsOneWidget);

        // A screen reader reads neither the message nor its button while the answer may be another.
        expect(find.bySemanticsLabel('Acknowledged'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('not available')), findsNothing);

        // A tap where the invisible button lies does not close the dialog.
        await tester.tapAt(tester.getCenter(find.text('Acknowledged')));
        await settle(tester);
        expect(missDialog, findsOneWidget);

        // Nor does the keyboard reach it.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await settle(tester);
        var hiddenFocused = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          final widget = element.widget;
          if (widget is Visibility && !widget.visible) hiddenFocused = true;
          return !hiddenFocused;
        });
        expect(hiddenFocused, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(missDialog, findsOneWidget);
        expect(wait, findsOneWidget);

        await letTheVaultSettle(tester);
        expect(find.bySemanticsLabel('Acknowledged'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('an order the book holds opens without reading the vault', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await searchMissingOrder(
        tester,
        books: {
          'temple': [bookOrder(id: 1, makerSeed: 1)],
        },
      );

      expect(missDialog, findsNothing);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(storage.reads, 0);
    });

    testWidgets(
      'the book of the order\'s coordinator still awaited: the wait, then the order it brings, without reading the vault',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await searchMissingOrder(
          tester,
          books: {
            'temple': [bookOrder(id: 1, makerSeed: 1)],
          },
          held: {'temple'},
        );

        expect(wait, findsOneWidget);
        await letTheVaultSettle(tester);
        expect(wait, findsOneWidget);
        expect(storage.reads, 0);

        transport.release('temple');
        await settle(tester);
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);

        expect(missDialog, findsNothing);
        expect(find.byType(OrderDetailsScreen), findsOneWidget);
        expect(storage.reads, 0);
      },
    );

    for (final (locale, search, offline, acknowledged) in [
      (const Locale('en'), 'Search', 'Coordinator offline', 'Acknowledged'),
      (const Locale('fr'), 'Rechercher', 'Coordinateur hors ligne', 'Compris'),
    ]) {
      testWidgets(
        'the book of the order\'s coordinator could not be had: « $offline », not the order\'s unavailability',
        (tester) async {
          keystoreHolding({_testnetEntry: null});
          await searchMissingOrder(
            tester,
            locale: locale,
            search: search,
            failures: {'temple': const CoordinatorTransportFailed()},
          );

          expect(
            find.descendant(of: missDialog, matching: find.text(offline)),
            findsOneWidget,
          );
          expect(find.text(acknowledged), findsOneWidget);
          expect(find.byType(NoRobotDialog), findsNothing);
          expect(storage.reads, 0);

          await tester.tap(find.text(acknowledged));
          await settle(tester);
          expect(missDialog, findsNothing);
        },
      );
    }

    testWidgets(
      'closed during the wait: the answer that comes later changes nothing',
      (tester) async {
        keystoreHolding({});
        await searchMissingOrder(tester);
        expect(wait, findsOneWidget);

        await tester.tapAt(const Offset(4, 4));
        await settle(tester);
        expect(missDialog, findsNothing);
        await letTheVaultSettle(tester);

        expect(missDialog, findsNothing);
        expect(find.byType(NoRobotDialog), findsNothing);
        expect(find.byType(GarageView), findsNothing);
        expect(storage.entries, isEmpty);
      },
    );
  });

  group('the copied key', () {});

  group('the profile', () {
    testWidgets('hides the key until the re-authentication passes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);

      expect(find.text(fixedNickname), findsOneWidget);
      expect(find.text('Robot #0'), findsOneWidget);
      expect(find.text('Garage Key'), findsWidgets);
      expect(find.byType(GarageKeyView), findsNothing);
      expectKeyOnlyInView(tester);

      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);
      expect(reauthentications, isPositive);
      await tester.tap(find.text('PIN back'));
      await afterRoute(tester);
      expect(find.byType(GarageKeyView), findsNothing);

      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);
      await tester.tap(find.text('PIN ok'));
      await afterRoute(tester);

      expect(find.byType(GarageKeyView), findsOneWidget);
      expect(shownKey(tester) == fixedKey.revealBech32(), isTrue);
      expectKeyOnlyInView(tester);
      semantics.dispose();
    });

    testWidgets('a system back from the re-authentication shows nothing', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);

      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await afterRoute(tester);

      expect(find.byType(GarageKeyView), findsNothing);
      expect(find.text('Show Garage Key'), findsOneWidget);
    });

    testWidgets('without the re-authentication of the shell, never shows it', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openTab(tester, withReauthentication: false);
      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);

      expect(reauthentications, 0);
      expect(find.byType(GarageKeyView), findsNothing);
    });

    for (final (locale, texts) in [
      (
        const Locale('en'),
        [
          'Delete Garage Key?',
          'Are you sure you want to permanently delete this Garage Key and ALL associated robots?',
          '⚠️ This action cannot be undone!',
          'Before deleting, make sure you have:',
          '•  Stored your Garage Key safely',
          '•  No active or pending orders in ANY robot',
          '•  Exported any important data',
          'Delete Garage Key',
          'Cancel',
        ],
      ),
      (
        const Locale('fr'),
        [
          'Supprimer la clé de garage ?',
          'Êtes-vous sûr de vouloir supprimer définitivement cette clé de garage et TOUS les robots associés ?',
          '⚠️ Cette action ne peut pas être annulée !',
          "Avant de supprimer, assurez-vous d'avoir :",
          '•  Conservé votre clé de garage en lieu sûr',
          '•  Aucun ordre actif ou en attente, sur TOUS vos robots',
          '•  Exporté toutes les données importantes',
          'Supprimer la clé de garage',
          'Annuler',
        ],
      ),
    ]) {}
  });

  group('a change of network', () {});

  /// The paste field of step 1 and its editable text.
  Finder pasteInput() => find.descendant(
    of: find.byType(GarageKeyField),
    matching: find.byType(EditableText),
  );

  Future<void> openWizard(
    WidgetTester tester, {
    Map<String, String?>? held,
    bool slowWrites = false,
  }) async {
    if (slowWrites) {
      storage = _SlowWrites();
    } else {
      keystoreHolding(held ?? {});
    }
    await openGarage(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
  }

  group('the re-authentication', () {
    testWidgets('the key is not built under the gate before it answers', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);

      await tester.tap(find.text('Show Garage Key'));
      await tester.pump();
      expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      await afterRoute(tester);
      expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      await tester.tap(find.text('PIN back'));
      await afterRoute(tester);
      expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
    });

    testWidgets('a gate that calls back twice reveals once, and pops once', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);

      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);
      await tester.tap(find.text('PIN twice'));
      await afterRoute(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(GarageView), findsOneWidget);
      expect(find.byType(GarageKeyView), findsOneWidget);
      expect(find.text('PIN ok'), findsNothing);
    });

    testWidgets(
      'a gate covered by its own dialog when it calls back pops nothing',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openGarage(tester);

        await tester.tap(find.text('Show Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN under a dialog'));
        await afterRoute(tester);

        // The callback came while its route was not on top: ignored, and the gate is still there.
        expect(find.text('over the PIN'), findsOneWidget);
        expect(find.text('PIN ok', skipOffstage: false), findsOneWidget);
        expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'a revealed key is hidden when the app goes to the background',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openGarage(tester);
        await tester.tap(find.text('Show Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);

        for (final state in [
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
        await settle(tester);

        expect(find.byType(GarageKeyView), findsNothing);
        expect(find.text('Show Garage Key'), findsOneWidget);
      },
    );
  });

  /// The app goes to the background and comes back.
  Future<void> backgroundAndBack(WidgetTester tester) async {
    for (final state in [
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
    await settle(tester);
  }

  /// The app goes to the background, and stays there.
  Future<void> toBackground(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  /// The app comes back from the background.
  Future<void> backToForeground(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await settle(tester);
  }

  Finder backupAlert() =>
      find.textContaining('Store it somewhere safe!', findRichText: true);

  /// Records the fixed key as drawn here on [network] and binds its robot [index] to temple there, in the database of the tab: what a screen that sends a robot will write.
  Future<void> bindFixedRobot({
    RobosatsNetwork network = RobosatsNetwork.testnet,
    int index = 0,
  }) async {
    final bindings = locator<RobotBindingRepository>();
    final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    final temple = switch (CoordinatorIdentity.of(
      coordinator('temple'),
      network,
    )) {
      final identity? => identity,
      null => throw StateError('no temple'),
    };
    expect(
      await bindings.recordGeneratedKey(network, fingerprint),
      isA<Ok<void, P2pFailure>>(),
    );
    expect(
      await bindings.bind(RobotSlot(network, fingerprint, index), temple),
      isA<Ok<void, P2pFailure>>(),
    );
  }

  /// Opens the Garage of the testnet slot, which holds the fixed key, once [prepare] wrote what it needs in the database of the tab.
  Future<void> openGarageAfter(
    WidgetTester tester,
    Future<void> Function() prepare, {
    Locale locale = const Locale('en'),
    bool withReauthentication = true,
    Map<String, String?>? held,
  }) async {
    keystoreHolding(held ?? {_testnetEntry: null});
    await openTab(
      tester,
      locale: locale,
      withReauthentication: withReauthentication,
    );
    await prepare();
    await tester.tap(find.text('Garage'));
    await settle(tester);
    await letTheVaultSettle(tester);
  }

  /// The « Delete All » button of the profile.
  TextButton deleteAllButton(WidgetTester tester) => tester.widget<TextButton>(
    find.ancestor(
      of: find.text('Delete All'),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    ),
  );

  group('the robot panel, in the Garage', () {
    bool robotRequestsMade() =>
        transport.requested.any((path) => path.contains('/api/robot'));

    testWidgets(
      'shows under the navigator; a key from elsewhere asks « Robots from elsewhere » first, under the capture protection',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openGarage(tester);

        expect(find.text('Coordinator that knows your robot:'), findsOneWidget);
        expect(
          find.text('No coordinator knows this robot yet.'),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(find.text('No coordinator knows this robot yet.'))
              .dy,
          greaterThan(tester.getTopLeft(find.text('Robot #0')).dy),
        );
        expect(_selectHost(tester).disabled, isTrue);
        expect(find.text('Connecting to Tor network'), findsOneWidget);
        await tester.tap(find.text('Select Host'), warnIfMissed: false);
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsNothing);

        tor.add(P2pTorState.ready);
        await settle(tester);

        // A key stored with no record of its draw: its history is unknown, and « Select Host » asks first.
        expect(_selectHost(tester).disabled, isFalse);
        expect(find.text('Connecting to Tor network'), findsNothing);
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsOneWidget);
        expect(find.text('Robots from elsewhere'), findsOneWidget);
        expect(find.byType(SelectHostSheet), findsNothing);
        // A modal route above the Garage, which stays built under it: the protection asked when the Garage opened holds, and nothing turned it off.
        expect(find.byType(GarageView), findsOneWidget);
        expect(privacyCalls, contains('screenshotOff'));
        expect(privacyCalls, isNot(contains('screenshotOn')));

        await tester.tap(find.text('Cancel'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsNothing);
        expect(find.byType(SelectHostSheet), findsNothing);
        expect(privacyCalls, isNot(contains('screenshotOn')));
        expect(robotRequestsMade(), isFalse);
      },
    );

    // Security review of step 6: what the panel opened closes with it when the Garage changes under it, and nothing is recorded or sent.
    for (final opened in [
      '« Robots from elsewhere »',
      '« Select Host »',
      'the confirmation',
    ]) {
      for (final change in [
        'the network',
        'the next robot',
        'the key deleted',
      ]) {}
    }

    // Second security pass on #77: the coordinator dialog that an info button of « Select Host » opens sits above the sheet; the sheet's own route goes, not the one on top, and the dialog goes too.
    for (final change in ['the network', 'the next robot']) {
      testWidgets(
        '$change while the coordinator dialog of « Select Host » is open: the dialog and the sheet close, and nothing is sent',
        (tester) async {
          keystoreHolding({_testnetEntry: null, _mainnetEntry: null});
          await openGarage(tester);
          tor.add(P2pTorState.ready);
          await letTheVaultSettle(tester);
          await tester.ensureVisible(find.text('Select Host'));
          await settle(tester);
          await tester.tap(find.text('Select Host'));
          await afterRoute(tester);
          await tester.ensureVisible(find.text('I understand'));
          await settle(tester);
          await tester.tap(find.text('I understand'));
          await afterRoute(tester);
          await tester.tap(find.byTooltip('Details of Temple of Sats'));
          await afterRoute(tester);
          expect(find.byType(CoordinatorDetailsDialog), findsOneWidget);
          expect(find.byType(SelectHostSheet), findsOneWidget);

          final garage = tester
              .element(find.byType(GarageView))
              .read<GarageCubit>();
          switch (change) {
            case 'the network':
              network.switchTo(RobosatsNetwork.mainnet);
            default:
              garage.next();
          }
          await settle(tester);
          await letTheVaultSettle(tester);

          expect(find.byType(CoordinatorDetailsDialog), findsNothing);
          expect(find.byType(SelectHostSheet), findsNothing);
          expect(find.byType(GarageView), findsOneWidget);
          expect(robotRequestsMade(), isFalse);
        },
      );
    }

    testWidgets('moving to another robot gives it a panel of its own', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);
      final first = tester
          .element(find.byType(RobotCoordinatorPanel))
          .read<RobotCoordinatorCubit>();

      await tester.tap(find.byTooltip('Next account'));
      await settle(tester);

      final second = tester
          .element(find.byType(RobotCoordinatorPanel))
          .read<RobotCoordinatorCubit>();
      expect(identical(first, second), isFalse);
      expect(first.isClosed, isTrue);
      expect(second.isClosed, isFalse);
    });
  });

  group('the robot panel', () {
    final temple = coordinator('temple');
    late Map<RobotHashId, RobotPgpKey> pairs;
    late RobotPgpKey otherPair;
    late FakeRobotCoordinators robotCoordinators;
    late RecordingBindings bindings;
    late RobotRequestLimiter limiter;
    late FakeTor robotTor;
    late PairsByRobot keys;

    /// The timers of the book of the tab under the panel, which the test fires.
    late FakeWaits bookWaits;

    NetworkRobot robotAt(
      int index, [
      RobosatsNetwork net = RobosatsNetwork.testnet,
    ]) => switch (NetworkGarageKey(net, fixedKey).firstUsableRobot(index)) {
      Ok(:final value) when value.accountIndex == index => value,
      _ => throw StateError('no robot $index'),
    };

    setUpAll(() {
      pairs = {
        for (var i = 0; i < 2; i++)
          robotAt(i).identity.hashId: pairOf(robotAt(i).identity),
      };
      // A second pair of robot 1, as another device would make it.
      otherPair = pairOf(robotAt(1).identity);
    });

    setUp(() {
      robotCoordinators = FakeRobotCoordinators([
        for (var i = 0; i < 4; i++) robotAt(i).identity,
      ]);
      final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
        Ok(:final value) => value,
        Err() => throw StateError('no fingerprint'),
      };
      bindings = RecordingBindings(
        drawnHere: [
          for (final net in RobosatsNetwork.values) (net, fingerprint),
        ],
      );
      // Every wait of the limiter ends at once.
      limiter = RobotRequestLimiter(
        elapsed: () => Duration.zero,
        delay: (_) => Future<void>.value(),
        random: () => 0.5,
      );
      robotTor = FakeTor();
      keys = PairsByRobot(pairs);
    });

    /// Binds robot [index] to [alias] and has that coordinator keep it, as after a first contact in an earlier run.
    Future<void> boundTo(int index, String alias) async {
      final robot = robotAt(index);
      final identity = CoordinatorIdentity.of(
        coordinator(alias),
        robot.network,
      );
      if (identity == null) fail('no instance');
      await bindings.bind(robot.slot, identity);
      final pair = pairs[robot.identity.hashId];
      if (pair != null) {
        robotCoordinators.keepFor(robot.identity, alias, robot.network, pair);
      }
    }

    /// Lets the book of the tab ask again, after its waits, the coordinators it could not reach, until they are shown offline.
    Future<void> settleBook(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        bookWaits.fireAll();
        await settle(tester);
      }
    }

    /// The panel of robot [index] of the fixed key on [network], [width] points wide at [textScale], in [locale], with Tor ready unless [torReady] is false; the book of the tab could not reach the coordinators of [offline], and shows them offline once its attempts are over, unless [bookSettled] is false.
    Future<RobotCoordinatorCubit> showPanel(
      WidgetTester tester, {
      int index = 0,
      RobosatsNetwork network = RobosatsNetwork.testnet,
      Locale locale = const Locale('en'),
      double width = 390,
      double textScale = 1,
      bool torReady = true,
      Set<String> offline = const {},
      bool bookSettled = true,
      Set<(String, int)> lastOrdersShown = const {},
      Set<(String, int)> ordersNotServed = const {},
    }) async {
      // A panel shown before is gone first, with its cubit.
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view
        ..physicalSize = Size(width * 3, 844 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final fetch = FetchRobotUsecase(
        CoordinatorClient(robotCoordinators, clock: () => testNow),
        bindings,
        keys,
      );
      final cubit = RobotCoordinatorCubit(
        NetworkGarageKey(network, fixedKey),
        index,
        ReadRobotStandingUsecase(bindings),
        PutRobotOnCoordinatorUsecase(fetch, bindings, limiter),
        ReadRobotOnCoordinatorUsecase(
          fetch,
          bindings,
          limiter,
          Federation.robosats,
        ),
        ReleaseRobotUsecase(
          limiter,
          CloseRobotSessionsUsecase(RecordingSessions()),
        ),
        WatchP2pTorStateUsecase(() => robotTor),
        ListRobotHostsUsecase(Federation.robosats, limiter),
        AcknowledgeGarageKeyHistoryUsecase(bindings),
      );
      final bookTransport = FakeTransport(
        network: network,
        failures: {
          for (final alias in offline) alias: const CoordinatorUnreachable(),
        },
      );
      bookWaits = FakeWaits();
      final book = BookCubit(
        network,
        WatchP2pTorStateUsecase(() => robotTor),
        StartP2pTorUsecase(() => robotTor),
        RetryP2pTorUsecase(() => robotTor),
        LoadFederationBooksUsecase(
          RequestFederationBooksUsecase(
            FederationBookReader(bookTransport, clock: () => testNow),
            Federation.robosats,
          ),
          BookRequestsInFlight(),
          bookWaits.waits,
        ),
      )..start();
      addTearDown(book.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          locale: locale,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: book),
                BlocProvider(create: (_) => cubit..load()),
              ],
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RobotCoordinatorPanel(
                  nickname: robotAt(index, network).identity.nickname,
                  network: network,
                  lastOrdersShown: lastOrdersShown,
                  ordersNotServed: ordersNotServed,
                  coordinatorDetails: (request) => CoordinatorDetailsCubit(
                    request,
                    FetchCoordinatorInfoUsecase(
                      CoordinatorClient(bookTransport, clock: () => testNow),
                    ),
                    now: testNow,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      if (torReady) {
        robotTor.embedded.ready();
        await settle(tester);
        if (bookSettled) await settleBook(tester);
      }
      return cubit;
    }

    /// Puts the robot shown on Temple of Sats through Select Host and the confirmation.
    Future<void> sendToTemple(WidgetTester tester) async {
      await tester.tap(find.text(_text(tester).p2pRobotSelectHost));
      await afterRoute(tester);
      await tester.tap(find.text('Temple of Sats'));
      await afterRoute(tester);
      await tester.tap(find.text(_text(tester).p2pCommonContinue));
      await afterRoute(tester);
    }

    testWidgets(
      'Select Host says « Coordinator offline » only of a coordinator the book shows offline, not of one it still awaits',
      (tester) async {
        await showPanel(
          tester,
          network: RobosatsNetwork.mainnet,
          offline: {'gumpellite', 'lake'},
          bookSettled: false,
        );
        Future<void> openHosts() async {
          await tester.tap(find.text('Select Host'));
          await afterRoute(tester);
        }

        Future<void> closeHosts() async {
          await tester.tapAt(const Offset(4, 4));
          await afterRoute(tester);
        }

        // Asked again by the book: awaited, and not said offline.
        await openHosts();
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect(find.text('Coordinator offline'), findsNothing);
        await closeHosts();

        // Lake still has no answer 80 seconds after it was asked: the book shows it offline while its attempts go on, and so does the sheet.
        bookWaits.fireAwaitedBounds();
        await settle(tester);
        await openHosts();
        expect(find.text('Coordinator offline'), findsNWidgets(2));
        await closeHosts();

        // The last attempts fail: still offline.
        await settleBook(tester);
        await openHosts();
        expect(find.text('Coordinator offline'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Select Host: the hosts of the network in order, offline or closed, and their dialog',
      (tester) async {
        // Three first contacts LibreBazaar refused with a nickname taken, in this run.
        for (var i = 0; i < RobotRequestLimiter.maxNicknameRefusals; i++) {
          limiter
              .holdFirstContactSlot(
                RobosatsNetwork.mainnet,
                coordinator('bazaar'),
              )
              ?.end(refused: true);
        }
        final semantics = tester.ensureSemantics();
        await showPanel(
          tester,
          network: RobosatsNetwork.mainnet,
          offline: {'gumpellite'},
        );
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);

        final names = [
          for (final coordinator in Federation.robosats.on(
            RobosatsNetwork.mainnet,
          ))
            coordinator.longAlias,
        ];
        final tops = [
          for (final name in names) tester.getTopLeft(find.text(name)).dy,
        ];
        expect(tops, [...tops]..sort());
        expect(find.text('Coordinator offline'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Coordinator offline')).dy,
          greaterThan(tester.getTopLeft(find.text('Gumpellite')).dy),
        );
        expect(
          find.text('This coordinator refused too many robots.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ListTile>(
                find.ancestor(
                  of: find.text('LibreBazaar'),
                  matching: find.byType(ListTile),
                ),
              )
              .enabled,
          isFalse,
        );
        // A closed coordinator is not chosen.
        await tester.tap(find.text('LibreBazaar'), warnIfMissed: false);
        await afterRoute(tester);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect(find.byType(SendRobotDialog), findsNothing);

        expect(find.byTooltip('Details of Temple of Sats'), findsOneWidget);
        await tester.tap(find.byTooltip('Details of Temple of Sats'));
        await afterRoute(tester);
        expect(find.byType(CoordinatorDetailsDialog), findsOneWidget);
        expect(robotCoordinators.requests, isEmpty);
        semantics.dispose();
      },
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'a first contact sent, then the records unreadable: never « Nothing was sent. », in ${locale.languageCode}',
        (tester) async {
          robotCoordinators.script.add(RobotReply.notJson);
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          robotCoordinators.onSend = (_) {
            bindings.readFailure = const P2pStorageFailure();
          };
          await tester.tap(find.text(l10n.p2pRobotSelectHost));
          await afterRoute(tester);
          await tester.tap(find.text('Temple of Sats'));
          await afterRoute(tester);
          await tester.tap(find.text(l10n.p2pCommonContinue));
          await afterRoute(tester);
          await settle(tester);

          expect(robotCoordinators.firstContacts, hasLength(1));
          expect(
            find.text(l10n.p2pRobotBadAnswer('Temple of Sats')),
            findsOneWidget,
          );
          expect(find.text(l10n.p2pRobotRecordsUnreadable), findsOneWidget);
          expect(find.text(l10n.p2pRobotStorage), findsNothing);
          expect(find.text(l10n.p2pCommonRetry), findsOneWidget);

          // Once the records can be read: the failure, under the coordinator it went to.
          bindings.readFailure = null;
          await tester.tap(find.text(l10n.p2pCommonRetry));
          await settle(tester);
          expect(find.text('Temple of Sats'), findsOneWidget);
          expect(
            find.text(l10n.p2pRobotBadAnswer('Temple of Sats')),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'the coordinator chosen, not the first: the confirmation names it, and the first contact goes to it',
      (tester) async {
        await showPanel(tester);
        final l10n = _text(tester);
        final nickname = robotAt(0).identity.nickname;
        await tester.tap(find.text(l10n.p2pRobotSelectHost));
        await afterRoute(tester);
        // TheBigLake, the second coordinator of testnet.
        await tester.tap(find.text('TheBigLake'));
        await afterRoute(tester);
        expect(
          find.text(l10n.p2pRobotSendTitle(nickname, 'TheBigLake')),
          findsOneWidget,
        );
        expect(find.text(l10n.p2pRobotSendBody('TheBigLake')), findsOneWidget);
        expect(find.textContaining('Temple of Sats'), findsNothing);

        await tester.tap(find.text(l10n.p2pCommonContinue));
        await afterRoute(tester);
        await settle(tester);

        expect(robotCoordinators.firstContacts, hasLength(1));
        expect(
          robotCoordinators.firstContacts.single.url.host,
          FakeRobotCoordinators.hostOf('lake', RobosatsNetwork.testnet),
        );
        expect(
          robotCoordinators.firstContacts.single.robot,
          robotAt(0).identity.sessionKey,
        );
        expect(find.text('TheBigLake'), findsOneWidget);
        expect(find.text(l10n.p2pRobotNoOrders), findsOneWidget);
      },
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'Continue makes the first contact: building, still waiting, then the card, in ${locale.languageCode}',
        (tester) async {
          robotCoordinators.hold = Completer<void>();
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          final nickname = robotAt(0).identity.nickname;
          await tester.tap(find.text(l10n.p2pRobotSelectHost));
          await afterRoute(tester);
          await tester.tap(find.text('Temple of Sats'));
          await afterRoute(tester);
          expect(
            find.text(l10n.p2pRobotSendTitle(nickname, 'Temple of Sats')),
            findsOneWidget,
          );
          expect(
            find.text(l10n.p2pRobotSendBody('Temple of Sats')),
            findsOneWidget,
          );
          expect(find.text(l10n.p2pRobotSendOtherApp), findsOneWidget);
          expect(robotCoordinators.requests, isEmpty);

          await tester.tap(find.text(l10n.p2pCommonContinue));
          await afterRoute(tester);

          expect(find.text(l10n.p2pGarageBuildingRobot), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(robotCoordinators.firstContacts, hasLength(1));
          expect(
            find.text(l10n.p2pRobotStillWaiting('Temple of Sats')),
            findsNothing,
          );
          await tester.pump(const Duration(seconds: 27));
          expect(
            find.text(l10n.p2pRobotStillWaiting('Temple of Sats')),
            findsNothing,
          );
          await tester.pump(const Duration(seconds: 3));
          expect(
            find.text(l10n.p2pRobotStillWaiting('Temple of Sats')),
            findsOneWidget,
          );

          robotCoordinators.hold?.complete();
          robotCoordinators.hold = null;
          await settle(tester);

          expect(find.text('Temple of Sats'), findsOneWidget);
          expect(find.text(l10n.p2pRobotNoOrders), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.text(l10n.p2pRobotSelectHost), findsNothing);
          expect(
            find.text(l10n.p2pRobotAlreadyExisted('Temple of Sats')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'the card of a robot with orders and rewards, in ${locale.languageCode}',
        (tester) async {
          await boundTo(0, 'temple');
          robotCoordinators.fields[robotAt(0).identity.sessionKey] = {
            'last_order_id': 4321,
            'earned_rewards': 3500,
            'nostr_pubkey': robotAt(0).identity
                .nostrKeyPair(NostrKeyDerivation.repositoryFixtures)
                .publicKeyHex,
          };
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);

          // A last order no « Last order #N » line of the Garage opens (here, none: no record of it on this device), said by the panel as the coordinator says it (functional review of #220, R4, and its verification); one a line opens is not said again (`reopen_order_route_test.dart`).
          expect(find.text(l10n.p2pRobotLastOrder('4321')), findsOneWidget);
          expect(find.text(l10n.p2pRobotNoOrders), findsNothing);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsOneWidget);
          expect(find.text(l10n.p2pRobotRewards), findsOneWidget);
          expect(
            find.text(
              l10n.p2pAmountSats(
                NumberFormat.decimalPattern(locale.languageCode).format(3500),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text(l10n.p2pRobotNostrOld('Temple of Sats')),
            findsOneWidget,
          );
          expect(robotCoordinators.firstContacts, isEmpty);

          // The same order opened by a « Last order #N » line of the Garage: not said again by the panel (functional review of #220, R4).
          await showPanel(
            tester,
            locale: locale,
            lastOrdersShown: {('temple', 4321)},
          );
          expect(find.text(l10n.p2pRobotLastOrder('4321')), findsNothing);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsOneWidget);

          // The same order held here finished with an end that has not served (an expiry, a take that never started, #251): the sentence is not said; an order of another coordinator, or another order, keeps it.
          await showPanel(
            tester,
            locale: locale,
            lastOrdersShown: {('temple', 4321)},
            ordersNotServed: {('temple', 4321)},
          );
          expect(find.text(l10n.p2pRobotUsedInTrade), findsNothing);
          for (final other in [('lake', 4321), ('temple', 4320)]) {
            await showPanel(tester, locale: locale, ordersNotServed: {other});
            expect(
              find.text(l10n.p2pRobotUsedInTrade),
              findsOneWidget,
              reason: '$other',
            );
          }
        },
      );

      testWidgets(
        'an active order, no trade info, a Nostr key it cannot use, in ${locale.languageCode}',
        (tester) async {
          await boundTo(0, 'temple');
          robotCoordinators.fields[robotAt(0).identity.sessionKey] = {
            'active_order_id': 77,
            'last_order_id': 76,
            'nostr_pubkey': '0' * 64,
          };
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);

          expect(find.text(l10n.p2pRobotActiveOrder('77')), findsOneWidget);
          expect(find.text(l10n.p2pRobotLastOrder('76')), findsNothing);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsNothing);
          expect(find.text(l10n.p2pRobotRewards), findsNothing);
          expect(
            find.text(l10n.p2pRobotNostrUnknown('Temple of Sats')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a robot that already existed there, in ${locale.languageCode}',
        (tester) async {
          robotCoordinators.keepFor(
            robotAt(1).identity,
            'temple',
            RobosatsNetwork.testnet,
            pairOf(robotAt(1).identity),
          );
          await showPanel(tester, index: 1, locale: locale);
          await sendToTemple(tester);
          await settle(tester);
          expect(
            find.text(_text(tester).p2pRobotAlreadyExisted('Temple of Sats')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a first contact at Retry answered with another pair: « already existed », in ${locale.languageCode}',
        (tester) async {
          await boundTo(1, 'temple');
          robotCoordinators.kept.clear();
          await showPanel(tester, index: 1, locale: locale);
          final l10n = _text(tester);
          expect(
            find.text(l10n.p2pRobotNotCreated('Temple of Sats')),
            findsOneWidget,
          );
          // Another device creates the robot there with its own pair, just before this first contact arrives.
          final other = otherPair;
          robotCoordinators.onSend = (request) {
            if (robotCoordinators.firstContacts.contains(request)) {
              robotCoordinators.keepFor(
                robotAt(1).identity,
                'temple',
                RobosatsNetwork.testnet,
                other,
              );
            }
          };

          await tester.tap(find.text(l10n.p2pCommonRetry));
          await settle(tester);

          expect(robotCoordinators.firstContacts, hasLength(1));
          expect(
            find.text(l10n.p2pRobotAlreadyExisted('Temple of Sats')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a robot found again at Retry: no « already existed », in ${locale.languageCode}',
        (tester) async {
          await boundTo(0, 'temple');
          final kept = Map.of(robotCoordinators.kept);
          robotCoordinators.kept.clear();
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          expect(
            find.text(l10n.p2pRobotNotCreated('Temple of Sats')),
            findsOneWidget,
          );
          // The coordinator knows it again: the put reads it back first and finds it.
          robotCoordinators.kept.addAll(kept);

          await tester.tap(find.text(l10n.p2pCommonRetry));
          await settle(tester);

          expect(find.text(l10n.p2pRobotNoOrders), findsOneWidget);
          expect(
            find.text(l10n.p2pRobotAlreadyExisted('Temple of Sats')),
            findsNothing,
          );
          expect(robotCoordinators.firstContacts, isEmpty);
        },
      );

      // Each failure of the design note of #29, § 2.3: its text and its way out.
      for (final (name, replies, firstContact, text, retry)
          in <
            (
              String,
              List<RobotReply>,
              bool,
              String Function(P2pLocalizations),
              bool,
            )
          >[
            (
              'offline',
              [RobotReply.unreachable],
              false,
              (l) => l.p2pCoordinatorOffline,
              true,
            ),
            (
              'busy',
              List.filled(RobotRequestLimiter.maxAttempts, RobotReply.busy),
              false,
              (l) => l.p2pRobotBusy,
              true,
            ),
            (
              'unknown there',
              [RobotReply.unknown],
              false,
              (l) => l.p2pRobotNotCreated('Temple of Sats'),
              true,
            ),
            (
              'an unreadable answer',
              [RobotReply.notJson],
              false,
              (l) => l.p2pRobotBadAnswer('Temple of Sats'),
              true,
            ),
            (
              'another robot',
              [RobotReply.otherRobot],
              false,
              (l) => l.p2pRobotMismatch('Temple of Sats'),
              false,
            ),
            (
              'a nickname taken',
              [RobotReply.nicknameTaken],
              true,
              (l) => l.p2pRobotNicknameTaken('Temple of Sats'),
              false,
            ),
            (
              'a key too recent',
              [RobotReply.keyTooRecent],
              true,
              (l) => l.p2pRobotKeyTooRecent('Temple of Sats'),
              true,
            ),
            (
              'keys refused',
              [RobotReply.keysRefused],
              true,
              (l) => l.p2pRobotRefused('Temple of Sats'),
              false,
            ),
          ]) {
        testWidgets(
          '$name: its text, ${retry ? 'with' : 'without'} Retry, in ${locale.languageCode}',
          (tester) async {
            if (!firstContact) await boundTo(0, 'temple');
            robotCoordinators.script.addAll(replies);
            await showPanel(tester, locale: locale);
            if (firstContact) await sendToTemple(tester);
            await settle(tester);
            final l10n = _text(tester);

            expect(find.text(text(l10n)), findsOneWidget);
            expect(
              find.text(l10n.p2pCommonRetry),
              retry ? findsOneWidget : findsNothing,
            );
            if (retry) {
              final before = robotCoordinators.requests.length;
              await tester.tap(find.text(l10n.p2pCommonRetry));
              await settle(tester);
              expect(robotCoordinators.requests.length, greaterThan(before));
            }
          },
        );
      }

      testWidgets(
        'Tor failed while a bound robot waits, in ${locale.languageCode}',
        (tester) async {
          await boundTo(0, 'temple');
          await showPanel(tester, locale: locale, torReady: false);
          final l10n = _text(tester);
          expect(find.text(l10n.p2pTorConnecting), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          robotTor.embedded.failed();
          await settle(tester);
          expect(find.text(l10n.p2pTorConnectionError), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          robotTor.embedded.ready();
          await settle(tester);
          expect(find.text(l10n.p2pRobotNoOrders), findsOneWidget);
        },
      );

      testWidgets(
        'a database that cannot be read, and its Retry, in ${locale.languageCode}',
        (tester) async {
          bindings.readFailure = const P2pStorageFailure();
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          expect(find.text(l10n.p2pRobotStorage), findsOneWidget);
          bindings.readFailure = null;
          await tester.tap(find.text(l10n.p2pCommonRetry));
          await settle(tester);
          expect(find.text(l10n.p2pRobotNoCoordinator), findsOneWidget);
        },
      );

      testWidgets(
        'a coordinator changed, and a robot of the other network, in ${locale.languageCode}',
        (tester) async {
          final identity = CoordinatorIdentity.of(
            temple,
            RobosatsNetwork.testnet,
          );
          if (identity == null) fail('no instance');
          await bindings.bind(
            robotAt(0).slot,
            CoordinatorIdentity(
              network: RobosatsNetwork.testnet,
              alias: 'temple',
              onion: identity.onion,
              nodeKeys: identity.nodeKeys,
              nostrKey: '00${identity.nostrKey.substring(2)}',
            ),
          );
          final mainnetTemple = CoordinatorIdentity.of(
            temple,
            RobosatsNetwork.mainnet,
          );
          if (mainnetTemple == null) fail('no instance');
          await bindings.bind(
            robotAt(1, RobosatsNetwork.mainnet).slot,
            mainnetTemple,
          );

          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          expect(
            find.text(l10n.p2pRobotCoordinatorChanged('Temple of Sats')),
            findsOneWidget,
          );
          expect(find.text(l10n.p2pCommonRetry), findsNothing);

          await showPanel(tester, index: 1, locale: locale);
          expect(
            find.text(l10n.p2pRobotOnOtherNetwork('mainnet')),
            findsOneWidget,
          );
          expect(robotCoordinators.requests, isEmpty);
        },
      );

      for (final textScale in [1.0, 2.0, 3.0]) {
        testWidgets(
          'nothing overflows at 320 points and text size $textScale, in ${locale.languageCode}',
          (tester) async {
            // Robot 0 has everything a card shows; robot 1 has none yet, with Tor connecting.
            await boundTo(0, 'temple');
            robotCoordinators.fields[robotAt(0).identity.sessionKey] = {
              'last_order_id': 4321,
              'earned_rewards': 3500,
              'nostr_pubkey': '0' * 64,
            };
            await showPanel(
              tester,
              locale: locale,
              width: 320,
              textScale: textScale,
            );
            expect(tester.takeException(), isNull);
            expect(find.text(_text(tester).p2pRobotRewards), findsOneWidget);

            await showPanel(
              tester,
              index: 1,
              locale: locale,
              width: 320,
              textScale: textScale,
              torReady: false,
              network: RobosatsNetwork.mainnet,
              offline: {'gumpellite'},
            );
            expect(tester.takeException(), isNull);
            robotTor.embedded.ready();
            await settle(tester);
            await settleBook(tester);
            final selectHost = find.text(_text(tester).p2pRobotSelectHost);
            await tester.ensureVisible(selectHost);
            await settle(tester);
            await tester.tap(selectHost);
            await afterRoute(tester);
            expect(tester.takeException(), isNull);
            // The last coordinator of the sheet, scrolled to, and back to the first.
            final hosts = find.descendant(
              of: find.byType(SelectHostSheet),
              matching: find.byType(Scrollable),
            );
            await tester.scrollUntilVisible(
              find.text('Gumpellite'),
              100,
              scrollable: hosts,
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text('Temple of Sats'),
              -100,
              scrollable: hosts,
            );
            await settle(tester);
            await tester.tap(find.text('Temple of Sats'));
            await afterRoute(tester);
            expect(tester.takeException(), isNull);
            expect(find.byType(SendRobotDialog), findsOneWidget);
            final cancel = find.text(_text(tester).p2pCommonCancel);
            await tester.ensureVisible(cancel);
            await settle(tester);
            expect(tester.takeException(), isNull);
            await tester.tap(cancel);
            await afterRoute(tester);
            expect(find.byType(SendRobotDialog), findsNothing);
          },
        );
      }
    }

    // #29, step 6: « Select Host » of a robot of a key of unknown history asks « Robots from elsewhere » first, once per key and network; only « I understand » records it.
    group('a key pasted, or whose draw could not be recorded', () {
      setUp(() => bindings = RecordingBindings());

      int acknowledgements() =>
          bindings.calls.where((c) => c.$1 == 'recordAcknowledgedKey').length;

      Future<void> openSelectHost(WidgetTester tester) async {
        final selectHost = find.text(_text(tester).p2pRobotSelectHost);
        await tester.ensureVisible(selectHost);
        await settle(tester);
        await tester.tap(selectHost);
        await afterRoute(tester);
      }

      /// Taps [label] in the dialog, scrolled to first: the body is long, and in French the buttons are under the fold of a phone.
      Future<void> tapInDialog(WidgetTester tester, String label) async {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await settle(tester);
        await tester.tap(button);
        await afterRoute(tester);
      }

      for (final (locale, title, body, confirm) in const [
        (
          Locale('en'),
          'Robots from elsewhere',
          'This Garage Key was pasted in, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Bull Market, a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, generate a new Garage Key.',
          'I understand',
        ),
        (
          Locale('fr'),
          'Robots venus d’ailleurs',
          'Cette clé de garage a été collée, ou cet appareil n’a pas pu enregistrer qu’il l’a générée. Ses robots existent peut-être déjà chez des coordinateurs\u00a0: l’application officielle RoboSats envoie chaque robot qu’elle affiche à tous les coordinateurs. Dans Bull Market, un robot ne vit que chez un seul coordinateur\u00a0: si vous avez déjà utilisé cette clé, placez chaque robot chez le coordinateur où vous l’avez utilisé. Pour repartir de zéro, générez une nouvelle clé de garage.',
          'Je comprends',
        ),
      ]) {
        final language = locale.languageCode;

        testWidgets('« Select Host » asks it first, in $language', (
          tester,
        ) async {
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          expect(find.text(l10n.p2pRobotNoCoordinator), findsOneWidget);
          expect(_selectHost(tester).disabled, isFalse);

          await openSelectHost(tester);

          expect(find.byType(RobotHistoryDialog), findsOneWidget);
          expect(find.text(title), findsOneWidget);
          expect(find.text(body), findsOneWidget);
          expect(find.text(confirm), findsOneWidget);
          expect(find.text(l10n.p2pCommonCancel), findsOneWidget);
          expect(find.byType(SelectHostSheet), findsNothing);
          expect(acknowledgements(), 0);
          expect(robotCoordinators.requests, isEmpty);
        });

        testWidgets(
          '« Cancel », a back and a tap outside record nothing and open nothing, in $language',
          (tester) async {
            await showPanel(tester, locale: locale);
            final l10n = _text(tester);
            Future<void> open() async {
              await openSelectHost(tester);
              expect(find.byType(RobotHistoryDialog), findsOneWidget);
            }

            await open();
            await tapInDialog(tester, l10n.p2pCommonCancel);
            await open();
            // The system back.
            await tester.binding.handlePopRoute();
            await afterRoute(tester);
            await open();
            await tester.tapAt(const Offset(4, 4));
            await afterRoute(tester);

            expect(find.byType(RobotHistoryDialog), findsNothing);
            expect(find.byType(SelectHostSheet), findsNothing);
            expect(find.byType(RobotCoordinatorPanel), findsOneWidget);
            expect(acknowledgements(), 0);
            expect(robotCoordinators.requests, isEmpty);
            // Nothing was recorded: it is asked again.
            await open();
          },
        );

        testWidgets(
          '« I understand »: recorded once, then the sheet, and the robot is bound as acknowledged, in $language',
          (tester) async {
            await showPanel(tester, locale: locale);
            final l10n = _text(tester);
            await openSelectHost(tester);

            await tapInDialog(tester, confirm);

            expect(acknowledgements(), 1);
            expect(find.byType(RobotHistoryDialog), findsNothing);
            expect(find.byType(SelectHostSheet), findsOneWidget);
            expect(robotCoordinators.requests, isEmpty);

            await tester.tap(find.text('Temple of Sats'));
            await afterRoute(tester);
            await tester.tap(find.text(l10n.p2pCommonContinue));
            await afterRoute(tester);
            await settle(tester);

            expect(robotCoordinators.firstContacts, hasLength(1));
            expect(find.text(l10n.p2pRobotNoOrders), findsOneWidget);
            expect(switch (await bindings.standingOf(robotAt(0).slot)) {
              Ok(:final value) => value.binding?.provenance,
              Err() => null,
            }, BindingProvenance.acknowledged);
          },
        );

        testWidgets(
          'a record that fails: the storage text, no sheet, nothing sent, and asked again, in $language',
          (tester) async {
            await showPanel(tester, locale: locale);
            final l10n = _text(tester);
            bindings
              ..failure = const P2pStorageFailure()
              ..failures = 1;
            await openSelectHost(tester);
            await tapInDialog(tester, confirm);

            expect(find.text(l10n.p2pRobotStorage), findsOneWidget);
            expect(find.byType(RobotHistoryDialog), findsNothing);
            expect(find.byType(SelectHostSheet), findsNothing);
            expect(robotCoordinators.requests, isEmpty);
            expect(bindings.calls.where((c) => c.$1 == 'bind'), isEmpty);

            await openSelectHost(tester);
            expect(find.byType(RobotHistoryDialog), findsOneWidget);
            await tapInDialog(tester, confirm);
            expect(find.byType(SelectHostSheet), findsOneWidget);
            expect(acknowledgements(), 2);
            await tester.tap(
              find.byTooltip(
                MaterialLocalizations.of(
                  tester.element(find.byType(SelectHostSheet)),
                ).closeButtonTooltip,
              ),
            );
            await afterRoute(tester);
            expect(find.text(l10n.p2pRobotStorage), findsNothing);
          },
        );

        for (final textScale in [1.0, 2.0, 3.0]) {
          testWidgets(
            'it fits at 320 points and text size $textScale, its failure too, in $language',
            (tester) async {
              await showPanel(
                tester,
                locale: locale,
                width: 320,
                textScale: textScale,
              );
              final l10n = _text(tester);
              await openSelectHost(tester);
              expect(tester.takeException(), isNull);
              expect(find.byType(RobotHistoryDialog), findsOneWidget);
              // The body scrolls inside the dialog: both buttons can be reached.
              final cancel = find.text(l10n.p2pCommonCancel);
              await tester.ensureVisible(cancel);
              await settle(tester);
              expect(tester.takeException(), isNull);
              await tester.tap(cancel);
              await afterRoute(tester);
              expect(find.byType(RobotHistoryDialog), findsNothing);

              bindings.failure = const P2pStorageFailure();
              await openSelectHost(tester);
              final understood = find.text(confirm);
              await tester.ensureVisible(understood);
              await settle(tester);
              await tester.tap(understood);
              await afterRoute(tester);
              expect(tester.takeException(), isNull);
              expect(find.text(l10n.p2pRobotStorage), findsOneWidget);
            },
          );
        }
      }

      // A double tap as a finger makes it, 16, 50 or 120 ms apart, or within one frame (security review of step 6).
      for (final gap in [0, 16, 50, 120]) {
        testWidgets(
          '« I understand » tapped twice, $gap ms apart: recorded once, nothing sent',
          (tester) async {
            await showPanel(tester);
            await openSelectHost(tester);
            final button = find.text('I understand');
            await tester.ensureVisible(button);
            await settle(tester);
            final at = tester.getCenter(button);

            await tester.tapAt(at);
            if (gap > 0) await tester.pump(Duration(milliseconds: gap));
            await tester.tapAt(at);
            await afterRoute(tester);

            expect(acknowledgements(), 1);
            expect(find.byType(RobotHistoryDialog), findsNothing);
            expect(find.byType(RobotCoordinatorPanel), findsOneWidget);
            expect(robotCoordinators.requests, isEmpty);
            // The tail of the double tap may land on the barrier of the sheet that just opened, and close it, as any tap outside it does: it never reaches the Garage under it. « Select Host » then goes straight to the sheet.
            expect(
              find.byType(SelectHostSheet).evaluate().length,
              lessThanOrEqualTo(1),
            );
            if (find.byType(SelectHostSheet).evaluate().isEmpty) {
              await openSelectHost(tester);
              expect(find.byType(RobotHistoryDialog), findsNothing);
              expect(find.byType(SelectHostSheet), findsOneWidget);
            }
            expect(acknowledgements(), 1);
          },
        );

        testWidgets(
          '« Select Host » tapped twice, $gap ms apart: one dialog, nothing recorded',
          (tester) async {
            await showPanel(tester);
            final selectHost = find.text('Select Host');
            await tester.ensureVisible(selectHost);
            await settle(tester);
            final at = tester.getCenter(selectHost);

            await tester.tapAt(at);
            if (gap > 0) await tester.pump(Duration(milliseconds: gap));
            await tester.tapAt(at);
            await afterRoute(tester);

            expect(find.byType(RobotHistoryDialog), findsOneWidget);
            expect(acknowledgements(), 0);
            expect(robotCoordinators.requests, isEmpty);
          },
        );
      }

      // Tor stays ready for the panel once it has been (`TorWait`, as for the book): « I understand » cannot meet a Tor that is not ready; asked before, it records nothing and the panel says that Tor connects (security review of step 6).
      testWidgets(
        'before Tor is ready, an acknowledgement records nothing and the panel says Tor connects',
        (tester) async {
          final cubit = await showPanel(tester, torReady: false);
          final l10n = _text(tester);
          expect(find.text(l10n.p2pTorConnecting), findsOneWidget);

          await cubit.acknowledge();
          await settle(tester);

          expect(acknowledgements(), 0);
          expect(find.text(l10n.p2pTorConnecting), findsOneWidget);
          expect(_selectHost(tester).disabled, isTrue);
        },
      );

      testWidgets(
        'Tor failing while the dialog is open does not stop « I understand »',
        (tester) async {
          await showPanel(tester);
          await openSelectHost(tester);
          robotTor.embedded.failed();
          await settle(tester);

          await tapInDialog(tester, 'I understand');

          expect(acknowledgements(), 1);
          expect(find.byType(SelectHostSheet), findsOneWidget);
        },
      );

      testWidgets(
        'once per key and network: the next robot goes straight to the sheet, the other network asks',
        (tester) async {
          await showPanel(tester);
          await openSelectHost(tester);
          await tapInDialog(tester, 'I understand');
          expect(find.byType(SelectHostSheet), findsOneWidget);

          await showPanel(tester, index: 1);
          await openSelectHost(tester);
          expect(find.byType(RobotHistoryDialog), findsNothing);
          expect(find.byType(SelectHostSheet), findsOneWidget);

          // The same key in the mainnet slot has a history of its own there.
          await showPanel(tester, network: RobosatsNetwork.mainnet);
          await openSelectHost(tester);
          expect(find.byType(RobotHistoryDialog), findsOneWidget);
          expect(acknowledgements(), 1);
          expect(robotCoordinators.requests, isEmpty);
        },
      );

      testWidgets('a key drawn here asks nothing', (tester) async {
        final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
          Ok(:final value) => value,
          Err() => throw StateError('no fingerprint'),
        };
        bindings = RecordingBindings(
          drawnHere: [(RobosatsNetwork.testnet, fingerprint)],
        );
        await showPanel(tester);
        await openSelectHost(tester);

        expect(find.byType(RobotHistoryDialog), findsNothing);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect(acknowledgements(), 0);
      });

      testWidgets(
        'Tor not ready: « Select Host » disabled, and nothing asked',
        (tester) async {
          await showPanel(tester, torReady: false);
          expect(_selectHost(tester).disabled, isTrue);
          await tester.tap(find.text('Select Host'), warnIfMissed: false);
          await afterRoute(tester);
          expect(find.byType(RobotHistoryDialog), findsNothing);

          robotTor.embedded.failed();
          await settle(tester);
          expect(_selectHost(tester).disabled, isTrue);
          await tester.tap(find.text('Select Host'), warnIfMissed: false);
          await afterRoute(tester);
          expect(find.byType(RobotHistoryDialog), findsNothing);
          expect(acknowledgements(), 0);
        },
      );

      testWidgets(
        'a screen reader hears its title as a header, and its buttons',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await showPanel(tester);
          await openSelectHost(tester);

          expect(
            tester.getSemantics(find.text('Robots from elsewhere')),
            isSemantics(isHeader: true, label: 'Robots from elsewhere'),
          );
          expect(find.bySemanticsLabel(RegExp('I understand')), findsWidgets);
          expect(find.bySemanticsLabel(RegExp('Cancel')), findsWidgets);
          semantics.dispose();
        },
      );
    });

    // The notes of the second security pass on step 5: a text never says that nothing was sent when a request of the call may have left.
    for (final locale in const [Locale('en'), Locale('fr')]) {
      final language = locale.languageCode;
      final nothingSent = language == 'fr'
          ? 'Rien n’a été envoyé.'
          : 'Nothing was sent.';

      testWidgets(
        'a first contact answered, whose proof could not run, then the records unreadable: never « Nothing was sent. », in $language',
        (tester) async {
          // Robot 1 already lives on Temple of Sats with a pair made elsewhere: the answer must be proven, and the proof cannot run.
          robotCoordinators.keepFor(
            robotAt(1).identity,
            'temple',
            RobosatsNetwork.testnet,
            otherPair,
          );
          keys.proveFailure = const RobotKeyComputeFailure();
          await showPanel(tester, index: 1, locale: locale);
          final l10n = _text(tester);
          robotCoordinators.onSend = (_) {
            bindings.readFailure = const P2pStorageFailure();
          };
          await sendToTemple(tester);
          await settle(tester);

          expect(robotCoordinators.firstContacts, hasLength(1));
          expect(keys.proved, [robotAt(1).identity.hashId]);
          expect(find.text(l10n.p2pRobotKeyComputeFailed), findsOneWidget);
          expect(find.text(l10n.p2pRobotRecordsUnreadable), findsOneWidget);
          expect(find.textContaining(nothingSent), findsNothing);
          expect(find.text(l10n.p2pCommonRetry), findsOneWidget);
        },
      );

      testWidgets(
        'a put on a bound robot whose read back left, then refused by the database: never « Nothing was sent. », in $language',
        (tester) async {
          await boundTo(0, 'temple');
          robotCoordinators.kept.clear();
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          expect(
            find.text(l10n.p2pRobotNotCreated('Temple of Sats')),
            findsOneWidget,
          );
          // The binding of the first contact, after the put's own read back, cannot be written.
          robotCoordinators.onSend = (_) {
            bindings.failure = const P2pStorageFailure();
          };

          await tester.tap(find.text(l10n.p2pCommonRetry));
          await settle(tester);

          expect(robotCoordinators.requests, hasLength(2));
          expect(robotCoordinators.firstContacts, isEmpty);
          expect(find.text(l10n.p2pRobotRecordsUnreadable), findsOneWidget);
          expect(find.textContaining(nothingSent), findsNothing);
          // « Retry » reads it back.
          expect(find.text(l10n.p2pCommonRetry), findsOneWidget);
        },
      );

      testWidgets(
        'a nickname taken, its read 10 s later refused by the database, the records unreadable: never « Nothing was sent. », in $language',
        (tester) async {
          robotCoordinators.script.add(RobotReply.nicknameTaken);
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);
          robotCoordinators.onSend = (_) {
            bindings
              ..failure = const P2pStorageFailure()
              ..readFailure = const P2pStorageFailure();
          };
          await sendToTemple(tester);
          await settle(tester);

          expect(robotCoordinators.firstContacts, hasLength(1));
          expect(find.text(l10n.p2pRobotRecordsUnreadable), findsOneWidget);
          expect(find.textContaining(nothingSent), findsNothing);
          expect(find.text(l10n.p2pCommonRetry), findsOneWidget);
        },
      );

      testWidgets(
        'a read back refused by the database says that nothing was sent, which is so, in $language',
        (tester) async {
          await boundTo(0, 'temple');
          var reads = 0;
          bindings.onRead = () {
            // The read of ReadRobotOnCoordinatorUsecase, after the panel's own.
            if (++reads == 2) bindings.readFailure = const P2pStorageFailure();
          };
          await showPanel(tester, locale: locale);
          final l10n = _text(tester);

          expect(find.text(l10n.p2pRobotStorage), findsOneWidget);
          expect(robotCoordinators.requests, isEmpty);
        },
      );
    }

    testWidgets(
      'a screen reader hears the panel, the hosts and their buttons',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await showPanel(tester);
        expect(
          find.bySemanticsLabel('Coordinator that knows your robot:'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('No coordinator knows this robot yet.'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('Select Host')), findsWidgets);
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byTooltip('Details of TheBigLake'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        semantics.dispose();
      },
    );
  });

  group('the keys of the words (#81)', () {
    IconButton arrow(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(
          find
              .ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(IconButton),
              )
              .first,
        );

    String nickname(WidgetTester tester) =>
        tester.widget<RobotNickname>(find.byType(RobotNickname)).nickname;

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pump();
      await tester.tap(find.text(text));
      await settle(tester);
    }

    Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
      await tester.ensureVisible(find.byTooltip(tooltip));
      await tester.pump();
      await tester.tap(find.byTooltip(tooltip));
      await settle(tester);
    }

    testWidgets(
      'the first opening shows key 0 in its card: no wizard, no backup, no delete',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: TestWordsPort());
        expect(find.text('Garage Key #0'), findsOneWidget);
        expect(find.text('robo1••••••••••••'), findsOneWidget);
        expect(
          find.text(
            'Keep this key safe and do not share it. Your 12 words remake it.',
          ),
          findsOneWidget,
        );
        expect(find.text('New key'), findsOneWidget);
        expect(find.text('Delete All'), findsNothing);
        expect(find.text('Start'), findsNothing);
        expect(arrow(tester, 'Previous key').onPressed, isNull);
        expect(arrow(tester, 'Next key').onPressed, isNull);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));
      },
    );

    testWidgets(
      'nothing of the Garage is drawn until the capture protection is on, in French',
      (tester) async {
        keystoreHolding({});
        protection = () async => false;
        await openTab(
          tester,
          locale: const Locale('fr'),
          words: TestWordsPort(),
        );
        await tester.tap(find.text('Garage'));
        await letTheVaultSettle(tester);
        expect(
          find.text(
            'La protection de l’écran n’a pas pu être activée : la clé de garage reste masquée.',
          ),
          findsOneWidget,
        );
        expect(find.text('Clé de garage n° 0'), findsNothing);
        protection = () async => true;
        await tester.tap(find.text('Réessayer'));
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text('Clé de garage n° 0'), findsOneWidget);
        expect(find.text('Nouvelle clé'), findsOneWidget);
      },
    );

    testWidgets(
      'a key copied is cleared after 30 seconds if the clipboard still holds it',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: TestWordsPort());
        await tapTooltip(tester, 'Show Garage Key');
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        final key = shownKey(tester);
        expect(key, abandonTestnet0);
        await tapTooltip(tester, 'Copy');
        expect(clipboard == key, isTrue);
        await tester.pump(const Duration(seconds: 29));
        expect(clipboard == key, isTrue);
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expect(clipboard, '');
        expect(locator<GarageKeyClipboard>().isArmed, isFalse);
      },
    );

    testWidgets(
      'no request reaches a coordinator from the keys of the Garage, and nothing printed or logged holds a key',
      (tester) async {
        keystoreHolding({});
        final printed = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        late int before;
        try {
          await runZoned(
            () async {
              Zone.current.print('print capture works');
              log.fine('logger capture works');
              await openTab(tester, words: TestWordsPort());
              tor.add(P2pTorState.ready);
              await letTheVaultSettle(tester);
              before = transport.requested.length;
              expect(before, isPositive);
              await tester.tap(find.text('Garage'));
              await settle(tester);
              await letTheVaultSettle(tester);
              await tapTooltip(tester, 'Show Garage Key');
              await tester.tap(find.text('PIN ok'));
              await afterRoute(tester);
              await tapTooltip(tester, 'Copy');
              await tester.pump(const Duration(seconds: 31));
              await settle(tester);
              await tapText(tester, 'New key');
              await tapText(tester, 'Create key #1');
              await tapTooltip(tester, 'Next account');
              await tapTooltip(tester, 'Previous key');
              await tapTooltip(tester, 'Next key');
              await tapTooltip(tester, 'Show Garage Key');
              await tester.tap(find.text('PIN ok'));
              await afterRoute(tester);
              await tapTooltip(tester, 'Copy');
              await tester.pump(const Duration(seconds: 31));
              await settle(tester);
            },
            zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => printed.add(line),
            ),
          );
        } finally {
          debugPrint = previousDebugPrint;
        }
        expect(transport.requested.length, before);
        expect(printed, contains('print capture works'));
        expect(
          printed.any((line) => line.contains('logger capture works')),
          isTrue,
        );
        expect(clipboardWrites.where((text) => text != ''), hasLength(2));
        final keys = [
          for (final text in clipboardWrites.where((text) => text != ''))
            switch (GarageKey.parse(text ?? '')) {
              Ok(:final value) => value,
              Err() => fail('the copied text is not a key'),
            },
        ];
        expect(keys.toSet(), hasLength(2));
        expectNoKeyIn(printed.join('\n'), keys);
        for (final key in keys) {
          for (final index in [0, 1]) {
            final robot = switch (key.deriveIdentity(index)) {
              Ok(:final value) => value,
              Err() => fail('no robot $index'),
            };
            expect(
              printed.join('\n').contains(robot.tokenSha256Hex),
              isFalse,
              reason: 'robot $index',
            );
          }
        }
      },
    );

    testWidgets(
      '« New key » asks first; Cancel creates nothing, « Create key #1 » shows key 1 and its robot 0',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: TestWordsPort());
        final first = nickname(tester);
        await tapText(tester, 'New key');
        expect(find.text('New key?'), findsOneWidget);
        expect(find.text('Your new trades will use key #1.'), findsOneWidget);
        await tapText(tester, 'Cancel');
        expect(find.text('Garage Key #0'), findsOneWidget);
        await tapText(tester, 'New key');
        await tapText(tester, 'Create key #1');
        expect(find.text('Garage Key #1'), findsOneWidget);
        expect(find.text('Robot #0'), findsOneWidget);
        expect(nickname(tester), isNot(first));
        expect(arrow(tester, 'Next key').onPressed, isNull);
        expect(arrow(tester, 'Previous key').onPressed, isNotNull);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'an earlier key says so and offers no « New key »; the arrows ask no PIN',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: TestWordsPort());
        final first = nickname(tester);
        await tapText(tester, 'New key');
        await tapText(tester, 'Create key #1');
        await tapTooltip(tester, 'Previous key');
        expect(find.text('Garage Key #0'), findsOneWidget);
        expect(
          find.text('Earlier key: new trades use key #1.'),
          findsOneWidget,
        );
        expect(find.text('New key'), findsNothing);
        expect(nickname(tester), first);
        await tapTooltip(tester, 'Next key');
        expect(find.text('Garage Key #1'), findsOneWidget);
        expect(find.text('New key'), findsOneWidget);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'the text of every key is behind the PIN, and hidden again on another key',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: TestWordsPort());
        await tapText(tester, 'New key');
        await tapText(tester, 'Create key #1');
        await tapTooltip(tester, 'Show Garage Key');
        expect(reauthentications, 1);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);
        expect(shownKey(tester), startsWith('robo1'));
        expect(shownKey(tester), isNot(abandonTestnet0));
        expectKeyOnlyInView(tester);
        // An earlier key: its text is asked for again.
        await tapTooltip(tester, 'Previous key');
        expect(find.byType(GarageKeyView), findsNothing);
        await tapTooltip(tester, 'Show Garage Key');
        expect(reauthentications, 2);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(shownKey(tester), abandonTestnet0);
        // A system back from the PIN shows nothing.
        await tapTooltip(tester, 'Next key');
        await tapTooltip(tester, 'Show Garage Key');
        await tester.tap(find.text('PIN back'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsNothing);
      },
    );

    testWidgets('without the shell\'s re-authentication, no key is shown', (
      tester,
    ) async {
      keystoreHolding({});
      await openTab(
        tester,
        withReauthentication: false,
        words: TestWordsPort(),
      );
      await tester.tap(find.text('Garage'));
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(arrow(tester, 'Show Garage Key').onPressed, isNull);
    });

    testWidgets('words that cannot give a key: why, then Retry; nothing drawn', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(
        tester,
        words: TestWordsPort(
          refusal: P2pGarageKeyRefusalReason.noDefaultWallet,
        ),
      );
      expect(
        find.text(
          'No default Bitcoin wallet: the Garage Key comes from its 12 words.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('New key'), findsNothing);
      expect(storage.entries, isEmpty);
    });

    testWidgets(
      'while a trade of the key drawn at random is in progress, its card is today\'s, without arrows or « New key »',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        final directory = Directory.systemTemp.createTempSync('p2p-legacy-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/nine.sqlite');
        await tester.runAsync(() => legacyBook(file, fixedKey));
        await openGarage(
          tester,
          words: TestWordsPort(),
          databaseOpener: () => NativeDatabase(file),
        );
        expect(find.text('Garage Key'), findsOneWidget);
        expect(
          find.text(
            'Finish your trades in progress: the Garage Key from your 12 words will come next.',
          ),
          findsOneWidget,
        );
        expect(find.text('Store your Garage Key safely'), findsOneWidget);
        expect(find.text('New key'), findsNothing);
        expect(find.byTooltip('Previous key'), findsNothing);
        expect(find.byTooltip('Next key'), findsNothing);
      },
    );
  });
}

/// Whether [widget] is drawn inside a widget of type [T].
bool _isInside<T extends Widget>(WidgetTester tester, Widget widget) => find
    .ancestor(of: find.byWidget(widget), matching: find.byType(T))
    .evaluate()
    .isNotEmpty;

/// The « Select Host » button of the robot panel.
BullButton _selectHost(WidgetTester tester) => tester.widget<BullButton>(
  find.ancestor(
    of: find.text(_text(tester).p2pRobotSelectHost),
    matching: find.byType(BullButton),
  ),
);

/// The texts of the robot panel shown, in its language.
P2pLocalizations _text(WidgetTester tester) =>
    P2pLocalizations.of(tester.element(find.byType(RobotCoordinatorPanel)));

/// A book of schema 9 at [file] with an open trade of a robot of [key], drawn here: what an update finds with a trade in progress (#81).
Future<void> legacyBook(File file, GarageKey key) async {
  final fingerprint = switch (GarageKeyFingerprint.of(key)) {
    Ok(:final value) => value.hex,
    Err(:final failure) => throw StateError('$failure'),
  };
  final old = v9.DatabaseAtV9(NativeDatabase(file));
  for (final statement in [
    "INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES ('testnet', '$fingerprint', 'generated', 1)",
    "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('testnet', '$fingerprint', 0, 'temple', 'http://temple.onion', '', 'abc', 2, 'generated')",
    "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('testnet', '$fingerprint', 0, 'temple', 'http://temple.onion', 42, 'buyer', 'takenHere', 3, 4, NULL)",
  ]) {
    await old.customStatement(statement);
  }
  await old.close();
}
