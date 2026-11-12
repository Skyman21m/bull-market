import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// A resolved-symbol boundary, not a whole-program secret-flow analysis.
///
/// Imports, re-exports, aliases and tear-offs resolve to the declaration being
/// used. The test keystore is also forbidden in production consumers.
/// Validation, word lists, mnemonic formatting and public-key derivation
/// remain available to the app. New cryptographic dependencies or APIs require
/// updating this policy; arbitrary cryptography and dynamic dispatch are not
/// proven safe by this gate. Analysis errors fail closed.
Future<void> main(List<String> arguments) async {
  final root = Directory(arguments.isEmpty ? '.' : arguments.single).absolute;
  final report = await checkKeyMaterial(root.path);
  for (final violation in report.violations) {
    stderr.writeln(violation);
  }
  stdout.writeln(
    'Key-material boundary: ${report.fileCount} files, '
    '${report.violations.length} violations',
  );
  if (report.violations.isNotEmpty) exitCode = 1;
}

class KeyMaterialReport {
  final int fileCount;
  final List<String> violations;

  const KeyMaterialReport(this.fileCount, this.violations);
}

Future<KeyMaterialReport> checkKeyMaterial(String rootPath) async {
  final root = Directory(rootPath).resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(
    includedPaths: [root],
    sdkPath: dartSdkPath(root),
  );
  final files = productionDartFiles(root);
  final scanned = files.toSet();
  final workspaceConfig = packageConfigPath(root);
  final violations = <String>[
    for (final link in productionLinks(root))
      '${link.substring(root.length + 1)}: symbolic link',
    for (final configuration in productionConfigurations(root))
      '${configuration.substring(root.length + 1)}: package or analysis configuration under a production root',
    if (!{
      FileSystemEntityType.directory,
      FileSystemEntityType.link,
    }.contains(FileSystemEntity.typeSync('$root/lib', followLinks: false)))
      'lib: missing',
    if (files.isEmpty) 'lib: no production Dart file',
  ];
  for (final path in files) {
    final relative = path.substring(root.length + 1);
    final context = _contextOf(collection, path);
    // A package configuration of its own would make the gate resolve the file against other packages than the build does.
    if (context.contextRoot.packagesFile?.path != workspaceConfig) {
      violations.add('$relative: resolved with another package configuration');
      continue;
    }
    final result = await context.currentSession.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      violations.add('$relative: unresolved unit');
      continue;
    }
    for (final diagnostic in result.diagnostics) {
      if (diagnostic.diagnosticCode.severity.name == 'ERROR') {
        violations.add('$relative: ${diagnostic.diagnosticCode.lowerCaseName}');
      }
    }
    final visitor = _check(result.unit, relative);
    violations.addAll(visitor.violations);
    // The composition root asks for the handle once, in the shape [_KeyMaterialVisitor.isHandleCall] allows.
    if (relative == 'lib/locator.dart' &&
        visitor.declaresAppLocator &&
        visitor.handleCalls != 1) {
      violations.add(
        '$relative: AppLocator.setupP2p#not one call of Secrets.garageKeys of the allowed shape',
      );
    }
    for (final target in directiveTargets(result.unit)) {
      final real = File(target).existsSync()
          ? File(target).resolveSymbolicLinksSync()
          : target;
      if (real.startsWith('$root/') &&
          !scanned.contains(real) &&
          !real.startsWith('$root/packages/secrets/lib/')) {
        violations.add(
          '$relative: ${real.substring(root.length + 1)}#unscanned file',
        );
      }
    }
  }
  await collection.dispose();
  return KeyMaterialReport(files.length, violations.toSet().toList()..sort());
}

/// The context that resolves [path].
///
/// `analysis_options.yaml` may exclude a file from analysis (the app excludes `lib/**/*.g.dart` and `lib/**/*.freezed.dart`), and `contextFor` then finds no context for it; such a file is still compiled, so it is resolved in the deepest context whose folder holds it.
AnalysisContext _contextOf(AnalysisContextCollection collection, String path) {
  AnalysisContext? deepest;
  for (final context in collection.contexts) {
    final folder = context.contextRoot.root.path;
    if (path.startsWith('$folder/') &&
        folder.length > (deepest?.contextRoot.root.path.length ?? -1)) {
      deepest = context;
    }
  }
  return deepest ?? (throw StateError('No analysis context holds $path'));
}

/// Every Dart file the gate scans: all of `lib/`, `packages/*/lib/` and `features/*/lib/` but the custody package, generated files included.
///
/// No file is left out for its name or its folder: a generated file is scanned like a hand-written one (issue #47).
List<String> productionDartFiles(String root) => [
  for (final entity in _productionEntities(root))
    if (entity is File && entity.path.endsWith('.dart')) entity.path,
]..sort();

/// The symbolic links under the production roots, and those that stand for a root, a whole package or feature, or the folder of all of them: the gate does not follow them, so each one fails the check.
List<String> productionLinks(String root) => [
  for (final entity in _productionEntities(root))
    if (entity is Link) entity.path,
]..sort();

/// The package and analysis configurations under the production roots, each of which fails the check (issue #47).
///
/// A `pubspec.yaml` with a `.dart_tool/package_config.json` beside it would make the gate resolve the files below it against other packages than the build does, and an `analysis_options.yaml` could lower the severity of an error the gate reports.
List<String> productionConfigurations(String root) => [
  for (final entity in _productionEntities(root))
    if (_configurationNames.contains(entity.path.split('/').last)) entity.path,
]..sort();

const _configurationNames = {
  'pubspec.yaml',
  'analysis_options.yaml',
  'package_config.json',
  '.packages',
  '.dart_tool',
};

Iterable<FileSystemEntity> _productionEntities(String root) sync* {
  final roots = ['$root/lib'];
  for (final group in ['packages', 'features']) {
    switch (FileSystemEntity.typeSync('$root/$group', followLinks: false)) {
      case FileSystemEntityType.link:
        yield Link('$root/$group');
      case FileSystemEntityType.directory:
        for (final member in Directory(
          '$root/$group',
        ).listSync(followLinks: false)) {
          if (member.path == '$root/packages/secrets') continue;
          if (member is Link) yield member;
          if (member is Directory) roots.add('${member.path}/lib');
        }
      default:
    }
  }
  for (final path in roots) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.link:
        yield Link(path);
      case FileSystemEntityType.directory:
        yield* Directory(path).listSync(recursive: true, followLinks: false);
      default:
    }
  }
}

