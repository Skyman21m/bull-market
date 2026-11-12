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

  // `AppLocator.setup` cannot run in a unit test, so these read the code of `lib/`, with its comments and the text of its strings removed; `test/locator_test.dart` runs what each value of the flag registers.
  // They prove which literal each composition passes, that `setup` forwards its own flag, that the P2P database directory follows the same flag, and that nothing else in `lib/` names `setupP2p` or `withGarageKeys`, or sets up P2P.
  // They do not run the handler, so they prove nothing about what happens at run time, and they do not see a handle obtained by any other path: the custody gate refuses `Secrets.garageKeys` outside `AppLocator`.
  group('only the foreground composition hands P2P the Garage Key handle', () {
    final code = _codeOfLib();

    test('the app is composed in two places', () {
      expect(_occurrences(code, RegExp(r'\bAppLocator\s*\.\s*setup\b')), {
        'lib/init.dart': 1,
        'lib/core/background_tasks/handler.dart': 1,
      });
    });

    for (final (path, flag) in [
      ('lib/core/background_tasks/handler.dart', 'false'),
      ('lib/init.dart', 'true'),
    ]) {
      test('$path passes withGarageKeys: $flag, as a literal', () {
        final calls = _calls(
          code[path] ?? '',
          RegExp(r'\bAppLocator\s*\.\s*setup\s*\('),
        );

        expect(calls, hasLength(1));
        expect(
          calls.single.where((argument) => argument.contains('GarageKeys')),
          ['withGarageKeys: $flag'],
        );
      });
    }

    test(
      'only lib/locator.dart names setupP2p, and passes it its own flag',
      () {
        expect(_occurrences(code, RegExp(r'\bsetupP2p\b')), {
          'lib/locator.dart': 2,
        });
        // Its declaration and its one call.
        expect(
          _calls(code['lib/locator.dart'] ?? '', RegExp(r'\bsetupP2p\s*\(')),
          unorderedEquals([
            ['GetIt locator', '{required bool withGarageKeys}'],
            ['locator', 'withGarageKeys: withGarageKeys'],
          ]),
        );
        expect(_occurrences(code, RegExp(r'\.\s*garageKeys\b')), {
          'lib/locator.dart': 1,
        });
      },
    );

    test(
      'setupP2p gives P2P the handle and the directory of its database under that one flag',
      () {
        expect(
          _calls(
            code['lib/locator.dart'] ?? '',
            RegExp(r'\bP2pFeature\s*\(\s*\)\s*\.\s*setup\s*\('),
          ),
          [
            [
              'locator',
              'garageKeys: withGarageKeys ? locator<Secrets>().garageKeys() : null',
              'databaseDirectory: withGarageKeys ? getApplicationDocumentsDirectory : null',
            ],
          ],
        );
        // Nothing else in `lib/` sets up P2P, so nothing else hands it a directory.
        expect(
          _occurrences(code, RegExp(r'\bP2pFeature\s*\(\s*\)\s*\.\s*setup\b')),
          {'lib/locator.dart': 1},
        );
      },
    );

    test('the flag is named in the three compositions only', () {
      expect(_occurrences(code, RegExp(r'\bwithGarageKeys\b')), {
        'lib/init.dart': 1,
        'lib/core/background_tasks/handler.dart': 1,
        // The parameter of `setup`, both sides of the argument it passes to `setupP2p`, the parameter of `setupP2p` and its two uses.
        'lib/locator.dart': 6,
      });
    });

    test('the reading removes every comment and the text of every string', () {
      const probe = r"""
a(); // b(
/* c( /* d( */ e( */ f();
g('h( // i', "j/*", r'k\', '''l
m(''', '${n('o)')}', 'p\'q(');
""";
      final read = _codeOf(probe);

      expect(RegExp('[a-z]+').allMatches(read).map((match) => match[0]), [
        'a',
        'f',
        'g',
        'r',
        'n',
      ]);
      expect('('.allMatches(read), hasLength(4));
      expect(')'.allMatches(read), hasLength(4));
      expect(read.split('\n'), hasLength(probe.split('\n').length));
    });
  });
}

