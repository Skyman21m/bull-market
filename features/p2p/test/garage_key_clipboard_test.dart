import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/garage_key_clipboard.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey;

/// The one place a Garage Key reaches the clipboard, over a fake clipboard and the fake clock of a widget test.
void main() {
  // Fixed test bytes: 0x01 to 0x20, then 0x21 to 0x40; not keys anyone uses.
  GarageKey keyFrom(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + first)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final first = keyFrom(1);
  final second = keyFrom(33);

  String? clipboard;
  late bool writeFails;
  late bool unreadable;

  setUp(() {
    clipboard = null;
    writeFails = false;
    unreadable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              if (writeFails) throw PlatformException(code: 'clipboard');
              clipboard = (call.arguments as Map)['text'] as String?;
            case 'Clipboard.getData':
              return unreadable ? null : {'text': clipboard};
          }
          return null;
        });
  });

  testWidgets('a refused copy keeps the clearing of the key copied before', (
    tester,
  ) async {
    final helper = GarageKeyClipboard();
    addTearDown(helper.dispose);
    expect(await helper.copy(first, first.revealBech32()), isTrue);
    await tester.pump(const Duration(seconds: 10));

    writeFails = true;
    expect(await helper.copy(second, second.revealBech32()), isFalse);
    writeFails = false;
    expect(clipboard == first.revealBech32(), isTrue);
    expect(helper.isArmed, isTrue);

    // Thirty seconds after the first copy, not after the refused one.
    await tester.pump(const Duration(seconds: 21));

    expect(clipboard, '');
  });

  testWidgets('a second copy moves the clearing to its own 30 seconds', (
    tester,
  ) async {
    final helper = GarageKeyClipboard();
    addTearDown(helper.dispose);
    await helper.copy(first, first.revealBech32());
    await tester.pump(const Duration(seconds: 20));
    await helper.copy(second, second.revealBech32());

    await tester.pump(const Duration(seconds: 20));
    expect(clipboard == second.revealBech32(), isTrue);
    await tester.pump(const Duration(seconds: 11));

    expect(clipboard, '');
  });

  testWidgets('an unreadable clipboard is emptied anyway', (tester) async {
    final helper = GarageKeyClipboard();
    addTearDown(helper.dispose);
    await helper.copy(first, first.revealBech32());
    unreadable = true;

    await tester.pump(const Duration(seconds: 31));

    expect(clipboard, '');
  });

  testWidgets('dispose clears at once what the timer would clear', (
    tester,
  ) async {
    final helper = GarageKeyClipboard();
    await helper.copy(first, first.revealBech32());

    await helper.dispose();

    expect(clipboard, '');
    expect(helper.isArmed, isFalse);
  });

  testWidgets('the app torn down clears at once', (tester) async {
    final helper = GarageKeyClipboard();
    addTearDown(helper.dispose);
    await helper.copy(first, first.revealBech32());

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }

    expect(clipboard, '');
    expect(helper.isArmed, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('going to the background alone does not clear it', (
    tester,
  ) async {
    final helper = GarageKeyClipboard();
    addTearDown(helper.dispose);
    await helper.copy(first, first.revealBech32());

    // The user pastes it in another app.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }

    expect(clipboard == first.revealBech32(), isTrue);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 31));
    expect(clipboard, '');
  });
}
