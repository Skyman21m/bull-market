/// Troc peer-to-peer trading on the RoboSats federation, read over the embedded Tor.
///
/// The shell calls [P2pFeature.setup]; everything else goes through [P2pFacade], whose signatures use the types of `package:robosats` exported here.
library;

export 'package:primitives/primitives.dart' show Err, Ok, Result;
export 'package:robosats/robosats.dart'
    show
        Coordinator,
        CoordinatorBookOutcome,
        CoordinatorFailure,
        CoordinatorIdentityFailure,
        CoordinatorInfo,
        CoordinatorNetworkMismatch,
        CoordinatorNodeIdMismatch,
        CoordinatorNotJson,
        CoordinatorNotOnNetwork,
        CoordinatorResponseMalformed,
        CoordinatorResponseTooLarge,
        CoordinatorTimedOut,
        CoordinatorTransportFailed,
        CoordinatorTransportFailure,
        CoordinatorUnexpectedStatus,
        CoordinatorUnreachable,
        DroppedOrderReason,
        OrderBook,
        PublicOrder,
        RobosatsNetwork;

export 'public/p2p_facade.dart' show P2pFacade, P2pFeature;
export 'src/domain/p2p_tor_state.dart' show P2pTorState;
