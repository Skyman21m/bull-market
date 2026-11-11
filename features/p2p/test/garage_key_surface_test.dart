import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

/// What the Garage Key repository lets out of the one class allowed to read a stored key.
///
/// The custody gate checks where the bytes of a key are read, not where they go afterwards: a public method of `GarageKeyRepositoryImpl` returning a copy of them, called from another file, would pass it.
/// So the public members of that class are pinned here, from its syntax tree, to the methods of its interface, and the return types of the interface to the ones allowed today.
void main() {
  // Tests run with the package directory as working directory.
  CompilationUnit unitOf(String path) =>
      parseString(content: File(path).readAsStringSync()).unit;

  // The methods of the interface and what each returns: nothing, whether a key is stored, or a robot derived from it.
  const allowed = {
    'create': 'Future<Result<void, P2pFailure>>',
    'import': 'Future<Result<void, P2pFailure>>',
    'exists': 'Future<Result<bool, P2pFailure>>',
    'firstUsableRobot': 'Future<Result<GarageRobot, P2pFailure>>',
    'delete': 'Future<Result<void, P2pFailure>>',
  };

  test('the interface returns nothing, whether a key is stored, or robots', () {
    final unit = unitOf(
      'lib/src/domain/repositories/garage_key_repository.dart',
    );

    final interface = unit.declarations.single as ClassDeclaration;
    expect(interface.namePart.typeName.lexeme, 'GarageKeyRepository');
    expect(interface.interfaceKeyword, isNotNull);
    final members = _membersOf(interface);
    expect(members, everyElement(isA<MethodDeclaration>()));
    expect({
      for (final method in members.cast<MethodDeclaration>())
        method.name.lexeme: method.returnType?.toSource(),
    }, allowed);
  });

  test(
    'the repository has no public member but the methods of its interface',
    () {
      final unit = unitOf('lib/src/data/garage_key_repository_impl.dart');

      final repository = unit.declarations.single as ClassDeclaration;
      expect(repository.namePart.typeName.lexeme, 'GarageKeyRepositoryImpl');
      expect(_waysOut(repository), isEmpty);
      expect([
        for (final member in _membersOf(repository))
          if (member case MethodDeclaration(
            :final name,
          ) when !name.lexeme.startsWith('_'))
            name.lexeme,
      ], unorderedEquals(allowed.keys));
    },
  );

  test('the check refuses each public way out of the repository', () {
    // A public method and a public static field are the two ways out a review found the custody gate blind to.
    for (final member in [
      'Uint8List bytesOf(GarageKeyMaterial m) => m.bytes;',
      'static final reveal = (GarageKeyMaterial m) => m.bytes;',
      '@override\n  Uint8List get bytes => Uint8List(0);',
      'GarageKeyRepositoryImpl.leaky(this.bytes);',
    ]) {
      final unit = parseString(
        content: 'final class GarageKeyRepositoryImpl {\n  $member\n}\n',
      ).unit;

      expect(
        _waysOut(unit.declarations.single as ClassDeclaration),
        hasLength(1),
        reason: member,
      );
    }
  });
}

/// The members of [declaration], or none when it has no body.
List<ClassMember> _membersOf(ClassDeclaration declaration) =>
    switch (declaration.body) {
      BlockClassBody(:final members) => members,
      _ => const [],
    };

/// The members of [repository] that another file could reach, other than its unnamed constructor and its overrides of instance methods: public fields, getters, setters, operators, static members and named constructors.
List<ClassMember> _waysOut(ClassDeclaration repository) => [
  for (final member in _membersOf(repository))
    if (!_closed(member)) member,
];

bool _closed(ClassMember member) => switch (member) {
  ConstructorDeclaration(:final name) =>
    name == null || name.lexeme.startsWith('_'),
  FieldDeclaration(:final fields) => fields.variables.every(
    (variable) => variable.name.lexeme.startsWith('_'),
  ),
  MethodDeclaration(:final name) when name.lexeme.startsWith('_') => true,
  MethodDeclaration(
    isStatic: false,
    isGetter: false,
    isSetter: false,
    isOperator: false,
  ) =>
    member.metadata.any((annotation) => annotation.name.name == 'override'),
  _ => false,
};
