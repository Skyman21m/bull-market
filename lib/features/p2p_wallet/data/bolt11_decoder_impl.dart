import 'package:bolt11_decoder/bolt11_decoder.dart';
import 'package:decimal/decimal.dart';
import 'package:p2p/p2p.dart';

/// The P2P feature's BOLT11 port, implemented with the app's pinned `bolt11_decoder` (`pubspec.yaml`, git ref f5deec21), which the feature does not depend on (#86, design note § 3.9).
///
/// What that decoder does and does not do, read in its sources at that ref: it checks the bech32 checksum, reads the prefix, the amount, the timestamp and the tagged fields; it does not check the signature and does not recover the payee's key from it, so the payee is known only when the invoice states it (`n`).
/// It signals a malformed invoice by throwing whatever its parsing hits, `Error`s included (a `RangeError` on a short field, a `StateError` on an unknown prefix): on text from a coordinator these are no bug of this app, so every throw is caught here and becomes [Bolt11Malformed], and nothing of the invoice or of the throw is kept.
/// The feature calls [decode] only with at most 2,000 visible ASCII characters (`Bolt11Reader`).
final class Bolt11DecoderImpl implements Bolt11Decoder {
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _nodeKey = RegExp(r'^0[23][0-9a-f]{64}$');
  static final Decimal _satsPerBitcoin = Decimal.fromInt(100000000);

  /// The longest expiry read: about 68 years, the largest a 31-bit count of seconds holds; a coordinator's hold invoice lives minutes to hours.
  static const _maxExpirySeconds = 0x7fffffff;

  const Bolt11DecoderImpl();

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) {
    final Bolt11PaymentRequest request;
    try {
      request = Bolt11PaymentRequest(invoice);
    } catch (_) {
      // Every throw of the decoder is a malformed invoice: see the class comment.
      return const Err(Bolt11Malformed());
    }
    final network = switch (request.prefix) {
      PayRequestPrefix.lnbc => Bolt11Network.mainnet,
      PayRequestPrefix.lntb => Bolt11Network.testnet,
      PayRequestPrefix.lntbs => Bolt11Network.signet,
      PayRequestPrefix.lnbcrt => Bolt11Network.regtest,
    };
    final sats = request.amount * _satsPerBitcoin;
    if (sats <= Decimal.zero || !sats.isInteger) {
      return const Err(Bolt11AmountUnusable());
    }
    List<Object?> fields(String type) => [
      for (final tag in request.tags)
        if (tag.type == type) tag.data as Object?,
    ];
    // Exactly one payment hash, and at most one field of each other kind read: a reader that took another of two hashes than the payer's wallet would pin an invoice other than the one paid.
    final hashes = fields('payment_hash');
    final descriptions = fields('description');
    final payees = fields('payee_pubkey');
    final expiries = fields('expiry');
    if (hashes.length != 1 ||
        descriptions.length > 1 ||
        payees.length > 1 ||
        expiries.length > 1) {
      return const Err(Bolt11Malformed());
    }
    final hash = hashes.single;
    final description = descriptions.isEmpty ? null : descriptions.single;
    final payee = payees.isEmpty ? null : payees.single;
    final expiry = expiries.isEmpty ? 3600 : expiries.single;
    if (hash is! String || !_hex64.hasMatch(hash)) {
      return const Err(Bolt11Malformed());
    }
    final String? descriptionText;
    switch (description) {
      case null:
        descriptionText = null;
      case final String text:
        descriptionText = text;
      default:
        return const Err(Bolt11Malformed());
    }
    final String? payeeKey;
    switch (payee) {
      case null:
        payeeKey = null;
      case final String key when _nodeKey.hasMatch(key):
        payeeKey = key;
      default:
        return const Err(Bolt11Malformed());
    }
    if (expiry is! int || expiry < 0 || expiry > _maxExpirySeconds) {
      return const Err(Bolt11Malformed());
    }
    final seconds = request.timestamp.toInt();
    return Ok(
      Bolt11Invoice(
        network: network,
        amount: Sats(sats.toBigInt()),
        paymentHash: hash,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ),
        expiry: Duration(seconds: expiry),
        description: descriptionText,
        payeeNodeKey: payeeKey,
      ),
    );
  }
}
