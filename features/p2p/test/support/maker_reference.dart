import 'dart:math';

import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:robosats/robosats.dart';

import 'maker_orders.dart';
import 'trade_orders.dart';

/// One order made here, as the reference coordinator lives it (`api/logics.py`, `api/views.py`, `follow_invoices.py`, `clean_orders.py`, commit ff1998c), moved by random events of the coordinator, the takers and the maker, and read by this app now and then (design note `docs/design/phase-3-making-an-order.md` § 1.1 to § 1.10).
///
/// With [secondClient], the maker also acts from another client with the same Garage Key (the official app, as the owner's trials do), so its own steps happen whether this app read them or not, and each take is by a robot that never took the order before (a take by the very same robot, read from 6, 7 or 8 at 9 or later, is not told from the same contract: a known limit, tested apart).
///
/// Otherwise the maker acts only on what this app showed it: it locks its bond after a read at 0, its escrow after a read of the current contract at 6 or 7, gives its payout after a read of the current contract at 6 or 8, cancels alone after a read at 6 or 7, says « fiat sent » or « received » after a read in the chat. Everything else (takes, the takers' steps, cancels and timeouts, returns to the book, expiries, disputes) happens whether the app reads or not, so that the reads have the gaps of an app left closed.
final class MakerReference {
  final TradeRole role;
  final bool range;
  final Random random;
  final bool secondClient;

  /// What the reference's order is at: its status (1043 for a cancel), the number of takes so far, the current contract's taker, amount, sats and deadline, and whether a taker is still named at 5.
  int status = 0;
  int takes = 0;
  RobotIdentity? taker;
  double taken = 120;
  int last = makerSats;
  bool expiredWithTaker = false;
  bool escrowLocked = false;
  bool payoutGiven = false;

  /// What the app's last read showed: the status and the contract.
  int? seenStatus;
  int? seenTake;

  MakerReference(
    this.role, {
    required this.range,
    required this.random,
    this.secondClient = false,
  });

  static final Map<int, RobotIdentity> _freshRobots = {};

  static RobotIdentity _fresh(int take) =>
      _freshRobots.putIfAbsent(take, () => robotOfTests(10 + take));

  bool get ended => const [5, 14, 17, 18, 1043].contains(status);

  bool get _makerBuys => role == TradeRole.buyer;

  bool _seenAt(List<int> statuses) =>
      secondClient || (seenTake == takes && statuses.contains(seenStatus));

  static final _takers = [peer, third, robotOfTests(3)];

  /// The deadline the reference gives the contract of take [k] (1 for the first): the lock's time and the escrow duration, later at each take.
  static DateTime deadlineOf(int k) => deadline0.add(Duration(minutes: 37 * k));

  /// One event of the reference, chosen at random among those that can happen now.
  void step() {
    // Each event with a weight: the ends that cut an order short (an expiry, a cancel) are rare, so that sequences go through contracts and returns to the book.
    final events = <void Function()>[];
    void weighted(int weight, void Function() event) {
      for (var i = 0; i < weight; i++) {
        events.add(event);
      }
    }

    void to(int next, [int weight = 4]) =>
        weighted(weight, () => status = next);
    void take() => weighted(8, () {
      takes++;
      // With a second client, a robot that never took this order before.
      taker = secondClient
          ? _fresh(takes)
          : _takers[random.nextInt(_takers.length)];
      taken = range ? 50.0 + random.nextInt(151) : 120;
      last = 40000 + random.nextInt(200000);
      escrowLocked = false;
      payoutGiven = false;
      expiredWithTaker = false;
      status = 6;
    });
    void backToBook() => weighted(8, () {
      taker = null;
      escrowLocked = false;
      payoutGiven = false;
      status = 1;
    });
    void expireTaken() => weighted(1, () {
      expiredWithTaker = true;
      status = 5;
    });
    switch (status) {
      case 0:
        if (seenStatus == 0 || secondClient) to(1);
        to(5, 1);
        to(1043, 1);
      case 1:
        to(2, 1);
        take();
        to(5, 1);
        if (seenStatus != null) to(1043, 1);
      case 2:
        to(1);
        to(5, 1);
        if (seenStatus != null) to(1043, 1);
      case 6:
        // The buyer's payout, the seller's escrow: the taker's whenever, the maker's after a read of this contract.
        if (!_makerBuys || _seenAt(const [6, 8])) {
          weighted(4, () {
            payoutGiven = true;
            status = escrowLocked ? 9 : 7;
          });
        }
        if (_makerBuys || _seenAt(const [6, 7])) {
          weighted(4, () {
            escrowLocked = true;
            status = 8;
          });
        }
        backToBook(); // the taker cancelled
        expireTaken(); // neither in time
        if (_seenAt(const [6, 7])) to(1043, 1); // this maker cancelled
      case 7:
        if (_makerBuys || _seenAt(const [6, 7])) to(9);
        backToBook(); // the taker cancelled
        if (_makerBuys) {
          backToBook(); // the taker seller did not lock
        } else {
          expireTaken(); // this maker seller did not lock
        }
        if (_seenAt(const [6, 7])) to(1043, 1);
      case 8:
        if (!_makerBuys || _seenAt(const [6, 8])) to(9);
        if (_makerBuys) {
          expireTaken(); // this maker buyer gave no payout
        } else {
          backToBook(); // the taker buyer gave no payout
        }
        if (_seenAt(const [8])) to(1043, 1); // both asked to cancel
      case 9:
        if (!_makerBuys || _seenAt(const [9])) to(10);
        to(11, 1);
        if (_seenAt(const [9])) to(1043, 1);
      case 10:
        if (!_makerBuys || _seenAt(const [10])) to(9);
        if (_makerBuys || _seenAt(const [10])) {
          to(13);
          to(14);
        }
        to(11);
      case 11:
        to(16);
        to(17);
        to(18);
        to(1043);
        to(13);
      case 16:
        to(17);
        to(18);
        to(1043);
        to(13);
      case 13:
        to(14);
        to(15);
      case 15:
        to(13);
        to(14);
    }
    if (events.isEmpty) return;
    events[random.nextInt(events.length)]();
  }

  /// The answer this app reads now, its invoices made readable by [decoder]; [network] is the order's.
  Future<TradeAnswer> read(
    Bolt11TestDecoder decoder, {
    RobosatsNetwork network = RobosatsNetwork.mainnet,
  }) async {
    seenStatus = status;
    seenTake = takes;
    if (status == 1043) return const TradeOrderCancelled();
    final invoiceNetwork = network == RobosatsNetwork.mainnet
        ? Bolt11Network.mainnet
        : Bolt11Network.testnet;
    final bond = makerBondInvoice(network: invoiceNetwork);
    final escrow = makerEscrowInvoice(
      take: takes,
      sats: makerEscrowOf(last),
      network: invoiceNetwork,
    );
    decoder
      ..add(bond)
      ..add(escrow);
    final named = status >= 6 || (status == 5 && expiredWithTaker);
    return readAnswer(
      makerOrderJson(
        status,
        role: role,
        range: range,
        last: last,
        taker: named ? taker : null,
        deadline: deadlineOf(takes),
        taken: taken,
        bond: bond,
        escrow: escrow,
      ),
      network: network,
    );
  }

  /// The terms of this order on [network].
  TradeTerms<MadeSide> terms({
    RobosatsNetwork network = RobosatsNetwork.mainnet,
  }) => madeTerms(role: role, range: range, network: network);
}