/// The code of every Dart file under `lib/` whose text names one of the identifiers these tests look for, by path.
///
/// A file whose text does not name an identifier cannot name it in its code: removing comments and strings only removes text.
Map<String, String> _codeOfLib() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      if (file.readAsStringSync() case final source
          when RegExp(
            'AppLocator|setupP2p|GarageKeys|garageKeys|P2pFeature',
          ).hasMatch(source))
        file.path: _codeOf(source),
};

/// How many times [pattern] matches the code of each file of [code], for the files where it matches at all.
Map<String, int> _occurrences(Map<String, String> code, RegExp pattern) => {
  for (final MapEntry(key: path, value: source) in code.entries)
    if (pattern.allMatches(source).length case final count when count > 0)
      path: count,
};

/// [source] with its comments, and the text of its string literals, replaced by spaces, so that only code is left; line breaks are kept.
///
/// It follows the lexical rules of Dart as far as these tests need: `//` comments, nested `/* */` comments, single and triple quotes, raw strings, escapes, and `${…}` interpolations, whose code stays code.
String _codeOf(String source) {
  String blank(String text) => text.replaceAll(RegExp(r'[^\n]'), ' ');
  final out = StringBuffer();
  // The innermost last: the code of the file, then each string and each interpolation being read.
  final stack = <_Reading>[_Code()];
  var i = 0;
  while (i < source.length) {
    final reading = stack.last;
    final char = source[i];
    switch (reading) {
      case _String(:final quote, :final raw):
        if (source.startsWith(quote, i)) {
          out.write(quote);
          i += quote.length;
          stack.removeLast();
        } else if (!raw && char == r'\' && i + 1 < source.length) {
          out.write(blank(source.substring(i, i + 2)));
          i += 2;
        } else if (!raw && source.startsWith(r'${', i)) {
          out.write(r'${');
          i += 2;
          stack.add(_Code());
        } else {
          out.write(blank(char));
          i++;
        }
      case _Code() when source.startsWith('//', i):
        final end = source.indexOf('\n', i);
        final stop = end < 0 ? source.length : end;
        out.write(blank(source.substring(i, stop)));
        i = stop;
      case _Code() when source.startsWith('/*', i):
        final start = i;
        var depth = 0;
        do {
          if (source.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        } while (depth > 0 && i < source.length);
        out.write(blank(source.substring(start, i)));
      case _Code():
        final raw =
            char == 'r' &&
            (i == 0 || !RegExp(r'[\w$]').hasMatch(source[i - 1]));
        final quoteAt = raw ? i + 1 : i;
        if (quoteAt < source.length &&
            (source[quoteAt] == "'" || source[quoteAt] == '"')) {
          final single = source[quoteAt];
          final quote = source.startsWith(single * 3, quoteAt)
              ? single * 3
              : single;
          out.write(source.substring(i, quoteAt + quote.length));
          i = quoteAt + quote.length;
          stack.add(_String(quote, raw: raw));
          continue;
        }
        if (char == '}' && reading.depth == 0 && stack.length > 1) {
          // The end of an interpolation: back to its string.
          stack.removeLast();
        } else if (char == '{') {
          reading.depth++;
        } else if (char == '}') {
          reading.depth--;
        }
        out.write(char);
        i++;
    }
  }
  return out.toString();
}

sealed class _Reading {}

/// Code, with the depth of its braces, so that the `}` that ends an interpolation is told from the others.
final class _Code extends _Reading {
  int depth = 0;
}

/// A string literal, up to its closing [quote].
final class _String extends _Reading {
  final String quote;
  final bool raw;

  _String(this.quote, {required this.raw});
}

/// The arguments of every call of [callee] in [code], each with its whitespace collapsed; [callee] matches up to the opening parenthesis.
///
/// A declaration of the callee reads as a call whose arguments are its parameters.
List<List<String>> _calls(String code, RegExp callee) {
  final calls = <List<String>>[];
  for (final match in callee.allMatches(code)) {
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
