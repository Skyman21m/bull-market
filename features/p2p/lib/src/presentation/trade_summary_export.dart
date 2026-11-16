import 'dart:convert';

import 'package:robosats/robosats.dart';

/// « Export trade summary » of the official client (`TradeBox/TradeSummary.tsx`, `onClickExport`, commit ff1998c): what it saves as `order<id>-summary.json`, and copies to the clipboard on a phone (`utils/saveFile.ts`), `JSON.stringify(summary, null, 2)`.
///
/// The reference writes the coordinator's objects as it received them; Bull Market writes what it read of them, checked and bounded, under the coordinator's keys and in its order (`Logics.summarize_trade`, `api/logics.py:2047-2139`): a field the app does not read (`routing_fee_sats`, always 0, of an on-chain payout) is not written, and a date is written in UTC with its milliseconds.
abstract final class TradeSummaryExport {
  /// The export of [summary] for the order [orderId] of the coordinator [coordinator] (its long alias), in [currencyCode], for the robot [robot] (its nickname).
  static Map<String, Object?> of(
    TradeSummary summary, {
    required String coordinator,
    required int orderId,
    required String currencyCode,
    required String robot,
  }) => {
    'coordinator': coordinator,
    'order_id': orderId,
    'currency': currencyCode,
    'robot': robot,
    'role': summary.isMaker ? 'maker' : 'taker',
    'maker': _side(summary.maker),
    'taker': _side(summary.taker),
    'platform': {
      'contract_exchange_rate': ?_number(summary.contractExchangeRate),
      'contract_timestamp': ?summary.contractTimestamp
          ?.toUtc()
          .toIso8601String(),
      'contract_total_time': ?_seconds(summary.contractTotalTime),
      'routing_budget_sats': ?_number(summary.routingBudgetSats),
      'trade_revenue_sats': ?summary.tradeRevenueSats,
    },
  };

  /// The text copied: two spaces of indent, as `JSON.stringify(summary, null, 2)`.
  static String text(Map<String, Object?> exported) =>
      const JsonEncoder.withIndent('  ').convert(exported);

  static Map<String, Object?>? _side(TradeSideSummary? side) {
    if (side == null) return null;
    return {
      'trade_fee_percent': ?_number(side.tradeFeeFraction),
      'bond_size_sats': ?side.bondSats?.value.toInt(),
      'bond_size_percent': ?_number(side.bondPercent),
      'is_buyer': side.isBuyer,
      if (side.isBuyer) ...{
        'sent_fiat': ?_number(side.fiatAmount),
        'received_sats': ?side.receivedSats?.value.toInt(),
        'payment_hash': ?side.paymentHash,
        'preimage': ?side.preimage,
        'trade_fee_sats': ?side.tradeFeeSats,
        if (side.isSwap) ...{
          'is_swap': true,
          'received_onchain_sats': ?side.receivedOnchainSats?.value.toInt(),
          'address': ?side.address,
          'txid': ?side.txid,
          'mining_fee_sats': ?side.miningFeeSats?.value.toInt(),
          'swap_fee_sats': ?side.swapFeeSats?.value.toInt(),
          'swap_fee_percent': ?_number(side.swapFeePercent),
        },
      } else ...{
        'sent_sats': ?side.sentSats?.value.toInt(),
        'received_fiat': ?_number(side.fiatAmount),
        'trade_fee_sats': ?side.tradeFeeSats,
      },
    };
  }

  /// A duration in seconds, as the coordinator gives `contract_total_time`.
  static num? _seconds(Duration? duration) => duration == null
      ? null
      : _number(duration.inMicroseconds / Duration.microsecondsPerSecond);

  /// A whole number as an integer, as JavaScript writes `150` for `150.0`.
  static num? _number(double? value) => switch (value) {
    null => null,
    final value when value == value.truncateToDouble() && value.abs() < 1e15 =>
      value.toInt(),
    final value => value,
  };
}
