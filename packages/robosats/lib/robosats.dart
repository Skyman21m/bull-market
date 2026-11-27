/// Pure-Dart RoboSats client primitives: the identity of a robot, its OpenPGP key, and the client of the coordinators.
///
/// A [GarageKey] derives one [RobotToken] per robot index, and a [RobotIdentity] holds everything RoboSats derives from a token: the token hash sent to coordinators, the [RobotHashId] with its nickname, the Nostr key and the `Authorization` header values.
/// A [RobotPgpKey] is the OpenPGP key pair of a robot, locked by its token: once unlocked it clear-signs invoices and payout addresses and encrypts, signs, decrypts and verifies chat messages, in the formats of the official client and of the coordinators.
/// A [CoordinatorClient] reads what a coordinator of the embedded [Federation] publishes (`/api/info/`, `/api/book/`, `/api/limits/`) through a [CoordinatorTransport] that the app implements over Tor, and a [FederationBookReader] merges the books of every coordinator.
/// The same client makes a robot known to a coordinator and reads it back (`/api/robot/`), checked against what this device computed: a [CoordinatorRobot] when the coordinator returns the key pair this device has just sent, and otherwise an [UnprovenCoordinatorRobot], which gives the robot only once the robot's token has proved the pair it returned.
/// For the robot of this device, the client also reads an order as the coordinator describes it to that robot (`/api/order/`, a [CoordinatorOrder]), sends a taker's take and cancel of it, and the buyer's payout: a Lightning invoice or an on-chain address, clear-signed by the robot's key ([SignedPayout]), the address first checked by [BitcoinAddress.check].
/// It also sends the actions of the trade's chat step, each answered with a [TradeActionOutcome]: the buyer's « fiat sent » and its undo, a dispute, and the robot's rating of its coordinator ([PlatformRating]).
/// As a maker, the client makes an order from a checked [MakeOrderRequest], answered with a [MadeOrder], the coordinator's word on the order's number and on the terms its answer carries, which proves neither the terms it leaves out nor the maker, and pauses or resumes it ([CoordinatorClient.pauseOrder], a toggle); the app calls each from its own use case (#179, #184).
/// Invalid input is reported as a [RobosatsFailure] in a `Result`, never thrown.
/// No Flutter, no networking of its own, no logging.
///
/// The client also reads the encrypted chat of a trade as a [ChatPage] and posts to it an [OutgoingChatMessage], which only the robot's unlocked key makes ([UnlockedRobotPgpKey.encryptChatMessageToPost]).
/// As the official client, a message is also sent over Nostr: an [OutgoingNostrChatMessage] holds its two NIP-59 gift wraps (NIP-44 v2, BIP-340 signatures through the `bip340` package), which the app publishes to the coordinators' relays.
/// At the end of a trade, the client asks the coordinator for a [HostReviewToken] (`/api/review/`), with which an [OutgoingHostRating] rates the coordinator over Nostr, as « Rate your host » of the official client.
/// The [GarageRecoveryNote] of a Garage Key, the index of its last robot that the official client keeps on Nostr, is written as an [OutgoingGarageRecoveryNote] and read back, one relay at a time, from the events relays answer to its [GarageRecoveryFilter]s as a [GarageRecoveryReading]; the app publishes and reads it through an [OwnSessionNostrRelayTransport], each call on a Tor session of its own, on every relay [nostrRelaysOfNetwork] gives; nothing here connects to a relay.
library;

export 'src/bitcoin_address.dart' show BitcoinAddress, BitcoinAddressKind;
export 'src/coordinator/action_signature.dart'
    show
        actionSignatureWindow,
        orderActionContent,
        reviewActionContent,
        timedActionContent,
        unixSeconds;
export 'src/coordinator/coordinator.dart'
    show Coordinator, CoordinatorBadges, CoordinatorContact, CoordinatorOrigins;
export 'src/coordinator/coordinator_client.dart' show CoordinatorClient;
export 'src/coordinator/coordinator_info.dart'
    show CoordinatorInfo, CoordinatorVersion, NoticeSeverity;
export 'src/coordinator/coordinator_order.dart'
    show
        CancelOrderOutcome,
        CoordinatorOrder,
        CoordinatorOrderStatus,
        HoldInvoice,
        OnchainPayout,
        PayoutAccepted,
        PayoutOutcome,
        OrderAlreadyTakenByThisRobot,
        OrderCancelAccepted,
        OrderCancelEnded,
        OrderExpiryReason,
        OrderNotTaken,
        OrderTakeStarted,
        PayoutFailureReason,
        SwapRefusal,
        TakeOrderOutcome,
        TradeSideSummary,
        TradeSummary;
