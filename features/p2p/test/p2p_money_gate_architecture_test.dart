import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Where the money members of the coordinator client may be called in `features/p2p/lib`, and that each call is refused unless `P2pMoneyGate` said yes (#83, design note `docs/design/phase-2-taking-an-order.md` § 3.7).
///
/// The members are listed by name before they exist (#84, #89), so that this rule guards the pull requests that add them.
/// It reads the sources as text, parsed without resolution: a name is a use wherever it stands in code, a tear-off, a cascade, a call on an import prefix, an implicit `this` in an extension or a mixin, a `dynamic` call and a `Symbol` included; comments, doc comments and strings are not code.
/// A declaration of a member with one of these names is not a use (a fake of the client could declare them), but a named argument or a record field of that name is: in the feature, these names are kept for the client's members.
/// Outside the trade use cases (files `lib/src/domain/usecases/trade/<name>_usecase.dart`, not a `part`), any use is refused.
/// Inside them, a member may only be called (no tear-off, no `Symbol`), and each call needs its own guard, the gate's answer deciding before it:
/// - the guard is a call `P2pMoneyGate.allowsNewTrade(n)` for `takeOrder`, `P2pMoneyGate.allowsActionOnRecordedTrade(n)` for every other member, with one argument;
/// - `P2pMoneyGate` is the gate's own library, imported by its relative path or as `package:p2p/src/domain/p2p_money_gate.dart`, without hiding it, unprefixed or through that import's prefix (another library declaring the name as well would make the name ambiguous, which does not compile);
/// - the whole condition of an `if` without a `case` is that call, in parentheses or not, or its negation by one `!`, and nothing else (no `&&`, `||`, `await` or `?:`);
/// - either `if (!gate) <exits>` or `if (gate) … else <exits>` stands before the call in a block that contains the call, or the call is inside the `then` branch of `if (gate)`; a branch exits when it is a `return`, a `throw`, a `rethrow`, or a non-empty block whose last statement exits;
/// - `n` is a simple name and the call's second positional argument, its network as every client member takes it, is that same name, which no statement of the file assigns and which is not declared again between the guard and the call.
/// So an `assert`, an expression statement, an unused variable, an `if` whose branch does not exit, a guard in another function or in a nested block, and a gate asked about a literal or another network are not guards.
/// What it cannot see is left to the money review, as the AGENTS.md paragraph on the gate says: a callable that a trade use case hands out once the gate said yes, the value bound to `n` (that it is the trade's network is #87's to show), code outside `features/p2p/lib`, an inherited member or a class named `P2pMoneyGate` from another package, money moved by anything but these members (a payable mainnet invoice shown from `fetchOrder`, the wallet's `payInvoice` of slice 6), and a member added to the package under a name this list does not have yet.
/// An extension on `CoordinatorClient`, which could rename a member, and a raw `CoordinatorTransport.send` are refused anywhere in the feature by `robot_bindings_architecture_test.dart`.
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

  test('the money members are these seven, written out', () {
    // A member removed from the list would stop being watched without a sign: the list is pinned here, not looped over itself (review of #98).
    expect(_moneyMembers, {
      'takeOrder',
      'cancelOrder',
      'submitPayoutInvoice',
      'submitPayoutAddress',
      'confirmFiat',
      'undoConfirmFiat',
      'openDispute',
    });
  });

  test(
    'only the trade use cases call a money member of the coordinator client, each after the gate said yes',
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
    const tradeUseCase =
        'lib/src/domain/usecases/trade/take_order_usecase.dart';
    const cancelUseCase =
        'lib/src/domain/usecases/trade/cancel_trade_usecase.dart';
    const cubit = 'lib/src/presentation/trade_cubit.dart';
    const import = "import '../../p2p_money_gate.dart';\n";
    const take = 'await client.takeOrder(coordinator, network, 1);';
    const notAsked =
        '$tradeUseCase calls takeOrder without asking P2pMoneyGate.allowsNewTrade first';
    const otherNetwork =
        '$tradeUseCase calls takeOrder on another network than it asked P2pMoneyGate.allowsNewTrade about';

    List<String> offencesOf(String path, String source) =>
        _offences({path: source});

    /// A take use case whose method body is [body], with the gate imported.
    String takeWith(String body) =>
        '${import}Future<void> take(RobosatsNetwork network) async {\n$body\n}\n';

    test('each form of a guard that decides passes', () {
      for (final (label, source) in [
        (
          'negated, return',
          takeWith('if (!P2pMoneyGate.allowsNewTrade(network)) return;\n$take'),
        ),
        (
          'negated in parentheses, block ending in a throw',
          takeWith(
            'if (!(P2pMoneyGate.allowsNewTrade(network))) {\n  log();\n  throw StateError("closed");\n}\n$take',
          ),
        ),
        (
          'positive, the call in the then branch',
          takeWith('if (P2pMoneyGate.allowsNewTrade(network)) {\n  $take\n}'),
        ),
        (
          'positive, the call after, an else that returns',
          takeWith(
            'if ((P2pMoneyGate.allowsNewTrade(network))) {\n  log();\n} else {\n  return;\n}\n$take',
          ),
        ),
        (
          'the call in a closure after the guard',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nawait limiter.send(() => client.takeOrder(coordinator, network, 1));',
          ),
        ),
        (
          'the call in a nested block after the guard',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\ntry {\n  $take\n} finally {}',
          ),
        ),
        (
          'a cascade',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nclient..takeOrder(coordinator, network, 1);',
          ),
        ),
        (
          'the gate through its import prefix',
          "import '../../p2p_money_gate.dart' as gate;\nFuture<void> take(RobosatsNetwork network) async {\n  if (!gate.P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'the gate by its package URI, shown',
          "import 'package:p2p/src/domain/p2p_money_gate.dart' show P2pMoneyGate;\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
      ]) {
        expect(offencesOf(tradeUseCase, source), isEmpty, reason: label);
      }
    });

    test('an action on a recorded trade passes with its own question', () {
      expect(
        offencesOf(cancelUseCase, '''
$import
Future<void> cancel(RobosatsNetwork network) async {
  if (!P2pMoneyGate.allowsActionOnRecordedTrade(network)) return;
  await client.cancelOrder(coordinator, network, 1, cancelStatus: 1);
}
'''),
        isEmpty,
      );
    });

    test(
      'an answer that does not decide is no guard, an assert first: it is stripped from release builds',
      () {
        for (final (label, body) in [
          ('assert', 'assert(P2pMoneyGate.allowsNewTrade(network));\n$take'),
          (
            'assert of a closure that returns',
            'assert(() {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return false;\n  return true;\n}());\n$take',
          ),
          (
            'expression statement',
            'P2pMoneyGate.allowsNewTrade(network);\n$take',
          ),
          (
            'parenthesised statement',
            '(P2pMoneyGate.allowsNewTrade(network));\n$take',
          ),
          (
            'awaited',
            'await Future.value(P2pMoneyGate.allowsNewTrade(network));\n$take',
          ),
          (
            'assigned, unused',
            'final ok = P2pMoneyGate.allowsNewTrade(network);\n$take',
          ),
          (
            'assigned, then tested',
            'final ok = P2pMoneyGate.allowsNewTrade(network);\nif (!ok) return;\n$take',
          ),
          ('|| true', 'P2pMoneyGate.allowsNewTrade(network) || true;\n$take'),
          (
            '|| true in the condition',
            'if (!(P2pMoneyGate.allowsNewTrade(network) || true)) return;\n$take',
          ),
          (
            'false && in the condition',
            'if (false && !P2pMoneyGate.allowsNewTrade(network)) return;\n$take',
          ),
          (
            '&& false in the condition',
            'if (!P2pMoneyGate.allowsNewTrade(network) && false) return;\n$take',
          ),
          (
            'await in the condition',
            'if (!await Future.value(P2pMoneyGate.allowsNewTrade(network))) return;\n$take',
          ),
          (
            'double negation',
            'if (!!P2pMoneyGate.allowsNewTrade(network)) return;\n$take',
          ),
          ('empty then', 'if (P2pMoneyGate.allowsNewTrade(network)) {}\n$take'),
          (
            'negated, empty then',
            'if (!P2pMoneyGate.allowsNewTrade(network)) {}\n$take',
          ),
          (
            'negated, a then that does not exit',
            'if (!P2pMoneyGate.allowsNewTrade(network)) {\n  log();\n}\n$take',
          ),
          (
            'positive, an else that does not exit',
            'if (P2pMoneyGate.allowsNewTrade(network)) {} else {\n  log();\n}\n$take',
          ),
          (
            'the call in the else branch',
            'if (!P2pMoneyGate.allowsNewTrade(network)) {\n  log();\n} else {\n  $take\n}',
          ),
          (
            'a guard in a nested block',
            'if (ready) {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n}\n$take',
          ),
          (
            'a guard in a closure',
            'final check = () {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n};\n$take',
          ),
          (
            'the guard after the call',
            '$take\nif (!P2pMoneyGate.allowsNewTrade(network)) return;',
          ),
          (
            'a conditional expression',
            'P2pMoneyGate.allowsNewTrade(network) ? await client.takeOrder(coordinator, network, 1) : null;',
          ),
          (
            'an if-case',
            'if (P2pMoneyGate.allowsNewTrade(network) case false) return;\n$take',
          ),
        ]) {
          expect(offencesOf(tradeUseCase, takeWith(body)), [
            notAsked,
          ], reason: label);
        }
      },
    );

    test('a guard in another function of the file is no guard', () {
      expect(
        offencesOf(tradeUseCase, '''
$import
bool open(RobosatsNetwork network) {
  if (!P2pMoneyGate.allowsNewTrade(network)) return false;
  return true;
}
Future<void> rawTake(RobosatsNetwork network) => client.takeOrder(coordinator, network, 1);
'''),
        [notAsked],
      );
      expect(
        offencesOf(tradeUseCase, '''
$import
bool open(RobosatsNetwork n) => P2pMoneyGate.allowsNewTrade(n);
mixin Taker on CoordinatorClient {
  Future<void> grab(Coordinator c, RobosatsNetwork n) => takeOrder(c, n, 1);
}
'''),
        [notAsked],
      );
    });

    test('a gate that is not this feature\'s is no guard', () {
      for (final (label, source) in [
        (
          'another class (A14)',
          takeWith('if (!Fake.allowsNewTrade(network)) return;\n$take'),
        ),
        (
          'a prefix bound to another library',
          "import 'package:robosats/robosats.dart' as gate;\nFuture<void> take(RobosatsNetwork network) async {\n  if (!gate.P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'the gate not imported, another library is',
          "import 'package:evil/evil.dart';\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'the gate imported with its class hidden',
          "import '../../p2p_money_gate.dart' hide P2pMoneyGate;\nimport 'package:evil/evil.dart';\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'the gate imported with another name shown',
          "import '../../p2p_money_gate.dart' show Other;\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'a file of the same name elsewhere',
          "import '../p2p_money_gate.dart';\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
        (
          'the prefixed gate used unprefixed',
          "import '../../p2p_money_gate.dart' as gate;\nimport 'package:evil/evil.dart';\nFuture<void> take(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  $take\n}\n",
        ),
      ]) {
        expect(offencesOf(tradeUseCase, source), [notAsked], reason: label);
      }
    });

    test('a gate asked about another network than the call\'s fails', () {
      for (final (label, source) in [
        (
          'a literal testnet, a call on mainnet',
          '${import}Future<void> take() async {\n  if (!P2pMoneyGate.allowsNewTrade(RobosatsNetwork.testnet)) return;\n  await client.takeOrder(coordinator, RobosatsNetwork.mainnet, 1);\n}\n',
        ),
        (
          'a literal on both sides',
          '${import}Future<void> take() async {\n  if (!P2pMoneyGate.allowsNewTrade(RobosatsNetwork.testnet)) return;\n  await client.takeOrder(coordinator, RobosatsNetwork.testnet, 1);\n}\n',
        ),
        (
          'two fields',
          '${import}Future<void> take(Trade trade, NetworkRobot robot) async {\n  if (!P2pMoneyGate.allowsNewTrade(trade.network)) return;\n  await client.takeOrder(coordinator, robot.network, 1);\n}\n',
        ),
        (
          'two names',
          '${import}Future<void> take(RobosatsNetwork a, RobosatsNetwork b) async {\n  if (!P2pMoneyGate.allowsNewTrade(a)) return;\n  await client.takeOrder(coordinator, b, 1);\n}\n',
        ),
        (
          'the name assigned in between',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nnetwork = RobosatsNetwork.mainnet;\n$take',
          ),
        ),
        (
          'the name assigned anywhere in the file',
          '${takeWith('if (!P2pMoneyGate.allowsNewTrade(network)) return;\n$take')}void reset() { network = RobosatsNetwork.mainnet; }\n',
        ),
        (
          'the name declared again by a closure',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nawait each(RobosatsNetwork.values, (network) => client.takeOrder(coordinator, network, 1));',
          ),
        ),
        (
          'the name declared again by a variable',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\n{\n  final network = RobosatsNetwork.mainnet;\n  $take\n}',
          ),
        ),
        (
          'no network argument',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nawait client.takeOrder(1);',
          ),
        ),
        (
          'the network as a named argument',
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nawait client.takeOrder(coordinator, 1, network: network);',
          ),
        ),
      ]) {
        expect(offencesOf(tradeUseCase, source), [otherNetwork], reason: label);
      }
    });

    test('each money member needs its own question: an ungated action fails (A9)', () {
      for (final member in ['cancelOrder', 'confirmFiat', 'openDispute']) {
        expect(
          offencesOf(
            cancelUseCase,
            '${import}Future<void> act(RobosatsNetwork network) async {\n  await client.$member(coordinator, network, 1);\n}\n',
          ),
          [
            '$cancelUseCase calls $member without asking P2pMoneyGate.allowsActionOnRecordedTrade first',
          ],
          reason: member,
        );
      }
      // Taking always starts a new trade; anything else acts on a recorded one.
      expect(
        offencesOf(
          tradeUseCase,
          takeWith(
            'if (!P2pMoneyGate.allowsActionOnRecordedTrade(network)) return;\n$take',
          ),
        ),
        [notAsked],
      );
      expect(
        offencesOf(
          cancelUseCase,
          '${import}Future<void> cancel(RobosatsNetwork network) async {\n  if (!P2pMoneyGate.allowsNewTrade(network)) return;\n  await client.cancelOrder(coordinator, network, 1);\n}\n',
        ),
        [
          '$cancelUseCase calls cancelOrder without asking P2pMoneyGate.allowsActionOnRecordedTrade first',
        ],
      );
      // One guarded call does not cover another.
      expect(
        offencesOf(
          tradeUseCase,
          takeWith(
            'if (!P2pMoneyGate.allowsNewTrade(network)) return;\n$take\nawait client.cancelOrder(coordinator, network, 1);',
          ),
        ),
        [
          '$tradeUseCase calls cancelOrder without asking P2pMoneyGate.allowsActionOnRecordedTrade first',
        ],
      );
    });

    test('a trade use case may only call a member, not reach it otherwise', () {
      for (final (label, body) in [
        (
          'tear-off',
          'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nfinal f = client.takeOrder;',
        ),
        (
          'symbol',
          'if (!P2pMoneyGate.allowsNewTrade(network)) return;\nfinal s = #takeOrder;',
        ),
      ]) {
        expect(offencesOf(tradeUseCase, takeWith(body)), [
          '$tradeUseCase names takeOrder other than in a call',
        ], reason: label);
      }
    });

    test(
      'a use from a file that is not a trade use case fails, guard or not',
      () {
        for (final path in [
          cubit,
          'lib/src/ui/trade_screen.dart',
          'lib/src/domain/usecases/take_order_usecase.dart',
          'lib/src/domain/usecases/trade/take_order.dart',
          'lib/src/domain/usecases/trade/nested/take_order_usecase.dart',
          'lib/src/data/trade_repository_impl.dart',
          'lib/public/p2p_facade.dart',
          'lib/testing.dart',
        ]) {
          expect(
            offencesOf(
              path,
              takeWith(
                'if (!P2pMoneyGate.allowsNewTrade(network)) return;\n$take',
              ),
            ),
            ['$path calls takeOrder but is not a trade use case'],
            reason: path,
          );
        }
      },
    );

    test(
      'each of the seven members is watched outside the trade use cases',
      () {
        for (final member in [
          'takeOrder',
          'cancelOrder',
          'submitPayoutInvoice',
          'submitPayoutAddress',
          'confirmFiat',
          'undoConfirmFiat',
          'openDispute',
        ]) {
          expect(offencesOf(cubit, 'void f() => client.$member();'), [
            '$cubit calls $member but is not a trade use case',
          ], reason: member);
        }
      },
    );

    test('each way of reaching a member by its name is a use', () {
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
        (
          'Function.apply',
          'void f() => Function.apply(client.takeOrder, [1]);',
        ),
      ]) {
        expect(offencesOf(cubit, source), [
          '$cubit calls takeOrder but is not a trade use case',
        ], reason: label);
      }
    });

    test(
      'a comment, a doc comment or a string that names a member is no use',
      () {
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
      },
    );

    test('a declaration of a member with a watched name is no use', () {
      expect(
        offencesOf(
          'lib/testing.dart',
          'final class FakeClient { Future<void> takeOrder(int id) async {} }',
        ),
        isEmpty,
      );
    });

    test('a trade use case may not be a part of another library', () {
      expect(
        offencesOf(tradeUseCase, '''
part of '../../../presentation/trade_cubit.dart';
Future<void> take(RobosatsNetwork network) async {
  if (!P2pMoneyGate.allowsNewTrade(network)) return;
  $take
}
'''),
        ['$tradeUseCase is a part of another library', notAsked],
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
          'getter of a class',
          'final class TakeOrderUsecase { Object get P2pMoneyGate => _Open(); }',
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
        expect(_gateOffences({cubit: source}), [
          '$cubit $offence',
        ], reason: label);
      }
      // The gate's own file declares it, and its imports and uses through the class pass.
      expect(
        _gateOffences({
          _gate:
              'abstract final class P2pMoneyGate { static const bool mainnetApproved = false; }',
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
        'method static bool allowsActionOnRecordedTrade(RobosatsNetwork network) => switch (network) {RobosatsNetwork.testnet => true, RobosatsNetwork.mainnet => mainnetApproved}',
      ],
    );
  });

  group('the live tests', () {
    // `package:p2p/testing.dart` hands the coordinator client to the integration tests: they stay read-only for money on every network, and their robots stay on testnet (design note § 5).
    const folder = '../../integration_test';

    test('never name a money member, nor the gate', () {
      final files = _dartFilesUnder(folder);
      expect(files, contains('$folder/p2p_robot_tor_test.dart'));
      expect({
        for (final path in files)
          if (_MoneyVisitor.of(File(path).readAsStringSync()) case final facts
              when facts.named.isNotEmpty || facts.namesGate)
            path,
      }, isEmpty);
    });

    test('make robots with no network value but RobosatsNetwork.testnet', () {
      expect(
        _liveNetworkOffences(
          File('$folder/p2p_robot_tor_test.dart').readAsStringSync(),
        ),
        isEmpty,
      );
    });

    test('the check of the robot test sees the ways to mainnet', () {
      const head = 'const _network = RobosatsNetwork.testnet;\n';
      expect(_liveNetworkOffences('final n = 1;'), [
        'no const _network = RobosatsNetwork.testnet;',
      ]);
      for (final (label, line) in [
        ('mainnet', 'final n = RobosatsNetwork.mainnet;'),
        ('mainnet on two lines', 'final n = RobosatsNetwork\n  .mainnet;'),
        ('values', 'final n = RobosatsNetwork.values.first;'),
        ('byName', "final n = RobosatsNetwork.values.byName('mainnet');"),
        ('fromWire', "final n = RobosatsNetwork.fromWire('mainnet');"),
        ('another mainnet', 'final o = federation.mainnet.onion;'),
      ]) {
        expect(_liveNetworkOffences('$head$line'), isNotEmpty, reason: label);
      }
      // The one use of `mainnet` the test has: the federation entry's mainnet onion, which it compares the testnet one against.
      expect(
        _liveNetworkOffences(
          '${head}void f() { expect(a, isNot(coordinator.mainnet.onion)); _measure(values); }',
        ),
        isEmpty,
      );
    });
  });
}

