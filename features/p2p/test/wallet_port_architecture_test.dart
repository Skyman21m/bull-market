import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// Where the wallet's port may be reached in `features/p2p/lib`, and that the feature depends on neither the app nor the wallet's core (#100, design note § 3.9).
///
/// The port is the shell's Instant Payments wallet, lent to the feature: its balance, the swap service's quote, and the payment (`payInvoice`, which moves money and triggers a signature, with `watchPayment` and `findPayment`), reviewed as money code.
/// Only the trade use cases, files `lib/src/domain/usecases/trade/<name>_usecase.dart` that are not a `part`, may name one of its members, as only they may name the coordinator's money members (`trade_money_calls_architecture_test.dart`), so that what reads the wallet and what pays from it sit in one reviewed place. None names them yet: the pull request of the bond's panel (#100, W4) adds the one use case that pays.
/// The port's type may be named there too, and where the feature declares, exports, receives and registers it, and in its testing seam; nowhere else, so that no cubit or screen takes it from the locator.
/// The only invoice the port takes, `CheckedBolt11Invoice`, is built by `CheckedBolt11Invoice.of`, which only its own file, the trade's `wallet_payment.dart` (where `walletPaymentFor` builds it when it offers « Pay with this wallet », the one source of the type) and the testing seam's helper may call. No file may declare an alias of the type, through which `of` could be reached under another name.
/// The sources are read as text and parsed without resolution, as in `trade_money_calls_architecture_test.dart`: a name is a use wherever it stands in code, comments and strings are not code, and a declaration of a member with a watched name is no use (the fake of `testing.dart` declares them).
/// It cannot see what a trade use case hands out (a tear-off, a wrapper), a member added to the port under a name this list does not have yet (the pull request that adds one adds it here), nor code outside `features/p2p/lib`: the shell's side has its own test, `features/p2p/test/wallet_shell_architecture_test.dart`.
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
        'lib/public/p2p_wallet_port.dart',
        'lib/src/domain/checked_bolt11_invoice.dart',
        'lib/testing.dart',
      ]),
    );
  });

  test('the members of the port are these five, written out', () {
    // A member removed from the list would stop being watched without a sign: the list is pinned here, not looped over itself.
    expect(_portMembers, {
      'instantBalance',
      'quote',
      'payInvoice',
      'watchPayment',
      'findPayment',
    });
  });

  test('no file names a member of the payment yet', () {
    // The bond's panel (#100, W4) adds the one trade use case that pays; until then nothing in the feature may.
    expect([
      for (final MapEntry(key: path, value: source) in sources.entries)
        if ((_Names(_paymentMembers)..visit(_parse(source))).named.isNotEmpty)
          path,
    ], isEmpty);
  });

  test('only the trade use cases name a member of the port', () {
    expect(_memberOffences(sources), isEmpty);
  });

  test(
    'only the trade use cases and the feature\'s own wiring name the port',
    () {
      expect(_typeOffences(sources), isEmpty);
    },
  );

  test('the feature imports nothing of the app or of the wallet\'s core', () {
    expect(_importOffences(sources), isEmpty);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final package in _forbiddenPackages) {
      expect(
        RegExp('^\\s+$package\\s*:', multiLine: true).hasMatch(pubspec),
        isFalse,
        reason: package,
      );
    }
  });

  group('who builds a checked invoice:', () {
    test(
      'the files that may call CheckedBolt11Invoice.of are these three, written out',
      () {
        expect(_invoiceBuilders, {
          'lib/src/domain/checked_bolt11_invoice.dart',
          'lib/src/domain/trade/wallet_payment.dart',
          'lib/testing.dart',
        });
      },
    );

    test('walletPaymentFor calls it, once', () {
      final finder = _InvoiceBuilds();
      _parse(
        sources['lib/src/domain/trade/wallet_payment.dart'] ?? '',
      ).accept(finder);
      expect(finder.found, ['calls CheckedBolt11Invoice.of']);
    });

    test('only they call it', () {
      expect(_invoiceOffences(sources), isEmpty);
    });

    test('the rule bites', () {
      const cubit = 'lib/src/presentation/trade_cubit.dart';
      for (final (label, source) in [
        (
          'call',
          "final i = CheckedBolt11Invoice.of(bolt11: s, amount: a, network: n, expiresAt: e, now: t);",
        ),
        ('tear-off', 'final f = CheckedBolt11Invoice.of;'),
        (
          'import prefix',
          "final i = p2p.CheckedBolt11Invoice.of(bolt11: s, amount: a, network: n, expiresAt: e, now: t);",
        ),
        ('prefixed tear-off', 'final f = p2p.CheckedBolt11Invoice.of;'),
        ('alias', 'typedef Invoice = CheckedBolt11Invoice;'),
        (
          'alias of a function type',
          'typedef Make = CheckedBolt11Invoice? Function();',
        ),
      ]) {
        expect(_invoiceOffences({cubit: source}), isNotEmpty, reason: label);
      }
      // A trade use case is no exception: the state machine builds the invoice, the use cases receive it.
      expect(
        _invoiceOffences({
          'lib/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart':
              'final f = CheckedBolt11Invoice.of;',
        }),
        isNotEmpty,
      );
      for (final path in _invoiceBuilders) {
        expect(
          _invoiceOffences({path: 'final f = CheckedBolt11Invoice.of;'}),
          isEmpty,
          reason: path,
        );
      }
      // Naming the type, or another `of`, builds nothing.
      expect(
        _invoiceOffences({
          cubit:
              "/// [CheckedBolt11Invoice.of]\nvoid f(CheckedBolt11Invoice i, BuildContext c) { Theme.of(c); final s = 'CheckedBolt11Invoice.of'; }",
        }),
        isEmpty,
      );
    });
  });

  group('the rule bites:', () {
    const tradeUseCase =
        'lib/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
    const cubit = 'lib/src/presentation/trade_cubit.dart';
    const quote =
        'Future<void> ask(P2pWalletPort wallet, CheckedBolt11Invoice invoice) => wallet.quote(invoice);';

    test('a trade use case may name the port and its members', () {
      expect(_memberOffences({tradeUseCase: quote}), isEmpty);
      expect(_typeOffences({tradeUseCase: quote}), isEmpty);
      expect(
        _memberOffences({
          'lib/src/domain/usecases/trade/watch_trade_usecase.dart':
              'Stream<void> f(P2pWalletPort wallet) => wallet.instantBalance(network);',
        }),
        isEmpty,
      );
      expect(
        _memberOffences({
          tradeUseCase:
              'Future<void> pay(P2pWalletPort wallet) async { await wallet.payInvoice(invoice, accepted: quote); wallet.watchPayment(payment); await wallet.findPayment(hash); }',
        }),
        isEmpty,
      );
    });

    test('a use from a file that is not a trade use case fails', () {
      for (final path in [
        cubit,
        'lib/src/ui/trade_screen.dart',
        'lib/src/domain/usecases/pay_bond_from_wallet_usecase.dart',
        'lib/src/domain/usecases/trade/pay_bond.dart',
        'lib/src/domain/usecases/trade/nested/pay_bond_usecase.dart',
        'lib/src/data/trade_repository_impl.dart',
        'lib/public/p2p_facade.dart',
        'lib/src/p2p_locator.dart',
        'lib/testing.dart',
      ]) {
        expect(_memberOffences({path: quote}), [
          '$path names quote but is not a trade use case',
        ], reason: path);
      }
    });

    test('naming the port outside the allowed files fails', () {
      expect(_typeOffences({cubit: quote}), ['$cubit names P2pWalletPort']);
      expect(
        _typeOffences({
          'lib/src/ui/trade_screen.dart':
              'final wallet = GetIt.instance<P2pWalletPort>();',
        }),
        ['lib/src/ui/trade_screen.dart names P2pWalletPort'],
      );
      for (final path in [
        'lib/public/p2p_wallet_port.dart',
        'lib/public/p2p_facade.dart',
        'lib/src/p2p_locator.dart',
        'lib/p2p.dart',
        'lib/testing.dart',
      ]) {
        expect(_typeOffences({path: quote}), isEmpty, reason: path);
      }
    });

    test('each way of reaching a member by its name is a use', () {
      for (final (label, source) in [
        ('call', 'void f() => wallet.instantBalance(network);'),
        ('tear-off', 'final f = wallet.quote;'),
        ('cascade', 'void f() { wallet..quote(invoice); }'),
        (
          'extension with an implicit this',
          'extension Ask on P2pWalletPort { Future<void> ask() => quote(invoice); }',
        ),
        ('dynamic call', 'void f() => (wallet as dynamic).quote(invoice);'),
        ('symbol', 'final s = #quote;'),
        ('interpolation', r'''final s = '${wallet.instantBalance}';'''),
        ('pay', 'void f() => wallet.payInvoice(invoice, accepted: quote);'),
        ('pay torn off', 'final f = wallet.payInvoice;'),
        ('watch', 'void f() => wallet.watchPayment(payment);'),
        ('find', 'void f() => wallet.findPayment(hash);'),
        ('find in a cascade', 'void f() { wallet..findPayment(hash); }'),
        ('pay as a symbol', 'final s = #payInvoice;'),
      ]) {
        expect(_memberOffences({cubit: source}), isNotEmpty, reason: label);
      }
    });

    test('a comment, a doc comment, a string or a declaration is no use', () {
      expect(
        _memberOffences({
          cubit: '''
// The trade use case asks wallet.quote.
/// See [P2pWalletPort.quote] and [P2pWalletPort].
final class TradeCubit {
  final String label = 'quote instantBalance P2pWalletPort';
}
''',
          'lib/testing.dart':
              'final class FakeWallet { Future<void> quote(Object invoice) async {} Stream<void> instantBalance(Object network) => const Stream.empty(); }',
        }),
        isEmpty,
      );
      expect(
        _typeOffences({
          cubit: "/// [P2pWalletPort]\nfinal s = 'P2pWalletPort';",
        }),
        isEmpty,
      );
    });

    test('a trade use case may not be a part of another library', () {
      expect(
        _memberOffences({
          tradeUseCase:
              "part of '../../../presentation/trade_cubit.dart';\n$quote",
        }),
        ['$tradeUseCase is a part of another library'],
      );
    });

    test('an import of the app or of the wallet\'s core fails', () {
      for (final directive in [
        "import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';",
        "import 'package:bb_mobile/features/p2p_wallet/public/p2p_wallet_facade.dart';",
        "export 'package:bb_mobile/locator.dart';",
        "import 'package:bull_sdk/lwk.dart' as lwk;",
      ]) {
        expect(
          _importOffences({cubit: directive}),
          hasLength(1),
          reason: directive,
        );
      }
      expect(
        _importOffences({
          cubit: "import 'package:primitives/primitives.dart';",
        }),
        isEmpty,
      );
    });
  });
}

