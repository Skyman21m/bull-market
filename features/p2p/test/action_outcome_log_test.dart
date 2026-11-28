import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart' show TradePosition;
import 'package:p2p/src/domain/trade/trade_make.dart' show MakePendingReason;
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
        OutcomeAction.make,
        OutcomeAnswer.refused,
        const OrderActionRefused(OrderRequestRefused(1038)),
      );
      ActionOutcomeLog.answered(
        OutcomeAction.make,
        OutcomeAnswer.answered,
        null,
      );
      ActionOutcomeLog.answered(
        OutcomeAction.take,
        OutcomeAnswer.pending,
        const OrderActionOutcomeUnknown(CoordinatorUnexpectedStatus(502)),
      );
      ActionOutcomeLog.answered(
        OutcomeAction.take,
        OutcomeAnswer.takeStarted,
        null,
      );
      ActionOutcomeLog.answered(
        OutcomeAction.take,
        OutcomeAnswer.notSent,
        const _Leaky(),
      );
      expect(messages(), [
        'P2P make: refused (refused, OrderRequestRefused 1038)',
        'P2P make: answered (none)',
        'P2P take: pending (unknown, status 5xx)',
        'P2P take: answered OrderTakeStarted (none)',
        'P2P take: notSent (_Leaky)',
      ]);
    });

    test('notSent: the type of the refusal only', () {
      ActionOutcomeLog.notSent(OutcomeAction.make, const _Refused(_Leaky()));
      ActionOutcomeLog.notSent(
        OutcomeAction.take,
        const _Refused(OrderRequestRefused(7)),
      );
      expect(messages(), [
        'P2P make: notSent (_Refused)',
        'P2P take: notSent (_Refused)',
      ]);
    });

    test('resolved: the issue and the reason, word for word', () {
      ActionOutcomeLog.resolved(
        OutcomeAction.make,
        OutcomeResolution.pending,
        OutcomeReason.orderUnread,
        pending: MakePendingReason.unread,
      );
      ActionOutcomeLog.resolved(
        OutcomeAction.make,
        OutcomeResolution.started,
        OutcomeReason.robotUnread,
        cause: const CoordinatorUnexpectedStatus(500),
      );
      ActionOutcomeLog.resolvedAt(
        OutcomeAction.take,
        OutcomeResolution.notMade,
        TradePosition.public,
      );
      expect(messages(), [
        'P2P make resolved: pending unread (orderUnread)',
        'P2P make resolved: started (robotUnread status 5xx)',
        'P2P take resolved: notMade (public)',
      ]);
    });

    test('resolvedOnceAt: once per action, issue and key in a run', () {
      final first = Object();
      final second = Object();
      void once(OutcomeResolution issue, TradePosition position, Object key) =>
          ActionOutcomeLog.resolvedOnceAt(
            OutcomeAction.take,
            issue,
            position,
            once: key,
          );
      once(OutcomeResolution.taker, TradePosition.bondStep, first);
      once(OutcomeResolution.taker, TradePosition.bondStep, first);
      once(OutcomeResolution.taker, TradePosition.chatting, first);
      once(OutcomeResolution.taker, TradePosition.bondStep, second);
      once(OutcomeResolution.notMade, TradePosition.public, first);
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
        ActionOutcomeLog.answered(
          OutcomeAction.make,
          OutcomeAnswer.pending,
          cause,
        );
        ActionOutcomeLog.answered(
          OutcomeAction.take,
          OutcomeAnswer.notTaken,
          cause,
        );
        ActionOutcomeLog.notSent(OutcomeAction.take, cause ?? const _Leaky());
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

  group('no caller can write a text of its own (review of #303, S2)', () {
    // Tests run with the package directory as working directory.
    const path = 'lib/src/domain/usecases/trade/action_outcome_log.dart';

    test(
      'no public method or constructor of the log or of its enums takes a String: every parameter is one of the listed types, an `Object` only where it is written by its type or not at all',
      () {
        final offences = _parameterOffences(File(path).readAsStringSync());
        expect(offences.checked, containsAll(_publicMethods));
        expect(offences.found, isEmpty);
      },
    );

    test(
      'the check sees a String, an untyped or an unlisted parameter, in a class, an enum, an extension, a mixin or a top-level function, and any other public declaration (review of the lot, R4)',
      () {
        for (final (source, offence) in [
          (
            'abstract final class L { static void resolved(String reason) {} }',
            'L.resolved(reason: String)',
          ),
          (
            'abstract final class L { static void resolved(reason) {} }',
            'L.resolved(reason: untyped)',
          ),
          (
            'abstract final class L { static void resolved({required String? reason}) {} }',
            'L.resolved(reason: String?)',
          ),
          (
            'abstract final class L { static void resolved(Object reason) {} }',
            'L.resolved(reason: Object)',
          ),
          (
            'enum E { a; static E of(String text) => a; }',
            'E.of(text: String)',
          ),
          (
            'abstract final class L { L.of(String text); }',
            'L.of(text: String)',
          ),
          ('void say(String text) {}', '<top level>.say(text: String)'),
          (
            'extension Said on OutcomeAction { void say(String text) {} }',
            'Said.say(text: String)',
          ),
          (
            'extension on OutcomeAction { void say(String text) {} }',
            '<extension>.say(text: String)',
          ),
          ('mixin Says { void say(String text) {} }', 'Says.say(text: String)'),
          ('final say = (String text) => text;', 'say: unlisted declaration'),
          ('typedef Say = void Function(String);', 'Say: unlisted declaration'),
          ('extension type Said(String text) {}', 'unlisted declaration'),
          ('void _said(String text) {}', null),
        ]) {
          expect(_parameterOffences(source).found, [?offence], reason: source);
        }
      },
    );

    test(
      'the words of every answer, resolution and reason are fixed words',
      () {
        for (final words in [
          for (final answer in OutcomeAnswer.values) answer.words,
          for (final resolution in OutcomeResolution.values) resolution.name,
          for (final reason in OutcomeReason.values) reason.name,
        ]) {
          expect(words, matches(RegExp(r'^[A-Za-z]+(?: [A-Za-z]+)?$')));
        }
      },
    );
  });
}

/// The public methods of [ActionOutcomeLog] and of its enums that the scan must see, so that a rename does not empty it.
const _publicMethods = {
  'ActionOutcomeLog.answered',
  'ActionOutcomeLog.notSent',
  'ActionOutcomeLog.resolved',
  'ActionOutcomeLog.resolvedAt',
  'ActionOutcomeLog.resolvedOnceAt',
  'ActionOutcomeLog.causeOf',
  'OutcomeAnswer.ofTake',
};

/// The types a parameter of a public method of the log may have: the log's own enums and the app's, and the package's answer of a take, each written by a name of its own.
const _allowedTypes = {
  'OutcomeAction',
  'OutcomeAnswer',
  'OutcomeResolution',
  'OutcomeReason',
  'MakePendingReason',
  'TradePosition',
  'TakeOrderOutcome',
};

/// The parameters that may be an `Object`: a cause or a refusal, written by its type or [ActionOutcomeLog.causeOf]'s fixed label, and the key of a line said once, never written.
const _objectParameters = {'cause', 'refusal', 'once'};

/// Every public method and constructor of the classes, enums, mixins and extensions of [source], and every public top-level function, with each parameter of theirs that is not of an allowed type, as `<type>.<member>(<parameter>: <type>)` (`<top level>` for a function); any other public declaration (a top-level variable, which could hold a function, a type alias) is an offence too, as `<name>: unlisted declaration`, and so is any extension type or other kind, public or not, as `unlisted declaration`.
({Set<String> checked, List<String> found}) _parameterOffences(String source) {
  final unit = parseString(content: source).unit;
  final checked = <String>{};
  final found = <String>[];

  void check(String owner, String name, ast.FormalParameterList? parameters) {
    checked.add('$owner.$name');
    for (final parameter
        in parameters?.parameters ?? const <ast.FormalParameter>[]) {
      final plain = switch (parameter) {
        ast.DefaultFormalParameter(:final parameter) => parameter,
        _ => parameter,
      };
      final label = plain.name?.lexeme ?? '';
      final type = switch (plain) {
        ast.SimpleFormalParameter(:final type?) => type.toSource(),
        _ => null,
      };
      final bare = type?.replaceAll('?', '');
      final allowed =
          _allowedTypes.contains(bare) ||
          (bare == 'Object' && _objectParameters.contains(label));
      if (!allowed) found.add('$owner.$name($label: ${type ?? 'untyped'})');
    }
  }

  for (final declaration in unit.declarations) {
    final (owner, members) = switch (declaration) {
      ast.ClassDeclaration(:final namePart, :final body) => (
        namePart.typeName.lexeme,
        switch (body) {
          ast.BlockClassBody(:final members) => members.toList(),
          _ => const <ast.ClassMember>[],
        },
      ),
      ast.EnumDeclaration(:final namePart, :final body) => (
        namePart.typeName.lexeme,
        body.members.toList(),
      ),
      ast.MixinDeclaration(:final name, :final body) => (
        name.lexeme,
        body.members.toList(),
      ),
      // An unnamed extension applies in this file only, but its members are checked all the same.
      ast.ExtensionDeclaration(:final name, :final body) => (
        name?.lexeme ?? '<extension>',
        body.members.toList(),
      ),
      _ => (null, const <ast.ClassMember>[]),
    };
    if (owner == null) {
      switch (declaration) {
        case ast.FunctionDeclaration(:final name, :final functionExpression)
            when !name.lexeme.startsWith('_'):
          check('<top level>', name.lexeme, functionExpression.parameters);
        case ast.FunctionDeclaration():
          break;
        case ast.TopLevelVariableDeclaration(:final variables):
          for (final variable in variables.variables) {
            if (!variable.name.lexeme.startsWith('_')) {
              found.add('${variable.name.lexeme}: unlisted declaration');
            }
          }
        case ast.GenericTypeAlias(:final name) ||
                ast.FunctionTypeAlias(:final name)
            when !name.lexeme.startsWith('_'):
          found.add('${name.lexeme}: unlisted declaration');
        case ast.GenericTypeAlias() || ast.FunctionTypeAlias():
          break;
        // An extension type, or any other kind, public or not.
        default:
          found.add('unlisted declaration');
      }
      continue;
    }
    for (final member in members) {
      final (name, parameters) = switch (member) {
        ast.MethodDeclaration(:final name, :final parameters) => (
          name.lexeme,
          parameters,
        ),
        ast.ConstructorDeclaration(:final name, :final parameters) => (
          name?.lexeme ?? '',
          parameters,
        ),
        _ => (null, null),
      };
      // An enum's constructors are called by its own values only.
      if (name == null ||
          name.startsWith('_') ||
          (member is ast.ConstructorDeclaration &&
              declaration is ast.EnumDeclaration &&
              member.factoryKeyword == null)) {
        continue;
      }
      check(owner, name, parameters);
    }
  }
  return (checked: checked, found: found);
}
