import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/payment_methods.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';
import 'package:robosats/src/robot_identity.dart';

/// The status of an order on its coordinator, the `status` field, 0 to 18 (`api/models/order.py:35-54`, commit ff1998c).
enum CoordinatorOrderStatus {
  /// The maker has not locked its bond yet.
  waitingForMakerBond(0),

  /// In the book, waiting for a taker.
  public(1),

  /// Taken out of the book by its maker for a while.
  paused(2),

  /// Shown only to the robot that holds a live pre-take of a public order, which waits for its bond: the coordinator stores the order as [public] all along (`api/views.py:381-396`).
  waitingForTakerBond(3),

  /// Cancelled by one side alone: the coordinator answers error 1043 instead of the order.
  cancelled(4),

  /// Ran out of time: see [CoordinatorOrder.expiryReason].
  expired(5),

  /// Both bonds locked: the seller's escrow and the buyer's payout are both awaited.
  waitingForCollateralAndInvoice(6),

  /// The buyer's payout is in, the seller's escrow is awaited.
  waitingForCollateral(7),

  /// The seller's escrow is locked, the buyer's payout is awaited.
  waitingForInvoice(8),

  /// Everything is locked: the buyer sends the fiat, both talk in the chat.
  sendingFiat(9),

  /// The buyer said the fiat is sent.
  fiatSent(10),

  /// A dispute is open.
  inDispute(11),

  /// Cancelled by both sides: the coordinator answers error 1043 instead of the order.
  collaborativelyCancelled(12),

  /// The seller confirmed: the coordinator pays the buyer.
  sendingSats(13),

  /// The trade is over and the buyer paid.
  successful(14),

  /// The coordinator could not pay the buyer's invoice.
  routingFailed(15),

  /// Both dispute statements are in.
  waitingForDisputeResolution(16),

  /// The coordinator decided the dispute against the maker.
  makerLostDispute(17),

  /// The coordinator decided the dispute against the taker.
  takerLostDispute(18);

  /// The value of the `status` field.
  final int wire;

  const CoordinatorOrderStatus(this.wire);

  /// The status with this wire value, or `null` outside 0 to 18.
  static CoordinatorOrderStatus? fromWire(int value) =>
      value >= 0 && value < values.length ? values[value] : null;
}

/// Why an order expired, the `expiry_reason` field of an expired order (`api/models/order.py:56-61`).
enum OrderExpiryReason {
  /// Nobody took it while it was public.
  notTaken(0),

  /// Its maker did not lock the bond.
  makerBondNotLocked(1),

  /// The seller did not lock the escrow.
  escrowNotLocked(2),

  /// The buyer did not give a payout.
  invoiceNotSubmitted(3),

  /// Neither the escrow nor the payout came.
  neitherEscrowNorInvoice(4);

  final int wire;

  const OrderExpiryReason(this.wire);
}

/// Why the coordinator could not pay the buyer's invoice, read from the label it sends (`LNPayment.FailureReason`, `api/models/ln_payment.py:35-50`).
enum PayoutFailureReason {
  notFailedYet("Payment isn't failed (yet)"),
  timedOut(
    'There are more routes to try, but the payment timeout was exceeded.',
  ),
  noRoute(
    'All possible routes were tried and failed permanently. Or there were no routes to the destination at all.',
  ),
  nonRecoverable('A non-recoverable error has occurred.'),
  incorrectDetails(
    'Payment details are incorrect (unknown hash, invalid amount or invalid final CLTV delta).',
  ),
  coordinatorBalance("Insufficient unlocked balance in RoboSats' node."),

  /// A label this package does not know.
  unspecified(null);

  /// The label the coordinator sends: compared, never kept or shown.
  final String? _label;

  const PayoutFailureReason(this._label);

  static PayoutFailureReason _fromLabel(String label) {
    for (final reason in values) {
      if (reason._label == label) return reason;
    }
    return unspecified;
  }
}

/// Why the coordinator offers no on-chain payout to the buyer, read from the start of the reason it sends (`Logics.payout_amount`, `api/logics.py:671-718`).
enum SwapRefusal {
  /// The amount is under the coordinator's smallest swap.
  belowMinimum('Order amount is smaller than the minimum swap'),

  /// The amount is over the coordinator's largest swap.
  aboveMaximum('Order amount is bigger than the maximum swap'),

  /// The coordinator offers no swap at all.
  disabled('On-the-fly submarine swaps are disabled'),

  /// The coordinator has not enough on-chain funds for it.
  noLiquidity('Not enough onchain liquidity'),

  /// A reason this package does not know.
  unspecified(null);

  final String? _prefix;

  const SwapRefusal(this._prefix);

  static SwapRefusal _fromText(String text) {
    for (final refusal in values) {
      if (refusal._prefix case final prefix? when text.startsWith(prefix)) {
        return refusal;
      }
    }
    return unspecified;
  }
}

/// A hold invoice the coordinator asks this robot to pay, a bond or the escrow, as it sent it: nothing in it has been decoded or checked.
@immutable
final class HoldInvoice {
  /// The invoice text, at most [CoordinatorOrder.maxInvoiceLength] visible ASCII characters, kept opaque: decode and check it before showing or paying it.
  final String invoice;

  /// The amount the coordinator says the invoice is for.
  final Sats satoshis;

  const HoldInvoice._(this.invoice, this.satoshis);

  /// The amount only: an invoice is never printed.
  @override
  String toString() => 'HoldInvoice($satoshis sats)';
}

/// The on-chain payout of a successful order whose buyer chose one, as the coordinator describes it to that buyer (`api/views.py:511-526`).
@immutable
final class OnchainPayout {
  /// The sats taken from the trade for the payout, before the mining fee.
  final Sats numSatoshis;

  /// The sats sent to the buyer's address.
  final Sats sentSatoshis;

  /// The network the coordinator says it pays on.
  final RobosatsNetwork network;

