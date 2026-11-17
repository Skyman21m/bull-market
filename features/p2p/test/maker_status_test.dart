import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cadence.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/maker_orders.dart';
import 'support/trade_orders.dart';

/// A maker's state machine (#178; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3): the statuses of an order made here, every pair of a position and an answer for a maker buyer and a maker seller against a table written out here from the reference (`api/logics.py`, `api/views.py`, `follow_invoices.py`, `clean_orders.py`, commit ff1998c), the contracts, and the maker's checks.
///
/// Every answer goes through the package's own parser (`readAnswer`), so only answers it accepts reach the state machine.
void main() {
  const b = TradeRole.buyer;
  const s = TradeRole.seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

  TradeTerms<MadeSide> termsOf(TradeRole role, {bool range = false}) =>
      madeTerms(role: role, range: range);

  /// The maker's answer at [status], its invoices made readable: the maker bond at 0, contract [take]'s escrow at 6 and 7 for a seller.
  Future<TradeAnswer> made(
    int status, {
    TradeRole role = b,
    bool range = false,
    int last = makerSats,
    RobotIdentity? taker,
    DateTime? deadline,
    double taken = 120,
    Bolt11TestInvoice? bond,
    Bolt11TestInvoice? escrow,
    int take = 0,
    Map<String, Object?> changes = const {},
  }) async {
    final bondInvoice = bond ?? makerBondInvoice();
    final escrowInvoice =
        escrow ?? makerEscrowInvoice(take: take, sats: makerEscrowOf(last));
    decoder
      ..add(bondInvoice)
      ..add(escrowInvoice);
    return readAnswer(
      makerOrderJson(
        status,
        role: role,
        range: range,
        last: last,
        taker: taker,
        deadline: deadline,
        taken: taken,
        bond: bondInvoice,
        escrow: escrowInvoice,
        changes: changes,
      ),
    );
  }

  TradeStatus first(
    TradeAnswer answer, {
    TradeTerms<MadeSide>? terms,
    DateTime? now,
  }) => TradeStatus.afterMake(
    answer,
    terms: terms ?? termsOf(b),
    now: now ?? tradeNow,
    reader: reader,
  );

  TradeStatus next(
    TradeStatus previous,
    TradeAnswer answer, {
    TradeTerms<MadeSide>? terms,
    DateTime? now,
  }) => TradeStatus.from(
    previous: previous,
    answer: answer,
    terms: terms ?? termsOf(previous.trail.role),
    now: now ?? tradeNow,
    reader: reader,
  );

  CheckedInvoice checkedOf(TradeStatus status) => switch (status.invoice) {
    final CheckedInvoice invoice => invoice,
    final other => fail('expected a checked invoice, got $other'),
  };

  /// The order public after its bond locked.
  Future<TradeStatus> published(TradeRole role, {bool range = false}) async {
    final terms = termsOf(role, range: range);
    final bond = first(
      await made(0, role: role, range: range),
      terms: terms,
    );
    return next(
      bond,
      await made(1, role: role, range: range),
      terms: terms,
    );
  }

  /// Contract 0 at 6, taken by [peer].
  Future<TradeStatus> taken(TradeRole role, {bool range = false}) async {
    final terms = termsOf(role, range: range);
    return next(
      await published(role, range: range),
      await made(6, role: role, range: range),
      terms: terms,
    );
  }

  group('the statuses of an order made here', () {
    test(
      '0: the maker bond, checked clean and payable within the bond\'s ceiling',
      () async {
        final status = first(await made(0));
        expect(status, isA<WaitingForMakerBond>());
        status as WaitingForMakerBond;
        expect(status.warnings, isEmpty);
        expect(status.position, TradePosition.makerBondStep);
        expect(status.deadline, madeAt.add(const Duration(seconds: 300)));
        expect(status.stepDuration, const Duration(seconds: 300));
        final bond = checkedOf(status);
        expect(bond.step, InvoiceStep.bond);
        expect(bond.amount, Sats.fromInt(makerBond));
        expect(bond.passedEveryCheck, isTrue);
        expect(status.trail.bondHash, bond.paymentHash);
        expect(status.trail.take, 0);
        expect(status.trail.takeDeadline, isNull);
        final terms = termsOf(b);
        expect(
          walletPaymentFor(
            accepted: terms.bondCeiling,
            status: status,
            step: InvoiceStep.bond,
            now: tradeNow,
          ),
          isA<WalletPaymentOffered>().having((o) => o.take, 'take', 0),
        );
        // A bond above the ceiling is asked: the wallet pays at most what was accepted.
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(makerBond - 1),
            status: status,
            step: InvoiceStep.bond,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>(),
        );
      },
    );

    test(
      'the first read is the bond, the order expired at 0, or 1043',
      () async {
        final expired = first(await made(5));
        expect(expired, isA<Expired>());
        expect(expired.warnings, isEmpty);
        final cancelled = first(const TradeOrderCancelled());
        expect(cancelled, isA<Cancelled>());
        expect((cancelled as Cancelled).bondMayHaveBeenLost, isFalse);
        expect(cancelled.warnings, isEmpty);
      },
    );

    test(
      '1 and 2: public, paused, public again, each with its deadline',
      () async {
        final public = await published(b);
        expect(public, isA<MakerOrderPublic>());
        public as MakerOrderPublic;
        expect(public.paused, isFalse);
        expect(public.backInBook, isFalse);
        expect(public.warnings, isEmpty);
        expect(public.deadline, madeAt.add(const Duration(seconds: 86340)));
        expect(public.invoice, isNull);
        final paused = next(public, await made(2));
        expect(paused, isA<MakerOrderPublic>());
        expect((paused as MakerOrderPublic).paused, isTrue);
        expect(paused.position, TradePosition.paused);
        expect(paused.warnings, isEmpty);
        final resumed = next(paused, await made(1));
        expect(resumed.position, TradePosition.public);
        expect(resumed.warnings, isEmpty);
        // The bond's hash stays pinned for the order's whole life.
        expect(resumed.trail.bondHash, makerBondInvoice().facts.paymentHash);
      },
    );

    test('a maker buyer from 6 to the end', () async {
      final both = await taken(b);
      expect(both, isA<WaitingForBoth>());
      both as WaitingForBoth;
      expect(both.warnings, isEmpty);
      expect(both.role, b);
      expect(both.escrow, isNull);
      expect(both.payoutAmount, Sats.fromInt(makerPayoutOf(makerSats)));
      expect(both.trail.take, 0);
      expect(both.trail.takeDeadline, deadline0);
      expect(both.trail.takerHashId, peer.hashId.hex);
      expect(both.trail.takenAmount, isNull);
      expect(both.rateGap, isNotNull);
      final escrow = next(both, await made(7));
      expect(escrow, isA<WaitingForEscrow>());
      expect(escrow.warnings, isEmpty);
      final payout = next(both, await made(8));
      expect(payout, isA<WaitingForPayout>());
      expect(payout.warnings, isEmpty);
      final chat = next(payout, await made(9));
      expect(chat, isA<Chatting>());
      expect((chat as Chatting).amount.value, 100);
      expect(chat.rateGap, isNotNull);
      expect(chat.warnings, isEmpty);
      final sent = next(chat, await made(10));
      expect((sent as Chatting).fiatSent, isTrue);
      final paying = next(sent, await made(13));
      expect(paying, isA<SendingSats>());
      final failed = next(paying, await made(15));
      expect(failed, isA<RoutingFailed>());
      final done = next(failed, await made(14));
      expect(done, isA<Succeeded>());
      for (final status in [sent, paying, failed, done]) {
        expect(status.warnings, isEmpty, reason: '$status');
      }
    });

    test('17 and 18 by side: for a maker, 17 is lost and 18 won', () async {
      for (final role in [b, s]) {
        final dispute = next(
          next(await taken(role), await made(9, role: role)),
          await made(11, role: role),
        );
        expect(dispute, isA<InDispute>());
        final resolution = next(dispute, await made(16, role: role));
        expect(resolution, isA<WaitingDisputeResolution>());
        final lost = next(resolution, await made(17, role: role));
        expect(lost, isA<DisputeLost>());
        expect(lost.position, TradePosition.makerLostDispute);
        final won = next(resolution, await made(18, role: role));
        expect(won, isA<DisputeWon>());
        expect(won.position, TradePosition.takerLostDispute);
        for (final status in [dispute, resolution, lost, won]) {
          expect(status.warnings, isEmpty, reason: '$role $status');
        }
      }
    });

    test(
      'a maker seller locks the escrow of its contract at 6 and 7',
      () async {
        final both = await taken(s);
        expect(both.warnings, isEmpty);
        final escrow = checkedOf(both);
        expect(escrow.step, InvoiceStep.escrow);
        expect(escrow.amount, Sats.fromInt(makerEscrowOf(makerSats)));
        expect(both.trail.escrowHash, escrow.paymentHash);
        final terms = termsOf(s);
        final ceiling = terms.side.maker.escrowCeilingFor(null);
        expect(ceiling, isNotNull);
        expect(
          walletPaymentFor(
            accepted: escrow.amount,
            status: both,
            step: InvoiceStep.escrow,
            now: tradeNow,
          ),
          isA<WalletPaymentOffered>().having((o) => o.take, 'take', 0),
        );
        final atSeven = next(both, await made(7, role: s));
        expect(atSeven.warnings, isEmpty);
        expect(checkedOf(atSeven).paymentHash, escrow.paymentHash);
        final waits = next(atSeven, await made(9, role: s));
        expect(waits.warnings, isEmpty);
      },
    );

    test('the cadence of a maker\'s statuses is the reference\'s', () {
      const second = Duration(seconds: 1);
      expect(
        TradeCadence.referenceDelay(TradePosition.makerBondStep),
        second * 3,
      );
      expect(TradeCadence.referenceDelay(TradePosition.public), second * 35);
      expect(TradeCadence.referenceDelay(TradePosition.paused), second * 180);
      expect(
        TradeCadence.delayAfter(TradePosition.makerBondStep, onScreen: true),
        second * 5,
      );
      expect(
        TradeCadence.delayAfter(TradePosition.makerBondStep, onScreen: false),
        second * 15,
      );
      expect(
        TradeCadence.delayAfter(TradePosition.public, onScreen: true),
        second * 35,
      );
      expect(
        TradeCadence.delayAfter(TradePosition.public, onScreen: false),
        second * 175,
      );
      expect(
        TradeCadence.delayAfter(TradePosition.paused, onScreen: true),
        second * 180,
      );
      expect(
        TradeCadence.delayAfter(TradePosition.paused, onScreen: false),
        second * 900,
      );
    });
  });

  group('the trail of a maker', () {
    test(
      'restored as it was written, and refused when it is not one a trail writes',
      () async {
        final both = await taken(s, range: true);
        final record = both.trail.record;
        final terms = termsOf(s, range: true);
        expect(switch (TradeTrail.restore(
          record,
          terms: terms,
          now: tradeNow,
        )) {
          Ok(:final value) => value == both.trail && value.made,
          Err() => false,
        }, isTrue);
        TradeTrailRecord changed({
          int? take,
          int? takeDeadlineMicros,
          String? takerHashId,
          double? takenAmount,
          bool clearDeadline = false,
        }) => TradeTrailRecord(
          version: record.version,
          network: record.network,
          coordinatorAlias: record.coordinatorAlias,
          orderId: record.orderId,
          role: record.role,
          position: record.position,
          readAtMicros: record.readAtMicros,
          bondHash: record.bondHash,
          escrowHash: record.escrowHash,
          deadlineMicros: record.deadlineMicros,
          bondStepSeenAtMicros: record.bondStepSeenAtMicros,
          bondStepDeadlineMicros: record.bondStepDeadlineMicros,
          breached: record.breached,
          historyUnknown: record.historyUnknown,
          take: take ?? record.take,
          takeDeadlineMicros: clearDeadline
              ? null
              : takeDeadlineMicros ?? record.takeDeadlineMicros,
          takerHashId: takerHashId ?? record.takerHashId,
          takenAmount: takenAmount ?? record.takenAmount,
        );
        for (final (label, bad) in [
          ('take below 0', changed(take: -1)),
          (
            'a next contract with no deadline',
            changed(take: 1, clearDeadline: true),
          ),
          ('a taker that is no hash id', changed(takerHashId: 'A' * 64)),
          ('an amount of 0', changed(takenAmount: 0)),
          ('an amount of 10^10', changed(takenAmount: 1e10)),
          ('an amount that is no figure', changed(takenAmount: double.nan)),
          ('a deadline out of range', changed(takeDeadlineMicros: -1)),
        ]) {
          expect(
            TradeTrail.restore(bad, terms: terms, now: tradeNow),
            isA<Err>(),
            reason: label,
          );
        }
        // A contract on a taker's trail is no trail a taker writes.
        final taker = await tradeTerms(role: s);
        final takerRecord = TradeStatus.beforeFirstRead(
          TradeTrail.forPendingTake(taker, tradeNow),
        ).trail.record;
        TradeTrailRecord withContract({
          int take = 0,
          int? deadline,
          String? hash,
          double? amount,
        }) => TradeTrailRecord(
          version: takerRecord.version,
          network: takerRecord.network,
          coordinatorAlias: takerRecord.coordinatorAlias,
          orderId: takerRecord.orderId,
          role: takerRecord.role,
          position: takerRecord.position,
          readAtMicros: takerRecord.readAtMicros,
          bondHash: null,
          escrowHash: null,
          deadlineMicros: null,
          bondStepSeenAtMicros: null,
          bondStepDeadlineMicros: null,
          breached: false,
          historyUnknown: false,
          take: take,
          takeDeadlineMicros: deadline,
          takerHashId: hash,
          takenAmount: amount,
        );
        expect(
          TradeTrail.restore(withContract(), terms: taker, now: tradeNow),
          isA<Ok>(),
        );
        for (final bad in [
          withContract(take: 1, deadline: 1),
          withContract(deadline: 1),
          withContract(hash: peer.hashId.hex),
          withContract(amount: 100),
        ]) {
          expect(
            TradeTrail.restore(bad, terms: taker, now: tradeNow),
            isA<Err>(),
          );
        }
      },
    );

    test(
      'a maker\'s trail is never another side\'s: the terms of a take of the same order are refused',
      () async {
        final bond = first(await made(0));
        final taker = await tradeTerms();
        expect(bond.trail.isOf(taker), isFalse);
        final after = TradeStatus.from(
          previous: bond,
          answer: await made(1),
          terms: taker,
          now: tradeNow,
          reader: reader,
        );
        expect(after.has<TradeOrderMismatch>(), isTrue);
        expect(after.trail, bond.trail);
      },
    );
    test(
      'a taker told « you are the maker » of an order of the other type, on its own side, is refused (the taker\'s guard, unchanged)',
      () async {
        // A taker buyer of a sell order; the answer says this robot made a buy order, and so buys: only `is_maker` tells it.
        final taker = await tradeTerms();
        final before = TradeStatus.beforeFirstRead(
          TradeTrail.forPendingTake(taker, tradeNow),
        );
        final after = TradeStatus.from(
          previous: before,
          answer: await made(1),
          terms: taker,
          now: tradeNow,
          reader: reader,
        );
        expect(after.has<TradeRoleMismatch>(), isTrue);
        expect(after.trail.made, isFalse);
        expect(after.trail.breached, isTrue);
      },
    );

    test('a trail is restored only at a position of its own side', () async {
      final maker = first(await made(0)).trail.record;
      final takerTerms = await tradeTerms();
      final taker = TradeStatus.beforeFirstRead(
        TradeTrail.forPendingTake(takerTerms, tradeNow),
      ).trail.record;
      TradeTrailRecord at(
        TradeTrailRecord record,
        String position, {
        String earlier = '',
        bool late = false,
        int take = 0,
      }) => TradeTrailRecord(
        version: record.version,
        network: record.network,
        coordinatorAlias: record.coordinatorAlias,
        orderId: record.orderId,
        role: record.role,
        position: position,
        readAtMicros: record.readAtMicros,
        bondHash: record.bondHash,
        escrowHash: null,
        deadlineMicros: null,
        bondStepSeenAtMicros: null,
        bondStepDeadlineMicros: null,
        breached: false,
        historyUnknown: false,
        take: take,
        takeDeadlineMicros: take > 0 ? 1 : null,
        earlierEscrows: earlier,
        seenLate: late,
      );
      for (final position in [
        'bondStep',
        'preTakeUnavailable',
        'publicAgain',
        'notAvailable',
      ]) {
        expect(
          TradeTrail.restore(
            at(maker, position),
            terms: termsOf(b),
            now: tradeNow,
          ),
          isA<Err>(),
          reason: position,
        );
      }
      for (final position in ['makerBondStep', 'public', 'paused']) {
        expect(
          TradeTrail.restore(
            at(taker, position),
            terms: takerTerms,
            now: tradeNow,
          ),
          isA<Err>(),
          reason: position,
        );
        expect(
          TradeTrail.restore(
            at(maker, position),
            terms: termsOf(b),
            now: tradeNow,
          ),
          isA<Ok>(),
          reason: position,
        );
      }
      // Earlier escrows and a contract seen late need a contract after the first, and well-formed hashes.
      final hash = 'a' * 64;
      expect(
        TradeTrail.restore(
          at(maker, 'chatting', earlier: '$hash;', late: true, take: 1),
          terms: termsOf(b),
          now: tradeNow,
        ),
        isA<Ok>(),
      );
      for (final (label, record) in [
        (
          'earlier escrows at contract 0',
          at(maker, 'chatting', earlier: '$hash;'),
        ),
        ('seen late at contract 0', at(maker, 'chatting', late: true)),
        ('no separator', at(maker, 'chatting', earlier: hash, take: 1)),
        ('a short hash', at(maker, 'chatting', earlier: 'abc;', take: 1)),
        (
          'an uppercase hash',
          at(maker, 'chatting', earlier: '${'A' * 64};', take: 1),
        ),
      ]) {
        expect(
          TradeTrail.restore(record, terms: termsOf(b), now: tradeNow),
          isA<Err>(),
          reason: label,
        );
      }
    });
  });

  group('the maker\'s edges', () {
    test(
      'are exactly those of the reference, as written out here apart from the table',
      () {
        TradePosition at(String name) => TradePosition.values.byName(name);
        final table = {
          for (final MapEntry(key: from, value: targets)
              in TradeEdges.makerSteps.entries)
            for (final MapEntry(key: to, value: roles) in targets.entries)
              (from, to): roles,
        };
        expect(table.length, _makerSteps.length);
        for (final (from, to, roles) in _makerSteps) {
          expect(table[(at(from), at(to))], roles, reason: '$from → $to');
        }
        // A maker is never at a pre-taker's positions.
        for (final position in [
          TradePosition.bondStep,
          TradePosition.preTakeUnavailable,
          TradePosition.publicAgain,
          TradePosition.notAvailable,
        ]) {
          expect(TradeEdges.makerSteps.containsKey(position), isFalse);
          for (final targets in TradeEdges.makerSteps.values) {
            expect(targets.containsKey(position), isFalse);
          }
        }
        // From 9 on, a maker's moves are a taker's.
        for (final position in [
          TradePosition.chatting,
          TradePosition.fiatSent,
          TradePosition.inDispute,
          TradePosition.waitingDisputeResolution,
          TradePosition.sendingSats,
          TradePosition.routingFailed,
        ]) {
          expect(TradeEdges.makerSteps[position], TradeEdges.steps[position]);
        }
      },
    );

    test('allowsMade is the closure of the written-out table, by role', () {
      for (final role in [b, s]) {
        final reachable = _closure(role);
        for (final from in TradePosition.values) {
          for (final to in TradePosition.values) {
            final expected =
                from == to ||
                (from == TradePosition.start
                    ? _makerSteps.any(
                        (step) =>
                            step.$1 == 'start' &&
                            step.$2 == to.name &&
                            step.$3.contains(role),
                      )
                    : (reachable[from] ?? const {}).contains(to));
            expect(
              TradeEdges.allowsMade(role, from, to),
              expected,
              reason: '$role $from → $to',
            );
          }
        }
      }
      // The taker's edges are untouched by a maker's.
      expect(
        TradeEdges.allows(
          b,
          TradePosition.waitingForBoth,
          TradePosition.public,
        ),
        isFalse,
      );
      expect(
        TradeEdges.allowsMade(
          b,
          TradePosition.waitingForBoth,
          TradePosition.publicAgain,
        ),
        isFalse,
      );
    });
  });

  group('every position and every answer, for a maker buyer and a maker seller', () {
    /// The rows: a position reached along the reference's own answers, and whether a contract was kept and the order went back to the book since.
    Future<TradeStatus> statusAt(_Row row, TradeRole role) async {
      final terms = termsOf(role);
      Future<TradeStatus> along(List<int> wires) async {
        var status = first(await made(0, role: role), terms: terms);
        for (final wire in wires) {
          status = next(status, await made(wire, role: role), terms: terms);
        }
        return status;
      }

      return switch (row) {
        _Row.makerBondStep => along(const []),
        _Row.publicFresh => along(const [1]),
        _Row.pausedFresh => along(const [1, 2]),
        _Row.publicBack => along(const [1, 6, 1]),
        _Row.pausedBack => along(const [1, 6, 1, 2]),
        _Row.both => along(const [1, 6]),
        _Row.escrow => along(const [1, 6, 7]),
        _Row.payout => along(const [1, 6, 8]),
        _Row.chatting => along(const [1, 6, 9]),
        _Row.fiatSent => along(const [1, 6, 9, 10]),
        _Row.inDispute => along(const [1, 6, 9, 11]),
        _Row.sendingSats => along(const [1, 6, 9, 10, 13]),
        _Row.routingFailed => along(const [1, 6, 9, 10, 13, 15]),
        _Row.resolution => along(const [1, 6, 9, 11, 16]),
        _Row.succeeded => along(const [1, 6, 9, 10, 14]),
        _Row.makerLost => along(const [1, 6, 9, 11, 17]),
        _Row.takerLost => along(const [1, 6, 9, 11, 18]),
        _Row.expired => along(const [1, 5]),
        _Row.cancelled => along(const [1]).then(
          (public) => next(public, const TradeOrderCancelled(), terms: terms),
        ),
      };
    }

    test('each pair gives the outcome the reference implies', () async {
      var pairs = 0;
      for (final role in [b, s]) {
        final terms = termsOf(role);
        for (final row in [null, ..._Row.values]) {
          final from = row == null ? null : await statusAt(row, role);
          expect(from?.warnings ?? const [], isEmpty, reason: '$row');
          final fromPosition = from?.position ?? TradePosition.start;
          for (final answerKind in _Answer.values) {
            // At 6, 7 and 8 after a return to the book, the next contract's figures, which an honest coordinator gives; in a contract, the same contract's.
            final nextContract =
                (row == _Row.publicBack || row == _Row.pausedBack) &&
                answerKind.isStep;
            final wire = answerKind.wire;
            final TradeAnswer answer = wire == null
                ? (answerKind == _Answer.cancelled
                      ? const TradeOrderCancelled()
                      : const TradeOrderNotAvailable())
                : await made(
                    wire,
                    role: role,
                    taker: nextContract ? third : null,
                    deadline: nextContract ? deadline1 : null,
                    take: nextContract ? 1 : 0,
                  );
            final after = from == null
                ? first(answer, terms: terms)
                : next(from, answer, terms: terms);
            final expected = _expected(
              role,
              fromPosition,
              answerKind,
              contractStepBack:
                  !nextContract &&
                  row != null &&
                  row.isStep &&
                  answerKind.isStep &&
                  fromPosition != answerKind.position &&
                  fromPosition != TradePosition.waitingForBoth,
              nextContractUnreachable:
                  nextContract &&
                  !(_closure(role)[fromPosition] ?? const {}).contains(
                    TradePosition.public,
                  ) &&
                  fromPosition != TradePosition.public &&
                  fromPosition != TradePosition.paused,
              // After a return to the book, a read from 9 on is a contract the app did not see at its steps (the maker's step done from another client).
              seenLate:
                  (row == _Row.publicBack || row == _Row.pausedBack) &&
                  (answerKind.wire ?? 0) >= 9 &&
                  answerKind != _Answer.w12,
            );
            final label =
                '$role $row ${answerKind.name}: $expected, got $after';
            pairs++;
            switch (expected) {
              case _Outcome.passes:
                expect(after.position, answerKind.position, reason: label);
                expect(after.warnings, isEmpty, reason: label);
                expect(after.trail.breached, isFalse, reason: label);
              case _Outcome.seenLate:
                expect(after.position, answerKind.position, reason: label);
                expect(after.warnings, [
                  isA<ContractSeenLate>(),
                ], reason: label);
                expect(after.trail.take, 1, reason: label);
                expect(after.trail.breached, isFalse, reason: label);
              case _Outcome.warns:
                expect(after.position, answerKind.position, reason: label);
                expect(
                  after.has<TradeStatusUnexpected>(),
                  isTrue,
                  reason: label,
                );
                expect(after.trail.breached, isTrue, reason: label);
              case _Outcome.refusedUnexpected || _Outcome.refusedRegressed:
                expect(after.position, fromPosition, reason: label);
                expect(after.trail.position, fromPosition, reason: label);
                expect(after.trail.breached, isTrue, reason: label);
                expect(
                  expected == _Outcome.refusedUnexpected
                      ? after.has<TradeStatusUnexpected>()
                      : after.has<TradeStatusRegressed>(),
                  isTrue,
                  reason: label,
                );
                if (from == null) {
                  expect(after, isA<StatusUnknown>(), reason: label);
                } else {
                  expect(after.runtimeType, from.runtimeType, reason: label);
                }
              case _Outcome.stays:
                expect(identical(after, from), isTrue, reason: label);
              case _Outcome.refreshed:
                expect(after.runtimeType, from.runtimeType, reason: label);
                expect(after.position, fromPosition, reason: label);
                expect(after.warnings, isEmpty, reason: label);
            }
            // Every trail the state machine gives may replace the one it read from: the database never refuses it (the trigger's rules are whyNotReplace's).
            if (from != null && !identical(after, from)) {
              expect(
                after.trail.record.whyNotReplace(
                  from.trail.record,
                  madeHere: true,
                ),
                isNull,
                reason: label,
              );
            }
          }
        }
      }
      expect(pairs, 2 * (_Row.values.length + 1) * _Answer.values.length);
    });

    test('status 3 never reaches a maker: the package refuses it', () async {
      final json = makerOrderJson(3);
      await expectLater(readOrder(json), throwsStateError);
    });
  });
}

