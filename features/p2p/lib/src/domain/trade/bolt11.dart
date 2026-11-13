import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// The network a BOLT11 invoice is for, read from its prefix (BOLT 11, « Human-readable part »).
enum Bolt11Network {
  /// `lnbc`.
  mainnet,

  /// `lntb`.
  testnet,

  /// `lntbs`.
  signet,

  /// `lnbcrt`.
  regtest;

  /// Whether an invoice of this network can belong to a trade on [network]: `lnbc` on mainnet, `lntb` or `lntbs` on testnet, as the design note says (§ 4.4) and the wallet port's invoice accepts; regtest never.
  bool belongsTo(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => this == mainnet,
    RobosatsNetwork.testnet => this == testnet || this == signet,
  };
}

/// What a BOLT11 invoice says, once decoded and its signature checked: nothing in it has been compared with an order yet.
///
/// Its [toString] names nothing of the invoice: an invoice, a payment hash or a node key is never printed or logged (design note § 4.3).
@immutable
final class Bolt11Invoice {
  final Bolt11Network network;

  /// The amount, a whole number of sats: an invoice without an amount, or for a fraction of a sat, is refused before it becomes one.
  final Sats amount;

  /// The payment hash, 64 lowercase hexadecimal characters.
  final String paymentHash;

  /// When the invoice was made, as it says.
  final DateTime createdAt;

  /// How long after [createdAt] it may be paid: its `x` field, or 3,600 s without one (BOLT 11).
  final Duration expiry;

  /// The description, as the payee wrote it, `null` without a `d` field: free text of the coordinator, to clean before it is shown.
  final String? description;

  /// The node the invoice says it pays, 66 lowercase hexadecimal characters: its `n` field, `null` without one.
  ///
  /// The app's decoder (`bolt11_decoder` at f5deec21) neither checks the signature nor recovers the key it was made with, so this is what the invoice states, not a proof; a coordinator's LND hold invoice carries no `n` field.
  final String? payeeNodeKey;

  const Bolt11Invoice({
    required this.network,
    required this.amount,
    required this.paymentHash,
    required this.createdAt,
    required this.expiry,
    required this.description,
    required this.payeeNodeKey,
  });

  /// When the invoice stops being payable.
  DateTime get expiresAt => createdAt.add(expiry);

  @override
  String toString() => 'Bolt11Invoice';
}

/// Why a text is not a BOLT11 invoice the trade can use: a type, never the text or the decoder's message.
sealed class Bolt11Refusal extends Failure {
  const Bolt11Refusal();

  @override
  String toString() => runtimeType.toString();
}

/// More than [Bolt11Reader.maxLength] characters, refused before the decoder sees it.
final class Bolt11TooLong extends Bolt11Refusal {
  const Bolt11TooLong();
}

/// Empty, or a character that is not visible ASCII (`!` to `~`), refused before the decoder sees it.
final class Bolt11NotVisibleAscii extends Bolt11Refusal {
  const Bolt11NotVisibleAscii();
}

/// Not a BOLT11 invoice: its encoding, its checksum, its fields or its signature are wrong.
final class Bolt11Malformed extends Bolt11Refusal {
  const Bolt11Malformed();
}

/// A prefix of no known network.
final class Bolt11UnknownNetwork extends Bolt11Refusal {
  const Bolt11UnknownNetwork();
}

/// No amount, or an amount that is not a whole number of sats: a hold invoice of a coordinator always has whole sats (`api/lightning/lnd.py`).
final class Bolt11AmountUnusable extends Bolt11Refusal {
  const Bolt11AmountUnusable();
}

/// The domain port of a BOLT11 decoder, implemented outside the feature with the app's pinned `bolt11_decoder` and lent by the shell (design note § 3.9).
///
/// [decode] is pure: no clock, no I/O, no randomness, nothing printed or logged.
/// It is called only through [Bolt11Reader], with at most [Bolt11Reader.maxLength] visible ASCII characters, and must turn anything the library throws or returns that it cannot vouch for into a [Bolt11Refusal].
abstract interface class Bolt11Decoder {
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice);
}

/// Reads a BOLT11 invoice through a [Bolt11Decoder], with the input bounded first and every surprise of the decoder a [Bolt11Refusal].
@immutable
final class Bolt11Reader {
  /// The longest invoice read, in characters, as the package keeps a coordinator's invoice and the design note bounds it (§ 4.4): a hold invoice of a coordinator is about 400.
  static const maxLength = 2000;

  static final RegExp _visibleAscii = RegExp(r'^[\x21-\x7E]+$');
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _nodeKey = RegExp(r'^0[23][0-9a-f]{64}$');

  final Bolt11Decoder _decoder;

  const Bolt11Reader(this._decoder);

  /// The invoice [text] decodes to, or why it cannot be used.
  ///
  /// The decoder sees only [maxLength] visible ASCII characters at most; an exception it throws is a [Bolt11Malformed], and so is an answer that breaks its own contract (a payment hash or a node key of the wrong form, no amount).
  Result<Bolt11Invoice, Bolt11Refusal> read(String text) {
    if (text.length > maxLength) return const Err(Bolt11TooLong());
    if (!_visibleAscii.hasMatch(text)) return const Err(Bolt11NotVisibleAscii());
    final Result<Bolt11Invoice, Bolt11Refusal> decoded;
    try {
      decoded = _decoder.decode(text);
    } on Exception {
      return const Err(Bolt11Malformed());
    }
    return switch (decoded) {
      Err() => decoded,
      Ok(:final value)
          when !_hex64.hasMatch(value.paymentHash) ||
              !(value.payeeNodeKey == null ||
                  _nodeKey.hasMatch(value.payeeNodeKey ?? '')) ||
              value.amount.value <= BigInt.zero ||
              value.expiry.isNegative =>
        const Err(Bolt11Malformed()),
      Ok() => decoded,
    };
  }
}