  /// The transaction, 64 lowercase hexadecimal characters, once it is in the mempool.
  final String? txid;

  /// Whether the payment waits in the coordinator's queue.
  final bool queued;

  /// The buyer's address, given while the payment is queued.
  final String? address;

  const OnchainPayout._({
    required this.numSatoshis,
    required this.sentSatoshis,
    required this.network,
    required this.txid,
    required this.queued,
    required this.address,
  });

  /// Amounts only.
  @override
  String toString() => 'OnchainPayout($sentSatoshis sats, queued: $queued)';
}

/// What the coordinator says this robot's side of a finished trade was, and the contract's figures (`Logics.summarize_trade`, `api/logics.py:2047-2139`).
///
/// Read from this robot's own summary, `maker_summary` or `taker_summary`, and from `platform_summary`; the peer's summary is not read, nor the payment hash or preimage of the payout.
@immutable
final class TradeSummary {
  final bool isBuyer;

  /// The fiat the buyer sent or the seller received, in the order's currency.
  final double? fiatAmount;

  /// The sats the buyer received.
  final Sats? receivedSats;

  /// The sats the seller sent.
  final Sats? sentSats;

  /// The trade fee in sats, as the coordinator computes it.
  final int? tradeFeeSats;

  /// The trade fee as a fraction of the trade, 0.00175 for a taker with the default fees.
  final double? tradeFeeFraction;

  /// This robot's bond, in sats and in percent.
  final Sats? bondSats;
  final double? bondPercent;

  /// Whether the buyer was paid on chain, and its costs.
  final bool isSwap;
  final Sats? receivedOnchainSats;
  final Sats? miningFeeSats;
  final Sats? swapFeeSats;
  final double? swapFeePercent;

  /// The price of the contract, in the order's currency per bitcoin.
  final double? contractExchangeRate;

  /// When the contract's amount in sats was fixed, and how long the trade took from then.
  final DateTime? contractTimestamp;
  final Duration? contractTotalTime;

  /// The routing budget the buyer allowed for a Lightning payout, in sats with millisat decimals (a `DecimalField` of 3 places, `api/models/ln_payment.py:95`).
  final double? routingBudgetSats;

  const TradeSummary._({
    required this.isBuyer,
    required this.fiatAmount,
    required this.receivedSats,
    required this.sentSats,
    required this.tradeFeeSats,
    required this.tradeFeeFraction,
    required this.bondSats,
    required this.bondPercent,
    required this.isSwap,
    required this.receivedOnchainSats,
    required this.miningFeeSats,
    required this.swapFeeSats,
    required this.swapFeePercent,
    required this.contractExchangeRate,
    required this.contractTimestamp,
    required this.contractTotalTime,
    required this.routingBudgetSats,
  });

  @override
  String toString() => 'TradeSummary(buyer: $isBuyer)';
}

/// An order as its coordinator describes it to one robot, the answer of `GET /api/order/` (`OrderView.get`, `api/views.py:226-528`, commit ff1998c), to its maker, its taker, the robot that holds a pre-take of it, or any robot while it is public.
///
/// Every field is checked for its JSON type, as the view writes it for that robot, and its bounds, as `PublicOrder` checks the book.
/// The roles are checked against each other and against the robot that asked: maker and taker not both, `is_participant` agreeing with them, the maker's or taker's hash id this robot's exactly when the answer says this robot is the maker or the taker, buyer and seller each the one the order's type and the role give, `ur_nick` this robot's nickname, status 3 only for a pre-taker with its bond, a taker named past a pre-take, a robot that is no participant shown a public order without any participant's field, a bond invoice only at the step that asks for it and an escrow invoice only to a seller at the escrow step.
/// Nothing else is checked: the amounts and the invoices are what the coordinator says, for the caller to check against what it knows.
/// Fields that the coordinator sends only in some statuses or to some robots are `null` when absent; an absent field never rejects the answer, an invalid one always does, but for this robot's trade summary, which is display only and is dropped alone.
/// Free text of the maker goes through [displayText]; the coordinator's own labels are read as enums, never kept.
@immutable
final class CoordinatorOrder {
  /// The longest invoice kept: a BOLT11 hold invoice of a coordinator is about 400 characters.
  static const maxInvoiceLength = 2000;

  /// The coordinator that answered, and the network of its instance.
  final Coordinator coordinator;
  final RobosatsNetwork network;

  /// The hash id of the robot the answer was given to, which every role of the answer was checked against.
  final String _readBy;

  final int id;
  final CoordinatorOrderStatus status;
  final DateTime createdAt;

  /// When the current step ends: for [CoordinatorOrderStatus.waitingForTakerBond], when the pre-take ends.
  final DateTime expiresAt;

  /// How long the current step lasts in total (`total_secs_exp`).
  final Duration stepDuration;

  final OrderType type;
  final RobosatsCurrency currency;

  /// The amount the order offers: fixed, or a range.
  final OrderAmount amount;

  /// For a range order, the amount chosen by a take: the pre-take's for its pre-taker, the contract's once taken; `null` for a fixed order and for a range order nobody has taken.
  final FiatAmount? takenAmount;

  final PaymentMethods paymentMethods;

  /// The maker's description of its terms, cleaned by [displayText], or `null` when there is none or the coordinator hides it.
  final String? description;

  final bool isExplicit;
  final Premium? premium;

  /// The amount in sats the maker fixed, for an order priced in sats.
  final Sats? explicitSatoshis;
  final Duration escrowDuration;
  final BondSize bondSize;
  final OrderLocation? location;

  /// How long the order stays public, sent for an expired or finished order.
  final Duration? publicDuration;

  /// Whether a password protects the order.
  final bool hasPassword;

  /// What the coordinator says this robot is to the order.
  final bool isMaker;
  final bool isTaker;
  final bool isParticipant;

  /// Whether this robot buys or sells bitcoin, sent to participants only.
  final bool? isBuyer;
  final bool? isSeller;

