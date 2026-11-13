import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// What the shell's side of the wallet port, `lib/features/p2p_wallet` of the app (#100), may reach: in this pull request, reads of the wallet and the swap service's quote, nothing else.
///
/// It is an allow-list, pinned literally: every import of the feature, conditional alternatives included, is one of its own files or one of [_shellImports]; every member, constructor and type its code names, and every label of a named argument it passes, is one of [_shellVocabulary], and every name of that list is used, so that nothing is allowed by a stale entry. An `extension`, an `extension type`, a `mixin`, an `extends` or a `with` counts as a name too, none of them listed: through them a member could be reached with an implicit `this`, unseen (the second review's evasion file, a fixture below). A label allows the argument, not its value: the feature passes no `sync:` to the wallet's reader, so `sync: true` fails as any `sync:` does. Any other name of the wallet's code (an order, a signature, a broadcast, a sync, a new address) fails it, whatever object it is reached through.
/// It lives in `features/p2p`, whose tests have the analyzer, and reads the app's files from here, as `trade_money_calls_architecture_test.dart` reads the integration tests: the app has no analyzer among its dependencies. The sources are parsed without resolution: comments and strings are not code.
/// It cannot see a name used bare (a top-level function or variable of an allowed import named without a call or a dot, such as one torn off under an allowed local name), nor what an allowed member does: the allowed members are the quote of `SwapFacade`, the `execute` of the readers the feature calls, and the build and fee read of an unsigned transaction, read in the reviews of this pull request.
/// The pull request that adds the payment extends this rule with a per-file list: the names that commit funds are allowed in its one pay use case file only, and the shared list stays untouched. It is reviewed as money code.
/// Pull request #106 adds `lib/features/p2p_wallet/data/bolt11_decoder_impl.dart`: whichever of #103 and #106 merges second adds that file's import of the `bolt11_decoder` package and its names to this list.
void main() {
  // Tests run with the package directory as working directory.
  const shell = '../../lib/features/p2p_wallet';
  final sources = {
    for (final file in Directory(shell).listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        file.path.substring(shell.length + 1): file.readAsStringSync(),
  };

  test('the scan reads the shell\'s feature', () {
    expect(
      sources.keys,
      containsAll([
        'public/p2p_wallet_facade.dart',
        'data/instant_wallet_repository_impl.dart',
        'data/lightning_swap_quote_repository_impl.dart',
        'p2p_wallet_locator.dart',
      ]),
    );
  });

  test('imports only its own files and the ones listed', () {
    expect(_importOffences(sources), isEmpty);
  });

  test('names only what it is allowed to, and uses all of it', () {
    final used = _vocabularyOf(sources.values);
    expect(
      used.difference(_shellVocabulary),
      isEmpty,
      reason:
          'not allowed: ${(used.difference(_shellVocabulary).toList()..sort()).join(', ')}',
    );
    expect(
      _shellVocabulary.difference(used),
      isEmpty,
      reason:
          'allowed but unused: ${(_shellVocabulary.difference(used).toList()..sort()).join(', ')}',
    );
  });

  test('every import listed is used', () {
    final imported = {
      for (final source in sources.values) ..._urisOf(_parse(source)),
    };
    expect(_shellImports.difference(imported), isEmpty);
  });

  test(
    'its facade is built by its locator and named outside it by the composition only',
    () {
      final lib = {
        for (final file in Directory('../../lib').listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            if (file.readAsStringSync() case final source
                when source.contains('P2pWalletFacade'))
              file.path.substring('../../'.length): _parse(source),
      };
      expect(
        {
          for (final MapEntry(key: path, value: unit) in lib.entries)
            if ((_Vocabulary()..visit(unit)).names.contains('P2pWalletFacade'))
              path,
        },
        // Its own file declares it, which is no use of it.
        {'lib/features/p2p_wallet/p2p_wallet_locator.dart', 'lib/locator.dart'},
      );
      expect(
        {
          for (final MapEntry(key: path, value: unit) in lib.entries)
            if ((_Vocabulary()..visit(unit)).built.contains('P2pWalletFacade'))
              path,
        },
        {'lib/features/p2p_wallet/p2p_wallet_locator.dart'},
      );
    },
  );

  group('the rule bites:', () {
    test('the second review\'s evasion file fails: an extension and sync: true', () {
      const evasion = '''
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
extension Sign on LiquidWalletRepository {
  Future<String> Function({required String pset, required String walletId}) get execute => signPset;
}
Future<String> leak(LiquidWalletRepository liquid, GetWalletsUsecase wallets, String pset) async {
  await wallets.execute(onlyDefaults: true, onlyLiquid: true, sync: true);
  return liquid.execute(pset: pset, walletId: 'w');
}
''';
      // Its imports are both allowed: only its names give it away.
      expect(_importOffences({'data/zz_evasion2.dart': evasion}), isEmpty);
      expect(
        _vocabularyOf([evasion]).difference(_shellVocabulary),
        containsAll(['extension', 'sync']),
      );
    });

    test('each way of reaching a member with an implicit this is seen', () {
      for (final (label, source, name) in [
        ('extension', 'extension E on Object { void f() => g(); }', 'extension'),
        ('extension type', 'extension type T(int i) {}', 'extension type'),
        ('mixin', 'mixin M on Object {}', 'mixin'),
        ('extends', 'class C extends LiquidWalletRepository {}', 'extends'),
        ('with', 'class C with M {}', 'with'),
        ('named argument', 'void f() => g(sync: true);', 'sync'),
      ]) {
        expect(_vocabularyOf([source]), contains(name), reason: label);
      }
      for (final name in [
        'extension',
        'extension type',
        'mixin',
        'extends',
        'with',
        'sync',
      ]) {
        expect(_shellVocabulary, isNot(contains(name)), reason: name);
      }
    });

    test('the reviewer\'s evasion file fails on every line', () {
      const evasion = '''
import 'package:bb_mobile/core/blockchain/domain/repositories/liquid_blockchain_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/sync_wallet_usecase.dart';
import 'package:bb_mobile/features/sp/public/sp_facade.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart'
    if (dart.library.html) 'package:bb_mobile/features/send/send_locator.dart';
import 'package:get_it/get_it.dart';

Future<void> leak(String pset) async {
  await GetIt.I<LiquidBlockchainRepository>().broadcastTransaction(signedPset: pset, isTestnet: false);
  GetIt.I<SyncWalletUsecase>();
  GetIt.I<SpFacade>();
  GetIt.I<LiquidWalletRepository>();
  GetIt.I<SwapFacade>();
}
''';
      expect(_importOffences({'data/zz_evasion.dart': evasion}), [
        'data/zz_evasion.dart imports package:bb_mobile/core/blockchain/domain/repositories/liquid_blockchain_repository.dart',
        'data/zz_evasion.dart imports package:bb_mobile/core/wallet/domain/usecases/sync_wallet_usecase.dart',
        'data/zz_evasion.dart imports package:bb_mobile/features/sp/public/sp_facade.dart',
        'data/zz_evasion.dart imports package:bb_mobile/features/send/send_locator.dart',
      ]);
      expect(
        _vocabularyOf([evasion]).difference(_shellVocabulary),
        containsAll([
          'broadcastTransaction',
          'LiquidBlockchainRepository',
          'SyncWalletUsecase',
          'SpFacade',
          'I',
        ]),
      );
    });

    test('each member that would move funds is outside the list', () {
      for (final name in [
        'createOrder',
        'signPset',
        'signPsbt',
        'savePreparedPayin',
        'replacePreparedPayin',
        'markBroadcastUnknown',
        'markPayinBroadcast',
        'refreshOrder',
        'broadcast',
        'broadcastTransaction',
        'broadcastPsbt',
        'consolidate',
        'generateNewReceiveAddress',
        'getNewAddress',
        'sendPayment',
        'GetReceiveAddressUsecase',
        'SyncWalletUsecase',
        'BroadcastLiquidTransactionUsecase',
        'SpFacade',
        'dynamic',
        'noSuchMethod',
        'apply',
      ]) {
        expect(_shellVocabulary, isNot(contains(name)), reason: name);
        expect(
          _vocabularyOf(['void f() => wallet.$name();']),
          contains(name),
          reason: name,
        );
      }
    });

    test('each way of naming a member, a constructor or a type is seen', () {
      for (final (label, source, name) in [
        ('call', 'void f() => repository.signPset(pset: p);', 'signPset'),
        ('tear-off', 'final f = repository.signPset;', 'signPset'),
        ('cascade', 'void f() { repository..signPset(pset: p); }', 'signPset'),
        (
          'property',
          'final f = facade.isAppUpdateRequired;',
          'isAppUpdateRequired',
        ),
        ('static', 'final f = Broadcast.now;', 'now'),
        ('constructor', 'final f = SyncWalletUsecase(r);', 'SyncWalletUsecase'),
        ('const constructor', 'const f = SomeUsecase();', 'SomeUsecase'),
        ('type argument', 'final f = GetIt.I<SpFacade>();', 'SpFacade'),
        ('type annotation', 'late final SpFacade f;', 'SpFacade'),
        ('dynamic', 'void f(Object o) => (o as dynamic).go();', 'dynamic'),
        ('symbol', 'final s = #signPset;', 'signPset'),
      ]) {
        expect(_vocabularyOf([source]), contains(name), reason: label);
      }
    });

    test('a comment or a string is no use', () {
      expect(
        _vocabularyOf([
          "// createOrder, signPset\n/// [SwapFacade.createOrder]\nfinal s = 'signPset broadcast';",
        ]),
        isEmpty,
      );
    });

    test('an import that is not listed fails, conditional ones included', () {
      for (final directive in [
        "import 'package:bb_mobile/features/swap/domain/usecases/create_order_swap_usecase.dart';",
        "import 'package:bb_mobile/features/send/public/send_facade.dart';",
        "export 'package:bb_mobile/features/pay/domain/sign_pay_payin_usecase.dart';",
        "import '../../swap/domain/swap_failure.dart';",
        "import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';",
        "import 'package:p2p/p2p.dart' if (dart.library.io) 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';",
        "part 'x.g.dart';",
      ]) {
        expect(
          _importOffences({'domain/x.dart': directive}),
          hasLength(1),
          reason: directive,
        );
      }
      for (final directive in [
        "import 'package:bb_mobile/features/swap/public/swap_facade.dart';",
        "import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';",
        "import 'package:p2p/p2p.dart';",
      ]) {
        expect(
          _importOffences({'domain/x.dart': directive}),
          isEmpty,
          reason: directive,
        );
      }
    });
  });
}

/// What the feature imports from outside itself: the Swap feature's facade, the P2P feature's contract, and the wallet readers of `lib/core` that it calls, with the types they throw or return.
const _shellImports = {
  'dart:async',
  'package:bb_mobile/core/fees/domain/fees_entity.dart',
  'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart',
  'package:bb_mobile/core/wallet/domain/consolidation_required_exception.dart',
  'package:bb_mobile/core/wallet/domain/entities/wallet.dart',
  'package:bb_mobile/core/wallet/domain/insufficient_funds_exception.dart',
  'package:bb_mobile/core/wallet/domain/no_spendable_utxo_exception.dart',
  'package:bb_mobile/core/wallet/domain/usecases/get_address_at_index_usecase.dart',
  'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart',
  'package:bb_mobile/core/wallet/domain/usecases/watch_finished_wallet_syncs_usecase.dart',
  'package:bb_mobile/core/wallet/domain/wallet_failure.dart',
  'package:bb_mobile/features/swap/public/swap_facade.dart',
  'package:get_it/get_it.dart',
  'package:meta/meta.dart',
  'package:p2p/p2p.dart',
};

/// Every member, constructor and type the feature's code names, its own included.
const _shellVocabulary = {
  // Dart's own types and `dart:async`, and `GetIt` of the locator.
  'BigInt',
  'bool',
  'DateTime',
  'Duration',
  'Future',
  'GetIt',
  'List',
  'Object',
  'Stream',
  'StreamController',
  'StreamSubscription',
  'String',
  'unawaited',
  'void',
  // The port's contract and its value types (`package:p2p`).
  'CheckedBolt11Invoice',
  'Err',
  'Ok',
  'P2pWalletFacade',
  'P2pWalletInvoiceExpired',
  'P2pWalletNeedsConsolidation',
  'P2pWalletNoInstantWallet',
  'P2pWalletNotEnoughBalance',
  'P2pWalletOutsideServiceLimits',
  'P2pWalletOverMaximum',
  'P2pWalletPort',
  'P2pWalletQuote',
  'P2pWalletRefusal',
  'P2pWalletServiceBusy',
  'P2pWalletServiceRefused',
  'P2pWalletServiceUnreachable',
  'P2pWalletUnavailable',
  'P2pWalletUnderMinimum',
  'P2pWalletWrongNetwork',
  'Result',
  'RobosatsNetwork',
  'Sats',
  // Of the Swap feature's facade: its quote, the networks of a route, the amounts of a quote, and every failure it returns (mapped one by one).
  'getQuote',
  'inAmountSat',
  'lightning',
  'liquid',
  'outAmountSat',
  'SwapAmountOutOfBoundsFailure',
  'SwapCreationUnknownFailure',
  'SwapFacade',
  'SwapFailure',
  'SwapInvalidStateFailure',
  'SwapNetworkFailure',
  'SwapNoPaymentOptionFailure',
  'SwapOrderExpiredFailure',
  'SwapOrderMismatchFailure',
  'SwapOrderNotFoundFailure',
  'SwapPriceUnavailableFailure',
  'SwapProviderFailure',
  'SwapRateLimitedFailure',
  'SwapStorageFailure',
  'SwapTimeoutFailure',
  'SwapUnexpectedFailure',
  'SwapValidationFailure',
  // Of the wallet's readers: the default Liquid wallet and its fields, the address at an index, the build and fee read of an unsigned transaction at a fee rate, and the exceptions and failures they give. `execute` is below, with the members.
  'address',
  'balanceSat',
  'buildPset',
  'ConsolidationRequiredException',
  'GetAddressAtIndexUsecase',
  'getPsetSizeAndAbsoluteFees',
  'GetWalletsUsecase',
  'id',
  'InsufficientFundsException',
  'isDefault',
  'isHardwareWallet',
  'isLiquid',
  'isTestnet',
  'LiquidWalletRepository',
  'NoSpendableUtxoException',
  'NoWalletsFoundFailure',
  'RelativeFee',
  'signsLocally',
  'Wallet',
  'WalletFailure',
  'WatchFinishedWalletSyncsUsecase',
  // The feature's own classes.
  'InstantWallet',
  'InstantWalletRepository',
  'InstantWalletRepositoryImpl',
  'LightningSwapQuote',
  'LightningSwapQuoteRepository',
  'LightningSwapQuoteRepositoryImpl',
  'QuoteInvoicePaymentUsecase',
  'WatchInstantBalanceUsecase',
  // Members: the feature's own (`read`, `watchSyncs`, `estimateNetworkFee`, `quote`, `refusalFor`…), the readers' `execute`, the locator's registrations, and those of Dart's numbers, collections, streams and dates.
  '_instant',
  '_now',
  '_sats',
  '_short',
  '_wait',
  'add',
  'amount',
  'balance',
  'cancel',
  'cast',
  'close',
  'estimateNetworkFee',
  'execute',
  'firstOrNull',
  'from',
  'fromInt',
  'isExpiredAt',
  'isNegative',
  'listen',
  'locator',
  'mainnet',
  'map',
  'network',
  'now',
  'one',
  'payin',
  'quote',
  'read',
  'refusalFor',
  'refusalOf',
  'refuse',
  'registerFactory',
  'registerLazySingleton',
  'start',
  'stream',
  'testnet',
  'toInt',
  'value',
  'watchSyncs',
  'where',
};

CompilationUnit _parse(String source) =>
    parseString(content: source, throwIfDiagnostics: false).unit;

/// The URIs of [unit]'s imports and exports, conditional alternatives included.
List<String> _urisOf(CompilationUnit unit) => [
  for (final directive in unit.directives)
    if (directive is NamespaceDirective) ...[
      ?directive.uri.stringValue,
      for (final configuration in directive.configurations)
        ?configuration.uri.stringValue,
    ],
];

/// Each import or export of [sources] that is neither the feature's own nor listed, and each `part`.
List<String> _importOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries) ...[
    for (final directive in _parse(source).directives)
      if (directive is PartDirective || directive is PartOfDirective)
        '$path has a part',
    for (final uri in _urisOf(_parse(source)))
      if (!uri.startsWith('package:bb_mobile/features/p2p_wallet/') &&
          !_shellImports.contains(uri))
        '$path imports $uri',
  ],
];