/// The library of the gate.
const _gate = 'lib/src/domain/p2p_money_gate.dart';

/// The members of `CoordinatorClient` that lock, move or release funds, or that act on a trade whose bond or escrow is locked (design note § 3.1, § 3.7).
///
/// `fetchOrder`, `ratePlatform`, `fetchChat` and `postChat` move no money and are not listed.
/// A money member added to the package under another name, a reward claim (`POST /api/reward/`, a payout) included, must be added here in the pull request that adds it.
const _moneyMembers = {
  'takeOrder',
  'cancelOrder',
  'submitPayoutInvoice',
  'submitPayoutAddress',
  'confirmFiat',
  'undoConfirmFiat',
  'openDispute',
};

/// The question of the gate each money member asks: taking an order starts a new trade, the others act on a recorded one.
String _questionFor(String member) =>
    member == 'takeOrder' ? 'allowsNewTrade' : 'allowsActionOnRecordedTrade';

/// The questions the gate answers.
const _gateQuestions = {'allowsNewTrade', 'allowsActionOnRecordedTrade'};

/// Whether the file at [path] is a trade use case: a file `lib/src/domain/usecases/trade/<name>_usecase.dart`, one level deep, as the Garage's screens are grouped under `lib/src/ui/garage/`.
bool _isTradeUseCase(String path) => RegExp(
  r'^lib/src/domain/usecases/trade/[a-z0-9_]+_usecase\.dart$',
).hasMatch(path);

