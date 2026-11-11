import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:test/test.dart';

/// What the Garage Key repository lets out of the one class allowed to read a stored key.
///
/// The custody gate checks where the bytes of a key are read, not where they go afterwards: a public method of `GarageKeyRepositoryImpl` returning a copy of them, called from another file, would pass it.
/// So the public members of that class are pinned here, from its syntax tree, to the methods of its interface, and the full signature of each method to the ones allowed today.
/// A `part` file would add members the parsed file does not show, so none is allowed, and the failures the repository returns may carry no field but the reason of an invalid key.
void main() {
  // Tests run with the package directory as working directory.
  CompilationUnit unitOf(String path) =>
      parseString(content: File(path).readAsStringSync()).unit;

  // The methods of the interface, each with its full signature: nothing, whether a key is stored, or a robot derived from it.
  const allowed = {
    'create':
        'Future<Result<void, P2pFailure>> create(RobosatsNetwork network)',
    'import':
        'Future<Result<void, P2pFailure>> import(RobosatsNetwork network, GarageKey key)',
    'exists':
        'Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network)',
    'firstUsableRobot':
        'Future<Result<GarageRobot, P2pFailure>> firstUsableRobot(RobosatsNetwork network)',
    'delete':
        'Future<Result<void, P2pFailure>> delete(RobosatsNetwork network)',
  };

  test('the interface returns nothing, whether a key is stored, or robots', () {
    final unit = unitOf(
      'lib/src/domain/repositories/garage_key_repository.dart',
    );

    expect(_parts(unit), isEmpty);
    final interface = unit.declarations.single as ClassDeclaration;
    expect(interface.namePart.typeName.lexeme, 'GarageKeyRepository');
    expect(interface.interfaceKeyword, isNotNull);
    final members = _membersOf(interface);
    expect(members, everyElement(isA<MethodDeclaration>()));
    expect({
      for (final method in members.cast<MethodDeclaration>())
        method.name.lexeme: _signature(method),
    }, allowed);
  });

  test(
    'the repository has no public member but the methods of its interface',
    () {
      final unit = unitOf('lib/src/data/garage_key_repository_impl.dart');

      expect(_parts(unit), isEmpty);
      final repository = unit.declarations.single as ClassDeclaration;
      expect(repository.namePart.typeName.lexeme, 'GarageKeyRepositoryImpl');
      expect(_waysOut(repository), isEmpty);
      expect({
        for (final member in _membersOf(repository))
          if (member case MethodDeclaration(
            :final name,
          ) when !name.lexeme.startsWith('_'))
            name.lexeme: _signature(member),
      }, allowed);
    },
  );

  test('the repository holds the vault handle and nothing else', () {
    final repository =
        unitOf(
              'lib/src/data/garage_key_repository_impl.dart',
            ).declarations.single
            as ClassDeclaration;

    expect(_fieldsOf(repository), ['final GarageKeys _garageKeys']);
    final constructors = _membersOf(
      repository,
    ).whereType<ConstructorDeclaration>().toList();
    expect(constructors, hasLength(1));
    final constructor = constructors.single;
    expect(constructor.name, isNull);
    expect(constructor.parameters.toSource(), '(this._garageKeys)');
    expect(constructor.initializers, isEmpty);
    expect(constructor.redirectedConstructor, isNull);
  });

  test('the failures carry no field but the reason of an invalid key', () {
    final unit = unitOf('lib/src/domain/p2p_failure.dart');

    expect(_parts(unit), isEmpty);
    final fields = {
      for (final declaration in unit.declarations.whereType<ClassDeclaration>())
        declaration.namePart.typeName.lexeme: _fieldsOf(declaration),
    };
    expect(fields, containsPair('GarageKeyMissingFailure', isEmpty));
    expect(fields.values.expand((f) => f), ['final GarageKeyFailure reason']);
    expect(fields['GarageKeyInvalidFailure'], [
      'final GarageKeyFailure reason',
    ]);
    expect(unit.declarations, everyElement(isA<ClassDeclaration>()));
  });

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

  test('the checks see a part, a second field and a changed signature', () {
    final unit = parseString(
      content: '''
part 'more.dart';
final class GarageKeyRepositoryImpl {
  final GarageKeys _garageKeys;
  Uint8List? _copy;
  const GarageKeyRepositoryImpl(this._garageKeys, [this._copy]);
  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network, {bool all = true}) async => const Ok(null);
}
''',
    ).unit;
    final repository = unit.declarations.single as ClassDeclaration;

    expect(_parts(unit), hasLength(1));
    expect(_fieldsOf(repository), hasLength(2));
    expect(
      _membersOf(
        repository,
      ).whereType<ConstructorDeclaration>().single.parameters.toSource(),
      isNot('(this._garageKeys)'),
    );
    expect(
      _signature(_membersOf(repository).whereType<MethodDeclaration>().single),
      isNot(allowed['delete']),
    );
  });
}

/// The `part` and `part of` directives of [unit].
List<Directive> _parts(CompilationUnit unit) => [
  for (final directive in unit.directives)
    if (directive is PartDirective || directive is PartOfDirective) directive,
];

/// The members of [declaration], or none when it has no body.
List<ClassMember> _membersOf(ClassDeclaration declaration) =>
    switch (declaration.body) {
      BlockClassBody(:final members) => members,
      _ => const [],
    };

/// Every field [declaration] declares, static or not, as `<keywords> <type> <name>`.
List<String> _fieldsOf(ClassDeclaration declaration) => [
  for (final member in _membersOf(declaration))
    if (member is FieldDeclaration)
      for (final variable in member.fields.variables)
        [
          if (member.isStatic) 'static',
          ?member.fields.keyword?.lexeme,
          ?member.fields.type?.toSource(),
          variable.name.lexeme,
        ].join(' '),
];

/// `<return type> <name><parameters>`, as the syntax tree prints them.
String _signature(MethodDeclaration method) =>
    '${method.returnType?.toSource()} ${method.name.lexeme}${method.parameters?.toSource()}';

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
