// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class P2pLocalizationsFa extends P2pLocalizations {
  P2pLocalizationsFa([String locale = 'fa']) : super(locale);

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
  String get p2pGarageKeyInvalid => 'Invalid garage key';

  @override
  String get p2pGarageTradingAvatar => 'This is your trading avatar';

  @override
  String get p2pGaragePreviousAccount => 'Previous account';

  @override
  String get p2pGarageNextAccount => 'Next account';

  @override
  String get p2pGarageRobotLabel => 'Robot';

  @override
  String get p2pGarageKeyLabel => 'Garage Key';

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
  String p2pSignatureClockSkew(String coordinator) {
    return 'The time of this device is too far from $coordinator\'s. Turn on automatic time and try again.';
  }

  @override
  String p2pSignatureNewerVersion(String coordinator) {
    return '$coordinator asks for a newer version of Bull Market.';
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
      'This Garage Key was imported, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Bull Market, a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, go back to the internal Garage Keys.';

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
  String p2pTakeYouWillSend(String satoshis) {
    return 'You will send $satoshis Sats (Approx)';
  }

  @override
  String get p2pTakeSpecifyAmountFirst => 'You must specify an amount first';

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
  String p2pTakeFreshRobot(String nickname) {
    return 'A fresh robot for this order: $nickname.';
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
  String p2pTradeTitleLockBondPublish(String amountSats) {
    return 'Lock $amountSats Sats to PUBLISH order';
  }

  @override
  String p2pTradeTitleLockEscrow(String amountSats) {
    return 'Lock $amountSats Sats as collateral';
  }

  @override
  String p2pTradeEscrowTimeWarning(String hours, String minutes) {
    return 'You risk losing your bond if you do not lock the collateral. Total time available is ${hours}h ${minutes}m.';
  }

  @override
  String get p2pTradeYouAreBuying => 'You are BUYING BTC';

  @override
  String get p2pTradeYouAreSelling => 'You are SELLING BTC';

  @override
  String get p2pTradeCompatibleWallets => 'See Compatible Wallets';

  @override
  String get p2pTradeCopyToClipboard => 'Copy to clipboard';

  @override
  String get p2pTradeHoldInvoiceBond =>
      'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.';

  @override
  String p2pTradeHoldInvoiceEscrow(String currencyCode) {
    return 'This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the $currencyCode.';
  }

  @override
  String get p2pTradeInvoiceQr => 'QR code of the bond invoice';

  @override
  String get p2pTradeEscrowQr => 'QR code of the escrow invoice';

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
  String get p2pTradePayoutPromptNoAmount =>
      'Before letting you send the fiat, we want to make sure you are able to receive the BTC.';

  @override
  String get p2pTradeTitleInfoGood => 'Your info looks good!';

  @override
  String get p2pTradeTitleCollateralLocked => 'The trade collateral is locked!';

  @override
  String get p2pTradeEscrowWait =>
      'We are waiting for the seller to lock the trade amount.';

  @override
  String get p2pTradeEscrowWaitHangOn =>
      'Just hang on for a moment. If the seller does not deposit, you will get your bond back automatically. In addition, you will receive a compensation (check the rewards in your profile).';

  @override
  String get p2pTradePayoutWait =>
      'We are waiting for the buyer to post a lightning invoice. Once he does, you will be able to directly communicate the payment details.';

  @override
  String get p2pTradePayoutWaitHangOn =>
      'Just hang on for a moment. If the buyer does not cooperate, you will get back the trade collateral and your bond automatically. In addition, you will receive a compensation (check the rewards in your profile).';

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
  String get p2pTradeTitleChatWithBuyer => 'Chat with the buyer';

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
      'At this step only a collaborative cancel exists, which RoboSats offers from the chat.';

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
  String get p2pTradeYouAreSwappingOut => 'SWAPPING OUT of Lightning';

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
    return 'Submit invoice for $amountSats sats';
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
  String get p2pPayRowCollateral => 'Collateral';

  @override
  String get p2pPayRowBond => 'Bond';

  @override
  String get p2pPayRowFees => 'Swap and network fees';

  @override
  String p2pPayAmountSats(String amount) {
    return '$amount sats';
  }

  @override
  String get p2pPayRowSwapFees => 'Swap fees';

  @override
  String get p2pPayRowNetworkFee => 'Network fee (estimate)';

  @override
  String get p2pPayRowTotal => 'Total to pay';

  @override
  String get p2pPayRowLeft => 'Balance after payment';

  @override
  String get p2pPayEscrowHeld =>
      'Until the trade ends, these sats are with the swap service, not in this wallet. If the trade is cancelled, they come back to Instant payments, less the swap and network fees, sometimes with a delay.';

  @override
  String p2pPayRateWallet(
    String price,
    String currency,
    String expected,
    String gap,
  ) {
    return 'At the Bull wallet\'s price, $price $currency/BTC, with the order\'s premium, this bond is worth $expected sats. Gap of the invoice: $gap.';
  }

  @override
  String p2pPayRateWalletEscrow(
    String price,
    String currency,
    String amount,
    String expected,
    String gap,
  ) {
    return 'At the Bull wallet\'s price, $price $currency/BTC, with the order\'s premium, $amount $currency are worth $expected sats. Gap of the collateral: $gap, the coordinator\'s fee included.';
  }

  @override
  String p2pPayRateDetail(
    String amount,
    String currency,
    String price,
    String expected,
    String gap,
  ) {
    return 'Bull Wallet redoes the calculation with its own price: $amount $currency at $price $currency/BTC, premium included, come to $expected sats. The coordinator asks $gap more, its fees included.';
  }

  @override
  String p2pPayAgainstFigures(String expected, String asked) {
    return 'Bull Wallet expected $expected sats, the coordinator asks $asked.';
  }

  @override
  String p2pPayAgainstDetail(String price, String currency, String threshold) {
    return 'Bull Wallet redoes the calculation with its own price ($price $currency/BTC, premium included) and warns you beyond a $threshold gap. Check the order before paying.';
  }

  @override
  String get p2pPayUnverifiedDetail =>
      'Without this price, it cannot compare the coordinator\'s amount. You can try again, or pay without this check.';

  @override
  String get p2pPayEarlierNotBack => 'A previous collateral has not come back';

  @override
  String p2pPayEarlierOutTotal(String total) {
    return 'With this one, $total sats will be out of this wallet.';
  }

  @override
  String p2pPayEarlierNotBackDetail(String sats) {
    return 'You already paid, or tried to pay, a collateral of $sats sats for this order with this wallet. It has not come back to it yet.';
  }

  @override
  String get p2pPayNewContractTitle => 'New contract';

  @override
  String get p2pPayNewContractLine =>
      'The previous take of this order did not go through. This collateral is for the new contract.';

  @override
  String get p2pPayConfirmAgainTitle => 'The amounts have changed';

  @override
  String get p2pPayConfirmAgainLine => 'Check them, then confirm again.';

  @override
  String get p2pPayConfirmStaleTitle => 'The order was taken again meanwhile';

  @override
  String get p2pPayConfirmStaleLine =>
      'This confirmation is no longer valid. Go back.';

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
  String p2pPayEscrowSent(String coordinator) {
    return 'Payment sent. Waiting for $coordinator to see the collateral locked.';
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
  String p2pPayEscrowSettled(String coordinator) {
    return '$coordinator received the collateral.';
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
  String get p2pPayEscrowAskSupport =>
      'Swap failed. The sats of this collateral may have left this wallet. Contact Bull Bitcoin support.';

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
  String get p2pPayEscrowShownBefore =>
      'This collateral invoice was already presented to this device, for this order or another one. It is not paid from this wallet.';

  @override
  String get p2pPayConfirmAgain =>
      'Since you confirmed, what will leave this wallet, or the state of an earlier collateral, changed. Nothing was paid: check the figures below and confirm again.';

  @override
  String get p2pPayContractMoved =>
      'The order was taken again before the payment: the confirmation was for the earlier take. Nothing was paid.';

  @override
  String p2pEscrowEarlierOut(String sats, String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count earlier collaterals of this order, paid or attempted with this wallet, have not come back yet',
      one:
          'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet',
    );
    return '$_temp0: $sats sats. With this one, $total sats will be out of this wallet for the collaterals of this order, bond not included.';
  }

  @override
  String p2pEscrowEarlierOutUnknown(
    String sats,
    String total,
    int count,
    int known,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      known,
      locale: localeName,
      other:
          '$known earlier collaterals of this order, paid or attempted with this wallet, have not come back yet: $sats sats',
      one:
          'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet: $sats sats',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more whose amounts this device no longer knows',
      one: '1 more whose amount this device no longer knows',
    );
    return '$_temp0, and $_temp1. With this one, at least $total sats will be out of this wallet for the collaterals of this order, bond not included.';
  }

  @override
  String p2pEscrowEarlierOutAllUnknown(String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count earlier collaterals of this order, paid or attempted with this wallet, have not come back yet; this device no longer knows their amounts.',
      one:
          'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet; this device no longer knows its amount.',
    );
    return '$_temp0 With this one, at least $total sats will be out of this wallet for the collaterals of this order, bond not included.';
  }

  @override
  String p2pEscrowEarlierKept(String sats, String coordinator) {
    return 'The collateral of an earlier take ($sats sats) was kept by $coordinator: check this order in the official RoboSats app before paying another one.';
  }

  @override
  String p2pEscrowEarlierKeptUnknown(String coordinator) {
    return 'The collateral of an earlier take was kept by $coordinator: check this order in the official RoboSats app before paying another one.';
  }

  @override
  String get p2pPayEscrowBondHeldToo =>
      'Your order\'s bond was paid with this wallet: it is out of this wallet too until the order ends, and is not in this total.';

  @override
  String get p2pPayEscrowBondMaybeHeldToo =>
      'If your order\'s bond was paid with this wallet, it is out of this wallet too until the order ends, and is not in this total.';

  @override
  String get p2pEscrowsEarlierTitle =>
      'Collaterals of earlier takes of this order, paid or attempted with this wallet:';

  @override
  String p2pEscrowsEarlierLine(String take, String state) {
    return 'Take $take: $state';
  }

  @override
  String get p2pEscrowStateRefunded =>
      'back, refunded to this wallet without the swap fees and the network fee';

  @override
  String get p2pEscrowStateNothingSent => 'back, nothing left this wallet';

  @override
  String get p2pEscrowStateRefundPending =>
      'not back yet, the swap service is refunding it';

  @override
  String get p2pEscrowStatePreparing =>
      'not back yet, its swap was being prepared and may never have been sent';

  @override
  String get p2pEscrowStateMaybeSent =>
      'not back yet, the payment may have been sent';

  @override
  String get p2pEscrowStateWithService => 'not back yet, with the swap service';

  @override
  String get p2pEscrowStateUnderReview =>
      'not back yet, under review at the swap service; contact Bull Bitcoin support if it lasts';

  @override
  String get p2pEscrowStateAskSupport =>
      'not back yet, the swap failed and its sats may have left this wallet; contact Bull Bitcoin support';

  @override
  String get p2pEscrowStateUnknown =>
      'state unknown, this device cannot tell where it stands';

  @override
  String p2pEscrowStateHeld(String coordinator) {
    return 'not back yet, paid by the swap service and held by $coordinator';
  }

  @override
  String p2pEscrowStateKept(String coordinator) {
    return 'kept by $coordinator';
  }

  @override
  String p2pEscrowRefundUndoneHeld(String take, String coordinator) {
    return 'The collateral of take $take was being refunded, and is now held by $coordinator again: check this order in the official RoboSats app.';
  }

  @override
  String p2pEscrowRefundUndoneKept(String take, String coordinator) {
    return 'The collateral of take $take was being refunded, and was then kept by $coordinator: check this order in the official RoboSats app.';
  }

  @override
  String get p2pPayEscrowWalletUnavailable =>
      'This wallet cannot pay this collateral now.';

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
  String get p2pPayEscrowAskSupportSent =>
      'Swap failed. The sats of this collateral left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayUnreadable =>
      'Bull Market cannot read where this payment stands.';

  @override
  String get p2pPayCancelNote =>
      'A payment of this bond is on its way from this wallet. Cancelling now costs the swap fees, and the refund may take time.';

  @override
  String get p2pPayEscrowCancelNote =>
      'A payment of this collateral is on its way from this wallet. Cancelling does not stop it: if it reaches the coordinator, the coordinator returns it, then the swap service refunds it to Instant payments without the swap fees and the network fee. The refund may take time.';

  @override
  String p2pPayLineBond(String line) {
    return 'Bond: $line';
  }

  @override
  String p2pPayLineEscrow(String line) {
    return 'Collateral: $line';
  }

  @override
  String get p2pPayServiceRefunded =>
      'Swap failed. Swap has been refunded. The swap fees are not refunded.';

  @override
  String get p2pPayAskSupportExpired =>
      'Swap expired. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayEscrowAskSupportExpired =>
      'Swap expired. The sats of this collateral may have left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayAskSupportExpiredSent =>
      'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pPayEscrowAskSupportExpiredSent =>
      'Swap expired. The sats of this collateral left this wallet. Contact Bull Bitcoin support.';

  @override
  String get p2pEndChatBuyerHi =>
      'Say hi! Ask for payment details and click \'Confirm Sent\' as soon as the payment is sent.';

  @override
  String p2pEndChatSellerHi(String amount, String currencyCode) {
    return 'Say hi! Be helpful and concise. Let them know how to send you $amount $currencyCode.';
  }

  @override
  String get p2pEndBewareScams => '⚠️ Beware scams';

  @override
  String p2pEndConfirmSent(String amount, String currencyCode) {
    return 'Confirm $amount $currencyCode sent';
  }

  @override
  String p2pEndConfirmReceived(String amount, String currencyCode) {
    return 'Confirm $amount $currencyCode received';
  }

  @override
  String p2pEndConfirmSentTitle(String amount, String currencyCode) {
    return '✅ Confirm you sent $amount $currencyCode?';
  }

  @override
  String p2pEndConfirmReceivedTitle(String amount, String currencyCode) {
    return '✅ Confirm you received $amount $currencyCode?';
  }

  @override
  String get p2pEndConfirmSentText =>
      'Confirming will allow your peer to finalize the trade.';

  @override
  String get p2pEndConfirmReceivedText => 'Confirming will finalize the trade.';

  @override
  String get p2pEndEscrowReleased =>
      'The satoshis in the escrow will be released to the buyer:';

  @override
  String p2pEndOnlyConfirmAfter(String amount, String currencyCode) {
    return 'Only confirm after $amount $currencyCode have arrived to your account.';
  }

  @override
  String get p2pEndNotConfirmingRisk =>
      'If you have received the payment and do not click confirm, you risk losing your bond.';

  @override
  String get p2pEndFiatReversal =>
      'Some fiat payment methods might reverse their transactions up to 80 days after they are completed. Please keep this token and your order data in case you need to use them as proof.';

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
  String get p2pEndBuyerSentFiat =>
      'The buyer has sent the fiat. Click \'Confirm Received\' once you receive it.';

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
  String get p2pEndUnknownReceived =>
      'Bull Market does not know yet whether your confirmation went through. It keeps reading the order; if the trade does not finish, confirm again: a second confirmation cannot release more than the one escrow.';

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
  String get p2pEndPaymentFailed => 'Payment failed?';

  @override
  String get p2pEndUndoTitle => 'Revert the confirmation of fiat sent?';

  @override
  String get p2pEndUndoText =>
      'READ. In case your payment to the seller has been blocked and it is absolutely impossible to finish the trade, you can revert your confirmation of \"Fiat sent\". Do so only if you and the seller have ALREADY AGREED in the chat to proceed to a collaborative cancellation. After confirming, the \"Collaborative cancel\" button will be visible again. Only click this button if you know what you are doing. First time users of RoboSats are highly discouraged from performing this action! Make 100% sure your payment has failed and the amount is in your account.';

  @override
  String p2pEndWaitCountdown(String time) {
    return 'Wait ($time)';
  }

  @override
  String get p2pEndCollabTitle => 'Collaborative cancel the order?';

  @override
  String get p2pEndCollabText =>
      'The trade escrow has been posted. The order can be cancelled only if both, maker and taker, agree to cancel.';

  @override
  String get p2pEndCollabPeerAsked => 'Your peer has asked for cancellation';

  @override
  String get p2pEndCollabAccept => 'Accept Cancelation';

  @override
  String get p2pEndCollabAsk => 'Ask for Cancel';

  @override
  String p2pEndCollabPeerAlert(String nickname) {
    return '$nickname is asking for a collaborative cancel';
  }

  @override
  String get p2pEndCollabAskedAlert =>
      'You asked for a collaborative cancellation';

  @override
  String get p2pEndOrderOptions => 'Order options';

  @override
  String get p2pEndCollabCancel => 'Collaborative Cancel';

  @override
  String get p2pEndCollabAfterFiat =>
      'Orders can\'t be cancelled if fiat has been sent.';

  @override
  String p2pEndStepSendingRequest(String coordinator) {
    return 'Sending your request to $coordinator…';
  }

  @override
  String get p2pEndNotSentReadRefused =>
      'Nothing was sent: the order read just now carries the alert shown above.';

  @override
  String get p2pEndNotSent => 'Nothing was sent.';

  @override
  String get p2pEndTradeMovedOn =>
      'The trade moved on: your request was not sent.';

  @override
  String get p2pEndUnknownRequest =>
      'Bull Market does not know yet whether your request went through. It keeps checking.';

  @override
  String p2pEndRequestNotRecordedMovedOn(String coordinator) {
    return 'The trade moved on: $coordinator did not record your request.';
  }

  @override
  String p2pEndRequestRefusedBy(String coordinator) {
    return '$coordinator did not record your request.';
  }

  @override
  String p2pEndRequestNotDoneAfter(String reason) {
    return '$reason Your request was not sent.';
  }

  @override
  String p2pEndOffline(String coordinator) {
    return '$coordinator is offline: your confirmation was not sent.';
  }

  @override
  String p2pEndRequestOffline(String coordinator) {
    return '$coordinator is offline: your request was not sent.';
  }

  @override
  String get p2pEndOpenOptions => 'open options';

  @override
  String p2pEndWaitSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Wait $seconds seconds',
      one: 'Wait 1 second',
    );
    return '$_temp0';
  }

  @override
  String p2pChatYouState(String state) {
    return 'You: $state';
  }

  @override
  String p2pChatPeerState(String state) {
    return 'Peer: $state';
  }

  @override
  String get p2pChatConnected => 'connected';

  @override
  String get p2pChatDisconnected => 'disconnected';

  @override
  String get p2pChatWaitingShort => '...waiting';

  @override
  String get p2pChatTypeMessage => 'Type a message';

  @override
  String get p2pChatWaitingForPeer => 'Waiting for peer...';

  @override
  String get p2pChatSend => 'Send';

  @override
  String p2pChatSignatureVerified(String nickname) {
    return 'Verified signature by $nickname';
  }

  @override
  String p2pChatSignatureUnverified(String nickname) {
    return 'Cannot verify signature of $nickname';
  }

  @override
  String get p2pChatTokenBlocked =>
      'Aye! You just sent your own robot token to your peer in chat, that\'s a catastrophic idea! So bad your message was blocked.';

  @override
  String get p2pChatGarageKeyBlocked =>
      'This message holds your Garage Key, which controls all your robots. It will not be sent.';

  @override
  String get p2pChatTooLong =>
      'This message is too long. Shorten it to send it.';

  @override
  String get p2pChatClosed => 'Messages are not sent at this step.';

  @override
  String get p2pChatKeyChanged =>
      'This chat is no longer secure: your peer’s key changed. Nothing more is sent here. Do not trust payment details received from now on.';

  @override
  String p2pChatSending(String coordinator) {
    return 'Sending the message to $coordinator…';
  }

  @override
  String p2pChatNotConfirmed(String coordinator) {
    return 'Not confirmed by $coordinator. It may still reach your peer.';
  }

  @override
  String get p2pChatSendAgain => 'Send again';

  @override
  String get p2pChatSendFailed => 'The message was not sent. Try again.';

  @override
  String p2pChatSendRefused(String coordinator) {
    return '$coordinator did not take the message. Try again.';
  }

  @override
  String get p2pChatTradeMoved =>
      'The message was not sent: the trade has moved on.';

  @override
  String p2pChatReadFailed(String coordinator) {
    return 'Cannot read the chat from $coordinator. Trying again…';
  }

  @override
  String get p2pChatUnavailable => 'The chat cannot be read on this device.';

  @override
  String get p2pChatHistoryTooLarge =>
      'This chat is too long to be read from its first message.';

  @override
  String get p2pChatReadNewer => 'Read only the newer messages';

  @override
  String p2pChatReading(String coordinator) {
    return 'Reading the chat from $coordinator…';
  }

  @override
  String get p2pChatSkipAwaited => 'Reading the newer messages…';

  @override
  String get p2pChatEarlierHidden => 'Earlier messages are not shown.';

  @override
  String get p2pChatScreenPrivacyUnavailable =>
      'Screen protection could not be turned on, so the chat stays hidden.';

  @override
  String get p2pChatUnreadable => 'This message cannot be read.';

  @override
  String get p2pChatMarkAfterGap => 'A message may be missing before this one.';

  @override
  String get p2pChatMarkRepeat => 'This message was already shown above.';

  @override
  String get p2pChatMarkSentTwice => 'You sent this message twice.';

  @override
  String get p2pChatMarkOutOfOrder =>
      'This message may be older than it looks.';

  @override
  String get p2pChatAuditChat => 'Audit Chat';

  @override
  String get p2pChatExport => 'Export';

  @override
  String get p2pChatExportCopyFailed => 'The chat log could not be copied.';

  @override
  String get p2pChatAuditTitle => 'Don\'t trust, verify';

  @override
  String get p2pChatAuditText =>
      'Your communication is end-to-end encrypted with OpenPGP. You can verify the privacy of this chat using any tool based on the OpenPGP standard.';

  @override
  String get p2pChatYourPublicKey => 'Your public key';

  @override
  String get p2pChatYourPublicKeyTooltip =>
      'Your PGP public key. Your peer uses it to encrypt messages only you can read.';

  @override
  String get p2pChatPeerPublicKey => 'Peer public key';

  @override
  String get p2pChatPeerPublicKeyTooltip =>
      'Your peer PGP public key. You use it to encrypt messages only he can read and to verify your peer signed the incoming messages.';

  @override
  String get p2pChatYourEncryptedPrivateKey => 'Your encrypted private key';

  @override
  String get p2pChatYourEncryptedPrivateKeyTooltip =>
      'Your encrypted private key. You use it to decrypt the messages that your peer encrypted for you. You also use it to sign the messages you send.';

  @override
  String get p2pChatPassphrase => 'Your private key passphrase (keep secure!)';

  @override
  String get p2pChatPassphraseTooltip =>
      'The passphrase to decrypt your private key. Only you know it! Do not share. It is also your robot token.';

  @override
  String p2pChatAuditKeyFailed(String coordinator) {
    return 'The key of your robot could not be read from $coordinator.';
  }

  @override
  String p2pChatFingerprint(String fingerprint) {
    return 'Fingerprint: $fingerprint';
  }

  @override
  String get p2pChatSaveKeys => 'Keys';

  @override
  String get p2pChatSaveKeysTooltip => 'Save credentials as a JSON file';

  @override
  String get p2pChatSaveMessages => 'Messages';

  @override
  String get p2pChatSaveMessagesTooltip => 'Save messages as a JSON file';

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
  String get p2pPayoutWalletNoInvoice =>
      'This wallet cannot create an invoice now.';

  @override
  String get p2pPayoutWalletNoAddress =>
      'This wallet cannot give an address now.';

  @override
  String get p2pPayoutWalletAnotherWaiting =>
      'This wallet is already waiting for a payment of this amount. Paste an invoice from another wallet, or try again later.';

  @override
  String get p2pPayoutWalletEarlierStillOpen =>
      'This wallet\'s earlier invoice for this trade is still open, and the coordinator takes only a new one. Paste an invoice from another wallet, or try again once it has expired.';

  @override
  String get p2pEndOpenDispute => 'Open Dispute';

  @override
  String p2pEndDisputeWait(String hours, String minutes) {
    return 'To open a dispute you need to wait ${hours}h ${minutes}m';
  }

  @override
  String get p2pEndDisputeTitle => 'Do you want to open a dispute?';

  @override
  String get p2pEndDisputeText =>
      'The RoboSats staff will examine the statements and evidence provided. You need to build a complete case, as the staff cannot read the chat. It is best to provide a burner contact method with your statement. The satoshis in the trade escrow will be sent to the dispute winner, while the dispute loser will lose the bond.';

  @override
  String get p2pEndDisputeExport =>
      'Make sure to EXPORT the chat log. The staff might request your exported chat log JSON in order to solve discrepancies. It is your responsibility to store it.';

  @override
  String get p2pEndDisagree => 'Disagree';

  @override
  String get p2pEndAgreeDispute => 'Agree and open dispute';

  @override
  String p2pEndStepSendingDispute(String coordinator) {
    return 'Opening the dispute at $coordinator…';
  }

  @override
  String get p2pEndDisputeWaitPeer =>
      'We are waiting for your trade counterpart statement. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods.';

  @override
  String get p2pEndDisputeSaveInfoPeer =>
      'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself using that information if you contact your trade coordinator.';

  @override
  String get p2pEndDisputeWaitResolution =>
      'Both statements have been received, wait for the staff to resolve the dispute. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods. If you did not provide a contact method, or are unsure whether you wrote it right, write your coordinator immediately.';

  @override
  String get p2pEndDisputeSaveInfoResolution =>
      'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself as the user involved in this trade via email (or other contact methods).';

  @override
  String p2pEndDisputeWinner(String email) {
    return 'You can claim the dispute resolution amount (escrow and fidelity bond) from your profile rewards. If there is anything the staff can help with, do not hesitate to contact to $email (or via your provided burner contact method).';
  }

  @override
  String p2pEndDisputeLoser(String email) {
    return 'Unfortunately you have lost the dispute. If you think this is a mistake you can ask to re-open the case by contacting your coordinator. If you think your coordinator was unfair, please fill a claim via email to $email';
  }

  @override
  String p2pEndStatementLater(String coordinator) {
    return 'Bull Market cannot send a dispute statement yet. Contact $coordinator through one of its contacts below, with the information to identify your order.';
  }

  @override
  String p2pEndRewardsLater(String coordinator) {
    return 'Bull Market cannot claim rewards yet: contact $coordinator through one of its contacts below.';
  }

  @override
  String p2pEndStatementLaterNoContacts(String coordinator) {
    return 'Bull Market cannot send a dispute statement yet. Contact $coordinator with the information to identify your order.';
  }

  @override
  String p2pEndRewardsLaterNoContacts(String coordinator) {
    return 'Bull Market cannot claim rewards yet: contact $coordinator.';
  }

  @override
  String p2pEndOrderId(String id) {
    return 'Order ID: $id';
  }

  @override
  String get p2pEndDisputeTooEarly =>
      'Cannot open a dispute yet. You need to wait until 18 hours before expiry.';

  @override
  String get p2pEndDisputeNeedsRead =>
      'Wait until the order is read again. The dispute was not opened.';

  @override
  String p2pEndDisputeReadFailed(String coordinator) {
    return 'The order could not be read again from $coordinator: the dispute was not opened.';
  }

  @override
  String get p2pEndDisputeMovedOn =>
      'The trade moved on: the dispute was not opened.';

  @override
  String p2pEndDisputeNotSentAfter(String reason) {
    return '$reason The dispute was not opened.';
  }

  @override
  String p2pEndDisputeNotRecordedMovedOn(String coordinator) {
    return 'The trade moved on: $coordinator did not open the dispute.';
  }

  @override
  String p2pEndDisputeOffline(String coordinator) {
    return '$coordinator is offline: the dispute was not opened.';
  }

  @override
  String p2pEndDisputeRefusedBy(String coordinator) {
    return '$coordinator did not open the dispute.';
  }

  @override
  String get p2pEndDisputeUnknown =>
      'Bull Market does not know yet whether the dispute was opened. It keeps checking: the dispute shows here once it is open.';

  @override
  String get p2pEndRateTrade => 'Rate your trade experience';

  @override
  String p2pEndRateStar(String stars) {
    return '$stars of 5';
  }

  @override
  String get p2pEndYourTxid => 'Your TXID';

  @override
  String get p2pEndCopyTxid => 'Copy the TXID';

  @override
  String get p2pEndSendingCoins => 'Sending coins';

  @override
  String get p2pEndCopyAddress => 'Copy the address';

  @override
  String get p2pSummaryTitle => 'Trade Summary';

  @override
  String get p2pSummaryExport => 'Export trade summary';

  @override
  String get p2pSummaryExportCopyFailed =>
      'The trade summary could not be copied.';

  @override
  String get p2pSummaryUserRole => 'User role';

  @override
  String get p2pSummarySent => 'Sent';

  @override
  String get p2pSummaryReceived => 'Received';

  @override
  String get p2pSummaryBtcReceived => 'BTC received';

  @override
  String get p2pSummaryBtcSent => 'BTC sent';

  @override
  String get p2pSummaryTradeFee => 'Trade fee';

  @override
  String p2pSummarySats(String sats) {
    return '$sats Sats';
  }

  @override
  String p2pSummarySatsPercent(String sats, String percent) {
    return '$sats Sats ($percent%)';
  }

  @override
  String get p2pSummaryOnchainSwapFee => 'Onchain swap fee';

  @override
  String get p2pSummaryMakerBond => 'Maker bond';

  @override
  String get p2pSummaryUnlocked => 'Unlocked';

  @override
  String get p2pSummaryRevenue => 'Coordinator trade revenue';

  @override
  String get p2pSummaryRoutingBudget => 'Routing budget';

  @override
  String p2pSummaryRate(String rate, String currencyCode) {
    return '$rate $currencyCode/BTC';
  }

  @override
  String get p2pSummaryContractRate => 'Contract exchange rate';

  @override
  String get p2pEndRateUnknown =>
      'Bull Market does not know whether your rating went through: the order does not show it. Tap a star to send it again.';

  @override
  String get p2pEndRateNotSent => 'Your rating was not sent.';

  @override
  String p2pEndRateReadFailed(String coordinator) {
    return 'The order could not be read again from $coordinator: your rating was not sent.';
  }

  @override
  String get p2pEndRateHost => 'Rate your host';

  @override
  String p2pEndRateHostAsking(String coordinator) {
    return 'Asking $coordinator for permission to publish your rating…';
  }

  @override
  String p2pEndRateHostUnavailable(String coordinator) {
    return 'Your rating cannot be published: $coordinator could not be asked for permission, or refused it. Open this trade again to try again.';
  }

  @override
  String p2pEndHostLovesYou(String coordinator) {
    return 'Thank you! $coordinator loves you too';
  }

  @override
  String get p2pEndTellAFriend =>
      'RoboSats gets better with more liquidity and users. Tell a bitcoiner friend about Robosats!';

  @override
  String get p2pEndThanksForUsing => 'Thank you for using Robosats!';

  @override
  String p2pEndImprove(String simplex, String matrix, String github) {
    return 'Let us know how the platform could improve ($simplex / $matrix / $github)';
  }

  @override
  String get p2pEndImproveSimplex => 'SimpleX';

  @override
  String get p2pEndImproveMatrix => 'Matrix';

  @override
  String get p2pEndImproveGithub => 'Github';

  @override
  String get p2pMakeEnableAdvanced => 'Enable advanced options';

  @override
  String get p2pMakeBuyOrSell => 'Buy or Sell Bitcoin?';

  @override
  String get p2pMakeBuy => 'Buy';

  @override
  String get p2pMakeSell => 'Sell';

  @override
  String get p2pMakeAmount => 'Amount';

  @override
  String get p2pMakeAmountHint => 'Amount of fiat to exchange for bitcoin';

  @override
  String p2pMakeMoreThan(String minAmount) {
    return 'Must be more than $minAmount';
  }

  @override
  String p2pMakeLessThan(String maxAmount) {
    return 'Must be less than $maxAmount';
  }

  @override
  String get p2pMakePaymentMethods => 'Fiat Payment Method(s)';

  @override
  String get p2pMakePaymentMethodsHint =>
      'Enter your preferred fiat payment methods. Fast methods are highly recommended.';

  @override
  String get p2pMakeAddCustomMethod => 'Add custom payment method';

  @override
  String get p2pMakeCustomMethodQuestion =>
      'Can\'t find your favorite payment method in the list?';

  @override
  String get p2pMakeCustomMethodText =>
      'Use this free input to add any payment method you would like to offer.';

  @override
  String get p2pMakeCustomMethodLabel => 'Payment method';

  @override
  String get p2pMakeCustomMethodEmpty => 'Can\'t be empty';

  @override
  String get p2pMakeCustomMethodNotShown =>
      'Others would not see this text as you typed it. Use visible characters only.';

  @override
  String get p2pMakeAddPaymentMethod => 'Add payment method';

  @override
  String p2pMakeMustBeShorter(String max) {
    return 'Must be at most $max characters';
  }

  @override
  String p2pMakeRemoveMethod(String method) {
    return 'Remove $method';
  }

  @override
  String get p2pMakePremium => 'Premium over Market (%)';

  @override
  String p2pMakePremiumTooHigh(String max) {
    return 'Must be less than $max%';
  }

  @override
  String p2pMakePremiumTooLow(String min) {
    return 'Must be more than $min%';
  }

  @override
  String get p2pMakeOrderFor => 'Order for ';

  @override
  String get p2pMakeBuyBtcFor => 'Buy BTC for ';

  @override
  String get p2pMakeSellBtcFor => 'Sell BTC for ';

  @override
  String get p2pMakeAtMarketPrice => ' at market price';

  @override
  String p2pMakeAtPremium(String premium) {
    return ' at a $premium% premium';
  }

  @override
  String p2pMakeAtDiscount(String discount) {
    return ' at a $discount% discount';
  }

  @override
  String p2pMakeEstimatedBond(String sats) {
    return 'Estimated Bond: $sats Sats';
  }

  @override
  String p2pMakeCurrentRate(String rate, String currencyCode) {
    return 'Order current rate: $rate $currencyCode/BTC';
  }

  @override
  String get p2pMakeCurrentRateHint =>
      'Your order\'s current exchange rate. Rate will move with the market.';

  @override
  String get p2pMakeCreateOrder => 'Create order';

  @override
  String get p2pMakeLoading => 'Loading...';

  @override
  String get p2pMakeChooseHost => 'Choose the coordinator of the order';

  @override
  String get p2pMakeWhyLoadingCoordinators => 'Loading coordinator list...';

  @override
  String get p2pMakeWhyPriceNotSynchronized =>
      'The Bitcoin price is not synchronized.';

  @override
  String get p2pMakeWhyNoSide => 'Please select if you want to buy or sell.';

  @override
  String get p2pMakeWhyOutsideLimits =>
      'The amount is outside the allowed limits.';

  @override
  String get p2pMakeWhyBadPaymentMethod => 'The payment method is not valid.';

  @override
  String get p2pMakeWhyNoAmount => 'Please enter an amount.';

  @override
  String get p2pMakeWhyAmountNotPositive =>
      'The amount must be greater than 0.';

  @override
  String get p2pMakeWhyPremiumInvalid => 'The premium is not valid.';

  @override
  String get p2pMakeWhyLimitsUnavailable =>
      'The coordinator limits are not available.';

  @override
  String get p2pMakeWhyPremiumNotANumber => 'The premium must be a number.';

  @override
  String get p2pMakeWhyNoPaymentMethod => 'Please select a payment method.';

  @override
  String get p2pMakeWhyFormIncorrect => 'You must fill the form correctly';

  @override
  String get p2pMakeAmountRange => 'Amount Range';

  @override
  String get p2pMakeExactAmount => 'Exact Amount';

  @override
  String get p2pMakeFrom => 'From';

  @override
  String get p2pMakeTo => 'to';

  @override
  String get p2pMakeDescription => 'Description';

  @override
  String get p2pMakeDescriptionHint =>
      'You can add more details about your order.';

  @override
  String p2pMakeDescriptionTooLong(String max) {
    return 'Must be equal to or shorter than $max characters';
  }

  @override
  String get p2pMakePassword => 'Password';

  @override
  String get p2pMakePasswordHint =>
      'You can optionally set a password so that only the robots you share it with can take this order.';

  @override
  String get p2pMakePublicDuration => 'Public Duration (HH:mm)';

  @override
  String get p2pMakePublicDurationTitle => 'Public order length';

  @override
  String get p2pMakeEscrowDuration => 'Escrow/Invoice Timer (HH:mm)';

  @override
  String get p2pMakeEscrowDurationTitle => 'Escrow/invoice step length';

  @override
  String get p2pMakeBondSize => 'Fidelity Bond Size';

  @override
  String get p2pMakeBondSizeHint =>
      'Set the skin-in-the-game, increase for higher safety assurance';

  @override
  String p2pMakeBondSizeValue(String percent) {
    return '$percent%';
  }

  @override
  String get p2pMakeLocation => 'Face to Face Location';

  @override
  String get p2pMakeLocationHint => 'Add geolocation for a face to face trade';

  @override
  String get p2pMakeWhyRangeInvalid => 'The amount range is not valid.';

  @override
  String get p2pMakeRangeMaxBelowMin =>
      'The maximum must be above the minimum.';

  @override
  String p2pMakeRangeMinAtLeast(String amount, String coordinator) {
    return 'The minimum must be at least $amount with $coordinator.';
  }

  @override
  String p2pMakeRangeMaxAtMost(String amount, String coordinator) {
    return 'The maximum cannot exceed $amount with $coordinator.';
  }

  @override
  String p2pMakeRangeMaxAtLeastFor(String min, String amount) {
    return 'For a minimum of $min, the maximum must be at least $amount.';
  }

  @override
  String p2pMakeRangeMaxAtMostFor(String min, String amount) {
    return 'For a minimum of $min, the maximum cannot exceed $amount.';
  }

  @override
  String p2pMakeRangeAccepted(String coordinator, String min, String max) {
    return 'Amounts accepted with $coordinator: $min to $max.';
  }

  @override
  String get p2pMakeRangeRatio =>
      'The maximum must be more than 1.5 times the minimum and at most 14.95 times it.';

  @override
  String p2pMakeRangeMinAtMost(String amount, String coordinator) {
    return 'The minimum cannot exceed $amount with $coordinator: the maximum must be more than 1.5 times it.';
  }

  @override
  String p2pMakeRangeNoRoom(String coordinator) {
    return 'No range of amounts is possible with $coordinator at this premium: use an exact amount.';
  }

  @override
  String get p2pMakeRangeNotPositive => 'Type a minimum and a maximum above 0.';

  @override
  String get p2pMakeWhyDescriptionInvalid => 'The description is not valid.';

  @override
  String p2pMakeOptionsSentOpen(String options) {
    return 'Advanced options sent with this order: $options.';
  }

  @override
  String p2pMakeOptionsSentClosed(String options) {
    return 'Advanced options closed, but still sent with this order: $options.';
  }

  @override
  String get p2pMakeOptionSentDescription => 'a description';

  @override
  String p2pMakeOptionSentPublicDuration(String duration) {
    return 'public duration $duration';
  }

  @override
  String p2pMakeOptionSentEscrowDuration(String duration) {
    return 'escrow/invoice timer $duration';
  }

  @override
  String p2pMakeOptionSentBondSize(String percent) {
    return 'fidelity bond $percent';
  }

  @override
  String p2pMakeRateCompare(
    String walletPrice,
    String currency,
    String coordinator,
    String coordinatorPrice,
    String gap,
  ) {
    return 'For comparison, the Bull wallet\'s indicative price: $walletPrice $currency/BTC ($coordinator: $coordinatorPrice, gap $gap).';
  }

  @override
  String p2pMakeRateBelow(String coordinator, String threshold) {
    return '$coordinator\'s price is more than $threshold below the Bull wallet\'s: your bond would be larger than it should be. Check it before creating the order.';
  }

  @override
  String p2pMakeRateBelowSell(String coordinator, String threshold) {
    return '$coordinator\'s price is more than $threshold below the Bull wallet\'s: your bond would be larger than it should be, and you would lock more sats for your amount when the order is taken. Check it before creating the order.';
  }

  @override
  String p2pMakeRateAbove(String coordinator, String threshold) {
    return '$coordinator\'s price is more than $threshold above the Bull wallet\'s: you would receive fewer sats when the order is taken. Check it before creating the order.';
  }

  @override
  String p2pMakeRateNotPriced(String currency, String coordinator) {
    return 'The Bull wallet has no price for $currency: rate not checked. You are trusting $coordinator\'s price: check it yourself before creating the order.';
  }

  @override
  String p2pMakeRateUnverified(String currency) {
    return 'The Bull wallet\'s price of a bitcoin in $currency could not be read: rate not checked.';
  }

  @override
  String get p2pMakeRateReading =>
      'Reading the Bull wallet\'s price for comparison…';

  @override
  String get p2pMakeCreating => 'Creating your order…';

  @override
  String p2pMakePending(String coordinator) {
    return 'Bull Market does not know yet whether $coordinator made your order. Check it again below, or set it aside.';
  }

  @override
  String get p2pMakeNotMade => 'The order was not created.';

  @override
  String p2pMakeNotMadeAfter(String reason) {
    return '$reason The order was not created.';
  }

  @override
  String p2pMakeCoordinatorUnreadable(String coordinator) {
    return 'Could not reach $coordinator. The order was not created.';
  }

  @override
  String p2pMakeFeeTooHigh(String coordinator) {
    return '$coordinator asks for a maker fee above 1 %. The order was not created.';
  }

  @override
  String get p2pMakeTermsUnusable =>
      'The terms of this order could not be checked. It was not created.';

  @override
  String get p2pMakeNotRecorded =>
      'Bull Market could not write its records on this device. The order was not created.';

  @override
  String p2pMakeRobotNotNew(String coordinator) {
    return 'The robot chosen for this order already existed on $coordinator. The order was not created: try again.';
  }

  @override
  String get p2pMakeTooBig => 'Your order is too big.';

  @override
  String get p2pMakeTooSmall => 'Your order is too small.';

  @override
  String get p2pMakeRangeTooNarrow =>
      'Maximum range amount must be at least 50 percent higher than the minimum amount.';

  @override
  String get p2pMakeRangeMaxTooBig => 'Your order maximum amount is too big.';

  @override
  String get p2pMakeRangeMinTooSmall =>
      'Your order minimum amount is too small.';

  @override
  String get p2pMakeRangeTooWide =>
      'Your order amount range is too large. Max amount can only be 15 times bigger than min amount.';

  @override
  String p2pMakeBookFull(String coordinator) {
    return '$coordinator\'s book is full.';
  }

  @override
  String get p2pMakeClearForm => 'Clear form';

  @override
  String get p2pMakeCurrentRateLabel => 'Order current rate:';

  @override
  String p2pMakeCurrentRateUnit(String currencyCode) {
    return '$currencyCode/BTC';
  }

  @override
  String get p2pMakeNoHost => 'No coordinator can be chosen right now.';

  @override
  String p2pMakePriceCheckChanged(String coordinator) {
    return '$coordinator\'s price changed since it was shown. Check the comparison, then press \"Create order\" again.';
  }

  @override
  String get p2pMakePricesReadAgain =>
      'The limits and prices were read again and changed. Check the form, then press \"Create order\" again.';

  @override
  String get p2pMakePriceReadAtPress =>
      'The price comparison has just been updated. Check it, then press \"Create order\" again.';

  @override
  String get p2pTradeTitleOrderPublic => 'Your order is public';

  @override
  String get p2pTradeTitleOrderPaused => 'Your order is paused';

  @override
  String p2pTradePublicWait(String hours, String minutes) {
    return 'Be patient while robots check the book. This box will ring 🔊 once a robot takes your order, then you will have ${hours}h ${minutes}m to reply. If you do not reply, you risk losing your bond.';
  }

  @override
  String get p2pTradePublicExpiresUntaken =>
      'If the order expires untaken, your bond will return to you (no action needed).';

  @override
  String p2pTradePublicOrdersFor(String currencyCode) {
    return 'Public orders for $currencyCode';
  }

  @override
  String p2pTradePremiumRank(String rank) {
    return 'Premium rank $rank%';
  }

  @override
  String p2pTradePremiumRankAmong(String currencyCode) {
    return 'Among public $currencyCode orders (higher is cheaper)';
  }

  @override
  String get p2pTradePausedText =>
      'Your public order has been paused. At the moment it cannot be seen or taken by other robots. You can choose to unpause it at any time.';

  @override
  String get p2pTradePauseOrder => 'Pause the public order';

  @override
  String get p2pTradeUnpauseOrder => 'Unpause Order';

  @override
  String get p2pTradePauseNeedsRead =>
      'Wait until the order is read again before pausing or unpausing it.';

  @override
  String get p2pTradePauseMovedOn =>
      'The order changed before your request left: nothing was sent. It is shown as it is now.';

  @override
  String p2pTradePauseReadFailed(String coordinator) {
    return 'The order could not be read again from $coordinator: nothing was sent.';
  }

  @override
  String p2pTradePauseNotDoneAfter(String reason) {
    return '$reason Your request changed nothing.';
  }

  @override
  String p2pTradePauseRefusedBy(String coordinator) {
    return '$coordinator refused the request: your request changed nothing. The order is shown as it is now.';
  }

  @override
  String p2pTradePauseUnknown(String coordinator) {
    return 'Bull Market does not know yet whether your request reached $coordinator. It checks again while this screen is open, and never sends it again by itself. Do not tap again until a read shows where your order is: a second request would undo the first if the first arrives late.';
  }

  @override
  String p2pTradePauseNotReachedPaused(String coordinator) {
    return '$coordinator accepted the request, but your order is not paused: it is shown as it is now.';
  }

  @override
  String p2pTradePauseNotReachedPublic(String coordinator) {
    return '$coordinator accepted the request, but your order is not public: it is shown as it is now.';
  }

  @override
  String get p2pTradePauseWhileCancel =>
      'The order is being cancelled: wait until it ends.';

  @override
  String get p2pTradePauseMayStillArrive =>
      'A request whose answer was lost may still arrive and make your order public again. Two reads that show it paused, minutes apart, with this screen open, lower that risk without ruling it out: until then, count on it being possibly public.';

  @override
  String get p2pTradeCancelAfterPause =>
      'Your cancel will leave once the pause or unpause ends.';

  @override
  String get p2pTradeCancelMovedOnTapAgain =>
      'The order changed state before the cancel: nothing was cancelled. Tap \"Cancel\" again if you still want to cancel it.';

  @override
  String get p2pTradeStillPublic =>
      'Your order is public: robots can see it and take it.';

  @override
  String get p2pTradeMayBePublic =>
      'Until a read made after your request shows it paused, count on your order being public: robots can take it.';

  @override
  String get p2pTradePublicAgain =>
      'Your order is public again, although it was paused from this app: robots can see it and take it.';

  @override
  String get p2pTradeMakerBondLocked => 'Your maker bond is locked';

  @override
  String get p2pTradeMakerBondUnlocked => 'Your maker bond is unlocked';

  @override
  String get p2pTradeMakerBondSettled => 'Your maker bond is settled';

  @override
  String p2pTradeRateGap(
    String coordinator,
    String sats,
    String amount,
    String currencyCode,
    String rate,
    String gap,
    String createdRate,
  ) {
    return '$coordinator fixed $sats sats for $amount $currencyCode when your order was taken: a rate of $rate $currencyCode/BTC, $gap from the rate when you made it ($createdRate).';
  }

  @override
  String get p2pTradeWarnContractSeenLate =>
      'Your order was taken again and this trade moved on without Bull Market seeing its steps, as when your Garage Key is used in another app. Check the trade in that app before acting here.';

  @override
  String p2pPendingMakeChecking(String coordinator) {
    return 'Checking with $coordinator…';
  }

  @override
  String p2pPendingMakeUnknown(String coordinator) {
    return 'Bull Market does not know yet whether $coordinator made this order. No bond is asked until it knows.';
  }

  @override
  String get p2pPendingMakeSetAside => 'Set aside';

  @override
  String get p2pPendingMakeSetAsideTitle => 'Set this order aside?';

  @override
  String p2pPendingMakeSetAsideText(String coordinator) {
    return 'Bull Market will stop checking it. An order may still exist at $coordinator: no bond was paid for it from this app, and it expires on its own a few minutes after it was made.';
  }

  @override
  String get p2pMakePendingFirst =>
      'An order of yours is still being created. Check it again or set it aside before creating another.';

  @override
  String p2pMakeSendingStay(String coordinator) {
    return 'Wait for $coordinator\'s answer before leaving: your order is being created.';
  }

  @override
  String get p2pPayoutRateReading =>
      'Reading the Bull wallet\'s price for comparison…';

  @override
  String p2pPayoutRateWallet(
    String price,
    String currency,
    String amount,
    String expected,
    String received,
    String gap,
  ) {
    return 'At the Bull wallet\'s price, $price $currency/BTC, with the order\'s premium, $amount $currency are worth $expected sats. You receive $received sats: gap $gap.';
  }

  @override
  String get p2pPayoutBreakdownTitle => 'Breakdown, in sats';

  @override
  String get p2pPayoutBreakdownNotCompared =>
      'No Bull Wallet check at this step';

  @override
  String get p2pPayoutBreakdownValue => 'Expected by Bull Wallet';

  @override
  String p2pPayoutBreakdownPrice(String amount, String currency, String price) {
    return '$amount $currency at $price $currency/BTC, premium included';
  }

  @override
  String get p2pPayoutBreakdownGiven => 'Paid by the coordinator';

  @override
  String get p2pPayoutBreakdownGap => 'Gap to the Bull price (indicative)';

  @override
  String get p2pPayoutBreakdownCoordinatorFee =>
      'Coordinator\'s fee, already deducted';

  @override
  String get p2pPayoutBreakdownRoutingBudget => 'Lightning routing fees';

  @override
  String get p2pPayoutBreakdownInvoice => 'Your invoice';

  @override
  String get p2pPayoutBreakdownSwapFee => 'Swap fees';

  @override
  String get p2pPayoutBreakdownReceived => 'You will receive';

  @override
  String get p2pPayoutBreakdownFees => 'Routing and swap fees';

  @override
  String get p2pPayoutBreakdownRoutingFees => 'Routing fees';

  @override
  String get p2pPayoutBreakdownGapNotPriced => 'Gap to the Bull price';

  @override
  String get p2pPayoutBreakdownNotPriced => 'not quoted';

  @override
  String get p2pPayoutBreakdownAgainst => 'Gap against you';

  @override
  String p2pPayoutBreakdownAgainstFigures(String expected, String received) {
    return 'Bull Wallet expected $expected sats, the coordinator pays $received.';
  }

  @override
  String p2pPayoutBreakdownAgainstDetail(String threshold) {
    return 'Bull Wallet redoes the calculation with its own price, premium included, and warns you beyond a $threshold gap. Check the order before going on.';
  }

  @override
  String get p2pPayoutBreakdownUnverified => 'Amount not checked';

  @override
  String get p2pPayoutBreakdownUnverifiedLine =>
      'Bull Wallet could not get its bitcoin price.';

  @override
  String get p2pPayoutBreakdownUnverifiedDetail =>
      'Without this price, it cannot compare the coordinator\'s amount.';

  @override
  String get p2pPayoutRateTermsUnreadLine =>
      'Bull Wallet could not read this order\'s terms on this device.';

  @override
  String get p2pPayoutRateTermsUnreadDetail =>
      'Without them, it cannot compare the coordinator\'s amount.';

  @override
  String get p2pPayoutFirstFewer => 'Fewer sats than the first invoice';

  @override
  String p2pPayoutFirstFewerFigures(String first, String now) {
    return 'First asked: $first sats, the coordinator now pays $now.';
  }

  @override
  String get p2pPayoutFirstFewerDetail =>
      'For the same contract, the coordinator must ask the same amount again. You have already sent your payment and no dispute can be opened at this step: contact the coordinator before giving this invoice.';

  @override
  String get p2pPayoutFirstUnknown => 'Not compared with the first invoice';

  @override
  String get p2pPayoutFirstUnknownDetail =>
      'Bull Market knows the first invoice\'s amount only if it saw it since the app last started. Compare it yourself with this one.';

  @override
  String p2pRateAgainstSinceMade(String gap) {
    return 'Gap of $gap against you since the order was made';
  }

  @override
  String p2pRateAgainstSinceMadeDetail(String currency) {
    return 'Bull Wallet does not quote $currency. It therefore compares the coordinator\'s rate at the take with its rate when the order was made. The market may have moved in between.';
  }

  @override
  String get p2pPayoutBreakdownSmallGap =>
      'A small gap is normal: the coordinator has its own price source.';

  @override
  String get p2pDetailShow => 'Show details';

  @override
  String get p2pDetailHide => 'Hide details';

  @override
  String p2pPayoutRateAgainst(String gap) {
    return 'Gap against you $gap';
  }

  @override
  String p2pPayoutRateNotPriced(String currency, String coordinator) {
    return 'The Bull wallet has no price for $currency: rate not checked. You are trusting $coordinator\'s price: check it yourself before going on.';
  }

  @override
  String p2pPayoutRateUnverified(String currency) {
    return 'The Bull wallet\'s price of a bitcoin in $currency could not be read: rate not checked. You can try again, or go on without the check.';
  }

  @override
  String p2pTradeBreachWhatToDo(String coordinator) {
    return 'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact $coordinator if something looks wrong.';
  }

  @override
  String p2pPayoutRateSatsMissing(String coordinator) {
    return 'Rate not checked: $coordinator gives no sats for this step of the trade. Check them yourself before going on.';
  }

  @override
  String get p2pTradeNoRingYet =>
      'Bull Market does not ring yet: keep this screen open, or come back to it often.';

  @override
  String get p2pTradeEscrowWaitMaker =>
      'For an order you made: if the seller does not lock the collateral, your order goes back to the book and your bond stays locked.';

  @override
  String get p2pTradePayoutWaitMaker =>
      'For an order you made: if the buyer does not cooperate, your collateral comes back, but your order goes back to the book and your bond stays locked.';

  @override
  String p2pPayoutRateToldMoved(String coordinator, String told, String asked) {
    return '$coordinator now gives $told sats for this contract, but asked for an invoice of $asked sats before: Bull Market compares the smaller. Check the invoice you gave before going on.';
  }

  @override
  String p2pPayoutRateToldNow(String coordinator) {
    return 'The sats you receive shown above are those $coordinator gives now: Bull Market does not keep your invoice after a restart. Compare them yourself with your invoice\'s amount.';
  }

  @override
  String get p2pTradeBondBackThroughSwap =>
      'A bond paid with this wallet comes back through the swap service, less its fees, after a delay.';

  @override
  String get p2pPayoutRateNotSeen =>
      'Bull Market has not seen this contract\'s payout invoice: do not send the money before checking in the official app.';

  @override
  String get p2pTradeBondPaidHereBack =>
      'Your bond was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.';

  @override
  String get p2pTradeEscrowPaidHereBack =>
      'Your collateral was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.';

  @override
  String get p2pTradeBothPaidHereBack =>
      'Your bond and collateral were paid with this wallet: once returned, they come back through the swap service, less its fees, after a delay.';

  @override
  String get p2pTradeBondOrEscrowBackThroughSwap =>
      'A bond or collateral paid with this wallet comes back through the swap service, less its fees, after a delay.';

  @override
  String get p2pOrderRecordsUnreadable =>
      'Bull Market could not read its trades: this order may be yours, so it cannot be taken here. Go back and try again.';

  @override
  String get p2pRenewOrder => 'Renew Order';

  @override
  String get p2pRenew => 'Renew';

  @override
  String p2pRenewIntro(String orderId) {
    return 'Renewing order $orderId: a new order is made with the terms this device kept of it, under a new robot, and asks for a new bond.';
  }

  @override
  String get p2pRenewTermsUnreadable =>
      'This order cannot be renewed: the terms this device kept of it could not be read.';

  @override
  String get p2pRenewNotEnded =>
      'This order cannot be renewed: this device has not seen it expired or finished.';

  @override
  String get p2pRenewCoordinatorGone =>
      'This order cannot be renewed: its coordinator is no longer in the list, or has moved.';

  @override
  String get p2pRenewNotAsKept =>
      'The form does not show exactly the terms kept of this order: nothing can be sent.';

  @override
  String get p2pRenewNoLongerAsKept =>
      'This order can no longer be renewed as it was: create a new order.';

  @override
  String p2pTradeKeptTerms(String date, String summary) {
    return 'Made here on $date, with the terms kept on this device: $summary.';
  }

  @override
  String p2pSameTermsMade(String orderId, String stands) {
    return 'An order with the same terms was made here after this one: order $orderId, $stands.';
  }

  @override
  String get p2pSameTermsRunning => 'still running here';

  @override
  String get p2pSameTermsExpired => 'expired';

  @override
  String get p2pSameTermsCancelled => 'cancelled';

  @override
  String get p2pSameTermsCompleted => 'completed';

  @override
  String get p2pSameTermsEnded => 'ended';

  @override
  String p2pSameTermsOpen(String orderId) {
    return 'Open order $orderId';
  }

  @override
  String get p2pSameTermsUnknown =>
      'Bull Market could not read its records to tell whether an order with the same terms was made here since this one.';

  @override
  String get p2pRenewSameTermsTitle => 'Renew this order?';

  @override
  String get p2pRenewSameTermsGo => 'Renew anyway';

  @override
  String p2pTradeEndNotRead(String coordinator, String date) {
    return 'This order could not be read again from $coordinator: what is shown is what this device kept when it ended, on $date.';
  }

  @override
  String p2pTradeEndUnknown(String coordinator, String date) {
    return '$coordinator answered that it does not know this order: what is shown is what this device kept when it ended, on $date.';
  }

  @override
  String p2pTradeEndOtherwise(String coordinator, String date) {
    return '$coordinator now shows this order otherwise than this device kept it when it ended, on $date.';
  }

  @override
  String p2pRenewEndNotConfirmed(String coordinator) {
    return 'The end of this order was not confirmed by $coordinator.';
  }

  @override
  String p2pRenewEndAlive(String coordinator) {
    return '$coordinator shows this order still running: it may still be taken or need an action from you, and sats may still be locked in it.';
  }

  @override
  String p2pRenewEndOtherwise(String coordinator) {
    return '$coordinator shows this order otherwise than this device kept it.';
  }

  @override
  String p2pRenewSameTermsMade(String orderId, String stands) {
    return 'An order with the same terms was already made here after this one: order $orderId, $stands.';
  }

  @override
  String get p2pRenewSameTermsUnknown =>
      'Bull Market could not check whether an order with the same terms was already made here.';

  @override
  String get p2pRenewOneMore =>
      'Renewing makes one more order, under a new robot, with a new bond to pay.';

  @override
  String get p2pSameTermsPending =>
      'An order with the same terms is still being created here.';

  @override
  String p2pTradeEndReading(String coordinator) {
    return 'Reading this order again from $coordinator…';
  }

  @override
  String p2pTradeEndAlive(String coordinator) {
    return '$coordinator now shows this order as still running: it may still be taken or need an action from you, and sats may still be locked in it. Check it in the official RoboSats app with your Garage Key before you create another.';
  }

  @override
  String p2pTradeEndKeptEnded(String date) {
    return 'This device kept this order as ended on $date.';
  }

  @override
  String get p2pRenewUnverified =>
      'Bull Market could not check whether this renewal made an order: nothing more can be sent from this page. Go back, then open the order again from the Garage or « Order ».';

  @override
  String get p2pMakeSubmit => 'Submit';

  @override
  String get p2pMakeEditOrder => 'Edit order';

  @override
  String get p2pMakeMatchesFound => 'Existing orders match yours!';

  @override
  String get p2pMakeSeeDetails => 'See details';

  @override
  String get p2pMakeHideDetails => 'Hide details';

  @override
  String get p2pMakePasswordLine =>
      'Kept out of the book; taken with its link and the password.';

  @override
  String get p2pMakePasswordShare =>
      'Share the order\'s link (« Copy URL » on its page once it is made) and the password with the robots you choose.';

  @override
  String get p2pMakePasswordTakers =>
      'Whoever has the link and the password can take it, in Bull Market (« Search order ») or in the official RoboSats app.';

  @override
  String get p2pMakePasswordReadable =>
      'Whoever asks the coordinator for the order by its number can still read its side, currency, amount, premium, payment method, bond, timers and your robot\'s name; not its description nor its location.';

  @override
  String get p2pMakePasswordHashOnly =>
      'Only the password\'s SHA-256 leaves this device, and it is not kept: renewing the order asks for the password again.';

  @override
  String p2pMakePasswordOldCoordinator(String coordinator, String version) {
    return '$coordinator ($version) shows protected orders to anyone.';
  }

  @override
  String p2pMakePasswordUnknownVersion(String coordinator) {
    return 'Version of $coordinator unknown: a protected order may be visible to anyone.';
  }

  @override
  String get p2pMakePasswordOldDetail =>
      'Before version 0.8.7 (advisory GHSA-r6f6-x59j-8q69), a coordinator gives a protected order\'s amount, premium, payment method, your robot\'s name and its location to whoever asks for it, without the password. The order can still be made; choose another coordinator to keep it private.';

  @override
  String get p2pMakeOptionSentPassword => 'a password';

  @override
  String get p2pRenewPasswordAgain => 'Enter a password again';

  @override
  String get p2pRenewPasswordSame =>
      'This device does not keep the password: type the same one as before, the one you shared, or the order will not open with it.';

  @override
  String p2pMakeLocationSent(String point) {
    return 'Point sent: $point';
  }

  @override
  String get p2pMakeLocationRemove => 'Remove the location';

  @override
  String get p2pMakeLocationRandomized =>
      'To protect your privacy, the exact location you pin will be slightly randomized.';

  @override
  String get p2pMakeLocationPublished =>
      'Sent to the coordinator; published with the order unless it has a password.';

  @override
  String get p2pMakeLocationDetail =>
      'The point shown is the one sent: the place you pinned, moved by up to 0.05° each way (a few kilometres). The coordinator shows it with the order, and publishes it on Nostr with an order without a password. Bull Market reads nothing of your phone\'s position, only the point you pin.';

  @override
  String get p2pMapChooseLocation => 'Choose a location';

  @override
  String get p2pMapSave => 'Save';

  @override
  String get p2pMapPinHint => 'World map: tap a place to pin it.';

  @override
  String p2pMapPinned(String point) {
    return 'Place pinned: $point';
  }

  @override
  String get p2pPayoutTracePasted =>
      'This contract\'s payout invoice was pasted: the sats will go to the wallet that made it.';

  @override
  String get p2pPayoutTracePastedAddress =>
      'This contract\'s payout address was pasted: the sats will go to the wallet it belongs to.';

  @override
  String get p2pPayoutTraceNotGivenHere =>
      'This contract\'s payout invoice or address was not given from Bull Market: check where the sats will arrive.';

  @override
  String get p2pPayoutTraceUnknown =>
      'Bull Market cannot tell whether this contract\'s payout invoice or address came from this wallet.';

  @override
  String p2pTermsShownAbove(
    String coordinator,
    String day,
    String time,
    String high,
    String own,
  ) {
    return '$coordinator showed this trade with other terms from $day at $time, up to a premium of $high instead of $own.';
  }

  @override
  String p2pTermsShownBelow(
    String coordinator,
    String day,
    String time,
    String low,
    String own,
  ) {
    return '$coordinator showed this trade with other terms from $day at $time, with a premium down to $low instead of $own.';
  }

  @override
  String p2pTermsShownBoth(
    String coordinator,
    String day,
    String time,
    String low,
    String high,
    String own,
  ) {
    return '$coordinator showed this trade with other terms from $day at $time, with premiums from $low to $high instead of $own.';
  }

  @override
  String p2pTermsShownPremiums(
    String coordinator,
    String day,
    String time,
    String low,
    String high,
  ) {
    return '$coordinator showed this trade with other terms from $day at $time, with premiums from $low to $high.';
  }

  @override
  String p2pTermsShownPremiumAlone(
    String coordinator,
    String day,
    String time,
    String premium,
  ) {
    return '$coordinator showed this trade with other terms from $day at $time, with a premium of $premium.';
  }

  @override
  String p2pTermsShownOther(String coordinator, String day, String time) {
    return '$coordinator showed this trade with other terms from $day at $time.';
  }

  @override
  String get p2pTakeWrongPassword => 'Wrong password';

  @override
  String get p2pTakePasswordMissing => 'Enter the order\'s password.';

  @override
  String get p2pTakeProtectedHidden =>
      'Protected order: its description and location are shown once you take it.';

  @override
  String get p2pTradeMeetingPoint => 'F2F location';

  @override
  String get p2pTradeMeetingPointApproximate =>
      'The pinned location is approximate. The exact location for the meeting place must be exchanged in the encrypted chat.';

  @override
  String get p2pMapShowTiles => 'Show tiles';

  @override
  String get p2pMapTilesTitle => 'Download high resolution map?';

  @override
  String get p2pMapTilesText =>
      'By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation.';

  @override
  String get p2pMapTilesClose => 'Close';

  @override
  String get p2pMapTilesAcknowledged => 'Acknowledged';

  @override
  String get p2pMapTilesCredit => '© OpenStreetMap contributors';

  @override
  String get p2pMapTilesUnavailable => 'Map tiles unavailable';

  @override
  String get p2pTakePriceAgainst => 'Price against you';

  @override
  String get p2pTakePriceFarBelow => 'Price far below the Bull price';

  @override
  String p2pTakePriceFigures(
    String wallet,
    String currency,
    String coordinator,
  ) {
    return 'Bull Wallet uses $wallet $currency/BTC, the coordinator $coordinator.';
  }

  @override
  String p2pTakePriceDetail(String threshold) {
    return 'Bull Wallet compares the coordinator\'s price, premium excluded, with its own price and warns you beyond a $threshold gap. Check the order before taking it.';
  }

  @override
  String get p2pTakePriceUnverified => 'Price not checked';

  @override
  String get p2pTakePriceUnverifiedDetail =>
      'Without this price, it cannot compare the coordinator\'s price. You can try again, or take the order without this check.';

  @override
  String get p2pTakePageChangedTitle => 'This page has changed';

  @override
  String get p2pTakePageChangedLine =>
      'Read the price line again, then continue again.';

  @override
  String get p2pHistoryShow => 'See history';

  @override
  String get p2pHistoryHide => 'Hide history';

  @override
  String get p2pHistorySeeMore => 'See more';

  @override
  String p2pHistoryTitle(String orderId, String coordinator) {
    return '#$orderId · $coordinator';
  }

  @override
  String p2pHistoryFacts(String side, String origin, String day) {
    return '$side · $origin · $day';
  }

  @override
  String p2pHistoryRobotNamed(String robot, String nickname) {
    return '$robot · $nickname';
  }

  @override
  String get p2pHistorySell => 'Sell';

  @override
  String get p2pHistoryBuy => 'Buy';

  @override
  String get p2pHistoryMadeHere => 'made here';

  @override
  String get p2pHistoryTakenHere => 'taken here';

  @override
  String get p2pHistoryTraded => 'Traded';

  @override
  String get p2pHistoryExpired => 'Expired';

  @override
  String get p2pHistoryCancelled => 'Cancelled';

  @override
  String get p2pHistoryDispute => 'Dispute';

  @override
  String get p2pHistoryEndUnknown => 'End unknown';

  @override
  String p2pGarageKeyNumber(int index) {
    return 'Internal Garage Key #$index';
  }

  @override
  String get p2pGarageKeyMasked => 'robo1••••••••••••';

  @override
  String get p2pGaragePreviousKey => 'Previous internal Garage Key';

  @override
  String get p2pGarageNextKey => 'Next internal Garage Key';

  @override
  String get p2pGarageNewKey => 'New internal Garage Key';

  @override
  String get p2pGarageNewKeyTitle => 'New Garage Key';

  @override
  String p2pGarageNewKeyText(int index) {
    return 'Your trades will use internal Garage Key #$index. Earlier Garage Keys stay within reach in the Garage.';
  }

  @override
  String p2pGarageNewKeyConfirm(int index) {
    return 'Create internal Garage Key #$index';
  }

  @override
  String get p2pGarageKeyNoWallet =>
      'No default Bitcoin wallet: the internal Garage Keys come from its 12 words.';

  @override
  String get p2pGarageKeyPassphrase =>
      'This wallet has a passphrase: its 12 words alone do not give the internal Garage Keys.';

  @override
  String get p2pGarageKeyNoWords =>
      'This wallet has no words: the internal Garage Keys come from them.';

  @override
  String get p2pGarageKeyMismatch =>
      'The 12 words of this wallet do not give back the internal Garage Key recorded on this device. Nothing was signed.';

  @override
  String get p2pGarageKeyLastIndex =>
      'There is no internal Garage Key after this one.';

  @override
  String get p2pGarageExternalKey => 'External Garage Key';

  @override
  String get p2pGarageKeyBackedUp =>
      'Backed up by the 12 words of your Bull Wallet.';

  @override
  String get p2pGarageKeyNotBackedUp =>
      'Not backed up by your Bull Wallet: keep a copy of it.';

  @override
  String get p2pGarageKeyExplain => 'Explanation';

  @override
  String get p2pGarageInternalKeysTitle => 'Internal Garage Keys';

  @override
  String get p2pGarageInternalKeysInfo =>
      'Your internal Garage Keys are backed up by the 12 words of your Bull Wallet: reinstall the app with these 12 words and you find them again. Keep them safe and do not share them: whoever holds a Garage Key controls its robots.';

  @override
  String get p2pGarageExternalKeyInfo =>
      'This Garage Key is not backed up by the 12 words of your Bull Wallet. If you lose this phone or delete the app, you will only find it again with your own copy: back it up separately. Keep it safe and do not share it.';

  @override
  String get p2pGarageSwitchToExternal => 'Switch to the external Garage Key';

  @override
  String get p2pGarageBackToInternal => 'Back to internal Garage Keys';

  @override
  String get p2pGarageImportExternal => 'Import an external Garage Key';

  @override
  String get p2pGarageDeleteExternal => 'Delete the external Garage Key';

  @override
  String get p2pGarageDeleteExternalTitle => 'Delete the external Garage Key?';

  @override
  String get p2pGarageDeleteExternalText =>
      'It is not backed up by your Bull Wallet. Without a copy, its robots will be lost to this app.';

  @override
  String p2pGarageDeleteExternalTrades(int count, String orders) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Trades $orders use this Garage Key: without it, you will not be able to continue them.',
      one:
          'Trade $orders uses this Garage Key: without it, you will not be able to continue it.',
    );
    return '$_temp0';
  }

  @override
  String get p2pGarageDeleteExternalUnread =>
      'Bull Market could not read your trades: a trade in progress may use this Garage Key.';

  @override
  String get p2pGarageDeleteConfirm => 'Delete';

  @override
  String get p2pGarageNoticeTitle => 'Your Garage Keys';

  @override
  String get p2pGarageNoticeText =>
      'Your current Garage Key is now called « External Garage Key ». The internal Garage Keys, backed up by your Bull Wallet, are next to it: tap « Back to internal Garage Keys ».';

  @override
  String p2pGarageTradeInProgress(String orderId) {
    return 'Trade in progress #$orderId';
  }

  @override
  String p2pGarageKeyIsInternal(int index) {
    return 'This is already your internal Garage Key #$index.';
  }
}
