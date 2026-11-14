import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Who may name what around the trade screens (#88), read from the syntax tree of every Dart file of `features/p2p/lib` (names in code only: comments, doc comments and strings are not code).
///
/// - Only the cancel's confirmation dialog builds the acknowledgement that a cancel loses the bond: `BondLossAcknowledged.fromConfirmationDialog` is named in `lib/src/ui/trade/confirm_cancel_dialog.dart` and in the file that declares it, nowhere else.
/// - Each trade use case is called by one cubit, which the locator gives its `execute`: the take by `TakeOrderCubit`, the watch and the cancel by `TradeCubit`, the list by `ActiveTradesCubit`; no other file names them but the domain and the locator.
/// - The screens (`lib/src/ui/`) name no use case of the trades, no coordinator client, no trade repository, no limiter, no wallet port and no wallet payment offer: they call their cubits only.
/// - `TakeOrderCubit.take`, `confirm` and `back` are called by `TakeOrderSection` only, the single place a take starts, is confirmed or abandoned (`AGENTS.md`, #119): of the files that name `TakeOrderCubit`, only `lib/src/ui/take_order_section.dart` calls a method of those names (a name without its type, so a file that names the cubit and calls an unrelated `take` would be seen too, which is the safe side).
/// - The screens of the trade open no link and import no launcher, and only the bond panel (the invoice) and the trade screen (the order's address) write to the clipboard.
/// It cannot see what a cubit hands out, nor code outside `features/p2p/lib`.
void main() {
  final sources = {
    for (final path in _dartFilesUnder('lib'))
      if (!path.startsWith('lib/generated/'))
        path: File(path).readAsStringSync(),
  };

  test('the scan reads the files it rules', () {
    expect(
      sources.keys,
      containsAll([
        'lib/src/ui/trade/confirm_cancel_dialog.dart',
        'lib/src/ui/trade/trade_screen.dart',
        'lib/src/presentation/trade_cubit.dart',
        'lib/src/domain/trade/trade_cancel.dart',
      ]),
    );
  });

  test('only the confirmation dialog builds a BondLossAcknowledged', () {
    expect(_whereNamed(sources, 'fromConfirmationDialog'), {
      'lib/src/domain/trade/trade_cancel.dart',
      'lib/src/ui/trade/confirm_cancel_dialog.dart',
    });
  });

  test(
    'each trade use case is named by its cubit, the domain and the locator only',
    () {
      for (final (useCase, cubit) in [
        ('TakeOrderUsecase', 'lib/src/presentation/take_order_cubit.dart'),
        ('WatchTradeUsecase', 'lib/src/presentation/trade_cubit.dart'),
        ('CancelTradeUsecase', 'lib/src/presentation/trade_cubit.dart'),
        (
          'ListActiveTradesUsecase',
          'lib/src/presentation/active_trades_cubit.dart',
        ),
        (
          'FindPublicOrderUsecase',
          'lib/src/presentation/trade_order_page_cubit.dart',
        ),
      ]) {
        final outside = {
          for (final path in _whereNamed(sources, useCase))
            if (!path.startsWith('lib/src/domain/') &&
                path != 'lib/src/p2p_locator.dart' &&
                path != cubit)
              path,
        };
        expect(outside, isEmpty, reason: useCase);
      }
    },
  );

  test('the screens call their cubits only', () {
    final offences = <String>{
      for (final name in _notForScreens)
        for (final path in _whereNamed(sources, name))
          if (path.startsWith('lib/src/ui/')) '$path: $name',
    };
    expect(offences, isEmpty);
  });

  test('only TakeOrderSection prepares, confirms or abandons a take', () {
    for (final method in _takeSteps) {
      expect(_callersOf(sources, method), {
        'lib/src/ui/take_order_section.dart',
      }, reason: method);
    }
  });

  test(
    'the trade screens open no link, and copy only the invoice and the order\'s address',
    () {
      final tradeScreens = {
        for (final MapEntry(key: path, value: source) in sources.entries)
          if (_tradeScreens.any(path.startsWith)) path: source,
      };
      expect(tradeScreens.keys, contains('lib/src/ui/trade/bond_panel.dart'));
      for (final MapEntry(key: path, value: source) in tradeScreens.entries) {
        expect(source.contains('url_launcher'), isFalse, reason: path);
        expect(
          _namesIn(source).intersection({'launchUrl', 'launchUrlString'}),
          isEmpty,
          reason: path,
        );
      }
      expect(_whereNamed(tradeScreens, 'Clipboard'), {
        'lib/src/ui/trade/bond_panel.dart',
        'lib/src/ui/trade/trade_screen.dart',
      });
    },
  );

  group('the rules bite:', () {
    test(
      'a second caller of the take, of its confirmation or of going back is seen',
      () {
        for (final method in _takeSteps) {
          expect(
            _callersOf({
              'lib/src/ui/take_order_section.dart':
                  'void f(TakeOrderCubit c) => c.$method();',
              'lib/src/ui/trade/trade_screen.dart':
                  'void g(TakeOrderCubit c) { c.$method(); }',
              'lib/src/ui/book.dart': 'final l = [1, 2].$method(1);',
            }, method),
            {
              'lib/src/ui/take_order_section.dart',
              'lib/src/ui/trade/trade_screen.dart',
            },
            reason: method,
          );
        }
      },
    );

    test('an acknowledgement built elsewhere is seen', () {
      expect(
        _whereNamed({
          'lib/src/presentation/trade_cubit.dart':
              'final a = BondLossAcknowledged.fromConfirmationDialog();',
          'lib/src/ui/trade/trade_screen.dart':
              'const b = BondLossAcknowledged.fromConfirmationDialog;',
          'lib/src/ui/other.dart':
              '// BondLossAcknowledged.fromConfirmationDialog() in a comment\nconst c = "fromConfirmationDialog";',
        }, 'fromConfirmationDialog'),
        {
          'lib/src/presentation/trade_cubit.dart',
          'lib/src/ui/trade/trade_screen.dart',
        },
      );
    });

    test('a screen that calls a use case or a client is seen', () {
      final names = _whereNamed({
        'lib/src/ui/trade/trade_screen.dart':
            'void f(CancelTradeUsecase u) => u.execute();',
        'lib/src/ui/x.dart': 'final c = CoordinatorClient(t);',
      }, 'CancelTradeUsecase');
      expect(names, {'lib/src/ui/trade/trade_screen.dart'});
    });
  });
}

/// The files of the trade's screens.
const _tradeScreens = [
  'lib/src/ui/trade/',
  'lib/src/ui/take_order_section.dart',
  'lib/src/ui/widgets/store_token_dialog.dart',
  'lib/src/ui/widgets/trade_dialog_body.dart',
  'lib/src/ui/widgets/trade_button.dart',
];

/// The steps of a take that only its section calls (#119).
const _takeSteps = ['take', 'confirm', 'back'];

/// The files of [sources] that name `TakeOrderCubit` and call a method [method], the cubit's own file aside.
Set<String> _callersOf(Map<String, String> sources, String method) => {
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (path != 'lib/src/presentation/take_order_cubit.dart' &&
        _namesIn(source).contains('TakeOrderCubit') &&
        _callsMethod(source, method))
      path,
};

bool _callsMethod(String source, String method) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final calls = _Calls(method);
  unit.accept(calls);
  return calls.found;
}

