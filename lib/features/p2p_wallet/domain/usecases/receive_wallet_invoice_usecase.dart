import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// A Lightning invoice of the Instant Payments wallet for the buyer's payout (#90): what the wallet's Receive screen does (`CreateReceiveOrderSwapUsecase`), through the Swap feature's facade, with the checks of the port.
///
/// In this order:
/// 1. the Instant Payments wallet, on the trade's network;
/// 2. an earlier invoice of this feature still waiting to be paid, for the same amount and the same wallet, with at least [minimumLife] left, is given again rather than a new order created, so that taps do not pile up orders at the service;
/// 3. the quote, the amount fixed on the Lightning side (`isInAmountFixed: true`): the invoice asks exactly the amount, and the service's fee comes out of what arrives;
/// 4. a new address of the Instant Payments wallet, the destination of the service's payout (the Receive screen's, `generateNew: true`);
/// 5. the order, retried once when the service asks to wait a short time (a create right after a quote is the request it most often refuses, `ExchangeAutoswapProvider`);
/// 6. the invoice the order carries, read by the wallet's own decoder: exactly the amount, the trade's network, at least [minimumLife] left, and expiring with the order, no earlier than its deadline and no later than [deadlineTolerance] after it: what the service does with a payment that reaches it after its own deadline cannot be read in the wallet's code (the order has no refund address), so such an invoice is never given ([P2pWalletServiceRefused]).
///
/// It moves none of the user's funds. An invoice given and never paid leaves its order at the service, which expires at its deadline; the wallet marks it expired when it next reads it, and its history shows it so. Two calls at once run one after the other, so that the second one finds the first one's invoice. It logs nothing.
class ReceiveWalletInvoiceUsecase {
  /// The least time an invoice given must still live: enough to submit it to the coordinator.
  static const minimumLife = Duration(minutes: 1);

  /// How long after the order's deadline its invoice may still expire: the deadline and the invoice's expiry are written at different precisions (`CreateReceiveOrderSwapUsecase` compares them to the second).
  static const deadlineTolerance = Duration(seconds: 10);

  /// The longest wait taken on a service that asks to wait before the order: past it, the refusal is given.
  static const maximumRetryWait = Duration(seconds: 30);

  final InstantWalletRepository _wallets;
  final WalletInvoiceRepository _invoices;
  final SwapFacade _swaps;
  final GetReceiveAddressUsecase _addresses;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  Future<void> _previous = Future.value();