  /// The maker, whose nickname is derived from its hash id.
  final RobotHashId maker;

  /// The taker, once the order is taken: a pre-taker is not one.
  final RobotHashId? taker;

  /// The Nostr public keys the coordinator holds for the maker and the taker, 64 lowercase hexadecimal characters, or `null` when it holds none (it sends `"None"`).
  final String? makerNostrPublicKeyHex;
  final String? takerNostrPublicKeyHex;

  final MakerActivity? makerActivity;
  final MakerActivity? takerActivity;

  /// When this robot may take or make orders again, when the coordinator has put it on hold.
  final DateTime? penaltyUntil;

  /// The price and premium at the current market price, sent while the order is public or before it is final.
  final double? priceNow;
  final Premium? premiumNow;

  /// The sats of the trade: for a non-participant of a public order at the current price; for a participant, the coordinator's `last_satoshis`, not the sats of a pre-take's amount.
  final Sats? satoshisNow;

  final bool? isFiatSent;
  final bool? isDisputed;

  /// Whether the maker's bond, the taker's bond and the escrow are locked, sent to participants.
  final bool? makerBondLocked;
  final bool? takerBondLocked;
  final bool? escrowLocked;

  /// What this robot sends (seller) or receives (buyer), once both bonds are locked.
  final Sats? tradeSatoshis;

  /// The bond this robot must lock: the maker's at [CoordinatorOrderStatus.waitingForMakerBond], the pre-taker's at [CoordinatorOrderStatus.waitingForTakerBond].
  final HoldInvoice? bondInvoice;

  /// The escrow the seller must lock.
  final HoldInvoice? escrowInvoice;

  /// The amount of the buyer's Lightning payout invoice.
  final Sats? payoutInvoiceAmount;

  /// Whether the buyer may be paid on chain, and if not why, with the coordinator's rates when it may.
  final bool? swapAllowed;
  final SwapRefusal? swapRefusal;
  final double? suggestedMiningFeeRate;
  final double? swapFeeRate;

  /// Whether the peer asked to cancel together, and whether this robot did.
  final bool? peerAskedToCancel;
  final bool? askedToCancel;

  /// The index of the last chat message.
  final int? chatLastIndex;

  /// Whether this robot's dispute statement is in.
  final bool? statementSubmitted;

  /// After a failed payout: attempts so far, the next one, why it failed, and whether the invoice expired.
  final int? payoutRetries;
  final DateTime? nextPayoutRetry;
  final PayoutFailureReason? payoutFailureReason;
  final bool? payoutInvoiceExpired;

  final OrderExpiryReason? expiryReason;

  /// This robot's summary of a trade that is paying, paid or failed to pay.
  final TradeSummary? summary;

  final OnchainPayout? onchainPayout;

  const CoordinatorOrder._(
    this._readBy, {
    required this.coordinator,
    required this.network,
    required this.id,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.stepDuration,
    required this.type,
    required this.currency,
    required this.amount,
    required this.takenAmount,
    required this.paymentMethods,
    required this.description,
    required this.isExplicit,
    required this.premium,
    required this.explicitSatoshis,
    required this.escrowDuration,
    required this.bondSize,
    required this.location,
    required this.publicDuration,
    required this.hasPassword,
    required this.isMaker,
    required this.isTaker,
    required this.isParticipant,
    required this.isBuyer,
    required this.isSeller,
    required this.maker,
    required this.taker,
    required this.makerNostrPublicKeyHex,
    required this.takerNostrPublicKeyHex,
    required this.makerActivity,
    required this.takerActivity,
    required this.penaltyUntil,
    required this.priceNow,
    required this.premiumNow,
    required this.satoshisNow,
    required this.isFiatSent,
    required this.isDisputed,
    required this.makerBondLocked,
    required this.takerBondLocked,
    required this.escrowLocked,
    required this.tradeSatoshis,
    required this.bondInvoice,
    required this.escrowInvoice,
    required this.payoutInvoiceAmount,
    required this.swapAllowed,
    required this.swapRefusal,
    required this.suggestedMiningFeeRate,
    required this.swapFeeRate,
    required this.peerAskedToCancel,
    required this.askedToCancel,
    required this.chatLastIndex,
    required this.statementSubmitted,
    required this.payoutRetries,
    required this.nextPayoutRetry,
    required this.payoutFailureReason,
    required this.payoutInvoiceExpired,
    required this.expiryReason,
    required this.summary,
    required this.onchainPayout,
  });

  /// Whether this answer was given to the robot [identity].
  @internal
  bool wasReadBy(RobotIdentity identity) => _readBy == identity.hashId.hex;

  static final RegExp _nostrKey = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _txid = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _address = RegExp(r'^[A-Za-z0-9]{1,100}$');
  static final RegExp _invoice = RegExp(r'^[\x21-\x7E]+$');
  static const _maxId = 1 << 53;
  static const _maxSats = CoordinatorReadBounds.maxSats;

  /// The longest step: `t_to_expire` gives at most 100 days (`api/models/order.py:310-339`), with margin.
  static const _maxStepSeconds = 400 * 24 * 3600;

  /// The bounds of `escrow_duration` in the order model, in seconds: 30 minutes to 10 hours.
  static const _minEscrowSeconds = 1800;
  static const _maxEscrowSeconds = 36000;

  /// The longest `public_duration`: 24 hours (`robosats/settings.py:298`), doubled for margin.
  static const _maxPublicSeconds = 48 * 3600;