/// The files that the directives of [unit] name, each alternative of a conditional import or export included, as the analyzer resolved them.
Iterable<String> directiveTargets(CompilationUnit unit) sync* {
  for (final directive in unit.directives) {
    final uris = switch (directive) {
      ImportDirective(:final libraryImport, :final configurations) => [
        libraryImport?.uri,
        for (final configuration in configurations) configuration.resolvedUri,
      ],
      ExportDirective(:final libraryExport, :final configurations) => [
        libraryExport?.uri,
        for (final configuration in configurations) configuration.resolvedUri,
      ],
      PartDirective(:final partInclude) => [partInclude?.uri],
      _ => const <DirectiveUri?>[],
    };
    for (final uri in uris) {
      if (uri is DirectiveUriWithSource) yield uri.source.fullName;
    }
  }
}

List<String> checkUnit(CompilationUnit unit, String relativePath) =>
    _check(unit, relativePath).violations.toList()..sort();

_KeyMaterialVisitor _check(CompilationUnit unit, String relativePath) {
  final visitor = _KeyMaterialVisitor(relativePath, unit);
  unit.accept(visitor);
  return visitor;
}

class _KeyMaterialVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final Set<String> violations = {};

  /// The file of the unit being checked, and the folder of its analysis context, which name where a declaration lives (see [declarationPath]).
  final String? unitSource;
  final String? analysisRoot;

  /// How many calls of `Secrets.garageKeys` of the allowed shape the unit makes, and whether it declares the class `AppLocator` (see [checkKeyMaterial]).
  int handleCalls = 0;
  bool declaresAppLocator = false;

  /// The P2P failures that a reader's file names, constructs or returns, checked once the unit is read (see [checkFailure]).
  final Set<InterfaceElement> readerFailures = {};

  _KeyMaterialVisitor(this.path, CompilationUnit unit)
    : unitSource = unit.declaredFragment?.source.fullName,
      analysisRoot = unit
          .declaredFragment
          ?.element
          .session
          .analysisContext
          .contextRoot
          .root
          .path;

  /// Where [element] is declared, relative to the folder of the analysis context, the unit being checked standing at [path].
  String? declarationPath(Element? element) {
    final source = element?.firstFragment.libraryFragment?.source.fullName;
    final root = analysisRoot;
    if (source == null) return null;
    if (source == unitSource) return path;
    return root != null && source.startsWith('$root/')
        ? source.substring(root.length + 1)
        : null;
  }

  /// `AppLocator.setup` or `AppLocator.setupP2p` of `lib/locator.dart`, the static methods that compose the app and hand P2P the Garage Key handle (issue #47).
  bool isCompositionMethod(Element? element) =>
      element is MethodElement &&
      element.isStatic &&
      element.enclosingElement?.name == 'AppLocator' &&
      {'setup', 'setupP2p'}.contains(element.name) &&
      declarationPath(element) == 'lib/locator.dart';

  /// The `withGarageKeys` parameter of `AppLocator.setup` or of `AppLocator.setupP2p`.
  bool isCompositionFlag(Element? element) =>
      element is FormalParameterElement &&
      element.name == 'withGarageKeys' &&
      isCompositionMethod(element.enclosingElement);

  /// `Bull.init` of `lib/init.dart`, the foreground composition.
  bool isForegroundInit(Element? element) =>
      element is MethodElement &&
      element.isStatic &&
      element.enclosingElement?.name == 'Bull' &&
      element.name == 'init' &&
      declarationPath(element) == 'lib/init.dart';

  /// The top-level function [name] of the file [file]: `startApp` of `lib/bootstrap.dart`, which calls `Bull.init`, and `main` of `lib/main.dart`, which calls `startApp`.
  bool isTopLevel(Element? element, String name, String file) =>
      element is ExecutableElement &&
      element.enclosingElement is LibraryElement &&
      element.name == name &&
      declarationPath(element) == file;

  /// Whether [node] is the one call of `Secrets.garageKeys` the composition makes (issue #47).
  ///
  /// In the static `AppLocator.setupP2p` of `lib/locator.dart`, `<vault>.garageKeys()` is the value of `withGarageKeys ? … : null`, whose condition is that method's own flag, and that choice is the `garageKeys:` argument of `P2pFeature.setup`, called as the method's body or as a statement of it.
  bool isHandleCall(AstNode node) {
    final call = node.parent;
    if (path != 'lib/locator.dart' ||
        node is! SimpleIdentifier ||
        call is! MethodInvocation ||
        call.methodName != node) {
      return false;
    }
    final choice = call.parent;
    if (choice is! ConditionalExpression ||
        choice.thenExpression != call ||
        choice.elseExpression is! NullLiteral) {
      return false;
    }
    final condition = choice.condition;
    final argument = choice.parent;
    final arguments = argument?.parent;
    final setup = arguments?.parent;
    if (condition is! SimpleIdentifier ||
        argument is! NamedExpression ||
        argument.name.label.name != 'garageKeys' ||
        arguments is! ArgumentList ||
        setup is! MethodInvocation ||
        !_isP2pSetup(setup.methodName.element) ||
        !_isDirectStatementOf(setup, 'setupP2p')) {
      return false;
    }
    final flag = condition.element;
    return isCompositionFlag(flag) &&
        flag?.enclosingElement?.name == 'setupP2p';
  }

  void check(Element? element, AstNode node) {
    if (element == null) {
      if (node is SimpleIdentifier &&
          _unresolvedSensitiveMembers.contains(node.name) &&
          (node.parent is PropertyAccess ||
              node.parent is PrefixedIdentifier ||
              node.parent is MethodInvocation ||
              node.parent is DotShorthandInvocation)) {
        violations.add('$path: unresolved sensitive member ${node.name}');
      }
      return;
    }
    final symbol = materialSymbol(element);
    if (symbol == null) return;
    if (symbol.startsWith('package:secrets/') &&
        symbol.endsWith('#Secrets.garageKeys') &&
        isHandleCall(node)) {
      handleCalls++;
      return;
    }
    if (_isException(path, node, symbol)) return;
    violations.add('$path: $symbol');
  }

  void checkTestingLibrary(String? uri) {
    if (uri != null && _isTestingLibrary(uri)) {
      violations.add('$path: $uri#test-only library');
    }
  }

  /// No production library outside the custody package re-exports a declaration of `package:secrets` (issue #47).
  ///
  /// Only the vault's own libraries then make its declarations importable, so a check that reads the URIs of a feature's imports, as `features/p2p/test/secrets_imports_test.dart` does, sees every way in by import.
  /// The names an export brings are read from the library the analyzer resolved, after its `show` and `hide` lists; a conditional export fails closed, since the gate does not resolve the library of an inactive alternative.
  void checkVaultExport(ExportDirective node) {
    if (node.configurations.isNotEmpty) {
      violations.add('$path: ${node.uri.stringValue}#conditional export');
      return;
    }
    final library = node.libraryExport?.exportedLibrary;
    if (library == null) return;
    if (_namesThrough(
      library,
      node.combinators,
    ).values.any(_isVaultDeclaration)) {
      violations.add('$path: ${library.uri}#re-exports the vault');
    }
  }

  /// Outside the files of [_vaultUsers], no file of `features/*/lib` or `packages/*/lib` refers to a declaration of `package:secrets`, and those files refer only to the declarations the table gives each of them (issue #47).
  ///
  /// A member counts as its class, and a type alias declared anywhere counts as the declaration of the vault it names, so `typedef Vault = Secrets;` in another package hands nothing on.
  /// The app's own `lib/` is not concerned: it uses the vault.
  void checkVaultUse(Element? element) {
    if (element == null ||
        !(path.startsWith('features/') || path.startsWith('packages/'))) {
      return;
    }
    final declaration = _vaultDeclarationOf(element);
    if (declaration == null ||
        (_vaultUsers[path]?.contains(declaration) ?? false)) {
      return;
    }
    violations.add(
      '$path: package:secrets#$declaration outside the files that may use the vault',
    );
  }

  @override
  void visitNamedType(NamedType node) {
    checkVaultUse(node.element);
    noteReaderFailure(node.element);
    super.visitNamedType(node);
  }

  /// Production code does not import or export `package:p2p/testing.dart`, the feature's test seam, which registers the Garage over a handle a test made (#54): the resolved library, the decoded text and every conditional alternative are read, so an escaped URI does not hide it.
  void checkP2pSeam(NamespaceDirective node, LibraryElement? library) {
    final uris = [
      library?.uri.toString(),
      node.uri.stringValue,
      for (final configuration in node.configurations) ...[
        configuration.uri.stringValue,
        if (configuration.resolvedUri case DirectiveUriWithSource(
          :final source,
        ))
          source.uri.toString(),
      ],
    ];
    if (uris.contains('package:p2p/testing.dart')) {
      violations.add(
        '$path: package:p2p/testing.dart#test seam in production code',
      );
    }
  }

  @override
  void visitImportDirective(ImportDirective node) {
    checkP2pSeam(node, node.libraryImport?.importedLibrary);
    checkTestingLibrary(node.libraryImport?.importedLibrary?.uri.toString());
    checkTestingLibrary(node.uri.stringValue);
    for (final configuration in node.configurations) {
      checkTestingLibrary(configuration.uri.stringValue);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    checkP2pSeam(node, node.libraryExport?.exportedLibrary);
    checkTestingLibrary(node.libraryExport?.exportedLibrary?.uri.toString());
    checkTestingLibrary(node.uri.stringValue);
    for (final configuration in node.configurations) {
      checkTestingLibrary(configuration.uri.stringValue);
    }
    checkVaultExport(node);
    super.visitExportDirective(node);
  }

  /// A class of [_garageKeyReaders] has the public surface the table gives it, and nothing more (issue #47).
  ///
  /// Each public member, constructors, fields, getters, setters and static members included, must be in the table with its exact signature, and each type a signature or a supertype names must come from the library [_readerTypes] gives it; a mixin, a supertype not in the table, an override not in the table (`toString` among them) fail.
  /// The implicit constructor of a class that declares none takes nothing and is not counted.
  /// This fixes what the class lets out through its own members, not what the values it returns let out (a `GarageKey` derives every robot of the key).
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final reader = _garageKeyReaders[path];
    final name = node.namePart.typeName.lexeme;
    final element = node.declaredFragment?.element;
    if (name == 'AppLocator') declaresAppLocator = true;
    if (reader != null && name == reader.owner) {
      if (element == null) {
        violations.add('$path: $name#unresolved class');
      } else {
        for (final detail in _surfaceViolations(element, reader)) {
          violations.add('$path: $name$detail, not in the table of readers');
        }
      }
    }
    super.visitClassDeclaration(node);
  }

  /// Whether [element] is a class of [_garageKeyReaders], in its file.
  bool isReaderClass(Element? element) =>
      element is InterfaceElement &&
      _garageKeyReaders[declarationPath(element)]?.owner == element.name;

  /// No other code reaches into a reader: no part in its file, no extension on it, and no use of its private members outside it (issue #47).
  @override
  void visitPartDirective(PartDirective node) {
    if (_garageKeyReaders.containsKey(path)) {
      violations.add('$path: part directive in the file of a reader');
    }
    super.visitPartDirective(node);
  }

  @override
  void visitPartOfDirective(PartOfDirective node) {
    if (_garageKeyReaders.containsKey(path)) {
      violations.add('$path: part directive in the file of a reader');
    }
    super.visitPartOfDirective(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final extended = node.declaredFragment?.element.extendedType;
    if (extended is InterfaceType && isReaderClass(extended.element)) {
      violations.add('$path: extension on ${extended.element.name}');
    }
    super.visitExtensionDeclaration(node);
  }

  void checkPrivateUse(Element? element, AstNode node) {
    final owner = element?.enclosingElement;
    if (element == null ||
        !(element.name?.startsWith('_') ?? false) ||
        !isReaderClass(owner)) {
      return;
    }
    final holder = node.thisOrAncestorOfType<ClassDeclaration>();
    if (holder?.declaredFragment?.element != owner) {
      violations.add(
        '$path: ${owner?.name}.${element.name}#private member used outside its class',
      );
    }
  }

  /// Whether [element] is `P2pFailure` of `features/p2p/lib/src/domain/p2p_failure.dart`, or a class that extends it.
  bool isP2pFailure(InterfaceElement element) =>
      [element, ...element.allSupertypes.map((type) => type.element)].any(
        (type) =>
            type.name == 'P2pFailure' &&
            declarationPath(type) == _p2pFailurePath,
      );

  /// Records a P2P failure that the file of a reader names, constructs or returns: [element] is the class, one of its constructors or members, or anything else.
  void noteReaderFailure(Element? element) {
    if (!_garageKeyReaders.containsKey(path)) return;
    final type = element is InterfaceElement
        ? element
        : element?.enclosingElement;
    if (type is InterfaceElement && isP2pFailure(type)) {
      readerFailures.add(type);
    }
  }

  /// A P2P failure that a reader uses carries no data but what [_failureFields] allows (issue #47).
  ///
  /// It mixes nothing in, it and its supertypes outside the SDK declare no field but those of the table (`Failure.logMessage` of `package:primitives` excepted), and the constructors of `P2pFailure` take no parameter, so no failure passes a message to `Failure.logMessage`.
  /// A failure that no reader names is not concerned: it cannot carry what a reader reads unless the reader hands the bytes to code outside it, which the gate does not follow.
  void checkFailure(InterfaceElement failure) {
    for (final mixin in failure.mixins) {
      violations.add(
        '$path: ${failure.name}#mixin ${mixin.element.name} in a P2P failure the reader uses',
      );
    }
    for (final type in [
      failure,
      ...failure.allSupertypes.map((t) => t.element),
    ]) {
      final library = type.library.uri.toString();
      if (library.startsWith('dart:') ||
          (type.name == 'Failure' &&
              library == 'package:primitives/src/failure.dart')) {
        continue;
      }
      for (final field in type.fields) {
        if (!field.isOriginDeclaration) continue;
        final fieldType = field.type;
        final described = fieldType is InterfaceType
            ? '${fieldType.element.library.uri}#${fieldType.getDisplayString()}'
            : fieldType.getDisplayString();
        if (_failureFields[type.name]?[field.name] != described) {
          violations.add(
            '$path: ${type.name}.${field.name}#field of a P2P failure the reader uses',
          );
        }
      }
      if (type.name == 'P2pFailure' &&
          declarationPath(type) == _p2pFailurePath) {
        for (final constructor in type.constructors) {
          if (constructor.formalParameters.isNotEmpty) {
            violations.add(
              '$path: P2pFailure.${constructor.name}#constructor with parameters',
            );
          }
        }
      }
    }
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    super.visitCompilationUnit(node);
    for (final failure in readerFailures) {
      checkFailure(failure);
    }
    // A reader's file declares what the table lists and nothing else: a top-level function or an extension there would reach the reader's private members (the second review of #58).
    final reader = _garageKeyReaders[path];
    if (reader != null) {
      for (final declaration in node.declarations) {
        for (final name in _declaredNames(declaration)) {
          if (!reader.declarations.contains(name)) {
            violations.add(
              '$path: $name#declaration in the file of a reader, not in the table of readers',
            );
          }
        }
      }
    }
  }

  /// No dynamic or unresolved access to a member in a reader's file: it would reach the reader's private members without naming them (the second review of #58).
  void checkDynamicAccess(SimpleIdentifier node) {
    final parent = node.parent;
    if (!_garageKeyReaders.containsKey(path) || node.element != null) return;
    if ((parent is PropertyAccess && parent.propertyName == node) ||
        (parent is PrefixedIdentifier && parent.identifier == node) ||
        (parent is MethodInvocation && parent.methodName == node)) {
      violations.add(
        '$path: ${node.name}#dynamic access in the file of a reader',
      );
    }
  }

  /// Outside the files of [_vaultUsers], no file of `features/*/lib` or `packages/*/lib` invokes or reads a member of a value whose static type mentions a declaration of the vault, though it names none of its types (the second review of #58: a handle reached through a function of an allowed file, and an extension on `GarageKeys`).
  void checkVaultTarget(Expression? target) {
    if (target == null ||
        !(path.startsWith('features/') || path.startsWith('packages/')) ||
        _vaultUsers.containsKey(path)) {
      return;
    }
    final type = target.staticType;
    final declaration = type == null ? null : _vaultTypeIn(type);
    if (declaration != null) {
      violations.add(
        '$path: package:secrets#$declaration outside the files that may use the vault',
      );
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    checkVaultTarget(node.realTarget);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    checkVaultTarget(node.prefix);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitCascadeExpression(CascadeExpression node) {
    checkVaultTarget(node.target);
    super.visitCascadeExpression(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    checkVaultTarget(node.realTarget);
    super.visitIndexExpression(node);
  }

  // The bridge's default handler is the only one that sees call arguments: a
  // host handler or API would receive the words handed to lwk, boltz and bwk.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element is ExecutableElement &&
        element.library.uri.toString() == _bridgeLibrary &&
        element.enclosingElement?.name == 'BullSdk' &&
        element.name == 'init' &&
        node.argumentList.arguments.isNotEmpty) {
      violations.add('$path: $_bridgeLibrary#BullSdk.init with arguments');
    }
    checkContainer(node, element);
    checkVaultTarget(node.realTarget);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    checkContainer(node, node.element);
    checkVaultTarget(node.function);
    super.visitFunctionExpressionInvocation(node);
  }

  /// No Garage Key handle goes into a GetIt container or comes out of one (issue #47).
  ///
  /// A call of `package:get_it` fails when one of its type arguments, written or inferred, or a `Type` it is passed, mentions `GarageKeys`: the composition hands the handle to `P2pFeature.setup` alone, and the feature keeps it in its repository, so a container would hand it to any isolate that reads it.
  void checkContainer(InvocationExpression node, Element? element) {
    if (!(element?.library?.uri.toString().startsWith('package:get_it/') ??
        false)) {
      return;
    }
    final types = [
      ...?node.typeArgumentTypes,
      for (final argument in node.argumentList.arguments)
        if ((argument is NamedExpression ? argument.expression : argument)
            case TypeLiteral(:final type))
          type.type,
    ];
    if (types.any(_mentionsGarageKeys)) {
      violations.add('$path: package:get_it#GarageKeys in a container');
    }
  }

  @override
  void visitCommentReference(CommentReference node) {}

  /// Which composition of the app hands P2P the Garage Key handle (issue #47).
  ///
  /// `startApp` of `lib/bootstrap.dart` is called only as the body or a statement of `main` of `lib/main.dart`, the app's entry point, to which nothing refers.
  /// `Bull.init` of `lib/init.dart`, the foreground composition, is called only by `startApp`.
  /// `AppLocator.setup` is called with a boolean literal for `withGarageKeys`, and `true` only as a statement of `Bull.init` itself, not in a closure or a local function.
  /// `AppLocator.setupP2p`, which asks the vault for the handle when its flag is true, is called only as a statement of `AppLocator.setup` of `lib/locator.dart`, with the flag that method received.
  /// Any other reference to these methods (a tear-off, which `Function.apply` or a dynamic call needs) fails closed: Dart cannot reach a static method dynamically without one.
  void checkComposition(SimpleIdentifier node) {
    final element = node.element;
    final String member;
    if (isCompositionMethod(element)) {
      member = 'AppLocator.${element?.name}';
    } else if (isForegroundInit(element)) {
      member = 'Bull.init';
    } else if (isTopLevel(element, 'startApp', 'lib/bootstrap.dart')) {
      member = 'startApp';
    } else if (isTopLevel(element, 'main', 'lib/main.dart')) {
      violations.add('$path: main of lib/main.dart#referenced');
      return;
    } else {
      return;
    }
    final invocation = node.parent;
    if (invocation is! MethodInvocation || invocation.methodName != node) {
      violations.add('$path: $member#not a direct call');
      return;
    }
    final (:owner, :function) = _enclosingDeclaration(node);
    if (member == 'startApp') {
      if (path != 'lib/main.dart' ||
          owner != null ||
          !_isDirectStatementOf(invocation, 'main')) {
        violations.add('$path: startApp#outside main of lib/main.dart');
      }
      return;
    }
    if (member == 'Bull.init') {
      if (path != 'lib/bootstrap.dart' ||
          owner != null ||
          function != 'startApp') {
        violations.add(
          '$path: Bull.init#outside startApp of lib/bootstrap.dart',
        );
      }
      return;
    }
    final flag = [
      for (final argument in invocation.argumentList.arguments)
        if (argument is NamedExpression &&
            argument.name.label.name == 'withGarageKeys')
          argument.expression,
    ].firstOrNull;
    if (member == 'AppLocator.setupP2p') {
      if (path != 'lib/locator.dart' ||
          owner != 'AppLocator' ||
          !_isDirectStatementOf(invocation, 'setup')) {
        violations.add('$path: $member#outside AppLocator.setup');
      } else if (flag is! SimpleIdentifier ||
          !isCompositionFlag(flag.element) ||
          flag.element?.enclosingElement?.name != 'setup') {
        violations.add('$path: $member#withGarageKeys not forwarded');
      }
    } else if (flag is! BooleanLiteral) {
      violations.add('$path: $member#withGarageKeys not a literal');
    } else if (flag.value &&
        (path != 'lib/init.dart' ||
            owner != 'Bull' ||
            !_isDirectStatementOf(invocation, 'init'))) {
      violations.add('$path: $member#withGarageKeys: true outside Bull.init');
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext()) {
      check(node.element, node);
      checkComposition(node);
      checkVaultUse(node.element);
      checkPrivateUse(node.element, node);
      noteReaderFailure(node.element);
      checkDynamicAccess(node);
    }
    super.visitSimpleIdentifier(node);
  }

  // The flags of `AppLocator.setup` and `setupP2p` keep the value their caller passed.
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (isCompositionFlag(node.writeElement)) {
      violations.add('$path: AppLocator#withGarageKeys reassigned');
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (isCompositionFlag(node.element)) {
      violations.add('$path: AppLocator#withGarageKeys reassigned');
    }
    super.visitAssignedVariablePattern(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    check(node.element, node);
    super.visitConstructorName(node);
  }

  // An object pattern reads a getter, or tears off a method, without an identifier that names it: `case GarageKeyMaterial(:final bytes)`.
  @override
  void visitPatternField(PatternField node) {
    check(node.element, node);
    checkVaultUse(node.element);
    checkPrivateUse(node.element, node);
    super.visitPatternField(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    check(node.element, node);
    checkVaultUse(node.element);
    super.visitDotShorthandConstructorInvocation(node);
  }
}

// Dynamic or otherwise unresolved access to these sensitive entry points must
// be replaced by a statically resolved call. Generic names such as `sign` are
// deliberately absent: this is not a blanket ban on dynamic app data.
const _unresolvedSensitiveMembers = {
  'seed',
  'fromSeed',
  'fromPrivateKey',
  'deriveHardened',
  'secretBytes',
  'newConfidential',
  'restoreBackup',
  'signedPsetWithExtraDetails',
  'revealBytes',
  'revealBech32',
  'garageKeys',
  // `GarageKeyMaterial.bytes`, reached without a static type. No production file reads a member named `bytes` dynamically today.
  'bytes',
  // `AppLocator.setupP2p`, called dynamically.
  // Dart reaches a static method dynamically only through a tear-off, which the gate refuses, so `setup`, a generic name, is left out.
  'setupP2p',
};

const _bridgeLibrary = 'package:bull_sdk/src/rust/frb_generated.dart';

// A relative URI in an inactive conditional alternative is never resolved, so
// it is matched on its path.
bool _isTestingLibrary(String uri) =>
    uri == 'package:secrets/testing.dart' ||
    uri.startsWith('package:secrets/src/testing/') ||
    (!uri.contains(':') &&
        RegExp(
          r'(^|/)secrets/lib/(testing\.dart$|src/testing/)',
        ).hasMatch(Uri.parse(uri).normalizePath().path));

String? materialSymbol(Element element) {
  final uri = element.library?.uri.toString();
  if (uri != null && _isTestingLibrary(uri)) {
    return '$uri#${element.name}';
  }
  if (element is! ExecutableElement || uri == null) return null;
  final owner = element.enclosingElement?.name;
  final member = element.name;
  final symbol = '$owner.$member';
  final forbidden = switch (uri) {
    _ when uri.startsWith('package:bip39_mnemonic/') =>
      symbol == 'Mnemonic.seed',
    _ when uri.startsWith('package:bip32_keys/') =>
      owner == 'Bip32Keys' &&
          {
            'new',
            'fromSeed',
            'fromBase58',
            'fromPrivateKey',
            'private',
            'deriveHardened',
            'sign',
            'toWIF',
          }.contains(member),
    _ when uri.startsWith('package:bip85_entropy/') =>
      owner == 'Bip85Entropy' && (member?.startsWith('derive') ?? false),
    _ when uri.startsWith('package:bdk_dart/') =>
      {'DescriptorSecretKey', 'DescriptorSecretKeyInterface'}.contains(owner) ||
          (owner == 'Mnemonic' && element is ConstructorElement) ||
          (owner == 'Descriptor' &&
              {
                'newBip44',
                'newBip49',
                'newBip84',
                'newBip86',
              }.contains(member)),
    _ when uri.startsWith('package:bull_sdk/src/rust/third_party/lwk/') =>
      symbol == 'Descriptor.newConfidential' ||
          {
            'Wallet.signTx',
            'Wallet.signedPsetWithExtraDetails',
          }.contains(symbol),
    _ when uri.startsWith('package:bull_sdk/src/rust/third_party/boltz/') =>
      owner == 'SwapMasterKey' &&
          {'new', 'create', 'xprv', 'mnemonic'}.contains(member),
    _ when uri.startsWith('package:bull_sdk/src/rust/third_party/dart_bwk/') =>
      owner == 'SpAccount' &&
          (member?.startsWith('createFromMnemonic') ?? false),
    _bridgeLibrary => symbol == 'BullSdk.initMock',
    _ when uri.startsWith('package:recoverbull/') =>
      symbol == 'RecoverBull.restoreBackup' ||
          symbol == 'EncryptionService.decrypt',
    // The bytes of a stored RoboSats Garage Key, and its two clear forms: whoever holds one controls every robot derived from it.
    // The handle that reads and writes Garage Keys is asked for by the composition root alone (see [_KeyMaterialVisitor.isHandleCall]).
    _ when uri.startsWith('package:secrets/') =>
      symbol == 'GarageKeyMaterial.bytes' || symbol == 'Secrets.garageKeys',
    _ when uri.startsWith('package:robosats/') =>
      owner == 'GarageKey' && {'revealBytes', 'revealBech32'}.contains(member),
    _ => false,
  };
  return forbidden ? '$uri#$symbol' : null;
}

/// Where the P2P feature may read a Garage Key, what each place may read, and the whole public surface of the class that reads it (issues #28, #47).
///
/// The repository converts the stored bytes into a `GarageKey` and back for an import (#28).
/// The widget shows the `robo1…` text on the protected screens of the Garage (#29), and no other production file may reveal that text.
/// A step that needs another name, member or signature changes this table in the same pull request, where review sees both.
/// [declarations] are the only top-level declarations of the reader's file, [supertypes] the only supertypes the class may name, besides `Object`, and [surface] the only public members it may declare, each with its signature as the analyzer prints it.
const _garageKeyReaders = {
  'features/p2p/lib/src/data/garage_key_repository_impl.dart': (
    owner: 'GarageKeyRepositoryImpl',
    members: {'GarageKeyMaterial.bytes', 'GarageKey.revealBytes'},
    declarations: {'GarageKeyRepositoryImpl'},
    supertypes: {'GarageKeyRepository'},
    surface: {
      'new': 'GarageKeyRepositoryImpl Function(GarageKeys)',
      'create': 'Future<Result<void, P2pFailure>> Function(RobosatsNetwork)',
      'import':
          'Future<Result<void, P2pFailure>> Function(RobosatsNetwork, GarageKey)',
      'exists': 'Future<Result<bool, P2pFailure>> Function(RobosatsNetwork)',
      'read':
          'Future<Result<NetworkGarageKey, P2pFailure>> Function(RobosatsNetwork)',
      'firstUsableRobot':
          'Future<Result<NetworkRobot, P2pFailure>> Function(RobosatsNetwork)',
      'delete': 'Future<Result<void, P2pFailure>> Function(RobosatsNetwork)',
    },
  ),
  'features/p2p/lib/src/ui/widgets/garage_key_view.dart': (
    owner: 'GarageKeyView',
    members: {'GarageKey.revealBech32'},
    // The copy button of the view, a private widget and its state (#54).
    declarations: {'GarageKeyView', '_CopyButton', '_CopyButtonState'},
    supertypes: {'StatelessWidget'},
    surface: {
      // The analyzer prints named parameters in alphabetical order.
      'new':
          'GarageKeyView Function({required GarageKeyClipboard clipboard, required GarageKey garageKey, Key? key})',
      'garageKey': 'GarageKey',
      'clipboard': 'GarageKeyClipboard',
      'build': 'Widget Function(BuildContext)',
    },
  ),
};

/// The library of each type that the public surface or the supertypes of a reader may name (issue #47): a type of the same name from another library fails, so that the printed signatures of [_garageKeyReaders] say what they mean.
const _readerTypes = {
  'bool': 'dart:core',
  'Future': 'dart:async',
  'Result': 'package:primitives/src/result.dart',
  'GarageKey': 'package:robosats/src/garage_key.dart',
  'RobosatsNetwork': 'package:robosats/src/coordinator/robosats_network.dart',
  'GarageKeys': 'package:secrets/src/public/secrets.dart',
  'P2pFailure': 'package:p2p/src/domain/p2p_failure.dart',
  'NetworkGarageKey': 'package:p2p/src/domain/network_garage_key.dart',
  'NetworkRobot': 'package:p2p/src/domain/network_garage_key.dart',
  'GarageKeyRepository':
      'package:p2p/src/domain/repositories/garage_key_repository.dart',
  'GarageKeyClipboard': 'package:p2p/src/ui/widgets/garage_key_clipboard.dart',
  'Key': 'package:flutter/src/foundation/key.dart',
  'BuildContext': 'package:flutter/src/widgets/framework.dart',
  'Widget': 'package:flutter/src/widgets/framework.dart',
  'StatelessWidget': 'package:flutter/src/widgets/framework.dart',
};

/// What of [owner] is not in its entry of [_garageKeyReaders], each as the text that follows the class name in a violation.
Iterable<String> _surfaceViolations(
  InterfaceElement owner,
  ({
    String owner,
    Set<String> members,
    Set<String> declarations,
    Set<String> supertypes,
    Map<String, String> surface,
  })
  reader,
) sync* {
  bool known(InterfaceElement type) =>
      type == owner || _readerTypes[type.name] == type.library.uri.toString();
  for (final mixin in owner.mixins) {
    yield '#mixin ${mixin.element.name}';
  }
  for (final supertype in [
    if (owner.supertype case final superclass?
        when !superclass.isDartCoreObject)
      superclass,
    ...owner.interfaces,
  ]) {
    if (!reader.supertypes.contains(supertype.element.name) ||
        !known(supertype.element)) {
      yield '#supertype ${supertype.element.name}';
    }
  }
  // A supertype from the workspace declares abstract members only, so that the class inherits nothing that the table does not list (the second review of #58 made the repository's interface a class with a public field).
  for (final supertype in owner.allSupertypes) {
    final type = supertype.element;
    final library = type.library.uri.toString();
    if (library.startsWith('dart:') || library.startsWith('package:flutter/')) {
      continue;
    }
    final fields = {
      for (final field in type.fields)
        if (field.isOriginDeclaration) field.name,
    };
    for (final field in fields) {
      yield '#supertype ${type.name} declares the field $field';
    }
    // The getters and setters of a declared field are its own, already reported.
    for (final member in <ExecutableElement>[
      ...type.methods,
      ...type.getters,
      ...type.setters,
    ]) {
      if (!member.isAbstract && !fields.contains(member.name)) {
        yield '#supertype ${type.name} declares the concrete member ${member.name}';
      }
    }
  }
  for (final member in <ExecutableElement>[
    ...owner.constructors,
    ...owner.methods,
    ...owner.getters,
    ...owner.setters,
  ]) {
    if (!member.isPublic ||
        (member is ConstructorElement && member.isOriginImplicitDefault)) {
      continue;
    }
    final key = member is SetterElement ? '${member.name}=' : '${member.name}';
    final signature = member is GetterElement
        ? member.returnType.getDisplayString()
        : member.type.getDisplayString();
    if (reader.surface[key] != signature) {
      yield '.$key#$signature';
    } else {
      for (final type in _interfaceTypesIn(member.type)) {
        if (!known(type.element)) {
          yield '.$key#${type.element.name} of ${type.element.library.uri}';
        }
      }
    }
  }
}

/// The names that a top-level [declaration] introduces.
Iterable<String> _declaredNames(CompilationUnitMember declaration) sync* {
  if (declaration is TopLevelVariableDeclaration) {
    for (final variable in declaration.variables.variables) {
      yield variable.name.lexeme;
    }
  } else {
    yield declaration.declaredFragment?.name ?? '<unnamed>';
  }
}

/// Every interface type that [type] names, its type arguments, parameters and record fields included.
Iterable<InterfaceType> _interfaceTypesIn(DartType type) sync* {
  switch (type) {
    case InterfaceType(:final typeArguments):
      yield type;
      for (final argument in typeArguments) {
        yield* _interfaceTypesIn(argument);
      }
    case FunctionType(:final returnType, :final formalParameters):
      yield* _interfaceTypesIn(returnType);
      for (final parameter in formalParameters) {
        yield* _interfaceTypesIn(parameter.type);
      }
    case RecordType(:final positionalFields, :final namedFields):
      for (final field in positionalFields) {
        yield* _interfaceTypesIn(field.type);
      }
      for (final field in namedFields) {
        yield* _interfaceTypesIn(field.type);
      }
    default:
  }
}

/// The file of the P2P failures, and the only field they may declare (issue #47): the reason of an invalid Garage Key, a failure of `package:robosats`.
const _p2pFailurePath = 'features/p2p/lib/src/domain/p2p_failure.dart';
const _failureFields = {
  'GarageKeyInvalidFailure': {
    'reason': 'package:robosats/src/robosats_failure.dart#GarageKeyFailure',
  },
};

/// A declaration of `package:secrets`.
bool _isVaultDeclaration(Element element) =>
    element.library?.uri.toString().startsWith('package:secrets/') ?? false;

/// The files of the workspace's packages and features that may refer to the vault, `package:secrets`, and the declarations each one may refer to (issue #47).
///
/// Only the P2P feature does: its facade receives the Garage Key handle from the shell, its locator registers it, and its repository uses it.
/// Its test seam, `package:p2p/testing.dart`, registers the Garage over a handle a test made (#54); no production library imports it (`test/features/p2p/p2p_testing_seam_test.dart`).
/// `features/p2p/test/secrets_imports_test.dart` pins the names these files import; a declaration here may be used without being imported, as the repository uses `GarageKeyMaterial` through the result of a read.
const _vaultUsers = {
  'features/p2p/lib/public/p2p_facade.dart': {'GarageKeys'},
  'features/p2p/lib/src/p2p_locator.dart': {'GarageKeys'},
  'features/p2p/lib/testing.dart': {'GarageKeys'},
  'features/p2p/lib/src/data/garage_key_repository_impl.dart': {
    'GarageKeyAlreadyExistsFailure',
    'GarageKeyCorruptFailure',
    'GarageKeyMaterial',
    'GarageKeySlot',
    'GarageKeys',
    'KeystoreLockedFailure',
    'SecretFailure',
    'SecretNotFoundFailure',
  },
};

/// The top-level declaration of `package:secrets` that [element] is, or belongs to, or that it names when it is a type alias declared elsewhere; `null` for anything else.
String? _vaultDeclarationOf(Element element) {
  if (element is TypeAliasElement && !_isVaultDeclaration(element)) {
    return _vaultTypeIn(element.aliasedType);
  }
  if (!_isVaultDeclaration(element)) return null;
  var declaration = element;
  for (
    var enclosing = element.enclosingElement;
    enclosing != null && enclosing is! LibraryElement;
    enclosing = enclosing.enclosingElement
  ) {
    declaration = enclosing;
  }
  return declaration.name;
}

/// The name of a declaration of the vault that [type] mentions, if any.
String? _vaultTypeIn(DartType type) => switch (type) {
  InterfaceType(:final element, :final typeArguments) =>
    _isVaultDeclaration(element)
        ? element.name
        : typeArguments.map(_vaultTypeIn).nonNulls.firstOrNull,
  FunctionType(:final returnType, :final formalParameters) => [
    returnType,
    for (final parameter in formalParameters) parameter.type,
  ].map(_vaultTypeIn).nonNulls.firstOrNull,
  RecordType(:final positionalFields, :final namedFields) => [
    for (final field in positionalFields) field.type,
    for (final field in namedFields) field.type,
  ].map(_vaultTypeIn).nonNulls.firstOrNull,
  _ => null,
};

/// The names that a directive with [combinators] brings from [library], each with the declaration it stands for.
Map<String, Element> _namesThrough(
  LibraryElement library,
  List<Combinator> combinators,
) {
  final names = {...library.exportNamespace.definedNames2};
  String withoutSetter(String name) =>
      name.endsWith('=') ? name.substring(0, name.length - 1) : name;
  for (final combinator in combinators) {
    switch (combinator) {
      case ShowCombinator(:final shownNames):
        final shown = {for (final name in shownNames) name.name};
        names.removeWhere((name, _) => !shown.contains(withoutSetter(name)));
      case HideCombinator(:final hiddenNames):
        final hidden = {for (final name in hiddenNames) name.name};
        names.removeWhere((name, _) => hidden.contains(withoutSetter(name)));
    }
  }
  return names;
}

/// The outermost class and function that hold [node], as the exceptions name them.
({String? owner, String? function}) _enclosingDeclaration(AstNode node) {
  String? function;
  String? owner;
  for (AstNode? current = node; current != null; current = current.parent) {
    if (current is FunctionDeclaration) function = current.name.lexeme;
    if (current is MethodDeclaration) function = current.name.lexeme;
    if (current is ConstructorDeclaration) {
      function = current.name?.lexeme ?? 'new';
    }
    if (current is ClassDeclaration) owner = current.namePart.typeName.lexeme;
  }
  return (owner: owner, function: function);
}

/// Whether [type] is or contains `GarageKeys` of `package:secrets`.
bool _mentionsGarageKeys(DartType? type) => switch (type) {
  InterfaceType(:final element, :final typeArguments) =>
    (element.name == 'GarageKeys' &&
            element.library.uri.toString().startsWith('package:secrets/')) ||
        typeArguments.any(_mentionsGarageKeys),
  FunctionType(:final returnType, :final formalParameters) =>
    _mentionsGarageKeys(returnType) ||
        formalParameters.any(
          (parameter) => _mentionsGarageKeys(parameter.type),
        ),
  RecordType(:final positionalFields, :final namedFields) => [
    for (final field in positionalFields) field.type,
    for (final field in namedFields) field.type,
  ].any(_mentionsGarageKeys),
  _ => false,
};

/// `P2pFeature.setup`, which receives the Garage Key handle.
bool _isP2pSetup(Element? element) =>
    element is MethodElement &&
    element.name == 'setup' &&
    element.enclosingElement?.name == 'P2pFeature' &&
    element.library.uri.toString().startsWith('package:p2p/');

/// Whether [call] stands on its own, as the body of the static method or top-level function named [method], or as a statement directly in that body: not in a closure, a local function, a condition or a loop.
bool _isDirectStatementOf(Expression call, String method) {
  final parent = call.parent;
  final wrapper = parent is AwaitExpression ? parent.parent : parent;
  final statementBlock = wrapper is ExpressionStatement ? wrapper.parent : null;
  final body = switch (wrapper) {
    ExpressionFunctionBody() => wrapper,
    ExpressionStatement() when statementBlock is Block =>
      statementBlock.parent is BlockFunctionBody ? statementBlock.parent : null,
    _ => null,
  };
  final declaration = body?.parent;
  final function = declaration is FunctionExpression
      ? declaration.parent
      : null;
  return (declaration is MethodDeclaration &&
          declaration.isStatic &&
          declaration.name.lexeme == method) ||
      (function is FunctionDeclaration &&
          function.parent is CompilationUnit &&
          function.name.lexeme == method);
}

bool _isException(String path, AstNode node, String symbol) {
  final (:owner, :function) = _enclosingDeclaration(node);
  final member = symbol.split('#').last;
  // This adapter replaces version bytes with the public xpub version before
  // decoding. Elsewhere this mixed decoder could import private extended keys.
  if (path == 'lib/core/utils/bip32_derivation.dart' &&
      owner == 'Bip32Derivation' &&
      function == 'getBip32Xpub' &&
      member == 'Bip32Keys.fromBase58') {
    return true;
  }
  // Pre-import discovery operates on user input before there is a stored Secret.
  if (path == 'lib/core/wallet/data/datasources/bdk_wallet_datasource.dart' &&
      function == '_performDryScan' &&
      owner == null) {
    return {
      'Mnemonic.fromEntropy',
      'DescriptorSecretKey.new',
      'Descriptor.newBip44',
      'Descriptor.newBip49',
      'Descriptor.newBip84',
    }.contains(member);
  }
  // The exported swap master key is a documented, independent child secret.
  if (path == 'lib/core/swaps/data/models/swap_master_key_model.dart' &&
      owner == 'SwapMasterKeyModel') {
    return (function == 'fromBoltz' &&
            {
              'SwapMasterKey.xprv',
              'SwapMasterKey.mnemonic',
            }.contains(member)) ||
        (function == 'toBoltz' && member == 'SwapMasterKey.new');
  }
  // A Garage Key is read in one class of one file per use, and nowhere else.
  final garageKeyReader = _garageKeyReaders[path];
  if (garageKeyReader != null && owner == garageKeyReader.owner) {
    final library = symbol.split('#').first;
    return garageKeyReader.members.contains(member) &&
        (library.startsWith('package:secrets/') ||
            library.startsWith('package:robosats/'));
  }
  return false;
}

/// The workspace's package configuration: the nearest `.dart_tool/package_config.json` at or above [start].
String packageConfigPath(String start) {
  var directory = Directory(start);
  while (true) {
    final config = File('${directory.path}/.dart_tool/package_config.json');
    if (config.existsSync()) return config.path;
    if (directory.parent.path == directory.path) {
      throw StateError('No package_config.json');
    }
    directory = directory.parent;
  }
}

String dartSdkPath(String start) {
  var directory = Directory(start);
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
