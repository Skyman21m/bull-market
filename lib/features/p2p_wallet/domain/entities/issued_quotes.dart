import 'package:p2p/p2p.dart';

/// The quotes this wallet gave, each payable once (#88: one confirmation, one payment), from the wallet it was given for.
///
/// A [P2pWalletQuote] has a public constructor in `package:p2p`: a payment takes only a quote that [issue] recorded here, by its identity, and [consume] lets it through once, telling which wallet it was given for. Kept in memory for the run of the app: a quote given before a restart is not payable after it.
final class IssuedQuotes {
  final Expando<_QuoteUse> _uses = Expando('issued quotes');

  /// Records [quote] as given by this wallet, for the Instant Payments wallet [walletId], and not used yet; a quote recorded already keeps its first record.
  void issue(P2pWalletQuote quote, {required String walletId}) =>
      _uses[quote] ??= _QuoteUse(walletId);

  /// The wallet [quote] was given for, when this wallet gave it and it was not used yet, or `null`; it is used from now on, whatever the payment that presents it becomes.
  String? consume(P2pWalletQuote quote) {
    final use = _uses[quote];
    if (use == null || use.used) return null;
    use.used = true;
    return use.walletId;
  }
}

/// Whom a quote was given for, and whether a payment presented it.
final class _QuoteUse {
  final String walletId;
  bool used = false;

  _QuoteUse(this.walletId);
}
