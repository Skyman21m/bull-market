import 'package:bull_logger/bull_logger.dart';
import 'package:bull_tor/tor.dart' show TorConnectFailure;
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart' show TradePosition;
import 'package:p2p/src/domain/trade/trade_make.dart' show MakePendingReason;
import 'package:p2p/src/domain/usecases/trade/action_outcome_log.dart';
import 'package:robosats/robosats.dart';

import 'support/key_output.dart';

/// What [captureKeyOutput] leaves of the support log's lines on how a request that acts, a make or a take ended (review of #303, C1): every form those lines take is left out, and a line of that shape that carries a secret between its brackets stays.
void main() {
  /// Every way `TorCoordinatorTransport` ends a line, after `P2P coordinator <method> ` (`_logAction`, `_logThrown`), with the types each may name.
  final transportEnds = [
    'refused before sending (url)',
    'refused before sending (credential on anonymous)',
    'refused before sending (headers)',
    'timed out at the deadline',
    'timed out before an attempt',
    'stopped (sessions closed)',
    'busy (no place)',
    for (final type in [
      'CoordinatorUnreachable',
      'CoordinatorTimedOut',
      'CoordinatorTransportFailed',
    ])
      'session not opened ($type)',
    'abandoned at the deadline',
    for (final reason in TorConnectFailure.values)
      'connection failed (${reason.name})',
    for (final type in DioExceptionType.values)
      for (final cause in ['SocketException', 'Null', '_TypeError'])
        'failed before headers (${type.name}, $cause)',
    'answer without status',
    for (var hundred = 1; hundred <= 5; hundred++) 'answered (${hundred}xx)',
    'answer too large',
    for (final type in ['CoordinatorResponseTooLarge', 'CoordinatorTimedOut'])
      'body not read ($type)',
    for (final type in ['StateError', '_TypeError', 'SocketException'])
      'threw ($type)',
  ];

  /// Causes as the use cases give them to [ActionOutcomeLog.answered].
  final causes = <Object?>[
    null,
    const CoordinatorTransportBusy(),
    const OrderActionOutcomeUnknown(CoordinatorTimedOut()),
    const OrderActionOutcomeUnknown(CoordinatorUnexpectedStatus(503)),
    const OrderActionRefused(OrderRequestRefused(1038)),
    const OrderActionRefused(CoordinatorResponseMalformed('bond_invoice')),
    const OrderActionRefused(OrderRequestRefused(null)),
  ];

  /// The reasons `MakeOrderUsecase` gives to the resolution of a make, with the causes it writes after them.
  final makeReasons = <(OutcomeReason, Object?)>[
    for (final reason in OutcomeReason.values)
      if (reason != OutcomeReason.robot && reason != OutcomeReason.robotUnread)
        (reason, null),
    (OutcomeReason.robot, const TradeKeyMissingFailure()),
    (OutcomeReason.robotUnread, const CoordinatorUnexpectedStatus(500)),
    (OutcomeReason.robotUnread, const OrderRequestRefused(1038)),
    (OutcomeReason.robotUnread, const CoordinatorResponseMalformed('nickname')),
    (OutcomeReason.robotUnread, const P2pStorageFailure()),
  ];

  /// Every line the code can write, written through the code that writes it where it is reachable ([ActionOutcomeLog]), and word for word for the transport's private helpers.
  void writeEveryForm() {
    for (final method in ['get', 'post', 'put', 'delete']) {
      for (final end in transportEnds) {
        log.fine('P2P coordinator $method $end');
      }
    }
    log.fine('P2P coordinator sessions closed (all)');
    log.fine('P2P coordinator sessions closed (one robot)');
    for (final cause in causes) {
      for (final answer in [
        OutcomeAnswer.notSent,
        OutcomeAnswer.refused,
        OutcomeAnswer.pending,
        OutcomeAnswer.answered,
      ]) {
        ActionOutcomeLog.answered(OutcomeAction.make, answer, cause);
      }
      for (final answer in [
        OutcomeAnswer.notSent,
        OutcomeAnswer.refused,
        OutcomeAnswer.pending,
        OutcomeAnswer.takeStarted,
        OutcomeAnswer.alreadyTaken,
        OutcomeAnswer.notTaken,
      ]) {
        ActionOutcomeLog.answered(OutcomeAction.take, answer, cause);
      }
    }
    for (final refusal in [
      'MakeCoordinatorNotOnNetwork',
      'MakePriceCheckChanged',
      'MakeRobotRefused',
      'MakeNotRecorded',
    ]) {
      log.fine('P2P make: notSent ($refusal)');
    }
    for (final refusal in [
      'TakeOrderGone',
      'TakePreparationGone',
      'TakeRobotNotPut',
      'TakeNotRecorded',
    ]) {
      log.fine('P2P take: notSent ($refusal)');
    }
    for (final (issue, pending) in [
      (OutcomeResolution.started, null),
      (OutcomeResolution.notMade, null),
      (OutcomeResolution.neverSent, null),
      for (final reason in MakePendingReason.values)
        (OutcomeResolution.pending, reason),
      (OutcomeResolution.noLongerPending, null),
    ]) {
      for (final (reason, cause) in makeReasons) {
        ActionOutcomeLog.resolved(
          OutcomeAction.make,
          issue,
          reason,
          pending: pending,
          cause: cause,
        );
      }
    }
    for (final position in TradePosition.values) {
      ActionOutcomeLog.resolvedAt(
        OutcomeAction.take,
        OutcomeResolution.taker,
        position,
      );
      ActionOutcomeLog.resolvedAt(
        OutcomeAction.take,
        OutcomeResolution.notMade,
        position,
      );
    }
  }

  test('every form of the lines is left out of the capture', () async {
    final output = await captureKeyOutput(() async => writeEveryForm());
    expect([
      for (final line in output.split('\n'))
        if (line.contains('P2P ')) line,
    ], isEmpty);
  });

  test(
    'a line of that shape that carries a secret between its brackets stays',
    () async {
      // Made up for this test, in the forms `expectNoKeyIn` looks for.
      const bech32Fragment = 'qpzry9x8gf2tvdw0s3jn54khc';
      final hex = '0123456789abcdef' * 4;
      final bytes = List.generate(32, (index) => index + 1);
      const base64 = 'RmFrZUtleUZvclRlc3RzT25seTAxMjM0NTY3';
      final probes = {
        'P2P take: answered (': 'P2P take: answered ($bech32Fragment)',
        'P2P make resolved: pending unread (':
            'P2P make resolved: pending unread (robotUnread $hex)',
        'P2P make: refused (': 'P2P make: refused (${bytes.join(',')})',
        'P2P coordinator post answered (':
            'P2P coordinator post answered ($base64)',
        // The same list with a space after each comma: more items than any line holds.
        'P2P take: refused (': 'P2P take: refused (${bytes.join(', ')})',
      };
      expect(bech32Fragment, hasLength(25));
      expect(hex, hasLength(64));
      final output = await captureKeyOutput(() async {
        for (final probe in probes.values) {
          log.fine(probe);
        }
      });
      for (final MapEntry(key: head, value: probe) in probes.entries) {
        expect(output.contains(head), isTrue, reason: probe);
      }
    },
  );
}
