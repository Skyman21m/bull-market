import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

/// The files of the feature that may import `package:secrets`, and the names each one may take from it.
///
/// The vault also guards the wallet seeds: the feature takes the Garage Key handle the shell gives it, in the file that receives it, the file that registers it and the repository that uses it, and nothing else but the test seam.
const _allowed = {
  'lib/public/p2p_facade.dart': {'GarageKeys'},
  'lib/src/p2p_locator.dart': {'GarageKeys'},
  // The test seam, which registers the Garage over a handle a test made: no library of the app imports it (`test/features/p2p/p2p_testing_seam_test.dart`).
  'lib/testing.dart': {'GarageKeys'},
  'lib/src/data/garage_key_repository_impl.dart': {
    'GarageKeyAlreadyExistsFailure',
    'GarageKeyCorruptFailure',
    'GarageKeySlot',
    'GarageKeys',
    'KeystoreLockedFailure',
    'SecretFailure',
    'SecretNotFoundFailure',
  },
};

/// What [source] takes from the vault: one entry per directive whose library could be the vault, with the names it shows, or `null` when it is anything but an import of `package:secrets/secrets.dart` with a `show` list and nothing else.
///
/// The directives are read from the parsed syntax tree, so the library is the value Dart gives the string, with its escapes decoded, whatever the spacing, quotes or comments around it; the libraries of conditional imports are read too.
/// A library whose name is not a plain string, or that mentions `secrets` anywhere, counts as the vault.
List<Set<String>?> _vaultImports(String source) => [
  for (final directive in parseString(content: source).unit.directives)
    if (_libraries(
      directive,
    ).any((uri) => uri == null || uri.contains('secrets')))
      _narrowImport(directive),
];

/// Every library [directive] names.
List<String?> _libraries(Directive directive) => switch (directive) {
  NamespaceDirective(:final uri, :final configurations) => [
    uri.stringValue,
    for (final configuration in configurations) configuration.uri.stringValue,
  ],
  PartDirective(:final uri) => [uri.stringValue],
  PartOfDirective(uri: final uri?) => [uri.stringValue],
  _ => const [],
};

/// The names [directive] shows, when it is `import 'package:secrets/secrets.dart' show …;` with no prefix, no deferral, no condition and no other combinator.
Set<String>? _narrowImport(Directive directive) {
  if (directive is! ImportDirective ||
      directive.uri.stringValue != 'package:secrets/secrets.dart' ||
      directive.prefix != null ||
      directive.deferredKeyword != null ||
      directive.configurations.isNotEmpty ||
      directive.combinators.length != 1) {
    return null;
  }
  return switch (directive.combinators.single) {
    ShowCombinator(:final shownNames) => {
      for (final name in shownNames) name.name,
    },
    _ => null,
  };
}

void main() {
  // Tests run with the package directory as working directory.
  final libraries = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  test('the libraries of the feature are found', () {
    expect(libraries.length, greaterThan(40));
    expect(libraries.map((file) => file.path), containsAll(_allowed.keys));
  });

  test('only the named files import the vault, each with its own names', () {
    final imports = <String, Set<String>>{};
    final offenders = <String>[];
    for (final file in libraries) {
      for (final names in _vaultImports(file.readAsStringSync())) {
        if (names == null) {
          offenders.add(file.path);
        } else {
          (imports[file.path] ??= {}).addAll(names);
        }
      }
    }

    expect(offenders, isEmpty);
    expect(imports, _allowed);
  });

  test('the check sees an import of the vault however it is written', () {
    // Each directive below but the first names the vault without the one form allowed; the second is the escaped spelling a review found the earlier, textual check blind to.
    const probe = r'''
import 'package:secrets/secrets.dart'
    show
        GarageKeys,
        Secrets;
import 'package:\x73ecrets/\x73ecrets.dart';
/* a comment */ import "package:secrets/secrets.dart";
import'package:secrets/secrets.dart'as vault;
import 'package:secrets/secrets.dart' deferred as later show GarageKeys;
import 'dart:core' if (dart.library.io) 'package:secrets/secrets.dart';
import '../../packages/secrets/lib/secrets.dart' show GarageKeys;
import 'package:robosats/robosats.dart';
export 'package:secrets/secrets.dart' show GarageKeys;
''';

    expect(_vaultImports(probe), [
      {'GarageKeys', 'Secrets'},
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ]);
  });
}
