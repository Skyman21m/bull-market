import 'dart:async';

import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart' show checkedBolt11InvoiceForTesting;

import 'fakes.dart';

/// What the fakes of a payment did, in order, as one list: the order of the side effects is what the tests pin.
final class Journal {
  final List<String> events = [];

  void add(String event) => events.add(event);

  /// The events of [kinds] only, in order (an event's kind is the text before its first `:`).
  List<String> only(Set<String> kinds) => [
    for (final event in events)
      if (kinds.contains(event.split(':').first)) event,
  ];
}

/// An obviously fake invoice string of [amount] sats on [network], [tag] making it differ from the others: the shape the port's type checks, never a real invoice.
String payBolt11({
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  int amount = 600,
  String tag = 'q',
}) {
  final prefix = switch (network) {
    RobosatsNetwork.mainnet => 'lnbc',
    RobosatsNetwork.testnet => 'lntb',
  };
  return '$prefix${amount * 10}n1${tag * 8}${'q' * 52}';
}

/// An obviously fake payment hash of [seed].
String payHash([int seed = 1]) => seed.toRadixString(16).padLeft(2, '0') * 32;

/// A checked invoice, as `walletPaymentFor` would give it, payable until [payableIn] after [testNow].
CheckedBolt11Invoice payInvoice({
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  int amount = 600,
  String tag = 'q',
  String? hash,
  Duration payableIn = const Duration(minutes: 3),
  Duration? expiresIn,
}) {
  final invoice = checkedBolt11InvoiceForTesting(
    bolt11: payBolt11(network: network, amount: amount, tag: tag),
    amount: Sats.fromInt(amount),
    network: network,
    paymentHash: hash ?? payHash(),
    expiresAt: testNow.add(expiresIn ?? payableIn),
    payableUntil: testNow.add(payableIn),
    // Built before it stops being payable, so that the payment's own checks of time can be tested.
    now: testNow.subtract(const Duration(hours: 1)),
  );
  if (invoice == null) throw StateError('the fake invoice is refused');
  return invoice;
}

/// The wallet's decoder, as a test writes it: each invoice it knows reads as given, any other is unreadable. It records every text it was given.
final class FakeWalletInvoices implements WalletInvoiceRepository {
  final Map<String, Result<WalletInvoice, P2pWalletRefusal>> known = {};
  final List<String> reads = [];

  /// Makes [invoice] readable as it says, unless [read] says otherwise.
  void learn(CheckedBolt11Invoice invoice, {WalletInvoice? read}) =>
      known[invoice.bolt11] = Ok(
        read ??
            WalletInvoice(
              amount: invoice.amount,
              paymentHash: invoice.paymentHash,
              expiresAt: invoice.expiresAt,
              isTestnet: invoice.network == RobosatsNetwork.testnet,
            ),
      );

  @override
  Future<Result<WalletInvoice, P2pWalletRefusal>> read(String bolt11) async {
    reads.add(bolt11);
    return known[bolt11] ?? const Err(P2pWalletInvoiceUnreadable());
  }
}

/// The Swap feature's facade over records in memory, with the wallet's rules for the payin states (`order_swap_repository_impl.dart`): creating, preparing, marking and watching orders. No test reaches the swap service.
///
/// Creating an order journals `create`, or answers the next failure of [createFailures]; the order's payin is [payinFor] of the payin quoted. Like the wallet's repository, an active order with the same destination, wallet, purpose and amount is answered again instead of a new one.
final class FakeOrderSwaps implements SwapFacade {
  final Journal journal;
  final DateTime Function() now;
  final Map<String, OrderSwapRecord> records = {};
  final _changes = StreamController<OrderSwapRecord>.broadcast(sync: true);

  /// The failures the next creations answer, in order.
  final List<SwapFailure> createFailures = [];

  /// The payin the service asks for the payin quoted (by default, the same).
  BigInt Function(BigInt quoted) payinFor = (quoted) => quoted;

  /// The payout the service's order states for the amount asked (by default, the same).
  BigInt Function(BigInt amount) payoutFor = (amount) => amount;

