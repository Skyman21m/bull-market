import 'dart:io';

import 'package:bb_mobile/core/background_tasks/tasks.dart';
import 'package:flutter_test/flutter_test.dart';

/// The WorkManager isolate builds its own `Secrets`, and the package's write
/// lock is per isolate. That is safe only while no background task mutates
/// the keystore — which is true today, and this keeps it true: adding a task
/// that imports, trashes or repairs a secret must first fail here and be
/// argued for in review, not discovered as a lost write in the field.
void main() {
  group('background tasks stay out of the keystore', () {
    test('the task set is exactly the four read-only ones', () {
      expect(
        BackgroundTask.values.map((t) => t.name),
        unorderedEquals([
          'bitcoin-sync',
          'liquid-sync',
          'swaps-sync',
          'logs-prune',
        ]),
      );
    });

    test('the handler reaches no secret-mutating use case', () {
      final source = File(
        'lib/core/background_tasks/handler.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('package:secrets')));
      for (final mutating in [
        'ImportWalletUsecase',
        'CreateDefaultWalletsUsecase',
        'DeleteWalletUsecase',
        'DeleteSecretUsecase',
        'RestoreVaultUsecase',
        'CreateEncryptedVaultUsecase',
        '.recoverbull.restore(',
        '.trash(',
        '.import(',
        '.generate(',
        // The Garage Key handle creates and imports keys: its lock does not reach the foreground isolate.
        'garageKeys',
      ]) {
        expect(source, isNot(contains(mutating)), reason: mutating);
      }
    });
  });

  // `AppLocator.setup` cannot run in a unit test, so these read the calls in the source; `test/locator_test.dart` runs what each value of the flag registers.
  // They do not prove that the handler reaches its call at run time, nor see a Garage Key handle obtained by any other path: the custody gate refuses `Secrets.garageKeys` outside `AppLocator`.
  group('only the foreground composition hands P2P the Garage Key handle', () {
    test('the app is composed in two places', () {
      final callers = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              _calls(file.readAsStringSync(), 'AppLocator.setup').isNotEmpty)
            file.path,
      ];

      expect(
        callers,
        unorderedEquals([
          'lib/init.dart',
          'lib/core/background_tasks/handler.dart',
        ]),
      );
    });

    for (final (path, flag) in [
      ('lib/core/background_tasks/handler.dart', 'false'),
      ('lib/init.dart', 'true'),
    ]) {
      test('$path passes withGarageKeys: $flag, as a literal', () {
        final calls = _calls(File(path).readAsStringSync(), 'AppLocator.setup');

        expect(calls, hasLength(1));
        expect(
          calls.single.where((argument) => argument.contains('GarageKeys')),
          ['withGarageKeys: $flag'],
        );
      });
    }

    test('AppLocator.setup passes its own flag to the P2P setup', () {
      final source = File('lib/locator.dart').readAsStringSync();

      // Its declaration and its one call.
      expect(
        _calls(source, 'setupP2p'),
        unorderedEquals([
          ['GetIt locator', '{required bool withGarageKeys}'],
          ['locator', 'withGarageKeys: withGarageKeys'],
        ]),
      );
      expect('.garageKeys('.allMatches(source), hasLength(1));
    });
  });
}

/// The arguments of every call of [callee] in [source], each with its whitespace collapsed, after the comments that fill a line are removed.
///
/// A declaration of [callee] reads as a call whose arguments are its parameters.
List<List<String>> _calls(String source, String callee) {
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
  final calls = <List<String>>[];
  for (final match in RegExp('${RegExp.escape(callee)}\\(').allMatches(code)) {
    final arguments = <String>[];
    var depth = 0;
    var start = match.end;
    for (var i = match.end; i < code.length; i++) {
      final char = code[i];
      if ('([{'.contains(char)) depth++;
      if (')]}'.contains(char)) {
        if (depth == 0) {
          arguments.add(code.substring(start, i));
          break;
        }
        depth--;
      }
      if (char == ',' && depth == 0) {
        arguments.add(code.substring(start, i));
        start = i + 1;
      }
    }
    calls.add([
      for (final argument in arguments)
        if (argument.trim().isNotEmpty)
          argument.trim().replaceAll(RegExp(r'\s+'), ' '),
    ]);
  }
  return calls;
}
