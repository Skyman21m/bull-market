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
  final violations = <String>[
    for (final link in productionLinks(root))
      '${link.substring(root.length + 1)}: symbolic link',
  ];
  for (final path in files) {
    final relative = path.substring(root.length + 1);
    final result = await _contextOf(
      collection,
      path,
    ).currentSession.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      violations.add('$relative: unresolved unit');
      continue;
    }
    for (final diagnostic in result.diagnostics) {
      if (diagnostic.diagnosticCode.severity.name == 'ERROR') {
        violations.add('$relative: ${diagnostic.diagnosticCode.lowerCaseName}');
      }
    }
    violations.addAll(checkUnit(result.unit, relative));
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

/// The symbolic links under the production roots, and those that stand for a whole package or feature: the gate does not follow them, so each one fails the check.
List<String> productionLinks(String root) => [
  for (final entity in _productionEntities(root))
    if (entity is Link) entity.path,
]..sort();

Iterable<FileSystemEntity> _productionEntities(String root) sync* {
  final roots = ['$root/lib'];
  for (final group in ['packages', 'features']) {
    final parent = Directory('$root/$group');
    if (!parent.existsSync()) continue;
    for (final member in parent.listSync(followLinks: false)) {
      if (member.path == '$root/packages/secrets') continue;
      if (member is Link) yield member;
      if (member is Directory) roots.add('${member.path}/lib');
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

List<String> checkUnit(CompilationUnit unit, String relativePath) {
  final visitor = _KeyMaterialVisitor(relativePath);
  unit.accept(visitor);
  return visitor.violations.toList()..sort();
}

class _KeyMaterialVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final Set<String> violations = {};

  _KeyMaterialVisitor(this.path);

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
    if (symbol == null || _isException(path, node, symbol)) return;
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

  @override
  void visitImportDirective(ImportDirective node) {
    checkTestingLibrary(node.libraryImport?.importedLibrary?.uri.toString());
    checkTestingLibrary(node.uri.stringValue);
    for (final configuration in node.configurations) {
      checkTestingLibrary(configuration.uri.stringValue);
    }
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    checkTestingLibrary(node.libraryExport?.exportedLibrary?.uri.toString());
    checkTestingLibrary(node.uri.stringValue);
    for (final configuration in node.configurations) {
      checkTestingLibrary(configuration.uri.stringValue);
    }
    checkVaultExport(node);
    super.visitExportDirective(node);
  }

  /// A class of [_garageKeyReaders] reads a key for its own use: no public member's signature can hand the bytes or the text out (issue #47).
  ///
  /// Its constructors, methods, getters, setters and fields, static ones included, return no type that [_canCarry] key material, and take no parameter that [_canReceive] it.
  /// This sees what the class's signatures let out, not where a value goes inside them, nor what other declarations of its file do with its private members.
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final reader = _garageKeyReaders[path];
    final name = node.namePart.typeName.lexeme;
    if (reader != null && name == reader.owner) {
      final element = node.declaredFragment?.element;
      if (element == null) {
        violations.add('$path: $name#unresolved class');
      } else {
        for (final member in _waysOut(element)) {
          violations.add('$path: $name.$member#can hand out key material');
        }
      }
    }
    super.visitClassDeclaration(node);
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
    super.visitMethodInvocation(node);
  }

  @override
  void visitCommentReference(CommentReference node) {}

  /// Which composition of the app hands P2P the Garage Key handle (issue #47).
  ///
  /// `AppLocator.setup` is called with a boolean literal for `withGarageKeys`, `true` only in `Bull.init` of `lib/init.dart`, the foreground composition.
  /// `AppLocator.setupP2p`, which asks the vault for the handle when its flag is true, is called only by `AppLocator.setup` of `lib/locator.dart`, with the flag that method received.
  /// Any other reference to either method (a tear-off, which `Function.apply` or a dynamic call needs) fails closed: Dart cannot reach a static method dynamically without one.
  void checkComposition(SimpleIdentifier node) {
    final element = node.element;
    if (!_isCompositionMethod(element)) return;
    final member = 'AppLocator.${element?.name}';
    final invocation = node.parent;
    if (invocation is! MethodInvocation || invocation.methodName != node) {
      violations.add('$path: $member#not a direct call');
      return;
    }
    final (:owner, :function) = _enclosingDeclaration(node);
    final flag = [
      for (final argument in invocation.argumentList.arguments)
        if (argument is NamedExpression &&
            argument.name.label.name == 'withGarageKeys')
          argument.expression,
    ].firstOrNull;
    if (element?.name == 'setupP2p') {
      if (path != 'lib/locator.dart' ||
          owner != 'AppLocator' ||
          function != 'setup') {
        violations.add('$path: $member#outside AppLocator.setup');
      } else if (flag is! SimpleIdentifier ||
          !_isCompositionFlag(flag.element)) {
        violations.add('$path: $member#withGarageKeys not forwarded');
      }
    } else if (flag is! BooleanLiteral) {
      violations.add('$path: $member#withGarageKeys not a literal');
    } else if (flag.value &&
        (path != 'lib/init.dart' || owner != 'Bull' || function != 'init')) {
      violations.add('$path: $member#withGarageKeys: true outside Bull.init');
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext()) {
      check(node.element, node);
      checkComposition(node);
    }
    super.visitSimpleIdentifier(node);
  }

  // The flag that `AppLocator.setup` forwards to `setupP2p` keeps the value its caller passed.
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_isCompositionFlag(node.writeElement)) {
      violations.add('$path: AppLocator.setup#withGarageKeys reassigned');
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (_isCompositionFlag(node.element)) {
      violations.add('$path: AppLocator.setup#withGarageKeys reassigned');
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
    super.visitPatternField(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    check(node.element, node);
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
    // The handle that reads and writes Garage Keys is asked for by the composition root alone (see [_isException]).
    _ when uri.startsWith('package:secrets/') =>
      symbol == 'GarageKeyMaterial.bytes' || symbol == 'Secrets.garageKeys',
    _ when uri.startsWith('package:robosats/') =>
      owner == 'GarageKey' && {'revealBytes', 'revealBech32'}.contains(member),
    _ => false,
  };
  return forbidden ? '$uri#$symbol' : null;
}

/// Where the P2P feature may read a Garage Key, and what each place may read (issue #28).
///
/// The repository converts the stored bytes into a `GarageKey` and back for an import (#28). The widget that shows the `robo1…` text on a protected screen does not exist yet, so no production file may reveal that text. A step that needs another name changes this table in the same pull request, where review sees both.
const _garageKeyReaders = {
  'features/p2p/lib/src/data/garage_key_repository_impl.dart': (
    owner: 'GarageKeyRepositoryImpl',
    members: {'GarageKeyMaterial.bytes', 'GarageKey.revealBytes'},
  ),
  'features/p2p/lib/src/ui/widgets/garage_key_view.dart': (
    owner: 'GarageKeyView',
    members: {'GarageKey.revealBech32'},
  ),
};

/// The public members of [owner] whose signature can hand out key material.
List<String> _waysOut(InterfaceElement owner) => [
  for (final member in <ExecutableElement>[
    ...owner.constructors,
    ...owner.methods,
    ...owner.getters,
    ...owner.setters,
  ])
    if (member.isPublic &&
        ((member is! ConstructorElement &&
                member is! SetterElement &&
                _canCarry(member.returnType)) ||
            member.formalParameters.any(
              (parameter) => _canReceive(parameter.type),
            )))
      member.name ?? '',
];

/// Whether a value of [type] can hold the bytes or the text of a key.
///
/// Text, bytes (any `Iterable<int>`, any type of `dart:typed_data`), a `BigInt`, a value of any type (`Object`, `dynamic`, a type parameter, `Function`), and a function, record or generic type with one of those anywhere in it.
bool _canCarry(DartType type) => switch (type) {
  DynamicType() || InvalidType() || TypeParameterType() => true,
  FunctionType(:final returnType, :final formalParameters) =>
    _canCarry(returnType) ||
        formalParameters.any((parameter) => _canCarry(parameter.type)),
  RecordType(:final positionalFields, :final namedFields) => [
    for (final field in positionalFields) field.type,
    for (final field in namedFields) field.type,
  ].any(_canCarry),
  InterfaceType(:final element, :final typeArguments) =>
    type.isDartCoreObject ||
        type.isDartCoreString ||
        type.isDartCoreFunction ||
        (element.library.isDartCore && element.name == 'BigInt') ||
        element.library.uri.toString() == 'dart:typed_data' ||
        [type, ...type.allSupertypes].any(
          (supertype) =>
              supertype.isDartCoreIterable &&
              supertype.typeArguments.single.isDartCoreInt,
        ) ||
        typeArguments.any(_canCarry),
  _ => false,
};

/// Whether an argument of [type] can be handed key material by the member that takes it: a callback that takes a value [_canCarry] covers, a value of any type, which may be such a callback, or a container of either.
bool _canReceive(DartType type) => switch (type) {
  DynamicType() || InvalidType() || TypeParameterType() => true,
  FunctionType() => _canCarry(type),
  RecordType(:final positionalFields, :final namedFields) => [
    for (final field in positionalFields) field.type,
    for (final field in namedFields) field.type,
  ].any(_canReceive),
  InterfaceType(:final typeArguments) =>
    type.isDartCoreObject ||
        type.isDartCoreFunction ||
        typeArguments.any(_canReceive),
  _ => false,
};

/// A declaration of `package:secrets`.
bool _isVaultDeclaration(Element element) =>
    element.library?.uri.toString().startsWith('package:secrets/') ?? false;

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

/// `AppLocator.setup` or `AppLocator.setupP2p`, the static methods that compose the app and hand P2P the Garage Key handle (issue #47).
///
/// They are matched by the name of their class in any library, so that a class of that name elsewhere is held to the same rules; renaming the class of `lib/locator.dart` already fails the gate, whose exception for `Secrets.garageKeys` names it.
bool _isCompositionMethod(Element? element) =>
    element is MethodElement &&
    element.isStatic &&
    element.enclosingElement?.name == 'AppLocator' &&
    {'setup', 'setupP2p'}.contains(element.name);

/// The `withGarageKeys` parameter of `AppLocator.setup`.
bool _isCompositionFlag(Element? element) =>
    element is FormalParameterElement &&
    element.name == 'withGarageKeys' &&
    _isCompositionMethod(element.enclosingElement) &&
    element.enclosingElement?.name == 'setup';

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
  // The Garage Key handle is asked for in the composition root, which passes it to the P2P feature alone.
  // That file is also the composition of the WorkManager isolate (`AppLocator.setup` runs there too), so where the call sits inside it still decides which isolates hold the handle.
  if (path == 'lib/locator.dart' && owner == 'AppLocator') {
    return member == 'Secrets.garageKeys' &&
        symbol.startsWith('package:secrets/');
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