  /// The fields the coordinator gives to the maker and the taker only (`api/views.py:312-526`): an answer that gives one of them to a robot that is no participant is refused.
  static const _participantFields = [
    'is_buyer',
    'is_seller',
    'taker_nick',
    'taker_hash_id',
    'taker_nostr_pubkey',
    'ur_nick',
    'is_fiat_sent',
    'is_disputed',
    'maker_locked',
    'taker_locked',
    'escrow_locked',
    'trade_satoshis',
    'bond_invoice',
    'bond_satoshis',
    'escrow_invoice',
    'escrow_satoshis',
    'invoice_amount',
    'swap_allowed',
    'swap_failure_reason',
    'suggested_mining_fee_rate',
    'swap_fee_rate',
    'pending_cancel',
    'asked_for_cancel',
    'chat_last_index',
    'statement_submitted',
    'retries',
    'next_retry_time',
    'failure_reason',
    'invoice_expired',
    'public_duration',
    'maker_summary',
    'taker_summary',
    'platform_summary',
    'expiry_reason',
    'num_satoshis',
    'sent_satoshis',
    'txid',
    'tx_queued',
    'address',
  ];

  /// Reads the decoded body of a `200` answer about the order [orderId] that [coordinator] gave on [network] to the robot [identity].
  ///
  /// Any invalid field rejects the whole answer with [CoordinatorResponseMalformed], as does an answer about another order, but for this robot's trade summary, which is dropped alone.
  /// So does an answer whose roles contradict each other or the robot that asked: see the checks below, each with the view's lines it follows.
  @internal
  static Result<CoordinatorOrder, CoordinatorFailure> parse(
    Object? body,
    Coordinator coordinator,
    RobosatsNetwork network, {
    required int orderId,
    required RobotIdentity identity,
  }) {
    if (body is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('order'));
    }
    final fields = JsonFields(body);
    final id = fields.requiredInt('id', min: 1, max: _maxId);
    final statusWire = fields.requiredInt('status', min: 0, max: 18);
    final createdAt = fields.requiredDate('created_at');
    final expiresAt = fields.requiredDate('expires_at');
    final stepSeconds = fields.requiredInt(
      'total_secs_exp',
      min: 0,
      max: _maxStepSeconds,
    );
    final typeWire = fields.requiredInt('type', min: 0, max: 1);
    final currencyId = fields.requiredInt('currency', min: 1, max: 65535);
    final hasRange = fields.requiredBool('has_range');
    final fixed = fields.optionalDecimal('amount', min: 0, max: 1e10);
    final rangeMin = fields.optionalDecimal('min_amount', min: 0, max: 1e10);
    final rangeMax = fields.optionalDecimal('max_amount', min: 0, max: 1e10);
    // At most 70 code points, the `max_length` of the order model (`api/models/order.py:85`).
    final paymentMethod = fields.requiredText(
      'payment_method',
      maxCodePoints: 70,
    );
    // At most 240 code points (`api/models/order.py:178-183`).
    final description = fields.optionalText('description', maxCodePoints: 240);
    final isExplicit = fields.requiredBool('is_explicit');
    final premium = fields.optionalDecimal(
      'premium',
      min: Premium.minPercent,
      max: double.maxFinite,
    );
    final satoshis = fields.optionalInt('satoshis', min: 1, max: _maxSats);
    final escrowSeconds = fields.requiredInt(
      'escrow_duration',
      min: _minEscrowSeconds,
      max: _maxEscrowSeconds,
    );
    final bond = fields.requiredDecimal(
      'bond_size',
      min: BondSize.minPercent,
      max: BondSize.maxPercent,
    );
    // The serializer's string for a robot that is no participant, the raw `Decimal` as a JSON number for a participant (`api/views.py:320-321`).
    final latitude = fields.optionalDecimalOrNumber(
      'latitude',
      min: -90,
      max: 90,
    );
    final longitude = fields.optionalDecimalOrNumber(
      'longitude',
      min: -180,
      max: 180,
    );
    final publicSeconds = fields.optionalInt(
      'public_duration',
      min: 0,
      max: _maxPublicSeconds,
    );
    final hasPassword = fields.requiredBool('has_password');
    final isMaker = fields.requiredBool('is_maker');
    final isTaker = fields.requiredBool('is_taker');
    final isParticipant = fields.requiredBool('is_participant');
    final isBuyer = fields.optionalBool('is_buyer');
    final isSeller = fields.optionalBool('is_seller');
    final makerHashId = fields.requiredString('maker_hash_id', maxLength: 64);
    final makerNick = fields.optionalString('maker_nick', maxLength: 64);
    final takerHashId = fields.optionalString('taker_hash_id', maxLength: 64);
    final takerNick = fields.optionalString('taker_nick', maxLength: 64);
    final ownNick = fields.optionalString('ur_nick', maxLength: 64);
    final makerNostrKey = _nostrKeyOf(fields, 'maker_nostr_pubkey');
    final takerNostrKey = _nostrKeyOf(fields, 'taker_nostr_pubkey');
    // Any label is read, so that an unknown one becomes `null` rather than rejecting the order.
    final makerStatus = fields.optionalString(
      'maker_status',
      maxLength: CoordinatorReadBounds.orderBytes,
    );
    final takerStatus = fields.optionalString(
      'taker_status',
      maxLength: CoordinatorReadBounds.orderBytes,
    );
    final penalty = fields.optionalDate('penalty');
    final priceNow = fields.optionalDouble(
      'price_now',
      min: 0,
      max: double.maxFinite,
    );
    final premiumNow = fields.optionalDouble(
      'premium_now',
      min: Premium.minPercent,
      max: double.maxFinite,
    );
    final satoshisNow = fields.optionalInt(
      'satoshis_now',
      min: 0,
      max: _maxSats,
    );
    final isFiatSent = fields.optionalBool('is_fiat_sent');
    final isDisputed = fields.optionalBool('is_disputed');
    final makerLocked = fields.optionalBool('maker_locked');
    final takerLocked = fields.optionalBool('taker_locked');
    final escrowLocked = fields.optionalBool('escrow_locked');
    final tradeSatoshis = fields.optionalInt(
      'trade_satoshis',
      min: 0,
      max: _maxSats,
    );
    final bondInvoice = _holdInvoiceOf(fields, 'bond_invoice', 'bond_satoshis');
    final escrowInvoice = _holdInvoiceOf(
      fields,
      'escrow_invoice',
      'escrow_satoshis',
    );
    final invoiceAmount = fields.optionalInt(
      'invoice_amount',
      min: 0,
      max: _maxSats,
    );
    final swapAllowed = fields.optionalBool('swap_allowed');
    final swapFailureReason = fields.optionalString(
      'swap_failure_reason',
      maxLength: 500,
    );
    final suggestedMiningFeeRate = fields.optionalDouble(
      'suggested_mining_fee_rate',
      min: 0,
      max: 1e6,
    );
    final swapFeeRate = fields.optionalDouble(
      'swap_fee_rate',
      min: 0,
      max: 100,
    );
    final pendingCancel = fields.optionalBool('pending_cancel');
    final askedForCancel = fields.optionalBool('asked_for_cancel');
    final chatLastIndex = fields.optionalInt(
      'chat_last_index',
      min: 0,
      max: _maxId,
    );
    final statementSubmitted = fields.optionalBool('statement_submitted');
    final retries = fields.optionalInt('retries', min: 0, max: 32767);
    final nextRetryTime = fields.optionalDate('next_retry_time');
    final failureReason = fields.optionalString(
      'failure_reason',
      maxLength: 500,
    );
    final invoiceExpired = fields.optionalBool('invoice_expired');
    final expiryReasonWire = fields.optionalInt(
      'expiry_reason',
      min: 0,
      max: OrderExpiryReason.values.length - 1,
    );
    final summary = _summaryOf(fields, isMaker: isMaker, isTaker: isTaker);
    final onchainPayout = _onchainPayoutOf(fields);
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    if (id != orderId) return const Err(CoordinatorResponseMalformed('id'));

