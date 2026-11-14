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
// The port through which the shell lends the wallet's Instant Payments wallet (#100), and the types of its signatures.
export 'public/p2p_wallet_port.dart'
    show
        P2pWalletInvoiceExpired,
        P2pWalletInvoiceUnreadable,
        P2pWalletNeedsConsolidation,
        P2pWalletNoInstantWallet,
        P2pWalletNotEnoughBalance,
        P2pWalletOutsideServiceLimits,
        P2pWalletOverMaximum,
        P2pWalletPort,
        P2pWalletQuote,
        P2pWalletRefusal,
        P2pWalletServiceBusy,
        P2pWalletServiceRefused,
        P2pWalletServiceUnreachable,
        P2pWalletUnavailable,
        P2pWalletUnderMinimum,
        P2pWalletWrongNetwork;
export 'src/domain/checked_bolt11_invoice.dart' show CheckedBolt11Invoice;
export 'src/domain/p2p_tor_state.dart' show P2pTorState;
// The BOLT11 decoder port, which the shell implements with the app's pinned `bolt11_decoder` (#86, design note § 3.9): the trade's checks read every invoice of a coordinator through it.
export 'src/domain/trade/bolt11.dart'
    show
        Bolt11AmountUnusable,
        Bolt11Decoder,
        Bolt11Invoice,
        Bolt11Malformed,
        Bolt11Network,
        Bolt11NotVisibleAscii,
        Bolt11Refusal,
        Bolt11TooLong,
        Bolt11UnknownNetwork;
export 'src/ui/garage/garage_reauthentication.dart' show P2pReauthentication;