/// Each breach of the rule in [sources], by path.
List<String> _offences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    ..._offencesOf(path, source),
];

List<String> _offencesOf(String path, String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final facts = _MoneyVisitor();
  unit.accept(facts);
  if (!_isTradeUseCase(path)) {
    return [
      for (final member in facts.named)
        '$path calls $member but is not a trade use case',
    ];
  }
  final gate = _GateImport.of(unit, path);
  return [
    if (unit.directives.any((d) => d is PartOfDirective))
      '$path is a part of another library',
    for (final member in facts.namedOtherwise)
      '$path names $member other than in a call',
    for (final call in facts.calls)
      ...() {
        final member = call.methodName.name;
        final question = _questionFor(member);
        final guards = [
          for (final guard in _guardsOf(call, gate))
            if (guard.question == question) guard,
        ];
        if (guards.isEmpty) {
          return [
            '$path calls $member without asking P2pMoneyGate.$question first',
          ];
        }
        final network = _networkOf(call);
        final same = guards.any(
          (guard) =>
              network != null &&
              guard.network == network &&
              !facts.assigned.contains(network) &&
              !facts.declarations.any(
                (d) =>
                    d.name == network &&
                    d.offset > guard.end &&
                    d.offset < call.offset,
              ),
        );
        return [
          if (!same)
            '$path calls $member on another network than it asked P2pMoneyGate.$question about',
        ];
      }(),
  ];
}