/// The files of `lib/` that may call `CheckedBolt11Invoice.of`: its own, the trade's offer of a wallet payment (its one source), and the testing seam's helper.
const _invoiceBuilders = {
  'lib/src/domain/checked_bolt11_invoice.dart',
  'lib/src/domain/trade/wallet_payment.dart',
  'lib/testing.dart',
};

/// Each file of [sources] that calls or tears off `CheckedBolt11Invoice.of` and may not, or that declares an alias naming the type (through which `of` could be reached under another name).
List<String> _invoiceOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (!_invoiceBuilders.contains(path))
      ...() {
        final finder = _InvoiceBuilds();
        _parse(source).accept(finder);
        return [for (final how in finder.found) '$path $how'];
      }(),
];

/// The uses of `CheckedBolt11Invoice.of`, and the aliases of the type, in a source.
final class _InvoiceBuilds extends RecursiveAstVisitor<void> {
  final List<String> found = [];

  bool _isInvoice(Expression? target) =>
      target != null &&
      (target.toSource() == 'CheckedBolt11Invoice' ||
          target.toSource().endsWith('.CheckedBolt11Invoice'));

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'of' && _isInvoice(node.target)) {
      found.add('calls CheckedBolt11Invoice.of');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'of' &&
        node.prefix.name == 'CheckedBolt11Invoice') {
      found.add('names CheckedBolt11Invoice.of');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'of' && _isInvoice(node.target)) {
      found.add('names CheckedBolt11Invoice.of');
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    if (node.type.toSource().contains('CheckedBolt11Invoice')) {
      found.add('aliases CheckedBolt11Invoice');
    }
    super.visitGenericTypeAlias(node);
  }

  /// A `[name]` in a doc comment names it without using it.
  @override
  void visitCommentReference(CommentReference node) {}
}

