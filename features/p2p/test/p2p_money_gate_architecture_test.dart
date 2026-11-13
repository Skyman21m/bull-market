import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Where the money members of the coordinator client may be called in `features/p2p/lib`, and that each call asks `P2pMoneyGate` (#83, design note `docs/design/phase-2-taking-an-order.md` § 3.7).
///
/// The members are listed by name before they exist (#84, #89), so that this rule guards the pull requests that add them.
/// It reads the sources as text, parsed without resolution: a name is a call wherever it stands in code, a tear-off, a cascade, a call on an import prefix, an implicit `this` in an extension, a `dynamic` call and a `Symbol` included; comments, doc comments and strings are not code.
/// A declaration of a member with one of these names is not a call (a fake of the client could declare them), but every use of such a member is, whoever declares it, and so is a named argument or a record field of that name: in the feature, these names are kept for the client's members.
/// A file asks the gate when it uses the answer of `P2pMoneyGate.allowsNewTrade` or `P2pMoneyGate.allowsActionOnRecordedTrade`, called, not torn off nor dropped as a statement of its own; the file is the unit, not the function.
/// What it cannot see is in the working note of #83 and in the AGENTS.md paragraph on the gate: a trade use case that hands a tear-off out, the value of a gate's answer ignored by an `if` that does nothing, and code outside `features/p2p/lib`.
void main() {
  // Tests run with the package directory as working directory.
  final sources = {
    for (final path in _dartFilesUnder('lib'))
      path: File(path).readAsStringSync(),
  };

  test('the scan reads every Dart file of lib/, the gate included', () {
    expect(
      sources.keys,
      containsAll([
        _gate,
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
        'lib/generated/l10n/p2p_localizations.dart',
      ]),
    );
  });

  test(
    'only the trade use cases call a money member of the coordinator client, and each asks the gate',
    () {
      expect(_offences(sources), isEmpty);
    },
  );

  test(
    'no file but the gate declares or shadows P2pMoneyGate, or reads the approval',
    () {
      expect(_gateOffences(sources), isEmpty);
    },
  );

  group('the rule bites:', () {
    const tradeUseCase = 'lib/src/domain/usecases/trade/take_order_usecase.dart';
    const cubit = 'lib/src/presentation/trade_cubit.dart';

    List<String> offencesOf(String path, String source) =>
        _offences({path: source});

    test('a trade use case that asks the gate before it takes passes', () {
      expect(
        offencesOf(tradeUseCase, '''
import '../../p2p_money_gate.dart';
final class TakeOrderUsecase {
  Future<void> execute(RobosatsNetwork network) async {
    if (!P2pMoneyGate.allowsNewTrade(network)) return;
    await _client.takeOrder(1);
  }
}
'''),
        isEmpty,
      );
    });

    test('a call of takeOrder without the gate fails', () {
      expect(
        offencesOf(tradeUseCase, '''
final class TakeOrderUsecase {
  Future<void> execute() async => _client.takeOrder(1);
}
'''),
        [
          '$tradeUseCase calls takeOrder without asking P2pMoneyGate',
          '$tradeUseCase calls takeOrder without asking P2pMoneyGate.allowsNewTrade',
        ],
      );
    });

    test(
      'a take that asks only about recorded trades fails: taking an order always starts a new trade',
      () {
        expect(
          offencesOf(tradeUseCase, '''
Future<void> take(RobosatsNetwork network) async {
  if (P2pMoneyGate.allowsActionOnRecordedTrade(network)) await client.takeOrder(1);
}
'''),
          [
            '$tradeUseCase calls takeOrder without asking P2pMoneyGate.allowsNewTrade',
          ],
        );
      },
    );

    test(
      'an action on a recorded trade passes with the question about recorded trades',
      () {
        expect(
          offencesOf(
            'lib/src/domain/usecases/trade/cancel_trade_usecase.dart',
            '''
Future<void> cancel(RobosatsNetwork network) async {
  if (!P2pMoneyGate.allowsActionOnRecordedTrade(network)) return;
  await client.cancelOrder(1, cancelStatus: 3);
}
''',
          ),
          isEmpty,
        );
      },
    );

    test('a call from a file that is not a trade use case fails, gate or not', () {
      for (final path in [
        cubit,
        'lib/src/ui/trade_screen.dart',
        'lib/src/domain/usecases/take_order_usecase.dart',
        'lib/src/domain/usecases/trade/take_order.dart',
        'lib/src/domain/usecases/trade/nested/take_order_usecase.dart',
        'lib/src/data/trade_repository_impl.dart',
      ]) {
        expect(
          offencesOf(path, '''
Future<void> take(RobosatsNetwork network) async {
  if (P2pMoneyGate.allowsNewTrade(network)) await client.takeOrder(1);
}
'''),
          ['$path calls takeOrder but is not a trade use case'],
          reason: path,
        );
      }
    });

    test('every money member is watched', () {
      for (final member in _moneyMembers) {
        expect(
          offencesOf(cubit, 'void f() => client.$member();'),
          contains('$cubit calls $member but is not a trade use case'),
          reason: member,
        );
      }
    });

    test('each way of reaching a member by its name is a call', () {
      for (final (label, source) in [
        ('tear-off', 'final f = client.takeOrder;'),
        ('cascade', 'void f() { client..takeOrder(1); }'),
        ('import prefix', 'void f() => robosats.takeOrder(1);'),
        (
          'extension with an implicit this',
          'extension Wrap on CoordinatorClient { Future<void> grab() => takeOrder(1); }',
        ),
        ('dynamic call', 'void f() => (client as dynamic).takeOrder(1);'),
        ('symbol', 'final s = #takeOrder;'),
        ('interpolation', r'''final s = '${client.takeOrder}';'''),
      ]) {
        expect(
          offencesOf(cubit, source),
          ['$cubit calls takeOrder but is not a trade use case'],
          reason: label,
        );
      }
    });

    test('a comment, a doc comment or a string that names a member is no call', () {
      expect(
        offencesOf(cubit, '''
// The trade use case calls takeOrder.
/* takeOrder */
/// See [CoordinatorClient.takeOrder] and [takeOrder].
final class TradeCubit {
  final String label = 'takeOrder';
  final String other = "cancelOrder confirmFiat";
  final String raw = r'openDispute';
}
'''),
        isEmpty,
      );
    });

    test('a declaration of a member with a watched name is no call', () {
      expect(
        offencesOf(
          'lib/testing.dart',
          'final class FakeClient { Future<void> takeOrder(int id) async {} }',
        ),
        isEmpty,
      );
    });

    test('the gate named only in a comment, a string or a tear-off is not asked', () {
      for (final (label, source) in [
        ('comment', '// P2pMoneyGate.allowsNewTrade(network)\nvoid f() => client.takeOrder(1);'),
        ('string', "final s = 'P2pMoneyGate.allowsNewTrade';\nvoid f() => client.takeOrder(1);"),
        ('tear-off', 'final g = P2pMoneyGate.allowsNewTrade;\nvoid f() => client.takeOrder(1);'),
        ('result dropped', 'void f() { P2pMoneyGate.allowsNewTrade(network); client.takeOrder(1); }'),
        ('import only', "import '../../p2p_money_gate.dart';\nvoid f() => client.takeOrder(1);"),
      ]) {
        expect(
          offencesOf(tradeUseCase, source),
          contains('$tradeUseCase calls takeOrder without asking P2pMoneyGate'),
          reason: label,
        );
      }
    });

    test('the gate asked through an import prefix counts', () {
      expect(
        offencesOf(tradeUseCase, '''
import '../../p2p_money_gate.dart' as gate;
Future<void> take(RobosatsNetwork network) async {
  if (!gate.P2pMoneyGate.allowsNewTrade(network)) return;
  await client.takeOrder(1);
}
'''),
        isEmpty,
      );
    });

    test('a trade use case may not be a part of another library', () {
      expect(
        offencesOf(tradeUseCase, '''
part of '../../../presentation/trade_cubit.dart';
Future<void> take(RobosatsNetwork network) async {
  if (P2pMoneyGate.allowsNewTrade(network)) await client.takeOrder(1);
}
'''),
        ['$tradeUseCase is a part of another library'],
      );
    });

    test('a gate of its own, a shadow or a read of the approval elsewhere fails', () {
      for (final (label, source, offence) in [
        (
          'class',
          'abstract final class P2pMoneyGate { static bool allowsNewTrade(Object n) => true; }',
          'names P2pMoneyGate other than as P2pMoneyGate.<member>',
        ),
        (
          'local variable',
          'void f() { final P2pMoneyGate = _Open(); P2pMoneyGate.allowsNewTrade(n); }',
          'names P2pMoneyGate other than as P2pMoneyGate.<member>',
        ),
        (
          'import prefix',
          "import 'open_gate.dart' as P2pMoneyGate;",
          'names P2pMoneyGate other than as P2pMoneyGate.<member>',
        ),
        (
          'parameter',
          'bool f(Object P2pMoneyGate) => true;',
          'names P2pMoneyGate other than as P2pMoneyGate.<member>',
        ),
        (
          'approval read',
          'final open = P2pMoneyGate.mainnetApproved;',
          'reads mainnetApproved',
        ),
      ]) {
        expect(
          _gateOffences({cubit: source}),
          ['$cubit $offence'],
          reason: label,
        );
      }
      // The gate's own file declares it, and its imports and uses through the class pass.
      expect(
        _gateOffences({
          _gate: 'abstract final class P2pMoneyGate { static const bool mainnetApproved = false; }',
          cubit: '''
import '../domain/p2p_money_gate.dart' show P2pMoneyGate;
import '../domain/p2p_money_gate.dart' as gate show P2pMoneyGate;
final a = P2pMoneyGate.allowsNewTrade(n);
final b = gate.P2pMoneyGate.allowsActionOnRecordedTrade(n);
''',
        }),
        isEmpty,
      );
    });
  });

  test('the gate has no input but the network and its one constant', () {
    // A runtime switch, a build flag (`bool.fromEnvironment`), an environment variable or a developer-mode toggle would need an import, a field, a getter or another expression here: each changes what is pinned.
    // The value of the approval is pinned apart, in `p2p_money_gate_approval_test.dart`, which the pull request of the owner's approval changes.
    final unit = parseString(content: sources[_gate] ?? fail('no gate')).unit;
    expect(unit.directives.map((d) => d.toSource()), [
      "import 'package:robosats/robosats.dart' show RobosatsNetwork;",
    ]);
    final gate = unit.declarations.single as ClassDeclaration;
    expect(gate.namePart.typeName.lexeme, 'P2pMoneyGate');
    expect(gate.abstractKeyword, isNotNull);
    expect(gate.finalKeyword, isNotNull);
    expect(gate.extendsClause, isNull);
    expect(gate.implementsClause, isNull);
    expect(gate.withClause, isNull);
    final members = switch (gate.body) {
      BlockClassBody(:final members) => members,
      _ => fail('no body'),
    };
    expect(
      [
        for (final member in members)
          switch (member) {
            FieldDeclaration(:final fields, :final isStatic) => [
              'field',
              if (isStatic) 'static',
              ?fields.keyword?.lexeme,
              ?fields.type?.toSource(),
              for (final variable in fields.variables)
                '${variable.name.lexeme} = ${variable.initializer is BooleanLiteral ? '<true or false>' : variable.initializer?.toSource()}',
            ].join(' '),
            MethodDeclaration(:final body) => [
              'method',
              if (member.isStatic) 'static',
              ?member.returnType?.toSource(),
              '${member.name.lexeme}${member.parameters?.toSource()}',
              switch (body) {
                ExpressionFunctionBody(:final expression) =>
                  '=> ${expression.toSource()}',
                _ => body.toSource(),
              },
            ].join(' '),
            _ => member.toSource(),
          },
      ],
      [
        'field static const bool mainnetApproved = <true or false>',
        'method static bool allowsNewTrade(RobosatsNetwork network) => switch (network) {RobosatsNetwork.testnet => true, RobosatsNetwork.mainnet => mainnetApproved}',
        'method static bool allowsActionOnRecordedTrade(RobosatsNetwork network) => true',
      ],
    );
  });

  group('the live tests', () {
    // `package:p2p/testing.dart` hands the coordinator client to the integration tests: they stay read-only for money on every network, and their robots stay on testnet (design note § 5).
    const folder = '../../integration_test';

    test('never name a money member, nor the gate', () {
      final files = _dartFilesUnder(folder);
      expect(files, contains('$folder/p2p_robot_tor_test.dart'));
      expect(
        {
          for (final path in files)
            if (_MoneyFacts.of(File(path).readAsStringSync())
                case final facts
                when facts.calls.isNotEmpty || facts.namesGate)
              path,
        },
        isEmpty,
      );
    });

    test('make robots on testnet only', () {
      final source = File('$folder/p2p_robot_tor_test.dart').readAsStringSync();
      expect(
        source,
        contains('const _network = RobosatsNetwork.testnet;'),
      );
      expect(_tokens(source).map((t) => t.lexeme).join(' '), isNot(contains('RobosatsNetwork . mainnet')));
    });
  });
}

/// The library of the gate.
const _gate = 'lib/src/domain/p2p_money_gate.dart';

/// The members of `CoordinatorClient` that lock, move or release funds, or that act on a trade whose bond or escrow is locked (design note § 3.1, § 3.7).
///
/// `fetchOrder`, `ratePlatform`, `fetchChat` and `postChat` move no money and are not listed.
/// A money member added to the package under another name must be added here in the pull request that adds it.
const _moneyMembers = {
  'takeOrder',
  'cancelOrder',
  'submitPayoutInvoice',
  'submitPayoutAddress',
  'confirmFiat',
  'undoConfirmFiat',
  'openDispute',
};

/// The questions the gate answers: a new trade, or an action on a trade already recorded.
const _gateQuestions = {'allowsNewTrade', 'allowsActionOnRecordedTrade'};

/// Whether the file at [path] is a trade use case: a file `lib/src/domain/usecases/trade/<name>_usecase.dart`, one level deep, as the Garage's screens are grouped under `lib/src/ui/garage/`.
bool _isTradeUseCase(String path) =>
    RegExp(r'^lib/src/domain/usecases/trade/[a-z0-9_]+_usecase\.dart$')
        .hasMatch(path);

/// Each breach of the rule in [sources], by path.
List<String> _offences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    ...() {
      final facts = _MoneyFacts.of(source);
      return [
        if (_isTradeUseCase(path) && facts.isPart)
          '$path is a part of another library',
        for (final member in facts.calls) ...[
          if (!_isTradeUseCase(path))
            '$path calls $member but is not a trade use case'
          else ...[
            if (facts.asks.isEmpty)
              '$path calls $member without asking P2pMoneyGate',
            if (member == 'takeOrder' &&
                !facts.asks.contains('allowsNewTrade'))
              '$path calls $member without asking P2pMoneyGate.allowsNewTrade',
          ],
        ],
      ];
    }(),
];