/// The network a call of a client member is made on: its second positional argument, as every member takes `(coordinator, network, …)`, when it is a simple name.
String? _networkOf(MethodInvocation call) {
  final positional = [
    for (final argument in call.argumentList.arguments)
      if (argument is! NamedExpression) argument,
  ];
  return switch (positional) {
    [_, SimpleIdentifier(:final name), ...] => name,
    _ => null,
  };
}

/// A guard: the question asked of the gate, the simple name of the network it was asked about (or `null`), and where it ends.
typedef _Guard = ({String question, String? network, int end});

/// The guards that decide before [call]: an `if` that refuses, before it in a block that contains it, or an `if (gate)` whose `then` branch contains it.
List<_Guard> _guardsOf(AstNode call, _GateImport gate) {
  final guards = <_Guard>[];
  var child = call;
  for (var parent = call.parent; parent != null; parent = parent.parent) {
    if (parent is Block) {
      for (final statement in parent.statements) {
        if (identical(statement, child)) break;
        if (statement is IfStatement) {
          if (_refusingGuard(statement, gate) case final guard?) {
            guards.add(guard);
          }
        }
      }
    } else if (parent is IfStatement &&
        identical(child, parent.thenStatement) &&
        parent.caseClause == null) {
      if (_asked(parent.expression, gate, negated: false) case final guard?) {
        guards.add(guard);
      }
    }
    child = parent;
  }
  return guards;
}

