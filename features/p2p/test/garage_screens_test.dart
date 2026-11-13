import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton;
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
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/list_robot_hosts_usecase.dart';
import 'package:p2p/src/domain/book_requests_in_flight.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
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
import 'package:p2p/src/ui/garage/delete_garage_key_dialog.dart';
import 'package:p2p/src/ui/garage/garage_key_history_notice.dart';
import 'package:p2p/src/ui/garage/garage_view.dart';
import 'package:p2p/src/ui/garage/garage_wizard.dart';
import 'package:p2p/src/ui/garage/robot_coordinator_panel.dart';
import 'package:p2p/src/ui/garage/robot_history_dialog.dart';
import 'package:p2p/src/ui/garage/select_host_sheet.dart';
import 'package:p2p/src/ui/garage/send_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:p2p/src/ui/widgets/garage_key_field.dart';
import 'package:p2p/src/ui/widgets/garage_key_view.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart' show Failure;
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/book_attempts.dart';
import 'support/fakes.dart';
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
  }) async {
    usePhoneScreen(tester);
    storage.install();
    transport = FakeTransport(network: network.state);
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: withGarage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
      databaseUnavailable: databaseUnavailable,
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
  }) async {
    await openTab(tester, locale: locale);
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

    testWidgets('shows nothing but a retry when the protection is refused', (
      tester,
    ) async {
      keystoreHolding({});
      protection = () async => false;
      await openTab(tester, locale: const Locale('fr'));
      await tester.tap(find.text('Garage'));
      await letTheVaultSettle(tester);

      expect(
        find.text(
          'La protection de l’écran n’a pas pu être activée : la clé de garage reste masquée.',
        ),
        findsOneWidget,
      );
      expect(find.text('Commencer'), findsNothing);

      // The Garage is built only once the protection is on: until then it read nothing.
      expect(storage.reads, 0);

      protection = () async => true;
      await tester.tap(find.text('Réessayer'));
      await settle(tester);
      await letTheVaultSettle(tester);

      expect(find.text('Commencer'), findsOneWidget);
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

  testWidgets('« I have a Garage Key » opens the Garage from the book', (
    tester,
  ) async {
    network.switchTo(RobosatsNetwork.mainnet);
    keystoreHolding({_mainnetEntry: null});
    await openTab(tester);
    tor.add(P2pTorState.ready);
    await settle(tester);
    await tester.tap(find.text('Search'));
    await settle(tester);
    final temple = hostOf('temple', RobosatsNetwork.mainnet);
    await tester.enterText(
      find.byType(TextField),
      'http://$temple/order/temple/1/',
    );
    await tester.tap(find.text('Search').last);
    await settle(tester);

    await tester.tap(find.text('I have a Garage Key'));
    await settle(tester);
    await letTheVaultSettle(tester);

    expect(find.byType(GarageView), findsOneWidget);
    expect(find.text(fixedNickname), findsOneWidget);
  });

  group('the welcome screen', () {
    for (final (locale, texts) in [
      (
        const Locale('en'),
        [
          'A Simple and Private LN P2P Exchange',
          'Create a new robot and learn to use RoboSats',
          'Start',
          'Recover an existing robot using your token',
          'Recovery',
          'Search for Orders',
          'Fast Generate Order',
        ],
      ),
      (
        const Locale('fr'),
        [
          "Une bourse d'échange P2P LN simple et privée",
          'Créer un nouveau robot et apprendre à utiliser RoboSats',
          'Commencer',
          "Récupérer un robot existant à l'aide de votre clé de garage",
          'Récupération',
          'Rechercher des ordres',
          'Générer un ordre rapidement',
        ],
      ),
    ]) {
      testWidgets('in ${locale.languageCode}: the official order', (
        tester,
      ) async {
        keystoreHolding({_mainnetEntry: null});
        await openGarage(tester, locale: locale);

        for (final text in texts) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        final tops = [
          for (final text in texts) tester.getTopLeft(find.text(text)).dy,
        ];
        expect(tops, orderedEquals([...tops]..sort()));
        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text(texts.last),
                  matching: find.byWidgetPredicate((w) => w is TextButton),
                ),
              )
              .onPressed,
          isNull,
        );
      });
    }

    testWidgets('« Search for Orders » shows the offers', (tester) async {
      keystoreHolding({});
      await openGarage(tester);

      await tester.tap(find.text('Search for Orders'));
      await settle(tester);

      expect(find.byType(GarageView), findsNothing);
      expect(find.text('Start'), findsNothing);
    });
  });

  group('the wizard', () {
    testWidgets('generates a key, shows it for backup, then its robot', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      keystoreHolding({_mainnetEntry: null});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);

      expect(find.text('1. Generate your Garage Key'), findsOneWidget);
      expect(find.text('2. Meet your robot identity'), findsOneWidget);
      expect(find.text('3. Browse or create an order'), findsOneWidget);
      expect(find.byType(GarageKeyView), findsNothing);

      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);

      expect(
        find.textContaining('Store it somewhere safe!', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(GarageKeyView), findsOneWidget);
      expect(reauthentications, 0);
      expect(storage.entries.keys.toSet(), {_mainnetEntry, _testnetEntry});
      expect(storage.entries[_mainnetEntry], storedFixedKeys[_mainnetEntry]);
      final generated = switch (GarageKey.parse(shownKey(tester))) {
        Ok(:final value) => value,
        Err() => fail('not a key'),
      };
      expect(generated, isNot(fixedKey));
      expectKeyOnlyInView(tester);

      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(find.byType(GarageKeyView), findsNothing);
      expect(find.text('This is your trading avatar'), findsOneWidget);
      expect(find.text('Hi! My name is'), findsOneWidget);
      final nickname = switch (generated.deriveIdentity(0)) {
        Ok(:final value) => value.nickname,
        Err() => fail('no robot'),
      };
      expect(find.text(nickname), findsOneWidget);
      expect(find.text('Robot #0'), findsOneWidget);
      // Its draw was recorded: nothing to say about its history.
      expect(find.byType(GarageKeyHistoryNotRecorded), findsNothing);
      expectKeyOnlyInView(tester);
      semantics.dispose();
    });

    testWidgets('moves from robot to robot, never below robot 0', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Next account'));
      await settle(tester);
      expect(find.text('Robot #1'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous account'));
      await settle(tester);
      expect(find.text('Robot #0'), findsOneWidget);
    });

    testWidgets(
      'step 3: search shows the offers, create is disabled, links are copied',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('Continue'));
        await settle(tester);

        expect(
          find.text(
            'RoboSats is a peer-to-peer marketplace. You can browse the public offers or create a new one.',
          ),
          findsOneWidget,
        );
        // The link is a span of the help sentence.
        await tester.tapOnText(find.textRange.ofSubstring('SimpleX group'));
        await settle(tester);
        expect(find.textContaining('simplex.chat'), findsOneWidget);
        await tester.tap(find.byTooltip('Copy'));
        await settle(tester);
        expect(clipboard, startsWith('https://simplex.chat/contact/'));
        await tester.tapAt(const Offset(20, 20));
        await settle(tester);

        await tester.tap(find.text('Learn RoboSats'));
        await settle(tester);
        expect(find.text('https://learn.robosats.org'), findsOneWidget);
        await tester.tapAt(const Offset(20, 20));
        await settle(tester);

        await tester.tap(find.text('See profile'));
        await settle(tester);
        expect(find.text('Show Garage Key'), findsOneWidget);
        expect(find.byType(GarageKeyView), findsNothing);

        await tester.tap(find.text('Offers'));
        await settle(tester);
        await tester.tap(find.text('Garage'));
        await letTheVaultSettle(tester);
        expect(find.text('Show Garage Key'), findsOneWidget);
      },
    );

    testWidgets('« Search » on step 3 shows the offers', (tester) async {
      keystoreHolding({});
      await openGarage(tester, locale: const Locale('fr'));
      await tester.tap(find.text('Commencer'));
      await settle(tester);
      await tester.tap(find.text('Générer une clé de garage'));
      await letTheVaultSettle(tester);
      await tester.tap(find.text('Continuer'));
      await settle(tester);
      await tester.tap(find.text('Continuer'));
      await settle(tester);

      expect(find.text('3. Consulter ou créer un ordre'), findsOneWidget);
      expect(find.text('Voir le profil'), findsOneWidget);
      await tester.tap(find.text('Rechercher'));
      await settle(tester);

      expect(find.byType(GarageView), findsNothing);
    });

    testWidgets('« Generate new » asks before deleting the stored key', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      final first = shownKey(tester);
      final stored = storage.entries[_testnetEntry];

      await tester.tap(find.text('Generate new'));
      await settle(tester);
      expect(find.byType(DeleteGarageKeyDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(storage.entries[_testnetEntry], stored);
      expect(shownKey(tester) == first, isTrue);

      await tester.tap(find.text('Generate new'));
      await settle(tester);
      await tester.tap(find.text('Delete Garage Key'));
      await letTheVaultSettle(tester);

      expect(find.byType(GarageKeyView), findsOneWidget);
      expect(shownKey(tester) == first, isFalse);
      expect(storage.entries[_testnetEntry], isNot(stored));
      // Drawn here and recorded so: no PIN, as in RoboSats.
      expect(reauthentications, 0);
    });

    testWidgets('takes a pasted key, cleaned, refused until it is one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(GarageKeyField),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      final input = find.descendant(
        of: find.byType(GarageKeyField),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input, 'bad');
      await settle(tester);
      expect(find.text('Must start with "robo1"'), findsOneWidget);
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await letTheVaultSettle(tester);
      expect(storage.entries, isEmpty);
      expect(find.text('Robot #0'), findsNothing);
      // « Continue » is disabled: the text never reached the cubit, which would say why under « Generate Garage Key ».
      expect(find.text('Must start with "robo1"'), findsOneWidget);

      await tester.enterText(input, 'robo1abc');
      await settle(tester);
      expect(find.text('Invalid length'), findsOneWidget);

      // An invisible and a bidirectional mark are not whitespace: the text is refused, never silently changed.
      final marked =
          '${exampleText.substring(0, 10)}${String.fromCharCodes([0x200B, 0x202E])}${exampleText.substring(10)}';
      await tester.enterText(input, marked);
      await settle(tester);
      expect(find.text('Invalid garage key'), findsOneWidget);

      // Spaces and capitals, as a key copied from paper: cleaned as the official client cleans it.
      final spaced = exampleText.toUpperCase().replaceAllMapped(
        RegExp('.{8}'),
        (match) => '${match[0]} ',
      );
      await tester.enterText(input, spaced);
      await settle(tester);
      expect(
        tester.widget<EditableText>(input).controller.text == exampleText,
        isTrue,
      );
      expect(find.text('Store your Garage Key safely'), findsOneWidget);
      expectKeyOnlyInView(tester);

      await tester.tap(find.text('Continue'));
      await letTheVaultSettle(tester);

      expect(find.text(exampleNickname), findsOneWidget);
      expect(find.text('Robot #0'), findsOneWidget);
      expect(storage.entries.keys, [_testnetEntry]);
      semantics.dispose();
    });
  });

  group('the copied key', () {
    testWidgets('is cleared after 30 seconds if the clipboard still holds it', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      final key = shownKey(tester);

      await tester.tap(find.byTooltip('Copy'));
      await settle(tester);
      expect(clipboard == key, isTrue);
      expect(find.byTooltip('Copied!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 29));
      expect(clipboard == key, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);

      expect(clipboard, '');
      expect(locator<GarageKeyClipboard>().isArmed, isFalse);
    });

    testWidgets('is cleared even after the Garage is left', (tester) async {
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      await tester.tap(find.byTooltip('Copy'));
      await settle(tester);

      await tester.tap(find.text('Offers'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      expect(clipboard, '');
    });

    testWidgets('is left alone once the user copied something else', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      await tester.tap(find.byTooltip('Copy'));
      await settle(tester);

      clipboard = 'a shopping list';
      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      expect(clipboard, 'a shopping list');
    });
  });

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
    ]) {
      testWidgets(
        'in ${locale.languageCode}: Delete All asks, then the PIN, then deletes this network only',
        (tester) async {
          keystoreHolding({_testnetEntry: null, _mainnetEntry: null});
          await openGarage(tester, locale: locale);
          final deleteAll = locale.languageCode == 'fr'
              ? 'Tout supprimer'
              : 'Delete All';

          await tapDeleteAll(tester, label: deleteAll);
          await settle(tester);
          for (final text in texts) {
            expect(find.text(text), findsOneWidget, reason: text);
          }
          // No PIN before the confirmation, nor after « Cancel ».
          expect(reauthentications, 0);
          await tester.tap(find.text(texts.last));
          await settle(tester);
          expect(reauthentications, 0);
          expect(storage.entries.keys.toSet(), {_testnetEntry, _mainnetEntry});

          await tapDeleteAll(tester, label: deleteAll);
          await settle(tester);
          await tester.tap(find.text(texts[texts.length - 2]));
          await afterRoute(tester);

          // The fixed key has no record of being drawn here: a robot of it may live on a coordinator, so the PIN comes after the confirmation, before anything is deleted.
          expect(find.byType(DeleteGarageKeyDialog), findsNothing);
          expect(reauthentications, 1);
          expect(storage.entries.keys.toSet(), {_testnetEntry, _mainnetEntry});
          await tester.tap(find.text('PIN ok'));
          await afterRoute(tester);

          expect(storage.entries, {
            _mainnetEntry: storedFixedKeys[_mainnetEntry],
          });
          expect(find.text(fixedNickname), findsNothing);
          expect(find.byType(DeleteGarageKeyDialog), findsNothing);
          expect(
            find.text(locale.languageCode == 'fr' ? 'Commencer' : 'Start'),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('says so when the key could not be deleted', (tester) async {
      keystoreHolding(
        {_testnetEntry: null},
        scriptedWrites: [PlatformException(code: 'delete failed')],
      );
      await openGarage(tester);

      await tapDeleteAll(tester);
      await settle(tester);
      await tester.tap(find.text('Delete Garage Key'));
      await afterRoute(tester);
      await tester.tap(find.text('PIN ok'));
      await afterRoute(tester);

      expect(
        find.text('The Garage Key could not be deleted. Try again.'),
        findsOneWidget,
      );
      expect(find.text(fixedNickname), findsOneWidget);
      expect(storage.entries, {_testnetEntry: storedFixedKeys[_testnetEntry]});
    });
  });

  group('a key the vault cannot read', () {
    testWidgets('locked: retry only, nothing deleted', (tester) async {
      keystoreHolding({_testnetEntry: null}, locked: true);
      await openGarage(tester, locale: const Locale('fr'));

      expect(
        find.text(
          'Le coffre de l’appareil est verrouillé. Déverrouillez votre appareil, puis réessayez.',
        ),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Supprimer la clé de garage'), findsNothing);
      expect(find.text('Commencer'), findsNothing);

      storage
        ..locked = false
        ..writesFail = false;
      await tester.tap(find.text('Réessayer'));
      await letTheVaultSettle(tester);

      expect(find.text(fixedNickname), findsOneWidget);
    });

    testWidgets('damaged: delete with the warning, then the welcome', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: 'not json at all'});
      await openGarage(tester);

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
      await tester.tap(find.text('Delete Garage Key'));
      await settle(tester);
      expect(find.byType(DeleteGarageKeyDialog), findsOneWidget);
      expect(reauthentications, 0);
      await tester.tap(find.text('Delete Garage Key').last);
      await afterRoute(tester);
      // A slot that cannot be read always asks the PIN, after the confirmation.
      expect(reauthentications, 1);
      expect(storage.entries.keys, [_testnetEntry]);
      await tester.tap(find.text('PIN ok'));
      await afterRoute(tester);

      expect(storage.entries, isEmpty);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('unreadable: said so, kept as it is', (tester) async {
      keystoreHolding({
        _testnetEntry: null,
      }, scripted: List.generate(5, (_) => PlatformException(code: 'read')));
      await openGarage(tester);

      expect(
        find.text('The Garage Key stored on this device cannot be read.'),
        findsOneWidget,
      );
      expect(storage.entries, {_testnetEntry: storedFixedKeys[_testnetEntry]});
    });
  });

  group('« Robot recovery »', () {
    testWidgets('stores a pasted key, then shows the profile, the key hidden', (
      tester,
    ) async {
      keystoreHolding({});
      await openGarage(tester, locale: const Locale('fr'));

      await tester.tap(find.text('Récupération'));
      await settle(tester);
      expect(find.text('Récupération du robot'), findsOneWidget);
      expect(find.text('Mode clé de garage'), findsOneWidget);
      expect(
        find.text(
          'Saisissez votre clé de garage (robo1...) pour récupérer tous vos comptes robot.',
        ),
        findsOneWidget,
      );
      final input = find.descendant(
        of: find.byType(GarageKeyField),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input, 'robo1');
      await settle(tester);
      expect(find.text('Longueur invalide'), findsOneWidget);
      await tester.tap(find.text('Récupérer'));
      await settle(tester);
      expect(storage.entries, isEmpty);

      await tester.enterText(input, exampleText);
      await settle(tester);
      await tester.tap(find.text('Récupérer'));
      await letTheVaultSettle(tester);

      expect(find.text('Récupération du robot'), findsNothing);
      expect(find.text(exampleNickname), findsOneWidget);
      expect(find.text('Afficher la clé de garage'), findsOneWidget);
      expect(find.byType(GarageKeyView), findsNothing);
      expect(storage.entries.keys, [_testnetEntry]);
    });
  });

  group('a change of network', () {
    testWidgets('shows the key of the other network, never its robot', (
      tester,
    ) async {
      keystoreHolding({_testnetEntry: null});
      await openGarage(tester);
      expect(find.text(fixedNickname), findsOneWidget);

      network.switchTo(RobosatsNetwork.mainnet);
      await settle(tester);
      await letTheVaultSettle(tester);

      expect(find.text(fixedNickname), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(storage.entries, {_testnetEntry: storedFixedKeys[_testnetEntry]});

      network.switchTo(RobosatsNetwork.testnet);
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(find.text(fixedNickname), findsOneWidget);
    });
  });

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

  group('the paste field', () {
    testWidgets('has no text menu, no selection and no autofill', (
      tester,
    ) async {
      await openWizard(tester);
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
          tester.element(pasteInput()),
          tester.state<EditableTextState>(pasteInput()),
        ),
        isA<SizedBox>(),
      );

      await tester.enterText(pasteInput(), exampleText);
      await settle(tester);
      // What a user does to select text and open its menu.
      await tester.longPress(pasteInput());
      await settle(tester);
      await tester.tap(pasteInput());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(pasteInput());
      await settle(tester);

      final state = tester.state<EditableTextState>(pasteInput());
      expect(state.widget.selectionEnabled, isFalse);
      expect(state.textEditingValue.selection.isCollapsed, isTrue);
      expect(state.selectionOverlay?.toolbarIsVisible ?? false, isFalse);
      expect(state.selectionOverlay?.handlesAreVisible ?? false, isFalse);
      // With selection off, Flutter still lists the deprecated toolbar options (cut, copy, paste), which the user cannot reach: no selection, and an empty menu.
      // Nothing that hands the text to another app is offered, and cut or copy without a selection copy nothing.
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
        tester.widget<EditableText>(pasteInput()).controller.text ==
            exampleText,
        isTrue,
      );
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Translate'), findsNothing);

      // The keyboard's own selection, through the input connection, is not Flutter's to refuse: with it the text actions do appear, which shows the check above has teeth; and no menu shows them.
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: exampleText,
          selection: TextSelection(
            baseOffset: 0,
            extentOffset: exampleText.length,
          ),
        ),
      );
      await settle(tester);
      expect(
        state.contextMenuButtonItems.map((item) => item.label),
        contains('Translate'),
      );
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('Paste reads the clipboard once, cleans and checks it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openWizard(tester);
      expect(clipboardReads, 0);
      // Reachable by a screen reader, unlike the text of the field.
      expect(
        tester.getSemantics(find.byTooltip('Paste')),
        isSemantics(tooltip: 'Paste', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byTooltip('Clear')),
        isSemantics(tooltip: 'Clear', isButton: true),
      );

      clipboard = 'not a key';
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      expect(clipboardReads, 1);
      expect(find.text('Must start with "robo1"'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear'));
      await settle(tester);
      expect(
        tester.widget<EditableText>(pasteInput()).controller.text,
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
      final controller = tester.widget<EditableText>(pasteInput()).controller;
      expect(controller.text == exampleText, isTrue);
      expectKeyOnlyInView(tester);

      await tester.tap(find.text('Continue'));
      await letTheVaultSettle(tester);

      expect(find.text(exampleNickname), findsOneWidget);
      // The pasted text does not outlive the import.
      expect(controller.text, isEmpty);
      expect(clipboardReads, 2);
      semantics.dispose();
    });

    testWidgets('a pasted key is never sent to the keyboard', (tester) async {
      await openWizard(tester);
      await tester.tap(pasteInput());
      await settle(tester);
      expect(
        tester.state<EditableTextState>(pasteInput()).widget.focusNode.hasFocus,
        isTrue,
      );
      tester.testTextInput.log.clear();

      clipboard = exampleText;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);

      expect(
        tester.widget<EditableText>(pasteInput()).controller.text ==
            exampleText,
        isTrue,
      );
      expect(
        tester.state<EditableTextState>(pasteInput()).widget.focusNode.hasFocus,
        isFalse,
      );
      // A boolean, so that a failure does not print the key it found.
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
      await openWizard(tester);
      clipboard = exampleText;
      await tester.tap(pasteInput());
      await settle(tester);
      tester.testTextInput.log.clear();

      await tester.tap(find.byTooltip('Paste'));
      // Microtasks only, no timer: the clipboard is read and the focus leaves, and the write waits for its zero-length timer.
      // `tester.idle()` would not do: it fires the zero-length timers too, so the write would come before the tap below.
      for (var i = 0; i < 20; i++) {
        await Future<void>.value();
      }
      final focus = tester
          .state<EditableTextState>(pasteInput())
          .widget
          .focusNode;
      final controller = tester.widget<EditableText>(pasteInput()).controller;
      expect(focus.hasFocus, isFalse);
      expect(controller.text.isEmpty, isTrue);
      // A tap on the field lands in that turn, before the write.
      focus.requestFocus();
      await settle(tester);

      expect(focus.hasFocus, isTrue);
      // Booleans, so that a failure does not print the key it found.
      expect(controller.text.isEmpty, isTrue);
      expect(
        tester.testTextInput.log.any(
          (call) => '${call.arguments}'.contains(exampleText.substring(5, 30)),
        ),
        isFalse,
      );
    });

    testWidgets('a pasted text is bounded as a typed one', (tester) async {
      await openWizard(tester);

      clipboard = 'a' * 300;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);

      expect(
        tester.widget<EditableText>(pasteInput()).controller.text,
        'a' * GarageKeyField.maxLength,
      );
    });

    testWidgets('an empty or unreadable clipboard changes nothing', (
      tester,
    ) async {
      await openWizard(tester);
      await tester.enterText(pasteInput(), 'robo1');
      await settle(tester);

      clipboard = '   ';
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);
      clipboardUnreadable = true;
      await tester.tap(find.byTooltip('Paste'));
      await settle(tester);

      expect(
        tester.widget<EditableText>(pasteInput()).controller.text,
        'robo1',
      );
    });
  });

  testWidgets('no request reaches a coordinator from the Garage', (
    tester,
  ) async {
    keystoreHolding({});
    await openTab(tester);
    tor.add(P2pTorState.ready);
    await letTheVaultSettle(tester);
    final before = transport.requested.length;
    // The book did ask: the fake sees requests.
    expect(before, isPositive);

    await tester.tap(find.text('Garage'));
    await settle(tester);
    await letTheVaultSettle(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
    await tester.tap(find.text('Generate Garage Key'));
    await letTheVaultSettle(tester);
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump(const Duration(seconds: 31));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.byTooltip('Next account'));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.text('Learn RoboSats'));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tapOnText(find.textRange.ofSubstring('SimpleX group'));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tap(find.text('See profile'));
    await settle(tester);
    await tester.tap(find.text('Show Garage Key'));
    await afterRoute(tester);
    await tester.tap(find.text('PIN ok'));
    await afterRoute(tester);
    await tapDeleteAll(tester);
    await settle(tester);
    await tester.tap(find.text('Delete Garage Key'));
    await settle(tester);
    await tester.tap(find.text('Recovery'));
    await settle(tester);
    await tester.enterText(pasteInput(), exampleText);
    await settle(tester);
    await tester.tap(find.text('Recover'));
    await letTheVaultSettle(tester);
    expect(find.text(exampleNickname), findsOneWidget);

    expect(transport.requested.length, before);
  });

  testWidgets('a key that appears in the slot before Generate stays hidden', (
    tester,
  ) async {
    await openWizard(tester);
    // Another screen of the app could not do it, but the vault's own rule is what keeps it safe: the slot is read again.
    storage.entries[_testnetEntry] = storedFixedKeys[_testnetEntry] ?? '';

    await tester.tap(find.text('Generate Garage Key'));
    await letTheVaultSettle(tester);

    expect(reauthentications, 0);
    expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
    expect(find.text('Show Garage Key'), findsOneWidget);
    expect(find.text(fixedNickname), findsOneWidget);
  });

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

  group('a key shown for backup', () {
    testWidgets(
      'right after the draw, is hidden when the app goes to the background',
      (tester) async {
        await openWizard(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);
        expect(reauthentications, 0);

        await backgroundAndBack(tester);

        // Still the backup step, the key now behind the PIN as on the profile.
        expect(backupAlert(), findsOneWidget);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(find.text('Continue'), findsNothing);
        await tester.tap(find.text('Show Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN back'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsNothing);
        await tester.tap(find.text('Show Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);

        // Shown after the PIN, and hidden again in the background.
        await backgroundAndBack(tester);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(backupAlert(), findsOneWidget);
      },
    );

    testWidgets('drawn while the app was hidden, is behind the PIN on return', (
      tester,
    ) async {
      await openWizard(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await tester.pump();
      // The user presses Home or locks the phone while the vault draws; it answers in the background, and an hour passes.
      await toBackground(tester);
      await letTheVaultSettle(tester);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(minutes: 1));
      }
      await backToForeground(tester);

      expect(storage.entries.keys, [_testnetEntry]);
      expect(backupAlert(), findsOneWidget);
      expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      expect(find.text('Show Garage Key'), findsOneWidget);
      expect(reauthentications, 0);
    });

    testWidgets(
      'Generate new at a later visit, the app hidden meanwhile, is behind the PIN',
      (tester) async {
        await openWizard(tester, slowWrites: true);
        await tester.tap(find.text('Generate Garage Key'));
        await settle(tester);
        await tester.tap(find.text('Offers'));
        await tester.pump();
        await letTheVaultSettle(tester);
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);
        expect(find.text('Show Garage Key'), findsOneWidget);
        final first = storage.entries[_testnetEntry];

        await tester.tap(find.text('Generate new'));
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // While the vault works, the Garage shows its wait, not the wizard.
        expect(find.text('1. Generate your Garage Key'), findsNothing);
        await toBackground(tester);
        await letTheVaultSettle(tester);
        await backToForeground(tester);

        expect(storage.entries[_testnetEntry], isNot(first));
        expect(backupAlert(), findsOneWidget);
        expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
        expect(reauthentications, 0);
      },
    );

    testWidgets(
      'hidden between its arrival and its first frame, is behind the PIN',
      (tester) async {
        await openWizard(tester, slowWrites: true);
        await tester.tap(find.text('Generate Garage Key'));
        await tester.pump();
        // The write lands and the key is read back, with no frame drawn yet; the app is hidden before the next frame.
        await tester.binding.delayed(const Duration(seconds: 6));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);

        expect(backupAlert(), findsOneWidget);
        expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      },
    );

    testWidgets('drawn while the user left, is behind the PIN hours later', (
      tester,
    ) async {
      await openWizard(tester, slowWrites: true);
      await tester.tap(find.text('Generate Garage Key'));
      await settle(tester);
      // The key is being written: the user leaves before the vault answers.
      expect(storage.entries, isEmpty);
      await tester.tap(find.text('Offers'));
      // The Garage is gone before the vault answers.
      await tester.pump();
      await letTheVaultSettle(tester);
      expect(storage.entries.keys, [_testnetEntry]);
      // Two hours, and a trip to the background.
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(minutes: 1));
      }
      await backgroundAndBack(tester);

      await tester.tap(find.text('Garage'));
      await settle(tester);
      await letTheVaultSettle(tester);

      expect(backupAlert(), findsOneWidget);
      expect(find.byType(GarageKeyView, skipOffstage: false), findsNothing);
      expect(reauthentications, 0);
      await tester.tap(find.text('Show Garage Key'));
      await afterRoute(tester);
      await tester.tap(find.text('PIN ok'));
      await afterRoute(tester);
      expect(find.byType(GarageKeyView), findsOneWidget);
      final stored = switch (GarageKey.parse(shownKey(tester))) {
        Ok(:final value) => value,
        Err() => fail('not a key'),
      };
      expect(stored, isNot(fixedKey));

      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Robot #0'), findsOneWidget);

      // Acknowledged: the next visit is the profile, without the alert.
      await tester.tap(find.text('Offers'));
      await settle(tester);
      await tester.tap(find.text('Garage'));
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(backupAlert(), findsNothing);
      expect(find.byType(GarageKeyView), findsNothing);
      expect(find.text('Show Garage Key'), findsOneWidget);
    });

    testWidgets(
      'seen but not acknowledged, keeps its alert at the next visit',
      (tester) async {
        await openWizard(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        expect(find.byType(GarageKeyView), findsOneWidget);

        await tester.tap(find.text('Offers'));
        await settle(tester);
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);

        expect(backupAlert(), findsOneWidget);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(find.text('Show Garage Key'), findsOneWidget);
      },
    );

    testWidgets('of one network, gives no alert on the other', (tester) async {
      await openWizard(tester, held: {_mainnetEntry: null});
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      expect(find.byType(GarageKeyView), findsOneWidget);

      network.switchTo(RobosatsNetwork.mainnet);
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(backupAlert(), findsNothing);
      expect(find.text(fixedNickname), findsOneWidget);

      network.switchTo(RobosatsNetwork.testnet);
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(backupAlert(), findsOneWidget);
      expect(find.byType(GarageKeyView), findsNothing);
    });

    testWidgets('deleted, gives no alert any more', (tester) async {
      await openWizard(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('See profile'));
      await settle(tester);
      await tapDeleteAll(tester);
      await settle(tester);
      await tester.tap(find.text('Delete Garage Key'));
      await settle(tester);
      expect(find.text('Start'), findsOneWidget);
      expect(storage.entries, isEmpty);
      // Drawn here and recorded so, with no robot bound: the confirmation alone, as in RoboSats.
      expect(reauthentications, 0);

      // A key generated anew is the one of a new draw, shown without the PIN, and a key generated elsewhere gives no alert.
      storage.entries[_testnetEntry] = storedFixedKeys[_testnetEntry] ?? '';
      await tester.tap(find.text('Offers'));
      await settle(tester);
      await tester.tap(find.text('Garage'));
      await settle(tester);
      await letTheVaultSettle(tester);
      expect(backupAlert(), findsNothing);
      expect(find.text('Show Garage Key'), findsOneWidget);
    });
  });

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

  group('the PIN before a delete', () {
    testWidgets(
      'a key with a robot bound: the PIN after the confirmation, before anything is deleted',
      (tester) async {
        await openGarageAfter(tester, bindFixedRobot);

        await tapDeleteAll(tester);
        await settle(tester);
        expect(find.byType(DeleteGarageKeyDialog), findsOneWidget);
        expect(reauthentications, 0);
        await tester.tap(find.text('Delete Garage Key'));
        await afterRoute(tester);

        expect(find.text('PIN ok'), findsOneWidget);
        expect(find.byType(DeleteGarageKeyDialog), findsNothing);
        expect(reauthentications, 1);
        expect(storage.entries.keys, [_testnetEntry]);

        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);

        expect(storage.entries, isEmpty);
        expect(find.text('Start'), findsOneWidget);
        expect(reauthentications, 1);
      },
    );

    testWidgets(
      'a robot bound on the other network asks the PIN as well, in French',
      (tester) async {
        await openGarageAfter(
          tester,
          () => bindFixedRobot(network: RobosatsNetwork.mainnet),
          locale: const Locale('fr'),
        );

        await tapDeleteAll(tester, label: 'Tout supprimer');
        await settle(tester);
        await tester.tap(find.text('Supprimer la clé de garage'));
        await afterRoute(tester);

        expect(reauthentications, 1);
        expect(storage.entries.keys, [_testnetEntry]);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(storage.entries, isEmpty);
        expect(find.text('Commencer'), findsOneWidget);
      },
    );

    testWidgets(
      'leaving the PIN deletes nothing and leaves the profile as it was',
      (tester) async {
        await openGarageAfter(tester, bindFixedRobot);
        await tester.tap(find.byTooltip('Next account'));
        await settle(tester);
        expect(find.text('Robot #1'), findsOneWidget);

        await tapDeleteAll(tester);
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN back'));
        await afterRoute(tester);

        expect(storage.entries.keys, [_testnetEntry]);
        expect(find.text('Robot #1'), findsOneWidget);
        expect(find.text('Show Garage Key'), findsOneWidget);
        expect(find.byType(DeleteGarageKeyDialog), findsNothing);

        // A system back from the PIN deletes nothing either.
        await tapDeleteAll(tester);
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await afterRoute(tester);
        await tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .maybePop();
        await afterRoute(tester);

        expect(reauthentications, 2);
        expect(storage.entries.keys, [_testnetEntry]);
        expect(find.text('Robot #1'), findsOneWidget);
      },
    );

    testWidgets(
      'the app in the background while the PIN is open: still asked, then deleted',
      (tester) async {
        await openGarageAfter(tester, bindFixedRobot);
        await tapDeleteAll(tester);
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await afterRoute(tester);

        await backgroundAndBack(tester);

        expect(find.text('PIN ok'), findsOneWidget);
        expect(storage.entries.keys, [_testnetEntry]);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        expect(storage.entries, isEmpty);
        expect(reauthentications, 1);
      },
    );

    testWidgets(
      'without the shell\'s re-authentication, a key that may have robots cannot be deleted',
      (tester) async {
        await openGarageAfter(
          tester,
          bindFixedRobot,
          withReauthentication: false,
        );

        expect(deleteAllButton(tester).onPressed, isNull);
        await tapDeleteAll(tester, warnIfMissed: false);
        await settle(tester);

        expect(find.byType(DeleteGarageKeyDialog), findsNothing);
        expect(storage.entries.keys, [_testnetEntry]);
      },
    );

    testWidgets(
      'without the shell\'s re-authentication, a key drawn here is deleted and replaced as in RoboSats',
      (tester) async {
        keystoreHolding({});
        await openTab(tester, withReauthentication: false);
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        final first = storage.entries[_testnetEntry];

        await tester.tap(find.text('Generate new'));
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await letTheVaultSettle(tester);
        expect(storage.entries[_testnetEntry], isNot(first));

        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('See profile'));
        await settle(tester);
        expect(deleteAllButton(tester).onPressed, isNotNull);
        await tapDeleteAll(tester);
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await settle(tester);

        expect(storage.entries, isEmpty);
        expect(reauthentications, 0);
      },
    );

    testWidgets('a damaged key asks the PIN, robots bound or not, in French', (
      tester,
    ) async {
      await openGarageAfter(
        tester,
        () => bindFixedRobot(network: RobosatsNetwork.mainnet),
        held: {_testnetEntry: 'not json at all'},
        locale: const Locale('fr'),
      );
      expect(
        find.text(
          'La clé de garage enregistrée sur cet appareil est endommagée.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Supprimer la clé de garage'));
      await settle(tester);
      await tester.tap(find.text('Supprimer la clé de garage').last);
      await afterRoute(tester);
      expect(reauthentications, 1);
      expect(storage.entries.keys, [_testnetEntry]);
      await tester.tap(find.text('PIN back'));
      await afterRoute(tester);

      expect(storage.entries.keys, [_testnetEntry]);
      expect(
        find.text(
          'La clé de garage enregistrée sur cet appareil est endommagée.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a key that cannot be read: the PIN, even with no robot bound',
      (tester) async {
        await openGarageAfter(
          tester,
          () async {},
          held: {_testnetEntry: 'not json at all'},
        );
        expect(
          find.text('The Garage Key stored on this device is damaged.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Delete Garage Key'));
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key').last);
        await afterRoute(tester);
        expect(reauthentications, 1);
        expect(storage.entries.keys, [_testnetEntry]);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);

        expect(storage.entries, isEmpty);
        expect(find.text('Start'), findsOneWidget);
      },
    );

    testWidgets(
      'a key that cannot be read, without the re-authentication: its delete is disabled',
      (tester) async {
        await openGarageAfter(
          tester,
          () async {},
          held: {_testnetEntry: 'not json at all'},
          withReauthentication: false,
        );

        await tester.tap(find.text('Delete Garage Key'), warnIfMissed: false);
        await settle(tester);

        expect(find.byType(DeleteGarageKeyDialog), findsNothing);
        expect(storage.entries.keys, [_testnetEntry]);
      },
    );

    testWidgets(
      'without the re-authentication, « Generate new » of a key that may have robots is disabled',
      (tester) async {
        keystoreHolding({});
        // The draw cannot be recorded: the key's history is unknown, so its delete needs the PIN.
        await openTab(
          tester,
          withReauthentication: false,
          databaseUnavailable: true,
        );
        await tester.tap(find.text('Garage'));
        await settle(tester);
        await letTheVaultSettle(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        final drawn = storage.entries[_testnetEntry];
        expect(drawn, isNotNull);

        final generateNew = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Generate new'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        );
        expect(generateNew.onPressed, isNull);
        await tester.tap(find.text('Generate new'), warnIfMissed: false);
        await settle(tester);

        expect(find.byType(DeleteGarageKeyDialog), findsNothing);
        expect(storage.entries[_testnetEntry], drawn);
      },
    );
  });

  group('a draw whose history could not be recorded', () {
    for (final (locale, notice, labels) in [
      (
        const Locale('en'),
        'This device could not record that it drew this Garage Key. Its robots will ask for your confirmation before they reach a coordinator. You can generate a new key instead.',
        (
          start: 'Start',
          generate: 'Generate Garage Key',
          generateNew: 'Generate new',
          confirm: 'Delete Garage Key',
          next: 'Continue',
          profile: 'See profile',
        ),
      ),
      (
        const Locale('fr'),
        'Cet appareil n’a pas pu enregistrer qu’il a généré cette clé de garage. Ses robots demanderont votre confirmation avant de rejoindre un coordinateur. Vous pouvez plutôt générer une nouvelle clé.',
        (
          start: 'Commencer',
          generate: 'Générer une clé de garage',
          generateNew: 'Générer une nouvelle',
          confirm: 'Supprimer la clé de garage',
          next: 'Continuer',
          profile: 'Voir le profil',
        ),
      ),
    ]) {
      testWidgets(
        'in ${locale.languageCode}: said on the robot step and the profile, and « Generate new » asks the PIN once',
        (tester) async {
          keystoreHolding({});
          await openTab(tester, locale: locale, databaseUnavailable: true);
          await tester.tap(find.text('Garage'));
          await settle(tester);
          await letTheVaultSettle(tester);
          await tester.tap(find.text(labels.start));
          await settle(tester);
          await tester.tap(find.text(labels.generate));
          await letTheVaultSettle(tester);

          // Stored all the same, and shown for backup without the PIN, right after its draw.
          expect(storage.entries.keys, [_testnetEntry]);
          expect(find.byType(GarageKeyView), findsOneWidget);
          expect(find.text(notice), findsNothing);
          final first = shownKey(tester);

          // Its delete asks the PIN: its history is unknown, and the database cannot say more.
          await tester.tap(find.text(labels.generateNew));
          await settle(tester);
          await tester.tap(find.text(labels.confirm));
          await afterRoute(tester);
          expect(reauthentications, 1);
          expect(storage.entries.keys, [_testnetEntry]);
          await tester.tap(find.text('PIN ok'));
          await letTheVaultSettle(tester);

          expect(reauthentications, 1);
          expect(find.byType(GarageKeyView), findsOneWidget);
          expect(shownKey(tester) == first, isFalse);

          await tester.tap(find.text(labels.next));
          await settle(tester);
          expect(find.text(notice), findsOneWidget);
          expect(find.text('Robot #0'), findsOneWidget);

          await tester.tap(find.text(labels.next));
          await settle(tester);
          await tester.tap(find.text(labels.profile));
          await settle(tester);
          expect(find.text(notice), findsOneWidget);
          expectKeyOnlyInView(tester);

          // At a later visit, the key is the profile's, of unknown history like any key without a record: nothing more is said.
          await tester.tap(
            find.text(locale.languageCode == 'fr' ? 'Offres' : 'Offers'),
          );
          await settle(tester);
          await tester.tap(find.text('Garage'));
          await settle(tester);
          await letTheVaultSettle(tester);
          expect(find.text(notice), findsNothing);
        },
      );
    }
  });

  testWidgets(
    'Continue on a key that does not await its backup goes to the robot',
    (tester) async {
      // The wizard with a key that was pasted: its first step never shows it, whatever step it was asked for.
      final key = NetworkGarageKey(RobosatsNetwork.testnet, fixedKey);
      final robot = switch (key.firstUsableRobot(0)) {
        Ok(:final value) => value,
        Err() => fail('no robot'),
      };
      FakeSecureStoragePlatform().install();
      final repository = GarageKeyRepositoryImpl(
        Secrets(scratchDirectory: () async => '.').garageKeys(),
      );
      final bindings = RecordingBindings();
      final cubit = GarageCubit(
        RobosatsNetwork.testnet,
        ReadGarageKeyUsecase(repository),
        GenerateGarageKeyUsecase(repository, bindings),
        ImportGarageKeyUsecase(repository, bindings),
        DeleteGarageKeyUsecase(repository),
        NeedsPinToDeleteGarageKeyUsecase(bindings),
        UnacknowledgedGarageKeys(),
      );
      addTearDown(cubit.close);
      final clipboardHelper = GarageKeyClipboard();
      addTearDown(clipboardHelper.dispose);
      await tester.pumpWidget(
        harness(
          BlocProvider.value(
            value: cubit,
            child: GarageWizard(
              step: 1,
              state: GarageWithKey(
                RobosatsNetwork.testnet,
                key: key,
                robot: GarageRobotFace.of(robot),
                isNew: true,
              ),
              clipboard: clipboardHelper,
              reauthenticate: reauthenticate,
              onStep: (_) {},
              onSearch: () {},
              onSeeProfile: () {},
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Hi! My name is'), findsOneWidget);
      expect(find.text(fixedNickname), findsOneWidget);
      expect(backupAlert(), findsNothing);
      expect(find.byType(GarageKeyView), findsNothing);
    },
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

    testWidgets(
      'a pasted key: asked once, bound as acknowledged, not for its next robot, and again once pasted again',
      (tester) async {
        keystoreHolding({});
        await openGarage(tester);
        Future<void> paste() async {
          await tester.tap(find.text('Recovery'));
          await settle(tester);
          await tester.enterText(pasteInput(), exampleText);
          await settle(tester);
          await tester.tap(find.text('Recover'));
          await letTheVaultSettle(tester);
          expect(find.text(exampleNickname), findsOneWidget);
        }

        await paste();
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        final bindings = locator<RobotBindingRepository>();
        final example = switch (GarageKey.parse(exampleText)) {
          Ok(:final value) => NetworkGarageKey(RobosatsNetwork.testnet, value),
          Err() => fail('not a key'),
        };
        NetworkRobot exampleRobot(int index) =>
            switch (example.firstUsableRobot(index)) {
              Ok(:final value) when value.accountIndex == index => value,
              _ => fail('no robot $index'),
            };
        Future<RobotStanding> standingOf(int index) async =>
            switch (await bindings.standingOf(exampleRobot(index).slot)) {
              Ok(:final value) => value,
              Err() => fail('unreadable'),
            };
        expect((await standingOf(0)).history, GarageKeyHistory.unknown);

        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsOneWidget);
        await tester.tap(find.text('I understand'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsNothing);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect((await standingOf(0)).history, GarageKeyHistory.acknowledged);
        expect(robotRequestsMade(), isFalse);

        // Temple of Sats, then « Continue »: the robot is bound with the provenance of an acknowledged key.
        await tester.tap(find.text('Temple of Sats'));
        await afterRoute(tester);
        await tester.tap(find.text('Continue'));
        bool sent() => transport.requests.any((r) => r.robot != null);
        for (var i = 0; i < 400 && !sent(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        await settle(tester);
        expect(
          transport.requests.where((r) => r.robot != null).single.robot,
          exampleRobot(0).identity.sessionKey,
        );
        expect(
          (await standingOf(0)).binding?.provenance,
          BindingProvenance.acknowledged,
        );

        // The next robot of the key goes straight to the sheet.
        await tester.ensureVisible(find.byTooltip('Next account'));
        await settle(tester);
        await tester.tap(find.byTooltip('Next account'));
        await settle(tester);
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        await tester.ensureVisible(find.text('Select Host'));
        await settle(tester);
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsNothing);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await afterRoute(tester);

        // Deleted, then pasted again: a pasted copy may have travelled, and the acknowledgement is asked again.
        await tapDeleteAll(tester);
        await settle(tester);
        await tester.tap(find.text('Delete Garage Key'));
        await afterRoute(tester);
        await tester.tap(find.text('PIN ok'));
        await afterRoute(tester);
        await paste();
        expect((await standingOf(1)).history, GarageKeyHistory.unknown);
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        // Robot #0 is bound already: robot #1 has none.
        await tester.tap(find.byTooltip('Next account'));
        await settle(tester);
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        await tester.ensureVisible(find.text('Select Host'));
        await settle(tester);
        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byType(RobotHistoryDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await afterRoute(tester);
        expect(find.byType(SelectHostSheet), findsNothing);
        expect((await standingOf(1)).history, GarageKeyHistory.unknown);
        expect((await standingOf(1)).binding, isNull);
        expect(
          transport.requests.where(
            (r) => r.robot == exampleRobot(1).identity.sessionKey,
          ),
          isEmpty,
        );
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
      ]) {
        testWidgets(
          '$change while $opened is open: it closes, and nothing is recorded or sent',
          (tester) async {
            keystoreHolding({_testnetEntry: null, _mainnetEntry: null});
            await openGarage(tester);
            tor.add(P2pTorState.ready);
            await letTheVaultSettle(tester);
            final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
              Ok(:final value) => value,
              Err() => throw StateError('no fingerprint'),
            };
            Future<GarageKeyHistory> testnetHistory() async =>
                switch (await locator<RobotBindingRepository>().exposureOf(
                  RobosatsNetwork.testnet,
                  fingerprint,
                )) {
                  Ok(:final value) => value.history,
                  Err() => throw StateError('unreadable'),
                };
            await tester.ensureVisible(find.text('Select Host'));
            await settle(tester);
            await tester.tap(find.text('Select Host'));
            await afterRoute(tester);
            expect(find.byType(RobotHistoryDialog), findsOneWidget);
            if (opened != '« Robots from elsewhere »') {
              await tester.ensureVisible(find.text('I understand'));
              await settle(tester);
              await tester.tap(find.text('I understand'));
              await afterRoute(tester);
              expect(find.byType(SelectHostSheet), findsOneWidget);
            }
            if (opened == 'the confirmation') {
              await tester.tap(find.text('Temple of Sats'));
              await afterRoute(tester);
              expect(find.byType(SendRobotDialog), findsOneWidget);
            }
            final history = await testnetHistory();
            expect(
              history,
              opened == '« Robots from elsewhere »'
                  ? GarageKeyHistory.unknown
                  : GarageKeyHistory.acknowledged,
            );

            final garage = tester
                .element(find.byType(GarageView))
                .read<GarageCubit>();
            switch (change) {
              case 'the network':
                network.switchTo(RobosatsNetwork.mainnet);
              case 'the next robot':
                garage.next();
              default:
                unawaited(garage.delete(reauthenticate: () async => true));
            }
            await settle(tester);
            await letTheVaultSettle(tester);

            expect(find.byType(RobotHistoryDialog), findsNothing);
            expect(find.byType(SelectHostSheet), findsNothing);
            expect(find.byType(SendRobotDialog), findsNothing);
            expect(find.byType(GarageView), findsOneWidget);
            expect(await testnetHistory(), history);
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

    testWidgets(
      'a key drawn here: Select Host once Tor is ready, then the sheet and the confirmation, and Cancel sends nothing',
      (tester) async {
        keystoreHolding({_mainnetEntry: null});
        await openGarage(tester);
        await tester.tap(find.text('Start'));
        await settle(tester);
        await tester.tap(find.text('Generate Garage Key'));
        await letTheVaultSettle(tester);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('Continue'));
        await settle(tester);
        await tester.tap(find.text('See profile'));
        await settle(tester);

        expect(_selectHost(tester).disabled, isTrue);
        tor.add(P2pTorState.connecting);
        await settle(tester);
        expect(_selectHost(tester).disabled, isTrue);
        expect(find.text('Connecting to Tor network'), findsOneWidget);
        tor.add(P2pTorState.ready);
        await letTheVaultSettle(tester);
        expect(_selectHost(tester).disabled, isFalse);

        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
        expect(find.byType(SelectHostSheet), findsOneWidget);
        expect(find.text('Temple of Sats'), findsOneWidget);
        expect(find.text('TheBigLake'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Temple of Sats')).dy,
          lessThan(tester.getTopLeft(find.text('TheBigLake')).dy),
        );
        await tester.tap(find.byTooltip('Close'));
        await afterRoute(tester);
        expect(find.byType(SelectHostSheet), findsNothing);

        await tester.tap(find.text('Select Host'));
        await afterRoute(tester);
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
        expect(robotRequestsMade(), isFalse);
      },
    );

    testWidgets('Continue on robot #1 sends robot #1, and robot #0 stays unbound', (
      tester,
    ) async {
      keystoreHolding({_mainnetEntry: null});
      await openGarage(tester);
      await tester.tap(find.text('Start'));
      await settle(tester);
      await tester.tap(find.text('Generate Garage Key'));
      await letTheVaultSettle(tester);
      // The key drawn for this test, kept in memory only, to derive its robots.
      await tester.tap(find.byTooltip('Copy'));
      await settle(tester);
      final key = switch (GarageKey.parse(clipboardWrites.last ?? '')) {
        Ok(:final value) => value,
        Err() => fail('the copied text is not a key'),
      };
      await tester.pump(const Duration(seconds: 31));
      final robot1 = switch (NetworkGarageKey(
        RobosatsNetwork.testnet,
        key,
      ).firstUsableRobot(1)) {
        Ok(:final value) => value.identity,
        Err() => fail('no robot 1'),
      };
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      await tester.tap(find.text('See profile'));
      await settle(tester);
      await tester.tap(find.byTooltip('Next account'));
      await settle(tester);
      expect(find.text('Robot #1'), findsOneWidget);
      tor.add(P2pTorState.ready);
      await letTheVaultSettle(tester);

      await tester.ensureVisible(find.text('Select Host'));
      await settle(tester);
      await tester.tap(find.text('Select Host'));
      await afterRoute(tester);
      await tester.tap(find.text('Temple of Sats'));
      await afterRoute(tester);
      expect(
        find.text('Send ${robot1.nickname} to Temple of Sats?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      // The key pair is made in an isolate: real time passes for it.
      bool sent() => transport.requests.any((r) => r.robot != null);
      for (var i = 0; i < 400 && !sent(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }
      await settle(tester);

      final robotRequests = [
        for (final request in transport.requests)
          if (request.robot != null) request,
      ];
      expect(robotRequests, hasLength(1));
      expect(robotRequests.single.robot, robot1.sessionKey);
      expect(
        robotRequests.single.url.host,
        FakeRobotCoordinators.hostOf('temple', RobosatsNetwork.testnet),
      );
      // The fake coordinator answers no robot: robot #1 is bound to Temple of Sats all the same.
      expect(find.text('Temple of Sats'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Previous account'));
      await settle(tester);
      await tester.tap(find.byTooltip('Previous account'));
      await settle(tester);
      expect(find.text('Robot #0'), findsOneWidget);
      expect(find.text('No coordinator knows this robot yet.'), findsOneWidget);
      expect(transport.requests.where((r) => r.robot != null), hasLength(1));
    });

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
          'This Garage Key was pasted in, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Troc a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, generate a new Garage Key.',
          'I understand',
        ),
        (
          Locale('fr'),
          'Robots venus d’ailleurs',
          'Cette clé de garage a été collée, ou cet appareil n’a pas pu enregistrer qu’il l’a générée. Ses robots existent peut-être déjà chez des coordinateurs\u00a0: l’application officielle RoboSats envoie chaque robot qu’elle affiche à tous les coordinateurs. Dans Troc, un robot ne vit que chez un seul coordinateur\u00a0: si vous avez déjà utilisé cette clé, placez chaque robot chez le coordinateur où vous l’avez utilisé. Pour repartir de zéro, générez une nouvelle clé de garage.',
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

  testWidgets('nothing printed or logged through the screens holds a key', (
    tester,
  ) async {
    keystoreHolding({});
    // The logger prints every record it handles in debug mode, the level it does not write to its file included: what it prints is what it handled.
    final printed = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');

    try {
      await runZoned(
        () async {
          Zone.current.print('print capture works');
          log.fine('logger capture works');
          await openGarage(tester);
          await tester.tap(find.text('Start'));
          await settle(tester);
          await tester.tap(find.text('Generate Garage Key'));
          await letTheVaultSettle(tester);
          await tester.tap(find.byTooltip('Copy'));
          await tester.pump(const Duration(seconds: 31));
          await settle(tester);
          await tester.tap(find.text('Continue'));
          await settle(tester);
          await tester.tap(find.byTooltip('Next account'));
          await settle(tester);
          await tester.tap(find.text('Continue'));
          await settle(tester);
          await tester.tap(find.text('See profile'));
          await settle(tester);
          // The robot panel: « Select Host », « Continue », then « Retry » (security review of step 5).
          tor.add(P2pTorState.ready);
          await letTheVaultSettle(tester);
          await tester.tap(find.text('Select Host'));
          await afterRoute(tester);
          await tester.tap(find.text('Temple of Sats'));
          await afterRoute(tester);
          await tester.tap(find.text('Continue'));
          // The key pair is made in an isolate, and the fake coordinator answers no robot: « Retry » comes.
          for (
            var i = 0;
            i < 400 && find.text('Retry').evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }
          await tester.tap(find.text('Retry'));
          await settle(tester);
          expect(
            transport.requests.where((request) => request.robot != null),
            hasLength(2),
          );
          await tester.ensureVisible(find.text('Show Garage Key'));
          await settle(tester);
          await tester.tap(find.text('Show Garage Key'));
          await afterRoute(tester);
          await tester.tap(find.text('PIN ok'));
          await afterRoute(tester);
          await tapDeleteAll(tester);
          await settle(tester);
          await tester.tap(find.text('Delete Garage Key'));
          // A robot of the key is bound now: the delete asks the PIN.
          await afterRoute(tester);
          await tester.tap(find.text('PIN ok'));
          await afterRoute(tester);
          await tester.tap(find.text('Recovery'));
          await settle(tester);
          await tester.enterText(
            find.descendant(
              of: find.byType(GarageKeyField),
              matching: find.byType(EditableText),
            ),
            exampleText,
          );
          await settle(tester);
          await tester.tap(find.text('Recover'));
          await letTheVaultSettle(tester);
          expect(find.text(exampleNickname), findsOneWidget);
          // The pasted key: « Select Host » asks « Robots from elsewhere », and « I understand » records it and opens the sheet (#29, step 6).
          tor.add(P2pTorState.ready);
          await letTheVaultSettle(tester);
          await tester.ensureVisible(find.text('Select Host'));
          await settle(tester);
          await tester.tap(find.text('Select Host'));
          await afterRoute(tester);
          await tester.tap(find.text('I understand'));
          await afterRoute(tester);
          expect(find.byType(SelectHostSheet), findsOneWidget);
          await tester.tap(find.byTooltip('Close'));
          await afterRoute(tester);
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
    expect(printed, contains('print capture works'));
    expect(
      printed.any((line) => line.contains('logger capture works')),
      isTrue,
    );
    expect(clipboardWrites, hasLength(2));
    final copied = switch (GarageKey.parse(clipboardWrites.first ?? '')) {
      Ok(:final value) => value,
      Err() => fail('the copied text is not a key'),
    };
    final example = switch (GarageKey.parse(exampleText)) {
      Ok(:final value) => value,
      Err() => fail('not a key'),
    };
    expectNoKeyIn(printed.join('\n'), [copied, example]);
    // Nor the credential of the robot that went to the coordinator (robot #1, shown since the wizard), nor of robot #0.
    for (final index in [0, 1]) {
      final robot = switch (copied.deriveIdentity(index)) {
        Ok(:final value) => value,
        Err() => fail('no robot $index'),
      };
      expect(
        printed.join('\n').contains(robot.tokenSha256Hex),
        isFalse,
        reason: 'robot $index',
      );
    }
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
