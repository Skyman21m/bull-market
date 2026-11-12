import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';

/// Where the bindings of the robots can be reached, in every library of `features/p2p/lib`: what refers to the robot requests, the robot credentials and the bindings is resolved by the analyzer; what imports the database and what its SQL says is read from the syntax tree.
///
/// The behaviour is tested elsewhere (`robot_binding_repository_test.dart`, `robot_usecases_test.dart`): these keep it from being walked around inside the feature.
/// They see `features/p2p/lib` only: code elsewhere that holds a `CoordinatorClient` and a robot could still request one, which is why the robot types stay out of the app-facing library (`p2p_feature_test.dart`).
void main() {
  // Tests run with the package directory as working directory.
  final libraries = {
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File &&
          file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart') &&
          !file.path.contains('/generated/'))
        file.path: _Facts.of(file.readAsStringSync()),
  };

  Set<String> where(bool Function(_Facts facts) test) => {
    for (final MapEntry(key: path, value: facts) in libraries.entries)
      if (test(facts)) path,
  };

  test('the libraries are found', () {
    expect(
      libraries.keys,
      containsAll([
        'lib/src/data/p2p_database.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
      ]),
    );
  });

  group(
    'resolved by the analyzer, so that a tear-off, a cascade, a prefix or an implementation is the member it names,',
    () {
      late AnalysisContextCollection collection;
      // Every library of the feature but the generated ones: the watched members each one refers to.
      late Map<String, Set<String>> references;

      setUpAll(() async {
        collection = AnalysisContextCollection(
          includedPaths: [Directory.current.path],
          sdkPath: _dartSdkPath(),
        );
        references = {
          for (final path in libraries.keys)
            path: await _referencesIn(collection, path),
        };
      });

      Set<String> referring(String member) => {
        for (final MapEntry(key: path, value: members) in references.entries)
          if (members.contains(member)) path,
      };

      test(
        'the evasions of a check by names are seen',
        () async {
          expect(
            (await _referencesIn(
              collection,
              'test/fixtures/robot_request_makers.dart',
            )).where((reference) => !reference.startsWith('type ')),
            unorderedEquals({
              'CoordinatorClient.fetchKnownRobot',
              'CoordinatorClient.fetchRobot',
              'RobotIdentity.authorizationHeader',
              'RobotIdentity.firstContactAuthorizationHeader',
              'CoordinatorTransport.send',
              'RobotBindingRepository.bind',
            }),
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test(
        'in features/p2p/lib, only the use case that binds a robot requests one or binds',
        () {
          for (final member in [
            'CoordinatorClient.fetchRobot',
            'CoordinatorClient.fetchKnownRobot',
            'RobotBindingRepository.bind',
          ]) {
            expect(referring(member), {
              'lib/src/domain/usecases/fetch_robot_usecase.dart',
            }, reason: member);
          }
          // Nothing in the feature builds a robot's credential or sends a raw request: the coordinator client of `package:robosats` does both, for that use case.
          for (final member in [
            'RobotIdentity.authorizationHeader',
            'RobotIdentity.firstContactAuthorizationHeader',
            'CoordinatorTransport.send',
          ]) {
            expect(referring(member), isEmpty, reason: member);
          }
        },
      );

      test(
        'only the draw and the import write a key, and record its history',
        () {
          expect(referring('GarageKeyRepository.create'), {
            'lib/src/domain/usecases/generate_garage_key_usecase.dart',
          });
          expect(referring('RobotBindingRepository.recordGeneratedKey'), {
            'lib/src/domain/usecases/generate_garage_key_usecase.dart',
          });
          expect(referring('GarageKeyRepository.import'), {
            'lib/src/domain/usecases/import_garage_key_usecase.dart',
          });
          expect(referring('RobotBindingRepository.recordImportedKey'), {
            'lib/src/domain/usecases/import_garage_key_usecase.dart',
          });
          // And only the repository asks the vault to write one.
          for (final member in ['GarageKeys.create', 'GarageKeys.import']) {
            expect(referring(member), {
              'lib/src/data/garage_key_repository_impl.dart',
            }, reason: member);
          }
        },
      );

      test('deleting a key cannot reach the bindings', () {
        expect(
          references['lib/src/domain/usecases/delete_garage_key_usecase.dart'],
          isNot(
            anyOf(
              contains('type RobotBindingRepository'),
              contains('RobotBindingRepository.bind'),
            ),
          ),
        );
      });
    },
  );

  test('only the data layer and the composition reach the database', () {
    expect(
      where(
        (facts) =>
            facts.imports.any((uri) => uri.endsWith('p2p_database.dart')),
      ),
      {
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/src/p2p_locator.dart',
        'lib/testing.dart',
      },
    );
    expect(
      where(
        (facts) => facts.imports.any((uri) => uri.startsWith('package:drift')),
      ),
      {
        'lib/src/data/p2p_database.dart',
        'lib/src/data/robot_binding_repository_impl.dart',
        'lib/testing.dart',
      },
    );
    expect(where((facts) => facts.constructed.contains('P2pDatabase.open')), {
      'lib/src/p2p_locator.dart',
    });
    expect(
      where((facts) => facts.constructed.contains('P2pDatabase.forTesting')),
      {'lib/testing.dart'},
    );
  });

  test('nothing changes or deletes a binding', () {
    final repository =
        libraries['lib/src/data/robot_binding_repository_impl.dart'] ??
        fail('no repository');
    final database =
        libraries['lib/src/data/p2p_database.dart'] ?? fail('no database');

    for (final facts in [repository, database]) {
      expect(
        facts.invoked.intersection({
          'delete',
          'deleteWhere',
          'deleteAll',
          'update',
          'replace',
          'write',
          'customUpdate',
          'customStatement',
          'insertOnConflictUpdate',
          'insertAllOnConflictUpdate',
          'deleteTable',
          'drop',
        }),
        isEmpty,
      );
      expect(facts.names, isNot(contains('InsertMode')));
      for (final text in facts.strings) {
        expect(
          RegExp(
            r'\b(delete|update|drop|replace|alter)\b',
            caseSensitive: false,
          ).hasMatch(text),
          isFalse,
          reason: text,
        );
      }
    }
    // The one upsert moves the history of a key to `imported`, never a binding.
    expect(
      repository.namesByMethod.entries
          .where((entry) => entry.value.contains('DoUpdate'))
          .map((entry) => entry.key),
      ['recordImportedKey'],
    );
  });
}

/// What one library imports, names, invokes, constructs and spells out in strings.
final class _Facts {
  final List<String> imports;
  final Set<String> names;
  final Set<String> invoked;
  final Set<String> constructed;
  final List<String> strings;

  /// The names used in the body of each method or function, by its name.
  final Map<String, Set<String>> namesByMethod;

  _Facts(
    this.imports,
    this.names,
    this.invoked,
    this.constructed,
    this.strings,
    this.namesByMethod,
  );

  factory _Facts.of(String source) {
    final unit = parseString(content: source).unit;
    final visitor = _FactsVisitor();
    unit.accept(visitor);
    return _Facts(
      [
        for (final directive in unit.directives)
          if (directive case UriBasedDirective(:final uri))
            uri.stringValue ?? '?',
      ],
      visitor.names,
      visitor.invoked,
      visitor.constructed,
      visitor.strings,
      visitor.namesByMethod,
    );
  }
}

final class _FactsVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = {};
  final Set<String> invoked = {};
  final Set<String> constructed = {};
  final List<String> strings = [];
  final Map<String, Set<String>> namesByMethod = {};
  String? _method;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final outer = _method;
    _method = node.name.lexeme;
    super.visitMethodDeclaration(node);
    _method = outer;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    if (_method case final method?) {
      (namesByMethod[method] ??= {}).add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    if (_method case final method?) {
      (namesByMethod[method] ??= {}).add(node.name.lexeme);
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    invoked.add(node.methodName.name);
    // `P2pDatabase.open(…)` parses as an invocation of `open` on `P2pDatabase` when the parser does not resolve it.
    if (node.target case SimpleIdentifier(:final name)) {
      constructed.add('$name.${node.methodName.name}');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final named = node.constructorName.name?.name;
    constructed.add(named == null ? type : '$type.$named');
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    strings.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    strings.add(node.stringValue ?? node.toSource());
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    strings.add(node.toSource());
    super.visitStringInterpolation(node);
  }
}

/// The members watched by [_referencesIn], by the class that declares them and its library: a member of a subtype, an implementation of the interface included, counts as the member of its supertype.
const _watched = {
  'CoordinatorClient': ('package:robosats/', {'fetchRobot', 'fetchKnownRobot'}),
  'RobotIdentity': (
    'package:robosats/',
    {'authorizationHeader', 'firstContactAuthorizationHeader'},
  ),
  'CoordinatorTransport': ('package:robosats/', {'send'}),
  'RobotBindingRepository': (
    'package:p2p/',
    {'bind', 'recordGeneratedKey', 'recordImportedKey'},
  ),
  'GarageKeyRepository': ('package:p2p/', {'create', 'import'}),
  'GarageKeys': ('package:secrets/', {'create', 'import'}),
};

/// Each watched member the library at [path] refers to, as `Class.member`, and each watched class it names, as `type Class`; called, torn off, in a cascade, through a prefix or an implementation alike.
Future<Set<String>> _referencesIn(
  AnalysisContextCollection collection,
  String path,
) async {
  final absolute = File(path).absolute.path;
  final result = await collection
      .contextFor(absolute)
      .currentSession
      .getResolvedUnit(absolute);
  if (result is! ResolvedUnitResult) return {'$path: unresolved'};
  final found = <String>{};
  result.unit.accept(_ReferenceVisitor(found));
  return found;
}

final class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> found;

  _ReferenceVisitor(this.found);

  /// The watched class [type] is, or implements, with the members watched in it, if any.
  static ({String name, Set<String> members})? _watchedOwner(
    InterfaceElement type,
  ) {
    for (final candidate in [
      type,
      for (final supertype in type.allSupertypes) supertype.element,
    ]) {
      final name = candidate.name;
      if (_watched[name] case (final library, final members)
          when name != null &&
              candidate.library.uri.toString().startsWith(library)) {
        return (name: name, members: members);
      }
    }
    return null;
  }

  void _check(Element? element) {
    if (element case InterfaceElement()) {
      if (_watchedOwner(element) case (:final name, members: _)?) {
        found.add('type $name');
      }
    }
    if (element case ExecutableElement(
      :final name?,
      enclosingElement: final InterfaceElement owner,
    )) {
      if (_watchedOwner(owner) case (name: final ownerName, :final members)?
          when members.contains(name)) {
        found.add('$ownerName.$name');
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _check(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _check(node.element);
    super.visitNamedType(node);
  }

  /// A `[name]` in a doc comment names a member without using it.
  @override
  void visitCommentReference(CommentReference node) {}
}

String _dartSdkPath() {
  var directory = Directory('.').absolute;
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final packages =
          (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
      final flutter = packages.cast<Map>().firstWhere(
        (p) => p['name'] == 'flutter',
      );
      final root = config.uri
          .resolve(flutter['rootUri'] as String)
          .toFilePath();
      return '${Directory(root).parent.parent.path}/bin/cache/dart-sdk';
    }
    if (directory.parent.path == directory.path) {
      throw StateError('No package_config.json');
    }
    directory = directory.parent;
  }
}