/// The guard of `if (!gate) <exits>` or `if (gate) … else <exits>`, after which the gate said yes.
_Guard? _refusingGuard(IfStatement statement, _GateImport gate) {
  if (statement.caseClause != null) return null;
  if (_asked(statement.expression, gate, negated: true) case final guard?
      when _exits(statement.thenStatement)) {
    return guard;
  }
  final otherwise = statement.elseStatement;
  if (_asked(statement.expression, gate, negated: false) case final guard?
      when otherwise != null && _exits(otherwise)) {
    return guard;
  }
  return null;
}

/// The guard [condition] is, when it is a question of the gate, negated by one `!` when [negated], in parentheses or not, and nothing else.
_Guard? _asked(
  Expression condition,
  _GateImport gate, {
  required bool negated,
}) {
  var expression = condition.unParenthesized;
  if (negated) {
    if (expression case PrefixExpression(
      operator: Token(type: TokenType.BANG),
      :final operand,
    )) {
      expression = operand.unParenthesized;
    } else {
      return null;
    }
  }
  if (expression
      case MethodInvocation(
        :final target?,
        :final methodName,
        :final operator?,
        :final argumentList,
        typeArguments: null,
      )
      when operator.type == TokenType.PERIOD &&
          _gateQuestions.contains(methodName.name) &&
          gate.names(target) &&
          argumentList.arguments.length == 1) {
    final argument = argumentList.arguments.single;
    return (
      question: methodName.name,
      network: argument is SimpleIdentifier ? argument.name : null,
      end: expression.end,
    );
  }
  return null;
}

