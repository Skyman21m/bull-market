import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:test/test.dart';

/// A trade record of origin `takenHere` exists only as the take wrote it, and a reservation only as the repository's reservation wrote its binding: the constructors of `TradeRecord` and `TradeReservation` are called by the repository of the trade records alone, and nothing extends or implements either (#85, review of #102).
///
/// Resolved by the analyzer, so that an alias, a dot shorthand or a prefixed tear-off is the constructor it names; tests run with the package directory as working directory.
void main() {
  late AnalysisContextCollection collection;

  setUpAll(() {
    collection = AnalysisContextCollection(
      includedPaths: [Directory.current.path],
      sdkPath: _dartSdkPath(),
    );
  });

  /// Each place of the file at [path] that calls or tears off a constructor of a watched class, as `<class> <path>`, and each class of it that extends or implements one, as `subtype <class> <path>`.
  Future<List<String>> makersIn(String path) async {
    final absolute = File(path).absolute.path;
    final result = await collection
        .contextFor(absolute)
        .currentSession
        .getResolvedUnit(absolute);
    if (result is! ResolvedUnitResult) return ['$path: unresolved'];
    final makers = <String>[];
    result.unit.accept(_MakerVisitor(path, makers));
    return makers;
  }

  test(
    'are called by the repository of the trade records only, and nothing extends or implements them',
    () async {
      final makers = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        makers.addAll(await makersIn(file.path));
      }

      expect(makers.toSet(), {
        'TradeRecord lib/src/data/trade_record_repository_impl.dart',
        'TradeReservation lib/src/data/trade_record_repository_impl.dart',
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'is found behind an alias, a dot shorthand or a prefix',
    () async {
      expect(await makersIn('test/fixtures/trade_record_makers.dart'), [
        for (var i = 0; i < 4; i++)
          'TradeRecord test/fixtures/trade_record_makers.dart',
        for (var i = 0; i < 2; i++)
          'TradeReservation test/fixtures/trade_record_makers.dart',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// The Dart SDK of the Flutter that runs the tests, found from the workspace's package configuration, as the custody gate finds it.
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

/// The classes whose instances only the repository of the trade records makes.
const _watched = {'TradeRecord', 'TradeReservation'};

/// Each place that calls or tears off a constructor of a class of [_watched], resolved: through its name, a `typedef`, a prefix, a dot shorthand or a `super(…)` of a subclass; and each class that extends or implements one.
final class _MakerVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final List<String> makers;

  _MakerVisitor(this.path, this.makers);

  void _check(Element? element) {
    if (element case ConstructorElement(
      enclosingElement: InterfaceElement(:final name?),
    ) when _watched.contains(name)) {
      makers.add('$name $path');
    }
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _check(node.element);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final declared = node.declaredFragment?.element;
    if (declared != null) {
      for (final supertype in declared.allSupertypes) {
        final name = supertype.element.name;
        if (name != null && _watched.contains(name)) {
          makers.add('subtype $name $path');
        }
      }
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _check(node.element);
    super.visitConstructorName(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    _check(node.element);
    super.visitDotShorthandConstructorInvocation(node);
  }
}
