/// Troc peer-to-peer trading on the RoboSats federation, read over the embedded Tor.
///
/// The shell calls [P2pFeature.setup], mounts [P2pFeature.route] in its bottom bar and registers [P2pLocalizations.delegate]; everything else goes through [P2pFacade], whose signatures use the types of `package:robosats` exported here.
library;

export 'generated/l10n/p2p_localizations.dart' show P2pLocalizations;

export 'package:primitives/primitives.dart' show Err, Ok, Result, Sats;
// The types of the facade's signatures, and of their fields, so that a screen shows a coordinator, its info, its orders and a robot without importing `robosats`.
// `GarageKey` and `GarageRobot` are how a caller gets the `RobotIdentity` the robot methods take.
export 'package:robosats/robosats.dart'
    show
        BondSize,
        Coordinator,
        CoordinatorBadges,
        CoordinatorBookOutcome,
        CoordinatorContact,
        CoordinatorFailure,
        CoordinatorIdentityFailure,
        CoordinatorInfo,
        CoordinatorNetworkMismatch,
        CoordinatorNodeIdMismatch,
        CoordinatorNotJson,
        CoordinatorNotOnNetwork,
        CoordinatorOrigins,
        CoordinatorResponseMalformed,
        CoordinatorResponseTooLarge,
        CoordinatorRobot,
        CoordinatorRobotFailure,
        CoordinatorTimedOut,
        CoordinatorTransportFailed,
        CoordinatorTransportFailure,
        CoordinatorUnexpectedStatus,
        CoordinatorUnreachable,
        CoordinatorVersion,
        DroppedOrderReason,
        FiatAmount,
        FixedOrderAmount,
        GarageKey,
        GarageRobot,
        MakerActivity,
        NostrKeyDerivation,
        NoticeSeverity,
        OrderAmount,
        OrderBook,
        OrderLocation,
        OrderType,
        PaymentMethodInfo,
        PaymentMethods,
        Premium,
        PublicOrder,
        RangeOrderAmount,
        RobosatsCurrency,
        RobosatsNetwork,
        RobotCredentialsRejected,
        RobotHashId,
        RobotHashIdMismatch,
        RobotIdentity,
        RobotKeysRefusal,
        RobotKeysRefused,
        RobotMismatchFailure,
        RobotNicknameMismatch,
        RobotNicknameTaken,
        RobotPgpKey,
        RobotPgpKeyMismatch,
        RobotUnknown;

export 'public/p2p_facade.dart' show P2pFacade, P2pFeature;
export 'src/domain/p2p_tor_state.dart' show P2pTorState;
