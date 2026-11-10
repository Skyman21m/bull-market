// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class P2pLocalizationsCs extends P2pLocalizations {
  P2pLocalizationsCs([String locale = 'cs']) : super(locale);

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
}