  ReceiveWalletInvoiceUsecase(
    this._wallets,
    this._invoices,
    this._swaps,
    this._addresses,
    this._now, {
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  @useResult
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> execute(
    RobosatsNetwork network,
    Sats amount,
  ) async {
    final previous = _previous;
    final done = Completer<void>();
    _previous = done.future;
    await previous;
    try {
      return await _make(network, amount);
    } finally {
      done.complete();
    }
  }

  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> _make(
    RobosatsNetwork network,
    Sats amount,
  ) async {
    if (amount.value <= BigInt.zero) {
      return const Err(P2pWalletServiceRefused());
    }
    final InstantWallet wallet;
    switch (await _wallets.read()) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (wallet.isTestnet != (network == RobosatsNetwork.testnet)) {
      return const Err(P2pWalletWrongNetwork());
    }
    if (_swaps.isAppUpdateRequired) return const Err(P2pWalletServiceRefused());
    final environment = switch (network) {
      RobosatsNetwork.mainnet => OrderSwapEnvironment.mainnet,
      RobosatsNetwork.testnet => OrderSwapEnvironment.testnet,
    };

    // An earlier invoice still waiting, given again.
    switch (await _swaps.getOrders(walletId: wallet.id)) {
      case Ok(:final value):
        for (final record in value) {
          if (!_mayReuse(record, wallet, environment, amount)) continue;
          final invoice = await _invoiceOf(record, network, amount);
          if (invoice case Ok()) return invoice;
        }
      case Err():
        return const Err(P2pWalletUnavailable());
    }

    final OrderSwapQuote quote;
    switch (await _swaps.getQuote(
      environment: environment,
      amountSat: amount.value,
      isInAmountFixed: true,
      inNetwork: OrderSwapNetwork.lightning,
      outNetwork: OrderSwapNetwork.liquid,
    )) {
      case Ok(:final value):
        quote = value;
      case Err(:final failure):
        return Err(_refusalOf(failure));
    }
    if (quote.inAmountSat != amount.value ||
        quote.outAmountSat > amount.value) {
      return const Err(P2pWalletServiceRefused());
    }

    final String destination;
    try {
      destination = (await _addresses.execute(
        walletId: wallet.id,
        generateNew: true,
      )).address;
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }

    Future<Result<OrderSwapRecord, SwapFailure>> create() => _swaps.createOrder(
      amountSat: amount.value,
      isInAmountFixed: true,
      inNetwork: OrderSwapNetwork.lightning,
      outNetwork: OrderSwapNetwork.liquid,
      destinationAddress: destination,
      fallbackAddress: null,
      purpose: OrderSwapPurpose.receiveLightning,
      environment: environment,
      destinationWalletId: wallet.id,
      note: WalletPaymentRepository.note,
      quotedCounterpartAmountSat: quote.outAmountSat,
    );
    var created = await create();
    if (created case Err(failure: SwapRateLimitedFailure(:final retryAfter))
        when retryAfter != null &&
            !retryAfter.isNegative &&
            retryAfter <= maximumRetryWait) {
      await _delay(retryAfter);
      created = await create();
    }
    final OrderSwapRecord record;
    switch (created) {
      case Ok(:final value):
        record = value;
      case Err(:final failure):
        return Err(_refusalOf(failure));
    }
    if (record.purpose != OrderSwapPurpose.receiveLightning ||
        record.destinationWalletId != wallet.id ||
        record.destination != destination ||
        record.environment != environment ||
        record.note != WalletPaymentRepository.note) {
      return const Err(P2pWalletServiceRefused());
    }
    return _invoiceOf(record, network, amount);
  }

  /// Whether [record] is an invoice of this feature for [amount] to [wallet], still waiting for its payment and its deadline not passed: one that may be given again.
  bool _mayReuse(
    OrderSwapRecord record,
    InstantWallet wallet,
    OrderSwapEnvironment environment,
    Sats amount,
  ) {
    final order = record.order;
    return record.purpose == OrderSwapPurpose.receiveLightning &&
        record.note == WalletPaymentRepository.note &&
        record.destinationWalletId == wallet.id &&
        record.environment == environment &&
        record.localStatus == OrderSwapLocalStatus.awaitingUserConfirmation &&
        record.requestedAmountSat == amount.value &&
        order != null &&
        order.payinAmountSat == amount.value &&
        order.confirmationDeadline.isAfter(_now().add(minimumLife));
  }

  /// The invoice of [record], once the wallet's decoder read it as the port promises it; [P2pWalletServiceRefused] otherwise.
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> _invoiceOf(
    OrderSwapRecord record,
    RobosatsNetwork network,
    Sats amount,
  ) async {
    final order = record.order;
    final text = order?.lightningInvoice;
    if (order == null || text == null || text.isEmpty) {
      return const Err(P2pWalletServiceRefused());
    }
    final WalletInvoice read;
    switch (await _invoices.read(text)) {
      case Ok(:final value):
        read = value;
      case Err():
        return const Err(P2pWalletServiceRefused());
    }
    final now = _now().toUtc();
    final deadline = order.confirmationDeadline.toUtc();
    final received = order.payoutAmountSat;
    if (read.amount != amount ||
        order.payinAmountSat != amount.value ||
        read.isTestnet != (network == RobosatsNetwork.testnet) ||
        read.expiresAt.isBefore(now.add(minimumLife)) ||
        read.expiresAt.isBefore(_toTheSecond(deadline)) ||
        read.expiresAt.isAfter(deadline.add(deadlineTolerance)) ||
        received <= BigInt.zero ||
        received > amount.value) {
      return const Err(P2pWalletServiceRefused());
    }
    return Ok(
      P2pWalletInvoice(
        bolt11: text,
        amount: amount,
        expiresAt: read.expiresAt,
        received: Sats(received),
      ),
    );
  }

  /// The port's refusal for a failure of the quote or of the order: limits and waits as bounded numbers, never a text (as `PayCheckedInvoiceUsecase` maps them).
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
    // An unknown outcome leaves the order recorded, unpaid; the wallet's watcher settles it, and it expires at its deadline.
    SwapNetworkFailure() ||
    SwapTimeoutFailure() ||
    SwapCreationUnknownFailure() => const P2pWalletServiceUnreachable(),
    SwapStorageFailure() => const P2pWalletUnavailable(),
    // A refused route, a request or answer found invalid, « app update required » (HTTP 418), and what a creation cannot meet.
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

  /// The longest wait the port passes on.
  static const _maxWait = Duration(minutes: 10);

  static Duration? _bounded(Duration? value) => switch (value) {
    null => null,
    final wait when wait.isNegative => null,
    final wait when wait > _maxWait => _maxWait,
    final wait => wait,
  };

  /// [instant] without its fraction of a second: the precision of an invoice's expiry.
  static DateTime _toTheSecond(DateTime instant) =>
      DateTime.fromMillisecondsSinceEpoch(
        instant.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      );
}
