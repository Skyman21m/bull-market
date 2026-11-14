import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/bech32_checksum.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The kind of a Bitcoin address that [BitcoinAddress.check] accepts.
enum BitcoinAddressKind {
  /// Base58Check, pay to public key hash: `1…` on mainnet, `m…` or `n…` on testnet.
  p2pkh,

  /// Base58Check, pay to script hash: `3…` on mainnet, `2…` on testnet.
  p2sh,

  /// Segwit version 0 with a 20-byte program, bech32: `bc1q…` or `tb1q…`.
  p2wpkh,

  /// Segwit version 0 with a 32-byte program, bech32.
  p2wsh,

  /// Segwit version 1 with a 32-byte program, bech32m: `bc1p…` or `tb1p…`.
  p2tr,
}

/// An on-chain address that passed [check] for the network of a trade: the only kind of address a payout signs (`UnlockedRobotPgpKey.signPayoutAddress`).
///
/// It is a pre-check, not a verdict: the coordinator's own bitcoind judges the address (`validate_onchain_address`, `api/utils.py:106-121`, commit ff1998c).
/// The check exists to refuse, before anything is signed, an address of the other network, a mistyped one and anything that is not an address, such as a private key or an invoice pasted in the wrong field.
/// [text] is the address exactly as given, which is what is signed and should be what is shown.
@immutable
final class BitcoinAddress {
  /// The longest text read: BIP-173 caps a segwit address at 90 characters, and a Base58Check address is at most 35.
  static const maxLength = 90;

  final String text;
  final BitcoinAddressKind kind;
  final RobosatsNetwork network;

  const BitcoinAddress._(this.text, this.kind, this.network);

  /// Checks [text] as an address to be paid on [network], without trimming or changing it.
  ///
  /// Accepted: Base58Check P2PKH and P2SH (version bytes 0 and 5 on mainnet, 111 and 196 on testnet, which testnet3, testnet4, signet and regtest share, as Bitcoin Core does), segwit version 0 in bech32 with a 20- or 32-byte program, and version 1 with a 32-byte program (taproot) in bech32m, with the human-readable part `bc` on mainnet and `tb` on testnet (signet and testnet4 included) in either case but not mixed.
  /// Refused:
  /// - [PayoutDestinationMalformed]: longer than [maxLength], whitespace or any character outside the encoding, mixed case, an unknown version byte or human-readable part, a witness version over 16, a program of the wrong length or with invalid padding;
  /// - [PayoutDestinationBadChecksum]: a checksum that does not match, most likely a typo, or the bech32m checksum on a version 0 program or the bech32 one on a later version (BIP-350);
  /// - [PayoutDestinationWrongNetwork]: a valid address of the other network, or of regtest (`bcrt`);
  /// - [PayoutDestinationUnsupported]: a valid segwit address of a version this check does not accept, version 1 with a program other than 32 bytes or versions 2 to 16 (BIP-350 makes them valid, and the coordinator's bitcoind says so, but the Lightning node that pays the swap may not send to them).
  static Result<BitcoinAddress, PayoutDestinationFailure> check(
    String text,
    RobosatsNetwork network,
  ) {
    if (text.length > maxLength) {
      return const Err(PayoutDestinationMalformed());
    }
    final lower = text.toLowerCase();
    final looksSegwit =
        lower.startsWith('bc1') ||
        lower.startsWith('tb1') ||
        lower.startsWith('bcrt1');
    return looksSegwit ? _segwit(text, network) : _base58(text, network);
  }

  static Result<BitcoinAddress, PayoutDestinationFailure> _segwit(
    String text,
    RobosatsNetwork network,
  ) {
    final SegwitProgram decoded;
    switch (_readSegwit(text)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        decoded = value;
    }
    final addressNetwork = switch (decoded.humanReadablePart) {
      'bc' => RobosatsNetwork.mainnet,
      'tb' => RobosatsNetwork.testnet,
      _ => null,
    };
    if (addressNetwork != network) {
      return const Err(PayoutDestinationWrongNetwork());
    }
    final kind = switch ((decoded.version, decoded.program.length)) {
      (0, 20) => BitcoinAddressKind.p2wpkh,
      (0, 32) => BitcoinAddressKind.p2wsh,
      (1, 32) => BitcoinAddressKind.p2tr,
      _ => null,
    };
    if (kind == null) return const Err(PayoutDestinationUnsupported());
    return Ok(BitcoinAddress._(text, kind, network));
  }