  bool appUpdateRequired = false;
  SwapFailure? ordersFailure;
  SwapFailure? saveFailure;
  SwapFailure? markUnknownFailure;
  Object? markBroadcastError;

  /// When set, the order's saved transaction is replaced by this text when it is marked « broadcast unknown », as a store that kept another one would.
  String? savedInstead;

  /// Runs at each creation, before it answers: a test moves its clock there, as a slow service would.
  void Function()? onCreate;

  /// When set, every creation answers this record, as a store holding another order would.
  OrderSwapRecord? createAnswer;

  /// What every creation was asked: amount, destination, refund address, purpose, wallet, note, payin quoted.
  final List<Map<String, Object?>> created = [];
  var _next = 0;

  FakeOrderSwaps(this.journal, this.now);

  /// Adds [record] as the wallet's records would hold it.
  void hold(OrderSwapRecord record) => records[record.localId] = record;

  /// Changes a record as the wallet's watcher does after a poll, and gives it to every watch of it.
  void update(OrderSwapRecord record) {
    records[record.localId] = record;
    _changes.add(record);
  }

  @override
  bool get isAppUpdateRequired => appUpdateRequired;

  @override
  Future<Result<OrderSwapRecord, SwapFailure>> createOrder({
    required BigInt amountSat,
    required bool isInAmountFixed,
    required OrderSwapNetwork inNetwork,
    required OrderSwapNetwork outNetwork,
    required String destinationAddress,
    required String? fallbackAddress,
    required OrderSwapPurpose purpose,
    required OrderSwapEnvironment environment,
    String? sourceWalletId,
    String? destinationWalletId,
    String? note,
    BigInt? quotedCounterpartAmountSat,
  }) async {
    journal.add('create');
    created.add({
      'amount': amountSat,
      'fixedIn': isInAmountFixed,
      'in': inNetwork,
      'out': outNetwork,
      'destination': destinationAddress,
      'refund': fallbackAddress,
      'purpose': purpose,
      'environment': environment,
      'wallet': sourceWalletId,
      'note': note,
      'quoted': quotedCounterpartAmountSat,
    });
    onCreate?.call();
    if (createFailures.isNotEmpty) return Err(createFailures.removeAt(0));
    if (createAnswer case final answer?) return Ok(answer);
    for (final record in records.values) {
      if (!record.localStatus.isTerminal &&
          record.destination == destinationAddress &&
          record.sourceWalletId == sourceWalletId &&
          record.purpose == purpose &&
          record.requestedAmountSat == amountSat) {
        return Ok(record);
      }
    }
    _next++;
    final record = paymentRecord(
      localId: 'local-$_next',
      destination: destinationAddress,
      fallback: fallbackAddress ?? destinationAddress,
      amount: amountSat,
      payin: payinFor(quotedCounterpartAmountSat ?? amountSat),
      payout: payoutFor(amountSat),
      walletId: sourceWalletId,
      note: note,
      purpose: purpose,
      createdAt: now(),
      deadline: now().add(const Duration(minutes: 10)),
      status: OrderSwapLocalStatus.awaitingUserConfirmation,
      payinAddress: 'lq1payin$_next',
    );
    records[record.localId] = record;
    return Ok(record);
  }

  @override
  Future<Result<List<OrderSwapRecord>, SwapFailure>> getOrders({
    String? walletId,
  }) async {
    if (ordersFailure case final failure?) return Err(failure);
    return Ok([
      for (final record in records.values)
        if (walletId == null ||
            record.sourceWalletId == walletId ||
            record.destinationWalletId == walletId)
          record,
    ]);
  }