/// The members of `P2pWalletPort`: distinct names, since a name is a use wherever it stands (`watch` and `find` would match unrelated code, `context.watch` and drift's `watch` among them).
const _portMembers = {
  'instantBalance',
  'quote',
  'payInvoice',
  'watchPayment',
  'findPayment',
};

/// The members of the payment, which no file names until the bond's panel (#100, W4) adds its trade use case.
const _paymentMembers = {'payInvoice', 'watchPayment', 'findPayment'};

/// The files that may name the port's type besides the trade use cases: its declaration, the library that exports it, the setup that receives it, the locator that registers it, and the testing seam that fakes it.
const _typeAllowed = {
  'lib/public/p2p_wallet_port.dart',
  'lib/p2p.dart',
  'lib/public/p2p_facade.dart',
  'lib/src/p2p_locator.dart',
  'lib/testing.dart',
};

/// The app and the wallet's core: the feature gets the wallet through the port only.
const _forbiddenPackages = ['bb_mobile', 'bull_sdk'];

/// Whether the file at [path] is a trade use case, as `trade_money_calls_architecture_test.dart` says it.
bool _isTradeUseCase(String path) => RegExp(
  r'^lib/src/domain/usecases/trade/[a-z0-9_]+_usecase\.dart$',
).hasMatch(path);

