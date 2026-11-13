import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Where the money members of the coordinator client may be named in `features/p2p/lib`, and that automated tests never move money on a real coordinator (#83, design note `docs/design/phase-2-taking-an-order.md` § 3.7).
///
/// The members are listed by name before they exist (#84, #89), so that the rule guards the pull requests that add them.
/// Only the trade use cases, files `lib/src/domain/usecases/trade/<name>_usecase.dart` that are not a `part`, may name one, so that every call that locks, moves or releases funds is in one reviewed place.
/// The sources are read as text, parsed without resolution: a name is a use wherever it stands in code (a call, a tear-off, a cascade, an import prefix, an implicit `this`, a `dynamic` call, a `Symbol`), and comments, doc comments and strings are not code.
/// A declaration of a member with one of these names is not a use (a fake of the client could declare them), but a named argument or a record field of that name is: in the feature, these names are kept for the client's members.
/// It cannot see what a trade use case hands out (a tear-off, a wrapper), code outside `features/p2p/lib`, a money member added to the package under a name this list does not have yet, nor money moved by anything but these members (a payable invoice shown from `fetchOrder`, and the payment of `P2pWalletPort.payInvoice` behind « Pay with this wallet », which is not a coordinator member and is reviewed as money code when #100 adds it): those are for the money review (design note § 4.6).
/// An extension on `CoordinatorClient`, which could rename a member, and a raw `CoordinatorTransport.send` are refused anywhere in the feature by `robot_bindings_architecture_test.dart`.
void main() {
  // Tests run with the package directory as working directory.
  final sources = {
    for (final path in _dartFilesUnder('lib'))
      path: File(path).readAsStringSync(),
  };

  test('the scan reads every Dart file of lib/', () {
    expect(
      sources.keys,
      containsAll([
        'lib/src/domain/usecases/fetch_robot_usecase.dart',
        'lib/generated/l10n/p2p_localizations.dart',
      ]),
    );
  });

  test('the money members are these seven, written out', () {
    // A member removed from the list would stop being watched without a sign: the list is pinned here, not looped over itself.
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
    'only the trade use cases name a money member of the coordinator client',
    () {
      expect(_offences(sources), isEmpty);
    },
  );

  group('the rule bites:', () {
    const tradeUseCase =
        'lib/src/domain/usecases/trade/take_order_usecase.dart';
    const cubit = 'lib/src/presentation/trade_cubit.dart';
    const take =
        'Future<void> take(RobosatsNetwork network) => client.takeOrder(coordinator, network, orderId: 1);';

    List<String> offencesOf(String path, String source) =>
        _offences({path: source});

    test('a trade use case may call a money member', () {
      expect(offencesOf(tradeUseCase, take), isEmpty);
      expect(
        offencesOf(
          'lib/src/domain/usecases/trade/cancel_trade_usecase.dart',
          'Future<void> cancel(RobosatsNetwork network) => client.cancelOrder(coordinator, network, orderId: 1);',
        ),
        isEmpty,
      );
    });

    test('a use from a file that is not a trade use case fails', () {
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
        expect(offencesOf(path, take), [
          '$path names takeOrder but is not a trade use case',
        ], reason: path);
      }
    });

    test('each of the seven members is watched', () {
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
          '$cubit names $member but is not a trade use case',
        ], reason: member);
      }
    });

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
          '$cubit names takeOrder but is not a trade use case',
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
        offencesOf(
          tradeUseCase,
          "part of '../../../presentation/trade_cubit.dart';\n$take",
        ),
        ['$tradeUseCase is a part of another library'],
      );
    });
  });

  group('automated tests never move money on a real coordinator:', () {
    // `package:p2p/testing.dart` hands the coordinator client to the integration tests: they name no money member on any network, and their robots stay on testnet (design note § 5).
    const folder = '../../integration_test';

    test('the integration tests name no money member', () {
      final files = _dartFilesUnder(folder);
      expect(files, contains('$folder/p2p_robot_tor_test.dart'));
      expect({
        for (final path in files)
          if (_MoneyNames.of(File(path).readAsStringSync()).named.isNotEmpty)
            path,
      }, isEmpty);
    });

    test(
      'the live robot test gives no network value but RobosatsNetwork.testnet',
      () {
        expect(
          _liveNetworkOffences(
            File('$folder/p2p_robot_tor_test.dart').readAsStringSync(),
          ),
          isEmpty,
        );
      },
    );

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

/// The members of `CoordinatorClient` that lock, move or release funds, or that act on a trade whose bond or escrow is locked (design note § 3.1).
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

/// Whether the file at [path] is a trade use case: a file `lib/src/domain/usecases/trade/<name>_usecase.dart`, one level deep, as the Garage's screens are grouped under `lib/src/ui/garage/`.
bool _isTradeUseCase(String path) => RegExp(
  r'^lib/src/domain/usecases/trade/[a-z0-9_]+_usecase\.dart$',
).hasMatch(path);

/// Each breach of the rule in [sources], by path.
List<String> _offences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    ...() {
      final unit = parseString(content: source, throwIfDiagnostics: false).unit;
      final names = _MoneyNames();
      unit.accept(names);
      if (_isTradeUseCase(path)) {
        return [
          if (unit.directives.any((d) => d is PartOfDirective))
            '$path is a part of another library',
        ];
      }
      return [
        for (final member in names.named)
          '$path names $member but is not a trade use case',
      ];
    }(),
];

/// What in the live robot test could give a network other than testnet: the constant `_network` must be `RobosatsNetwork.testnet`, no `.values`, `.byName` or `.fromWire` is used, and `mainnet` stands only in `coordinator.mainnet.onion`, the federation entry's mainnet onion that it compares the testnet one against.
List<String> _liveNetworkOffences(String source) {
  final tokens = <Token>[];
  Token? token = parseString(
    content: source,
    throwIfDiagnostics: false,
  ).unit.beginToken;
  while (token != null && !token.isEof) {
    tokens.add(token);
    token = token.next;
  }
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

/// The money members a source names in code.
final class _MoneyNames extends RecursiveAstVisitor<void> {
  final Set<String> named = {};

  _MoneyNames();

  factory _MoneyNames.of(String source) {
    final names = _MoneyNames();
    parseString(content: source, throwIfDiagnostics: false).unit.accept(names);
    return names;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_moneyMembers.contains(node.name)) named.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    for (final component in node.components) {
      if (_moneyMembers.contains(component.lexeme)) {
        named.add(component.lexeme);
      }
    }
    super.visitSymbolLiteral(node);
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
