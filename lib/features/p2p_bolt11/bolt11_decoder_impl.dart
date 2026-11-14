import 'package:bolt11_decoder/bolt11_decoder.dart';
import 'package:decimal/decimal.dart';
import 'package:p2p/p2p.dart';

/// The P2P feature's BOLT11 port, implemented with the app's pinned `bolt11_decoder` (`pubspec.yaml`, git ref f5deec21), which the feature does not depend on (#86, design note § 3.9).
///
/// What that decoder does and does not do, read in its sources at that ref: it checks the bech32 checksum, reads the prefix, the amount, the timestamp and the tagged fields; it does not check the signature and does not recover the payee's key from it, so the payee is known only when the invoice states it (`n`).
/// It signals a malformed invoice by throwing whatever its parsing hits, `Error`s included (a `RangeError` on a short field, a `StateError` on an unknown prefix): on text from a coordinator these are no bug of this app, so every throw is caught here and becomes [Bolt11Malformed], and nothing of the invoice or of the throw is kept.
/// It reads the human-readable part leniently (`Decimal.parse` of what follows the prefix: `1.5u`, `1e3`, leading zeros, a unit letter repeated) and wraps an expiry field longer than 12 words: so the adapter also reads the amount itself, in the strict form of BOLT 11, and refuses any invoice whose amount the two readings do not agree on, and bounds the expiry field to 7 words (35 bits), as a second check that does not depend on the decoder.
/// The feature calls [decode] only with at most 2,000 visible ASCII characters (`Bolt11Reader`).
final class Bolt11DecoderImpl implements Bolt11Decoder {
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _nodeKey = RegExp(r'^0[23][0-9a-f]{64}$');
  static final Decimal _satsPerBitcoin = Decimal.fromInt(100000000);

  /// The longest expiry read: about 68 years, the largest a 31-bit count of seconds holds; a coordinator's hold invoice lives minutes to hours.
  static const _maxExpirySeconds = 0x7fffffff;

  /// The human-readable part of an invoice with an amount, in the strict form: a known prefix, digits without a leading zero (at most 18), at most one multiplier.
  static final RegExp _strictHrp = RegExp(
    r'^(?:lnbcrt|lntbs|lnbc|lntb)([1-9][0-9]{0,17})([munp]?)$',
  );

  static const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// The words of a timestamp, of a signature and of a checksum (BOLT 11).
  static const _timestampWords = 7;
  static const _signatureWords = 104;
  static const _checksumWords = 6;

  /// The longest expiry field read, in words: 35 bits, beyond any expiry and short of the decoder's wrap.
  static const _maxExpiryWords = 7;

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
    final strictSats = _strictSats(invoice);
    if (strictSats == null) return const Err(Bolt11AmountUnusable());
    if (!_fieldsBounded(invoice)) return const Err(Bolt11Malformed());
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
    if (sats.toBigInt() != strictSats) return const Err(Bolt11Malformed());
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

  /// The whole sats the human-readable part of [invoice] states, read in the strict form of BOLT 11 (« Human-readable part »), or `null` when it states none or not in that form, or a fraction of a sat.
  static BigInt? _strictSats(String invoice) {
    final lower = invoice.toLowerCase();
    final separator = lower.lastIndexOf('1');
    if (separator < 0) return null;
    final match = _strictHrp.firstMatch(lower.substring(0, separator));
    final digits = match?.group(1);
    if (match == null || digits == null) return null;
    final amount = BigInt.parse(digits);
    BigInt? exactly(BigInt divisor) =>
        amount % divisor == BigInt.zero ? amount ~/ divisor : null;
    return switch (match.group(2)) {
      'm' => amount * BigInt.from(100000),
      'u' => amount * BigInt.from(100),
      'n' => exactly(BigInt.from(10)),
      'p' => exactly(BigInt.from(10000)),
      _ => amount * BigInt.from(100000000),
    };
  }

  /// Whether the tagged fields of [invoice] fit exactly between its timestamp and its signature, and its expiry fields are 1 to [_maxExpiryWords] words long: read here from the data part, apart from the decoder.
  static bool _fieldsBounded(String invoice) {
    final lower = invoice.toLowerCase();
    final data = lower.substring(lower.lastIndexOf('1') + 1);
    final words = [
      for (final char in data.split('')) _bech32Charset.indexOf(char),
    ];
    if (words.any((word) => word < 0)) return false;
    final end = words.length - _checksumWords - _signatureWords;
    var at = _timestampWords;
    if (end < at) return false;
    while (at < end) {
      if (at + 3 > end) return false;
      final type = words[at];
      final length = words[at + 1] * 32 + words[at + 2];
      final start = at + 3;
      if (start + length > end) return false;
      if (type == 6 && (length < 1 || length > _maxExpiryWords)) return false;
      at = start + length;
    }
    return true;
  }
}