/// Every name [sources] give in code to a member, a constructor or a type.
Set<String> _vocabularyOf(Iterable<String> sources) => {
  for (final source in sources) ...(_Vocabulary()..visit(_parse(source))).names,
};

/// The names a unit gives to a member (called, torn off or read, through any object), a constructor, a type or a symbol, and the classes it builds.
final class _Vocabulary extends RecursiveAstVisitor<void> {
  final Set<String> names = {};
  final Set<String> built = {};

  void visit(CompilationUnit unit) => unit.accept(this);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    // Unresolved, `Foo(...)` reads as a call of `Foo`.
    if (node.target == null &&
        node.methodName.name.startsWith(RegExp('[A-Z]'))) {
      built.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    built.add(node.constructorName.type.name.lexeme);
    if (node.constructorName.name case final name?) names.add(name.name);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    names.add(node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    names.add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    for (final component in node.components) {
      names.add(component.lexeme);
    }
    super.visitSymbolLiteral(node);
  }

  /// The label of a named argument, such as `sync:`: allowing a reader allows only the arguments listed.
  @override
  void visitNamedExpression(NamedExpression node) {
    names.add(node.name.label.name);
    super.visitNamedExpression(node);
  }

  /// An extension, through which a member is reached with an implicit `this` that the rule would not see.
  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    names.add('extension');
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    names.add('extension type');
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    names.add('mixin');
    super.visitMixinDeclaration(node);
  }

  /// A superclass, whose members a subclass reaches with an implicit `this`.
  @override
  void visitExtendsClause(ExtendsClause node) {
    names.add('extends');
    super.visitExtendsClause(node);
  }

  @override
  void visitWithClause(WithClause node) {
    names.add('with');
    super.visitWithClause(node);
  }

  /// A `[name]` in a doc comment names it without using it.
  @override
  void visitCommentReference(CommentReference node) {}
}
