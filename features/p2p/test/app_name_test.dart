import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/token.dart';
import 'package:test/test.dart';

/// The app was called « Troc » until #105, and is called « Bull Market » since: no text a user reads may still carry the old name.
///
/// The texts are the values of the translation files and the strings of the localisations generated from them; the descriptions of the translation files and the comments of the generated code are for translators and developers, and may name it.
void main() {
  // Tests run with the package directory as working directory.
  final oldName = RegExp(r'\bTroc\b');

  test('no value of a translation file names the app « Troc »', () {
    final files = _files('lib/l10n', '.arb');
    expect(files, isNotEmpty);

    final found = <String>[
      for (final file in files)
        for (final MapEntry(:key, :value)
            in (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
                .entries)
          if (!key.startsWith('@') &&
              value is String &&
              oldName.hasMatch(value))
            '${file.path}: $key',
    ];
    expect(found, isEmpty);
  });

  test('no string of the generated localisations names the app « Troc »', () {
    final files = _files('lib/generated/l10n', '.dart');
    expect(files, isNotEmpty);

    final found = <String>[
      for (final file in files)
        for (final string in _strings(file.readAsStringSync()))
          if (oldName.hasMatch(string)) '${file.path}: $string',
    ];
    expect(found, isEmpty);
  });

  test('the check sees the strings of a Dart file and not its comments', () {
    const source = '''
/// Troc in a doc comment.
// Troc in a comment.
String a(String b) => 'Troc \$b';
const c = "Bull Market";
''';
    expect(_strings(source).where(oldName.hasMatch), hasLength(1));
    expect(_strings(source), contains('"Bull Market"'));
  });
}

/// The files of [directory] whose name ends with [extension], in a stable order.
List<File> _files(String directory, String extension) =>
    Directory(directory)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(extension))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// The string tokens of [source], as written, quotes included; comments are not tokens, so they are left out.
Iterable<String> _strings(String source) sync* {
  Token? token = parseString(content: source).unit.beginToken;
  while (token != null && !token.isEof) {
    if (token.type == TokenType.STRING) yield token.lexeme;
    token = token.next;
  }
}
