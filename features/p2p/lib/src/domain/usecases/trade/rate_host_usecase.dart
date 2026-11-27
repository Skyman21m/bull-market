import 'dart:async';
import 'dart:math';

import 'package:bull_logger/bull_logger.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../robot_key_compute_port.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_chat_step.dart';
import '../../trade/trade_host_rating.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';

/// « Rate your host » (#95): the rating of the trade's coordinator, which the official client publishes on Nostr only (`TradeBox/Prompts/Successful.tsx:54-105`, commit ff1998c).
///
/// [fetchToken] asks the coordinator once for the token of the robot's Nostr key (`POST /api/review/`, `CoordinatorClient.fetchReviewToken`), through the robot's places in [RobotRequestLimiter], as the reference asks it once when it shows its stars; the request is signed by the robot's key, leased from [TradeKeyring] for it (GHSA-22q8-9ghc-jg3h), and a key that cannot be had sends nothing.
/// [publish] signs, apart ([RobotKeyComputePort.composeHostRating]), one event of kind 31986 with that token and the stars, and publishes it to the relays [nostrRelaysFor] chooses, through the robot's Tor sessions, all at once; once per call, never again: the reference sends each change of its stars once and waits for nothing.
/// Both only for a status that offers the rating ([ChatStepAction.rate]: the buyer at 14, from an order read) and of this trade.
/// What [publish] sends is public: anyone reading the relays learns that this robot's Nostr key rated this coordinator for this order, with these stars.
/// Nothing here is shown of the publication's outcome, as in the reference; nothing is stored; nothing of the token, the robot or the relays is logged.
final class RateHostUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final RobotKeyComputePort _compute;
  final NostrRelayTransport _relays;
  final Federation _federation;

  /// [Random.secure] in the app: the choice of relays.
  final Random _random;
  final TradeKeyring _keyring;

  const RateHostUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._compute,
    this._relays,
    this._federation,
    this._random,
    this._keyring,
  );

  /// The token with which the robot of [record] rates its coordinator, for [seen], the status shown.
  Future<Result<HostReviewToken, HostTokenNotGiven>> fetchToken(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    final trade = await _open(record, seen);
    if (trade == null) return const Err(HostTokenNotGiven());
    final identity = trade.robot.identity;
    final requests = _limiter.open(identity.sessionKey);
    try {
      final TradeKeyLease lease;
      switch (await _keyring.lease(trade)) {
        case Ok(:final value):
          lease = value;
        case Err():
          return const Err(HostTokenNotGiven());
      }
      try {
        final sent = await requests.send(
          record.network,
          trade.coordinator,
          () => _client.fetchReviewToken(
            identity: identity,
            key: lease.key,
            coordinator: trade.coordinator,
            network: record.network,
            nostrPublicKeyHex: identity.nostrKeyPair().publicKeyHex,
          ),
          isBusy: (answer) => switch (answer) {
            Err(failure: CoordinatorTransportBusy()) => true,
            _ => false,
          },
        );
        return switch (sent) {
          Ok(value: Ok(:final value)) => Ok(value),
          _ => const Err(HostTokenNotGiven()),
        };
      } finally {
        lease.close();
      }
    } finally {
      requests.close();
    }
  }

  /// Publishes [rating] of the coordinator of [record] with [token], for [seen], the status shown when the user tapped the star.
  Future<void> publish(
    TradeRecord record,
    TradeSeen seen,
    HostReviewToken token,
    HostRating rating,
  ) async {
    final trade = await _open(record, seen);
    if (trade == null) return;
    final composed = await _compute.composeHostRating(
      trade.robot.identity.nostrKeyPair(),
      token: token,
      coordinator: trade.coordinator,
      orderId: record.orderId,
      rating: rating,
      now: _reader.now(),
    );
    final OutgoingHostRating event;
    switch (composed) {
      case Ok(:final value):
        event = value;
      case Err():
        log.info('P2P host rating not composed');
        return;
    }
    final relays = nostrRelaysFor(
      trade.coordinator,
      _federation,
      record.network,
      _random,
    );
    final robot = trade.robot.identity.sessionKey;
    await Future.wait([
      for (final relay in relays) _relays.publish(relay, event, robot: robot),
    ]);
  }

  /// The trade of [record], opened, when [seen] offers the rating and is this trade's; `null` otherwise.
  Future<OpenTrade?> _open(TradeRecord record, TradeSeen seen) async {
    final shown = seen.order;
    if (shown == null || !ChatStepAction.rate.offeredAt(seen)) return null;
    if (await _reader.open(record) case TradeOpened(:final trade)
        when shown.id == trade.terms.orderId &&
            shown.coordinator == trade.terms.coordinator &&
            shown.network == trade.terms.network) {
      return trade;
    }
    return null;
  }
}
