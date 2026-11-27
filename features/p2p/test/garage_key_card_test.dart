import 'dart:typed_data';

import 'package:bull_ui/testing.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/garage_key_book_repository_impl.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/new_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/src/ui/garage/garage_key_card.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:p2p/src/ui/widgets/garage_key_view.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/garage_words.dart';
import 'support/harness.dart';

/// The card « Garage Key » alone (review of #292, R-7): a key shown in clear, after the PIN, is hidden again when the card is given another key in the same frame, with no state between them, as when the Garage settles on another key before a frame is drawn. Then the card is not built anew: `didUpdateWidget` is what hides the text, and the text of the first key never stands under the title of the second.
void main() {
  const testnet = RobosatsNetwork.testnet;

  /// A key of fixed test bytes, [first] to [first] + 31: not a key anyone uses.
  GarageKey testKey(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + first)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  final keyA = testKey(0x21);
  final keyB = testKey(0x41);

  /// The state of the Garage on [key], internal key [index] or the external Garage Key when [index] is `null`.
  GarageWithKey stateOf(
    GarageKey key, {
    int? index,
    bool inProgressUnread = false,
    List<TradeRecord> inProgress = const [],
  }) => GarageWithKey(
    testnet,
    key: NetworkGarageKey(testnet, key, index: index),
    robot: GarageRobotFace(index: 0, nickname: 'TestRobot', hashId: 'ab' * 32),
    highest: 1,
    hasExternal: true,
    inProgressUnread: inProgressUnread,
    inProgress: inProgress,
    deletionNeedsPin: false,
  );

  late int reauthentications;
  Widget reauthenticate(VoidCallback onAuthenticated) {
    reauthentications++;
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: onAuthenticated,
          child: const Text('PIN ok'),
        ),
      ),
    );
  }

  /// A cubit the card only reads: none of its actions is tapped here.
  GarageCubit cubit() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    FakeSecureStoragePlatform().install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final recorded = RobotBindingRepositoryImpl(database, clock: DateTime.now);
    final repository = GarageKeyRepositoryImpl(
      vault,
      TestWordsPort(),
      GarageKeyBookRepositoryImpl(database, clock: DateTime.now),
    );
    final cubit = GarageCubit(
      testnet,
      ReadGarageKeyUsecase(repository),
      NewGarageKeyUsecase(repository),
      ImportGarageKeyUsecase(repository, recorded),
      DeleteGarageKeyUsecase(repository),
      NeedsPinToDeleteGarageKeyUsecase(recorded),
    );
    addTearDown(cubit.close);
    return cubit;
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

  for (final (name, first, second, secondTitle) in [
    (
      'another internal Garage Key',
      stateOf(keyA, index: 0),
      stateOf(keyB, index: 1),
      'Internal Garage Key #1',
    ),
    (
      'the external Garage Key, from an internal one',
      stateOf(keyA, index: 0),
      stateOf(keyB),
      'External Garage Key',
    ),
    (
      'an internal Garage Key, from the external one',
      stateOf(keyA),
      stateOf(keyB, index: 0),
      'Internal Garage Key #0',
    ),
  ]) {
    testWidgets(
      'a key shown in clear is hidden again when the card is given $name in the same frame',
      (tester) async {
        usePhoneScreen(tester);
        reauthentications = 0;
        final shown = ValueNotifier(first);
        addTearDown(shown.dispose);
        await tester.pumpWidget(
          harness(
            BlocProvider.value(
              value: cubit(),
              child: SingleChildScrollView(
                child: ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (context, state, _) => GarageKeyCard(
                    state: state,
                    clipboard: GarageKeyClipboard(),
                    reauthenticate: reauthenticate,
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(GarageKeyView), findsNothing);
        await tester.tap(find.byTooltip('Show Garage Key'));
        await settle(tester);
        await tester.tap(find.text('PIN ok'));
        await settle(tester);
        expect(reauthentications, 1);
        expect(shownKey(tester), keyA.revealBech32());

        // The other key, given to the same card, drawn in one frame.
        shown.value = second;
        await tester.pump();
        expect(find.text(secondTitle), findsOneWidget);
        expect(find.byType(GarageKeyView), findsNothing);
        expect(find.text(keyA.revealBech32()), findsNothing);
        expect(find.text(keyB.revealBech32()), findsNothing);
        // Its text is to be asked for again: the eye is offered, nothing else is asked.
        expect(find.byTooltip('Show Garage Key'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(GarageKeyView), findsNothing);
        expect(reauthentications, 1);
      },
    );
  }

  for (final (locale, delete, line, confirm, cancel) in [
    (
      const Locale('en'),
      'Delete the external Garage Key',
      'Bull Market could not read your trades: a trade in progress may use this Garage Key.',
      'Delete',
      'Cancel',
    ),
    (
      const Locale('fr'),
      'Supprimer la clé de garage externe',
      'Bull Market n’a pas pu lire vos échanges\u00a0: un échange en cours utilise peut-être cette clé de garage.',
      'Supprimer',
      'Annuler',
    ),
  ]) {
    testWidgets(
      'trades that could not be read: « Delete the external Garage Key? » says a trade in progress may use the key, in the warning colour, « Delete » enabled; read, nothing is said (${locale.languageCode}, review of #292, R-3)',
      (tester) async {
        usePhoneScreen(tester);
        final shown = ValueNotifier(stateOf(keyA, inProgressUnread: true));
        addTearDown(shown.dispose);
        await tester.pumpWidget(
          harness(
            BlocProvider.value(
              value: cubit(),
              child: SingleChildScrollView(
                child: ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (context, state, _) => GarageKeyCard(
                    state: state,
                    clipboard: GarageKeyClipboard(),
                    reauthenticate: reauthenticate,
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await settle(tester);
        await tester.tap(find.text(delete));
        await settle(tester);
        expect(find.text(line), findsOneWidget);
        expect(
          tester.widget<Text>(find.text(line)).style?.color,
          testBullTheme.warning,
        );
        expect(
          tester
              .widget<TradeButton>(
                find.ancestor(
                  of: find.text(confirm),
                  matching: find.byType(TradeButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text(cancel));
        await settle(tester);
        // The trades read again: the dialog says nothing of them.
        shown.value = stateOf(keyA);
        await tester.pump();
        await tester.tap(find.text(delete));
        await settle(tester);
        expect(find.text(line), findsNothing);
        await tester.tap(find.text(cancel));
        await settle(tester);
      },
    );
  }

  /// A trade in progress of [key]'s robot 0, order [orderId], taken here.
  TradeRecord tradeOf(GarageKey key, int orderId) => TradeRecord(
    robot: RobotSlot(testnet, switch (GarageKeyFingerprint.of(key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    }, 0),
    coordinatorAlias: 'temple',
    coordinatorOnion: 'http://temple.onion',
    orderId: orderId,
    role: TradeRole.buyer,
    origin: TradeOrigin.takenHere,
    takenAt: DateTime.utc(2026, 11, 27, 9),
    confirmedAt: DateTime.utc(2026, 11, 27, 9),
    closedAt: null,
  );

  for (final (locale, delete, trades, unread, cancel) in [
    (
      const Locale('en'),
      'Delete the external Garage Key',
      'Trades #42, #43 use this Garage Key: without it, you will not be able to continue them.',
      'Bull Market could not read your trades: a trade in progress may use this Garage Key.',
      'Cancel',
    ),
    (
      const Locale('fr'),
      'Supprimer la clé de garage externe',
      'Les échanges #42, #43 utilisent cette clé de garage\u00a0: sans elle, vous ne pourrez plus les continuer.',
      'Bull Market n’a pas pu lire vos échanges\u00a0: un échange en cours utilise peut-être cette clé de garage.',
      'Annuler',
    ),
  ]) {
    testWidgets(
      'a reading of the trades that failed after one that succeeded: « Delete the external Garage Key? » names the trades known first, then says the trades could not be read, both in the warning colour; the trades read again, only the trades known are named (${locale.languageCode}, review of #292, R-8)',
      (tester) async {
        usePhoneScreen(tester);
        final known = [tradeOf(keyA, 42), tradeOf(keyA, 43)];
        final shown = ValueNotifier(
          stateOf(keyA, inProgress: known, inProgressUnread: true),
        );
        addTearDown(shown.dispose);
        await tester.pumpWidget(
          harness(
            BlocProvider.value(
              value: cubit(),
              child: SingleChildScrollView(
                child: ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (context, state, _) => GarageKeyCard(
                    state: state,
                    clipboard: GarageKeyClipboard(),
                    reauthenticate: reauthenticate,
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await settle(tester);
        await tester.tap(find.text(delete));
        await settle(tester);
        expect(find.text(trades), findsOneWidget);
        expect(find.text(unread), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(trades)).dy,
          lessThan(tester.getTopLeft(find.text(unread)).dy),
        );
        for (final line in [trades, unread]) {
          expect(
            tester.widget<Text>(find.text(line)).style?.color,
            testBullTheme.warning,
          );
        }
        await tester.tap(find.text(cancel));
        await settle(tester);
        // The trades read again: only the trades known are named.
        shown.value = stateOf(keyA, inProgress: known);
        await tester.pump();
        await tester.tap(find.text(delete));
        await settle(tester);
        expect(find.text(trades), findsOneWidget);
        expect(find.text(unread), findsNothing);
        await tester.tap(find.text(cancel));
        await settle(tester);
      },
    );
  }
}