CompilationUnit _parse(String source) =>
    parseString(content: source, throwIfDiagnostics: false).unit;

/// Each use of a member of the port outside a trade use case, and each trade use case that is a part.
List<String> _memberOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    ...() {
      final unit = _parse(source);
      if (_isTradeUseCase(path)) {
        return [
          if (unit.directives.any((d) => d is PartOfDirective))
            '$path is a part of another library',
        ];
      }
      final names = _Names(_portMembers);
      unit.accept(names);
      return [
        for (final member in names.named)
          '$path names $member but is not a trade use case',
      ];
    }(),
];

/// Each file that names the port's type and may not.
List<String> _typeOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if (!_isTradeUseCase(path) && !_typeAllowed.contains(path))
      if ((_Names({'P2pWalletPort'})..visit(_parse(source))).named.isNotEmpty)
        '$path names P2pWalletPort',
];

/// Each import or export of the app or of the wallet's core.
List<String> _importOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    for (final directive in _parse(source).directives)
      if (directive is NamespaceDirective)
        if (directive.uri.stringValue case final uri?)
          if (_forbiddenPackages.any(
            (package) => uri.startsWith('package:$package/'),
          ))
            '$path imports $uri',
];

/// The watched names a source names in code.
final class _Names extends RecursiveAstVisitor<void> {
  final Set<String> watched;
  final Set<String> named = {};

  _Names(this.watched);

  void visit(CompilationUnit unit) => unit.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (watched.contains(node.name)) named.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (watched.contains(node.name.lexeme)) named.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    for (final component in node.components) {
      if (watched.contains(component.lexeme)) named.add(component.lexeme);
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