export 'src/coordinator/coordinator_robot.dart'
    show CoordinatorRobot, CoordinatorRobotAnswer, UnprovenCoordinatorRobot;
export 'src/coordinator/coordinator_transport.dart'
    show
        CoordinatorHttpMethod,
        CoordinatorRequest,
        CoordinatorResponse,
        CoordinatorTransport;
export 'src/coordinator/dropped_order_reason.dart' show DroppedOrderReason;
export 'src/coordinator/currency_limits.dart'
    show CurrencyLimit, CurrencyLimits;
export 'src/coordinator/federation.dart' show Federation;
export 'src/coordinator/federation_book.dart'
    show CoordinatorBookOutcome, FederationBook, FederationBookReader;
export 'src/coordinator/json_fields.dart' show displayText;
export 'src/coordinator/make_order.dart'
    show MadeOrder, MakeOrderRequest, OrderPasswordHash;
export 'src/coordinator/visible_text.dart'
    show isShownAsWritten, maxCombiningMarks;
export 'src/coordinator/order_book.dart' show OrderBook;
export 'src/coordinator/order_values.dart'
    show
        BondSize,
        FiatAmount,
        FixedOrderAmount,
        MakerActivity,
        OrderAmount,
        OrderLocation,
        OrderType,
        Premium,
        RangeOrderAmount;
export 'src/coordinator/payment_methods.dart'
    show PaymentMethodInfo, PaymentMethods;
export 'src/coordinator/payout.dart'
    show
        MiningFeeRate,
        RoutingBudgetPpm,
        SignedPayout,
        SignedPayoutAddress,
        SignedPayoutInvoice;
export 'src/coordinator/public_order.dart' show PublicOrder;
export 'src/coordinator/read_bounds.dart' show CoordinatorReadBounds;
export 'src/coordinator/host_rating.dart'
    show HostRating, HostReviewToken, OutgoingHostRating;
export 'src/coordinator/nostr_chat.dart' show OutgoingNostrChatMessage;
export 'src/coordinator/nostr_relay.dart'
    show
        NostrRelayAccepted,
        NostrRelayBusy,
        NostrRelayFailed,
        NostrRelayFilter,
        NostrRelayOk,
        NostrRelayOutcome,
        NostrRelayPublication,
        NostrRelayRead,
        NostrRelayRefused,
        NostrRelayTimedOut,
        NostrRelayTransport,
        NostrRelayUnreachable,
        OwnSessionNostrRelayTransport,
        nostrRelaysFor,
        nostrRelaysOfNetwork;
export 'src/coordinator/robosats_currency.dart' show RobosatsCurrency;
export 'src/coordinator/robosats_network.dart' show RobosatsNetwork;
export 'src/coordinator/robot_session_key.dart' show RobotSessionKey;
export 'src/coordinator/trade_action.dart'
    show PlatformRating, TradeActionAccepted, TradeActionOutcome;

export 'src/garage_key.dart' show GarageKey, GarageRobot;
export 'src/garage_recovery_note.dart'
    show
        GarageRecoveryFilter,
        GarageRecoveryNote,
        GarageRecoveryReading,
        OutgoingGarageRecoveryNote;
export 'src/nostr_key_pair.dart' show NostrKeyPair;
export 'src/pgp_wire.dart' show pgpArmorFromWire, pgpArmorToWire;
export 'src/robosats_failure.dart';
export 'src/robot_hash_id.dart' show RobotHashId;
export 'src/robot_identity.dart' show NostrKeyDerivation, RobotIdentity;
export 'src/robot_pgp_key.dart'
    show
        ChatDecryptionKey,
        ChatSignatureKey,
        DecryptedChatMessage,
        PgpPublicKey,
        RobotPgpKey,
        UnlockedRobotPgpKey;
export 'src/robot_token.dart' show RobotToken, TokenEntropy;
export 'src/coordinator/chat.dart'
    show
        ChatMessage,
        ChatMessageContent,
        ChatPage,
        ChatPeerKey,
        ChatPeerKeyMisnamed,
        ChatPeerKeyMissing,
        ChatPeerKeyOfPeer,
        ChatPeerKeyUnreadable,
        ChatSender,
        OutgoingChatMessage;
