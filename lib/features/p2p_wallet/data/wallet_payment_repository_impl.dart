import 'dart:async';

import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:p2p/p2p.dart';

/// The payments this feature started, read through the Swap feature's facade from the wallet's own records of its swap orders.
///
/// It reads the records (`getOrders`, `watchOrder`) and never asks the swap service: the wallet's own watcher refreshes pending orders while the app is open. Each record's state becomes a progress the port can show, without any text of the service.
/// This class logs nothing; the Swap feature logs no record it reads.
class WalletPaymentRepositoryImpl implements WalletPaymentRepository {
  final SwapFacade _swaps;
  final WalletInvoiceRepository _invoices;

  /// The payment hash of each destination read so far.
  final Map<String, String> _hashes = {};

  WalletPaymentRepositoryImpl(this._swaps, this._invoices);

  @override
  Future<Result<Set<String>, P2pWalletRefusal>> earlierAttemptsOf(
    CheckedBolt11Invoice invoice,
  ) async {
    final List<OrderSwapRecord> records;
    switch (await _records()) {
      case Ok(:final value):
        records = value;
      case Err(:final failure):
        return Err(failure);
    }
    final text = invoice.bolt11.toLowerCase();
    final matching = <OrderSwapRecord>[];
    for (final record in records) {
      if (record.destination.toLowerCase() == text) {
        matching.add(record);
      } else if (_isOurs(record)) {
        // An order whose invoice yields no payment hash cannot be tied to this invoice; its own text is covered above. It blocks nothing else: an unspent one paid nothing, and this feature decodes every invoice with the same decoder before it creates an order, so an order it made always reads (see [_paymentHashOf]).
        if (await _paymentHashOf(record) == invoice.paymentHash) {
          matching.add(record);
        }
      }
    }
    final spent = [
      for (final record in matching)
        if (!isProvablyUnspent(record, ours: _isOurs(record))) record,
    ];
    if (spent.isEmpty) {
      return Ok({for (final record in matching) record.localId});
    }
    final latest = _latest(spent);
    return Err(
      P2pWalletPaymentExists(
        progress: progressOf(latest),
        payment: _isOurs(latest)
            ? P2pWalletPayment(
                id: latest.localId,
                paymentHash: invoice.paymentHash,
              )
            : null,
      ),
    );
  }

  /// Whether nothing can have left the wallet, nor can leave it later, through [record]: then the invoice it pays may be paid again, after a new confirmation.
  ///
  /// A record is provably unspent when it holds no signed payin and no transaction id, its service order is not under review, and its status is one in which nothing was signed: the creation (`creating`, `creationUnknown`), the order waiting for its funding (`awaitingUserConfirmation`, `preparingPayin`), or an end with nothing signed (`expired`, `failed`). A record signed (`readyToBroadcast`), « broadcast unknown », broadcast, paid out, completed or refunded is not, nor is anything not listed. An order of this feature is never funded later (nothing resumes it); an order of another feature (the wallet's Send screen) that has not ended may still be funded by its screen, so only its ends count as unspent ([ours] false).
  /// The reason: the swap service is paid by a Liquid transaction of this wallet; a second attempt while the first one's transaction may exist would send the amount twice, and getting the second back would depend on the service's refund.
  static bool isProvablyUnspent(OrderSwapRecord record, {required bool ours}) {
    final order = record.order;
    if (record.signedPayinTransaction != null ||
        record.localPayinTransactionId != null ||
        (order != null && _serviceSawPayin(order))) {
      return false;
    }
    return switch (record.localStatus) {
      OrderSwapLocalStatus.expired || OrderSwapLocalStatus.failed => true,
      OrderSwapLocalStatus.creating ||
      OrderSwapLocalStatus.creationUnknown ||
      OrderSwapLocalStatus.awaitingUserConfirmation ||
      OrderSwapLocalStatus.preparingPayin => ours,
      OrderSwapLocalStatus.readyToBroadcast ||
      OrderSwapLocalStatus.broadcastUnknown ||
      OrderSwapLocalStatus.payinBroadcast ||
      OrderSwapLocalStatus.payoutInProgress ||
      OrderSwapLocalStatus.completed ||
      OrderSwapLocalStatus.refunded => false,
    };
  }

