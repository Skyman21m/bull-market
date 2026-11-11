import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// What `GarageKeyView` lets out: the custody gate allows `GarageKey.revealBech32` in any member of the class, so a public static, a getter returning the text or a tear-off of `revealBech32`, called from another file, would pass it.
///
/// So its members are pinned here, from the syntax tree: the two fields, the constructor and `build`, nothing else; and `revealBech32` appears exactly twice, each time called on `garageKey`: as the text of the `Text`, and as the text given to `clipboard.copy`.
void main() {
  // Tests run with the package directory as working directory.
  const path = 'lib/src/ui/widgets/garage_key_view.dart';

  test('the view has two fields, its constructor and build, nothing else', () {
    final view = _classNamed(_unit(File(path).readAsStringSync()));

    expect(_surface(view), [
      'field final GarageKey garageKey',
      'field final GarageKeyClipboard clipboard',
      'constructor GarageKeyView({super.key, required this.garageKey, required this.clipboard})',
      'method @override Widget build(BuildContext context)',
    ]);
  });

  test('the key becomes text only in the Text and in clipboard.copy', () {
    expect(_reveals(_unit(File(path).readAsStringSync())), [
      'Text(1)',
      'clipboard.copy(2)',
    ]);
  });

  test('the checks see each way out', () {
    for (final (member, kind) in [
      ('static String reveal(GarageKey k) => k.revealBech32();', 'surface'),
      ('String get text => garageKey.revealBech32();', 'surface'),
      ('String Function() get reveal => garageKey.revealBech32;', 'surface'),
      ('final String text = "";', 'surface'),
      ('GarageKeyView.named(this.garageKey, this.clipboard);', 'surface'),
    ]) {
      final view = _classNamed(
        _unit('class GarageKeyView extends StatelessWidget {\n  $member\n}\n'),
      );
      expect(_surface(view), hasLength(1), reason: '$kind: $member');
    }
    for (final source in [
      'Widget f(GarageKey garageKey) => Text(garageKey.revealBech32());',
      'f(GarageKey garageKey) => print(garageKey.revealBech32());',
      'f(GarageKey garageKey) => garageKey.revealBech32;',
      'f(GarageKey other) => Text(other.revealBech32());',
      'f(GarageKey garageKey) => Text("", semanticsLabel: garageKey.revealBech32());',
      'f(GarageKey garageKey, c) => c.copy(garageKey, garageKey.revealBech32());',
    ]) {
      expect(_reveals(_unit(source)), hasLength(1), reason: source);
    }
    expect(
      _reveals(
        _unit('f(GarageKey garageKey) => print(garageKey.revealBech32());'),
      ),
      ['print(1)'],
    );
    expect(
      _reveals(
        _unit('f(GarageKey garageKey) => Text(garageKey.revealBech32());'),
      ),
      ['Text(1)'],
    );
  });
}

CompilationUnit _unit(String source) => parseString(content: source).unit;

ClassDeclaration _classNamed(CompilationUnit unit) => unit.declarations
    .whereType<ClassDeclaration>()
    .singleWhere((c) => c.namePart.typeName.lexeme == 'GarageKeyView');

/// Each member of [view], as `<kind> <source without body>`.
List<String> _surface(ClassDeclaration view) => [
  for (final member in switch (view.body) {
    BlockClassBody(:final members) => members,
    _ => const <ClassMember>[],
  })
    switch (member) {
      FieldDeclaration(:final fields, :final isStatic) =>
        'field ${isStatic ? 'static ' : ''}${fields.toSource()}',
      ConstructorDeclaration(:final name, :final parameters) =>
        'constructor GarageKeyView${name == null ? '' : '.${name.lexeme}'}${parameters.toSource()}',
      MethodDeclaration() =>
        'method ${[for (final a in member.metadata) a.toSource(), if (member.isStatic) 'static', if (member.isGetter) 'get', member.returnType?.toSource(), member.name.lexeme].join(' ')}${member.parameters?.toSource() ?? ''}',
      _ => 'other ${member.toSource()}',
    },
];

/// Every use of `revealBech32` in the unit: `<callee>(<position>)` when it is called on `garageKey` and given as the [position]th argument of a call, and `other` otherwise.
List<String> _reveals(CompilationUnit unit) {
  final found = <String>[];
  unit.accept(_RevealVisitor(found));
  return found;
}

final class _RevealVisitor extends RecursiveAstVisitor<void> {
  final List<String> found;

  _RevealVisitor(this.found);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'revealBech32') found.add(_use(node));
    super.visitSimpleIdentifier(node);
  }

  static String _use(SimpleIdentifier node) {
    final call = node.parent;
    if (call is! MethodInvocation ||
        call.methodName != node ||
        call.argumentList.arguments.isNotEmpty ||
        call.target?.toSource() != 'garageKey') {
      return 'other';
    }
    final arguments = call.parent;
    if (arguments is! ArgumentList) return 'other';
    final position = arguments.arguments.indexOf(call) + 1;
    return switch (arguments.parent) {
      MethodInvocation(:final target, :final methodName) =>
        '${target == null ? '' : '${target.toSource()}.'}${methodName.name}($position)',
      InstanceCreationExpression(:final constructorName) =>
        '${constructorName.toSource()}($position)',
      _ => 'other',
    };
  }
}
