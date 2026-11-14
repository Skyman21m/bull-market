import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bull_sdk/boltz.dart' as boltz;
import 'package:p2p/p2p.dart';

/// What the wallet's BOLT11 decoder reads in an invoice, as this feature uses it.
typedef WalletBolt11Read = ({
  BigInt msats,
  String paymentHash,
  BigInt expiresAt,
  String network,
});

/// Reads an invoice with the wallet's own BOLT11 decoder, the one its Send screen reaches through `PaymentRequest.parse`: `DecodedInvoice.fromString` of the Boltz library in the wallet's SDK, called directly, without the other parsers `PaymentRequest.parse` tries after it and without their logging.
///
/// It is called without a Boltz URL, as `PaymentRequest.parse` calls it, so the binding is given nothing to reach. Anything it throws is [P2pWalletInvoiceUnreadable], with no text kept; this class logs and prints nothing.
/// What it verifies that the trade's decoder (`bolt11_decoder`, which checks no signature) does not: the binding's Dart side documents nothing (it is generated code: `third_party/boltz/api/invoice.dart` of `bull_sdk`); the Rust library behind it parses with the `lightning-invoice` crate, whose `Bolt11Invoice` parsing checks the bech32 checksum and that the signature is valid and recovers the payee's key, as the reviews of #116 read it. Those Rust sources are not in the build's package cache and could not be read here: the signature check is the crate's documented behaviour, not verified in this repository. The binding also reads an expired invoice (it returns `isExpired` instead of failing), so a payment's invoice reads again after it expires.
class WalletInvoiceRepositoryImpl implements WalletInvoiceRepository {
  final Future<WalletBolt11Read> Function(String) _decode;

  /// [decode] is the wallet's decoder, Boltz's `DecodedInvoice.fromString`, unless a test gives another.
  const WalletInvoiceRepositoryImpl([this._decode = _boltzDecode]);

  static Future<WalletBolt11Read> _boltzDecode(String bolt11) async {
    final invoice = await boltz.DecodedInvoice.fromString(s: bolt11);
    return (
      msats: invoice.msats,
      paymentHash: invoice.preimageHash,
      expiresAt: invoice.expiresAt,
      network: invoice.network,
    );
  }

  @override
  Future<Result<WalletInvoice, P2pWalletRefusal>> read(String bolt11) async {
    final WalletBolt11Read read;
    try {
      read = await _decode(bolt11);
    } catch (_) {
      return const Err(P2pWalletInvoiceUnreadable());
    }
    final thousand = BigInt.from(1000);
    if (read.msats <= BigInt.zero ||
        read.msats % thousand != BigInt.zero ||
        read.expiresAt <= BigInt.zero ||
        read.expiresAt > BigInt.from(_latestSecond)) {
      return const Err(P2pWalletInvoiceUnreadable());
    }
    return Ok(
      WalletInvoice(
        amount: Sats(read.msats ~/ thousand),
        paymentHash: read.paymentHash.toLowerCase(),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          read.expiresAt.toInt() * 1000,
          isUtc: true,
        ),
        // As the wallet's `PaymentRequest.parse` reads it: anything but Bitcoin's main network is a test network (the port's own type refuses signet and regtest prefixes before this).
        isTestnet: read.network != 'bitcoin',
      ),
    );
  }

  /// The last second a `DateTime` holds comfortably (year 9999): a later expiry is not one to read.
  static const _latestSecond = 253402300799;
}
