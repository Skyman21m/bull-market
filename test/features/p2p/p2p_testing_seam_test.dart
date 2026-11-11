import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every Dart file under [directory], or none when it does not exist.
Iterable<File> _dartFiles(Directory directory) => directory.existsSync()
    ? directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
    : const [];

/// The `import`, `export` and `part` directives of [file], each on one line once the formatter's line breaks are removed.
Iterable<String> _directives(File file) => RegExp(
  r'''^\s*(?:import|export|part)\s[^;]*;''',
  multiLine: true,
).allMatches(file.readAsStringSync()).map((match) => match[0] ?? '');

void main() {
  // Tests of the app run with the repository root as working directory.
  final appLibraries = [
    ..._dartFiles(Directory('lib')),
    for (final feature in Directory(
      'features',
    ).listSync().whereType<Directory>())
      ..._dartFiles(Directory('${feature.path}/lib')),
    for (final package in Directory(
      'packages',
    ).listSync().whereType<Directory>())
      ..._dartFiles(Directory('${package.path}/lib')),
  ];

  test('the libraries of the app are found', () {
    expect(appLibraries.length, greaterThan(500));
    expect(
      appLibraries.map((file) => file.path),
      containsAll([
        'lib/locator.dart',
        'features/p2p/lib/p2p.dart',
        'features/p2p/lib/testing.dart',
      ]),
    );
  });

  test('no library of the app imports the test seam of P2P', () {
    // `package:p2p/testing.dart` hands out the real Tor transport and the robot types: it is for tests only.
    final offenders = [
      for (final file in appLibraries)
        if (file.path != 'features/p2p/lib/testing.dart')
          for (final directive in _directives(file))
            if (directive.contains('package:p2p/testing.dart') ||
                (file.path.startsWith('features/p2p/lib/') &&
                    RegExp(r'''['"/]testing\.dart['"]''').hasMatch(directive)))
              '${file.path}: ${directive.trim()}',
    ];

    expect(offenders, isEmpty);
  });

  test('the check sees an import of the seam, however it is written', () {
    final folder = Directory.systemTemp.createTempSync();
    addTearDown(() => folder.deleteSync(recursive: true));
    final probe = File('${folder.path}/a.dart')
      ..writeAsStringSync('''
import 'dart:io';
import 'package:p2p/testing.dart'
    show liveCoordinatorTransportForTesting;
export "../testing.dart";
''');

    expect(_directives(probe), hasLength(3));
    expect(
      _directives(probe).where((d) => d.contains('testing.dart')),
      hasLength(2),
    );
  });
}