/// Each file of [sources] but the gate's that declares or shadows `P2pMoneyGate`, or reads the approval.
///
/// In code, a name `P2pMoneyGate` always followed by `.` is the class used, unprefixed or after an import prefix; anything else (a class, a variable, a parameter of that name) could stand in for the gate.
/// In the directives, it may be shown or hidden, never be an import prefix.
List<String> _gateOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (path != _gate) ...() {
      final unit = parseString(content: source, throwIfDiagnostics: false).unit;
      final codeFrom = unit.directives.isEmpty
          ? 0
          : unit.directives.last.endToken.end;
      final tokens = _tokensOf(unit);
      return [
        if (tokens.any(
          (t) =>
              t.lexeme == 'P2pMoneyGate' &&
              (t.offset < codeFrom
                  ? t.previous?.lexeme == 'as'
                  : t.next?.type != TokenType.PERIOD),
        ))
          '$path names P2pMoneyGate other than as P2pMoneyGate.<member>',
        if (tokens.any((t) => t.lexeme == 'mainnetApproved'))
          '$path reads mainnetApproved',
      ];
    }(),
];

/// The code tokens of [source]: comments are not in the stream, and a string is one token.
List<Token> _tokens(String source) =>
    _tokensOf(parseString(content: source, throwIfDiagnostics: false).unit);

