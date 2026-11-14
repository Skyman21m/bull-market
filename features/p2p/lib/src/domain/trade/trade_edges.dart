import 'trade_terms.dart';

/// Where a taker's trade stands, as the edges of the state machine see it: one position per status a taker is shown, and the three answers that are not an order of the trade.
enum TradePosition {
  /// No answer read yet since the take (or, for a trade found by recovery, since it was found): only the take's own answers may come first.
  start,

  /// 3: the pre-take, waiting for the taker bond.
  bondStep,

  /// Error 1044 while holding the pre-take, before the pre-take is certainly gone: the order paused, or another robot's bond locked first.
  preTakeUnavailable,

  /// 6.
  waitingForBoth,

  /// 7.
  waitingForEscrow,

  /// 8.
  waitingForPayout,

  /// 9.
  chatting,

  /// 10.
  fiatSent,

  /// 11.
  inDispute,

  /// 13.
  sendingSats,

  /// 14.
  succeeded,

  /// 15.
  routingFailed,

  /// 16.
  waitingDisputeResolution,

  /// 17: the maker lost the dispute, so this taker won it.
  makerLostDispute,

  /// 18: this taker lost the dispute.
  takerLostDispute,

  /// 5.
  expired,

  /// Error 1043: cancelled, by one side (4) or by both (12).
  cancelled,

  /// Public again, and this robot no longer a participant.
  publicAgain,

  /// Error 1044: this robot is no participant of an order that is not public.
  notAvailable;

  /// Whether the trade is over for this robot: a terminal position is never left (a later answer may only refresh it).
  bool get isTerminal => switch (this) {
    succeeded ||
    makerLostDispute ||
    takerLostDispute ||
    expired ||
    cancelled ||
    publicAgain ||
    notAvailable => true,
    _ => false,
  };
}

/// The edges a taker's trade may take between two reads, from the reference backend at commit ff1998c (design note § 1.1-1.5, § 3.2, as corrected by #86).
///
/// [steps] lists each single move the backend makes, with the roles it happens to and where; [allows] admits any path of them, since several moves can happen between two reads (a poll every 3 to 300 s, nothing while the app is closed).
abstract final class TradeEdges {
  static const _both = {TradeRole.buyer, TradeRole.seller};
  static const _buyer = {TradeRole.buyer};

