// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class P2pLocalizationsEn extends P2pLocalizations {
  P2pLocalizationsEn([String locale = 'en']) : super(locale);

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
    return '$coordinator will know this robot from now on. In Troc a robot lives on one coordinator only: this robot will never be sent to another one. To trade elsewhere, use another robot.';
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
    return '$coordinator sent an answer Troc cannot read.';
  }

  @override
  String p2pRobotCoordinatorChanged(String coordinator) {
    return '$coordinator changed its address or keys since this robot was sent to it. Nothing was sent. Until an update of the app has checked the change, use another robot.';
  }

  @override
  String get p2pRobotStorage =>
      'Troc could not read its records on this device. Nothing was sent.';

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
      'Troc could not read its records on this device.';

  @override
  String get p2pRobotHistoryTitle => 'Robots from elsewhere';

  @override
  String get p2pRobotHistoryBody =>
      'This Garage Key was pasted in, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Troc a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, generate a new Garage Key.';

  @override
  String get p2pRobotHistoryConfirm => 'I understand';
}