  @override
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> find(
    String paymentHash,
  ) async {
    final List<OrderSwapRecord> records;
    switch (await _records()) {
      case Ok(:final value):
        records = value;
      case Err(:final failure):
        return Err(failure);
    }
    final matching = <OrderSwapRecord>[];
    for (final record in records.where(_isOurs)) {
      // An order whose invoice yields no payment hash cannot be the payment of [paymentHash] as far as anything can tell; it is not a reason to answer nothing at all (see [earlierAttemptsOf]).
      if (await _paymentHashOf(record) == paymentHash) matching.add(record);
    }
    if (matching.isEmpty) return const Ok(null);
    final latest = _latest(matching);
    return Ok(
      P2pWalletPaymentFound(
        payment: P2pWalletPayment(id: latest.localId, paymentHash: paymentHash),
        progress: progressOf(latest),
      ),
    );
  }

  @override
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watch(
    P2pWalletPayment payment,
  ) {
    StreamSubscription<Result<OrderSwapRecord, SwapFailure>>? rows;
    late final StreamController<
      Result<P2pWalletPaymentProgress, P2pWalletRefusal>
    >
    controller;
    // Whether the record is this feature's order for that payment hash: read once, from the first row (the destination of an order never changes).
    Future<bool>? belongs;
    String? last;
    // The rows are handled one after the other, in order, even while the first one's invoice is read.
    var handled = Future<void>.value();

    void end() {
      if (controller.isClosed) return;
      unawaited(rows?.cancel());
      controller.add(const Err(P2pWalletUnavailable()));
      unawaited(controller.close());
    }

    Future<void> handle(Result<OrderSwapRecord, SwapFailure> row) async {
      if (controller.isClosed) return;
      final OrderSwapRecord record;
      switch (row) {
        case Ok(:final value):
          record = value;
        case Err():
          return end();
      }
      belongs ??= _belongsTo(record, payment);
      final ours = await belongs;
      if (controller.isClosed) return;
      if (ours != true || record.localId != payment.id) return end();
      final progress = progressOf(record);
      // The wallet rewrites a record at each poll; only a change of progress is given.
      if ('$progress' == last) return;
      last = '$progress';
      controller.add(Ok(progress));
    }

    controller = StreamController(
      onListen: () {
        rows = _swaps
            .watchOrder(payment.id)
            .listen(
              (row) => handled = handled.then((_) => handle(row)),
              onError: (Object _) => handled = handled.then((_) => end()),
              onDone: () => handled = handled.then((_) async {
                if (!controller.isClosed) await controller.close();
              }),
            );
      },
      onCancel: () => rows?.cancel(),
    );
    return controller.stream;
  }

  /// Where [record] stands, as a user can be told (`OrderSwapLocalStatus`, and the service's manual review).
  ///
  /// A broadcast is known from the transaction id the wallet records after it; a signed transaction without one may or may not have left the wallet once the record has ended.
  static P2pWalletPaymentProgress progressOf(OrderSwapRecord record) {
    final status = record.localStatus;
    final stillOpen =
        !status.isTerminal ||
        (status == OrderSwapLocalStatus.failed && record.hasFundsMoved);
    if (stillOpen && (record.order?.requiresManualReview ?? false)) {
      return const P2pWalletPaymentUnderReview();
    }
    final funds = record.hasFundsMoved
        ? P2pWalletFunds.sent
        : record.hasPreparedPayin
        ? P2pWalletFunds.maybeSent
        : P2pWalletFunds.notSent;
    return switch (status) {
      OrderSwapLocalStatus.creating ||
      OrderSwapLocalStatus.creationUnknown ||
      OrderSwapLocalStatus.awaitingUserConfirmation ||
      OrderSwapLocalStatus.preparingPayin => const P2pWalletPaymentPreparing(),
      OrderSwapLocalStatus.readyToBroadcast => const P2pWalletPaymentSigned(),
      OrderSwapLocalStatus.broadcastUnknown =>
        const P2pWalletPaymentBroadcastUnknown(),
      OrderSwapLocalStatus.payinBroadcast => const P2pWalletPaymentSent(),
      OrderSwapLocalStatus.payoutInProgress => const P2pWalletPaymentPending(),
      OrderSwapLocalStatus.completed => const P2pWalletPaymentPaid(),
      OrderSwapLocalStatus.refunded => const P2pWalletPaymentRefunded(),
      OrderSwapLocalStatus.expired => P2pWalletPaymentExpired(funds),
      OrderSwapLocalStatus.failed when record.hasFundsMoved =>
        const P2pWalletPaymentRefundPending(),
      OrderSwapLocalStatus.failed => P2pWalletPaymentFailed(funds),
    };
  }

