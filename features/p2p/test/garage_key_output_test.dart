import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/key_output.dart';

/// Where a Garage Key could leave the app as text: a print, the project logger, `stdout` or `dart:developer`.
///
/// The files that handle a key may not reach any of them: their imports and the names they use are read from the syntax tree.
/// What runs is then captured, prints and the logger's own file, while keys are created, imported, read, used and deleted: nothing captured may hold a key.
void main() {
  // Tests run with the package directory as working directory.
  final libraries = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.contains('/generated/'))
      .toList();

  // Every file whose name speaks of a Garage Key or a robot: the repository, its interface, the use cases, the cubits and the screens of the Garage.
  final keyFiles = [
    for (final file in libraries)
      if (RegExp('garage|robot').hasMatch(file.path.split('/').last) ||
          file.path.contains('/garage/'))
        file.path,
  ];

  group('the files that handle a key', () {
    test('are found', () {
      expect(
        keyFiles,
        containsAll([
          'lib/src/data/garage_key_repository_impl.dart',
          'lib/src/domain/repositories/garage_key_repository.dart',
          'lib/src/domain/usecases/import_garage_key_usecase.dart',
          'lib/src/domain/usecases/derive_first_robot_usecase.dart',
        ]),
      );
    });

    test('import nothing that prints or logs', () {
      final offenders = <String>[];
      for (final path in keyFiles) {
        for (final uri in _imports(File(path).readAsStringSync())) {
          if (_outputLibraries.any(uri.startsWith)) offenders.add('$path $uri');
        }
      }

      expect(offenders, isEmpty);
    });

    test('name nothing that prints or logs', () {
      final offenders = <String>[];
      for (final path in keyFiles) {
        for (final name in _outputNames(File(path).readAsStringSync())) {
          offenders.add('$path $name');
        }
      }

      expect(offenders, isEmpty);
    });

    test('the repository imports exactly what it needs', () {
      expect(
        _imports(
          File(
            'lib/src/data/garage_key_repository_impl.dart',
          ).readAsStringSync(),
        ),
        unorderedEquals([
          'package:primitives/primitives.dart',
          'package:robosats/robosats.dart',
          'package:secrets/secrets.dart',
          '../domain/network_garage_key.dart',
          '../domain/p2p_failure.dart',
          '../domain/repositories/garage_key_repository.dart',
        ]),
      );
    });

    test('the checks see each way out', () {
      const probe = '''
import 'dart:io';
import 'dart:developer' as dev;
import 'package:bull_logger/bull_logger.dart';
import "package:logging/logging.dart";
import 'package:flutter/foundation.dart' show debugPrint;
void f(String key) {
  print(key);
  debugPrint(key);
  stdout.writeln(key);
  stderr.write(key);
  dev.log(key);
  log.fine(key);
  Logger('x').info(key);
}
''';

      expect(
        _imports(probe).where((uri) => _outputLibraries.any(uri.startsWith)),
        hasLength(5),
      );
      expect(_outputNames(probe).toSet(), {
        'print',
        'debugPrint',
        'stdout',
        'stderr',
        'log',
        'Logger',
      });
    });
  });

  test(
    'nothing printed or logged while keys are created, imported, read, used and deleted holds a key',
    () async {
      FakeSecureStoragePlatform().install();
      final repository = GarageKeyRepositoryImpl(
        Secrets(scratchDirectory: () async => '.').garageKeys(),
      );
      // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
      final fixedKey = switch (GarageKey.fromBytes(
        Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      T ok<T>(Result<T, Failure> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('expected a value, got $failure'),
      };

      final created = <GarageKey>[];
      final output = await captureKeyOutput(() async {
        ok(await repository.create(RobosatsNetwork.testnet));
        ok(await repository.import(RobosatsNetwork.mainnet, fixedKey));
        for (final network in RobosatsNetwork.values) {
          ok(await repository.exists(network));
          ok(await repository.firstUsableRobot(network));
        }
        // The created key, read through the vault itself: the test looks for it, never shows it.
        created.add(switch (await Secrets(
          scratchDirectory: () async => '.',
        ).garageKeys().read(slot: GarageKeySlot.testnet)) {
          Ok(:final value) => switch (GarageKey.fromBytes(
            Uint8List.fromList(value.bytes),
          )) {
            Ok(:final value) => value,
            Err() => fail('not a key'),
          },
          Err() => fail('the created key cannot be read back'),
        });
        for (final network in RobosatsNetwork.values) {
          ok(await repository.delete(network));
        }
      });

      expect(created, hasLength(1));
      expectNoKeyIn(output, [...created, fixedKey]);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// The libraries through which text can leave the app: the console, the project logger and the platform's own logs.
const _outputLibraries = [
  'dart:io',
  'dart:developer',
  'package:bull_logger/',
  'package:logging/',
  'package:flutter/foundation.dart',
];

/// The library each import, export and part directive of [source] names, read from the syntax tree.
List<String> _imports(String source) => [
  for (final directive in parseString(content: source).unit.directives)
    if (directive case UriBasedDirective(:final uri)) uri.stringValue ?? '?',
];

/// The names of [source] that print or log: `print`, `debugPrint`, `stdout`, `stderr`, the project's `log` and a `Logger`.
List<String> _outputNames(String source) {
  final names = <String>[];
  parseString(content: source).unit.accept(_NameVisitor(names));
  return names;
}

final class _NameVisitor extends RecursiveAstVisitor<void> {
  final List<String> names;

  _NameVisitor(this.names);

  static const _watched = {
    'print',
    'debugPrint',
    'debugPrintThrottled',
    'stdout',
    'stderr',
    'log',
    'Logger',
  };

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_watched.contains(node.name)) names.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (_watched.contains(node.name.lexeme)) names.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}
