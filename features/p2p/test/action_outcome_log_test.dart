import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/usecases/trade/action_outcome_log.dart';
import 'package:robosats/robosats.dart';

/// A cause whose text holds what a line must never carry.
final class _Leaky {
  const _Leaky();

  @override
  String toString() => 'order 4242 of 21000 sats at host.onion';
}

/// A refusal of a use case, as `MakeRefusal` and `TakeRefusal` are: a type with a cause.
final class _Refused {
  const _Refused(this.cause);

  final Object cause;

  @override
  String toString() => 'refused: $cause';
}

/// The colour codes around a line printed to the console.
final RegExp _colour = RegExp(r'\x1b\[[0-9;]*m');

/// Every message of a line of the make and the take: `P2P make|take[ resolved]: <words> (<words, numbers, statuses by hundred>)`.
final RegExp _fixedWords = RegExp(
  r'^P2P (?:make|take)(?: resolved)?: [A-Za-z]+(?: [A-Za-z]+)? '
  r'\((?:[A-Za-z_]+|[0-9]{1,5}|[1-9]xx)(?:,? (?:[A-Za-z_]+|[0-9]{1,5}|[1-9]xx))*\)$',
);

void main() {
  group('causeOf', () {
    test('none for no cause', () {
      expect(ActionOutcomeLog.causeOf(null), 'none');
    });

    test('an outcome unknown and a refusal, with their cause', () {
      expect(
        ActionOutcomeLog.causeOf(
          const OrderActionOutcomeUnknown(CoordinatorTimedOut()),
        ),
        'unknown, CoordinatorTimedOut',
      );
      expect(
        ActionOutcomeLog.causeOf(
          const OrderActionRefused(OrderRequestRefused(1038)),
        ),
        'refused, OrderRequestRefused 1038',
      );
    });

    test(
      'a refused signature, with its code, so that a real attempt tells which refusal it met (GHSA-22q8-9ghc-jg3h)',
      () {
        for (final (reason, said) in [
          (ActionSignatureRefusal.invalid, '1048'),
          (ActionSignatureRefusal.missing, '1059'),
          (ActionSignatureRefusal.clockSkew, '1060'),
          (ActionSignatureRefusal.otherCoordinator, '1061'),
          (ActionSignatureRefusal.notSigned, 'notSigned'),
        ]) {
          expect(
            ActionOutcomeLog.causeOf(
              OrderActionRefused(ActionSignatureRefused(reason)),
            ),
            'refused, ActionSignatureRefused $said',
          );
        }
      },
    );

    test('an unexpected status, by hundred only', () {
      expect(
        ActionOutcomeLog.causeOf(const CoordinatorUnexpectedStatus(503)),
        'status 5xx',
      );
      expect(
        ActionOutcomeLog.causeOf(
          const OrderActionOutcomeUnknown(CoordinatorUnexpectedStatus(418)),
        ),
        'unknown, status 4xx',
      );
    });

    test('the field of a malformed answer, when it is a field name', () {
      expect(
        ActionOutcomeLog.causeOf(
          const CoordinatorResponseMalformed('bond_invoice'),
        ),
        'malformed bond_invoice',
      );
      for (final field in [
        '',
        'Bond_invoice',
        'bond invoice',
        'bond-invoice',
        'id 4242',
        'lnbc1fakeinvoicefortests',
        'a' * 41,
      ]) {
        expect(
          ActionOutcomeLog.causeOf(CoordinatorResponseMalformed(field)),
          'CoordinatorResponseMalformed',
          reason: 'a field that is not a name: its type only',
        );
      }
      expect(
        ActionOutcomeLog.causeOf(CoordinatorResponseMalformed('a' * 40)),
        'malformed ${'a' * 40}',
      );
    });

    test('the code of a refusal, from 0 to 99999 only', () {
      expect(
        ActionOutcomeLog.causeOf(const OrderRequestRefused(0)),
        'OrderRequestRefused 0',
      );
      expect(
        ActionOutcomeLog.causeOf(const OrderRequestRefused(99999)),
        'OrderRequestRefused 99999',
      );
      for (final code in [null, -1, 100000, 4242424242]) {
        expect(
          ActionOutcomeLog.causeOf(OrderRequestRefused(code)),
          'OrderRequestRefused',
        );
      }
    });

    test('any other cause: its type, never its text', () {
      expect(
        ActionOutcomeLog.causeOf(const CoordinatorTransportBusy()),
        'CoordinatorTransportBusy',
      );
      expect(ActionOutcomeLog.causeOf(const _Leaky()), '_Leaky');
      expect(
        ActionOutcomeLog.causeOf(StateError('http://host.onion/api/make/')),
        'StateError',
      );
      expect(
        ActionOutcomeLog.causeOf(
          const OrderActionRefused(OrderNotParticipant()),
        ),
        'refused, OrderNotParticipant',
      );
    });
  });

  group('the lines', () {
    final lines = <String>[];
    late DebugPrintCallback previous;
    setUp(() {
      lines.clear();
      previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    });
    tearDown(() => debugPrint = previous);

    /// The message of each line of the make and the take written since [setUp].
    List<String> messages() => [
      for (final line in lines)
        for (final column in line.replaceAll(_colour, '').split('\t'))
          if (column.startsWith('P2P ')) column,
    ];

    test('answered: the issue and the cause, word for word', () {
      ActionOutcomeLog.answered(
        'make',
        'refused',
        const OrderActionRefused(OrderRequestRefused(1038)),
      );
      ActionOutcomeLog.answered('make', 'answered', null);
      ActionOutcomeLog.answered(
        'take',
        'pending',
        const OrderActionOutcomeUnknown(CoordinatorUnexpectedStatus(502)),
      );
      ActionOutcomeLog.answered('take', 'answered OrderTakeStarted', null);
      ActionOutcomeLog.answered('take', 'notSent', const _Leaky());
      expect(messages(), [
        'P2P make: refused (refused, OrderRequestRefused 1038)',
        'P2P make: answered (none)',
        'P2P take: pending (unknown, status 5xx)',
        'P2P take: answered OrderTakeStarted (none)',
        'P2P take: notSent (_Leaky)',
      ]);
    });

    test('notSent: the type of the refusal only', () {
      ActionOutcomeLog.notSent('make', const _Refused(_Leaky()));
      ActionOutcomeLog.notSent('take', const _Refused(OrderRequestRefused(7)));
      expect(messages(), [
        'P2P make: notSent (_Refused)',
        'P2P take: notSent (_Refused)',
      ]);
    });

    test('resolved: the issue and the reason, word for word', () {
      ActionOutcomeLog.resolved('make', 'pending unread', 'orderUnread');
      ActionOutcomeLog.resolved(
        'make',
        'started',
        'robotUnread ${ActionOutcomeLog.causeOf(const CoordinatorUnexpectedStatus(500))}',
      );
      ActionOutcomeLog.resolved('take', 'notMade', 'public');
      expect(messages(), [
        'P2P make resolved: pending unread (orderUnread)',
        'P2P make resolved: started (robotUnread status 5xx)',
        'P2P take resolved: notMade (public)',
      ]);
    });

    test('resolvedOnce: once per action, issue and key in a run', () {
      final first = Object();
      final second = Object();
      ActionOutcomeLog.resolvedOnce('take', 'taker', 'bondStep', once: first);
      ActionOutcomeLog.resolvedOnce('take', 'taker', 'bondStep', once: first);
      ActionOutcomeLog.resolvedOnce('take', 'taker', 'chatting', once: first);
      ActionOutcomeLog.resolvedOnce('take', 'taker', 'bondStep', once: second);
      ActionOutcomeLog.resolvedOnce('take', 'notMade', 'public', once: first);
      expect(messages(), [
        'P2P take resolved: taker (bondStep)',
        'P2P take resolved: taker (bondStep)',
        'P2P take resolved: notMade (public)',
      ]);
    });

    test('every line is fixed words, type names and small figures only', () {
      final causes = <Object?>[
        null,
        const _Leaky(),
        StateError('token a-credential'),
        const CoordinatorUnexpectedStatus(503),
        const CoordinatorResponseMalformed('premium'),
        const CoordinatorResponseMalformed('21000 sats'),
        const OrderRequestRefused(1038),
        const OrderRequestRefused(123456789),
        const OrderActionOutcomeUnknown(
          CoordinatorResponseMalformed('Bad Key'),
        ),
        const OrderActionRefused(OrderRequestRefused(-4)),
      ];
      for (final cause in causes) {
        ActionOutcomeLog.answered('make', 'pending', cause);
        ActionOutcomeLog.answered('take', 'answered OrderNotTaken', cause);
        ActionOutcomeLog.notSent('take', cause ?? const _Leaky());
      }
      final written = messages();
      expect(written, hasLength(causes.length * 3));
      for (final message in written) {
        expect(message, matches(_fixedWords));
        for (final leak in [
          '4242',
          '21000',
          'host',
          'onion',
          'token',
          'credential',
          '123456789',
          '-4',
          'Bad',
          '503',
        ]) {
          expect(message, isNot(contains(leak)));
        }
      }
    });
  });
}
