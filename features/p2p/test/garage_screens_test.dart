import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_logger/bull_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/ui/garage/delete_garage_key_dialog.dart';
import 'package:p2p/src/ui/garage/garage_view.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:p2p/src/ui/widgets/garage_key_field.dart';
import 'package:p2p/src/ui/widgets/garage_key_view.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart' show Failure;
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/key_output.dart';

/// The `no_screenshot` plugin behind `PrivacyScreen` answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

const _mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
const _testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';

/// The network the tab reads, which a test can change while the tab is shown.
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

  /// What the fake plugin answers when the Garage asks for capture protection: `true`, `false`, or a future the test completes.
  late Future<bool> Function() protection;
  late List<String> privacyCalls;

  /// The text on the fake clipboard, and every text written to it.
  String? clipboard;
  late List<String?> clipboardWrites;

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
          clipboard = (call.arguments as Map)['text'] as String?;
          clipboardWrites.add(clipboard);
        case 'Clipboard.getData':
          return {'text': clipboard};
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
  }) async {
    usePhoneScreen(tester);
    storage.install();
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(network: network.state),
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: withGarage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
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
        'in ${locale.languageCode}: Delete All asks, then deletes this network only',
        (tester) async {
          keystoreHolding({_testnetEntry: null, _mainnetEntry: null});
          await openGarage(tester, locale: locale);
          final deleteAll = locale.languageCode == 'fr'
              ? 'Tout supprimer'
              : 'Delete All';

          await tester.tap(find.text(deleteAll));
          await settle(tester);
          for (final text in texts) {
            expect(find.text(text), findsOneWidget, reason: text);
          }
          await tester.tap(find.text(texts.last));
          await settle(tester);
          expect(storage.entries.keys.toSet(), {_testnetEntry, _mainnetEntry});

          await tester.tap(find.text(deleteAll));
          await settle(tester);
          await tester.tap(find.text(texts[texts.length - 2]));
          await settle(tester);

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

      await tester.tap(find.text('Delete All'));
      await settle(tester);
      await tester.tap(find.text('Delete Garage Key'));
      await settle(tester);

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
      await tester.tap(find.text('Delete Garage Key').last);
      await settle(tester);

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
          await tester.tap(find.text('Show Garage Key'));
          await afterRoute(tester);
          await tester.tap(find.text('PIN ok'));
          await afterRoute(tester);
          await tester.tap(find.text('Delete All'));
          await settle(tester);
          await tester.tap(find.text('Delete Garage Key'));
          await settle(tester);
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
  });
}

/// Whether [widget] is drawn inside a widget of type [T].
bool _isInside<T extends Widget>(WidgetTester tester, Widget widget) => find
    .ancestor(of: find.byWidget(widget), matching: find.byType(T))
    .evaluate()
    .isNotEmpty;
