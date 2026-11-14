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

  const WalletPaymentRepositoryImpl(this._swaps, this._invoices);

  @override
  Future<Result<bool, P2pWalletRefusal>> holdsPaymentOf(
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
    if (records.any((record) => record.destination.toLowerCase() == text)) {
      return const Ok(true);
    }
    for (final record in records.where(_isOurs)) {
      if (await _paymentHashOf(record) == invoice.paymentHash) {
        return const Ok(true);
      }
    }
    return const Ok(false);
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
    final ours = records.where(_isOurs).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final record in ours) {
      if (await _paymentHashOf(record) == paymentHash) {
        return Ok(
          P2pWalletPaymentFound(
            payment: P2pWalletPayment(
              id: record.localId,
              paymentHash: paymentHash,
            ),
            progress: progressOf(record),
          ),
        );
      }
    }
    return const Ok(null);
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

  /// Whether [record] is an order this feature created: a Lightning payment from Liquid with this feature's note.
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

  /// The payment hash of the invoice [record] pays, as the wallet's decoder reads it, or `null`.
  Future<String?> _paymentHashOf(OrderSwapRecord record) async =>
      switch (await _invoices.read(record.destination)) {
        Ok(:final value) => value.paymentHash,
        Err() => null,
      };
}