    // Each check below names the field it rejects, as [JsonFields] does.
    CoordinatorFailure reject(String field) =>
        CoordinatorResponseMalformed(field);

    final status = CoordinatorOrderStatus.fromWire(statusWire);
    if (status == null) return Err(reject('status'));
    if (createdAt == null) return Err(reject('created_at'));
    if (expiresAt == null) return Err(reject('expires_at'));
    final type = OrderType.fromWire(typeWire);
    if (type == null) return Err(reject('type'));
    final currency = RobosatsCurrency.fromId(currencyId);
    if (currency == null) return Err(reject('currency'));

    final OrderAmount amount;
    FiatAmount? takenAmount;
    if (hasRange) {
      final min = rangeMin == null ? null : FiatAmount.tryCreate(rangeMin);
      final max = rangeMax == null ? null : FiatAmount.tryCreate(rangeMax);
      if (min == null) return Err(reject('min_amount'));
      if (max == null) return Err(reject('max_amount'));
      final range = RangeOrderAmount.tryCreate(min, max);
      if (range == null) return Err(reject('max_amount'));
      amount = range;
      if (fixed != null) {
        takenAmount = FiatAmount.tryCreate(fixed);
        if (takenAmount == null) return Err(reject('amount'));
      }
    } else {
      final value = fixed == null ? null : FiatAmount.tryCreate(fixed);
      if (value == null) return Err(reject('amount'));
      amount = FixedOrderAmount(value);
    }

    if (isExplicit && satoshis == null) return Err(reject('satoshis'));
    final Premium? premiumValue;
    if (premium == null) {
      premiumValue = null;
    } else {
      premiumValue = Premium.tryCreate(premium);
      if (premiumValue == null ||
          (!isExplicit && premium > Premium.maxMarketPercent)) {
        return Err(reject('premium'));
      }
    }
    final bondValue = BondSize.tryCreate(bond);
    if (bondValue == null) return Err(reject('bond_size'));

    final OrderLocation? location;
    switch ((latitude, longitude)) {
      case (null, null):
        location = null;
      case (final double lat, final double lon):
        location = OrderLocation.tryCreate(lat, lon);
        if (location == null) return Err(reject('latitude'));
      default:
        return Err(reject(latitude == null ? 'latitude' : 'longitude'));
    }

    final maker = RobotHashId.parse(makerHashId);
    if (maker is! Ok<RobotHashId, RobosatsFailure>) {
      return Err(reject('maker_hash_id'));
    }
    if (makerNick != null && makerNick != maker.value.nickname) {
      return Err(reject('maker_nick'));
    }
    RobotHashId? taker;
    if (takerHashId != null) {
      final parsed = RobotHashId.parse(takerHashId);
      if (parsed is! Ok<RobotHashId, RobosatsFailure>) {
        return Err(reject('taker_hash_id'));
      }
      taker = parsed.value;
      if (takerNick != null && takerNick != parsed.value.nickname) {
        return Err(reject('taker_nick'));
      }
    } else if (takerNick != null && takerNick != 'None') {
      // With no taker the coordinator sends `str(None)` (`api/views.py:314`).
      return Err(reject('taker_nick'));
    }

