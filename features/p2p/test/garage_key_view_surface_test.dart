import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// What `GarageKeyView` lets out: the custody gate allows `GarageKey.revealBech32` in any member of the class, so a public static, a getter returning the text or a tear-off of `revealBech32`, called from another file, would pass it.
///
/// So its members are pinned here, from the syntax tree: the two fields, the constructor, `build` and the static `copy` (#318), which returns only whether the clipboard took the key, nothing else; and `revealBech32` appears exactly twice, each time called on `garageKey`: as the text of the `Text`, and as the text given to `clipboard.copy` in `copy`, which the view's button calls too.
/// Those names mean the widget of Flutter and the helper of the feature only because the file's imports and declarations are pinned too.
void main() {
  // Tests run with the package directory as working directory.
  const path = 'lib/src/ui/widgets/garage_key_view.dart';

  test(
    'the view has two fields, its constructor, its copy and build, nothing else',
    () {
      final view = _classNamed(_unit(File(path).readAsStringSync()));

      expect(_surface(view), [
        'field final GarageKey garageKey',
        'field final GarageKeyClipboard clipboard',
        'constructor GarageKeyView({super.key, required this.garageKey, required this.clipboard})',
        'method static Future<bool> copy(GarageKeyClipboard clipboard, GarageKey garageKey)',
        'method @override Widget build(BuildContext context)',
      ]);
    },
  );

  test(
    'copy hands the text to the clipboard helper and returns nothing else',
    () {
      // Its body, as written: a text returned, kept or given elsewhere would show here.
      final view = _classNamed(_unit(File(path).readAsStringSync()));
      final copy = switch (view.body) {
        BlockClassBody(:final members) =>
          members.whereType<MethodDeclaration>().singleWhere(
            (m) => m.name.lexeme == 'copy',
          ),
        _ => throw StateError('no body'),
      };

      expect(
        copy.body.toSource(),
        '=> clipboard.copy(garageKey, garageKey.revealBech32());',
      );
    },
  );

  test('the view imports exactly its libraries, and declares nothing else', () {
    // A `Text` or a `copy` of another library, through a `hide`, a new import or a declaration of this file, would keep the key: the names of the checks below are the ones of these libraries.
    final unit = _unit(File(path).readAsStringSync());

    expect(_directives(unit), [
      "import 'dart:async';",
      "import 'package:bull_ui/bull_ui.dart';",
      "import 'package:flutter/material.dart';",
      "import 'package:robosats/robosats.dart' show GarageKey;",
      "import '../../../generated/l10n/p2p_localizations.dart';",
      "import 'garage_key_clipboard.dart';",
    ]);
    expect(_declarations(unit), [
      'GarageKeyView',
      '_CopyButton',
      '_CopyButtonState',
    ]);
  });

  test('the check sees a hidden Text and a look-alike of another file', () {
    final shadowed = _unit('''
import 'dart:async';
import 'package:bull_ui/bull_ui.dart' hide Text;
import 'package:flutter/material.dart' hide Text;
import 'key_text.dart';
class Text {}
class GarageKeyView {}
''');

    expect(
      _directives(shadowed),
      isNot(contains("import 'package:flutter/material.dart';")),
    );
    expect(_directives(shadowed), contains("import 'key_text.dart';"));
    expect(_declarations(shadowed), contains('Text'));
  });

  test('the key becomes text only in the Text and in clipboard.copy', () {
    // In the order of the file: `copy`, then `build`.
    expect(_reveals(_unit(File(path).readAsStringSync())), [
      'clipboard.copy(2)',
      'Text(1)',
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

  test(
    'GarageKeyView.copy is called only by the view itself and by « Back it up! » after the re-authentication (security review of #320, C1)',
    () {
      expect(_copyCallers(_libraryFiles()), [
        'lib/src/ui/widgets/store_token_dialog.dart _StoreTokenDialogState._copy after askReauthentication',
      ]);
    },
  );

  test(
    'the check of the callers sees a call elsewhere, a tear-off, and a call before the re-authentication',
    () {
      expect(
        _copyCallers({
          'lib/src/ui/x.dart':
              'f(c, k) => GarageKeyView.copy(c, k);\nfinal g = GarageKeyView.copy;',
        }),
        ['lib/src/ui/x.dart f', 'lib/src/ui/x.dart (top level)'],
      );
      expect(
        _copyCallers({
          'lib/src/ui/widgets/store_token_dialog.dart': '''
class _StoreTokenDialogState {
  Future<void> _copy(copy) async {
    await GarageKeyView.copy(copy.clipboard, k);
    if (!await askReauthentication(context, copy.reauthenticate) || !mounted) {
      return;
    }
  }
}
''',
        }),
        [
          'lib/src/ui/widgets/store_token_dialog.dart _StoreTokenDialogState._copy before askReauthentication',
        ],
      );
      expect(
        _copyCallers({
          'lib/src/ui/widgets/store_token_dialog.dart': '''
class _StoreTokenDialogState {
  Future<void> _copy(copy) async {
    await askReauthentication(context, copy.reauthenticate);
    await GarageKeyView.copy(copy.clipboard, k);
  }
}
''',
        }),
        [
          'lib/src/ui/widgets/store_token_dialog.dart _StoreTokenDialogState._copy before askReauthentication',
        ],
      );
    },
  );
}

CompilationUnit _unit(String source) => parseString(content: source).unit;

/// Every directive of [unit], as its source.
List<String> _directives(CompilationUnit unit) => [
  for (final directive in unit.directives) directive.toSource(),
];

/// The name of every declaration of [unit], classes and others.
List<String> _declarations(CompilationUnit unit) => [
  for (final declaration in unit.declarations)
    switch (declaration) {
      ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
      _ => declaration.toSource(),
    },
];

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

/// The feature's libraries, generated files aside, by their path from the package.
Map<String, String> _libraryFiles() => {
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart') && !file.path.contains('/generated/'))
      file.path: file.readAsStringSync(),
};

/// Every use of `GarageKeyView.copy` in [sources] but the view's own file, as `<path> <enclosing member>`, and, in `_StoreTokenDialogState._copy` of the dialog's file, whether it comes after the `if` that returns unless `askReauthentication` passed (#318).
///
/// A use is a call or a tear-off written `GarageKeyView.copy`, whatever the import prefix; any other text that names it (`GarageKeyView .copy` across a line) is caught by the plain search that follows.
List<String> _copyCallers(Map<String, String> sources) {
  final found = <String>[];
  for (final MapEntry(key: path, value: source) in sources.entries) {
    if (path.endsWith('lib/src/ui/widgets/garage_key_view.dart')) continue;
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final visitor = _CopyVisitor(path);
    unit.accept(visitor);
    found.addAll(visitor.found);
    // Whatever the syntax tree did not show as a use, the text does.
    final mentions = RegExp(
      r'GarageKeyView\s*\.\s*copy\b',
    ).allMatches(source).length;
    if (mentions != visitor.found.length) found.add('$path text');
  }
  return found;
}

final class _CopyVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final List<String> found = [];

  _CopyVisitor(this.path);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'copy' && _namesView(node.target?.toSource())) {
      found.add(_where(node));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'copy' && _namesView(node.prefix.name)) {
      found.add(_where(node));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'copy' &&
        _namesView(node.target?.toSource())) {
      found.add(_where(node));
    }
    super.visitPropertyAccess(node);
  }

  static bool _namesView(String? target) =>
      target == 'GarageKeyView' ||
      (target?.endsWith('.GarageKeyView') ?? false);

  String _where(AstNode node) {
    final method = node.thisOrAncestorOfType<MethodDeclaration>();
    final function = node.thisOrAncestorOfType<FunctionDeclaration>();
    final owner = method?.thisOrAncestorOfType<ClassDeclaration>();
    final member = switch ((owner, method, function)) {
      (final owner?, final method?, _) =>
        '${owner.namePart.typeName.lexeme}.${method.name.lexeme}',
      (_, _, final function?) => function.name.lexeme,
      _ => '(top level)',
    };
    if (path.endsWith('lib/src/ui/widgets/store_token_dialog.dart') &&
        member == '_StoreTokenDialogState._copy' &&
        method != null) {
      return '$path $member ${_afterReauthentication(method, node) ? 'after' : 'before'} askReauthentication';
    }
    return '$path $member';
  }

  /// Whether, in [method], an `if` whose condition calls `askReauthentication` and whose branch returns ends before [use].
  static bool _afterReauthentication(MethodDeclaration method, AstNode use) {
    final guards = <IfStatement>[];
    method.body.accept(_IfVisitor(guards));
    return guards.any(
      (guard) =>
          guard.expression.toSource().contains('!await askReauthentication(') &&
          guard.thenStatement.toSource().contains('return') &&
          guard.end <= use.offset,
    );
  }
}

final class _IfVisitor extends RecursiveAstVisitor<void> {
  final List<IfStatement> found;

  _IfVisitor(this.found);

  @override
  void visitIfStatement(IfStatement node) {
    found.add(node);
    super.visitIfStatement(node);
  }
}
