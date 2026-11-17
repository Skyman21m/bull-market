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
  }) => TradeStatus.from(
    previous: previous,
    answer: answer,
    terms: madeTerms(role: previous.trail.role, range: range),
    now: tradeNow,
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

    test(
      'a range: the amount kept, changed or outside the range said',
      () async {
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
        final outside = next(
          public,
          await made(6, range: true, taken: 250),
          range: true,
        );
        expect(outside.has<TradeTermsChanged>(), isTrue);
        expect((outside as WaitingForBoth).rateGap, isNull);
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
      },
    );
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
      'shown after a next contract opened without one: refused, it cannot be told from an earlier one',
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
        for (final escrow in [
          makerEscrowInvoice(take: 0),
          makerEscrowInvoice(take: 1),
        ]) {
          final after = next(
            opened,
            await made(
              6,
              role: s,
              taker: third,
              deadline: deadline1,
              escrow: escrow,
            ),
          );
          expect(
            checkedOf(after).warnings.whereType<EscrowNotOfThisContract>(),
            hasLength(1),
          );
          expect(after.trail.escrowHash, isNull);
          storable(after, opened);
        }
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
            final gap = status.rateGap;
            expect(gap, isNotNull);
            gap!;
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
      'a faked next contract for a second escrow: taken as a contract, bounded by the wallet\'s ceiling',
      () async {
        final paid = await along(s, [1, 6]);
        final second = next(
          paid,
          await made(6, role: s, taker: third, deadline: deadline1, take: 1),
        );
        // Nothing tells it from a real take after a return to the book (design note § 3.2): this wallet pays it only under the ceiling of the contract's amount, and #187 only once the first escrow is no longer held.
        expect(second.warnings, isEmpty);
        final ceiling = madeTerms(role: s).side.maker.escrowCeilingFor(null);
        expect(ceiling, isNotNull);
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
        expect(
          walletPaymentFor(
            accepted: ceiling!,
            status: huge,
            step: InvoiceStep.escrow,
            now: tradeNow,
          ),
          isA<WalletPaymentRefused>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.aboveAccepted,
          ),
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
    test(
      'never a refusal or a warning, a contract only forward, every trail storable and restored as it was',
      () async {
        var contracts = 0;
        var nexts = 0;
        for (var seed = 0; seed < 300; seed++) {
          final random = Random(seed);
          final role = random.nextBool() ? b : s;
          final range = random.nextBool();
          final reference = MakerReference(role, range: range, random: random);
          final terms = reference.terms();
          var status = TradeStatus.afterMake(
            await reference.read(decoder),
            terms: terms,
            now: tradeNow,
            reader: reader,
          );
          for (var step = 0; step < 60 && !status.isTerminal; step++) {
            reference.step();
            // The app reads after about one event in three, and always at the end.
            if (!reference.ended && random.nextInt(3) != 0) continue;
            final before = status;
            status = next(before, await reference.read(decoder), range: range);
            final label = 'seed $seed step $step $role range $range: $status';
            expect(status.warnings, isEmpty, reason: label);
            expect(status.trail.breached, isFalse, reason: label);
            expect(status.trail.take, greaterThanOrEqualTo(before.trail.take));
            expect(status.trail.take - before.trail.take, lessThanOrEqualTo(1));
            if (status.trail.take > before.trail.take) nexts++;
            expect(status.trail.take, lessThanOrEqualTo(reference.takes));
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
              now: tradeNow,
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
        // The sequences went through contracts, and next ones.
        expect(contracts, greaterThan(100));
        expect(nexts, greaterThan(10), reason: 'contracts $contracts');
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

  group(
    'every trail of the reference\'s sequences, written to p2p.sqlite schema 8',
    () {
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

      test(
        'the database writes every one of them, a next contract\'s escrow included',
        () async {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
          var written = 0;
          var nexts = 0;
          for (var seed = 0; seed < 80; seed++) {
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
            final random = Random(5000 + seed);
            final role = random.nextBool() ? b : s;
            final range = random.nextBool();
            final reference = MakerReference(
              role,
              range: range,
              random: random,
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

            var status = TradeStatus.afterMake(
              await reference.read(decoder, network: testnet),
              terms: terms,
              now: tradeNow,
              reader: reader,
            );
            expect(
              stored(await trails.storeTrail(record, status.trail.record)),
              isTrue,
            );
            for (var step = 0; step < 50 && !status.isTerminal; step++) {
              reference.step();
              if (!reference.ended && random.nextInt(3) != 0) continue;
              final before = status;
              status = TradeStatus.from(
                previous: before,
                answer: await reference.read(decoder, network: testnet),
                terms: terms,
                now: tradeNow,
                reader: reader,
              );
              expect(status.warnings, isEmpty, reason: 'seed $seed: $status');
              if (status.trail.take > before.trail.take) nexts++;
              expect(
                stored(await trails.storeTrail(record, status.trail.record)),
                isTrue,
                reason: 'seed $seed step $step: $before → $status',
              );
              written++;
            }
            final history = switch (await trails.historyOf(record)) {
              Ok(:final value) => value,
              Err(:final failure) => fail('$failure'),
            };
            expect(history.trail, status.trail.record, reason: 'seed $seed');
          }
          expect(written, greaterThan(120));
          expect(nexts, greaterThan(3), reason: 'written $written');
        },
      );
    },
  );
}