/// The rows of the table.
enum _Row {
  makerBondStep(false),
  publicFresh(false),
  pausedFresh(false),
  publicBack(false),
  pausedBack(false),
  both(true),
  escrow(true),
  payout(true),
  chatting(false),
  fiatSent(false),
  inDispute(false),
  sendingSats(false),
  routingFailed(false),
  resolution(false),
  succeeded(false),
  makerLost(false),
  takerLost(false),
  expired(false),
  cancelled(false);

  /// Whether the row is at 6, 7 or 8.
  final bool isStep;

  const _Row(this.isStep);
}

/// The answers of the table: an order at each status a coordinator can write (3 is refused by the package), and errors 1043 and 1044.
enum _Answer {
  w0(0, TradePosition.makerBondStep),
  w1(1, TradePosition.public),
  w2(2, TradePosition.paused),
  w4(4, null),
  w5(5, TradePosition.expired),
  w6(6, TradePosition.waitingForBoth),
  w7(7, TradePosition.waitingForEscrow),
  w8(8, TradePosition.waitingForPayout),
  w9(9, TradePosition.chatting),
  w10(10, TradePosition.fiatSent),
  w11(11, TradePosition.inDispute),
  w12(12, null),
  w13(13, TradePosition.sendingSats),
  w14(14, TradePosition.succeeded),
  w15(15, TradePosition.routingFailed),
  w16(16, TradePosition.waitingDisputeResolution),
  w17(17, TradePosition.makerLostDispute),
  w18(18, TradePosition.takerLostDispute),
  cancelled(null, TradePosition.cancelled),
  notAvailable(null, null);