List<Token> _tokensOf(CompilationUnit unit) {
  final tokens = <Token>[];
  Token? token = unit.beginToken;
  while (token != null && !token.isEof) {
    tokens.add(token);
    token = token.next;
  }
  return tokens;
}

/// What a source calls of the money members, and which questions of the gate it asks.
final class _MoneyFacts {
  /// The money members named in code, by name.
  final Set<String> calls;

  /// The questions of the gate whose answer the code uses: a call on `P2pMoneyGate`, not a tear-off, not a statement of its own.
  final Set<String> asks;

  /// Whether `P2pMoneyGate` is named in code at all.
  final bool namesGate;

  /// Whether the source is a `part of` another library.
  final bool isPart;

  _MoneyFacts(this.calls, this.asks, this.namesGate, this.isPart);

  factory _MoneyFacts.of(String source) {
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final visitor = _MoneyVisitor();
    unit.accept(visitor);
    return _MoneyFacts(
      visitor.calls,
      visitor.asks,
      visitor.namesGate,
      unit.directives.any((d) => d is PartOfDirective),
    );
  }
}

final class _MoneyVisitor extends RecursiveAstVisitor<void> {
  final Set<String> calls = {};
  final Set<String> asks = {};
  bool namesGate = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_moneyMembers.contains(node.name)) calls.add(node.name);
    if (node.name == 'P2pMoneyGate') namesGate = true;
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    for (final component in node.components) {
      if (_moneyMembers.contains(component.lexeme)) calls.add(component.lexeme);
    }
    super.visitSymbolLiteral(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final onGate = switch (node.target) {
      SimpleIdentifier(name: 'P2pMoneyGate') => true,
      PrefixedIdentifier(identifier: SimpleIdentifier(name: 'P2pMoneyGate')) =>
        true,
      _ => false,
    };
    if (onGate &&
        _gateQuestions.contains(name) &&
        node.parent is! ExpressionStatement) {
      asks.add(name);
    }
    super.visitMethodInvocation(node);
  }

  /// A `[name]` in a doc comment names a member without using it.
  @override
  void visitCommentReference(CommentReference node) {}
}

/// Every Dart file under [folder], as a path that starts with [folder].
List<String> _dartFilesUnder(String folder) => [
  for (final file in Directory(folder).listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart')) file.path,
];
