/// The invoices and addresses this wallet gave for a payout during this run of the app (#90), in memory only, one for the feature (schema 9, #204): what tells a payout given from this wallet from one pasted, when it is submitted.
///
/// `PayoutFromWalletUsecase` notes each one it gives, the very text it puts in the payout field; `SubmitPayoutUsecase` asks whether the text submitted is one of them. An invoice and a segwit address are compared without case (BOLT11 and bech32 are case-insensitive), any other address exactly. Never written anywhere, never printed: its [toString] names nothing it holds.
final class WalletPayoutDestinations {
  final Set<String> _invoices = {};
  final Set<String> _addresses = {};

  /// Notes [bolt11], an invoice this wallet gave.
  void gaveInvoice(String bolt11) => _invoices.add(_invoice(bolt11));

  /// Notes [address], an address this wallet gave.
  void gaveAddress(String address) => _addresses.add(_address(address));

  /// Whether [bolt11] is an invoice this wallet gave during this run.
  bool isInvoiceOfThisWallet(String bolt11) =>
      _invoices.contains(_invoice(bolt11));

  /// Whether [address] is an address this wallet gave during this run.
  bool isAddressOfThisWallet(String address) =>
      _addresses.contains(_address(address));

  static String _invoice(String text) {
    final trimmed = text.trim().toLowerCase();
    return trimmed.startsWith('lightning:')
        ? trimmed.substring('lightning:'.length)
        : trimmed;
  }

  static String _address(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    return lower.startsWith('bc1') ||
            lower.startsWith('tb1') ||
            lower.startsWith('bcrt1')
        ? lower
        : trimmed;
  }

  @override
  String toString() => 'WalletPayoutDestinations';
}
