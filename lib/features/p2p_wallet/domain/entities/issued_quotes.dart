import 'package:p2p/p2p.dart';

/// The quotes this wallet gave, each payable once (#88: one confirmation, one payment).
///
/// A [P2pWalletQuote] has a public constructor in `package:p2p`: a payment takes only a quote that [issue] recorded here, by its identity, and [consume] lets it through once. Kept in memory for the run of the app: a quote given before a restart is not payable after it.
final class IssuedQuotes {
  final Expando<_QuoteUse> _uses = Expando('issued quotes');

  /// Records [quote] as given by this wallet and not used yet; a quote used already stays used.
  void issue(P2pWalletQuote quote) => _uses[quote] ??= _QuoteUse.issued;

  /// Whether [quote] was given by this wallet and not used yet; it is used from now on, whatever the payment that presents it becomes.
  bool consume(P2pWalletQuote quote) {
    if (_uses[quote] != _QuoteUse.issued) return false;
    _uses[quote] = _QuoteUse.used;
    return true;
  }
}

enum _QuoteUse { issued, used }
