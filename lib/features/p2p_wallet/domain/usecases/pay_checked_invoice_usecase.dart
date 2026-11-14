import 'dart:async';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/consolidation_required_exception.dart';
import 'package:bb_mobile/core/wallet/domain/insufficient_funds_exception.dart';
import 'package:bb_mobile/core/wallet/domain/no_spendable_utxo_exception.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// Pays a checked invoice from the Instant Payments wallet through the wallet's swap service, without a screen: the one place of this feature that creates a swap order, signs, saves a signed payin and broadcasts (#100, step W3; study § 3.3).
///
/// It is money code and triggers a signature: `wallet_shell_architecture_test.dart` allows the names that commit funds in this file only.
/// The sequence, the same as the wallet's automatic transfers (`ExchangeAutoswapProvider`), each step a stop with nothing moved until the broadcast:
/// 1. the quote is this wallet's, unused, recent and for this invoice; the invoice is still payable for [invoiceMargin]; the wallet is the default Liquid wallet, on the invoice's network, signing on this device; the wallet's own decoder reads the same payment hash, amount and network, and an expiry [invoiceMargin] away at least;
/// 2. no order of the wallet's records pays this invoice, in any state ([P2pWalletAlreadyPaid]): an invoice is never paid twice, even after a refund;
/// 3. the order is created with the invoice as its destination, an address of the wallet as the refund destination, and the payin the user accepted as the quoted counterpart, retried once when the service asks to wait, if the wait is short and leaves the margin;
/// 4. the payin the order asks is at most the one the user accepted, the app's own cap, much tighter than the wallet's tolerance of max(1 %, 1,000 sats): else [P2pWalletQuoteChanged];
/// 5. the funding transaction is built at the wallet's Liquid fee rate; it must send exactly the payin to the order's address (fail closed), and its fee and the total must stay within the quote;
/// 6. it is signed, saved on the order, the order marked « broadcast unknown », the **saved** transaction broadcast, and the order marked broadcast with its transaction id;
/// 7. the handle is returned.
/// 8. Nothing resumes or retries a payment: an order left signed or « broadcast unknown » by a crash is reported as such by the reads of the port, and finishing it is not this use case's.
/// Calls run one after the other ([execute] waits for the previous one), so that two payments of one invoice at once see each other's order, and two transactions are never built from the same coins at once.
/// It logs nothing, and passes the invoice's text to the wallet's code only as the order's destination and to its decoder.
class PayCheckedInvoiceUsecase {
  /// How long the invoice, and the coordinator's step, must stay payable when the payment starts and again just before the signature: 60 s.
  ///
  /// After the broadcast the swap service must see the funding on the Liquid network and pay the invoice: whether it waits for a confirmation (about a minute on Liquid) is not known (study § 2.5, § 7). 60 s covers one block and the calls before it; it is the margin the trade's state machine already asks before it offers the payment (`TradeTolerances.walletPaymentMargin`), and the owner's first trial is to tune both.
  static const invoiceMargin = Duration(seconds: 60);

  /// How old a quote may be when it is paid: 2 minutes.
  ///
  /// The service gives no expiry for its quotes; the cap of step 4 holds whatever the age, so this only bounds how long a confirmation may stay on screen before a fresh quote is needed. A taker bond lives 150 to 200 s in all.
  static const quoteMaxAge = Duration(minutes: 2);

  /// The wait before the one new try of a creation the service refused as too soon, when it says no wait: as the wallet's automatic transfers.
  static const _createRetryDelay = Duration(seconds: 5);

  /// The longest wait taken before that try: as the wallet's automatic transfers, whose quote goes stale past it.
  static const _maxCreateRetryDelay = Duration(seconds: 30);

  /// The longest wait the port passes on in a refusal: the service's `Retry-After` is any integer.
  static const _maxWait = Duration(minutes: 10);

  /// The rate of every Liquid send of the wallet, 0.1 sat/vB (25 sat/kwu), at which the quote estimated the network fee.
  static const _liquidFeeRate = RelativeFee(25);

  final IssuedQuotes _quotes;
  final InstantWalletRepository _wallets;
  final WalletInvoiceRepository _invoices;
  final WalletPaymentRepository _payments;
  final SwapFacade _swaps;
  final LiquidWalletRepository _liquid;
  final GetReceiveAddressUsecase _refundAddress;
  final BroadcastLiquidTransactionUsecase _broadcast;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// The end of the latest payment started: the next one waits for it.
  Future<void> _previous = Future<void>.value();

  PayCheckedInvoiceUsecase(
    this._quotes,
    this._wallets,
    this._invoices,
    this._payments,
    this._swaps,
    this._liquid,
    this._refundAddress,
    this._broadcast,
    this._now, {
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  /// Pays [invoice] within [accepted], or says why not; see the class for the sequence.
  ///
  /// The quote is consumed at once, before anything else, whatever happens next.
  @useResult
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> execute(
    CheckedBolt11Invoice invoice, {
    required P2pWalletQuote accepted,
  }) async {
    if (!_quotes.consume(accepted)) return const Err(P2pWalletQuoteStale());
    final previous = _previous;
    final done = Completer<void>();
    _previous = done.future;
    try {
      await previous;
      return await _pay(invoice, accepted);
    } finally {
      done.complete();
    }
  }

  Future<Result<P2pWalletPayment, P2pWalletRefusal>> _pay(
    CheckedBolt11Invoice invoice,
    P2pWalletQuote accepted,
  ) async {
    // 1. The quote, the invoice, the wallet, and the wallet's own reading of the invoice.
    final age = _now().difference(accepted.quotedAt);
    if (!accepted.invoice.isSameInvoiceAs(invoice) ||
        age.isNegative ||
        age > quoteMaxAge) {
      return const Err(P2pWalletQuoteStale());
    }
    if (_lateRefusal(invoice.payableUntil) case final refusal?) {
      return Err(refusal);
    }
    final InstantWallet wallet;
    switch (await _wallets.read()) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (wallet.refusalFor(invoice.network) case final refusal?) {
      return Err(refusal);
    }
    final WalletInvoice read;
    switch (await _invoices.read(invoice.bolt11)) {
      case Ok(:final value):
        read = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (read.isTestnet != (invoice.network == RobosatsNetwork.testnet)) {
      return const Err(P2pWalletWrongNetwork());
    }
    if (read.paymentHash != invoice.paymentHash ||
        read.amount != invoice.amount) {
      return const Err(P2pWalletInvoiceUnreadable());
    }
    if (_lateRefusal(read.expiresAt) case final refusal?) {
      return Err(refusal);
    }

    // 2. Never a second payment of this invoice.
    switch (await _payments.holdsPaymentOf(invoice)) {
      case Ok(value: true):
        return const Err(P2pWalletAlreadyPaid());
      case Ok():
        break;
      case Err(:final failure):
        return Err(failure);
    }

    // 3. The order, with the wallet's address for a refund.
    if (_swaps.isAppUpdateRequired) {
      return const Err(P2pWalletServiceRefused());
    }
    final String refund;
    try {
      refund = (await _refundAddress.execute(walletId: wallet.id)).address;
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final OrderSwapRecord record;
    switch (await _createOrder(invoice, accepted, wallet, refund)) {
      case Ok(:final value):
        record = value;
      case Err(:final failure):
        return Err(failure);
    }
    final order = record.order;
    final payinAddress = order?.payinAddressOrNull;
    if (order == null ||
        payinAddress == null ||
        payinAddress.isEmpty ||
        record.localStatus != OrderSwapLocalStatus.awaitingUserConfirmation ||
        record.purpose != OrderSwapPurpose.sendLightning ||
        record.destination != invoice.bolt11 ||
        record.sourceWalletId != wallet.id ||
        order.inNetwork != OrderSwapNetwork.liquid ||
        order.outNetwork != OrderSwapNetwork.lightning ||
        order.payoutAmountSat != invoice.amount.value) {
      // Not the order just asked for: nothing is built on it.
      return const Err(P2pWalletServiceRefused());
    }
    final payment = P2pWalletPayment(
      id: record.localId,
      paymentHash: invoice.paymentHash,
    );

    // 4. The cap: never more to the service than the payin the user accepted.
    final payin = order.payinAmountSat;
    if (payin > accepted.payin.value) {
      return const Err(P2pWalletQuoteChanged());
    }

    // 5. The funding transaction, checked before it is signed.
    final String pset;
    try {
      pset = await _liquid.buildPset(
        walletId: wallet.id,
        address: payinAddress,
        amountSat: payin.toInt(),
        feeRate: _liquidFeeRate,
      );
    } on InsufficientFundsException {
      return Err(_short(wallet, accepted));
    } on NoSpendableUtxoException {
      return Err(_short(wallet, accepted));
    } on ConsolidationRequiredException {
      return const Err(P2pWalletNeedsConsolidation());
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final int sent;
    final (int, int) sizeAndFee;
    try {
      sent = await _liquid.getAmountSentToAddress(
        pset: pset,
        address: payinAddress,
        walletId: wallet.id,
      );
      sizeAndFee = await _liquid.getPsetSizeAndAbsoluteFees(pset: pset);
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final (_, fee) = sizeAndFee;
    if (BigInt.from(sent) != payin || fee < 0) {
      // Fail closed: the transaction must send exactly the payin to the order's address.
      return const Err(P2pWalletUnavailable());
    }
    if (BigInt.from(fee) > accepted.networkFee.value ||
        payin + BigInt.from(fee) > accepted.total.value) {
      return const Err(P2pWalletQuoteChanged());
    }
    // The order took time to create: the margin is checked again just before the signature.
    if (_lateRefusal(invoice.payableUntil) case final refusal?) {
      return Err(refusal);
    }

    // 6. Sign, save, mark unknown, broadcast the saved transaction, mark broadcast.
    final String signed;
    try {
      signed = await _liquid.signPset(pset: pset, walletId: wallet.id);
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    try {
      switch (await _swaps.savePreparedPayin(
        localId: record.localId,
        signedTransaction: signed,
        isPsbt: false,
      )) {
        case Ok(:final value)
            when value.localStatus == OrderSwapLocalStatus.readyToBroadcast &&
                value.signedPayinTransaction == signed:
          break;
        case Ok() || Err():
          return const Err(P2pWalletUnavailable());
      }
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final String saved;
    try {
      switch (await _swaps.markBroadcastUnknown(record.localId)) {
        case Ok(:final value)
            when value.localStatus == OrderSwapLocalStatus.broadcastUnknown:
          // The transaction broadcast is the one saved on the order, read back from it, and only if it is the one just signed.
          final persisted = value.signedPayinTransaction;
          if (persisted == null || persisted != signed) {
            return const Err(P2pWalletUnavailable());
          }
          saved = persisted;
        case Ok():
          return const Err(P2pWalletUnavailable());
        case Err(failure: SwapOrderExpiredFailure()):
          // The order's deadline passed before the broadcast: nothing was sent.
          return const Err(P2pWalletServiceRefused());
        case Err():
          return const Err(P2pWalletUnavailable());
      }
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
    final String transactionId;
    try {
      transactionId = await _broadcast.execute(
        saved,
        isTestnet: wallet.isTestnet,
      );
    } catch (_) {
      // The transaction may have reached the network: the order stays « broadcast unknown », and nothing tries again.
      return Err(P2pWalletBroadcastUnknown(payment));
    }
    try {
      // The broadcast is done whatever this gives: a record left « broadcast unknown » is settled by the wallet's watcher.
      await _swaps.markPayinBroadcast(
        localId: record.localId,
        transactionId: transactionId,
      );
    } catch (_) {}

    // 7. The handle.
    return Ok(payment);
  }

  /// The order of step 3, tried once more when the service asks to wait, if the wait is short and leaves the margin; its failure as the port's refusal.
  Future<Result<OrderSwapRecord, P2pWalletRefusal>> _createOrder(
    CheckedBolt11Invoice invoice,
    P2pWalletQuote accepted,
    InstantWallet wallet,
    String refund,
  ) async {
    Future<Result<OrderSwapRecord, SwapFailure>> create() => _swaps.createOrder(
      amountSat: invoice.amount.value,
      // The invoice's amount is what the service pays out; the payin is its own, checked against the cap.
      isInAmountFixed: false,
      inNetwork: OrderSwapNetwork.liquid,
      outNetwork: OrderSwapNetwork.lightning,
      destinationAddress: invoice.bolt11,
      fallbackAddress: refund,
      purpose: OrderSwapPurpose.sendLightning,
      environment: switch (invoice.network) {
        RobosatsNetwork.mainnet => OrderSwapEnvironment.mainnet,
        RobosatsNetwork.testnet => OrderSwapEnvironment.testnet,
      },
      sourceWalletId: wallet.id,
      note: WalletPaymentRepository.note,
      quotedCounterpartAmountSat: accepted.payin.value,
    );

    try {
      var created = await create();
      // The quote may just have used the service's slot, so the creation is the call refused; nothing was created, so one new try is safe.
      if (created case Err(
        failure: SwapRateLimitedFailure(:final retryAfter),
      )) {
        final wait = retryAfter ?? _createRetryDelay;
        if (wait.isNegative ||
            wait > _maxCreateRetryDelay ||
            _lateRefusal(invoice.payableUntil, after: wait) != null) {
          return Err(P2pWalletServiceBusy(retryAfter: _bounded(retryAfter)));
        }
        await _delay(wait);
        created = await create();
      }
      return switch (created) {
        Ok(:final value) => Ok(value),
        Err(:final failure) => Err(_refusalOf(failure)),
      };
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
  }

  /// Why [until] is too close, from now (or after [after]): expired, or within [invoiceMargin]; `null` when the margin is left.
  P2pWalletRefusal? _lateRefusal(
    DateTime until, {
    Duration after = Duration.zero,
  }) {
    if (until.difference(_now().add(after)) >= invoiceMargin) return null;
    return until.isAfter(_now())
        ? const P2pWalletInvoiceExpiresTooSoon()
        : const P2pWalletInvoiceExpired();
  }

  /// The wallet cannot fund the payment: it has its balance, and needs the total accepted, or more than it has.
  static P2pWalletNotEnoughBalance _short(
    InstantWallet wallet,
    P2pWalletQuote accepted,
  ) {
    final atLeast = wallet.balance.value + BigInt.one;
    final total = accepted.total.value;
    return P2pWalletNotEnoughBalance(
      available: wallet.balance,
      needed: Sats(total > atLeast ? total : atLeast),
    );
  }

  /// The port's refusal for a failure of the order's creation: limits and waits as bounded numbers, never a text.
  static P2pWalletRefusal _refusalOf(SwapFailure failure) => switch (failure) {
    SwapAmountOutOfBoundsFailure(isMinimum: true, :final limitAmountSat) =>
      P2pWalletUnderMinimum(minimum: _sats(limitAmountSat)),
    SwapAmountOutOfBoundsFailure(isMinimum: false, :final limitAmountSat) =>
      P2pWalletOverMaximum(maximum: _sats(limitAmountSat)),
    SwapAmountOutOfBoundsFailure(isMinimum: null) =>
      const P2pWalletOutsideServiceLimits(),
    SwapRateLimitedFailure(:final retryAfter) => P2pWalletServiceBusy(
      retryAfter: _bounded(retryAfter),
    ),
    // An unknown outcome leaves the order recorded with this destination: the next payment of this invoice is refused as already paid, and the wallet's watcher settles the order.
    SwapNetworkFailure() ||
    SwapTimeoutFailure() ||
    SwapCreationUnknownFailure() => const P2pWalletServiceUnreachable(),
    SwapStorageFailure() => const P2pWalletUnavailable(),
    // A refused route, a request or answer found invalid, an order that deviates from the quote, « app update required » (HTTP 418), and what a creation cannot meet.
    SwapNoPaymentOptionFailure() ||
    SwapValidationFailure() ||
    SwapProviderFailure() ||
    SwapUnexpectedFailure() ||
    SwapOrderNotFoundFailure() ||
    SwapOrderExpiredFailure() ||
    SwapOrderMismatchFailure() ||
    SwapInvalidStateFailure() ||
    SwapPriceUnavailableFailure() => const P2pWalletServiceRefused(),
  };

  static Sats? _sats(BigInt? value) =>
      value == null || value.isNegative || value > CheckedBolt11Invoice.maxSats
      ? null
      : Sats(value);

  static Duration? _bounded(Duration? value) => switch (value) {
    null => null,
    final wait when wait.isNegative => null,
    final wait when wait > _maxWait => _maxWait,
    final wait => wait,
  };
}