final class _Calls extends RecursiveAstVisitor<void> {
  final String method;
  bool found = false;

  _Calls(this.method);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == method) found = true;
    super.visitMethodInvocation(node);
  }
}

/// What the screens never name.
const _notForScreens = {
  'FindPublicOrderUsecase',
  'TakeOrderUsecase',
  'WatchTradeUsecase',
  'CancelTradeUsecase',
  'ListActiveTradesUsecase',
  'CoordinatorClient',
  'TradeRecordRepository',
  'TradeTrailRepository',
  'RobotRequestLimiter',
  'P2pWalletPort',
  'walletPaymentFor',
  'TradeReader',
};

/// The files of [sources] whose code names [name].
Set<String> _whereNamed(Map<String, String> sources, String name) => {
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (_namesIn(source).contains(name)) path,
};

Set<String> _namesIn(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final names = _Names();
  unit.accept(names);
  return names.found;
}

final class _Names extends RecursiveAstVisitor<void> {
  final Set<String> found = {};

  // The references of doc comments are not code.
  @override
  void visitComment(Comment node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    found.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    final name = node.name;
    if (name != null) found.add(name.name);
    super.visitConstructorName(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final name = node.name;
    if (name != null) found.add(name.lexeme);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitNamedType(NamedType node) {
    found.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}

Iterable<String> _dartFilesUnder(String directory) sync* {
  for (final entity in Directory(directory).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity.path.replaceAll(r'\', '/');
    }
  }
}