  @override
  Future<Result<OrderSwapRecord, SwapFailure>> savePreparedPayin({
    required String localId,
    required String signedTransaction,
    required bool isPsbt,
  }) async {
    journal.add('save:$signedTransaction');
    if (saveFailure case final failure?) return Err(failure);
    final record = records[localId];
    if (record == null) return const Err(SwapOrderNotFoundFailure());
    if (record.localStatus != OrderSwapLocalStatus.awaitingUserConfirmation &&
        record.localStatus != OrderSwapLocalStatus.preparingPayin) {
      return const Err(SwapInvalidStateFailure());
    }
    final saved = record.withPayinState(
      status: OrderSwapLocalStatus.readyToBroadcast,
      signedTransaction: signedTransaction,
      isPsbt: isPsbt,
    );
    update(saved);
    return Ok(saved);
  }

  @override
  Future<Result<OrderSwapRecord, SwapFailure>> markBroadcastUnknown(
    String localId,
  ) async {
    journal.add('markUnknown');
    if (markUnknownFailure case final failure?) return Err(failure);
    final record = records[localId];
    if (record == null) return const Err(SwapOrderNotFoundFailure());
    if (record.localStatus != OrderSwapLocalStatus.readyToBroadcast) {
      return const Err(SwapInvalidStateFailure());
    }
    final deadline = record.order?.confirmationDeadline;
    if (deadline == null || !deadline.isAfter(now())) {
      return const Err(SwapOrderExpiredFailure());
    }
    var marked = record.withPayinState(
      status: OrderSwapLocalStatus.broadcastUnknown,
    );
    if (savedInstead case final other?) {
      marked = marked.withPayinState(
        status: OrderSwapLocalStatus.broadcastUnknown,
        signedTransaction: other,
      );
    }
    update(marked);
    return Ok(marked);
  }

  @override
  Future<Result<OrderSwapRecord, SwapFailure>> markPayinBroadcast({
    required String localId,
    required String transactionId,
  }) async {
    journal.add('markBroadcast:$transactionId');
    if (markBroadcastError case final error?) throw error;
    final record = records[localId];
    if (record == null) return const Err(SwapOrderNotFoundFailure());
    final marked = record.withPayinState(
      status: OrderSwapLocalStatus.payinBroadcast,
      transactionId: transactionId,
    );
    update(marked);
    return Ok(marked);
  }

