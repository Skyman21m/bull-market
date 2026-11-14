import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/bech32_checksum.dart';
import 'package:robosats/src/bitcoin_address.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';

/// The routing budget of a Lightning payout, in parts per million of the buyer's amount: what the coordinator may spend on routing fees, taken off the invoice (`routing_budget_ppm`).
///
/// From 0 to [maxPpm]: the reference client takes a budget only while it is under 99,999 (`frontend/src/components/TradeBox/Forms/LightningPayout.tsx:281-286`, commit ff1998c), within the serializer's 0 to 100,001 (`api/serializers.py:645-652`), and warns above 10,000.
/// 0 asks the coordinator for its own default budget (`api/lightning/lnd.py:476-480`), and the invoice is then for the whole amount.
@immutable
final class RoutingBudgetPpm {
  /// The largest budget the reference client sends.
  static const maxPpm = 99998;

  /// The reference client's default budget (`LightningPayout.tsx:67-74`).
  static const RoutingBudgetPpm referenceDefault = RoutingBudgetPpm._(1000);

  final int ppm;

  const RoutingBudgetPpm._(this.ppm);

  /// The budget of [ppm] parts per million, or `null` outside 0 to [maxPpm].
  static RoutingBudgetPpm? of(int ppm) =>
      ppm >= 0 && ppm <= maxPpm ? RoutingBudgetPpm._(ppm) : null;

  /// The amount the payout invoice must be for, out of the buyer's amount [buyerSats] (the order's `invoice_amount`, or `trade_satoshis` for a buyer, the same number): the coordinator refuses any other (`PayoutInvoiceRefusal.wrongAmount`).
  ///
  /// The coordinator's computation, in double precision as Python does it: `int(n - float(n) * (float(ppm) / 1_000_000))` (`api/logics.py:868-872`), which is the reference client's `Math.floor(n - n * (ppm / 1000000))` (`LightningPayout.tsx:110-113`).
  /// `null` when [buyerSats] is over [CoordinatorReadBounds.maxSats].
  Sats? invoiceSats(Sats buyerSats) {
    if (buyerSats.value > BigInt.from(CoordinatorReadBounds.maxSats)) {
      return null;
    }
    final amount = buyerSats.value.toDouble();
    return Sats.fromInt((amount - amount * (ppm / 1000000)).floor());
  }

  @override
  bool operator ==(Object other) => other is RoutingBudgetPpm && other.ppm == ppm;

  @override
  int get hashCode => ppm.hashCode;

  @override
  String toString() => 'RoutingBudgetPpm($ppm)';
}

/// The mining fee rate of an on-chain payout, in sat/vB with at most 3 decimals, from 2 to 500 (`mining_fee_rate`).
///
/// The bounds are the coordinator's absolute ones and the reference client's: at least 2 (`api/logics.py:784`; the coordinator also asks for its economy estimate when that is higher, and refuses less with `PayoutMiningFeeTooLow`), at most 500 (`api/logics.py:794`), as `frontend/src/components/TradeBox/Forms/OnchainPayout.tsx:37-39` (commit ff1998c) bounds its field.
/// The 3 decimals are the serializer's (`api/serializers.py:687-689`, `max_digits=6, decimal_places=3`), which refuses more with an empty `400`.
/// The rate is always sent: without one the coordinator would use its own suggestion unchecked, up to 1,000 (`api/logics.py:630-634`, `:802-803`).
@immutable
final class MiningFeeRate {
  static const minSatPerVbyte = 2;
  static const maxSatPerVbyte = 500;

  /// The virtual size the coordinator charges for the payout transaction (`api/logics.py:807`).
  static const chargedVbytes = 280;

  /// The least the coordinator sends on chain: a payout that would send less is refused (`api/logics.py:815-820`, `PayoutBelowDustLimit`).
  static const minimumSentSats = 20000;

  /// Thousandths of sat/vB.
  final int _thousandths;

  const MiningFeeRate._(this._thousandths);

  /// The rate of [satPerVbyte] sat/vB, or `null` when it is not a finite number from [minSatPerVbyte] to [maxSatPerVbyte] with at most 3 decimals.
  ///
  /// The coordinator's `suggested_mining_fee_rate` has 3 decimals at most (`OnchainPayment.suggested_mining_fee_rate`, `api/models/onchain_payment.py:56-62`), so it gives a rate whenever it is within the bounds.
  static MiningFeeRate? of(double satPerVbyte) {
    if (!satPerVbyte.isFinite ||
        satPerVbyte < minSatPerVbyte ||
        satPerVbyte > maxSatPerVbyte) {
      return null;
    }
    final thousandths = (satPerVbyte * 1000).round();
    if ((thousandths / 1000 - satPerVbyte).abs() > 1e-9) return null;
    return MiningFeeRate._(thousandths);
  }

  double get satPerVbyte => _thousandths / 1000;

  /// The value sent, as the reference client sends its number: an integer when the rate is whole.
  num get wire => _thousandths % 1000 == 0 ? _thousandths ~/ 1000 : satPerVbyte;

