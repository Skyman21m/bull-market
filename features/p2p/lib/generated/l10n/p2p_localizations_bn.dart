// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class P2pLocalizationsBn extends P2pLocalizations {
  P2pLocalizationsBn([String locale = 'bn']) : super(locale);

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
  String get p2pBookFilterAny => 'ANY';

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
  String p2pBookCoordinatorsLoading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coordinators are still loading',
      one: '1 coordinator is still loading',
    );
    return '$_temp0';
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
}
