import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/list_robot_hosts_usecase.dart';
import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
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
import 'package:p2p/src/presentation/robot_coordinator_cubit.dart';
import 'package:p2p/src/ui/coordinator_details_dialog.dart';
import 'package:p2p/src/ui/garage/garage_view.dart';
import 'package:p2p/src/ui/garage/robot_nickname.dart';
import 'package:p2p/src/ui/garage/robot_coordinator_panel.dart';
import 'package:p2p/src/ui/garage/robot_history_dialog.dart';
import 'package:p2p/src/ui/garage/select_host_sheet.dart';
import 'package:p2p/src/ui/garage/send_robot_dialog.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
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
import 'support/lean_confirmation.dart' show loadAppFont;
import 'support/robot_bindings.dart';
import 'support/robot_coordinators.dart';

/// The `no_screenshot` plugin behind `PrivacyScreen` answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

const _mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
const _testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';

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
          // The masked field (#81) shows the prefix of every key and dots, never any part of a key.
          widget.text.toPlainText() != 'robo1••••••••••••' &&
          // The instruction of « Robot recovery » names the prefix only.
          !widget.text.toPlainText().contains('(robo1...)') &&
          !_isInside<GarageKeyView>(tester, widget),
    );
    expect(outside, findsNothing);
    // A boolean, so that a failure does not print the key it found.
    expect(
      semanticsTexts(tester).any((text) => text.contains('robo1')),
      isFalse,
    );
  }

  /// The paste field of « Robot recovery » and its editable text.
  Finder pasteInput() => find.descendant(
    of: find.byType(GarageKeyField),
    matching: find.byType(EditableText),
  );

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
      expect(find.byTooltip('Show Garage Key'), findsNothing);

      answer.complete(true);
      await settle(tester);

      expect(find.text(fixedNickname), findsOneWidget);
    });

    testWidgets('releases the protection when the Garage is left', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);
      // The words of the seam read the empty slot, then the keys read it again for an external key (review of #292): two read budgets.
      await letTheVaultSettle(tester);

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

    // A failure is not an absence: « You do not have a Garage Key » would invite to make a key over one that may well be there.
    for (final (name, held, locked, scripted) in [
      ('the keystore locked', {_testnetEntry: null}, true, null),
      ('a damaged entry', {_testnetEntry: 'not json at all'}, false, null),
      (
        'an entry the keystore keeps failing to read',
        {_testnetEntry: null},
        false,
        // The words of the seam read the slot, then the keys read it again for an external key (review of #292): two read budgets of failures.
        List<Object?>.generate(10, (_) => PlatformException(code: 'read')),
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
        // An entry the keystore keeps failing to read: twice about 4.5 s of retries (the words of the seam read the slot, then the keys read it again, review of #292), then « This order is not available ».
        keystoreHolding(
          {_testnetEntry: null},
          scripted: List<Object?>.generate(
            10,
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
            10,
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
        // The words of the seam read the empty slot, then the keys read it again for an external key (review of #292): two read budgets.
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
      // The key the vault keeps is the external key, selected at the first opening (#81).
      expect(find.text('External Garage Key'), findsOneWidget);
      expect(find.byType(GarageKeyView), findsNothing);
      expectKeyOnlyInView(tester);

      await tester.tap(find.byTooltip('Show Garage Key'));
      await afterRoute(tester);
      expect(reauthentications, isPositive);
      await tester.tap(find.text('PIN back'));
      await afterRoute(tester);
      expect(find.byType(GarageKeyView), findsNothing);

      await tester.tap(find.byTooltip('Show Garage Key'));
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

      await tester.tap(find.byTooltip('Show Garage Key'));
      await afterRoute(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      await navigator.maybePop();
      await afterRoute(tester);

      expect(find.byType(GarageKeyView), findsNothing);
      expect(find.byTooltip('Show Garage Key'), findsOneWidget);
    });

    testWidgets('without the re-authentication of the shell, never shows it', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openTab(tester, withReauthentication: false);
      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      await tester.tap(find.byTooltip('Show Garage Key'));
      await afterRoute(tester);

      expect(reauthentications, 0);
      expect(find.byType(GarageKeyView), findsNothing);
    });
  });

  group('the re-authentication', () {
    testWidgets('the key is not built under the gate before it answers', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);

      await tester.tap(find.byTooltip('Show Garage Key'));
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

      await tester.tap(find.byTooltip('Show Garage Key'));
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

        await tester.tap(find.byTooltip('Show Garage Key'));
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
        await tester.tap(find.byTooltip('Show Garage Key'));
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
        expect(find.byTooltip('Show Garage Key'), findsOneWidget);
      },
    );
  });

  group('the robot panel, in the Garage', () {
    bool robotRequestsMade() =>
        transport.requested.any((path) => path.contains('/api/robot'));

    // Security review of step 6: what the panel opened closes with it when the Garage changes under it, and nothing is sent; since #81, another key shown is one more such change.
    for (final opened in ['« Select Host »', 'the confirmation']) {
      for (final change in ['the network', 'the next robot', 'a new key']) {
        testWidgets(
          '$change while $opened is open: it closes, and nothing is sent',
          (tester) async {
            keystoreHolding({});
            await openGarage(
              tester,
              words: await (() async {
                final words = TestWordsPort();
                await tester.runAsync(
                  () => words.precompute([
                    (RobosatsNetwork.testnet, 0),
                    (RobosatsNetwork.testnet, 1),
                    (RobosatsNetwork.mainnet, 0),
                  ]),
                );
                return words;
              })(),
            );
            tor.add(P2pTorState.ready);
            await letTheVaultSettle(tester);
            await tester.ensureVisible(find.text('Select Host'));
            await settle(tester);
            await tester.tap(find.text('Select Host'));
            await afterRoute(tester);
            expect(find.byType(SelectHostSheet), findsOneWidget);
            if (opened == 'the confirmation') {
              await tester.tap(find.text('Temple of Sats'));
              await afterRoute(tester);
              expect(find.byType(SendRobotDialog), findsOneWidget);
            }
            final garage = tester
                .element(find.byType(GarageView))
                .read<GarageCubit>();
            switch (change) {
              case 'the network':
                network.switchTo(RobosatsNetwork.mainnet);
              case 'the next robot':
                garage.next();
              default:
                unawaited(garage.newKey());
            }
            await settle(tester);
            await letTheVaultSettle(tester);
            expect(find.byType(SelectHostSheet), findsNothing);
            expect(find.byType(SendRobotDialog), findsNothing);
            expect(find.byType(GarageView), findsOneWidget);
            expect(robotRequestsMade(), isFalse);
          },
        );
      }
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
          // A key of the words is recorded as drawn here (#81): no « Robots from elsewhere » first.
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
          'This Garage Key was imported, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Bull Market, a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, go back to the internal Garage Keys.',
          'I understand',
        ),
        (
          Locale('fr'),
          'Robots venus d’ailleurs',
          'Cette clé de garage a été importée, ou cet appareil n’a pas pu enregistrer qu’il l’a générée. Ses robots existent peut-être déjà chez des coordinateurs\u00a0: l’application officielle RoboSats envoie chaque robot qu’elle affiche à tous les coordinateurs. Dans Bull Market, un robot ne vit que chez un seul coordinateur\u00a0: si vous avez déjà utilisé cette clé, placez chaque robot chez le coordinateur où vous l’avez utilisé. Pour repartir de zéro, revenez aux clés de garage internes.',
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

  group('the Garage Keys (#81, the mock-up decided on 2026-11-26)', () {
    /// The port of the test words, its keys derived beforehand, outside the fake time.
    Future<TestWordsPort> wordsOf(WidgetTester tester) async {
      final words = TestWordsPort();
      await tester.runAsync(
        () => words.precompute([
          for (var index = 0; index < 3; index++)
            (RobosatsNetwork.testnet, index),
          (RobosatsNetwork.mainnet, 0),
        ]),
      );
      return words;
    }

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

    // Each reading of the keys reads the vault slot of the external Garage Key, whose empty slot the vault settles with its full budget (#81).
    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.pump();
      await tester.tap(find.text(text).last);
      await letTheVaultSettle(tester);
    }

    Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
      await tester.ensureVisible(find.byTooltip(tooltip).first);
      await tester.pump();
      await tester.tap(find.byTooltip(tooltip).first);
      await letTheVaultSettle(tester);
    }

    const internalHelp = 'Backed up by the 12 words of your Bull Wallet.';
    const externalHelp =
        'Not backed up by your Bull Wallet: keep a copy of it.';

    /// A book of schema 9 with an open trade of the fixed key, in the vault's testnet slot: what an update finds.
    Future<QueryExecutor Function()> updatedBook(WidgetTester tester) async {
      keystoreHolding({_testnetEntry: null});
      final directory = Directory.systemTemp.createTempSync('p2p-external-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/nine.sqlite');
      await tester.runAsync(() => schema9Book(file, fixedKey));
      return () => NativeDatabase(file);
    }

    testWidgets(
      'the first opening shows internal key 0 in its card: no wizard, no backup, no delete, the import link',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(find.text('robo1••••••••••••'), findsOneWidget);
        expect(find.text(internalHelp), findsOneWidget);
        expect(find.text('New internal Garage Key'), findsOneWidget);
        expect(find.text('Import an external Garage Key'), findsOneWidget);
        expect(find.text('Switch to the external Garage Key'), findsNothing);
        expect(find.text('Delete the external Garage Key'), findsNothing);
        expect(find.text('Your Garage Keys'), findsNothing);
        expect(find.text('Delete All'), findsNothing);
        expect(find.text('Start'), findsNothing);
        expect(arrow(tester, 'Previous internal Garage Key').onPressed, isNull);
        expect(arrow(tester, 'Next internal Garage Key').onPressed, isNull);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));
      },
    );

    testWidgets(
      'nothing of the Garage is drawn until the capture protection is on, and nothing is read, in French',
      (tester) async {
        keystoreHolding({});
        protection = () async => false;
        await openTab(
          tester,
          locale: const Locale('fr'),
          words: await wordsOf(tester),
        );
        await tester.tap(find.text('Garage'));
        await letTheVaultSettle(tester);
        expect(
          find.text(
            'La protection de l’écran n’a pas pu être activée : la clé de garage reste masquée.',
          ),
          findsOneWidget,
        );
        expect(find.text('Clé de garage interne n° 0'), findsNothing);
        // The Garage is built only once the protection is on: until then it read nothing.
        expect(storage.reads, 0);
        protection = () async => true;
        await tester.tap(find.text('Réessayer'));
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text('Clé de garage interne n° 0'), findsOneWidget);
        expect(find.text('Nouvelle clé de garage interne'), findsOneWidget);
        expect(
          find.text('Sauvegardée par les 12 mots de votre Bull Wallet.'),
          findsOneWidget,
        );
        expect(find.text('Importer une clé de garage externe'), findsOneWidget);
      },
    );

    for (final (label, after)
        in <(String, Future<void> Function(WidgetTester))>[
          ('if the clipboard still holds it', (_) async {}),
          (
            'even after the Garage is left',
            (tester) async {
              await tester.tap(find.text('Offers'));
              await settle(tester);
            },
          ),
        ]) {
      testWidgets('a key copied is cleared after 30 seconds $label', (
        tester,
      ) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        await tapTooltip(tester, 'Show Garage Key');
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        final key = shownKey(tester);
        expect(key, abandonTestnet0);
        await tester.tap(find.byTooltip('Copy'));
        await settle(tester);
        expect(clipboard == key, isTrue);
        await after(tester);
        await tester.pump(const Duration(seconds: 29));
        // Still there until the 30 seconds, while the Garage is shown.
        if (label.startsWith('if')) expect(clipboard == key, isTrue);
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expect(clipboard, '');
        expect(locator<GarageKeyClipboard>().isArmed, isFalse);
      });
    }

    testWidgets(
      'a key copied is left alone once the user copied something else',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        await tapTooltip(tester, 'Show Garage Key');
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        await tester.tap(find.byTooltip('Copy'));
        await settle(tester);
        clipboard = 'a shopping list';
        await tester.pump(const Duration(seconds: 31));
        await settle(tester);
        expect(clipboard, 'a shopping list');
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
              await openTab(tester, words: await wordsOf(tester));
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
              await tapText(tester, 'New internal Garage Key');
              await tapText(tester, 'Create internal Garage Key #1');
              await tapTooltip(tester, 'Next account');
              await tapTooltip(tester, 'Previous internal Garage Key');
              await tapTooltip(tester, 'Next internal Garage Key');
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
      '« New internal Garage Key » asks first; Cancel creates nothing, « Create » shows internal key 1 and its robot 0, without the PIN',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        final first = nickname(tester);
        await tapText(tester, 'New internal Garage Key');
        expect(find.text('New Garage Key'), findsOneWidget);
        expect(
          find.text(
            'Your trades will use internal Garage Key #1. Earlier Garage Keys stay within reach in the Garage.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Cancel');
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        await tapText(tester, 'New internal Garage Key');
        await tapText(tester, 'Create internal Garage Key #1');
        expect(find.text('Internal Garage Key #1'), findsOneWidget);
        expect(find.text('Robot #0'), findsOneWidget);
        expect(nickname(tester), isNot(first));
        expect(arrow(tester, 'Next internal Garage Key').onPressed, isNull);
        expect(
          arrow(tester, 'Previous internal Garage Key').onPressed,
          isNotNull,
        );
        // From key 0, « Create » makes the key above the highest, key 2.
        await tapTooltip(tester, 'Previous internal Garage Key');
        await tapText(tester, 'New internal Garage Key');
        expect(find.text('Create internal Garage Key #2'), findsOneWidget);
        await tapText(tester, 'Create internal Garage Key #2');
        expect(find.text('Internal Garage Key #2'), findsOneWidget);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'the arrows select an earlier internal key, which keeps « New internal Garage Key »; they ask no PIN',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        final first = nickname(tester);
        await tapText(tester, 'New internal Garage Key');
        await tapText(tester, 'Create internal Garage Key #1');
        await tapTooltip(tester, 'Previous internal Garage Key');
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(find.text('New internal Garage Key'), findsOneWidget);
        expect(nickname(tester), first);
        await tapTooltip(tester, 'Next internal Garage Key');
        expect(find.text('Internal Garage Key #1'), findsOneWidget);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'the text of every key is behind the PIN, and hidden again on another key',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        await tapText(tester, 'New internal Garage Key');
        await tapText(tester, 'Create internal Garage Key #1');
        await tapTooltip(tester, 'Show Garage Key');
        expect(reauthentications, 1);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);
        expect(shownKey(tester), startsWith('robo1'));
        expect(shownKey(tester), isNot(abandonTestnet0));
        expectKeyOnlyInView(tester);
        // An earlier key: its text is asked for again.
        await tapTooltip(tester, 'Previous internal Garage Key');
        expect(find.byType(GarageKeyView), findsNothing);
        await tapTooltip(tester, 'Show Garage Key');
        expect(reauthentications, 2);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(shownKey(tester), abandonTestnet0);
        // A system back from the PIN shows nothing.
        await tapTooltip(tester, 'Next internal Garage Key');
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
        words: await wordsOf(tester),
      );
      await tester.tap(find.text('Garage'));
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(arrow(tester, 'Show Garage Key').onPressed, isNull);
    });

    testWidgets(
      'the ⓘ opens the explanation of the key shown, internal or external, closed by its button; a screen reader hears it as an explanation',
      (tester) async {
        final semantics = tester.ensureSemantics();
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        expect(
          tester.getSemantics(find.byTooltip('Explanation')),
          isSemantics(
            tooltip: 'Explanation',
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(find.bySemanticsLabel('Internal Garage Key #0'), findsOneWidget);
        await tapTooltip(tester, 'Explanation');
        expect(find.text('Internal Garage Keys'), findsOneWidget);
        expect(
          find.text(
            'Your internal Garage Keys are backed up by the 12 words of your Bull Wallet: reinstall the app with these 12 words and you find them again. Keep them safe and do not share them: whoever holds a Garage Key controls its robots.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Acknowledged');
        expect(find.text('Internal Garage Keys'), findsNothing);
        await tapText(tester, 'Import an external Garage Key');
        await tester.enterText(pasteInput(), exampleText);
        await settle(tester);
        await tapText(tester, 'Recover');
        expect(find.text('External Garage Key'), findsOneWidget);
        await tapTooltip(tester, 'Explanation');
        expect(find.text('External Garage Key'), findsNWidgets(2));
        expect(
          find.text(
            'This Garage Key is not backed up by the 12 words of your Bull Wallet. If you lose this phone or delete the app, you will only find it again with your own copy: back it up separately. Keep it safe and do not share it.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Acknowledged');
        expect(find.text('External Garage Key'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets(
      'after the update, the key the vault kept is the external Garage Key, shown once with « Your Garage Keys », its trade in progress named, and the way to the internal keys and back',
      (tester) async {
        final opener = await updatedBook(tester);
        await openGarage(
          tester,
          words: await wordsOf(tester),
          databaseOpener: opener,
        );
        expect(find.text('Your Garage Keys'), findsOneWidget);
        expect(
          find.text(
            'Your current Garage Key is now called « External Garage Key ». The internal Garage Keys, backed up by your Bull Wallet, are next to it: tap « Back to internal Garage Keys ».',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Acknowledged');
        expect(find.text('Your Garage Keys'), findsNothing);
        // Behind it, the Garage stays on the external Garage Key: no arrows, no « New internal Garage Key », no import.
        expect(find.text('External Garage Key'), findsOneWidget);
        expect(find.text(fixedNickname), findsOneWidget);
        expect(find.text(externalHelp), findsOneWidget);
        expect(find.byTooltip('Previous internal Garage Key'), findsNothing);
        expect(find.byTooltip('Next internal Garage Key'), findsNothing);
        expect(find.text('New internal Garage Key'), findsNothing);
        expect(find.text('Import an external Garage Key'), findsNothing);
        expect(find.text('Delete the external Garage Key'), findsOneWidget);
        // Its own trade in progress has no line of its own here.
        expect(find.text('Trade in progress #42'), findsNothing);
        await tapText(tester, 'Back to internal Garage Keys');
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(find.text('Switch to the external Garage Key'), findsOneWidget);
        expect(find.text('Import an external Garage Key'), findsNothing);
        // The trade of the external Garage Key, shown on another key: its line, its key, its robot and its coordinator.
        expect(find.text('Trade in progress #42'), findsOneWidget);
        expect(
          find.text('External Garage Key · Robot #0 · Temple of Sats'),
          findsOneWidget,
        );
        await tapText(tester, 'New internal Garage Key');
        await tapText(tester, 'Create internal Garage Key #1');
        await tapTooltip(tester, 'Previous internal Garage Key');
        await tapText(tester, 'Switch to the external Garage Key');
        expect(find.text('External Garage Key'), findsOneWidget);
        // « Back » returns to the last internal key shown, key 0, not the highest.
        await tapText(tester, 'Back to internal Garage Keys');
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        // Never twice: leaving the Garage and coming back, on the external key.
        await tapText(tester, 'Switch to the external Garage Key');
        await tester.tap(find.text('Offers'));
        await settle(tester);
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text('External Garage Key'), findsOneWidget);
        expect(find.text('Your Garage Keys'), findsNothing);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'deleting the external Garage Key during its trade: the dialog names the trade, « Delete » stays enabled, the PIN, then the last internal key and the import link',
      (tester) async {
        final opener = await updatedBook(tester);
        await openGarage(
          tester,
          words: await wordsOf(tester),
          databaseOpener: opener,
        );
        await tapText(tester, 'Acknowledged');
        await tapText(tester, 'Delete the external Garage Key');
        expect(find.text('Delete the external Garage Key?'), findsOneWidget);
        expect(
          find.text(
            'It is not backed up by your Bull Wallet. Without a copy, its robots will be lost to this app.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Trade #42 uses this Garage Key: without it, you will not be able to continue it.',
          ),
          findsOneWidget,
        );
        // « Cancel » deletes nothing and asks nothing.
        await tapText(tester, 'Cancel');
        expect(reauthentications, 0);
        expect(storage.entries.keys, contains(_testnetEntry));
        await tapText(tester, 'Delete the external Garage Key');
        await tester.tap(find.text('Delete'));
        await afterRoute(tester);
        // A robot of it is bound: the PIN, as before #81.
        expect(reauthentications, 1);
        expect(storage.entries.keys, contains(_testnetEntry));
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        await letTheVaultSettle(tester);
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(find.text('Import an external Garage Key'), findsOneWidget);
        expect(find.text('Switch to the external Garage Key'), findsNothing);
      },
    );

    for (final (locale, title, text, confirm, cancel, pin) in [
      (
        const Locale('en'),
        'Delete the external Garage Key?',
        'It is not backed up by your Bull Wallet. Without a copy, its robots will be lost to this app.',
        'Delete',
        'Cancel',
        'Delete the external Garage Key',
      ),
      (
        const Locale('fr'),
        'Supprimer la clé de garage externe ?',
        'Elle n\'est pas sauvegardée par votre Bull Wallet. Sans une copie, ses robots seront perdus pour cette app.',
        'Supprimer',
        'Annuler',
        'Supprimer la clé de garage externe',
      ),
    ]) {
      testWidgets(
        'in ${locale.languageCode}: its delete asks, then the PIN, then deletes this network\'s only',
        (tester) async {
          keystoreHolding({_testnetEntry: null, _mainnetEntry: null});
          await openGarage(
            tester,
            locale: locale,
            words: await wordsOf(tester),
          );
          await tapText(tester, pin);
          expect(find.text(title), findsOneWidget);
          expect(find.text(text), findsOneWidget);
          expect(reauthentications, 0);
          await tapText(tester, cancel);
          expect(reauthentications, 0);
          expect(
            storage.entries.keys.toSet(),
            containsAll({_testnetEntry, _mainnetEntry}),
          );
          await tapText(tester, pin);
          await tester.tap(find.text(confirm));
          await afterRoute(tester);
          // The fixed key has no record of being drawn here: a robot of it may live on a coordinator, so the PIN comes after the confirmation, before anything is deleted.
          expect(reauthentications, 1);
          expect(storage.entries.keys, contains(_testnetEntry));
          await tester.tap(find.text('PIN ok'));
          await afterRoute(tester);
          await letTheVaultSettle(tester);
          expect(storage.entries.keys, isNot(contains(_testnetEntry)));
          expect(
            storage.entries[_mainnetEntry],
            storedFixedKeys[_mainnetEntry],
          );
          expect(find.text(fixedNickname), findsNothing);
        },
      );
    }

    testWidgets('says so when the external key could not be deleted', (
      tester,
    ) async {
      keystoreHolding(
        {_testnetEntry: null},
        scriptedWrites: [PlatformException(code: 'delete failed')],
      );
      await openGarage(tester, words: await wordsOf(tester));
      await tapText(tester, 'Delete the external Garage Key');
      await tester.tap(find.text('Delete'));
      await afterRoute(tester);
      await tester.tap(find.text('PIN ok'));
      await afterRoute(tester);
      await letTheVaultSettle(tester);
      expect(
        find.text('The Garage Key could not be deleted. Try again.'),
        findsOneWidget,
      );
      expect(find.text(fixedNickname), findsOneWidget);
      expect(storage.entries[_testnetEntry], storedFixedKeys[_testnetEntry]);
    });

    testWidgets(
      'leaving the PIN deletes nothing and leaves the card as it was; without the re-authentication, a key that may have robots cannot be deleted',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openGarage(tester, words: await wordsOf(tester));
        await tapTooltip(tester, 'Next account');
        expect(find.text('Robot #1'), findsOneWidget);
        await tapText(tester, 'Delete the external Garage Key');
        await tester.tap(find.text('Delete'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN back'));
        await afterRoute(tester);
        expect(storage.entries.keys, contains(_testnetEntry));
        expect(find.text('Robot #1'), findsOneWidget);
        expect(find.text('External Garage Key'), findsOneWidget);
      },
    );

    testWidgets(
      'without the shell\'s re-authentication, the delete of an external key that may have robots is disabled',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openTab(
          tester,
          withReauthentication: false,
          words: await wordsOf(tester),
        );
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);
        await tester.ensureVisible(find.text('Delete the external Garage Key'));
        await tester.pump();
        final button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Delete the external Garage Key'),
            matching: find.byType(TextButton),
          ),
        );
        expect(button.onPressed, isNull);
        await tester.tap(
          find.text('Delete the external Garage Key'),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.text('Delete the external Garage Key?'), findsNothing);
        expect(storage.entries.keys, contains(_testnetEntry));
      },
    );

    testWidgets(
      'an external key locked: retry and the way back only, nothing deleted, in French',
      (tester) async {
        keystoreHolding({_testnetEntry: null}, locked: true);
        await openGarage(
          tester,
          locale: const Locale('fr'),
          words: await wordsOf(tester),
        );
        expect(
          find.text(
            'Le coffre de l’appareil est verrouillé. Déverrouillez votre appareil, puis réessayez.',
          ),
          findsOneWidget,
        );
        expect(find.text('Réessayer'), findsOneWidget);
        expect(
          find.text('Revenir aux clés de garage internes'),
          findsOneWidget,
        );
        expect(find.text('Supprimer la clé de garage externe'), findsNothing);
        storage
          ..locked = false
          ..writesFail = false;
        await tapText(tester, 'Réessayer');
        expect(find.text(fixedNickname), findsOneWidget);
        expect(find.text('Clé de garage externe'), findsOneWidget);
      },
    );

    testWidgets(
      'an external key damaged: why, its delete after the PIN, then the internal key and the import link',
      (tester) async {
        keystoreHolding({_testnetEntry: 'not json at all'});
        await openGarage(tester, words: await wordsOf(tester));
        expect(find.text('External Garage Key'), findsOneWidget);
        expect(
          find.text('The Garage Key stored on this device is damaged.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Try again. If it keeps failing, delete it: the key and its robots are lost unless you kept a copy.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Delete the external Garage Key');
        expect(find.text('Delete the external Garage Key?'), findsOneWidget);
        expect(reauthentications, 0);
        await tester.tap(find.text('Delete'));
        await afterRoute(tester);
        // A slot that cannot be read always asks the PIN, after the confirmation.
        expect(reauthentications, 1);
        expect(storage.entries.keys, contains(_testnetEntry));
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        await letTheVaultSettle(tester);
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(find.text('Import an external Garage Key'), findsOneWidget);
      },
    );

    testWidgets(
      'an external key unreadable: said so, kept as it is, the way back offered',
      (tester) async {
        keystoreHolding({
          _testnetEntry: null,
        }, scripted: List.generate(5, (_) => PlatformException(code: 'read')));
        await openGarage(tester, words: await wordsOf(tester));
        expect(
          find.text('The Garage Key stored on this device cannot be read.'),
          findsOneWidget,
        );
        expect(find.text('Back to internal Garage Keys'), findsOneWidget);
        expect(storage.entries[_testnetEntry], storedFixedKeys[_testnetEntry]);
        await tapText(tester, 'Back to internal Garage Keys');
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
      },
    );

    for (final (reason, text) in [
      (
        P2pGarageKeyRefusalReason.noDefaultWallet,
        'No default Bitcoin wallet: the internal Garage Keys come from its 12 words.',
      ),
      (
        P2pGarageKeyRefusalReason.passphrase,
        'This wallet has a passphrase: its 12 words alone do not give the internal Garage Keys.',
      ),
      (
        P2pGarageKeyRefusalReason.noWords,
        'This wallet has no words: the internal Garage Keys come from them.',
      ),
      (
        P2pGarageKeyRefusalReason.locked,
        'The keystore is locked. Unlock your device, then try again.',
      ),
      (
        P2pGarageKeyRefusalReason.unreadable,
        'The Garage Key stored on this device cannot be read.',
      ),
    ]) {
      testWidgets(
        'words that refuse (${reason.name}): without an external key, why and Retry; with one, the external key shown and usable, the internal side saying why (C-passphrase)',
        (tester) async {
          keystoreHolding({});
          await openGarage(tester, words: TestWordsPort(refusal: reason));
          expect(find.text(text), findsOneWidget);
          expect(find.text('Retry'), findsOneWidget);
          expect(find.text('Switch to the external Garage Key'), findsNothing);
          expect(find.text('New internal Garage Key'), findsNothing);
          expect(storage.entries, isEmpty);
        },
      );

      testWidgets(
        'words that refuse (${reason.name}), with an external key: shown, usable and deletable; the internal side says why, with the way back',
        (tester) async {
          keystoreHolding({_testnetEntry: null});
          await openGarage(tester, words: TestWordsPort(refusal: reason));
          expect(find.text('External Garage Key'), findsOneWidget);
          expect(find.text(fixedNickname), findsOneWidget);
          expect(find.text('Delete the external Garage Key'), findsOneWidget);
          await tapText(tester, 'Back to internal Garage Keys');
          expect(find.text(text), findsOneWidget);
          expect(find.text('Retry'), findsOneWidget);
          await tapText(tester, 'Retry');
          expect(find.text(text), findsOneWidget);
          await tapText(tester, 'Switch to the external Garage Key');
          expect(find.text('External Garage Key'), findsOneWidget);
          expect(find.text(fixedNickname), findsOneWidget);
        },
      );
    }

    testWidgets(
      'without an external key, « Import an external Garage Key » opens today\'s « Robot recovery »; a key stored there shows the external key at once, its robot 0',
      (tester) async {
        keystoreHolding({});
        await openGarage(
          tester,
          locale: const Locale('fr'),
          words: await wordsOf(tester),
        );
        await tapText(tester, 'Importer une clé de garage externe');
        expect(find.text('Récupération du robot'), findsOneWidget);
        expect(find.text('Mode clé de garage'), findsOneWidget);
        expect(
          find.text(
            'Saisissez votre clé de garage (robo1...) pour récupérer tous vos comptes robot.',
          ),
          findsOneWidget,
        );
        await tester.enterText(pasteInput(), 'robo1');
        await settle(tester);
        expect(find.text('Longueur invalide'), findsOneWidget);
        await tester.tap(find.text('Récupérer'));
        await settle(tester);
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));
        // An internal key of this device is refused, by its number.
        await tester.enterText(pasteInput(), abandonTestnet0);
        await settle(tester);
        await tester.tap(find.text('Récupérer'));
        await letTheVaultSettle(tester);
        expect(
          find.text('C\'est déjà votre clé de garage interne n° 0.'),
          findsOneWidget,
        );
        expect(storage.entries.keys, isNot(contains(_testnetEntry)));

        await tester.enterText(pasteInput(), exampleText);
        await settle(tester);
        await tester.tap(find.text('Récupérer'));
        await letTheVaultSettle(tester);
        expect(find.text('Récupération du robot'), findsNothing);
        expect(find.text('Clé de garage externe'), findsOneWidget);
        expect(find.text(exampleNickname), findsOneWidget);
        expect(find.text('Robot #0'), findsOneWidget);
        expect(find.text('Your Garage Keys'), findsNothing);
        expect(find.text('Vos clés de garage'), findsNothing);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(storage.entries.keys, contains(_testnetEntry));
      },
    );

    testWidgets(
      'a change of network shows the keys of the other network, never their robot',
      (tester) async {
        keystoreHolding({_testnetEntry: null});
        await openGarage(tester, words: await wordsOf(tester));
        expect(find.text(fixedNickname), findsOneWidget);
        network.switchTo(RobosatsNetwork.mainnet);
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text(fixedNickname), findsNothing);
        expect(find.text('Internal Garage Key #0'), findsOneWidget);
        expect(storage.entries[_testnetEntry], storedFixedKeys[_testnetEntry]);
        network.switchTo(RobosatsNetwork.testnet);
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text(fixedNickname), findsOneWidget);
      },
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      testWidgets(
        'in ${locale.languageCode}, on a phone of 320 points at the text size ×1, ×2 and ×3: the card on each kind of key and its dialogs overflow nothing, break no word that fits a line, and every target is 44 points high at least',
        (tester) async {
          await loadAppFont();
          final opener = await updatedBook(tester);
          await openGarage(
            tester,
            locale: locale,
            words: await wordsOf(tester),
            databaseOpener: opener,
          );
          final l10n = P2pLocalizations.of(
            tester.element(find.byType(GarageView)),
          );
          await tapText(tester, l10n.p2pCommonAcknowledged);
          tester.view
            ..physicalSize = const Size(320 * 3, 2400 * 3)
            ..devicePixelRatio = 3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          /// Every text of [labels] shown: its lines break between words only.
          void wordsWhole(List<String> labels, String reason) {
            for (final label in labels) {
              for (final element in find.text(label).evaluate()) {
                final paragraph = element.renderObject;
                if (paragraph is! RenderParagraph) continue;
                final text = paragraph.text.toPlainText();
                // The paragraph's own text, width and scale, laid out again to read where its lines break.
                final painter = TextPainter(
                  text: paragraph.text,
                  textDirection: paragraph.textDirection,
                  textAlign: paragraph.textAlign,
                  textScaler: paragraph.textScaler,
                )..layout(maxWidth: paragraph.size.width);
                addTearDown(painter.dispose);
                var offset = 0;
                while (offset < text.length) {
                  final line = painter.getLineBoundary(
                    TextPosition(offset: offset),
                  );
                  if (line.end >= text.length || line.end <= offset) break;
                  expect(
                    text[line.end - 1] == ' ' || text[line.end] == ' ',
                    isTrue,
                    reason: '$reason: « $label » broken at ${line.end}',
                  );
                  offset = line.end;
                  while (offset < text.length && text[offset] == ' ') {
                    offset++;
                  }
                }
              }
            }
          }

          Finder iconButton(String tooltip) => find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          );

          void targets(List<Finder> finders, String reason) {
            for (final finder in finders) {
              for (final element in finder.evaluate()) {
                final box = element.renderObject as RenderBox;
                expect(
                  box.size.height >= 44,
                  isTrue,
                  reason: '$reason: ${box.size}',
                );
              }
            }
          }

          for (final scale in const [1.0, 2.0, 3.0]) {
            final reason = '${locale.languageCode} ×$scale';
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pump();
            await settle(tester);
            // The external key, its line under the field, « Back » and its delete.
            await tester.ensureVisible(find.text(l10n.p2pGarageDeleteExternal));
            await tester.pump();
            expect(tester.takeException(), isNull, reason: reason);
            wordsWhole([
              l10n.p2pGarageKeyNotBackedUp,
              l10n.p2pGarageBackToInternal,
              l10n.p2pGarageDeleteExternal,
            ], reason);
            targets([
              find.ancestor(
                of: find.text(l10n.p2pGarageDeleteExternal),
                matching: find.byType(TextButton),
              ),
              iconButton(l10n.p2pGarageKeyExplain),
              iconButton(l10n.p2pGarageKeyReveal),
            ], reason);
            // Its delete, with the trade in progress named.
            await tapText(tester, l10n.p2pGarageDeleteExternal);
            expect(tester.takeException(), isNull, reason: reason);
            wordsWhole([
              l10n.p2pGarageDeleteExternalTitle,
              l10n.p2pGarageDeleteExternalText,
              l10n.p2pGarageDeleteExternalTrades(1, '#42'),
              l10n.p2pGarageDeleteConfirm,
            ], reason);
            await tapText(tester, l10n.p2pCommonCancel);
            // The explanation of the external key.
            await tapTooltip(tester, l10n.p2pGarageKeyExplain);
            expect(tester.takeException(), isNull, reason: reason);
            wordsWhole([l10n.p2pGarageExternalKeyInfo], reason);
            await tapText(tester, l10n.p2pCommonAcknowledged);
            // An internal key: the arrows, the line, « New internal Garage Key », the switch, the trade of the other key.
            await tapText(tester, l10n.p2pGarageBackToInternal);
            await tester.ensureVisible(
              find.text(l10n.p2pGarageSwitchToExternal),
            );
            await tester.pump();
            expect(tester.takeException(), isNull, reason: reason);
            wordsWhole([
              l10n.p2pGarageKeyBackedUp,
              l10n.p2pGarageNewKey,
              l10n.p2pGarageSwitchToExternal,
              l10n.p2pGarageTradeInProgress('42'),
            ], reason);
            targets([
              iconButton(l10n.p2pGaragePreviousKey),
              iconButton(l10n.p2pGarageNextKey),
              iconButton(l10n.p2pGarageKeyExplain),
            ], reason);
            await tapText(tester, l10n.p2pGarageNewKey);
            expect(tester.takeException(), isNull, reason: reason);
            wordsWhole([
              l10n.p2pGarageNewKeyTitle,
              l10n.p2pGarageNewKeyText(1),
              l10n.p2pGarageNewKeyConfirm(1),
            ], reason);
            await tapText(tester, l10n.p2pCommonCancel);
            await tapText(tester, l10n.p2pGarageSwitchToExternal);
          }
        },
      );
    }

    testWidgets(
      'an internal key, drawn here: Select Host once Tor is ready, then the sheet and the confirmation, and Cancel sends nothing',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester, words: await wordsOf(tester));
        expect(_selectHost(tester).disabled, isTrue);
        tor.add(P2pTorState.connecting);
        await settle(tester);
        expect(_selectHost(tester).disabled, isTrue);
        expect(find.text('Connecting to Tor network'), findsOneWidget);
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        expect(_selectHost(tester).disabled, isFalse);
        await tester.ensureVisible(find.text('Select Host'));
        await settle(tester);
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        // A key drawn here asks no « Robots from elsewhere ».
        expect(find.byType(RobotHistoryDialog), findsNothing);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(find.text('TheBigLake'), findsOneWidget);
        await tester.tap(find.text('Temple of Sats'));
        await afterRoute(tester);
        expect(find.byType(SendRobotDialog), findsOneWidget);
        expect(find.textContaining('to Temple of Sats?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await afterRoute(tester);
        expect(find.byType(SendRobotDialog), findsNothing);
        expect(
          find.text('No coordinator knows this robot yet.'),
          findsOneWidget,
        );
        expect(transport.requests.where((r) => r.robot != null), isEmpty);
      },
    );
  });

  /// The paste field of « Robot recovery » and its editable text.
  Finder recoveryInput() => pasteInput();

  /// « Robot recovery » opened from « Import an external Garage Key », over the Garage on internal key 0.
  Future<void> openRecovery(WidgetTester tester) async {
    keystoreHolding({});
    final words = TestWordsPort();
    await tester.runAsync(
      () => words.precompute([(RobosatsNetwork.testnet, 0)]),
    );
    await openGarage(tester, words: words);
    await tester.ensureVisible(find.text('Import an external Garage Key'));
    await tester.pump();
    await tester.tap(find.text('Import an external Garage Key'));
    await settle(tester);
  }

  // Restored from `main` (review of #292): the paste field, which « Robot recovery » keeps, played there now that the wizard is gone.
  group('the paste field of « Robot recovery »', () {
    testWidgets('has no text menu, no selection and no autofill', (
      tester,
    ) async {
      await openRecovery(tester);
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(GarageKeyField),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enableInteractiveSelection, isFalse);
      expect(field.autofillHints, isNull);
      expect(
        field.contextMenuBuilder?.call(
          tester.element(recoveryInput()),
          tester.state<EditableTextState>(recoveryInput()),
        ),
        isA<SizedBox>(),
      );
      await tester.enterText(recoveryInput(), exampleText);
      await settle(tester);
      await tester.longPress(recoveryInput());
      await settle(tester);
      await tester.tap(recoveryInput());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(recoveryInput());
      await settle(tester);
      final state = tester.state<EditableTextState>(recoveryInput());
      expect(state.widget.selectionEnabled, isFalse);
      expect(state.textEditingValue.selection.isCollapsed, isTrue);
      expect(state.selectionOverlay?.toolbarIsVisible ?? false, isFalse);
      expect(state.selectionOverlay?.handlesAreVisible ?? false, isFalse);
      final items = state.contextMenuButtonItems;
      expect(
        items.map((item) => item.type),
        isNot(contains(ContextMenuButtonType.share)),
      );
      expect(items.map((item) => item.label), isNot(contains('Translate')));
      for (final item in items.where(
        (item) =>
            item.type == ContextMenuButtonType.copy ||
            item.type == ContextMenuButtonType.cut,
      )) {
        item.onPressed?.call();
      }
      await settle(tester);
      expect(clipboardWrites, isEmpty);
      expect(
        tester.widget<EditableText>(recoveryInput()).controller.text ==
            exampleText,
        isTrue,
      );
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('Paste reads the clipboard once, cleans and checks it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openRecovery(tester);
      expect(clipboardReads, 0);
      expect(
        tester.getSemantics(find.byTooltip('Paste')),
        isSemantics(tooltip: 'Paste', isButton: true, hasTapAction: true),
      );
      clipboard = 'not a key';
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(clipboardReads, 1);
      expect(find.text('Must start with "robo1"'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await settle(tester);
      expect(
        tester.widget<EditableText>(recoveryInput()).controller.text,
        isEmpty,
      );
      // A key copied with spaces and capitals: cleaned as if it were typed.
      clipboard = exampleText.toUpperCase().replaceAllMapped(
        RegExp('.{8}'),
        (match) => '${match[0]} ',
      );
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(clipboardReads, 2);
      final controller = tester
          .widget<EditableText>(recoveryInput())
          .controller;
      expect(controller.text == exampleText, isTrue);
      expectKeyOnlyInView(tester);
      await tester.tap(find.text('Recover'));
      await letTheVaultSettle(tester);
      expect(find.text(exampleNickname), findsOneWidget);
      expect(clipboardReads, 2);
      semantics.dispose();
    });

    testWidgets('a pasted key is never sent to the keyboard', (tester) async {
      await openRecovery(tester);
      await tester.tap(recoveryInput());
      await settle(tester);
      tester.testTextInput.log.clear();
      clipboard = exampleText;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(
        tester.widget<EditableText>(recoveryInput()).controller.text ==
            exampleText,
        isTrue,
      );
      expect(
        tester
            .state<EditableTextState>(recoveryInput())
            .widget
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(
        tester.testTextInput.log.any(
          (call) => '${call.arguments}'.contains(exampleText.substring(5, 30)),
        ),
        isFalse,
      );
    });

    testWidgets('a field focused again during the paste gets nothing', (
      tester,
    ) async {
      await openRecovery(tester);
      clipboard = exampleText;
      await tester.tap(recoveryInput());
      await settle(tester);
      tester.testTextInput.log.clear();
      await tester.tap(find.byTooltip('Paste'));
      for (var i = 0; i < 20; i++) {
        await Future<void>.value();
      }
      final focus = tester
          .state<EditableTextState>(recoveryInput())
          .widget
          .focusNode;
      final controller = tester
          .widget<EditableText>(recoveryInput())
          .controller;
      expect(focus.hasFocus, isFalse);
      expect(controller.text.isEmpty, isTrue);
      focus.requestFocus();
      await settle(tester);
      expect(focus.hasFocus, isTrue);
      expect(controller.text.isEmpty, isTrue);
      expect(
        tester.testTextInput.log.any(
          (call) => '${call.arguments}'.contains(exampleText.substring(5, 30)),
        ),
        isFalse,
      );
    });

    testWidgets('a pasted text is bounded as a typed one', (tester) async {
      await openRecovery(tester);
      clipboard = 'a' * 300;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(
        tester.widget<EditableText>(recoveryInput()).controller.text,
        'a' * GarageKeyField.maxLength,
      );
    });

    testWidgets('an empty or unreadable clipboard changes nothing', (
      tester,
    ) async {
      await openRecovery(tester);
      await tester.enterText(recoveryInput(), 'robo1');
      await settle(tester);
      clipboard = '   ';
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      clipboardUnreadable = true;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(
        tester.widget<EditableText>(recoveryInput()).controller.text,
        'robo1',
      );
    });
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
Future<void> schema9Book(File file, GarageKey key) async {
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
