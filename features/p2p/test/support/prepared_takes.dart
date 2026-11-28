import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:primitives/primitives.dart';

import 'trade_orders.dart';

/// A take prepared as `TakeOrderUsecase.prepare` gives it (#119): the book's order 42 on temple, on mainnet, read by a robot that takes no part in it (`orderJson(1)`), with [description] and [changes] to that answer, and its terms built from that read, for [amount] of a [range] order, read at [readAt], with the taker fee [fee], by a robot of the external Garage Key unless [externalKey] is `false` (#318: « Store your garage key » only then).
Future<PreparedTake> preparedTake({
  String? description,
  Map<String, Object?> changes = const {},
  bool range = false,
  TakeAmount? amount,
  DateTime? readAt,
  double fee = takerFee,
  bool externalKey = true,
}) async {
  final order = await readOrder(
    orderJson(
      1,
      range: range,
      changes: {'description': description, ...changes},
    ),
  );
  final terms = switch (TradeTerms.takeRead(
    order,
    rangeAmount: amount?.amount,
    takerFee: fee,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  return PreparedTake(
    order: order,
    terms: terms,
    amount: amount,
    readAt: readAt ?? tradeNow,
    externalKey: externalKey,
  );
}