    // The roles must agree with each other and with the robot that asked (`api/views.py:253-255`, `:270-275`, `:312-323`, `:381-396`).
    final ownHash = identity.hashId.hex;
    if (isMaker && isTaker) return Err(reject('is_taker'));
    if (isParticipant != (isMaker || isTaker)) {
      return Err(reject('is_participant'));
    }
    if (isMaker != (maker.value.hex == ownHash)) {
      return Err(reject('maker_hash_id'));
    }
    if (taker != null && isTaker != (taker.hex == ownHash)) {
      return Err(reject('taker_hash_id'));
    }
    if (status == CoordinatorOrderStatus.waitingForTakerBond) {
      // Only the robot that holds a live pre-take is shown status 3, with its bond, and it is not the taker yet.
      if (!isTaker || taker != null) return Err(reject('status'));
      if (bondInvoice == null) return Err(reject('bond_invoice'));
    } else if (isTaker && taker == null) {
      // Past a pre-take, a robot is the taker only as `order.taker`, which the answer names.
      return Err(reject('taker_hash_id'));
    }
    if (!isParticipant) {
      // A robot that is no participant sees a public order only, and none of the participants' fields.
      if (status != CoordinatorOrderStatus.public) return Err(reject('status'));
      for (final key in _participantFields) {
        if (fields.has(key)) return Err(reject(key));
      }
    } else {
      if (status.wire >= 6 && taker == null) {
        return Err(reject('taker_hash_id'));
      }
      // The maker of a buy order and the taker of a sell order buy (`Logics.is_buyer`).
      final buys = isMaker == (type == OrderType.buy);
      if (isBuyer != buys) return Err(reject('is_buyer'));
      if (isSeller != !buys) return Err(reject('is_seller'));
      if (ownNick != identity.nickname) return Err(reject('ur_nick'));
      if (bondInvoice != null &&
          !(isMaker && status == CoordinatorOrderStatus.waitingForMakerBond) &&
          !(isTaker && status == CoordinatorOrderStatus.waitingForTakerBond)) {
        return Err(reject('bond_invoice'));
      }
      if (escrowInvoice != null &&
          !(!buys &&
              (status ==
                      CoordinatorOrderStatus.waitingForCollateralAndInvoice ||
                  status == CoordinatorOrderStatus.waitingForCollateral))) {
        return Err(reject('escrow_invoice'));
      }
      if (invoiceAmount != null && !buys) return Err(reject('invoice_amount'));
    }

    final premiumNowValue = premiumNow == null
        ? null
        : Premium.tryCreate(premiumNow);
    if (premiumNow != null && premiumNowValue == null) {
      return Err(reject('premium_now'));
    }