  final int? wire;
  final TradePosition? position;

  const _Answer(this.wire, this.position);

  bool get isStep => wire == 6 || wire == 7 || wire == 8;
}

enum _Outcome {
  passes,
  seenLate,
  warns,
  refusedUnexpected,
  refusedRegressed,
  stays,
  refreshed,
}

/// The outcome of [answer] read at [from] by a maker of [role], from the table written out below, apart from the state machine.
///
/// Said plainly (functional review of #178): this is a second writing of the same rules, from the same reading of the reference (the list of steps below, and the contract rules again as [contractStepBack], [nextContractUnreachable] and [seenLate]); it shows that the code follows that writing at every pair, not that the rules are the reference's. That was checked by the review's own table, made from the reference alone, which agrees with [TradeEdges.makerSteps] step by step.
///
/// The rules: an end is never left (but refreshed by an order of its status); error 1044 is refused (a maker is always a participant); 4 and 12 in an order are refused as never shown; the maker bond step after it is refused; an edge of the table passes; one that is not, to an end, is refused, and to a status that goes on, warned. Within a contract, a step back ([contractStepBack]) is warned; a next contract read where the order cannot have gone back to the book ([nextContractUnreachable]) too.
_Outcome _expected(
  TradeRole role,
  TradePosition from,
  _Answer answer, {
  required bool contractStepBack,
  required bool nextContractUnreachable,
  required bool seenLate,
}) {
  final to = answer.position;
  if (_terminal.contains(from)) {
    return to == from && answer.wire != null
        ? _Outcome.refreshed
        : _Outcome.stays;
  }
  if (answer == _Answer.notAvailable) return _Outcome.refusedUnexpected;
  if (to == null) return _Outcome.refusedRegressed;
  if (to == TradePosition.makerBondStep &&
      from != TradePosition.start &&
      from != TradePosition.makerBondStep) {
    return _Outcome.refusedRegressed;
  }
  final allowed =
      from == to ||
      (from == TradePosition.start
          ? _makerSteps.any(
              (step) =>
                  step.$1 == 'start' &&
                  step.$2 == to.name &&
                  step.$3.contains(role),
            )
          : (_closure(role)[from] ?? const {}).contains(to));
  if (!allowed) {
    return _terminal.contains(to) ? _Outcome.refusedUnexpected : _Outcome.warns;
  }
  if (contractStepBack || nextContractUnreachable) return _Outcome.warns;
  if (seenLate) return _Outcome.seenLate;
  return _Outcome.passes;
}