  /// What the address receives out of the buyer's amount [buyerSats] after the coordinator's swap fee of [swapFeePercent] percent (the order's `swap_fee_rate`) and this rate over [chargedVbytes]: the coordinator's computation, in double precision as Python does it (`api/logics.py:806-813`).
  ///
  /// Under [minimumSentSats], negative included, the coordinator refuses the address.
  /// `null` when [buyerSats] is over [CoordinatorReadBounds.maxSats] or [swapFeePercent] is not a finite number from 0 to 100.
  int? sentSats({required Sats buyerSats, required double swapFeePercent}) {
    if (buyerSats.value > BigInt.from(CoordinatorReadBounds.maxSats) ||
        !swapFeePercent.isFinite ||
        swapFeePercent < 0 ||
        swapFeePercent > 100) {
      return null;
    }
    final amount = buyerSats.value.toDouble();
    final miningFeeSats = (satPerVbyte * chargedVbytes).truncate();
    return (amount - amount * swapFeePercent / 100 - miningFeeSats).truncate();
  }

  @override
  bool operator ==(Object other) =>
      other is MiningFeeRate && other._thousandths == _thousandths;

  @override
  int get hashCode => _thousandths.hashCode;

  @override
  String toString() => 'MiningFeeRate($satPerVbyte sat/vB)';
}

/// A payout clear-signed by a robot's key, ready for `CoordinatorClient.submitPayoutInvoice` or `submitPayoutAddress`: only `UnlockedRobotPgpKey.signPayoutInvoice` and `signPayoutAddress` make one, never free text.
///
/// [text] is the invoice or the address exactly as it was signed, and as the coordinator will read it back (`api/utils.py:642-644`): the text to compare with what was decoded and shown before submitting.
sealed class SignedPayout {
  /// The invoice or the address that was signed.
  String get text;

  /// The clear-signed message: starts with `-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n`, then [text], then the signature block.
  String get signedMessage;

  /// The network of [text].
  RobosatsNetwork get network;

  /// The robot whose key signed it.
  RobotHashId get signer;

  const SignedPayout();
}

/// A Lightning invoice for the buyer's payout, clear-signed: its shape, checksum and network were checked, not its content (amount, expiry, payee), which the caller decodes and checks before signing.
final class SignedPayoutInvoice extends SignedPayout {
  @override
  final String text;
  @override
  final String signedMessage;
  @override
  final RobosatsNetwork network;
  @override
  final RobotHashId signer;

  @internal
  const SignedPayoutInvoice.internal(
    this.text,
    this.signedMessage,
    this.network,
    this.signer,
  );

  /// The network only: an invoice is not logged.
  @override
  String toString() => 'SignedPayoutInvoice(${network.name})';
}

/// An on-chain address for the buyer's payout, checked by [BitcoinAddress.check] and clear-signed.
final class SignedPayoutAddress extends SignedPayout {
  final BitcoinAddress address;
  @override
  final String signedMessage;
  @override
  final RobotHashId signer;

  @internal
  const SignedPayoutAddress.internal(
    this.address,
    this.signedMessage,
    this.signer,
  );

  @override
  String get text => address.text;

  @override
  RobosatsNetwork get network => address.network;

  /// The kind and network only: an address is not logged.
  @override
  String toString() => 'SignedPayoutAddress($address)';
}

/// The human-readable part of a BOLT11 invoice: `ln`, the currency, then an optional amount (BOLT 11, « Human-Readable Part »).
final RegExp _invoicePrefix = RegExp(r'^ln(bcrt|bc|tbs|tb)(?:[0-9]+[munp]?)?$');

/// Words of a BOLT11 data part before its checksum: a 35-bit timestamp (7 words) and a 520-bit signature (104 words) at least.
const _minimumInvoiceWords = 7 + 104;

/// Checks that [invoice] has the shape of a BOLT11 invoice of [network], before it is signed: at most [CoordinatorOrder.maxInvoiceLength] characters, bech32 with a valid checksum, all lowercase or all uppercase, the prefix `lnbc` on mainnet and `lntb` on testnet.
///
/// A coordinator on testnet runs testnet3 (or testnet4), whose invoices are `lntb`: a signet invoice (`lntbs`) and a regtest one (`lnbcrt`) are another network.
/// This is no decoding: the amount, expiry and payee are the caller's to check, on the very string signed.
@internal
Result<void, PayoutDestinationFailure> checkPayoutInvoice(
  String invoice,
  RobosatsNetwork network,
) {
  final read = readBech32(invoice, maxLength: CoordinatorOrder.maxInvoiceLength);
  final parts = read.parts;
  if (parts == null) {
    return read.refusal == Bech32Refusal.badChecksum
        ? const Err(PayoutDestinationBadChecksum())
        : const Err(PayoutDestinationMalformed());
  }
  final match = _invoicePrefix.firstMatch(parts.humanReadablePart);
  if (match == null || parts.words.length < _minimumInvoiceWords) {
    return const Err(PayoutDestinationMalformed());
  }
  if (parts.variant != Bech32Variant.bech32) {
    return const Err(PayoutDestinationBadChecksum());
  }
  final invoiceNetwork = switch (match.group(1)) {
    'bc' => RobosatsNetwork.mainnet,
    'tb' => RobosatsNetwork.testnet,
    _ => null,
  };
  if (invoiceNetwork != network) {
    return const Err(PayoutDestinationWrongNetwork());
  }
  return const Ok(null);
}