/// Whether [statement] always leaves: a `return`, a `throw`, a `rethrow`, or a non-empty block whose last statement leaves.
bool _exits(Statement statement) => switch (statement) {
  ReturnStatement() => true,
  ExpressionStatement(expression: ThrowExpression() || RethrowExpression()) =>
    true,
  Block(:final statements) => statements.isNotEmpty && _exits(statements.last),
  _ => false,
};

/// How a file reaches the gate's own library: unprefixed, or through these prefixes.
final class _GateImport {
  final bool unprefixed;
  final Set<String> prefixes;

  _GateImport(this.unprefixed, this.prefixes);

  factory _GateImport.of(CompilationUnit unit, String path) {
    var unprefixed = false;
    final prefixes = <String>{};
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final isGate =
          uri == 'package:p2p/src/domain/p2p_money_gate.dart' ||
          (!uri.contains(':') &&
              Uri.parse('/$path').resolve(uri).path == '/$_gate');
      final shown = directive.combinators.every(
        (combinator) => switch (combinator) {
          ShowCombinator(:final shownNames) => shownNames.any(
            (name) => name.name == 'P2pMoneyGate',
          ),
          HideCombinator(:final hiddenNames) => hiddenNames.every(
            (name) => name.name != 'P2pMoneyGate',
          ),
        },
      );
      if (!isGate || !shown) continue;
      switch (directive.prefix?.name) {
        case null:
          unprefixed = true;
        case final prefix:
          prefixes.add(prefix);
      }
    }
    return _GateImport(unprefixed, prefixes);
  }

  /// Whether [target] is the gate's class as this file imports it.
  bool names(Expression target) => switch (target) {
    SimpleIdentifier(name: 'P2pMoneyGate') => unprefixed,
    PrefixedIdentifier(
      prefix: SimpleIdentifier(:final name),
      identifier: SimpleIdentifier(name: 'P2pMoneyGate'),
    ) =>
      prefixes.contains(name),
    _ => false,
  };
}