  /// Every order of the wallet's records, of every wallet.
  Future<Result<List<OrderSwapRecord>, P2pWalletRefusal>> _records() async {
    try {
      return switch (await _swaps.getOrders()) {
        Ok(:final value) => Ok(value),
        Err() => const Err(P2pWalletUnavailable()),
      };
    } catch (_) {
      return const Err(P2pWalletUnavailable());
    }
  }

  /// The payin statuses in which the swap service reports nothing received: empty, « not started », « awaiting payment » (the values of the exchange's `OrderPayinStatus`, `lib/core/exchange/domain/entity/order.dart`, which the order service shares) and « pending » (what the wallet's own tests give a fresh order). Any other value (« in progress », « under review », « awaiting confirmation », « completed », « rejected », an unknown one) is the service's evidence of a payin.
  static const _noPayinStatuses = {
    '',
    'not started',
    'awaiting payment',
    'pending',
  };

  /// Whether the swap service reports a payin for [order]: a payin status other than [_noPayinStatuses] (its manual review included), or a transaction id it recorded, whoever sent it.
  static bool _serviceSawPayin(OrderSwap order) =>
      !_noPayinStatuses.contains(order.payinStatus.trim().toLowerCase()) ||
      order.liquidTransactionId != null ||
      order.bitcoinTransactionId != null;

  /// Whether [record] is an order this feature created: a Lightning payment from Liquid with this feature's note, a fixed text a user does not type by chance ([WalletPaymentRepository.note]).
  ///
  /// The note is the only field set at the creation that this feature can read back and that the wallet's Send screen does not decide by itself: the Send screen stores the user's own label there, and every other field is the same as a Send-screen order's (a destination wallet would mark it so, but the wallet's history would then show the payment as a transfer). An order of the Send screen labelled with that exact text would be taken for this feature's; it stays safe: one order holds one payin (the wallet's store refuses a second signed payin on a record), so paying on it leaves the Send screen's own attempt on it to fail.
  static bool _isOurs(OrderSwapRecord record) =>
      record.purpose == OrderSwapPurpose.sendLightning &&
      record.inNetwork == OrderSwapNetwork.liquid &&
      record.outNetwork == OrderSwapNetwork.lightning &&
      record.note == WalletPaymentRepository.note;

  /// Whether [record] is an order of this feature for an invoice of [payment]'s hash.
  Future<bool> _belongsTo(
    OrderSwapRecord record,
    P2pWalletPayment payment,
  ) async =>
      _isOurs(record) && await _paymentHashOf(record) == payment.paymentHash;

  /// The payment hash of the invoice [record] pays, as the wallet's decoder reads it (only the hash: an invoice without an amount or for a fraction of a satoshi, which the wallet's Send screen pays, reads too), or `null` when nothing can be read.
  ///
  /// `null` is possible only for an order this feature did not make (a payment of the wallet's own screens that happens to carry the feature's note) or after a change of the decoder: `PayCheckedInvoiceUsecase` reads every invoice with this decoder before it creates its order.
  /// An order's destination never changes: a hash read once is kept for the run of the app, so that each payment and each look-up decodes only the orders it has not decoded before (a few per payment, the history of this feature's orders at the first look-up). A failed read is not kept.
  Future<String?> _paymentHashOf(OrderSwapRecord record) async {
    final known = _hashes[record.destination];
    if (known != null) return known;
    final hash = await _invoices.paymentHashOf(record.destination);
    if (hash != null) _hashes[record.destination] = hash;
    return hash;
  }

  /// The latest of [records], by creation.
  static OrderSwapRecord _latest(List<OrderSwapRecord> records) =>
      records.reduce((a, b) => b.createdAt.isAfter(a.createdAt) ? b : a);
}
