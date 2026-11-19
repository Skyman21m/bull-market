import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/maker_orders.dart';
import 'support/maker_reference.dart';
import 'support/robot_bindings.dart';
import 'support/trade_orders.dart';

/// A maker's contracts and checks (#178; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3, § 3.5): a new take recognized whether the app saw the order back in the book or not, what a coordinator that lies can obtain, the reference's own sequences read with gaps, and every trail they give written to the database of schema 8.
void main() {
  const b = TradeRole.buyer;
  const s = TradeRole.seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

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

  TradeStatus next(
    TradeStatus previous,
    TradeAnswer answer, {
    bool range = false,
    DateTime? now,
  }) => TradeStatus.from(
    previous: previous,
    answer: answer,
    terms: madeTerms(role: previous.trail.role, range: range),
    now: now ?? tradeNow,
    reader: reader,
  );

  Future<TradeStatus> along(
    TradeRole role,
    List<int> wires, {
    bool range = false,
  }) async {
    var status = TradeStatus.afterMake(
      await made(0, role: role, range: range),
      terms: madeTerms(role: role, range: range),
      now: tradeNow,
      reader: reader,
    );
    for (final wire in wires) {
      status = next(
        status,
        await made(wire, role: role, range: range),
        range: range,
      );
    }
    return status;
  }

  CheckedInvoice checkedOf(TradeStatus status) => switch (status.invoice) {
    final CheckedInvoice invoice => invoice,
    final other => fail('expected a checked invoice, got $other'),
  };

  /// Whether [after] may be written over [before]: what the database's trigger says, which whyNotReplace mirrors.
  void storable(TradeStatus after, TradeStatus before) => expect(
    after.trail.record.whyNotReplace(before.trail.record, madeHere: true),
    isNull,
  );

  /// The answer refused as a whole: the status and the trail's position kept, the breach recorded, [T] said once.
  void refused<T extends TradeWarning>(TradeStatus after, TradeStatus before) {
    expect(after.runtimeType, before.runtimeType);
    expect(after.trail.position, before.trail.position);
    expect(after.trail.take, before.trail.take);
    expect(after.trail.takeDeadline, before.trail.takeDeadline);
    expect(after.trail.takerHashId, before.trail.takerHashId);
    expect(after.trail.breached, isTrue);
    expect(after.warnings.whereType<T>(), hasLength(1));
    storable(after, before);
  }

  group('a next contract, whether the book was seen or not', () {
    test(
      'a later deadline at 6, 7 or 8 opens the next contract: take + 1, its deadline, taker and escrow in one write',
      () async {
        for (final (role, fromWires, toWire) in [
          (s, [1, 6], 6), // 6 → 6
          (s, [1, 6, 7], 6), // 7 → 6
          (s, [1, 6, 7], 7), // 7 → 7
          (s, [1, 6, 8], 6), // 8 → 6
          (s, [1, 6, 8], 7), // 8 → 7
          (s, [1, 6, 8], 8), // 8 → 8
          (s, [1, 6, 1], 6), // 1 → 6, the book seen
          (s, [1, 6, 1, 2], 6), // 2 → 6
          (b, [1, 6], 6),
          (b, [1, 6, 7], 6),
          (b, [1, 6, 7], 7),
          (b, [1, 6, 7], 8),
          (b, [1, 6, 1], 8),
          (b, [1, 6, 1, 2], 6),
        ]) {
          final label = '$role $fromWires → $toWire';
          final before = await along(role, fromWires);
          expect(before.warnings, isEmpty, reason: label);
          expect(before.trail.take, 0, reason: label);
          final after = next(
            before,
            await made(
              toWire,
              role: role,
              taker: third,
              deadline: deadline1,
              take: 1,
              last: 90000,
            ),
          );
          expect(after.warnings, isEmpty, reason: label);
          expect(after.trail.take, 1, reason: label);
          expect(after.trail.takeDeadline, deadline1, reason: label);
          expect(after.trail.takerHashId, third.hashId.hex, reason: label);
          expect(after.trail.breached, isFalse, reason: label);
          if (role == s && toWire != 8) {
            final escrow = checkedOf(after);
            expect(escrow.paymentHash, isNot(before.trail.escrowHash));
            expect(after.trail.escrowHash, escrow.paymentHash, reason: label);
            // Offered for the next contract, under its own record.
            expect(
              walletPaymentFor(
                accepted: escrow.amount,
                status: after,
                step: InvoiceStep.escrow,
                now: tradeNow,
              ),
              isA<WalletPaymentOffered>().having((o) => o.take, 'take', 1),
              reason: label,
            );
          } else {
            expect(after.trail.escrowHash, isNull, reason: label);
          }
          storable(after, before);
        }
      },
    );

    test('the same robot may take again: a later deadline is enough', () async {
      final before = await along(s, [1, 6]);
      final after = next(
        before,
        await made(6, role: s, deadline: deadline1, take: 1),
      );
      expect(after.warnings, isEmpty);
      expect(after.trail.take, 1);
      expect(after.trail.takerHashId, peer.hashId.hex);
    });

    test(
      'a maker buyer\'s 8 never goes back to the book: a later deadline there is no contract',
      () async {
        final before = await along(b, [1, 6, 8]);
        final after = next(
          before,
          await made(6, taker: third, deadline: deadline1, take: 1),
        );
        expect(after.has<TradeStatusUnexpected>(), isTrue);
        expect(after.trail.take, 0);
        expect(after.trail.takeDeadline, deadline0);
        expect(after.trail.takerHashId, peer.hashId.hex);
        storable(after, before);
      },
    );

    test(
      'from the chat on, a later deadline at a step is no contract',
      () async {
        for (final role in [b, s]) {
          final before = await along(role, [1, 6, 9]);
          final after = next(
            before,
            await made(
              6,
              role: role,
              taker: third,
              deadline: deadline1,
              take: 1,
            ),
          );
          expect(after.has<TradeStatusUnexpected>(), isTrue);
          expect(after.trail.take, 0);
          expect(after.trail.takeDeadline, deadline0);
          storable(after, before);
        }
      },
    );

    test(
      'a range\'s next contract keeps its own amount, without a warning',
      () async {
        final before = await along(s, [1, 6], range: true);
        expect(before.trail.takenAmount, 120);
        final after = next(
          before,
          await made(
            6,
            role: s,
            range: true,
            taker: third,
            deadline: deadline1,
            take: 1,
            taken: 80,
          ),
          range: true,
        );
        expect(after.warnings, isEmpty);
        expect(after.trail.take, 1);
        expect(after.trail.takenAmount, 80);
        storable(after, before);
        final chat = next(
          after,
          await made(9, role: s, range: true, taker: third, taken: 80),
          range: true,
        );
        expect((chat as Chatting).amount.value, 80);
        expect(chat.warnings, isEmpty);
      },
    );
  });

  group('a next contract seen late: the maker acting from another client too', () {
    test(
      'a contract seen late is said at every read while it lasts, after a restart too',
      () async {
        final before = await along(b, [1, 6, 1]);
        final late = next(before, await made(9, taker: third));
        expect(late.trail.seenLate, isTrue);
        final again = next(late, await made(9, taker: third));
        expect(again.warnings, [isA<ContractSeenLate>()]);
        final sent = next(again, await made(10, taker: third));
        expect(sent.warnings, [isA<ContractSeenLate>()]);
        final restored = switch (TradeTrail.restore(
          sent.trail.record,
          terms: madeTerms(),
          now: tradeNow,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final resumed = TradeStatus.beforeFirstRead(restored);
        expect(resumed.warnings, [isA<ContractSeenLate>()]);
        final after = next(resumed, await made(13, taker: third));
        expect(after.warnings, [isA<ContractSeenLate>()]);
        expect(after.trail.breached, isFalse);
        // A next contract read at its steps is not seen late.
        final atStep = next(
          before,
          await made(6, taker: third, deadline: deadline1, take: 1),
        );
        expect(atStep.trail.seenLate, isFalse);
        expect(atStep.warnings, isEmpty);
      },
    );

    const after = [9, 10, 11, 13, 14, 15, 16, 17, 18];

    test(
      'from where the order can go back to the book, another taker from 9 on is a next contract, said as information',
      () async {
        for (final (role, wires) in [
          (b, [1, 6, 1]), // the book seen: 0 6 1 14
          (b, [1, 6, 1, 2]),
          (b, [1, 6]),
          (b, [1, 6, 7]),
          (s, [1, 6, 1]),
          (s, [1, 6]),
          (s, [1, 6, 7]),
          (s, [1, 6, 8]), // a maker seller's 8 goes back to the book
        ]) {
          for (final wire in after) {
            final label = '$role $wires → $wire';
            final before = await along(role, wires);
            final read = next(
              before,
              await made(wire, role: role, taker: third),
            );
            expect(
              read.position.name,
              isNot(before.position.name),
              reason: label,
            );
            expect(read.warnings, [isA<ContractSeenLate>()], reason: label);
            expect(read.trail.breached, isFalse, reason: label);
            expect(read.trail.take, 1, reason: label);
            expect(read.trail.takerHashId, third.hashId.hex, reason: label);
            // Its deadline at the steps is no longer readable: the last one read is kept.
            expect(read.trail.takeDeadline, deadline0, reason: label);
            expect(read.trail.escrowHash, isNull, reason: label);
            storable(read, before);
            // The contract goes on from there, with its taker: read again, nothing more to say.
            final again = next(
              read,
              await made(wire, role: role, taker: third),
            );
            // Said again at every read while the contract lasts (security review of #178).
            if (!read.isTerminal) {
              expect(again.warnings, [isA<ContractSeenLate>()], reason: label);
            }
            expect(again.trail.take, 1, reason: label);
            expect(again.trail.breached, isFalse, reason: label);
          }
        }
      },
    );

    test(
      'from the book, any taker from 9 on is a next contract: the book never gives back the one before',
      () async {
        final before = await along(b, [1, 6, 1]);
        final read = next(before, await made(14));
        expect(read, isA<Succeeded>());
        expect(read.warnings, [isA<ContractSeenLate>()]);
        expect(read.trail.take, 1);
        expect(read.trail.takerHashId, peer.hashId.hex);
      },
    );

    test(
      'a range\'s next contract seen late keeps the amount it read',
      () async {
        final before = await along(s, [1, 6, 1], range: true);
        final read = next(
          before,
          await made(9, role: s, range: true, taker: third, taken: 80),
          range: true,
        );
        expect(read.warnings, [isA<ContractSeenLate>()]);
        expect(read.trail.takenAmount, 80);
        expect((read as Chatting).amount.value, 80);
      },
    );

    test(
      'where the order cannot have gone back to the book, another taker from 9 on stays a breach',
      () async {
        for (final (role, wires) in [
          (
            b,
            [1, 6, 8],
          ), // a maker buyer's 8 expires the order rather than publish it
          (b, [1, 6, 9]),
          (s, [1, 6, 9]),
          (b, [1, 6, 9, 10]),
          (s, [1, 6, 9, 11]),
        ]) {
          for (final wire in after.where((w) => w > wires.last)) {
            final before = await along(role, wires);
            refused<TradeTakerChanged>(
              next(before, await made(wire, role: role, taker: third)),
              before,
            );
          }
        }
      },
    );

    test(
      'the same robot taking again, read from 6, 7 or 8 at 9 or later, is taken for the same contract (a known limit)',
      () async {
        final before = await along(b, [1, 6]);
        final read = next(before, await made(14));
        expect(read.warnings, isEmpty);
        expect(read.trail.take, 0);
        // Of a range, another amount is said as the terms changed: no breach.
        final range = await along(b, [1, 6], range: true);
        final other = next(
          range,
          await made(9, range: true, taken: 90),
          range: true,
        );
        expect(other.warnings, [isA<TradeTermsChanged>()]);
        expect(other.trail.breached, isFalse);
      },
    );

    test(
      'without a contract kept, the taker read from 9 on is kept, as before',
      () async {
        final public = await along(s, [1]);
        final read = next(public, await made(14, role: s, taker: third));
        expect(read.warnings, isEmpty);
        expect(read.trail.take, 0);
        expect(read.trail.takerHashId, third.hashId.hex);
      },
    );

    test(
      'the ends read straight from the book: 5 and 1043 as the reference gives them, a bond maybe lost after the book',
      () async {
        for (final wires in [
          [1],
          [1, 2],
          [1, 6, 1],
        ]) {
          final before = await along(b, wires);
          expect(next(before, await made(5)), isA<Expired>());
          final cancelled = next(before, const TradeOrderCancelled());
          expect(cancelled, isA<Cancelled>());
          // Taken and cancelled alone by this maker from another client, at 6 or 7, the bond is lost.
          expect((cancelled as Cancelled).bondMayHaveBeenLost, isTrue);
        }
        final bond = await along(b, const []);
        // At 0 once the bond was shown, it may have been paid, the order taken and cancelled elsewhere, or the bond kept (security review of #178); at the first read no bond existed.
        final atZero = next(bond, const TradeOrderCancelled());
        expect((atZero as Cancelled).bondMayHaveBeenLost, isTrue);
        final first = TradeStatus.afterMake(
          const TradeOrderCancelled(),
          terms: madeTerms(),
          now: tradeNow,
          reader: reader,
        );
        expect((first as Cancelled).bondMayHaveBeenLost, isFalse);
        // After 6, 7 or 8, for both roles: this maker may have cancelled alone, its bond settled.
        for (final role in [b, s]) {
          for (final wires in [
            [1, 6],
            [1, 6, 7],
            [1, 6, 8],
          ]) {
            final cancelled = next(
              await along(role, wires),
              const TradeOrderCancelled(),
            );
            expect(
              (cancelled as Cancelled).bondMayHaveBeenLost,
              isTrue,
              reason: '$role $wires',
            );
          }
          final chat = next(
            await along(role, [1, 6, 9]),
            const TradeOrderCancelled(),
          );
          expect((chat as Cancelled).bondMayHaveBeenLost, isFalse);
        }
        // 4 and 12 in an order are never served: error 1043 is.
        final public = await along(b, [1]);
        refused<TradeStatusRegressed>(next(public, await made(4)), public);
        refused<TradeStatusRegressed>(next(public, await made(12)), public);
      },
    );
  });

  group('within a contract', () {
    test('the same deadline and the same taker: the same contract', () async {
      final both = await along(s, [1, 6]);
      final escrow = next(both, await made(7, role: s));
      expect(escrow.warnings, isEmpty);
      expect(escrow.trail.take, 0);
      expect(escrow.trail.escrowHash, both.trail.escrowHash);
      storable(escrow, both);
    });

    test('the same deadline and another taker: refused, a breach', () async {
      for (final role in [b, s]) {
        for (final wire in [6, 7, 8]) {
          final before = await along(role, [1, 6]);
          final after = next(
            before,
            await made(wire, role: role, taker: third),
          );
          refused<TradeTakerChanged>(after, before);
        }
      }
    });

    test(
      'an earlier deadline: the same contract, its deadline moved back said; with another taker, refused',
      () async {
        final before = await along(b, [1, 6]);
        final earlier = deadline0.subtract(const Duration(minutes: 5));
        final after = next(before, await made(7, deadline: earlier));
        expect(after.position, TradePosition.waitingForEscrow);
        expect(after.has<DeadlineMovedBack>(), isTrue);
        expect(after.warnings, hasLength(1));
        expect(after.trail.take, 0);
        expect(after.trail.takeDeadline, deadline0);
        expect(after.trail.breached, isFalse);
        storable(after, before);
        refused<TradeTakerChanged>(
          next(before, await made(7, deadline: earlier, taker: third)),
          before,
        );
      },
    );

    test(
      'after a return to the book, the contract before is never given back',
      () async {
        for (final taker in [peer, third]) {
          final before = await along(s, [1, 6, 1]);
          expect((before as MakerOrderPublic).backInBook, isTrue);
          refused<TradeStatusUnexpected>(
            next(
              before,
              await made(6, role: s, taker: taker, deadline: deadline0),
            ),
            before,
          );
        }
      },
    );

    test(
      'from 9 on, the kept taker or refused; with none kept, the taker read is kept, with no deadline',
      () async {
        final before = await along(b, [1, 6, 9]);
        refused<TradeTakerChanged>(
          next(before, await made(10, taker: third)),
          before,
        );
        refused<TradeTakerChanged>(
          next(before, await made(17, taker: third)),
          before,
        );
        // The maker's step done elsewhere, with the Garage Key: no contract was kept.
        final public = await along(b, [1]);
        final chat = next(public, await made(9, taker: third));
        expect(chat.warnings, isEmpty);
        expect(chat.trail.takerHashId, third.hashId.hex);
        expect(chat.trail.takeDeadline, isNull);
        expect(chat.trail.take, 0);
        storable(chat, public);
        refused<TradeTakerChanged>(next(chat, await made(10)), chat);
      },
    );

    test('a step back within a contract is unexpected', () async {
      for (final (role, wires, wire) in [
        (s, [1, 6, 7], 6),
        (s, [1, 6, 8], 6),
        (s, [1, 6, 8], 7),
        (b, [1, 6, 7], 6),
        (b, [1, 6, 8], 7),
      ]) {
        final before = await along(role, wires);
        final after = next(before, await made(wire, role: role));
        expect(
          after.has<TradeStatusUnexpected>(),
          isTrue,
          reason: '$wires $wire',
        );
        expect(after.trail.take, 0);
        storable(after, before);
      }
    });

    test(
      'an escrow changed within a contract is a breach, never shown',
      () async {
        final both = await along(s, [1, 6]);
        final after = next(
          both,
          await made(7, role: s, escrow: makerEscrowInvoice(take: 5)),
        );
        expect(
          checkedOf(after).warnings.whereType<InvoiceHashChanged>(),
          hasLength(1),
        );
        expect(checkedOf(after).mayShowAnyway, isFalse);
        expect(after.trail.escrowHash, both.trail.escrowHash);
        expect(after.trail.breached, isTrue);
        storable(after, both);
      },
    );

    test('a range: the amount kept, changed or outside the range said', () async {
      final both = await along(b, [1, 6], range: true);
      expect(both.warnings, isEmpty);
      expect(both.trail.takenAmount, 120);
      final changed = next(
        both,
        await made(8, range: true, taken: 130),
        range: true,
      );
      expect(changed.has<TradeTermsChanged>(), isTrue);
      expect(changed.trail.takenAmount, 120);
      storable(changed, both);
      final public = await along(b, [1], range: true);
      // An amount taken outside the range is refused, never kept (security review of #178): at the package's own bound too, which the trail could not even store.
      for (final taken in [250.0, 49.0, 1e10]) {
        refused<TradeTermsChanged>(
          next(public, await made(6, range: true, taken: taken), range: true),
          public,
        );
      }
      // At the very bounds, kept.
      for (final taken in [50.0, 200.0]) {
        final atBound = next(
          public,
          await made(6, range: true, taken: taken),
          range: true,
        );
        expect(atBound.warnings, isEmpty, reason: '$taken');
        expect(atBound.trail.takenAmount, taken);
      }
      // A fixed order showing another amount, or a range, at 6 or later: refused.
      final fixed = await along(b, [1]);
      refused<TradeTermsChanged>(
        next(fixed, await made(6, changes: {'amount': '101.00000000'})),
        fixed,
      );
      refused<TradeTermsChanged>(
        next(
          fixed,
          await made(
            6,
            changes: {
              'has_range': true,
              'min_amount': '50.00000000',
              'max_amount': '200.00000000',
            },
          ),
        ),
        fixed,
      );
      // No amount taken at 6 or later: refused, the contract cannot be told.
      refused<TradeTermsChanged>(
        next(
          public,
          await made(6, range: true, changes: {'amount': null}),
          range: true,
        ),
        public,
      );
      // An amount taken before any take.
      final atZero = TradeStatus.afterMake(
        await made(0, range: true, changes: {'amount': '120.00000000'}),
        terms: madeTerms(range: true),
        now: tradeNow,
        reader: reader,
      );
      expect(atZero.has<TradeTermsChanged>(), isTrue);
    });
  });

  group('an escrow of an earlier contract', () {
    test(
      'served again at the next contract: refused, never shown, never pinned',
      () async {
        final both = await along(s, [1, 6, 7]);
        final first = both.trail.escrowHash;
        final after = next(
          both,
          await made(
            6,
            role: s,
            taker: third,
            deadline: deadline1,
            escrow: makerEscrowInvoice(take: 0),
          ),
        );
        final escrow = checkedOf(after);
        expect(escrow.paymentHash, first);
        expect(
          escrow.warnings.whereType<EscrowNotOfThisContract>(),
          hasLength(1),
        );
        expect(escrow.mayShowAnyway, isFalse);
        expect(after.trail.take, 1);
        expect(after.trail.escrowHash, isNull);
        expect(after.trail.breached, isTrue);
        expect(
          walletPaymentFor(
            accepted: escrow.amount,
            status: after,
            step: InvoiceStep.escrow,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>(),
        );
        storable(after, both);
        // Read again later in the contract: still refused, the trigger never seeing it (not the write that moves `take`).
        final again = next(
          after,
          await made(
            7,
            role: s,
            taker: third,
            deadline: deadline1,
            escrow: makerEscrowInvoice(take: 0),
          ),
        );
        expect(
          checkedOf(again).warnings.whereType<EscrowNotOfThisContract>(),
          hasLength(1),
        );
        expect(again.trail.escrowHash, isNull);
        storable(again, after);
      },
    );

    test(
      'an escrow of any earlier contract never comes back, whatever came in between, after a restart too',
      () async {
        final e0 = makerEscrowInvoice(take: 0).facts.paymentHash;
        for (final (label, wire, changes)
            in <(String, int, Map<String, Object?>)>[
              ('contract 1 read at 8', 8, {}),
              (
                'contract 1 read at 7 without its escrow',
                7,
                {'escrow_invoice': null, 'escrow_satoshis': null},
              ),
              (
                'contract 1 read at 6 without its escrow',
                6,
                {'escrow_invoice': null, 'escrow_satoshis': null},
              ),
            ]) {
          final c0 = await along(s, [1, 6]);
          expect(c0.trail.escrowHash, e0);
          final c1 = next(
            c0,
            await made(
              wire,
              role: s,
              taker: third,
              deadline: deadline1,
              take: 1,
              changes: changes,
            ),
          );
          expect(c1.warnings, isEmpty, reason: label);
          expect(c1.trail.take, 1, reason: label);
          expect(c1.trail.escrowHash, isNull, reason: label);
          expect(c1.trail.earlierEscrows, [e0], reason: label);
          storable(c1, c0);
          Future<TradeAnswer> contract2() => made(
            6,
            role: s,
            taker: peer,
            deadline: deadline1.add(const Duration(hours: 1)),
            escrow: makerEscrowInvoice(take: 0),
          );
          final c2 = next(c1, await contract2());
          expect(c2.trail.take, 2, reason: label);
          expect(
            checkedOf(c2).warnings.whereType<EscrowNotOfThisContract>(),
            hasLength(1),
            reason: label,
          );
          expect(c2.trail.escrowHash, isNull, reason: label);
          expect(c2.trail.breached, isTrue, reason: label);
          expect(
            walletPaymentFor(
              accepted: Sats.fromInt(1 << 40),
              status: c2,
              step: InvoiceStep.escrow,
              now: tradeNow,
            ),
            isA<WalletPaymentRefused>(),
            reason: label,
          );
          storable(c2, c1);
          // After a restart, from the stored trail alone.
          final restored = switch (TradeTrail.restore(
            c1.trail.record,
            terms: madeTerms(role: s),
            now: tradeNow,
          )) {
            Ok(:final value) => value,
            Err(:final failure) => fail('$failure'),
          };
          final afterRestart = next(
            TradeStatus.beforeFirstRead(restored),
            await contract2(),
          );
          expect(
            checkedOf(
              afterRestart,
            ).warnings.whereType<EscrowNotOfThisContract>(),
            hasLength(1),
            reason: label,
          );
        }
      },
    );

    test(
      'shown after a next contract opened without one: refused when it is an earlier contract\'s, pinned when it is new',
      () async {
        final both = await along(s, [1, 6]);
        final opened = next(
          both,
          await made(
            6,
            role: s,
            taker: third,
            deadline: deadline1,
            changes: {'escrow_invoice': null, 'escrow_satoshis': null},
          ),
        );
        expect(opened.warnings, isEmpty);
        expect(opened.trail.take, 1);
        expect(opened.trail.escrowHash, isNull);
        final earlier = next(
          opened,
          await made(
            6,
            role: s,
            taker: third,
            deadline: deadline1,
            escrow: makerEscrowInvoice(take: 0),
          ),
        );
        expect(
          checkedOf(earlier).warnings.whereType<EscrowNotOfThisContract>(),
          hasLength(1),
        );
        expect(earlier.trail.escrowHash, isNull);
        storable(earlier, opened);
        // The trail keeps every escrow its earlier contracts pinned: a new one is told from them, and pinned.
        final fresh = next(
          opened,
          await made(
            6,
            role: s,
            taker: third,
            deadline: deadline1,
            escrow: makerEscrowInvoice(take: 1),
          ),
        );
        expect(fresh.warnings, isEmpty);
        expect(fresh.trail.escrowHash, checkedOf(fresh).paymentHash);
        storable(fresh, opened);
        // In the first contract, no earlier escrow exists: pinned as usual.
        final public = await along(s, [1]);
        final none = next(
          public,
          await made(
            6,
            role: s,
            changes: {'escrow_invoice': null, 'escrow_satoshis': null},
          ),
        );
        final pinned = next(none, await made(6, role: s));
        expect(pinned.warnings, isEmpty);
        expect(pinned.trail.escrowHash, checkedOf(pinned).paymentHash);
      },
    );
  });

  group('the maker\'s checks', () {
    test(
      'the maker bond at 0: within 2 % of the bond at the price of the creation',
      () async {
        final terms = madeTerms();
        final ceiling = terms.bondCeiling.value.toInt();
        for (final (sats, warned) in [
          (makerBond, false),
          (ceiling, false),
          (ceiling + 1, true),
          (makerBond ~/ 2, true),
        ]) {
          final status = TradeStatus.afterMake(
            await made(
              0,
              bond: makerBondInvoice(sats: sats, seed: 30 + sats % 7),
            ),
            terms: terms,
            now: tradeNow,
            reader: reader,
          );
          expect(status.has<BondAmountOutsideOrder>(), warned, reason: '$sats');
          expect(status.trail.breached, isFalse);
        }
        // The invoice's own amount is the bond's: `bond_satoshis` else.
        final mismatch = TradeStatus.afterMake(
          await made(0, changes: {'bond_satoshis': makerBond - 1}),
          terms: terms,
          now: tradeNow,
          reader: reader,
        );
        expect(
          checkedOf(mismatch).warnings.whereType<InvoiceAmountMismatch>(),
          hasLength(1),
        );
        // Another bond at 0: a breach.
        final bond = TradeStatus.afterMake(
          await made(0),
          terms: terms,
          now: tradeNow,
          reader: reader,
        );
        final changed = next(
          bond,
          await made(0, bond: makerBondInvoice(seed: 12)),
        );
        expect(
          checkedOf(changed).warnings.whereType<InvoiceHashChanged>(),
          hasLength(1),
        );
        expect(changed.trail.bondHash, bond.trail.bondHash);
      },
    );

    test(
      'no warning on the trade\'s sats against a price, and the gap said by side',
      () async {
        for (final role in [b, s]) {
          for (final last in [makerSats ~/ 2, makerSats, makerSats * 2]) {
            final status =
                next(
                      await along(role, [1]),
                      await made(6, role: role, last: last),
                    )
                    as WaitingForBoth;
            expect(status.warnings, isEmpty, reason: '$role $last');
            final gap = switch (status.rateGap) {
              final value? => value,
              null => fail('no gap'),
            };
            final effect = gap.effectFor(role);
            if (last < makerSats) {
              // Fewer sats: a higher rate, a positive gap.
              expect(gap.percent, greaterThan(99));
              expect(
                effect,
                role == b
                    ? RateGapEffect.unfavourable
                    : RateGapEffect.favourable,
              );
            } else if (last > makerSats) {
              expect(gap.percent, lessThan(-49));
              expect(
                effect,
                role == b
                    ? RateGapEffect.favourable
                    : RateGapEffect.unfavourable,
              );
            } else {
              expect(gap.percent.abs(), lessThan(0.001));
            }
          }
        }
      },
    );

    test('the amounts and the implied maker fee', () async {
      Future<List<TradeWarning>> warningsAt(
        TradeRole role,
        Map<String, Object?> changes, {
        Bolt11TestInvoice? escrow,
      }) async => next(
        await along(role, [1]),
        await made(6, role: role, changes: changes, escrow: escrow),
      ).warnings;

      final fee = makerFeeOf(makerSats);
      // The seller's escrow: equal to `trade_satoshis`, at most the announced fee over `last_satoshis`, plus a sat.
      expect(
        await warningsAt(s, {'trade_satoshis': makerSats + fee + 1}),
        contains(isA<EscrowAmountMismatch>()),
      );
      final most = (makerSats * makerFee).floor() + 1;
      final atMost = makerEscrowInvoice(take: 7, sats: makerSats + most);
      expect(
        await warningsAt(s, {
          'trade_satoshis': makerSats + most,
        }, escrow: atMost),
        isEmpty,
      );
      final above = makerEscrowInvoice(take: 8, sats: makerSats + most + 1);
      expect(
        await warningsAt(s, {
          'trade_satoshis': makerSats + most + 1,
        }, escrow: above),
        [isA<MakerFeeAboveAnnounced>()],
      );
      final below = makerEscrowInvoice(take: 9, sats: makerSats - 1);
      expect(
        await warningsAt(s, {'trade_satoshis': makerSats - 1}, escrow: below),
        [isA<MakerFeeAboveAnnounced>()],
      );
      // The buyer's payout: equal to `trade_satoshis`, the fee taken from it.
      expect(
        await warningsAt(b, {'invoice_amount': makerSats - fee - 1}),
        contains(isA<PayoutAmountMismatch>()),
      );
      expect(
        await warningsAt(b, {
          'invoice_amount': makerSats - most - 1,
          'trade_satoshis': makerSats - most - 1,
        }),
        [isA<MakerFeeAboveAnnounced>()],
      );
      expect(
        await warningsAt(b, {
          'invoice_amount': makerSats + 1,
          'trade_satoshis': makerSats + 1,
        }),
        [isA<MakerFeeAboveAnnounced>()],
      );
      // No `satoshis_now`: the fee cannot be told.
      expect(await warningsAt(b, {'satoshis_now': null}), [
        isA<MakerFeeAboveAnnounced>(),
      ]);
    });

    test('the order\'s terms, as the maker asked them', () async {
      for (final (label, wire, changes)
          in <(String, int, Map<String, Object?>)>[
            ('currency', 1, {'currency': 1}),
            ('premium', 1, {'premium': '2.50'}),
            ('premium missing', 1, {'premium': null}),
            ('bond size', 1, {'bond_size': '4.00'}),
            ('escrow duration', 1, {'escrow_duration': 7200}),
            ('payment method', 1, {'payment_method': 'Revolut'}),
            ('password', 1, {'has_password': true}),
            ('amount', 1, {'amount': '101.00000000'}),
            ('priced in sats', 1, {'is_explicit': true, 'satoshis': 100000}),
            ('public duration at 5', 5, {'public_duration': 3600}),
            ('public duration at 14', 14, {'public_duration': 3600}),
          ]) {
        final before = await along(
          b,
          label.contains('at 14') ? [1, 6, 9, 10] : [1],
        );
        final after = next(before, await made(wire, changes: changes));
        expect(after.has<TradeTermsChanged>(), isTrue, reason: label);
      }
      // A range's bounds.
      final range = await along(b, [1], range: true);
      expect(
        next(
          range,
          await made(2, range: true, changes: {'max_amount': '210.00000000'}),
          range: true,
        ).has<TradeTermsChanged>(),
        isTrue,
      );
    });
  });

  group('what a coordinator that lies can obtain', () {
    test(
      'a faked next contract for a second escrow, of any size: taken as a contract, with no warning (what bounds it is #187\'s rule of one escrow held at a time, `maker_escrow_from_wallet_test.dart`)',
      () async {
        final paid = await along(s, [1, 6]);
        final second = next(
          paid,
          await made(6, role: s, taker: third, deadline: deadline1, take: 1),
        );
        // Nothing tells it from a real take after a return to the book (design note § 3.2): this wallet pays its escrow only once the first one it paid is no longer held, under the owner's payment rule of 2026-11-17 (#187), which warns and never stops; the factor of the creation's price that bounded it before is gone.
        expect(second.warnings, isEmpty);
        expect(second.trail.take, 1);
        final huge = next(
          paid,
          await made(
            6,
            role: s,
            taker: third,
            deadline: deadline1,
            take: 2,
            last: 400000,
          ),
        );
        expect(huge.warnings, isEmpty);
        expect(huge.trail.take, 1);
        final escrow = huge.invoice;
        if (escrow is! CheckedInvoice) fail('no escrow');
        expect(
          walletPaymentFor(
            accepted: escrow.amount,
            status: huge,
            step: InvoiceStep.escrow,
            now: tradeNow,
          ),
          isA<WalletPaymentOffered>().having((o) => o.take, 'take', 1),
        );
      },
    );

    test(
      'a status going back, a role inverted, an order of another coordinator',
      () async {
        // 9 back to 6, under the same contract: unexpected.
        final chat = await along(b, [1, 6, 9]);
        expect(next(chat, await made(6)).has<TradeStatusUnexpected>(), isTrue);
        // 1 back to 0: refused.
        final public = await along(b, [1]);
        refused<TradeStatusRegressed>(next(public, await made(0)), public);
        // An end is never left.
        final done = await along(b, [1, 6, 9, 10, 14]);
        expect(identical(next(done, await made(9)), done), isTrue);
        // Another type, so the other side: the role refused.
        refused<TradeRoleMismatch>(
          next(
            public,
            await made(
              1,
              changes: {'type': 1, 'is_buyer': false, 'is_seller': true},
            ),
          ),
          public,
        );
        // This robot as the taker, or as no participant: as the taker on the maker's own side too (the buyer of a sell order), which only `is_maker` tells.
        refused<TradeRoleMismatch>(
          next(public, await readAnswer(orderJson(6, role: TradeRole.buyer))),
          public,
        );
        refused<TradeRoleMismatch>(
          next(public, await readAnswer(orderJson(1))),
          public,
        );
        refused<TradeRoleMismatch>(
          next(public, await readAnswer(orderJson(6, role: TradeRole.seller))),
          public,
        );
        // Another coordinator's order of the same number.
        final elsewhere = TradeOrderRead(
          await readOrder(makerOrderJson(1), alias: 'lake'),
        );
        refused<TradeOrderMismatch>(next(public, elsewhere), public);
        // Error 1044, which a maker is never given.
        refused<TradeStatusUnexpected>(
          next(public, const TradeOrderNotAvailable()),
          public,
        );
      },
    );
  });

  group('the reference\'s own sequences, read with gaps', () {
    /// [seeds] orders of the reference read now and then, the clock moving a few seconds at each read; with [secondClient], the maker also acts from another client.
    Future<(int, int, int)> sequences(
      int seeds, {
      required int first,
      bool secondClient = false,
    }) async {
      var contracts = 0;
      var nexts = 0;
      var late = 0;
      for (var seed = first; seed < first + seeds; seed++) {
        final random = Random(seed);
        final role = random.nextBool() ? b : s;
        final range = random.nextBool();
        final reference = MakerReference(
          role,
          range: range,
          random: random,
          secondClient: secondClient,
        );
        final terms = reference.terms();
        var now = tradeNow;
        var status = TradeStatus.afterMake(
          await reference.read(decoder),
          terms: terms,
          now: now,
          reader: reader,
        );
        for (var step = 0; step < 60 && !status.isTerminal; step++) {
          reference.step();
          // The app reads after about one event in three, and always at the end.
          if (!reference.ended && random.nextInt(secondClient ? 8 : 3) != 0) {
            continue;
          }
          now = now.add(Duration(seconds: random.nextInt(6)));
          final before = status;
          status = next(
            before,
            await reference.read(decoder),
            range: range,
            now: now,
          );
          final label = 'seed $seed step $step $role range $range: $status';
          if (status.has<ContractSeenLate>()) {
            late++;
            expect(secondClient, isTrue, reason: label);
          }
          expect(
            status.warnings.where((w) => w is! ContractSeenLate),
            isEmpty,
            reason: label,
          );
          expect(status.trail.breached, isFalse, reason: label);
          expect(status.trail.take, greaterThanOrEqualTo(before.trail.take));
          expect(status.trail.take - before.trail.take, lessThanOrEqualTo(1));
          if (status.trail.take > before.trail.take) nexts++;
          expect(status.trail.take, lessThanOrEqualTo(reference.takes));
          // The contract's taker is the reference's own, whenever the app keeps one.
          if ((reference.taker, status.trail.takerHashId)
              case (final taker?, final kept?)
              when !const {
                TradePosition.public,
                TradePosition.paused,
                TradePosition.expired,
                TradePosition.cancelled,
              }.contains(status.position)) {
            expect(kept, taker.hashId.hex, reason: label);
          }
          if (before.trail.bondHash case final bond?) {
            expect(status.trail.bondHash, bond, reason: label);
          }
          expect(
            status.trail.record.whyNotReplace(
              before.trail.record,
              madeHere: true,
            ),
            isNull,
            reason: label,
          );
          // Restored from its record, the trail reads the next answer as the trail in memory does.
          final restored = TradeTrail.restore(
            status.trail.record,
            terms: madeTerms(role: role, range: range),
            now: now,
          );
          expect(
            switch (restored) {
              Ok(:final value) => value == status.trail,
              Err() => false,
            },
            isTrue,
            reason: label,
          );
          // An escrow is its contract's own.
          if (status.invoice case final CheckedInvoice escrow
              when escrow.step == InvoiceStep.escrow) {
            expect(
              escrow.paymentHash,
              makerEscrowInvoice(take: reference.takes).facts.paymentHash,
              reason: label,
            );
          }
        }
        contracts += reference.takes;
      }
      return (contracts, nexts, late);
    }

    test(
      'never a refusal or a warning, a contract only forward, every trail storable and restored as it was',
      () async {
        final (contracts, nexts, late) = await sequences(300, first: 0);
        // The sequences went through contracts, and next ones.
        expect(contracts, greaterThan(100));
        expect(nexts, greaterThan(10), reason: 'contracts $contracts');
        expect(late, 0);
      },
    );

    test(
      'with the maker acting from another client too: never a breach, a next contract seen late said as information',
      () async {
        final (contracts, nexts, late) = await sequences(
          3000,
          first: 10000,
          secondClient: true,
        );
        expect(contracts, greaterThan(1000));
        expect(late, greaterThanOrEqualTo(25), reason: 'nexts $nexts');
      },
    );
  });

  group('answers of a coordinator that lies, at random', () {
    test(
      'an end never left, a contract never back, no escrow of an earlier contract offered, every trail storable',
      () async {
        for (var seed = 0; seed < 150; seed++) {
          final random = Random(1000 + seed);
          final role = random.nextBool() ? b : s;
          var status = TradeStatus.afterMake(
            await made(0, role: role),
            terms: madeTerms(role: role),
            now: tradeNow,
            reader: reader,
          );
          final escrowsByTake = <String, int>{};
          for (var step = 0; step < 40; step++) {
            final before = status;
            const wires = [
              0,
              1,
              2,
              4,
              5,
              6,
              7,
              8,
              9,
              10,
              11,
              12,
              13,
              14,
              15,
              16,
              17,
              18,
            ];
            final TradeAnswer answer;
            switch (random.nextInt(12)) {
              case 0:
                answer = const TradeOrderCancelled();
              case 1:
                answer = const TradeOrderNotAvailable();
              default:
                final wire = wires[random.nextInt(wires.length)];
                answer = await made(
                  wire,
                  role: role,
                  taker: [peer, third, robotOfTests(3)][random.nextInt(3)],
                  deadline: deadline0.add(
                    Duration(minutes: random.nextInt(7) * 10 - 20),
                  ),
                  take: random.nextInt(4),
                  last: 50000 + random.nextInt(100000),
                );
            }
            status = next(before, answer);
            final label = 'seed $seed step $step: $before → $status';
            if (before.isTerminal) {
              expect(status.position, before.position, reason: label);
            }
            expect(status.trail.take, greaterThanOrEqualTo(before.trail.take));
            expect(status.trail.take - before.trail.take, lessThanOrEqualTo(1));
            if (before.trail.breached) {
              expect(status.trail.breached, isTrue, reason: label);
            }
            if (!identical(status, before)) {
              expect(
                status.trail.record.whyNotReplace(
                  before.trail.record,
                  madeHere: true,
                ),
                isNull,
                reason: label,
              );
            }
            if (status.invoice case final CheckedInvoice escrow
                when escrow.step == InvoiceStep.escrow) {
              final offered = walletPaymentFor(
                accepted: Sats.fromInt(1 << 40),
                status: status,
                step: InvoiceStep.escrow,
                now: tradeNow,
              );
              final seenAt = escrowsByTake[escrow.paymentHash];
              if (offered is WalletPaymentOffered) {
                // Offered only in the contract it was first seen in.
                expect(
                  seenAt == null || seenAt == offered.take,
                  isTrue,
                  reason: label,
                );
                escrowsByTake.putIfAbsent(
                  escrow.paymentHash,
                  () => offered.take,
                );
              }
            }
          }
        }
      },
    );
  });

  group('every trail of the reference\'s sequences, written to p2p.sqlite schema 8', () {
    const testnet = RobosatsNetwork.testnet;
    final fingerprint = switch (GarageKey.fromBytes(
      Uint8List.fromList(List<int>.generate(32, (i) => 3 + i)),
    )) {
      Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      },
      Err(:final failure) => throw StateError('$failure'),
    };
    final temple = switch (CoordinatorIdentity.of(
      coordinator('temple'),
      testnet,
    )) {
      final identity? => identity,
      null => throw StateError('temple is not on testnet'),
    };

    bool stored(Result<TrailStoreOutcome, P2pFailure> outcome) =>
        switch (outcome) {
          Ok(value: TrailStored()) => true,
          _ => false,
        };

    /// [seeds] orders of the reference, every trail written by the real repository to a database of its own; with [secondClient], the maker also acts from another client.
    Future<(int, int, int)> written(
      int seeds, {
      required int first,
      bool secondClient = false,
    }) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      var writes = 0;
      var nexts = 0;
      var late = 0;
      for (var seed = first; seed < first + seeds; seed++) {
        // A database of its own for each order made, whose number is the tests' one.
        final database = P2pDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final bindings = bindingsInMemory(database: database);
        final trades = TradeRecordRepositoryImpl(
          database,
          clock: () => tradeNow,
        );
        final trails = TradeTrailRepositoryImpl(database);
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprint),
          isA<Ok>(),
        );
        final random = Random(seed);
        final role = random.nextBool() ? b : s;
        final range = random.nextBool();
        final reference = MakerReference(
          role,
          range: range,
          random: random,
          secondClient: secondClient,
        );
        final terms = reference.terms(network: testnet);
        final reservation = switch (await trades.reserveForNewTrade(
          RobotSlot(testnet, fingerprint, 0),
          temple,
        )) {
          Ok(value: final reservation?) => reservation,
          final other => fail('not reserved: $other'),
        };
        final make = switch (await trades.recordPendingMake(
          reservation,
          role: role,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          await trails.recordMakerTerms(make, terms.side.maker.record),
          isA<Ok>(),
        );
        final record = switch (await trades.confirmMake(
          make,
          orderId: terms.orderId,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };

        var now = tradeNow;
        var status = TradeStatus.afterMake(
          await reference.read(decoder, network: testnet),
          terms: terms,
          now: now,
          reader: reader,
        );
        expect(
          stored(await trails.storeTrail(record, status.trail.record)),
          isTrue,
        );
        for (var step = 0; step < 60 && !status.isTerminal; step++) {
          reference.step();
          if (!reference.ended && random.nextInt(secondClient ? 8 : 3) != 0) {
            continue;
          }
          // The clock moves at each read, by up to five seconds.
          now = now.add(Duration(seconds: random.nextInt(6)));
          final before = status;
          status = TradeStatus.from(
            previous: before,
            answer: await reference.read(decoder, network: testnet),
            terms: terms,
            now: now,
            reader: reader,
          );
          if (status.has<ContractSeenLate>()) late++;
          expect(
            status.warnings.where((w) => w is! ContractSeenLate),
            isEmpty,
            reason: 'seed $seed: $status',
          );
          if (status.trail.take > before.trail.take) nexts++;
          expect(
            stored(await trails.storeTrail(record, status.trail.record)),
            isTrue,
            reason: 'seed $seed step $step: $before → $status',
          );
          writes++;
        }
        final history = switch (await trails.historyOf(record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.trail, status.trail.record, reason: 'seed $seed');
      }
      return (writes, nexts, late);
    }

    test(
      'an escrow of an earlier contract stays refused after a restart, from the stored trail alone',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final database = P2pDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final bindings = bindingsInMemory(database: database);
        final trades = TradeRecordRepositoryImpl(
          database,
          clock: () => tradeNow,
        );
        final trails = TradeTrailRepositoryImpl(database);
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprint),
          isA<Ok>(),
        );
        final terms = madeTerms(role: s, network: testnet);
        final reservation = switch (await trades.reserveForNewTrade(
          RobotSlot(testnet, fingerprint, 0),
          temple,
        )) {
          Ok(value: final reservation?) => reservation,
          final other => fail('not reserved: $other'),
        };
        final make = switch (await trades.recordPendingMake(
          reservation,
          role: s,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          await trails.recordMakerTerms(make, terms.side.maker.record),
          isA<Ok>(),
        );
        final record = switch (await trades.confirmMake(
          make,
          orderId: terms.orderId,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        Bolt11TestInvoice escrowOf(int take) =>
            makerEscrowInvoice(take: take, network: Bolt11Network.testnet);
        Future<TradeAnswer> read(
          int status, {
          RobotIdentity? taker,
          DateTime? deadline,
          Bolt11TestInvoice? escrow,
        }) async {
          final bond = makerBondInvoice(network: Bolt11Network.testnet);
          final invoice = escrow ?? escrowOf(0);
          decoder
            ..add(bond)
            ..add(invoice);
          return readAnswer(
            makerOrderJson(
              status,
              role: s,
              taker: taker,
              deadline: deadline,
              bond: bond,
              escrow: invoice,
            ),
            network: testnet,
          );
        }

        var status = TradeStatus.afterMake(
          await read(0),
          terms: terms,
          now: tradeNow,
          reader: reader,
        );
        for (final answer in [
          await read(1),
          await read(6),
          // Contract 1, read at 8: no escrow, the one of contract 0 kept as earlier.
          await read(8, taker: third, deadline: deadline1),
        ]) {
          status = TradeStatus.from(
            previous: status,
            answer: answer,
            terms: terms,
            now: tradeNow,
            reader: reader,
          );
          expect(switch (await trails.storeTrail(record, status.trail.record)) {
            Ok(value: TrailStored()) => true,
            _ => false,
          }, isTrue);
        }
        // The app killed: the trail is read back and restored alone.
        final stored = switch (await trails.historyOf(record)) {
          Ok(value: StoredTradeHistory(trail: final trail?)) => trail,
          final other => fail('$other'),
        };
        expect(stored.earlierEscrows, '${escrowOf(0).facts.paymentHash};');
        final restored = switch (TradeTrail.restore(
          stored,
          terms: terms,
          now: tradeNow,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final contract2 = TradeStatus.from(
          previous: TradeStatus.beforeFirstRead(restored),
          answer: await read(
            6,
            taker: peer,
            deadline: deadline1.add(const Duration(hours: 1)),
            escrow: escrowOf(0),
          ),
          terms: terms,
          now: tradeNow,
          reader: reader,
        );
        expect(
          checkedOf(contract2).warnings.whereType<EscrowNotOfThisContract>(),
          hasLength(1),
        );
        expect(switch (await trails.storeTrail(
          record,
          contract2.trail.record,
        )) {
          Ok(value: TrailStored()) => true,
          _ => false,
        }, isTrue);
        // Whatever the code, the database never pins it again.
        await expectLater(
          database.customStatement(
            "UPDATE trade_trails SET escrow_hash = '${escrowOf(0).facts.paymentHash}', read_at = read_at + 1",
          ),
          throwsA(
            predicate((e) => '$e'.contains('a trail only moves forward')),
          ),
        );
      },
    );

    test(
      'the database writes every one of them, next contracts\' escrows included',
      () async {
        final (writes, nexts, late) = await written(120, first: 5000);
        expect(writes, greaterThan(200));
        expect(nexts, greaterThanOrEqualTo(12), reason: 'writes $writes');
        expect(late, 0);
      },
    );

    test(
      'and with the maker acting from another client too, next contracts seen late included',
      () async {
        final (writes, nexts, late) = await written(
          1000,
          first: 20000,
          secondClient: true,
        );
        expect(writes, greaterThan(100));
        expect(
          late,
          greaterThanOrEqualTo(7),
          reason: 'nexts $nexts, writes $writes',
        );
      },
    );
  });
}
