import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:test/test.dart';

/// What the shell's side of the wallet port, `lib/features/p2p_wallet` of the app (#100), may reach: reads of the wallet, the swap service's quote and, in one file only, the payment.
///
/// It is an allow-list, pinned literally: every import of the feature, conditional alternatives included, is one of its own files, one of [_shellImports], or one of the imports [_perFileImports] gives that file alone; every member, constructor and type its code names, every label of a named argument it passes and every field a pattern of it reads, is one of [_shellVocabulary] or of the names [_perFile] gives that file alone; and every name of these lists is used, each per-file name in its own file, so that nothing is allowed by a stale entry.
/// The names that commit funds or trigger a signature, [_fundNames] (creating an order, signing, saving a signed payin, marking it, broadcasting, and the receive address sent as the refund destination), are allowed in the pay use case's file only (`domain/usecases/pay_checked_invoice_usecase.dart`, reviewed as money code and key material): no other file of the feature names any of them, whatever object it reaches them through. The reads of the payment (the wallet's records of its swap orders, its decoder of invoices) have per-file lists of their own; the shared list holds no name of the wallet's code that the quote of #103 did not already need. An `extension`, an `extension type`, a `mixin`, an `extends` or a `with` counts as a name too, none of them listed: through them a member could be reached with an implicit `this`, unseen (the second review's evasion file, a fixture below). A label allows the argument, not its value: the feature passes no `sync:` to the wallet's reader, so `sync: true` fails as any `sync:` does. Any other name of the wallet's code (an order, a signature, a broadcast, a sync, a new address) fails it, whatever object it is reached through.
/// It lives in `features/p2p`, whose tests have the analyzer, and reads the app's files from here, as `trade_money_calls_architecture_test.dart` reads the integration tests: the app has no analyzer among its dependencies. The sources are parsed without resolution: comments and strings are not code.
/// It cannot see a name used bare (a top-level function or variable of an allowed import named without a call or a dot, such as one torn off under an allowed local name), nor what an allowed member does: the allowed members are the quote of `SwapFacade`, the `execute` of the readers the feature calls, and the build and fee read of an unsigned transaction, read in the reviews of this pull request.
/// A pattern's field counts as a name too (`case LiquidWalletRepository(signPset: final sign)` tears a method off as surely as `.signPset` does).
/// The BOLT11 decoder's adapter of #86 is not part of this feature: it gets a shell folder of its own (`lib/features/p2p_bolt11/`), so this list never names the decoder package.
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
    expect(_vocabularyOffences(sources), isEmpty);
    final used = _vocabularyOf(sources.values);
    expect(
      _shellVocabulary.difference(used),
      isEmpty,
      reason:
          'allowed but unused: ${(_shellVocabulary.difference(used).toList()..sort()).join(', ')}',
    );
    for (final MapEntry(key: path, value: names) in _perFile.entries) {
      final own = _vocabularyOf([sources[path] ?? '']);
      expect(
        names.difference(own),
        isEmpty,
        reason:
            '$path is allowed but does not use: ${(names.difference(own).toList()..sort()).join(', ')}',
      );
    }
  });

  group('the names that commit funds', () {
    const pay = 'domain/usecases/pay_checked_invoice_usecase.dart';

    test('are these, written out, and the pay use case\'s alone', () {
      // A name removed from the list would be allowed nowhere and fail above; a name added to the shared list or another file's would be allowed there: both are pinned here.
      expect(_fundNames, {
        'createOrder',
        'savePreparedPayin',
        'markBroadcastUnknown',
        'markPayinBroadcast',
        'signPset',
        'BroadcastLiquidTransactionUsecase',
        'GetReceiveAddressUsecase',
      });
      expect(_perFile[pay], containsAll(_fundNames));
      expect(_shellVocabulary.intersection(_fundNames), isEmpty);
      for (final MapEntry(key: path, value: names) in _perFile.entries) {
        if (path != pay) {
          expect(names.intersection(_fundNames), isEmpty, reason: path);
        }
      }
      expect(_perFileImports[pay], {
        'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart',
        'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart',
      });
    });

    test('no other file of the feature names any of them', () {
      expect(sources.keys, contains(pay));
      for (final MapEntry(key: path, value: source) in sources.entries) {
        if (path == pay) continue;
        expect(
          _vocabularyOf([source]).intersection(_fundNames),
          isEmpty,
          reason: path,
        );
      }
    });

    test(
      'a per-file name is not shared, so that it is allowed in its file only',
      () {
        for (final MapEntry(key: path, value: names) in _perFile.entries) {
          expect(names.intersection(_shellVocabulary), isEmpty, reason: path);
          expect(sources.keys, contains(path));
        }
        for (final path in _perFileImports.keys) {
          expect(_perFile.keys, contains(path));
        }
      },
    );

    test(
      'the security review\'s file that quotes and pays through the locator fails (#116)',
      () {
        const evasion = '''
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/pay_checked_invoice_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';

class FindAndPay {
  final GetIt locator;

  FindAndPay(this.locator);

  Future<void> start(CheckedBolt11Invoice invoice) async {
    final quoted = await locator<QuoteInvoicePaymentUsecase>().execute(invoice);
    if (quoted case Ok(:final value)) {
      await locator<PayCheckedInvoiceUsecase>().execute(
        invoice,
        accepted: value,
      );
    }
  }
}
''';
        const path = 'domain/usecases/find_and_pay_probe.dart';
        expect(_importOffences({path: evasion}), [
          '$path imports package:get_it/get_it.dart',
        ]);
        expect(
          _vocabularyOffences({path: evasion}).join(),
          allOf(
            contains('PayCheckedInvoiceUsecase'),
            contains('QuoteInvoicePaymentUsecase'),
            contains('GetIt'),
          ),
        );
        // Through the facade's type or the port's member, too.
        expect(
          _vocabularyOffences({
            path:
                'Future<void> f(P2pWalletPort port, CheckedBolt11Invoice i, P2pWalletQuote q, Object o) async { await port.payInvoice(i, accepted: q); final P2pWalletFacade f = o as P2pWalletFacade; }',
          }).join(),
          allOf(contains('payInvoice'), contains('P2pWalletFacade')),
        );
        // In the locator's own file, the composition names them, and nothing else may.
        expect(
          _vocabularyOffences({'p2p_wallet_locator.dart': evasion}).join(),
          isNot(contains('PayCheckedInvoiceUsecase')),
        );
      },
    );

    test('a file that reaches the signature by another way fails', () {
      // The third review's probe: from another file of the feature, the wallet's signer through the locator, a pattern, an extension, a cascade or a symbol.
      const evasion = '''
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:get_it/get_it.dart';
Future<void> leak(String pset, SwapFacade swaps) async {
  final liquid = GetIt.I<LiquidWalletRepository>();
  if (liquid case LiquidWalletRepository(signPset: final sign)) {
    await sign(pset: pset, walletId: 'w');
  }
  liquid..signPset(pset: pset, walletId: 'w');
  final s = #markPayinBroadcast;
  await swaps.createOrder;
}
''';
      const path = 'data/zz_evasion3.dart';
      // Of its imports, only the locator's package is refused; its names give it away too.
      expect(_importOffences({path: evasion}), [
        '$path imports package:get_it/get_it.dart',
      ]);
      expect(
        _vocabularyOffences({path: evasion}),
        contains(
          allOf(
            contains('signPset'),
            contains('markPayinBroadcast'),
            contains('createOrder'),
            contains('I'),
          ),
        ),
      );
      // In the pay use case's file, the same names are allowed but the locator's `I` is not.
      expect(
        _vocabularyOffences({pay: evasion}).join(),
        allOf(isNot(contains('signPset')), contains(' I')),
      );
      // The broadcast's and the address's use cases, imported from another file, fail on their import.
      expect(
        _importOffences({
          path:
              "import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';",
        }),
        hasLength(1),
      );
      expect(
        _importOffences({
          'data/wallet_payment_repository_impl.dart':
              "import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';",
        }),
        hasLength(1),
      );
      expect(
        _importOffences({
          pay:
              "import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';",
        }),
        isEmpty,
      );
    });
  });

  test('every import listed is used', () {
    final imported = {
      for (final source in sources.values) ..._urisOf(_parse(source)),
    };
    expect(_shellImports.difference(imported), isEmpty);
    for (final MapEntry(key: path, value: uris) in _perFileImports.entries) {
      expect(
        uris.difference(_urisOf(_parse(sources[path] ?? '')).toSet()),
        isEmpty,
        reason: path,
      );
    }
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
      // In the composition, it is named once: in the `wallet:` argument of `P2pFeature.setup`.
      final composition = lib['lib/locator.dart'];
      if (composition == null) fail('lib/locator.dart not read');
      final handed = _FacadeHandedOver();
      composition.accept(handed);
      expect(handed.elsewhere, 0);
      expect(handed.toSetup, 1);
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
    test(
      'the second review\'s evasion file fails: an extension and sync: true',
      () {
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
      },
    );

    test('each way of reaching a member with an implicit this is seen', () {
      for (final (label, source, name) in [
        (
          'extension',
          'extension E on Object { void f() => g(); }',
          'extension',
        ),
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
        // The locator's package, since the security review of #116: only the feature's locator resolves anything.
        'data/zz_evasion.dart imports package:get_it/get_it.dart',
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
      // In the pay use case's file too.
      expect(
        _vocabularyOffences({
          'domain/usecases/pay_checked_invoice_usecase.dart': evasion,
        }).join(),
        allOf(contains('broadcastTransaction'), contains('SpFacade')),
      );
    });

    test('each member that would move funds is outside the lists', () {
      // The names that commit funds are allowed in the pay use case's file only, never in the shared list; none of the others is allowed anywhere.
      for (final name in _fundNames) {
        expect(_shellVocabulary, isNot(contains(name)), reason: name);
        expect(
          _vocabularyOf(['void f() => wallet.$name();']),
          contains(name),
          reason: name,
        );
      }
      final everywhere = {
        _shellVocabulary,
        for (final names in _perFile.values) names,
      }.expand((names) => names).toSet();
      for (final name in [
        'signPsbt',
        'replacePreparedPayin',
        'refreshOrder',
        'refreshOrders',
        'getPendingOrders',
        'generateNew',
        'broadcast',
        'broadcastTransaction',
        'broadcastPsbt',
        'consolidate',
        'generateNewReceiveAddress',
        'getNewAddress',
        'sendPayment',
        'SyncWalletUsecase',
        'SpFacade',
        'dynamic',
        'noSuchMethod',
        'apply',
      ]) {
        expect(everywhere, isNot(contains(name)), reason: name);
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
        (
          'pattern field',
          'void f(Object o) { if (o case LiquidWalletRepository(signPset: final s)) {} }',
          'signPset',
        ),
        (
          'pattern field by its variable',
          'void f(Object o) { if (o case LiquidWalletRepository(:final signPset)) {} }',
          'signPset',
        ),
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
  // The payment's types (#100, W3): the handle, its progress and the refusals it adds; and the reading of a pattern's fields that #103's code already had (`Err(:final failure)`, `SwapAmountOutOfBoundsFailure(isMinimum: true, :final limitAmountSat)`).
  'P2pWalletPaymentExists',
  'P2pWalletBroadcastUnknown',
  'P2pWalletInvoiceExpiresTooSoon',
  'P2pWalletInvoiceUnreadable',
  'P2pWalletPayment',
  'P2pWalletPaymentBroadcastUnknown',
  'P2pWalletPaymentExpired',
  'P2pWalletPaymentFailed',
  'P2pWalletPaymentFound',
  'P2pWalletPaymentPaid',
  'P2pWalletPaymentPending',
  'P2pWalletPaymentPreparing',
  'P2pWalletPaymentProgress',
  'P2pWalletPaymentRefundPending',
  'P2pWalletPaymentRefunded',
  'P2pWalletPaymentSent',
  'P2pWalletPaymentSigned',
  'P2pWalletPaymentUnderReview',
  'P2pWalletQuoteChanged',
  'P2pWalletQuoteStale',
  'failure',
  'isMinimum',
  'limitAmountSat',
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
  'WatchInstantBalanceUsecase',
  // The payment's own classes, and their members and labels used across files.
  'FindWalletPaymentUsecase',
  'WalletInvoice',
  'WalletInvoiceRepository',
  'WalletInvoiceRepositoryImpl',
  'WalletPaymentRepository',
  'WalletPaymentRepositoryImpl',
  'WatchWalletPaymentUsecase',
  'accepted',
  'bolt11',
  'expiresAt',
  'find',
  'isSameInvoiceAs',
  'maxSats',
  'maybeSent',
  'note',
  'notSent',
  'payableUntil',
  'payment',
  'paymentHash',
  'progress',
  'progressOf',
  'sent',
  'total',
  'watch',
  // Of Dart's own, for the payment.
  'complete',
  'Completer',
  'difference',
  'fromMillisecondsSinceEpoch',
  'future',
  'int',
  'isAfter',
  'isClosed',
  'isEmpty',
  'isUtc',
  'Map',
  'Set',
  'zero',
  'then',
  'toLowerCase',
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
  'start',
  'stream',
  'testnet',
  'toInt',
  'value',
  'watchSyncs',
  'where',
  // Labels of named arguments the feature passes, the ones not already above (`id:`, `balance:`, `isTestnet:`… are). No `sync:`: the wallet's reader is asked without a sync, by its default.
  'amountSat',
  'available',
  'environment',
  'feeRate',
  'index',
  'inNetwork',
  'invoice',
  'isInAmountFixed',
  'maximum',
  'minimum',
  'minutes',
  'needed',
  'networkFee',
  'onCancel',
  'onDone',
  'onError',
  'onListen',
  'onlyDefaults',
  'onlyLiquid',
  'outNetwork',
  'pset',
  'quotedAt',
  'retryAfter',
  'signsHere',
  'walletId',
};

/// The names that commit funds or trigger a signature: an order created at the swap service, a signature, a signed payin saved and marked, a broadcast, and the wallet's receive address sent as the refund destination. Allowed in the pay use case's file only.
const _fundNames = {
  'createOrder',
  'savePreparedPayin',
  'markBroadcastUnknown',
  'markPayinBroadcast',
  'signPset',
  'BroadcastLiquidTransactionUsecase',
  'GetReceiveAddressUsecase',
};

/// The names each of these files may use besides [_shellVocabulary], and no other file: the wallet's code each one needs, and its own private helpers.
const _perFile = <String, Set<String>>{
  // The payment: the names that commit funds, and what it reads of the order it creates and of the transaction it builds.
  'domain/usecases/pay_checked_invoice_usecase.dart': {
    ..._fundNames,
    '_bounded',
    '_createOrder',
    '_delay',
    '_lateRefusal',
    'broadcasting',
    'building',
    'consume',
    'contains',
    'creation',
    'delayed',
    'earlierAttemptsOf',
    'IssuedQuotes',
    'localPayinTransactionId',
    'onTimeout',
    'payoutAddress',
    'PayTimeouts',
    'reading',
    'signing',
    'storing',
    'timeout',
    'TimeoutException',
    '_pay',
    '_refusalOf',
    'after',
    'awaitingUserConfirmation',
    'broadcastUnknown',
    'create',
    'destination',
    'destinationAddress',
    'fallbackAddress',
    'getAmountSentToAddress',
    'isAppUpdateRequired',
    'isPsbt',
    'localId',
    'localStatus',
    'order',
    'OrderSwapRecord',
    'payinAddressOrNull',
    'payinAmountSat',
    'payoutAmountSat',
    'purpose',
    'quotedCounterpartAmountSat',
    'readyToBroadcast',
    'seconds',
    'sendLightning',
    'signedPayinTransaction',
    'signedTransaction',
    'sourceWalletId',
    'transactionId',
    'OrderSwapEnvironment',
  },
  // The reads of a payment: the wallet's records of its swap orders, never a creation, a change or a refresh.
  'data/wallet_payment_repository_impl.dart': {
    '_belongsTo',
    '_isOurs',
    '_latest',
    '_paymentHashOf',
    '_records',
    'isProvablyUnspent',
    'localPayinTransactionId',
    'ours',
    'reduce',
    'signedPayinTransaction',
    'awaitingUserConfirmation',
    'broadcastUnknown',
    'completed',
    'createdAt',
    'creating',
    'creationUnknown',
    'destination',
    'end',
    'expired',
    'failed',
    'getOrders',
    'handle',
    'hasFundsMoved',
    'hasPreparedPayin',
    'isTerminal',
    'localId',
    'localStatus',
    'order',
    'OrderSwapRecord',
    'payinBroadcast',
    'payoutInProgress',
    'preparingPayin',
    'purpose',
    'readyToBroadcast',
    'refunded',
    'requiresManualReview',
    'sendLightning',
    'watchOrder',
  },
  // The wallet's decoder of invoices, its Send screen's.
  'data/wallet_invoice_repository_impl.dart': {
    '_decode',
    'DecodedInvoice',
    'fromString',
    'msats',
    'preimageHash',
    's',
    'WalletBolt11Read',
  },
  // The record of the quotes given.
  'domain/entities/issued_quotes.dart': {'_QuoteUse', 'Expando', 'used'},
  // The composition of the feature: the only file that resolves from the locator, and with the facade the only one that names the two use cases that quote and pay, so that no other file can reach them.
  'p2p_wallet_locator.dart': {
    'GetIt',
    'IssuedQuotes',
    'locator',
    'P2pWalletFacade',
    'PayCheckedInvoiceUsecase',
    'QuoteInvoicePaymentUsecase',
    'registerFactory',
    'registerLazySingleton',
  },
  'public/p2p_wallet_facade.dart': {
    'PayCheckedInvoiceUsecase',
    'QuoteInvoicePaymentUsecase',
  },
  'domain/usecases/quote_invoice_payment_usecase.dart': {
    'IssuedQuotes',
    'issue',
  },
};

/// The imports each of these files may have besides [_shellImports], and no other file.
const _perFileImports = <String, Set<String>>{
  'domain/usecases/pay_checked_invoice_usecase.dart': {
    'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart',
    'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart',
  },
  'data/wallet_invoice_repository_impl.dart': {'package:bull_sdk/boltz.dart'},
  'p2p_wallet_locator.dart': {'package:get_it/get_it.dart'},
};

/// Each file of [sources] that names what neither [_shellVocabulary] nor its own entry of [_perFile] allows, with those names.
List<String> _vocabularyOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    if ((_vocabularyOf([source])
            .difference(_shellVocabulary)
            .difference(_perFile[path] ?? const {})
            .toList()
          ..sort())
        case final names when names.isNotEmpty)
      '$path names ${names.join(' ')}',
];

/// Counts where `lib/locator.dart` names `P2pWalletFacade`: in the `wallet:` argument of `P2pFeature.setup`, or elsewhere.
final class _FacadeHandedOver extends RecursiveAstVisitor<void> {
  var toSetup = 0;
  var elsewhere = 0;

  bool _inSetupWallet(AstNode node) {
    for (AstNode? at = node; at != null; at = at.parent) {
      if (at is NamedExpression && at.name.label.name == 'wallet') {
        final call = at.parent?.parent;
        return call is MethodInvocation &&
            call.methodName.name == 'setup' &&
            (call.target?.toSource().contains('P2pFeature') ?? false);
      }
    }
    return false;
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'P2pWalletFacade') {
      _inSetupWallet(node) ? toSetup++ : elsewhere++;
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'P2pWalletFacade') {
      _inSetupWallet(node) ? toSetup++ : elsewhere++;
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitCommentReference(CommentReference node) {}
}

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
          !_shellImports.contains(uri) &&
          !(_perFileImports[path]?.contains(uri) ?? false))
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

  /// The field a pattern reads, such as `signPset:` in `LiquidWalletRepository(signPset: final sign)`, or `value` in `Ok(:final value)`: a getter, or a method torn off.
  @override
  void visitPatternField(PatternField node) {
    if (node.effectiveName case final name?) names.add(name);
    super.visitPatternField(node);
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
