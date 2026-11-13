import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the shell's side of the P2P wallet port (`lib/features/p2p_wallet`, #100) may reach in the app: in this pull request, only reads of the wallet and the swap service's quote.
///
/// Its code names none of the members that create an order at the swap service, sign, store a signed payin, broadcast, or reveal a new address; the pull request that adds the payment allows them in its pay use case alone, and is reviewed as money code.
/// It imports other features through their `public/` facade only, never the wallet's send feature; its facade is built by its locator alone and named outside the feature by `lib/locator.dart` alone, which hands it to P2P.
/// The sources are read as text, comments and string contents removed (the reading of `background_tasks_keystore_test.dart`): a name is a use wherever it stands in code. It cannot see a call made through a value received from elsewhere under another name: that is for the money review.
void main() {
  const folder = 'lib/features/p2p_wallet';
  final sources = {
    for (final file in Directory(folder).listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart'))
        file.path: file.readAsStringSync(),
  };

  test('the scan reads the feature', () {
    expect(
      sources.keys,
      containsAll([
        '$folder/public/p2p_wallet_facade.dart',
        '$folder/data/instant_wallet_repository_impl.dart',
        '$folder/data/lightning_swap_quote_repository_impl.dart',
        '$folder/p2p_wallet_locator.dart',
      ]),
    );
  });

  test(
    'names nothing that commits funds, signs, broadcasts or reveals an address',
    () {
      expect(_moneyOffences(sources), isEmpty);
    },
  );

  test(
    'imports other features through their public facade only, never send',
    () {
      expect(_importOffences(sources), isEmpty);
    },
  );

  test(
    'its facade is built by its locator and named outside it by the composition only',
    () {
      final lib = {
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            if (file.readAsStringSync() case final source
                when source.contains('P2pWalletFacade'))
              file.path: _codeOf(source),
      };
      expect(
        {
          for (final MapEntry(key: path, value: code) in lib.entries)
            if (RegExp(r'\bP2pWalletFacade\s*\(').hasMatch(code)) path,
        },
        {
          '$folder/p2p_wallet_locator.dart',
          // Its constructor's declaration.
          '$folder/public/p2p_wallet_facade.dart',
        },
      );
      expect(
        {
          for (final MapEntry(key: path, value: code) in lib.entries)
            if (RegExp(r'\bP2pWalletFacade\b').hasMatch(code)) path,
        },
        {
          '$folder/p2p_wallet_locator.dart',
          '$folder/public/p2p_wallet_facade.dart',
          'lib/locator.dart',
        },
      );
    },
  );

  group('the rule bites:', () {
    const path = '$folder/domain/usecases/pay_invoice_usecase.dart';

    test('each name that commits funds is seen in code', () {
      for (final member in _moneyMembers) {
        expect(_moneyOffences({path: 'void f() => facade.$member();'}), [
          '$path names $member',
        ], reason: member);
      }
    });

    test('a comment or a string is no use', () {
      expect(
        _moneyOffences({
          path:
              "// createOrder, signPset\n/// [SwapFacade.createOrder]\nfinal s = 'signPset broadcast';",
        }),
        isEmpty,
      );
    });

    test('an import of internals or of send fails', () {
      for (final directive in [
        "import 'package:bb_mobile/features/swap/domain/usecases/create_order_swap_usecase.dart';",
        "import 'package:bb_mobile/features/swap/data/order_swap_repository_impl.dart';",
        "import 'package:bb_mobile/features/send/public/send_facade.dart';",
        "import 'package:bb_mobile/features/send/domain/usecases/create_send_swap_usecase.dart';",
        "export 'package:bb_mobile/features/pay/domain/sign_pay_payin_usecase.dart';",
        "import '../../swap/domain/swap_failure.dart';",
      ]) {
        expect(
          _importOffences({path: directive}),
          hasLength(1),
          reason: directive,
        );
      }
      for (final directive in [
        "import 'package:bb_mobile/features/swap/public/swap_facade.dart';",
        "import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';",
        "import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';",
        "import 'package:p2p/p2p.dart';",
      ]) {
        expect(_importOffences({path: directive}), isEmpty, reason: directive);
      }
    });
  });
}

/// The names whose use commits or moves funds, signs, stores a signed payin, broadcasts, or reveals a new address of the wallet.
const _moneyMembers = [
  'createOrder',
  'signPset',
  'signPsbt',
  'savePreparedPayin',
  'replacePreparedPayin',
  'markBroadcastUnknown',
  'markPayinBroadcast',
  'refreshOrder',
  'refreshOrders',
  'broadcast',
  'consolidate',
  'generateNewReceiveAddress',
  'GetReceiveAddressUsecase',
  'BroadcastLiquidTransactionUsecase',
  'BroadcastBitcoinTransactionUsecase',
];

/// Each money name used in the code of [sources], by path.
List<String> _moneyOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    for (final member in _moneyMembers)
      if (RegExp('\\b$member\\b').hasMatch(_codeOf(source)))
        '$path names $member',
];