const _terminal = {
  TradePosition.succeeded,
  TradePosition.makerLostDispute,
  TradePosition.takerLostDispute,
  TradePosition.expired,
  TradePosition.cancelled,
};

/// Each position the closure of [_makerSteps] reaches from each position, for [role].
Map<TradePosition, Set<TradePosition>> _closure(TradeRole role) {
  final reachable = <TradePosition, Set<TradePosition>>{};
  for (final origin in TradePosition.values) {
    final seen = <TradePosition>{};
    final pending = [origin.name];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final (from, to, roles) in _makerSteps) {
        if (from == current &&
            roles.contains(role) &&
            seen.add(TradePosition.values.byName(to))) {
          pending.add(to);
        }
      }
    }
    reachable[origin] = seen;
  }
  return reachable;
}

const _b = TradeRole.buyer;
const _s = TradeRole.seller;

/// Each single move of the reference for a maker, written out from `api/logics.py`, `api/views.py`, `follow_invoices.py` and `clean_orders.py` at commit ff1998c (the lines of each are in `trade_edges.dart`): (from, to, roles).
const _makerSteps = <(String, String, Set<TradeRole>)>[
  ('start', 'makerBondStep', {_b, _s}),
  ('start', 'expired', {_b, _s}),
  ('start', 'cancelled', {_b, _s}),
  ('makerBondStep', 'public', {_b, _s}),
  ('makerBondStep', 'expired', {_b, _s}),
  ('makerBondStep', 'cancelled', {_b, _s}),
  ('public', 'paused', {_b, _s}),
  ('public', 'waitingForBoth', {_b, _s}),
  ('public', 'expired', {_b, _s}),
  ('public', 'cancelled', {_b, _s}),
  ('paused', 'public', {_b, _s}),
  ('paused', 'expired', {_b, _s}),
  ('paused', 'cancelled', {_b, _s}),
  ('waitingForBoth', 'waitingForEscrow', {_b, _s}),
  ('waitingForBoth', 'waitingForPayout', {_b, _s}),
  ('waitingForBoth', 'chatting', {_b, _s}),
  ('waitingForBoth', 'expired', {_b, _s}),
  ('waitingForBoth', 'public', {_b, _s}),
  ('waitingForBoth', 'cancelled', {_b, _s}),
  ('waitingForEscrow', 'chatting', {_b, _s}),
  ('waitingForEscrow', 'expired', {_b, _s}),
  ('waitingForEscrow', 'public', {_b, _s}),
  ('waitingForEscrow', 'cancelled', {_b, _s}),
  ('waitingForPayout', 'chatting', {_b, _s}),
  ('waitingForPayout', 'expired', {_b, _s}),
  ('waitingForPayout', 'public', {_s}),
  ('waitingForPayout', 'cancelled', {_b, _s}),
  ('chatting', 'fiatSent', {_b, _s}),
  ('chatting', 'inDispute', {_b, _s}),
  ('chatting', 'cancelled', {_b, _s}),
  ('chatting', 'expired', {_b, _s}),
  ('fiatSent', 'chatting', {_b, _s}),
  ('fiatSent', 'inDispute', {_b, _s}),
  ('fiatSent', 'sendingSats', {_b, _s}),
  ('fiatSent', 'succeeded', {_b, _s}),
  ('fiatSent', 'expired', {_b, _s}),
  ('inDispute', 'waitingDisputeResolution', {_b, _s}),
  ('inDispute', 'takerLostDispute', {_b, _s}),
  ('inDispute', 'makerLostDispute', {_b, _s}),
  ('inDispute', 'cancelled', {_b, _s}),
  ('inDispute', 'sendingSats', {_b, _s}),
  ('waitingDisputeResolution', 'takerLostDispute', {_b, _s}),
  ('waitingDisputeResolution', 'makerLostDispute', {_b, _s}),
  ('waitingDisputeResolution', 'cancelled', {_b, _s}),
  ('waitingDisputeResolution', 'sendingSats', {_b, _s}),
  ('sendingSats', 'succeeded', {_b, _s}),
  ('sendingSats', 'routingFailed', {_b, _s}),
  ('routingFailed', 'sendingSats', {_b, _s}),
  ('routingFailed', 'succeeded', {_b, _s}),
];
