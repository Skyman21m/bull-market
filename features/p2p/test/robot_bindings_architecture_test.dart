import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Where the bindings of the robots can be reached, read from the syntax tree of every library of the feature.
///
/// The behaviour is tested elsewhere (`robot_binding_repository_test.dart`, `robot_usecases_test.dart`): these keep it from being walked around.
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

  test('every request of a robot goes through the use case that binds it', () {
    expect(
      where(
        (facts) =>
            facts.invoked.contains('fetchRobot') ||
            facts.invoked.contains('fetchKnownRobot'),
      ),
      {'lib/src/domain/usecases/fetch_robot_usecase.dart'},
    );
    expect(where((facts) => facts.invoked.contains('bind')), {
      'lib/src/domain/usecases/fetch_robot_usecase.dart',
    });
  });

  test('only the draw and the import record the history of a key', () {
    expect(where((facts) => facts.invoked.contains('recordGeneratedKey')), {
      'lib/src/domain/usecases/generate_garage_key_usecase.dart',
    });
    expect(where((facts) => facts.invoked.contains('recordImportedKey')), {
      'lib/src/domain/usecases/import_garage_key_usecase.dart',
    });
    // Deleting a key leaves its bindings: the use case cannot even reach them.
    expect(
      libraries['lib/src/domain/usecases/delete_garage_key_usecase.dart']
          ?.names,
      isNot(contains('RobotBindingRepository')),
    );
  });

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
