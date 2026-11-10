/// Pure-Dart RoboSats client primitives: the identity of a robot, its OpenPGP key, and the read-only client of the coordinators.
///
/// A [GarageKey] derives one [RobotToken] per robot index, and a [RobotIdentity] holds everything RoboSats derives from a token: the token hash sent to coordinators, the [RobotHashId] with its nickname, the Nostr key and the `Authorization` header values.
/// A [RobotPgpKey] is the OpenPGP key pair of a robot, locked by its token: once unlocked it clear-signs invoices and payout addresses and encrypts, signs, decrypts and verifies chat messages, in the formats of the official client and of the coordinators.
/// A [CoordinatorClient] reads what a coordinator of the embedded [Federation] publishes (`/api/info/`, `/api/book/`, `/api/limits/`) through a [CoordinatorTransport] that the app implements over Tor, and a [FederationBookReader] merges the books of every coordinator.
/// Invalid input is reported as a [RobosatsFailure] in a `Result`, never thrown.
/// No Flutter, no networking of its own, no logging.
library;

export 'src/coordinator/coordinator.dart'
    show Coordinator, CoordinatorBadges, CoordinatorContact, CoordinatorOrigins;
export 'src/coordinator/coordinator_client.dart' show CoordinatorClient;
export 'src/coordinator/coordinator_info.dart'
    show CoordinatorInfo, CoordinatorVersion, NoticeSeverity;
export 'src/coordinator/coordinator_transport.dart'
    show
        CoordinatorHttpMethod,
        CoordinatorRequest,
        CoordinatorResponse,
        CoordinatorTransport;
export 'src/coordinator/currency_limits.dart'
    show CurrencyLimit, CurrencyLimits;
export 'src/coordinator/federation.dart' show Federation;
export 'src/coordinator/federation_book.dart'
    show CoordinatorBookOutcome, FederationBook, FederationBookReader;
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
export 'src/coordinator/public_order.dart' show PublicOrder;
export 'src/coordinator/read_bounds.dart' show CoordinatorReadBounds;
export 'src/coordinator/robosats_currency.dart' show RobosatsCurrency;
export 'src/coordinator/robosats_network.dart' show RobosatsNetwork;

export 'src/garage_key.dart' show GarageKey;
export 'src/nostr_key_pair.dart' show NostrKeyPair;
export 'src/pgp_wire.dart' show pgpArmorFromWire, pgpArmorToWire;
export 'src/robosats_failure.dart';
export 'src/robot_hash_id.dart' show RobotHashId;
export 'src/robot_identity.dart' show NostrKeyDerivation, RobotIdentity;
export 'src/robot_pgp_key.dart'
    show DecryptedChatMessage, PgpPublicKey, RobotPgpKey, UnlockedRobotPgpKey;
export 'src/robot_token.dart' show RobotToken, TokenEntropy;
