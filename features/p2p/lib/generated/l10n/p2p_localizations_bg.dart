// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bulgarian (`bg`).
class P2pLocalizationsBg extends P2pLocalizations {
  P2pLocalizationsBg([String locale = 'bg']) : super(locale);

  @override
  String get p2pTabLabel => 'P2P';

  @override
  String get p2pTestnetBanner => 'Using Testnet Bitcoin';

  @override
  String get p2pTorWaitingLine =>
      'Coordinators are only ever reached through Tor.';

  @override
  String get p2pTorInitializing => 'Initializing Tor daemon';

  @override
  String get p2pTorConnecting => 'Connecting to Tor network';

  @override
  String get p2pTorConnected => 'Connected to Tor network';

  @override
  String get p2pTorConnectionError => 'Connection error';

  @override
  String get p2pTorWaitPhrase1 => 'Sats travelling at the speed of light';

  @override
  String get p2pTorWaitPhrase2 => 'Peeling the onion, layer by layer';

  @override
  String get p2pTorWaitPhrase3 => 'Bouncing from relay to relay';

  @override
  String get p2pTorWaitPhrase4 => 'Hiding your IP address from coordinators';

  @override
  String get p2pTorWaitPhrase5 => 'Waking up the robots';

  @override
  String get p2pTorWaitPhrase6 => 'No KYC, just robots';

  @override
  String get p2pTorWaitPhrase7 => 'Not your keys, not your coins';

  @override
  String get p2pTorWaitPhrase8 => 'Don\'t trust, verify';

  @override
  String get p2pTorWaitPhrase9 => 'Privacy is not a crime';

  @override
  String get p2pTorWaitPhrase10 => 'Be your own bank';

  @override
  String get p2pTorWaitPhrase11 => 'Tick tock, next block';

  @override
  String get p2pTorWaitPhrase12 => 'Loading with low time preference';

  @override
  String get p2pNavOffers => 'Offers';

  @override
  String get p2pNavCreate => 'Create';

  @override
  String get p2pNavGarage => 'Garage';

  @override
  String get p2pNavOrder => 'Order';

  @override
  String get p2pCommonSearch => 'Search';

  @override
  String get p2pBookViewList => 'List';

  @override
  String get p2pBookViewChart => 'Chart';

  @override
  String get p2pBookViewMap => 'Map';

  @override
  String get p2pBookFilterIWantTo => 'I want to';

  @override
  String get p2pBookFilterBuy => 'Buy';

  @override
  String get p2pBookFilterSell => 'Sell';

  @override
  String get p2pBookFilterSelectOrderType => 'Select Order Type';

  @override
  String get p2pBookFilterAndUse => 'and use';

  @override
  String get p2pBookFilterSelectCurrency => 'Select Payment Currency';

  @override
  String get p2pBookFilterPayWith => 'pay with';

  @override
  String get p2pBookFilterSelectMethod => 'Select Payment Method';

  @override
  String get p2pBookFilterHostedBy => 'hosted by';

  @override
  String get p2pBookFilterSelectHost => 'Select Host';

  @override
  String get p2pBookFilterIWant => 'I want';

  @override
  String get p2pBookFilterAnyType => 'Any type';

  @override
  String get p2pBookFilterAnyCurrency => 'Any currency';

  @override
  String get p2pBookFilterAnyMethod => 'Any payment method';

  @override
  String get p2pBookFilterAnyHost => 'Any host';

  @override
  String p2pBookFilterMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get p2pBookFilterSubjectType => 'Order type';

  @override
  String get p2pBookFilterSubjectCurrency => 'Currency';

  @override
  String get p2pBookFilterSubjectMethod => 'Payment method';

  @override
  String get p2pBookFilterSubjectHost => 'Host';

  @override
  String p2pBookFilterChoices(String subject, String choices) {
    return '$subject: $choices';
  }

  @override
  String p2pBookFilterOrList(String others, String last) {
    return '$others or $last';
  }

  @override
  String get p2pBookFilterListSeparator => ', ';