  @override
  Stream<Result<OrderSwapRecord, SwapFailure>> watchOrder(String localId) {
    late final StreamController<Result<OrderSwapRecord, SwapFailure>>
    controller;
    StreamSubscription<OrderSwapRecord>? changes;
    controller = StreamController(
      onListen: () {
        changes = _changes.stream
            .where((record) => record.localId == localId)
            .listen((record) => controller.add(Ok(record)));
        final record = records[localId];
        if (record == null) {
          controller.add(const Err(SwapOrderNotFoundFailure()));
        } else {
          controller.add(Ok(record));
        }
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  /// Ends every watch, as the wallet's store would on close.
  Future<void> close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('SwapFacade.${invocation.memberName} used');
}

/// A record of the wallet's swap orders: a Lightning payment from Liquid of [amount] sats to [destination], in [status].
OrderSwapRecord paymentRecord({
  String localId = 'local-1',
  required String destination,
  String fallback = 'lq1refund',
  BigInt? amount,
  BigInt? payin,
  BigInt? payout,
  String? walletId = 'instant',
  String? note = 'RoboSats',
  OrderSwapPurpose purpose = OrderSwapPurpose.sendLightning,
  DateTime? createdAt,
  DateTime? deadline,
  OrderSwapLocalStatus status = OrderSwapLocalStatus.awaitingUserConfirmation,
  String payinAddress = 'lq1payin1',
  String? signed,
  String? transactionId,
  String payinStatus = 'pending',
  bool withOrder = true,
}) {
  final requested = amount ?? BigInt.from(600);
  final created = createdAt ?? testNow;
  return OrderSwapRecord(
    localId: localId,
    purpose: purpose,
    environment: OrderSwapEnvironment.mainnet,
    inNetwork: OrderSwapNetwork.liquid,
    outNetwork: OrderSwapNetwork.lightning,
    isInAmountFixed: false,
    requestedAmountSat: requested,
    destination: destination,
    fallback: fallback,
    createdAt: created,
    localStatus: status,
    sourceWalletId: walletId,
    note: note,
    signedPayinTransaction: signed,
    payinIsPsbt: signed == null ? null : false,
    localPayinTransactionId: transactionId,
    order: withOrder
        ? OrderSwap(
            orderId: 'order-$localId',
            orderNumber: 1,
            inNetwork: OrderSwapNetwork.liquid,
            outNetwork: OrderSwapNetwork.lightning,
            payinAmountSat: payin ?? BigInt.from(603),
            payoutAmountSat: payout ?? requested,
            payinCurrency: 'LBTC',
            payoutCurrency: 'BTC',
            payinMethod: 'liquid',
            payoutMethod: 'lightning',
            orderType: 'funding',
            orderStatus: 'pending',
            payinStatus: payinStatus,
            payoutStatus: 'pending',
            messageCode: 'ok',
            createdAt: created,
            confirmationDeadline:
                deadline ?? created.add(const Duration(minutes: 10)),
            liquidAddress: payinAddress,
            lightningInvoice: destination,
          )
        : null,
  );
}

/// The wallet's `LiquidWalletRepository` for a payment: it builds a fake transaction of the amount asked to the address asked, reads it back, and signs it into a fake signed text. Nothing real is built or signed.
final class FakePayingLiquid implements LiquidWalletRepository {
  final Journal journal;
  int fee = 26;
  Object? buildError;
  Object? signError;

  /// The amount the built transaction sends to the address asked, as read back (by default, the amount asked).
  int Function(int asked)? sentInstead;
  var _builds = 0;
  final Map<String, int> _amounts = {};

  FakePayingLiquid(this.journal);

  @override
  Future<String> buildPset({
    required String walletId,
    required String address,
    int? amountSat,
    required RelativeFee feeRate,
    bool? drain,
  }) async {
    journal.add('build:$address:$amountSat:${feeRate.satPerKwu}');
    if (buildError case final error?) throw error;
    _builds++;
    final pset = 'pset$_builds';
    _amounts[pset] = amountSat ?? 0;
    return pset;
  }

  @override
  Future<int> getAmountSentToAddress({
    required String pset,
    required String address,
    required String walletId,
  }) async {
    final asked = _amounts[pset] ?? (throw StateError('unknown pset'));
    return sentInstead?.call(asked) ?? asked;
  }

  @override
  Future<(int, int)> getPsetSizeAndAbsoluteFees({required String pset}) async {
    if (!_amounts.containsKey(pset)) throw StateError('unknown pset');
    return (1000, fee);
  }

  @override
  Future<String> signPset({
    required String pset,
    required String walletId,
  }) async {
    journal.add('sign:$pset');
    if (signError case final error?) throw error;
    return 'signed-$pset';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('LiquidWalletRepository.${invocation.memberName} used');
}

/// The wallet's broadcast of a Liquid transaction: it journals the text it was given, and answers a fake transaction id or throws [error].
final class FakeBroadcast implements BroadcastLiquidTransactionUsecase {
  final Journal journal;
  Object? error;
  final List<bool?> networks = [];

  FakeBroadcast(this.journal);

  @override
  Future<String> execute(String signedPset, {bool? isTestnet}) async {
    journal.add('broadcast:$signedPset');
    networks.add(isTestnet);
    if (error case final error?) throw error;
    return 'txid-of-$signedPset';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The wallet's receive address use case: the last revealed address of the wallet asked, as the Send feature takes a refund address.
final class FakeRefundAddress implements GetReceiveAddressUsecase {
  final Journal journal;
  Object? error;
  final List<({String walletId, bool generateNew})> calls = [];

  FakeRefundAddress(this.journal);

  @override
  Future<WalletAddress> execute({
    required String walletId,
    bool generateNew = false,
  }) async {
    journal.add('refund-address');
    calls.add((walletId: walletId, generateNew: generateNew));
    if (error case final error?) throw error;
    return WalletAddress(
      walletId: walletId,
      index: 7,
      address: 'lq1refund',
      createdAt: testNow,
      updatedAt: testNow,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