    return Ok(
      CoordinatorOrder._(
        ownHash,
        coordinator: coordinator,
        network: network,
        id: id,
        status: status,
        createdAt: createdAt,
        expiresAt: expiresAt,
        stepDuration: Duration(seconds: stepSeconds),
        type: type,
        currency: currency,
        amount: amount,
        takenAmount: takenAmount,
        paymentMethods: PaymentMethods.parse(paymentMethod),
        description: description,
        isExplicit: isExplicit,
        premium: premiumValue,
        explicitSatoshis: isExplicit && satoshis != null
            ? Sats.fromInt(satoshis)
            : null,
        escrowDuration: Duration(seconds: escrowSeconds),
        bondSize: bondValue,
        location: location,
        publicDuration: publicSeconds == null
            ? null
            : Duration(seconds: publicSeconds),
        hasPassword: hasPassword,
        isMaker: isMaker,
        isTaker: isTaker,
        isParticipant: isParticipant,
        isBuyer: isBuyer,
        isSeller: isSeller,
        maker: maker.value,
        taker: taker,
        makerNostrPublicKeyHex: makerNostrKey,
        takerNostrPublicKeyHex: takerNostrKey,
        makerActivity: makerStatus == null
            ? null
            : MakerActivity.fromWire(makerStatus),
        takerActivity: takerStatus == null
            ? null
            : MakerActivity.fromWire(takerStatus),
        penaltyUntil: penalty,
        priceNow: priceNow,
        premiumNow: premiumNowValue,
        satoshisNow: _sats(satoshisNow),
        isFiatSent: isFiatSent,
        isDisputed: isDisputed,
        makerBondLocked: makerLocked,
        takerBondLocked: takerLocked,
        escrowLocked: escrowLocked,
        tradeSatoshis: _sats(tradeSatoshis),
        bondInvoice: bondInvoice,
        escrowInvoice: escrowInvoice,
        payoutInvoiceAmount: _sats(invoiceAmount),
        swapAllowed: swapAllowed,
        swapRefusal: swapFailureReason == null
            ? null
            : SwapRefusal._fromText(swapFailureReason),
        suggestedMiningFeeRate: suggestedMiningFeeRate,
        swapFeeRate: swapFeeRate,
        peerAskedToCancel: pendingCancel,
        askedToCancel: askedForCancel,
        chatLastIndex: chatLastIndex,
        statementSubmitted: statementSubmitted,
        payoutRetries: retries,
        nextPayoutRetry: nextRetryTime,
        payoutFailureReason: failureReason == null
            ? null
            : PayoutFailureReason._fromLabel(failureReason),
        payoutInvoiceExpired: invoiceExpired,
        expiryReason: expiryReasonWire == null
            ? null
            : OrderExpiryReason.values[expiryReasonWire],
        summary: summary,
        onchainPayout: onchainPayout,
      ),
    );
  }

  static Sats? _sats(int? value) => value == null ? null : Sats.fromInt(value);

  /// A Nostr public key field: `null` when absent, empty or `"None"`, as the coordinator writes a missing key (`str(None)`, `api/views.py:279,317`).
  static String? _nostrKeyOf(JsonFields fields, String key) {
    final text = fields.optionalString(key, maxLength: 64);
    if (text == null || text.isEmpty || text == 'None') return null;
    if (_nostrKey.hasMatch(text)) return text;
    fields.rejected ??= key;
    return null;
  }

  /// A hold invoice and its amount, which come together or not at all.
  static HoldInvoice? _holdInvoiceOf(
    JsonFields fields,
    String invoiceKey,
    String satoshisKey,
  ) {
    final invoice = fields.optionalString(
      invoiceKey,
      maxLength: maxInvoiceLength,
    );
    final satoshis = fields.optionalInt(satoshisKey, min: 0, max: _maxSats);
    if (invoice == null && satoshis == null) return null;
    if (invoice == null || !_invoice.hasMatch(invoice)) {
      fields.rejected ??= invoiceKey;
      return null;
    }
    if (satoshis == null) {
      fields.rejected ??= satoshisKey;
      return null;
    }
    return HoldInvoice._(invoice, Sats.fromInt(satoshis));
  }

  /// The on-chain payout of a successful buyer, present when `sent_satoshis` is.
  static OnchainPayout? _onchainPayoutOf(JsonFields fields) {
    final numSatoshis = fields.optionalInt(
      'num_satoshis',
      min: 0,
      max: _maxSats,
    );
    final sentSatoshis = fields.optionalInt(
      'sent_satoshis',
      min: 0,
      max: _maxSats,
    );
    final network = fields.optionalString('network', maxLength: 16);
    final txid = fields.optionalString('txid', maxLength: 64);
    final queued = fields.optionalBool('tx_queued');
    final address = fields.optionalString('address', maxLength: 100);
    if (txid != null && !_txid.hasMatch(txid)) fields.rejected ??= 'txid';
    if (address != null && !_address.hasMatch(address)) {
      fields.rejected ??= 'address';
    }
    if (sentSatoshis == null) {
      if (numSatoshis != null) fields.rejected ??= 'sent_satoshis';
      return null;
    }
    if (numSatoshis == null) {
      fields.rejected ??= 'num_satoshis';
      return null;
    }
    final payoutNetwork = network == null
        ? null
        : RobosatsNetwork.fromWire(network);
    if (payoutNetwork == null) {
      fields.rejected ??= 'network';
      return null;
    }
    return OnchainPayout._(
      numSatoshis: Sats.fromInt(numSatoshis),
      sentSatoshis: Sats.fromInt(sentSatoshis),
      network: payoutNetwork,
      txid: txid,
      queued: queued ?? false,
      address: address,
    );
  }

  /// This robot's own summary and the contract's figures, or `null` when the coordinator sent no valid summary for this robot's side.
  static TradeSummary? _summaryOf(
    JsonFields fields, {
    required bool isMaker,
    required bool isTaker,
  }) {
    final side = isTaker
        ? 'taker_summary'
        : isMaker
        ? 'maker_summary'
        : null;
    if (side == null) return null;
    final ownObject = fields.objectOrNull(side);
    final platformObject =
        fields.objectOrNull('platform_summary') ?? const <String, Object?>{};
    if (ownObject == null) return null;
    final own = JsonFields(ownObject);
    final isBuyer = own.requiredBool('is_buyer');
    final sentFiat = own.optionalDouble('sent_fiat', min: 0, max: 1e10);
    final receivedFiat = own.optionalDouble('received_fiat', min: 0, max: 1e10);
    final receivedSats = own.optionalInt(
      'received_sats',
      min: 0,
      max: _maxSats,
    );
    final sentSats = own.optionalInt('sent_sats', min: 0, max: _maxSats);
    final tradeFeeSats = own.optionalInt(
      'trade_fee_sats',
      min: -_maxSats,
      max: _maxSats,
    );
    final tradeFeeFraction = own.optionalDouble(
      'trade_fee_percent',
      min: 0,
      max: 1,
    );
    final bondSats = own.optionalInt('bond_size_sats', min: 0, max: _maxSats);
    final bondPercent = own.optionalDouble(
      'bond_size_percent',
      min: 0,
      max: 100,
    );
    final isSwap = own.optionalBool('is_swap');
    final receivedOnchainSats = own.optionalInt(
      'received_onchain_sats',
      min: 0,
      max: _maxSats,
    );
    final miningFeeSats = own.optionalInt(
      'mining_fee_sats',
      min: 0,
      max: _maxSats,
    );
    final swapFeeSats = own.optionalInt('swap_fee_sats', min: 0, max: _maxSats);
    final swapFeePercent = own.optionalDouble(
      'swap_fee_percent',
      min: 0,
      max: 100,
    );
    final platform = JsonFields(platformObject);
    final exchangeRate = platform.optionalDouble(
      'contract_exchange_rate',
      min: 0,
      max: double.maxFinite,
    );
    final contractTimestamp = platform.optionalDate('contract_timestamp');
    final totalTime = platform.optionalDouble(
      'contract_total_time',
      min: 0,
      max: _maxStepSeconds.toDouble(),
    );
    // A raw `Decimal` of the payout, written as a JSON number such as `0.0` or `164.126` (`api/logics.py:2128`).
    final routingBudget = platform.optionalDouble(
      'routing_budget_sats',
      min: 0,
      max: _maxSats.toDouble(),
    );
    // The summary is for display only, and comes with what a buyer must act on (a failed payout's retries, an expired invoice): an invalid one is dropped, never the order with it.
    if (own.rejected != null || platform.rejected != null) return null;
    return TradeSummary._(
      isBuyer: isBuyer,
      fiatAmount: isBuyer ? sentFiat : receivedFiat,
      receivedSats: _sats(receivedSats),
      sentSats: _sats(sentSats),
      tradeFeeSats: tradeFeeSats,
      tradeFeeFraction: tradeFeeFraction,
      bondSats: _sats(bondSats),
      bondPercent: bondPercent,
      isSwap: isSwap ?? false,
      receivedOnchainSats: _sats(receivedOnchainSats),
      miningFeeSats: _sats(miningFeeSats),
      swapFeeSats: _sats(swapFeeSats),
      swapFeePercent: swapFeePercent,
      contractExchangeRate: exchangeRate,
      contractTimestamp: contractTimestamp,
      contractTotalTime: totalTime == null
          ? null
          : Duration(microseconds: (totalTime * 1e6).round()),
      routingBudgetSats: routingBudget,
    );
  }

  /// Public facts only: no invoice, no key, no text of the maker.
  @override
  String toString() =>
      'CoordinatorOrder(${coordinator.shortAlias}#$id, ${status.name}, maker: $isMaker, taker: $isTaker)';
}

/// What a coordinator answered to a take, once read and checked: the take started, this robot already had the order, or the take did not happen.
///
/// The reference coordinator answers a take on an order that is no longer public with the order as it is, `200` and no error (`api/views.py:595-596`, the error is built and not returned): so a `200` alone never says the take happened.
sealed class TakeOrderOutcome {
  /// The order as the coordinator described it in its answer.
  CoordinatorOrder get order;