/// Each import or export of another feature that is not its `public/` folder, any of the send feature, and any relative one that leaves the feature.
List<String> _importOffences(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: source) in sources.entries)
    for (final match in _directive.allMatches(source))
      if (match.group(1) case final uri? when _isForbidden(uri))
        '$path imports $uri',
];

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

bool _isForbidden(String uri) {
  if (!uri.startsWith('package:')) return uri.contains('../');
  final feature = RegExp(
    r'^package:bb_mobile/features/([a-z0-9_]+)/(.*)$',
  ).firstMatch(uri);
  if (feature == null) return false;
  final name = feature.group(1);
  if (name == 'p2p_wallet') return false;
  if (name == 'send') return true;
  return !(feature.group(2) ?? '').startsWith('public/');
}

/// The code of [source], every comment and the text of every string replaced by spaces, line breaks kept (the reading of `background_tasks_keystore_test.dart`).
String _codeOf(String source) {
  String blank(String text) => text.replaceAll(RegExp(r'[^\n]'), ' ');
  final out = StringBuffer();
  // The innermost last: the code of the file, then each string and each interpolation being read.
  final stack = <_Reading>[_Code()];
  var i = 0;
  while (i < source.length) {
    final reading = stack.last;
    final char = source[i];
    switch (reading) {
      case _String(:final quote, :final raw):
        if (source.startsWith(quote, i)) {
          out.write(quote);
          i += quote.length;
          stack.removeLast();
        } else if (!raw && char == r'\' && i + 1 < source.length) {
          out.write(blank(source.substring(i, i + 2)));
          i += 2;
        } else if (!raw && source.startsWith(r'${', i)) {
          out.write(r'${');
          i += 2;
          stack.add(_Code());
        } else {
          out.write(blank(char));
          i++;
        }
      case _Code() when source.startsWith('//', i):
        final end = source.indexOf('\n', i);
        final stop = end < 0 ? source.length : end;
        out.write(blank(source.substring(i, stop)));
        i = stop;
      case _Code() when source.startsWith('/*', i):
        final start = i;
        var depth = 0;
        do {
          if (source.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        } while (depth > 0 && i < source.length);
        out.write(blank(source.substring(start, i)));
      case _Code():
        final raw =
            char == 'r' &&
            (i == 0 || !RegExp(r'[\w$]').hasMatch(source[i - 1]));
        final quoteAt = raw ? i + 1 : i;
        if (quoteAt < source.length &&
            (source[quoteAt] == "'" || source[quoteAt] == '"')) {
          final single = source[quoteAt];
          final quote = source.startsWith(single * 3, quoteAt)
              ? single * 3
              : single;
          out.write(source.substring(i, quoteAt + quote.length));
          i = quoteAt + quote.length;
          stack.add(_String(quote, raw: raw));
          continue;
        }
        if (char == '}' && reading.depth == 0 && stack.length > 1) {
          // The end of an interpolation: back to its string.
          stack.removeLast();
        } else if (char == '{') {
          reading.depth++;
        } else if (char == '}') {
          reading.depth--;
        }
        out.write(char);
        i++;
    }
  }
  return out.toString();
}

sealed class _Reading {}

/// Code, with the depth of its braces, so that the `}` that ends an interpolation is told from the others.
final class _Code extends _Reading {
  int depth = 0;
}

/// A string literal, up to its closing [quote].
final class _String extends _Reading {
  final String quote;
  final bool raw;

  _String(this.quote, {required this.raw});
}