  @override
  String p2pBookFilterOrderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders',
      one: '1 order',
      zero: 'no orders',
    );
    return '$_temp0';
  }

  @override
  String p2pBookFilterMethodWithCount(String method, String orders) {
    return '$method · $orders';
  }

  @override
  String p2pBookFilterMethodWithCountSemantics(String method, String orders) {
    return '$method, $orders';
  }

  @override
  String get p2pBookFilterMethodsWithoutOrders => 'No orders right now';

  @override
  String get p2pBookFilterNoMethodFound => 'No payment method found';

  @override
  String get p2pBookMakerStatusActive => 'Active';

  @override
  String get p2pBookMakerStatusSeenRecently => 'Seen recently';

  @override
  String get p2pBookMakerStatusInactive => 'Inactive';

  @override
  String get p2pBookRoleSeller => 'Seller';

  @override
  String get p2pBookRoleBuyer => 'Buyer';

  @override
  String get p2pBookColumnAmount => 'Amount';

  @override
  String get p2pBookColumnPremium => 'Premium';

  @override
  String get p2pBookColumnBond => 'Bond';

  @override
  String p2pBookLowBond(String defaultBond) {
    return 'Low bond: This maker has set a bond below the default $defaultBond%. Lower bonds mean reduced trade security.';
  }

  @override
  String get p2pBookError => 'An error occurred.';

  @override
  String p2pBookEmptySell(String currencyCode) {
    return 'No orders found to sell BTC for $currencyCode';
  }

  @override
  String p2pBookEmptyBuy(String currencyCode) {
    return 'No orders found to buy BTC for $currencyCode';
  }

  @override
  String get p2pBookEmptyAnyCurrency => 'any currency';

  @override
  String get p2pBookEmptyBeFirst => 'Be the first one to create an order';

  @override
  String get p2pOrderHost => 'Order host';

  @override
  String get p2pOrderId => 'ID';

  @override
  String get p2pOrderFeeMaker => 'Maker';

  @override
  String get p2pOrderFeeMakerTooltip => 'Maker fee';

  @override
  String get p2pOrderFeeTaker => 'Taker';

  @override
  String get p2pOrderFeeTakerTooltip => 'Taker fee';

  @override
  String get p2pOrderOnchainEnabled => 'Onchain payouts enabled';

  @override
  String get p2pOrderOnchainDisabled => 'Onchain payouts disabled';

  @override
  String get p2pOrderDetailsDivider => 'Order Details';

  @override
  String get p2pOrderAmountRange => 'Amount Range';

  @override
  String p2pOrderYouSendVia(String method, String amount) {
    return 'You send via $method $amount';
  }

  @override
  String p2pOrderYouReceiveSats(String amount) {
    return 'You receive $amount Sats (Approx)';
  }

  @override
  String p2pOrderYouSendLightning(String amount) {
    return 'You send via Lightning $amount Sats (Approx)';
  }

  @override
  String p2pOrderYouReceiveVia(String method, String amount) {
    return 'You receive via $method $amount';
  }

  @override
  String get p2pOrderSwapDestination => 'Swap destination';

  @override
  String get p2pOrderAcceptedMethods => 'Accepted payment methods';

  @override
  String p2pOrderPriceAndPremiumValue(
    String price,
    String currencyCode,
    String premium,
  ) {
    return '$price $currencyCode/BTC - Premium: $premium%';
  }

  @override
  String get p2pOrderPriceAndPremium => 'Price and Premium';

  @override
  String get p2pOrderAmountOfSatoshis => 'Amount of Satoshis';

  @override
  String get p2pOrderPremiumOverMarket => 'Premium over market price';

  @override
  String get p2pOrderExpiresIn => 'Expires in';

  @override
  String get p2pOrderExpired => 'The order has expired';

  @override
  String get p2pOrderDeposit => 'Deposit';

  @override
  String get p2pTakeOrder => 'Take Order';

  @override
  String get p2pCoordinatorOffline => 'Coordinator offline';

  @override
  String get p2pOrderMaker => 'Order maker';

  @override
  String get p2pCommonRetry => 'Retry';

  @override
  String p2pBookCoordinatorsAnswered(int answered, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$answered of $total coordinators answered',
      one: '$answered of 1 coordinator answered',
    );
    return '$_temp0';
  }

  @override
  String p2pBookCoordinatorsOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coordinators offline',
      one: '1 coordinator offline',
    );
    return '$_temp0';
  }

  @override
  String p2pBookCoordinatorAnswered(String name) {
    return '$name, answered';
  }

  @override
  String p2pBookCoordinatorAwaited(String name) {
    return '$name, awaited';
  }

  @override
  String p2pBookCoordinatorOffline(String name) {
    return '$name, offline';
  }

  @override
  String p2pDurationHours(String hours) {
    return '${hours}h';
  }

  @override
  String p2pDurationMinutes(String minutes) {
    return '${minutes}m';
  }

  @override
  String p2pDurationHoursMinutes(String hours, String minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String p2pCountdownHms(String hours, String minutes, String seconds) {
    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  String get p2pBookOthers => 'Others';

  @override
  String get p2pReversibleTitle => 'Reversible payments';

  @override
  String get p2pReversibleIntro =>
      'This order offers one or multiple payment methods that the community has consistently reported as reverting their transactions.';

  @override
  String get p2pReversible80Days =>
      'If you receive a fiat transaction, it can be unilatery reverted up to 80 days after the trade has been completed.';

  @override
  String get p2pReversibleNoControl =>
      'Robosats and their coordinators have no control over the fiat system.';

  @override
  String get p2pReversibleScammers =>
      'Scammers can exploit this vulnerability in the fiat system to take away both your bitcoin and your fiat.';

  @override
  String get p2pCommonAcknowledged => 'Acknowledged';

  @override
  String get p2pCoordinatorNotice => 'Coordinator Notice';

  @override
  String get p2pCoordinatorBadgeFounder =>
      'Founder: coordinating trades since the testnet federation.';

  @override
  String get p2pCoordinatorBadgeNotFounder => 'Not a federation founder';

  @override
  String p2pCoordinatorBadgeDevFund(String percent) {
    return 'Development fund supporter: donates $percent% to make RoboSats better.';
  }

  @override
  String get p2pCoordinatorBadgeGoodOpsec =>
      'Good OpSec: the coordinator follows best practices to protect his and your privacy.';

  @override
  String get p2pCoordinatorBadgeOpsecCouldImprove =>
      'The privacy practices of this coordinator could improve';

  @override
  String get p2pCoordinatorBadgeLargeLimits =>
      'Large limits: the coordinator has large trade limits.';

  @override
  String get p2pCoordinatorBadgeNoLargeLimits =>
      'Does not have large trade limits.';

  @override
  String get p2pCoordinatorDescription => 'Coordinator description';

  @override
  String get p2pCoordinatorEstablished => 'Established';

  @override
  String get p2pCoordinatorHostedWebApp => 'Coordinator hosted web app';

  @override
  String get p2pCoordinatorPolicies => 'Policies';

  @override
  String get p2pCoordinatorSummary => 'Summary';

  @override
  String get p2pCoordinatorMaxOrderSize => 'Maximum order size';

  @override
  String get p2pCoordinatorOnchainStatus => 'Current onchain payout status';

  @override
  String get p2pCoordinatorCurrentOnchainFee => 'Current onchain payout fee';

  @override
  String get p2pCoordinatorMaxSwapSize => 'Maximum onchain swap size';

  @override
  String get p2pCoordinatorDevFundZaps => 'Zaps voluntarily for development';

  @override
  String p2pCoordinatorDevFundPercent(String percent) {
    return '$percent% of profits';
  }

  @override
  String get p2pCoordinatorPublicBuyOrders => 'Public buy orders';

  @override
  String get p2pCoordinatorPublicSellOrders => 'Public sell orders';

  @override
  String get p2pCoordinatorBookLiquidity => 'Book liquidity';

  @override
  String get p2pCoordinatorActiveRobotsToday => 'Today active robots';

  @override
  String get p2pCoordinatorNonKycPremium => '24h non-KYC bitcoin premium';

  @override
  String get p2pCoordinatorPriceSources =>
      'Market price sources (for multiple the median is calculated)';

  @override
  String get p2pCoordinatorStatsForNerds => 'Stats for Nerds';

  @override
  String get p2pCoordinatorVersionCoordinator => 'Coordinator';

  @override
  String get p2pCoordinatorRoboSatsVersion => 'RoboSats version';

  @override
  String get p2pCoordinatorLndVersion => 'LND version';

  @override
  String get p2pCoordinatorClnVersion => 'CLN version';

  @override
  String p2pCoordinatorLnNodeAlias(String alias) {
    return 'LN Node: $alias';
  }

  @override
  String get p2pCoordinatorCommitHash => 'Coordinator commit hash';

  @override
  String get p2pCoordinatorVolume24h => '24h contracted volume';

  @override
  String get p2pCoordinatorVolumeLifetime => 'Lifetime contracted volume';

  @override
  String p2pAmountSats(String amount) {
    return '$amount Sats';
  }

  @override
  String get p2pCoordinatorSendEmail => 'Send Email';

  @override
  String get p2pCoordinatorWebsite => 'Website';

  @override
  String get p2pCoordinatorPgpFingerprint => 'PGP Pubkey fingerprint';

  @override
  String get p2pCoordinatorNostr => 'Nostr';

  @override
  String get p2pCoordinatorTelegram => 'Telegram';

  @override
  String get p2pCoordinatorX => 'X';

  @override
  String get p2pCoordinatorReddit => 'Reddit';

  @override
  String get p2pCoordinatorMatrix => 'Matrix';

  @override
  String get p2pCoordinatorSimplex => 'Simplex';

  @override
  String get p2pCommonCopied => 'Copied!';

  @override
  String get p2pSearchOrderTitle => 'Search order';

  @override
  String get p2pSearchOrderText =>
      'Enter here an order URL to search for it, even if it\'s password protected';

  @override
  String get p2pSearchOrderUrlLabel => 'Order URL';

  @override
  String get p2pCommonCancel => 'Cancel';

  @override
  String get p2pNoRobotTitle => 'You do not have a Garage Key';

  @override
  String get p2pNoRobotText =>
      'Generate a Garage Key to get your first robot identity and start trading.';

  @override
  String get p2pNoRobotHaveKey => 'I have a Garage Key';

  @override
  String get p2pOrderNotAvailable => 'This order is not available';

  @override
  String get p2pGarageOnboardingGenerateKey => 'Generate Garage Key';

  @override
  String get p2pCoordinatorLnNode => 'LN Node';

  @override
  String p2pCoordinatorVersionValue(String name, String version) {
    return '$name v$version';
  }

  @override
  String p2pCoordinatorNodeAmboss(String node) {
    return '$node... (AMBOSS)';
  }

  @override
  String p2pCoordinatorNode1ml(String node) {
    return '$node... (1ML)';
  }

  @override
  String p2pCoordinatorCommitShort(String commit) {
    return '$commit...';
  }

  @override
  String get p2pCommonCopy => 'Copy';

  @override
  String get p2pBookColumnPrice => 'Price';

  @override
  String get p2pChartBtc => 'BTC';

  @override
  String get p2pChartZoomOut => 'Zoom out';

  @override
  String get p2pChartZoomIn => 'Zoom in';

  @override
  String p2pChartCenterPrice(String price, String currencyCode) {
    return '$price $currencyCode';
  }

  @override
  String p2pChartBuyOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count buy orders',
      one: '1 buy order',
    );
    return '$_temp0';
  }

  @override
  String p2pChartSellOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sell orders',
      one: '1 sell order',
    );
    return '$_temp0';
  }

  @override
  String p2pChartSummary(String center, String buyOrders, String sellOrders) {
    return 'Depth chart centered on $center: $buyOrders and $sellOrders.';
  }

  @override
  String get p2pChartSummaryNoAxis =>
      'Depth chart: nothing to draw on this axis.';

  @override
  String get p2pMapNoLocation => 'No order with a face to face location';

  @override
  String p2pMapSummary(String buyOrders, String sellOrders) {
    return 'Map of the face to face locations of the order book: $buyOrders and $sellOrders.';
  }

  @override
  String p2pMapOrdersHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders here',
      one: '1 order here',
    );
    return '$_temp0';
  }

  @override
  String p2pMapPin(
    String role,
    String amount,
    String currencyCode,
    String coordinator,
  ) {
    return '$role, $amount $currencyCode, $coordinator';
  }

  @override
  String get p2pCommonContinue => 'Continue';

  @override
  String get p2pGarageWelcomeTagline => 'A Simple and Private LN P2P Exchange';

  @override
  String get p2pGarageWelcomeCreateRobot =>
      'Create a new robot and learn to use RoboSats';

  @override
  String get p2pGarageWelcomeStart => 'Start';

  @override
  String get p2pGarageWelcomeRecoverHint =>
      'Recover an existing robot using your token';

  @override
  String get p2pGarageWelcomeRecovery => 'Recovery';

  @override
  String get p2pGarageWelcomeSearchForOrders => 'Search for Orders';

  @override
  String get p2pGarageWelcomeFastGenerateOrder => 'Fast Generate Order';

  @override
  String get p2pGarageOnboardingStep1Title => '1. Generate your Garage Key';

  @override
  String get p2pGarageOnboardingStep1Text =>
      'Your Garage Key is a master key that derives unlimited robot identities. Generate it once and use it forever.';

  @override
  String get p2pGarageOnboardingStoreItTitle => 'Store it somewhere safe!';

  @override
  String get p2pGarageOnboardingStoreItText =>
      'This key is the master key to all your robots. Keep it secret and backed up securely.';

  @override
  String get p2pGarageKeyHelper => 'Store your Garage Key safely';

  @override
  String get p2pGarageKeyInvalid => 'Invalid garage key';

  @override
  String get p2pGarageOnboardingPasteExisting =>
      'Or paste an existing Garage Key to recover your robots.';

  @override
  String get p2pGarageOnboardingGenerateNew => 'Generate new';

  @override
  String get p2pGarageOnboardingStep2Title => '2. Meet your robot identity';

  @override
  String get p2pGarageTradingAvatar => 'This is your trading avatar';

  @override
  String get p2pGarageHiMyNameIs => 'Hi! My name is';

  @override
  String get p2pGaragePreviousAccount => 'Previous account';

  @override
  String get p2pGarageNextAccount => 'Next account';

  @override
  String get p2pGarageRobotLabel => 'Robot';

  @override
  String get p2pGarageOnboardingStep3Title => '3. Browse or create an order';

  @override
  String get p2pGarageOnboardingStep3Text =>
      'RoboSats is a peer-to-peer marketplace. You can browse the public offers or create a new one.';

  @override
  String get p2pGarageOnboardingHelpIntro =>
      'If you need help on your RoboSats journey join our public support';

  @override
  String get p2pGarageOnboardingHelpLink => 'SimpleX group';

  @override
  String get p2pGarageOnboardingHelpOutro =>
      'or visit the robot school for documentation.';

  @override
  String get p2pGarageLearnRoboSats => 'Learn RoboSats';

  @override
  String get p2pGarageSeeProfile => 'See profile';

  @override
  String get p2pGarageKeyLabel => 'Garage Key';

  @override
  String get p2pGarageProfileDeleteAllTooltip =>
      'Delete Garage Key and all robots';

  @override
  String get p2pGarageProfileDeleteAll => 'Delete All';

  @override
  String get p2pRecoveryTitle => 'Robot recovery';

  @override
  String get p2pRecoveryModeGarageKey => 'Garage Key Mode';

  @override
  String get p2pRecoveryGarageKeyText =>
      'Enter your garage key (robo1...) to recover all your robot accounts.';

  @override
  String get p2pRecoveryPasteHere => 'Paste token here';

  @override
  String get p2pRecoveryInProgress =>
      'Recovering your robot. This may take a moment.';

  @override
  String get p2pRecoveryRecover => 'Recover';

  @override
  String get p2pDeleteKeyTitle => 'Delete Garage Key?';

  @override
  String get p2pDeleteKeyQuestion =>
      'Are you sure you want to permanently delete this Garage Key and ALL associated robots?';

  @override
  String get p2pDeleteCannotBeUndone => '⚠️ This action cannot be undone!';

  @override
  String get p2pDeleteBeforeDeleting => 'Before deleting, make sure you have:';

  @override
  String get p2pDeleteKeyStoredKey => 'Stored your Garage Key safely';

  @override
  String get p2pDeleteKeyNoActiveOrders =>
      'No active or pending orders in ANY robot';

  @override
  String get p2pDeleteExportedData => 'Exported any important data';

  @override
  String get p2pDeleteKeyConfirm => 'Delete Garage Key';

  @override
  String get p2pGarageKeyMustStartWith => 'Must start with \"robo1\"';

  @override
  String get p2pGarageKeyInvalidLength => 'Invalid length';

  @override
  String get p2pGarageKeyInvalidData => 'Invalid key data';

  @override
  String get p2pGarageKeyReveal => 'Show Garage Key';

  @override
  String get p2pGarageScreenPrivacyUnavailable =>
      'Screen protection could not be turned on, so the Garage Key stays hidden.';

  @override
  String get p2pGarageKeyLocked =>
      'The keystore is locked. Unlock your device, then try again.';

  @override
  String get p2pGarageKeyUnreadable =>
      'The Garage Key stored on this device cannot be read.';

  @override
  String get p2pGarageKeyUnusable =>
      'The Garage Key stored on this device is damaged.';

  @override
  String get p2pGarageKeyUnreadableHelp =>
      'Try again. If it keeps failing, delete it: the key and its robots are lost unless you kept a copy.';

  @override
  String get p2pGarageKeyNotSaved =>
      'The Garage Key could not be saved. Try again.';

  @override
  String get p2pGarageKeyNotDeleted =>
      'The Garage Key could not be deleted. Try again.';

  @override
  String get p2pGarageKeyAlreadyStored =>
      'A Garage Key is already stored for this network.';

  @override
  String get p2pGarageRobotUnavailable =>
      'No robot can be made from this Garage Key.';

  @override
  String get p2pCommonPaste => 'Paste';

  @override
  String get p2pCommonClear => 'Clear';

  @override
  String get p2pGarageKeyHistoryNotRecorded =>
      'This device could not record that it drew this Garage Key. Its robots will ask for your confirmation before they reach a coordinator. You can generate a new key instead.';

  @override
  String get p2pRobotCoordinatorTitle => 'Coordinator that knows your robot:';

  @override
  String get p2pRobotNoCoordinator => 'No coordinator knows this robot yet.';

  @override
  String get p2pRobotSelectHost => 'Select Host';

  @override
  String p2pRobotHostDetails(String coordinator) {
    return 'Details of $coordinator';
  }

  @override
  String p2pRobotSendTitle(String nickname, String coordinator) {
    return 'Send $nickname to $coordinator?';
  }

  @override
  String p2pRobotSendBody(String coordinator) {
    return '$coordinator will know this robot from now on. In Bull Market, a robot lives on one coordinator only: this robot will never be sent to another one. To trade elsewhere, use another robot.';
  }

  @override
  String get p2pRobotSendOtherApp =>
      'If you also use this Garage Key in another app, that app may send this robot to every coordinator.';

  @override
  String get p2pGarageBuildingRobot => 'Building your robot!';

  @override
  String get p2pRobotLookingForOrders => 'Looking for orders!';

  @override
  String p2pRobotStillWaiting(String coordinator) {
    return 'Still waiting for $coordinator. Tor can take a minute.';
  }

  @override
  String p2pRobotActiveOrder(String orderId) {
    return 'Active order #$orderId';
  }

  @override
  String p2pRobotLastOrder(String orderId) {
    return 'Last order #$orderId';
  }

  @override
  String get p2pRobotNoOrders => 'No existing orders found';

  @override
  String get p2pRobotUsedInTrade =>
      'This robot was involved in a trade. Navigate to a new account for fresh privacy.';

  @override
  String get p2pRobotRewards => 'Your compensations';

  @override
  String p2pRobotAlreadyExisted(String coordinator) {
    return 'This robot already existed on $coordinator.';
  }

  @override
  String p2pRobotOnOtherNetwork(String network) {
    String _temp0 = intl.Intl.selectLogic(network, {
      'testnet': 'testnet',
      'other': 'mainnet',
    });
    return 'This robot lives on a $_temp0 coordinator.';
  }

  @override
  String get p2pRobotCoordinatorTooManyRefusals =>
      'This coordinator refused too many robots.';

  @override
  String get p2pRobotBusy =>
      'Too many requests are waiting for this coordinator. Try again in a moment.';

  @override
  String p2pRobotNicknameTaken(String coordinator) {
    return 'This robot\'s name is already taken on $coordinator, so it cannot be created there. Use the next robot.';
  }

  @override
  String p2pRobotNotCreated(String coordinator) {
    return '$coordinator does not know this robot yet.';
  }

  @override
  String p2pRobotKeyTooRecent(String coordinator) {
    return '$coordinator refused the robot\'s key as too recent. Check your phone\'s date and time, then try again.';
  }

  @override
  String p2pRobotRefused(String coordinator) {
    return '$coordinator refused this robot. It may run another version of RoboSats.';
  }

  @override
  String p2pRobotMismatch(String coordinator) {
    return '$coordinator answered with another robot, or with keys this robot did not make. Do not use this robot there.';
  }

  @override
  String p2pRobotBadAnswer(String coordinator) {
    return '$coordinator sent an answer Bull Market cannot read.';
  }

  @override
  String p2pRobotCoordinatorChanged(String coordinator) {
    return '$coordinator changed its address or keys since this robot was sent to it. Nothing was sent. Until an update of the app has checked the change, use another robot.';
  }

  @override
  String get p2pRobotStorage =>
      'Bull Market could not read its records on this device. Nothing was sent.';

  @override
  String p2pRobotNostrOld(String coordinator) {
    return '$coordinator holds an old Nostr key for this robot, which it can compute: its notifications are not private. Prefer another robot for trading.';
  }

  @override
  String p2pRobotNostrUnknown(String coordinator) {
    return '$coordinator holds a Nostr key this app cannot use: notifications about this robot will not reach it.';
  }

  @override
  String get p2pRobotKeyComputeFailed =>
      'This phone could not make or check the keys of this robot. Check its date and time, then try again.';

  @override
  String get p2pRobotBoundElsewhere =>
      'This robot lives on another coordinator. Nothing was sent.';

  @override
  String get p2pRobotRecordsUnreadable =>
      'Bull Market could not read its records on this device.';

  @override
  String get p2pRobotHistoryTitle => 'Robots from elsewhere';

  @override
  String get p2pRobotHistoryBody =>
      'This Garage Key was pasted in, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Bull Market, a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, generate a new Garage Key.';

  @override
  String get p2pRobotHistoryConfirm => 'I understand';

  @override
  String p2pTakeAmountLabel(String currencyCode) {
    return 'Amount $currencyCode';
  }

  @override
  String get p2pTakeAmountHint =>
      'Enter amount of fiat to exchange for bitcoin';

  @override
  String get p2pTakeTooLow => 'Too low';

  @override
  String get p2pTakeTooHigh => 'Too high';

  @override
  String p2pTakeYouWillReceive(String satoshis) {
    return 'You will receive $satoshis Sats (Approx)';
  }

  @override
  String get p2pTakeSpecifyAmountFirst => 'You must specify an amount first';

  @override
  String get p2pTakeSellingLater => 'Selling is coming in a later version.';

  @override
  String get p2pStoreKeyTitle => 'Store your garage key';

  @override
  String get p2pStoreKeyText =>
      'Your garage key provides access to all your robot accounts. Store it safely. You can simply copy it into another application.';

  @override
  String get p2pCommonGoBack => 'Go back';

  @override
  String get p2pCommonDone => 'Done';

  @override
  String p2pTakeCoordinatorUnreadable(String coordinator) {
    return 'Could not reach $coordinator. The order was not taken.';
  }

  @override
  String get p2pTakeOrderChanged =>
      'This order changed since it was shown. It was not taken: open it again from the book.';

  @override
  String get p2pOrderDescription => 'Order description';

  @override
  String get p2pTakerBond => 'Taker bond';

  @override
  String p2pTakeBondEstimate(String estimate, String ceiling) {
    return '$estimate Sats, at most $ceiling Sats';
  }

  @override
  String p2pTakeReadAt(String time) {
    return 'Read by your robot at $time';
  }

  @override
  String p2pOrderNewValue(String value) {
    return 'New value: $value';
  }

  @override
  String get p2pTakeOrderChangedRead => 'The order changed.';

  @override
  String p2pTakeStepCheckingOrder(String coordinator) {
    return 'Checking the order with $coordinator';
  }

  @override
  String get p2pTakeStepCreatingRobot => 'Building your robot!';

  @override
  String get p2pTakeStepReadingOrder => 'Your robot is reading the order';

  @override
  String get p2pTakeStepReadingOrderAgain =>
      'Your robot is reading the order again';

  @override
  String p2pTakeStepSendingTake(String coordinator) {
    return 'Taking the order with $coordinator';
  }

  @override
  String p2pTradeFirstRead(String coordinator) {
    return 'Your robot is reading the order from $coordinator';
  }

  @override
  String get p2pTakeAmountOutOfRange =>
      'The amount specified is outside the range specified by the maker';

  @override
  String p2pTakeFeeTooHigh(String coordinator) {
    return '$coordinator asks for a taker fee above 1 %. The order was not taken.';
  }

  @override
  String get p2pTakeTermsUnusable =>
      'The terms of this order could not be checked. It was not taken.';

  @override
  String p2pTakeNotTakenAfter(String reason) {
    return '$reason The order was not taken.';
  }

  @override
  String get p2pTakeNotRecorded =>
      'Bull Market could not write its records on this device. The order was not taken.';

  @override
  String get p2pTakeKeyNotForTrades =>
      'The robots of a pasted Garage Key cannot take orders here. Generate a new Garage Key in the Garage.';

  @override
  String p2pTakeRobotNotNew(String coordinator) {
    return 'The robot chosen for this take already existed on $coordinator. The order was not taken: try again.';
  }

  @override
  String get p2pTakeNotMade => 'The order was not taken.';

  @override
  String get p2pTakeAlreadyMaker => 'You are already maker of an active order';

  @override
  String get p2pTakeAlreadyTaker => 'You are already taker of an active order';

  @override
  String get p2pTakeAlreadyTaking => 'You are already taking an active order';

  @override
  String get p2pTakePaymentPending =>
      'You are still pending a payment from a recent order';

  @override
  String p2pTakePenalty(String seconds) {
    return 'You need to wait $seconds seconds to take an order';
  }

  @override
  String get p2pTakeWaitPenalty => 'Wait until you can take an order';

  @override
  String get p2pTradeTabContract => 'Contract';

  @override
  String p2pTradeStep(String step, String steps) {
    return '($step/$steps)';
  }

  @override
  String p2pTradeTitleLockBond(String amountSats) {
    return 'Lock $amountSats Sats to TAKE order';
  }

  @override
  String get p2pTradeYouAreBuying => 'You are BUYING BTC';

  @override
  String get p2pTradeCompatibleWallets => 'See Compatible Wallets';

  @override
  String get p2pTradeCopyToClipboard => 'Copy to clipboard';

  @override
  String get p2pTradeHoldInvoiceBond =>
      'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.';

  @override
  String get p2pTradeInvoiceQr => 'QR code of the bond invoice';

  @override
  String get p2pTradeInvoiceExpires => 'Expires at';

  @override
  String get p2pTradeInvoiceNetwork => 'Network';

  @override
  String get p2pTradeInvoiceDescription => 'Description';

  @override
  String get p2pTradeNetworkMainnet => 'Bitcoin';

  @override
  String get p2pTradeNetworkTestnet => 'Bitcoin testnet';

  @override
  String get p2pTradePayOtherWallet => 'Pay with another wallet';

  @override
  String get p2pTradeShowAnyway => 'Show anyway';

  @override
  String get p2pTradeBondLocked => 'Your taker bond is locked';

  @override
  String get p2pTradeBondUnlocked => 'Your taker bond is unlocked';

  @override
  String get p2pTradeBondSettled => 'Your taker bond is settled';

  @override
  String get p2pTradeTitlePayout => 'Submit payout info';

  @override
  String p2pTradePayoutPrompt(String amountFiat, String currencyCode) {
    return 'Before letting you send $amountFiat $currencyCode, we want to make sure you are able to receive the BTC.';
  }

  @override
  String get p2pTradeTitleInfoGood => 'Your info looks good!';

  @override
  String get p2pTradeEscrowWait =>
      'We are waiting for the seller to lock the trade amount.';

  @override
  String get p2pTradeEscrowWaitHangOn =>
      'Just hang on for a moment. If the seller does not deposit, you will get your bond back automatically. In addition, you will receive a compensation (check the rewards in your profile).';

  @override
  String get p2pTradeExpiredNotTaken => 'Expired not taken';

  @override
  String get p2pTradeExpiredMakerBond => 'Maker bond not locked';

  @override
  String get p2pTradeExpiredEscrow => 'Escrow not locked';

  @override
  String get p2pTradeExpiredInvoice => 'Invoice not submitted';

  @override
  String get p2pTradeExpiredNeither =>
      'Neither escrow locked or invoice submitted';

  @override
  String get p2pOrderCancelled => 'This order has been cancelled';

  @override
  String get p2pTradeTitleChat => 'Chat with the seller';

  @override
  String get p2pTradeTitleDispute => 'A dispute has been opened';

  @override
  String get p2pTradeTitleStatementReceived =>
      'We have received your statement';

  @override
  String get p2pTradeTitleSendingSats => 'Attempting Lightning Payment';

  @override
  String get p2pTradeTitleFinished => 'Trade finished!';

  @override
  String get p2pTradeTitleRoutingFailed => 'Lightning Routing Failed';

  @override
  String get p2pTradeTitleStatements => 'We have the statements';

  @override
  String get p2pTradeTitleDisputeWon => 'You have won the dispute';

  @override
  String get p2pTradeTitleDisputeLost => 'You have lost the dispute';

  @override
  String get p2pTradeTitleUnknown => 'Unknown Order Status';

  @override
  String get p2pTradeStepLater => 'Bull Market cannot show this step yet.';

  @override
  String get p2pTradeCopyUrl => 'Copy URL';

  @override
  String get p2pTradeCopyOrderUrl => 'Copy order URL';

  @override
  String get p2pTradeCancelOrder => 'Cancel order';

  @override
  String get p2pTradeCancelUnilateral =>
      'Unilateral cancelation (bond at risk!)';

  @override
  String get p2pTradeCancelWhilePayout =>
      'Cancel is off while your payout info is being sent.';

  @override
  String get p2pTradeCancelTitle => 'Cancel the order?';

  @override
  String get p2pTradeCancelPreTakeText =>
      'If the order is cancelled now but you already tried to pay the invoice, you might lose your bond.';

  @override
  String get p2pTradeCancelBack => 'Back';

  @override
  String get p2pTradeConfirmCancellation => 'Confirm cancellation';

  @override
  String get p2pTradeCancelBondText =>
      'If the order is cancelled now you will lose your bond.';

  @override
  String get p2pTradeConfirmCancel => 'Confirm Cancel';

  @override
  String get p2pTradeCancelMovedOn =>
      'The order moved on before the cancel: nothing was cancelled.';

  @override
  String p2pTradeCancelNotDoneAfter(String reason) {
    return '$reason Nothing was cancelled.';
  }

  @override
  String get p2pTradeCancelUnknown =>
      'Bull Market does not know yet whether the cancel went through. It keeps checking.';

  @override
  String get p2pTradeCancelNeedsRead =>
      'Wait until the order is read again before cancelling.';

  @override
  String get p2pTradeCancelOnlyTogether =>
      'Only a collaborative cancel is possible now, which comes in a later version.';

  @override
  String get p2pTradeCancelNotPossible => 'You cannot cancel this order';

  @override
  String p2pTradeTakePending(String coordinator) {
    return 'Bull Market does not know yet whether the take went through. It keeps checking with $coordinator.';
  }

  @override
  String p2pTradeTakeNeverSent(String coordinator) {
    return 'This take was never sent to $coordinator.';
  }

  @override
  String p2pTradeReadsFailing(String coordinator, String time) {
    return 'Cannot reach $coordinator. What is shown was read at $time.';
  }

  @override
  String get p2pTradeRecordProblem =>
      'Bull Market could not write the records of this trade on this device.';

  @override
  String p2pTradeClosedProblem(String coordinator) {
    return 'This trade was closed on this device, but $coordinator shows this robot as its taker.';
  }

  @override
  String get p2pTradeUnrestorable =>
      'Bull Market cannot read the records of this trade. Nothing is sent.';

  @override
  String p2pTradeCoordinatorGone(String coordinator) {
    return '$coordinator is no longer in the list of coordinators. Nothing is sent.';
  }

  @override
  String get p2pTradeUnavailable =>
      'Bull Market cannot open this trade now. Nothing is sent.';

  @override
  String get p2pTradeKeyMissing =>
      'The Garage Key of this trade is not on this device. Nothing is sent.';

  @override
  String p2pTradeWarnRole(String coordinator) {
    return '$coordinator gives this robot another role than the one it took. Do not pay anything.';
  }

  @override
  String p2pTradeWarnOrder(String coordinator) {
    return '$coordinator answered about another order. Do not pay anything.';
  }

  @override
  String get p2pTradeWarnTerms =>
      'The terms of the order are not those of the order taken.';

  @override
  String get p2pTradeWarnUnexpected =>
      'Unexpected change on the coordinator\'s side.';

  @override
  String p2pTradeWarnRegressed(String coordinator) {
    return '$coordinator sent a status that does not follow this trade. It was ignored.';
  }

  @override
  String p2pTradeWarnInconsistent(String coordinator) {
    return '$coordinator contradicted itself earlier in this trade.';
  }

  @override
  String get p2pTradeWarnHistoryUnknown =>
      'This trade was found without its history: its invoices cannot be compared with the first ones.';

  @override
  String get p2pTradeWarnBond =>
      'The bond asked is not the bond of the order taken.';

  @override
  String get p2pTradeWarnPrice =>
      'The trade amount does not match the order\'s price.';

  @override
  String p2pTradeWarnAmounts(String coordinator) {
    return 'The amounts $coordinator gives do not add up.';
  }

  @override
  String p2pTradeWarnDeadline(String coordinator) {
    return '$coordinator moved the deadline earlier.';
  }

  @override
  String p2pTradeWarnUnreadable(String coordinator) {
    return 'The invoice $coordinator sent cannot be read. It is not shown.';
  }

  @override
  String p2pTradeWarnWrongNetwork(String coordinator) {
    return 'The invoice $coordinator sent is for another network. It is not shown.';
  }

  @override
  String get p2pTradeWarnInvoiceAmount =>
      'The invoice amount is not the amount the order asks for.';

  @override
  String get p2pTradeWarnExpired => 'This invoice has expired.';

  @override
  String get p2pTradeWarnExpiringSoon =>
      'This invoice expires in less than a minute.';

  @override
  String p2pTradeWarnHashChanged(String coordinator) {
    return '$coordinator sent a new invoice for the same step. Do not pay it.';
  }

  @override
  String p2pTradeWarnPayee(String coordinator) {
    return 'This invoice is not from $coordinator\'s known Lightning node. Do not pay it.';
  }

  @override
  String p2pActiveOrder(String orderId) {
    return 'Active order #$orderId';
  }

  @override
  String get p2pTradeEnded => 'This trade is over for this robot.';

  @override
  String get p2pSatsUnit => 'Sats';

  @override
  String get p2pTradeYouAreSwappingIn => 'SWAPPING INTO Lightning';

  @override
  String get p2pPayoutTabLightning => 'Lightning';

  @override
  String get p2pPayoutTabOnchain => 'Onchain';

  @override
  String get p2pPayoutAdvancedOptions => 'Advanced options';

  @override
  String get p2pPayoutRoutingBudget => 'Routing Budget';

  @override
  String get p2pPayoutBudgetTooHigh => 'Too high! (That is more than 1%)';

  @override
  String get p2pPayoutUnitPpm => 'PPM';

  @override
  String p2pPayoutSubmitInvoiceFor(String amountSats) {
    return 'Submit invoice for $amountSats Sats';
  }

  @override
  String get p2pPayoutCopyAmount => 'Copy the amount';

  @override
  String get p2pPayoutInvoiceField => 'Payout Lightning Invoice';

  @override
  String get p2pPayoutSubmit => 'Submit';

  @override
  String get p2pPayoutSubmitWhileCancelling =>
      'Submit is off while the trade is being cancelled.';

  @override
  String get p2pPayoutInvalidInvoiceAmount => 'Invalid invoice amount';

  @override
  String get p2pPayoutOnchainIntro =>
      'RoboSats coordinator will do a swap and send the Sats to your onchain address.';

  @override
  String get p2pPayoutSwapFee => 'Swap fee';

  @override
  String p2pPayoutSwapFeeValue(String sats, String percent) {
    return '$sats Sats ($percent%)';
  }

  @override
  String get p2pPayoutMiningFee => 'Mining fee';

  @override
  String p2pPayoutMiningFeeValue(String sats, String rate) {
    return '$sats Sats ($rate Sats/vByte)';
  }

  @override
  String get p2pPayoutFinalAmount => 'Final amount you will receive';

  @override
  String get p2pPayoutAddressField => 'Bitcoin Address';

  @override
  String get p2pPayoutMiningFeeField => 'Mining Fee';

  @override
  String get p2pPayoutInvalid => 'Invalid';

  @override
  String get p2pPayoutFailureReason => 'Failure reason:';

  @override
  String get p2pPayoutRetrying => 'Retrying!';

  @override
  String get p2pPayoutNextAttempt => 'Next attempt in';

  @override
  String p2pPayoutCountdown(String minutes, String seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String get p2pPayoutInvoiceExpiredSubmitNew =>
      'Your invoice has expired or more than 3 payment attempts have been made. Submit a new invoice.';

  @override
  String get p2pPayoutWillRetry =>
      'RoboSats will try to pay your invoice 3 times with a one minute pause in between. If it keeps failing, you will be able to submit a new invoice. Check whether you have enough inbound liquidity. Remember that lightning nodes must be online in order to receive payments.';

  @override
  String get p2pPayoutFailureNotYet => 'Payment isn\'t failed (yet)';

  @override
  String get p2pPayoutFailureTimeout =>
      'There are more routes to try, but the payment timeout was exceeded.';

  @override
  String get p2pPayoutFailureNoRoute =>
      'All possible routes were tried and failed permanently. Or there were no routes to the destination at all.';

  @override
  String get p2pPayoutFailureNonRecoverable =>
      'A non-recoverable error has occurred.';

  @override
  String get p2pPayoutFailureIncorrect =>
      'Payment details are incorrect (unknown hash, invalid amount or invalid final CLTV delta).';

  @override
  String get p2pPayoutFailureBalance =>
      'Insufficient unlocked balance in RoboSats\' node.';

  @override
  String p2pPayoutFailureUnknown(String coordinator) {
    return '$coordinator gave a reason this app does not know.';
  }

  @override
  String get p2pPayoutRefusedEmptyInvoice => 'You submitted an empty invoice';

  @override
  String get p2pPayoutRefusedNotInvoice =>
      'Does not look like a valid lightning invoice';

  @override
  String get p2pPayoutRefusedRouteHints =>
      'The invoice hinted private routes are not payable within the submitted routing budget. This can be adjusted with Advanced Options enabled.';

  @override
  String get p2pPayoutRefusedNoAmount =>
      'The invoice provided has no explicit amount';

  @override
  String p2pPayoutRefusedWrongAmount(String amount) {
    return 'The invoice provided is not for $amount Sats';
  }

  @override
  String get p2pPayoutRefusedExpired =>
      'The invoice provided has already expired';

  @override
  String get p2pPayoutRefusedNewInvoice => 'You must submit a NEW invoice';

  @override
  String get p2pPayoutRefusedNotNow =>
      'You can only submit an invoice after expiration or 3 failed attempts';

  @override
  String get p2pPayoutRefusedAddressNotNow =>
      'You cannot submit an address now.';

  @override
  String get p2pPayoutRefusedNotBuyer =>
      'Only the buyer of this order can provide a buyer invoice.';

  @override
  String get p2pPayoutRefusedSignature =>
      'The PGP signed cleartext message is not valid.';

  @override
  String get p2pPayoutRefusedNotParticipant =>
      'You are not a participant in this order';

  @override
  String get p2pPayoutRefusedEmptyAddress => 'You submitted an empty address';

  @override
  String p2pPayoutRefusedFeeTooLow(String rate) {
    return 'The mining fee is too low. Must be higher than $rate Sat/vbyte';
  }

  @override
  String get p2pPayoutRefusedFeeTooLowNoRate => 'The mining fee is too low.';

  @override
  String get p2pPayoutRefusedFeeTooHigh =>
      'The mining fee is too high, must be less than 500 Sats/vbyte';

  @override
  String get p2pPayoutRefusedDust =>
      'The amount remaining after subtracting mining fee is close to dust limit.';

  @override
  String get p2pPayoutRefusedInvalidAddress => 'Invalid address';

  @override
  String get p2pPayoutRefusedUnverifiable =>
      'Unable to validate address, check bitcoind backend';

  @override
  String p2pPayoutRefusedOther(String coordinator) {
    return '$coordinator refused your payout info.';
  }

  @override
  String p2pPayoutNotReached(String coordinator) {
    return 'Your payout info did not reach $coordinator: nothing was recorded. You can submit again.';
  }

  @override
  String get p2pPayoutNeedsARead =>
      'Wait until the order is read again to give your payout info.';

  @override
  String p2pPayoutNotAsked(String coordinator) {
    return '$coordinator does not ask for your payout info now.';
  }

  @override
  String p2pPayoutAmountUnknown(String coordinator) {
    return '$coordinator does not give the amount to receive yet.';
  }

  @override
  String get p2pPayoutInvoiceUnreadable =>
      'This is not a Lightning invoice this app can read.';

  @override
  String get p2pPayoutInvoiceOtherNetwork =>
      'This invoice is for another network than the trade\'s.';

  @override
  String get p2pPayoutInvoiceWholeSats =>
      'The invoice must ask for exactly the Sats shown, with no fraction of a sat.';

  @override
  String get p2pPayoutAddressMalformed => 'This is not a Bitcoin address.';

  @override
  String get p2pPayoutAddressBadChecksum =>
      'This address has a typo: its checksum is wrong.';

  @override
  String get p2pPayoutAddressOtherNetwork =>
      'This address is for another network than the trade\'s.';

  @override
  String p2pPayoutAddressUnsupported(String coordinator) {
    return '$coordinator may not be able to pay this kind of address.';
  }

  @override
  String p2pPayoutWarnExpiresFirst(
    String date,
    String time,
    String coordinator,
  ) {
    return 'This invoice expires on $date at $time. If the seller confirms after that, $coordinator cannot pay it and will ask you for a new one.';
  }

  @override
  String p2pPayoutWarnBelowMinimum(String coordinator) {
    return 'Less than 20,000 Sats would reach this address: $coordinator will refuse it.';
  }

  @override
  String get p2pPayoutOnchainSwapOrder =>
      'An order in bitcoin is paid on Lightning only.';

  @override
  String p2pPayoutSwapBelowMinimum(String coordinator) {
    return 'The amount is below the smallest swap $coordinator offers.';
  }

  @override
  String p2pPayoutSwapAboveMaximum(String coordinator) {
    return 'The amount is above the largest swap $coordinator offers.';
  }

  @override
  String p2pPayoutSwapDisabled(String coordinator) {
    return '$coordinator does not offer swaps.';
  }

  @override
  String p2pPayoutSwapNoLiquidity(String coordinator) {
    return '$coordinator does not have enough on-chain funds for a swap.';
  }

  @override
  String p2pPayoutSwapUnavailable(String coordinator) {
    return '$coordinator does not offer an on-chain payout for this order.';
  }

  @override
  String p2pPayoutStepUnlocking(String coordinator) {
    return 'Reading your robot from $coordinator and unlocking its key. The first time takes a few seconds.';
  }

  @override
  String p2pPayoutStepReading(String coordinator) {
    return 'Reading the order from $coordinator…';
  }

  @override
  String p2pPayoutStepSending(String coordinator) {
    return 'Sending your payout info to $coordinator…';
  }

  @override
  String p2pPayoutStepReadingAfter(String coordinator) {
    return 'Reading the order again from $coordinator…';
  }

  @override
  String get p2pPayoutStepWaitingForOrder =>
      'Waiting for another action on this order to end…';

  @override
  String get p2pPayoutStepOpening => 'Opening the trade…';

  @override
  String p2pPayoutGiven(String coordinator) {
    return '$coordinator received your payout info.';
  }

  @override
  String p2pPayoutUnknown(String coordinator) {
    return 'Bull Market does not know yet whether $coordinator received your payout info. It keeps checking while this screen is open.';
  }

  @override
  String p2pPayoutAskedAgain(String coordinator) {
    return '$coordinator still asks for your payout info: the last you gave was not recorded. You can submit again.';
  }

  @override
  String get p2pPayoutChanged =>
      'Nothing was sent: what is shown changed since you saw it. Check it again before you submit.';

  @override
  String get p2pPayoutChangedAmount =>
      'Nothing was sent: the amount changed since it was shown. Check it again before you submit.';

  @override
  String get p2pPayoutChangedExpiry =>
      'Nothing was sent: this invoice now expires before the step could end. Check it again before you submit.';

  @override
  String get p2pPayoutChangedStatus =>
      'Nothing was sent: the trade\'s status changed since it was shown. Check it again before you submit.';

  @override
  String p2pPayoutNotSentKey(String coordinator) {
    return 'The key of your robot could not be read from $coordinator. Nothing was sent.';
  }

  @override
  String p2pPayoutNotSentRead(String coordinator) {
    return 'Could not read the order from $coordinator. Nothing was sent.';
  }

  @override
  String get p2pPayoutNotSentSign =>
      'The key of your robot could not sign this. Nothing was sent.';

  @override
  String get p2pPayoutNotSentTrade =>
      'This trade cannot be opened now. Nothing was sent.';

  @override
  String p2pPayBalance(String balance) {
    return 'Instant payments: $balance sats available';
  }

  @override
  String get p2pPayWithThisWallet => 'Pay with this wallet';

  @override
  String get p2pPayQuoting => 'Getting the swap fees…';

  @override
  String p2pPayConfirmTitle(String amount) {
    return 'Pay $amount sats to lock your bond?';
  }

  @override
  String p2pPayServiceFee(String serviceFee) {
    return 'Swap fees: $serviceFee sats';
  }

  @override
  String p2pPayNetworkFee(String networkFee) {
    return 'Network fee: about $networkFee sats';
  }

  @override
  String p2pPayTotal(String total, String left) {
    return 'Total: $total sats. Left in Instant payments: $left sats.';
  }

  @override
  String p2pPayConfirm(String total) {
    return 'Pay $total sats';
  }

  @override
  String get p2pPaySending => 'Sending the payment…';

  @override
  String p2pPaySent(String coordinator) {
    return 'Payment sent. Waiting for $coordinator to see your bond locked.';
  }

  @override
  String get p2pPayRefundPending =>
      'Swap will be refunded shortly. The swap fees are not refunded.';

  @override
  String get p2pPayRefunded =>
      'Swap has been refunded. The swap fees are not refunded.';

  @override
  String p2pPaySettled(String coordinator) {
    return 'Your bond was kept by $coordinator.';
  }

  @override
  String get p2pPayUnderReview =>
      'Swap is under review. Contact Bull Bitcoin support if it lasts.';

  @override
  String get p2pPayInterrupted =>
      'The payment was interrupted before it was sent. Nothing left this wallet yet.';

  @override
  String get p2pPayMaybeSent =>
      'The payment may have been sent. Its status will update shortly.';

  @override
  String get p2pPayAskSupport =>
      'Swap failed. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.';

  @override
  String p2pPayUnderMinimum(String min) {
    return 'Amount below minimum swap limit: $min sats';
  }

  @override
  String get p2pPayUnderMinimumUnknown => 'Amount is below swap limits';

  @override
  String p2pPayOverMaximum(String max) {
    return 'Amount above maximum swap limit: $max sats';
  }

  @override
  String get p2pPayOutsideLimits => 'Amount is outside swap limits';

  @override
  String p2pPayNotEnough(String balance, String total) {
    return 'Not enough in Instant payments ($balance sats) for $total sats.';
  }

  @override
  String get p2pPayUnreachable =>
      'Swap server is unavailable. Please try again later.';

  @override
  String get p2pPayBusy => 'Too many requests. Please try again later.';

  @override
  String get p2pPayTooLate =>
      'Too little time is left to pay from this wallet.';

  @override
  String get p2pPayFeesChanged =>
      'The fees changed since you confirmed. Check them again.';

  @override
  String get p2pPayAlreadyPaid => 'This wallet already paid this invoice.';

  @override
  String get p2pPayOrderMoved =>
      'The order moved on before the payment. Nothing was paid.';

  @override
  String get p2pPayNotRecorded =>
      'Bull Market could not write its records on this device. Nothing was paid.';

  @override
  String get p2pPayWalletUnavailable => 'This wallet cannot pay this bond now.';

  @override
  String get p2pPayServiceCouldNotPay =>
      'Swap failed. Swap will be refunded shortly. The swap fees are not refunded.';

  @override
  String get p2pPayWithSwapService => 'Your swap is in progress.';

  @override
  String p2pPayCoordinatorUnreachable(String coordinator) {
    return 'Could not reach $coordinator. Nothing was paid.';
  }

  @override
  String p2pPayReadSuperseded(String coordinator) {
    return 'Could not read the order from $coordinator just now. Nothing was paid.';
  }

  @override
  String get p2pPayStillSending =>
      'Still sending. This can take a few minutes.';

  @override
  String get p2pPayAskSupportSent =>
      'Swap failed. The sats of this bond left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayUnreadable =>
      'Bull Market cannot read where this payment stands.';

  @override
  String get p2pPayCancelNote =>
      'A payment of this bond is on its way from this wallet. Cancelling now costs the swap fees, and the refund may take time.';

  @override
  String get p2pPayServiceRefunded =>
      'Swap failed. Swap has been refunded. The swap fees are not refunded.';

  @override
  String get p2pPayAskSupportExpired =>
      'Swap expired. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayAskSupportExpiredSent =>
      'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pEndChatBuyerHi =>
      'Say hi! Ask for payment details and click \'Confirm Sent\' as soon as the payment is sent.';

  @override
  String get p2pEndBewareScams => '⚠️ Beware scams';

  @override
  String p2pEndConfirmSent(String amount, String currencyCode) {
    return 'Confirm $amount $currencyCode sent';
  }

  @override
  String p2pEndConfirmSentTitle(String amount, String currencyCode) {
    return '✅ Confirm you sent $amount $currencyCode?';
  }

  @override
  String get p2pEndConfirmSentText =>
      'Confirming will allow your peer to finalize the trade.';

  @override
  String get p2pEndCannotBeUndone => '⚠️ This action cannot be undone!';

  @override
  String get p2pEndFalseConfirmRisk =>
      'If you have not yet sent it and you still proceed to falsely confirm, you risk losing your bond.';

  @override
  String get p2pEndConfirm => 'Confirm';

  @override
  String get p2pEndWaitSeller =>
      'Wait for the seller to confirm they have received the payment.';

  @override
  String p2pEndStepSending(String coordinator) {
    return 'Sending your confirmation to $coordinator…';
  }

  @override
  String get p2pEndNeedsRead => 'Wait until the order is read again.';

  @override
  String get p2pEndMovedOn =>
      'The order moved on: your confirmation was not sent.';

  @override
  String p2pEndReadFailed(String coordinator) {
    return 'The order could not be read again from $coordinator: your confirmation was not sent.';
  }

  @override
  String p2pEndNotDoneAfter(String reason) {
    return '$reason Your confirmation was not sent.';
  }

  @override
  String get p2pEndUnknown =>
      'Bull Market does not know yet whether your confirmation went through. It keeps checking.';

  @override
  String get p2pEndSendingSats =>
      'RoboSats is trying to pay your lightning invoice. Remember that lightning nodes must be online in order to receive payments.';

  @override
  String get p2pEndTakingTooLong => 'Taking too long?';

  @override
  String get p2pEndTakingTooLongText =>
      'Lightning payments are usually instantaneous, but sometimes a node in the route may be down, which can cause your payout to take up to 24 hours to arrive in your wallet.';

  @override
  String get p2pEndNeedsReadNotSent =>
      'Wait until the order is read again. Your confirmation was not sent.';

  @override
  String p2pEndRefusedBy(String coordinator) {
    return '$coordinator did not record your confirmation.';
  }

  @override
  String p2pEndNotRecordedMovedOn(String coordinator) {
    return 'The order moved on: $coordinator did not record your confirmation.';
  }

  @override
  String p2pEndAmountDiffers(
    String coordinator,
    String readAmount,
    String readCurrency,
    String amount,
    String currencyCode,
  ) {
    return '$coordinator now gives $readAmount $readCurrency; the order was taken for $amount $currencyCode.';
  }

  @override
  String p2pEndAmountMissing(
    String coordinator,
    String amount,
    String currencyCode,
  ) {
    return '$coordinator gives no amount for this order; it was taken for $amount $currencyCode.';
  }

  @override
  String p2pEndOffline(String coordinator) {
    return '$coordinator is offline: your confirmation was not sent.';
  }

  @override
  String get p2pPayoutWalletGenerateInvoice => 'Generate Invoice';

  @override
  String get p2pPayoutWalletGenerateAddress => 'Generate New Address';

  @override
  String get p2pPayoutWalletMakingInvoice => 'Generating the invoice…';

  @override
  String get p2pPayoutWalletMakingAddress => 'Generating a new address…';

  @override
  String get p2pPayoutWalletStillWaiting => 'Still waiting for the wallet.';

  @override
  String p2pPayoutWalletReceived(String amount) {
    return 'Receive Amount: $amount sats';
  }

  @override
  String get p2pPayoutWalletFeeTaken =>
      'This fee will be deducted from the amount sent';

  @override
  String get p2pPayoutWalletNoInvoice =>
      'This wallet cannot create an invoice now.';

  @override
  String get p2pPayoutWalletNoAddress =>
      'This wallet cannot give an address now.';

  @override
  String get p2pPayoutWalletAnotherWaiting =>
      'This wallet is already waiting for a payment of this amount. Try again in a few minutes, or paste an invoice from another wallet.';
}