  /// Each single move of the backend for a taker, by origin: the destination and the roles of this robot it happens to.
  static const Map<TradePosition, Map<TradePosition, Set<TradeRole>>> steps = {
    // The answer to the take itself, or the first read after a take whose answer was lost: the pre-take (`api/views.py:381-396`), or the order out of reach because the take did not happen (`api/views.py:595-596`: public, 1044 or 1043). No step from here goes further: a bond needs the invoice that only the pre-take gives.
    TradePosition.start: {
      TradePosition.bondStep: _both,
      TradePosition.publicAgain: _both,
      TradePosition.preTakeUnavailable: _both,
      TradePosition.cancelled: _both,
    },
    TradePosition.bondStep: {
      // The bond locks first: `finalize_contract` (`follow_invoices.py:243-251`, `api/logics.py:1320-1380`).
      TradePosition.waitingForBoth: _both,
      // The pre-take expires (`clean_orders.py:89-97`) or is cancelled (`api/logics.py:1061-1075`): the order is public, this robot no participant (`api/views.py:287-299`).
      TradePosition.publicAgain: _both,
      // Error 1044 (`api/views.py:269-275`, which tests `order.taker`, not the pre-take): the maker paused the order, which does not expire pre-takes (`api/logics.py:1758-1783`), another taker's bond locked first (`follow_invoices.py:252-261`), or the order expired (`api/logics.py:340-358`).
      TradePosition.preTakeUnavailable: _both,
      // The same, read once the pre-take is certainly gone (its deadline and the coordinator's loops, `clean_orders.py:89-97`).
      TradePosition.notAvailable: _both,
      // The maker cancelled the public order (`api/logics.py:1048-1060`): error 1043.
      TradePosition.cancelled: _both,
    },
    TradePosition.preTakeUnavailable: {
      // The maker resumed the order (`api/logics.py:1769-1773`): the pre-take shows again, with the same invoice (`api/logics.py:1393-1399`).
      TradePosition.bondStep: _both,
      // The bond locked while the order was public again: `finalize_contract` (`follow_invoices.py:243-251`).
      TradePosition.waitingForBoth: _both,
      // The pre-take expired, the order public again (`clean_orders.py:89-97`).
      TradePosition.publicAgain: _both,
      // Still out of reach once the pre-take is certainly gone.
      TradePosition.notAvailable: _both,
      // The maker cancelled the order (`api/logics.py:1048-1060`).
      TradePosition.cancelled: _both,
    },
    TradePosition.waitingForBoth: {
      // The buyer's payout is in (`api/logics.py:920-935`).
      TradePosition.waitingForEscrow: _both,
      // The seller's escrow locked (`api/logics.py:1469-1474`).
      TradePosition.waitingForPayout: _both,
      // The payout came while the escrow was already locked (`api/logics.py:926-933`).
      TradePosition.chatting: _both,
      // Neither came in time: both bonds settled (`api/logics.py:360-379`).
      TradePosition.expired: _both,
      // This taker cancelled: its bond settled, the order public again (`api/logics.py:1108-1130`).
      TradePosition.publicAgain: _both,
      // The maker cancelled: its bond settled, this taker's returned (`api/logics.py:1083-1106`).
      TradePosition.cancelled: _both,
    },
    TradePosition.waitingForEscrow: {
      // The escrow locked (`api/logics.py:1475-1481`).
      TradePosition.chatting: _both,
      // The maker, the seller, did not lock it: this buyer's bond returned (`api/logics.py:381-402`); or, for both roles, the cleaner could not find a hold invoice while expiring the order and set it expired (`clean_orders.py:72-81`).
      TradePosition.expired: _both,
      // This taker cancelled (`api/logics.py:1108-1130`), or as the seller did not lock the escrow (`api/logics.py:404-421`): its bond settled.
      TradePosition.publicAgain: _both,
      // The maker cancelled (`api/logics.py:1083-1106`).
      TradePosition.cancelled: _both,
    },
    TradePosition.waitingForPayout: {
      // The payout came (`api/logics.py:912-918`).
      TradePosition.chatting: _both,
      // The maker, the buyer, gave no payout: this seller's bond and escrow returned (`api/logics.py:423-443`); or, for both roles, a hold invoice the cleaner could not find (`clean_orders.py:72-81`).
      TradePosition.expired: _both,
      // This taker, the buyer, gave no payout: its bond settled (`api/logics.py:445-458`).
      TradePosition.publicAgain: _buyer,
      // Both asked to cancel (`api/logics.py:1138-1159`).
      TradePosition.cancelled: _both,
    },
    TradePosition.chatting: {
      // « Fiat sent » (`api/logics.py:1686-1735`).
      TradePosition.fiatSent: _both,
      // A dispute, opened by either side or when the chat's time ran out (`api/logics.py:460-468`, `:485-534`).
      TradePosition.inDispute: _both,
      // Both asked to cancel.
      TradePosition.cancelled: _both,
      // The chat's time ran out and opening the dispute failed on a hold invoice the cleaner could not find: the order is set expired (`clean_orders.py:72-81`, `api/logics.py:460-468`).
      TradePosition.expired: _both,
    },
    TradePosition.fiatSent: {
      // « Payment failed? »: the buyer takes « fiat sent » back (`api/logics.py:1737-1756`).
      TradePosition.chatting: _both,
      TradePosition.inDispute: _both,
      // The seller confirms: a Lightning payout (`api/logics.py:1645`), or at once an on-chain one (`:1653-1668`, `:1677`).
      TradePosition.sendingSats: _both,
      TradePosition.succeeded: _both,
      // As from 9 (`clean_orders.py:72-81`).
      TradePosition.expired: _both,
    },
    TradePosition.inDispute: {
      // Both statements are in (`api/logics.py:536-569`).
      TradePosition.waitingDisputeResolution: _both,
      // The coordinator decides (`api/admin.py:195-350`): maker wins, taker wins, everything returned, or the trade completed.
      TradePosition.takerLostDispute: _both,
      TradePosition.makerLostDispute: _both,
      TradePosition.cancelled: _both,
      TradePosition.sendingSats: _both,
    },
    TradePosition.waitingDisputeResolution: {
      TradePosition.takerLostDispute: _both,
      TradePosition.makerLostDispute: _both,
      TradePosition.cancelled: _both,
      TradePosition.sendingSats: _both,
    },
    // Back in the book without this robot, the order goes on without it: another robot takes it, it expires or is paused (error 1044), or its maker cancels it (error 1043). Only the closure uses these steps: a terminal position is never left.
    TradePosition.publicAgain: {
      TradePosition.notAvailable: _both,
      TradePosition.cancelled: _both,
    },
    TradePosition.sendingSats: {
      // The payout succeeded or failed (`api/lightning/lnd.py`, `cln.py:682-842`, `api/logics.py:1677`).
      TradePosition.succeeded: _both,
      TradePosition.routingFailed: _both,
    },
    TradePosition.routingFailed: {
      // A new invoice or a retry (`api/logics.py:938-944`), or a retry that succeeds (`:1677`).
      TradePosition.sendingSats: _both,
      TradePosition.succeeded: _both,
    },
  };

  static final Map<TradeRole, Map<TradePosition, Set<TradePosition>>>
  _reachable = {for (final role in TradeRole.values) role: _closure(role)};

  /// Whether a trade of a taker of [role] may be at [to] at a read after a read at [from]: the same position, or one reachable through [steps].
  ///
  /// From [TradePosition.start], only the single steps listed: the first answer after a take is the take's own, and nothing can have happened before it.
  static bool allows(TradeRole role, TradePosition from, TradePosition to) {
    if (from == to) return true;
    if (from == TradePosition.start) {
      return steps[from]?[to]?.contains(role) ?? false;
    }
    return _reachable[role]?[from]?.contains(to) ?? false;
  }

  static Map<TradePosition, Set<TradePosition>> _closure(TradeRole role) {
    final reachable = <TradePosition, Set<TradePosition>>{};
    for (final origin in TradePosition.values) {
      final seen = <TradePosition>{};
      final pending = [origin];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        for (final MapEntry(key: next, value: roles)
            in (steps[current] ?? const {}).entries) {
          if (roles.contains(role) && seen.add(next)) pending.add(next);
        }
      }
      reachable[origin] = seen;
    }
    return reachable;
  }
}
