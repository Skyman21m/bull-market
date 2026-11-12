/// Troc peer-to-peer trading on the RoboSats federation, read over the embedded Tor.
///
/// The shell calls [P2pFeature.setup], mounts [P2pFeature.route] in its bottom bar and registers [P2pLocalizations.delegate]; everything else goes through [P2pFacade], whose signatures use the types of `package:robosats` exported here.
library;

export 'generated/l10n/p2p_localizations.dart' show P2pLocalizations;

export 'package:primitives/primitives.dart' show Err, Ok, Result, Sats;
// The types of the facade's signatures, and of their fields, so that a screen shows a coordinator, its info and its orders without importing `robosats`.
// Nothing that makes, holds or reveals a robot is exported: Garage Keys, robot identities and robot keys stay inside the feature, where the custody rules of `AGENTS.md` apply to them.
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
        CoordinatorTimedOut,
        CoordinatorTransportBusy,
        CoordinatorTransportFailed,
        CoordinatorTransportFailure,
        CoordinatorUnexpectedStatus,
        CoordinatorUnreachable,
        CoordinatorVersion,
        DroppedOrderReason,
        FiatAmount,
        FixedOrderAmount,
        MakerActivity,
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
        RobotHashId;

export 'public/p2p_facade.dart' show P2pFacade, P2pFeature;
export 'src/domain/p2p_tor_state.dart' show P2pTorState;
export 'src/ui/garage/garage_reauthentication.dart' show P2pReauthentication;