/// Each file of [sources] but the gate's that declares or shadows `P2pMoneyGate`, or reads the approval.
///
/// In code, a name `P2pMoneyGate` always followed by `.` is the class used, unprefixed or after an import prefix; anything else (a class, a variable, a getter, a parameter of that name) could stand in for the gate.
/// In the directives, it may be shown or hidden, never be an import prefix.
List<String> _gateOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (path != _gate)
      ...() {
        final unit = parseString(
          content: source,
          throwIfDiagnostics: false,
        ).unit;
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

/// What in the live robot test could give a network other than testnet: the constant `_network` must be `RobosatsNetwork.testnet`, no `.values`, `.byName` or `.fromWire` is used, and `mainnet` stands only in `coordinator.mainnet.onion`, the federation entry's mainnet onion that it compares the testnet one against.
List<String> _liveNetworkOffences(String source) {
  final tokens = _tokensOf(
    parseString(content: source, throwIfDiagnostics: false).unit,
  );
  bool isMainnetOnion(Token t) =>
      t.previous?.lexeme == '.' &&
      t.previous?.previous?.lexeme == 'coordinator' &&
      t.next?.lexeme == '.' &&
      t.next?.next?.lexeme == 'onion';
  return [
    if (!source.contains('const _network = RobosatsNetwork.testnet;'))
      'no const _network = RobosatsNetwork.testnet;',
    for (final t in tokens)
      if ((t.previous?.lexeme == '.' &&
              {'values', 'byName', 'fromWire'}.contains(t.lexeme)) ||
          (t.lexeme == 'mainnet' && !isMainnetOnion(t)))
        '${t.lexeme} at ${t.offset}',
  ];
}

List<Token> _tokensOf(CompilationUnit unit) {
  final tokens = <Token>[];
  Token? token = unit.beginToken;
  while (token != null && !token.isEof) {
    tokens.add(token);
    token = token.next;
  }
  return tokens;
}

/// What a source does with the money members and the gate.
final class _MoneyVisitor extends RecursiveAstVisitor<void> {
  /// Every money member named in code, by name.
  final Set<String> named = {};

  /// The money members named in code other than as the method of a call.
  final Set<String> namedOtherwise = {};

  /// The calls of a money member, in the order of the source.
  final List<MethodInvocation> calls = [];

  /// Whether `P2pMoneyGate` is named in code at all.
  bool namesGate = false;

  /// The simple names that some statement assigns.
  final Set<String> assigned = {};

  /// Every variable and parameter declared, with where.
  final List<({String name, int offset})> declarations = [];

  _MoneyVisitor();

  factory _MoneyVisitor.of(String source) {
    final visitor = _MoneyVisitor();
    parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.accept(visitor);
    return visitor;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (_moneyMembers.contains(name)) {
      named.add(name);
      if (node.parent case final MethodInvocation call
          when identical(call.methodName, node)) {
        calls.add(call);
      } else {
        namedOtherwise.add(name);
      }
    }
    if (name == 'P2pMoneyGate') namesGate = true;
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    for (final component in node.components) {
      if (_moneyMembers.contains(component.lexeme)) {
        named.add(component.lexeme);
        namedOtherwise.add(component.lexeme);
      }
    }
    super.visitSymbolLiteral(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.leftHandSide case SimpleIdentifier(:final name)) {
      assigned.add(name);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    assigned.add(node.name.lexeme);
    super.visitAssignedVariablePattern(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    declarations.add((name: node.name.lexeme, offset: node.name.offset));
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      if (parameter.name case final name?) {
        declarations.add((name: name.lexeme, offset: name.offset));
      }
    }
    super.visitFormalParameterList(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    declarations.add((name: node.name.lexeme, offset: node.name.offset));
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    declarations.add((name: node.name.lexeme, offset: node.name.offset));
    super.visitDeclaredVariablePattern(node);
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
