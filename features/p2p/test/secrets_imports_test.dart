import 'dart:io';

import 'package:test/test.dart';

/// The files of the feature that may import `package:secrets`, and the names each one may take from it.
///
/// The vault also guards the wallet seeds: the feature takes the Garage Key handle the shell gives it, in the file that receives it, the file that registers it and the repository that uses it, and nothing else.
const _allowed = {
  'lib/public/p2p_facade.dart': {'GarageKeys'},
  'lib/src/p2p_locator.dart': {'GarageKeys'},
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

/// The only form an import of the vault may take: its public library, with a `show` list, no prefix and no other clause.
final _narrowImport = RegExp(
  r"^import 'package:secrets/secrets\.dart' show ([A-Za-z]+(?:, [A-Za-z]+)*);$",
);

/// The `import`, `export` and `part` directives of [source], each on one line with its whitespace collapsed.
Iterable<String> _directives(String source) =>
    RegExp(r'^\s*(?:import|export|part)\s[^;]*;', multiLine: true)
        .allMatches(source)
        .map(
          (match) => (match[0] ?? '').trim().replaceAll(RegExp(r'\s+'), ' '),
        );

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
      for (final directive in _directives(file.readAsStringSync())) {
        if (!directive.contains('secrets')) continue;
        final narrow = _narrowImport.firstMatch(directive);
        if (narrow == null) {
          offenders.add('${file.path}: $directive');
          continue;
        }
        imports[file.path] = (narrow[1] ?? '').split(', ').toSet();
      }
    }

    expect(offenders, isEmpty);
    expect(imports, _allowed);
  });

  test('the check sees an import of the vault however it is written', () {
    const probe = '''
import 'package:secrets/secrets.dart'
    show
        GarageKeys,
        Secrets;
import "package:secrets/secrets.dart";
import 'package:secrets/secrets.dart' as vault show GarageKeys;
export 'package:secrets/secrets.dart' show GarageKeys;
''';
    final directives = _directives(probe).toList();

    expect(directives, hasLength(4));
    expect(directives.map(_narrowImport.firstMatch).map((match) => match?[1]), [
      'GarageKeys, Secrets',
      null,
      null,
      null,
    ]);
  });
}