  /// [text] as a segwit address of mainnet, testnet or regtest, under the rules of BIP-173 and BIP-350, whatever its version.
  static Result<SegwitProgram, PayoutDestinationFailure> _readSegwit(
    String text,
  ) {
    final read = readBech32(text, maxLength: maxLength);
    final parts = read.parts;
    if (parts == null) {
      return read.refusal == Bech32Refusal.badChecksum
          ? const Err(PayoutDestinationBadChecksum())
          : const Err(PayoutDestinationMalformed());
    }
    final words = parts.words;
    if (!const {'bc', 'tb', 'bcrt'}.contains(parts.humanReadablePart) ||
        words.isEmpty ||
        words[0] > 16) {
      return const Err(PayoutDestinationMalformed());
    }
    final version = words[0];
    final program = bytesFromWords(Uint8List.sublistView(words, 1));
    if (program == null ||
        program.length < 2 ||
        program.length > 40 ||
        (version == 0 && program.length != 20 && program.length != 32)) {
      return const Err(PayoutDestinationMalformed());
    }
    final expected = version == 0 ? Bech32Variant.bech32 : Bech32Variant.bech32m;
    if (parts.variant != expected) {
      return const Err(PayoutDestinationBadChecksum());
    }
    return Ok((
      humanReadablePart: parts.humanReadablePart,
      version: version,
      program: program,
    ));
  }

  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// A Base58Check address: 25 bytes, a version byte, a 20-byte hash and the first 4 bytes of the double SHA-256 of the 21 others.
  static Result<BitcoinAddress, PayoutDestinationFailure> _base58(
    String text,
    RobosatsNetwork network,
  ) {
    if (text.length < 25 || text.length > 35) {
      return const Err(PayoutDestinationMalformed());
    }
    var value = BigInt.zero;
    var leadingZeros = 0;
    var leading = true;
    for (var i = 0; i < text.length; i++) {
      final digit = _base58Alphabet.indexOf(text[i]);
      if (digit < 0) return const Err(PayoutDestinationMalformed());
      if (leading && digit == 0) {
        leadingZeros++;
      } else {
        leading = false;
      }
      value = value * BigInt.from(58) + BigInt.from(digit);
    }
    final significant = value == BigInt.zero ? 0 : (value.bitLength + 7) >> 3;
    if (leadingZeros + significant != 25) {
      return const Err(PayoutDestinationMalformed());
    }
    final bytes = Uint8List(25);
    for (var i = 24; i >= leadingZeros; i--) {
      bytes[i] = (value & BigInt.from(0xff)).toInt();
      value >>= 8;
    }
    final payload = Uint8List.sublistView(bytes, 0, 21);
    final digest = sha256.convert(sha256.convert(payload).bytes).bytes;
    var difference = 0;
    for (var i = 0; i < 4; i++) {
      difference |= digest[i] ^ bytes[21 + i];
    }
    if (difference != 0) return const Err(PayoutDestinationBadChecksum());
    final (addressNetwork, kind) = switch (bytes[0]) {
      0x00 => (RobosatsNetwork.mainnet, BitcoinAddressKind.p2pkh),
      0x05 => (RobosatsNetwork.mainnet, BitcoinAddressKind.p2sh),
      0x6f => (RobosatsNetwork.testnet, BitcoinAddressKind.p2pkh),
      0xc4 => (RobosatsNetwork.testnet, BitcoinAddressKind.p2sh),
      _ => (null, null),
    };
    if (addressNetwork == null || kind == null) {
      return const Err(PayoutDestinationMalformed());
    }
    if (addressNetwork != network) {
      return const Err(PayoutDestinationWrongNetwork());
    }
    return Ok(BitcoinAddress._(text, kind, network));
  }

  @override
  bool operator ==(Object other) =>
      other is BitcoinAddress &&
      other.text == text &&
      other.network == network;

  @override
  int get hashCode => Object.hash(text, network);

  /// The kind and network only: a payout address is not logged.
  @override
  String toString() => 'BitcoinAddress(${kind.name}, ${network.name})';
}

/// A segwit address decoded: its human-readable part in lowercase, its witness version and its program.
typedef SegwitProgram = ({String humanReadablePart, int version, Uint8List program});

/// The segwit address [text] decoded under the rules of BIP-173 and BIP-350, whatever its network among mainnet, testnet and regtest, for the specification's test vectors, or why it is not one.
@visibleForTesting
Result<SegwitProgram, PayoutDestinationFailure> decodeSegwit(String text) =>
    BitcoinAddress._readSegwit(text);