  const TakeOrderOutcome();
}

/// This robot now holds the pre-take: the order at [CoordinatorOrderStatus.waitingForTakerBond], this robot its taker and not its maker, and [CoordinatorOrder.bondInvoice] the bond to lock before [CoordinatorOrder.expiresAt].
final class OrderTakeStarted extends TakeOrderOutcome {
  @override
  final CoordinatorOrder order;

  /// The bond to lock, which an order at this step always carries.
  final HoldInvoice bondInvoice;

  const OrderTakeStarted._(this.order, this.bondInvoice);

  @override
  String toString() => 'OrderTakeStarted($order)';
}

/// This take did not happen, but the order was already this robot's from an earlier take: its bond is locked and the trade goes on at [CoordinatorOrder.status].
///
/// Do not drop the trade: a step left undone lets it time out, and a taker who lets its step time out loses its bond (`api/logics.py:404-458`).
final class OrderAlreadyTakenByThisRobot extends TakeOrderOutcome {
  @override
  final CoordinatorOrder order;

  const OrderAlreadyTakenByThisRobot._(this.order);

  @override
  String toString() => 'OrderAlreadyTakenByThisRobot($order)';
}

/// This take did not happen and the order is not this robot's: taken by another robot, paused, expired, or this robot's own order as maker.
final class OrderNotTaken extends TakeOrderOutcome {
  @override
  final CoordinatorOrder order;

  const OrderNotTaken._(this.order);

  @override
  String toString() => 'OrderNotTaken($order)';
}

/// What a coordinator answered to a cancel that it accepted.
sealed class CancelOrderOutcome {
  const CancelOrderOutcome();
}

/// The cancel ended the order: [status] is [CoordinatorOrderStatus.cancelled] or [CoordinatorOrderStatus.collaborativelyCancelled].
///
/// The reference coordinator then answers `200` with a short body that holds a `bad_request` text (`api/views.py:604-615`), which is read as this outcome and never as a refusal; its text is not kept.
final class OrderCancelEnded extends CancelOrderOutcome {
  final int orderId;
  final CoordinatorOrderStatus status;

  const OrderCancelEnded._(this.orderId, this.status);

  @override
  String toString() => 'OrderCancelEnded(#$orderId, ${status.name})';
}

/// The cancel was accepted and the order goes on: [order] is how the coordinator now describes it to this robot.
///
/// After a pre-taker's cancel the order is public again and this robot no longer its taker; after a taker's cancel with its bond locked the order is public again too, and the bond is lost (`api/logics.py:1108-1130`); in the chat, a first cancel only asks the peer ([CoordinatorOrder.askedToCancel]).
final class OrderCancelAccepted extends CancelOrderOutcome {
  final CoordinatorOrder order;

  const OrderCancelAccepted._(this.order);

  @override
  String toString() => 'OrderCancelAccepted($order)';
}

/// The status a cancel sends as `cancel_status` after the read [lastRead]: the status the coordinator stores, which is [CoordinatorOrderStatus.public] for a pre-take shown as [CoordinatorOrderStatus.waitingForTakerBond] (`api/views.py:381-396`).
@internal
CoordinatorOrderStatus storedStatusOf(CoordinatorOrder lastRead) =>
    lastRead.status == CoordinatorOrderStatus.waitingForTakerBond
    ? CoordinatorOrderStatus.public
    : lastRead.status;

/// Reads the decoded body of a `200` answer to a take of the order [orderId] by the robot [identity].
@internal
Result<TakeOrderOutcome, CoordinatorFailure> parseTakeAnswer(
  Object? body,
  Coordinator coordinator,
  RobosatsNetwork network, {
  required int orderId,
  required RobotIdentity identity,
}) => switch (CoordinatorOrder.parse(
  body,
  coordinator,
  network,
  orderId: orderId,
  identity: identity,
)) {
  Err(:final failure) => Err(failure),
  Ok(value: final order)
      when order.status == CoordinatorOrderStatus.waitingForTakerBond &&
          order.isTaker &&
          !order.isMaker =>
    switch (order.bondInvoice) {
      final bond? => Ok(OrderTakeStarted._(order, bond)),
      null => const Err(CoordinatorResponseMalformed('bond_invoice')),
    },
  Ok(value: final order) when order.isTaker => Ok(
    OrderAlreadyTakenByThisRobot._(order),
  ),
  Ok(value: final order) => Ok(OrderNotTaken._(order)),
};

/// Reads the decoded body of a `200` answer to a cancel of the order [orderId] by the robot [identity]: the short body of an order that the cancel ended, told by its `bad_request` key, or the order.
@internal
Result<CancelOrderOutcome, CoordinatorFailure> parseCancelAnswer(
  Object? body,
  Coordinator coordinator,
  RobosatsNetwork network, {
  required int orderId,
  required RobotIdentity identity,
}) {
  if (body case final Map<String, Object?> object
      when object.containsKey('bad_request')) {
    final fields = JsonFields(object);
    final id = fields.requiredInt('id', min: 1, max: CoordinatorOrder._maxId);
    final statusWire = fields.requiredInt('status', min: 0, max: 18);
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    if (id != orderId) return const Err(CoordinatorResponseMalformed('id'));
    return switch (CoordinatorOrderStatus.fromWire(statusWire)) {
      final status?
          when status == CoordinatorOrderStatus.cancelled ||
              status == CoordinatorOrderStatus.collaborativelyCancelled =>
        Ok(OrderCancelEnded._(id, status)),
      _ => const Err(CoordinatorResponseMalformed('status')),
    };
  }
  return CoordinatorOrder.parse(
    body,
    coordinator,
    network,
    orderId: orderId,
    identity: identity,
  ).map(OrderCancelAccepted._);
}
