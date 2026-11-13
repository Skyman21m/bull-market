import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'p2p_localizations_ar.dart';
import 'p2p_localizations_as.dart';
import 'p2p_localizations_bg.dart';
import 'p2p_localizations_bn.dart';
import 'p2p_localizations_cs.dart';
import 'p2p_localizations_de.dart';
import 'p2p_localizations_el.dart';
import 'p2p_localizations_en.dart';
import 'p2p_localizations_es.dart';
import 'p2p_localizations_fa.dart';
import 'p2p_localizations_fi.dart';
import 'p2p_localizations_fr.dart';
import 'p2p_localizations_hi.dart';
import 'p2p_localizations_hy.dart';
import 'p2p_localizations_it.dart';
import 'p2p_localizations_ka.dart';
import 'p2p_localizations_ko.dart';
import 'p2p_localizations_pt.dart';
import 'p2p_localizations_ru.dart';
import 'p2p_localizations_sw.dart';
import 'p2p_localizations_th.dart';
import 'p2p_localizations_tr.dart';
import 'p2p_localizations_uk.dart';
import 'p2p_localizations_vi.dart';
import 'p2p_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of P2pLocalizations
/// returned by `P2pLocalizations.of(context)`.
///
/// Applications need to include `P2pLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/p2p_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: P2pLocalizations.localizationsDelegates,
///   supportedLocales: P2pLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the P2pLocalizations.supportedLocales
/// property.
abstract class P2pLocalizations {
  P2pLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static P2pLocalizations of(BuildContext context) {
    return Localizations.of<P2pLocalizations>(context, P2pLocalizations)!;
  }

  static const LocalizationsDelegate<P2pLocalizations> delegate =
      _P2pLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('as'),
    Locale('bg'),
    Locale('bn'),
    Locale('cs'),
    Locale('de'),
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fi'),
    Locale('fr'),
    Locale('hi'),
    Locale.fromSubtags(languageCode: 'hi', scriptCode: 'Latn'),
    Locale('hy'),
    Locale('it'),
    Locale('ka'),
    Locale('ko'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('ru'),
    Locale('sw'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh'),
  ];

  /// Label of the third tab of the wallet's bottom bar, between Wallet and Exchange. Fits in every language; final label still to be confirmed.
  ///
  /// In en, this message translates to:
  /// **'P2P'**
  String get p2pTabLabel;

  /// Italic banner at the top of the P2P pages, only when the P2P network is testnet. The RoboSats French text drops the article; the wallet writes « Bitcoin Testnet ».
  ///
  /// In en, this message translates to:
  /// **'Using Testnet Bitcoin'**
  String get p2pTestnetBanner;

  /// Line under the progress bar while Tor connects inside the P2P tab. Corrected on 10/11/2026 after review of the mock-up: payments may go through the wallet's swap service, so only the coordinators are said to be reached through Tor.
  ///
  /// In en, this message translates to:
  /// **'Coordinators are only ever reached through Tor.'**
  String get p2pTorWaitingLine;

  /// First step of the Tor wait. The RoboSats French text keeps the English word « daemon »: « service » here.
  ///
  /// In en, this message translates to:
  /// **'Initializing Tor daemon'**
  String get p2pTorInitializing;

  /// Tor is starting (RoboSats state 'STARTING'). Also the title of the Tor wait inside the P2P tab.
  ///
  /// In en, this message translates to:
  /// **'Connecting to Tor network'**
  String get p2pTorConnecting;

  /// Tor is ready (RoboSats state 'ON'). The federation (coordinators, book) loads only after this state.
  ///
  /// In en, this message translates to:
  /// **'Connected to Tor network'**
  String get p2pTorConnected;

  /// Tor could not start. Default value of the Tor state in RoboSats, shown until another state is known.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get p2pTorConnectionError;

  /// Phrase 1 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Sats travelling at the speed of light'**
  String get p2pTorWaitPhrase1;

  /// Phrase 2 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Peeling the onion, layer by layer'**
  String get p2pTorWaitPhrase2;

  /// Phrase 3 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Bouncing from relay to relay'**
  String get p2pTorWaitPhrase3;

  /// Phrase 4 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Hiding your IP address from coordinators'**
  String get p2pTorWaitPhrase4;

  /// Phrase 5 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Waking up the robots'**
  String get p2pTorWaitPhrase5;

  /// Phrase 6 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'No KYC, just robots'**
  String get p2pTorWaitPhrase6;

  /// Phrase 7 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Not your keys, not your coins'**
  String get p2pTorWaitPhrase7;

  /// Phrase 8 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Don\'t trust, verify'**
  String get p2pTorWaitPhrase8;

  /// Phrase 9 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Privacy is not a crime'**
  String get p2pTorWaitPhrase9;

  /// Phrase 10 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Be your own bank'**
  String get p2pTorWaitPhrase10;

  /// Phrase 11 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Tick tock, next block'**
  String get p2pTorWaitPhrase11;

  /// Phrase 12 of the twelve shown one at a time under the bar while Tor starts in the P2P tab, changing every 2 seconds in an order shuffled at each wait. Troc's own text, approved by the owner on 2026-11-12 (#68): the official client shows none here. Decoration only, kept out of what a screen reader reads.
  ///
  /// In en, this message translates to:
  /// **'Loading with low time preference'**
  String get p2pTorWaitPhrase12;

  /// Destination inside the P2P tab: the order book. « Offers » because the RoboSats English says Offers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get p2pNavOffers;

  /// Middle destination when the robot has no active order: opens the maker form (phase 3). Disabled in phase 1.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get p2pNavCreate;

  /// Destination of the robots; the same word in English and French.
  ///
  /// In en, this message translates to:
  /// **'Garage'**
  String get p2pNavGarage;

  /// Middle destination when the robot has an active order; also the title of the page of an order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get p2pNavOrder;

  /// Narrow button (a quarter of the width, below the book): opens « Search order ». The RoboSats French text is left in English.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get p2pCommonSearch;

  /// View switch below the book. The RoboSats French text uses a verb (« Lister ») next to nouns: a noun here. Narrow segment.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get p2pBookViewList;

  /// View switch below the book, and header of the depth chart. The longest of the four narrow segments.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get p2pBookViewChart;

  /// View switch below the book, header of the map, and title of the meeting place map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get p2pBookViewMap;

  /// Start of the filter sentence « I want to [type] and use [currency] pay with [method] hosted by [host] ».
  ///
  /// In en, this message translates to:
  /// **'I want to'**
  String get p2pBookFilterIWantTo;

  /// The « any » value of the four selectors (type, currency, payment method, host), and the value of {currencyCode} in the empty book message.
  ///
  /// In en, this message translates to:
  /// **'ANY'**
  String get p2pBookFilterAny;

  /// Choosing « Buy » shows the SELL orders (type 1).
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get p2pBookFilterBuy;

  /// Choosing « Sell » shows the BUY orders (type 0).
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get p2pBookFilterSell;

  /// Title of the order type selector.
  ///
  /// In en, this message translates to:
  /// **'Select Order Type'**
  String get p2pBookFilterSelectOrderType;

  /// Linking words of the filter sentence, before the currency.
  ///
  /// In en, this message translates to:
  /// **'and use'**
  String get p2pBookFilterAndUse;

  /// Title of the currency selector.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Currency'**
  String get p2pBookFilterSelectCurrency;

  /// Linking words of the filter sentence, before the payment method (fiat mode).
  ///
  /// In en, this message translates to:
  /// **'pay with'**
  String get p2pBookFilterPayWith;

  /// Title of the payment method selector.
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get p2pBookFilterSelectMethod;

  /// Linking words of the filter sentence, before the host selector.
  ///
  /// In en, this message translates to:
  /// **'hosted by'**
  String get p2pBookFilterHostedBy;

  /// Title of the host (coordinator) selector.
  ///
  /// In en, this message translates to:
  /// **'Select Host'**
  String get p2pBookFilterSelectHost;

  /// The maker was seen in the last 2 minutes (`maker_status` of the API). Missing from the RoboSats French texts.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get p2pBookMakerStatusActive;

  /// The maker was seen in the last 10 minutes. Missing from the RoboSats French texts.
  ///
  /// In en, this message translates to:
  /// **'Seen recently'**
  String get p2pBookMakerStatusSeenRecently;

  /// The maker was not seen for 10 minutes or more. Missing from the RoboSats French texts.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get p2pBookMakerStatusInactive;

  /// Role pill of an order of type 1: its maker sells bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get p2pBookRoleSeller;

  /// Role pill of an order of type 0: its maker buys bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get p2pBookRoleBuyer;

  /// Amount column header, and caption of a fixed amount on the order page (where RoboSats leaves it untranslated).
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get p2pBookColumnAmount;

  /// Label of the premium of an offer in the book, and choice of the horizontal axis of the depth chart.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get p2pBookColumnPremium;

  /// Label of the bond of an offer in the book.
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get p2pBookColumnBond;

  /// Tooltip of a bond below the default (3 %). Left in English in the RoboSats French texts.
  ///
  /// In en, this message translates to:
  /// **'Low bond: This maker has set a bond below the default {defaultBond}%. Lower bonds mean reduced trade security.'**
  String p2pBookLowBond(String defaultBond);

  /// Generic error of a coordinator whose answer could not be read.
  ///
  /// In en, this message translates to:
  /// **'An error occurred.'**
  String get p2pBookError;

  /// Empty book when the filter is « Sell ». {currencyCode} is the currency code or « ANY ».
  ///
  /// In en, this message translates to:
  /// **'No orders found to sell BTC for {currencyCode}'**
  String p2pBookEmptySell(String currencyCode);

  /// Empty book for any filter but « Sell » (RoboSats tests type 0, else this text). {currencyCode} is the currency code or « ANY ».
  ///
  /// In en, this message translates to:
  /// **'No orders found to buy BTC for {currencyCode}'**
  String p2pBookEmptyBuy(String currencyCode);

  /// Below the empty book message, in the primary colour.
  ///
  /// In en, this message translates to:
  /// **'Be the first one to create an order'**
  String get p2pBookEmptyBeFirst;

  /// Caption under the long name of the coordinator that hosts the order.
  ///
  /// In en, this message translates to:
  /// **'Order host'**
  String get p2pOrderHost;

  /// Label of the order number (shown after a # sign). « Numéro » in French rather than the English abbreviation.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get p2pOrderId;

  /// RoboSats shows only the initial of this word before the maker fee in the fee row: the first character of the translation is used.
  ///
  /// In en, this message translates to:
  /// **'Maker'**
  String get p2pOrderFeeMaker;

  /// Tooltip of the maker fee in the fee row.
  ///
  /// In en, this message translates to:
  /// **'Maker fee'**
  String get p2pOrderFeeMakerTooltip;

  /// RoboSats shows only the initial of this word before the taker fee in the fee row.
  ///
  /// In en, this message translates to:
  /// **'Taker'**
  String get p2pOrderFeeTaker;

  /// Tooltip of the taker fee in the fee row.
  ///
  /// In en, this message translates to:
  /// **'Taker fee'**
  String get p2pOrderFeeTakerTooltip;

  /// Tooltip of the green on-chain fee chip of the fee row. Spelled « on-chain » as in the wallet.
  ///
  /// In en, this message translates to:
  /// **'Onchain payouts enabled'**
  String get p2pOrderOnchainEnabled;

  /// Tooltip of the grey on-chain icon of the fee row. Spelled « on-chain » as in the wallet.
  ///
  /// In en, this message translates to:
  /// **'Onchain payouts disabled'**
  String get p2pOrderOnchainDisabled;

  /// Heading of the order details.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get p2pOrderDetailsDivider;

  /// Caption of a range amount on the order page (RoboSats leaves it untranslated). « Fourchette » in French.
  ///
  /// In en, this message translates to:
  /// **'Amount Range'**
  String get p2pOrderAmountRange;

  /// Seen by the taker who buys bitcoin. {method} is the maker's payment method text, {amount} the amount with its currency code.
  ///
  /// In en, this message translates to:
  /// **'You send via {method} {amount}'**
  String p2pOrderYouSendVia(String method, String amount);

  /// Seen by the taker who buys bitcoin: sats estimated with the taker fee and a 0.1 % routing budget; {amount} can be a range « min-max ».
  ///
  /// In en, this message translates to:
  /// **'You receive {amount} Sats (Approx)'**
  String p2pOrderYouReceiveSats(String amount);

  /// Seen by the taker who sells bitcoin: sats estimated with the taker fee.
  ///
  /// In en, this message translates to:
  /// **'You send via Lightning {amount} Sats (Approx)'**
  String p2pOrderYouSendLightning(String amount);

  /// Seen by the taker who sells bitcoin. {method} is the maker's payment method text, {amount} the amount with its currency code.
  ///
  /// In en, this message translates to:
  /// **'You receive via {method} {amount}'**
  String p2pOrderYouReceiveVia(String method, String amount);

  /// Caption of the payment methods when the currency is BTC (swap order).
  ///
  /// In en, this message translates to:
  /// **'Swap destination'**
  String get p2pOrderSwapDestination;

  /// Caption of the payment methods of the order.
  ///
  /// In en, this message translates to:
  /// **'Accepted payment methods'**
  String get p2pOrderAcceptedMethods;

  /// Price per bitcoin and premium. French typography adds spaces before « : » and « % ».
  ///
  /// In en, this message translates to:
  /// **'{price} {currencyCode}/BTC - Premium: {premium}%'**
  String p2pOrderPriceAndPremiumValue(
    String price,
    String currencyCode,
    String premium,
  );

  /// Caption when the current price is known.
  ///
  /// In en, this message translates to:
  /// **'Price and Premium'**
  String get p2pOrderPriceAndPremium;

  /// Caption of an order priced in sats when the current price is unknown.
  ///
  /// In en, this message translates to:
  /// **'Amount of Satoshis'**
  String get p2pOrderAmountOfSatoshis;

  /// Caption when the current price is unknown (value « x% »).
  ///
  /// In en, this message translates to:
  /// **'Premium over market price'**
  String get p2pOrderPremiumOverMarket;

  /// Caption of the live countdown (orange under 25 % of the time left, red under 10 %, bold under 25 %).
  ///
  /// In en, this message translates to:
  /// **'Expires in'**
  String get p2pOrderExpiresIn;

  /// Replaces the countdown when it reaches zero.
  ///
  /// In en, this message translates to:
  /// **'The order has expired'**
  String get p2pOrderExpired;

  /// Time left to the parties to lock the escrow once the order is taken (« 3h »).
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get p2pOrderDeposit;

  /// Button of the order page. Taking an order comes in phase 2: in phase 1 the button is shown disabled.
  ///
  /// In en, this message translates to:
  /// **'Take Order'**
  String get p2pTakeOrder;

  /// A coordinator that does not answer: in the book, next to its name.
  ///
  /// In en, this message translates to:
  /// **'Coordinator offline'**
  String get p2pCoordinatorOffline;

  /// Not in the RoboSats texts: caption under the maker's nickname at the bottom of the order details, as in the validated mock-up.
  ///
  /// In en, this message translates to:
  /// **'Order maker'**
  String get p2pOrderMaker;

  /// Not in the RoboSats texts: asks again the coordinators whose book failed, or restarts Tor after a connection error.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get p2pCommonRetry;

  /// Not in the RoboSats texts (#73, asked by the owner): the line under the row of the coordinators' images above the book, while some coordinators are still awaited, and quietly once all of them answered (« 6 of 6 coordinators answered »).
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =1{{answered} of 1 coordinator answered} other{{answered} of {total} coordinators answered}}'**
  String p2pBookCoordinatorsAnswered(int answered, int total);

  /// Not in the RoboSats texts (#73): the same line, next to « Retry », once no coordinator is awaited any more and some gave no book after their last attempt.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 coordinator offline} other{{count} coordinators offline}}'**
  String p2pBookCoordinatorsOffline(int count);

  /// Not in the RoboSats texts (#73): what a screen reader says of a coordinator's image in the row above the book once its book has arrived; {name} is the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'{name}, answered'**
  String p2pBookCoordinatorAnswered(String name);

  /// Not in the RoboSats texts (#73): the same, while its book is being requested or the coordinator is about to be asked again.
  ///
  /// In en, this message translates to:
  /// **'{name}, awaited'**
  String p2pBookCoordinatorAwaited(String name);

  /// Not in the RoboSats texts (#73): the same, once the coordinator gave no book after its last attempt.
  ///
  /// In en, this message translates to:
  /// **'{name}, offline'**
  String p2pBookCoordinatorOffline(String name);

  /// Hours of a duration: the expiry ring of the book and the deposit time of an order. RoboSats writes `5h` in code, without translation.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String p2pDurationHours(String hours);

  /// Minutes of a duration under one hour: the expiry ring of the book and the deposit time. RoboSats writes `12m` in code.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String p2pDurationMinutes(String minutes);

  /// A deposit time of hours and minutes. RoboSats writes `1h 30m` in code; {minutes} has two digits.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String p2pDurationHoursMinutes(String hours, String minutes);

  /// The live countdown of an order: RoboSats writes `{h}h {mm}m {ss}s` in code; {minutes} and {seconds} have two digits.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m {seconds}s'**
  String p2pCountdownHms(String hours, String minutes, String seconds);

  /// Stands for payment methods written by the maker that are not in the official list.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get p2pBookOthers;

  /// Title of the dialog opened by the orange warning next to the payment methods of an order whose methods the community reports as reversible (PIX, Revolut…).
  ///
  /// In en, this message translates to:
  /// **'Reversible payments'**
  String get p2pReversibleTitle;

  /// First paragraph of the reversible payments dialog, followed by the names of the reversible methods of the order.
  ///
  /// In en, this message translates to:
  /// **'This order offers one or multiple payment methods that the community has consistently reported as reverting their transactions.'**
  String get p2pReversibleIntro;

  /// First point of the reversible payments dialog, in bold. The English typo « unilatery » is RoboSats' own and kept.
  ///
  /// In en, this message translates to:
  /// **'If you receive a fiat transaction, it can be unilatery reverted up to 80 days after the trade has been completed.'**
  String get p2pReversible80Days;

  /// Second point of the reversible payments dialog.
  ///
  /// In en, this message translates to:
  /// **'Robosats and their coordinators have no control over the fiat system.'**
  String get p2pReversibleNoControl;

  /// Third point of the reversible payments dialog.
  ///
  /// In en, this message translates to:
  /// **'Scammers can exploit this vulnerability in the fiat system to take away both your bitcoin and your fiat.'**
  String get p2pReversibleScammers;

  /// Button that closes a warning the user has read.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get p2pCommonAcknowledged;

  /// Title of the box that holds the notice of a coordinator, free text it writes (usually in English), shown in the coordinator dialog when its severity is not « none ».
  ///
  /// In en, this message translates to:
  /// **'Coordinator Notice'**
  String get p2pCoordinatorNotice;

  /// Tooltip of the founder badge of the coordinator dialog, when lit.
  ///
  /// In en, this message translates to:
  /// **'Founder: coordinating trades since the testnet federation.'**
  String get p2pCoordinatorBadgeFounder;

  /// Tooltip of the founder badge, greyed out.
  ///
  /// In en, this message translates to:
  /// **'Not a federation founder'**
  String get p2pCoordinatorBadgeNotFounder;

  /// Tooltip of the development fund badge, lit from 20 %. {percent} is the share the coordinator gives, a number written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'Development fund supporter: donates {percent}% to make RoboSats better.'**
  String p2pCoordinatorBadgeDevFund(String percent);

  /// Tooltip of the privacy badge, when lit.
  ///
  /// In en, this message translates to:
  /// **'Good OpSec: the coordinator follows best practices to protect his and your privacy.'**
  String get p2pCoordinatorBadgeGoodOpsec;

  /// Tooltip of the privacy badge, greyed out.
  ///
  /// In en, this message translates to:
  /// **'The privacy practices of this coordinator could improve'**
  String get p2pCoordinatorBadgeOpsecCouldImprove;

  /// Tooltip of the limits badge, lit when the size limit of the coordinator is above 3 million sats.
  ///
  /// In en, this message translates to:
  /// **'Large limits: the coordinator has large trade limits.'**
  String get p2pCoordinatorBadgeLargeLimits;

  /// Tooltip of the limits badge, greyed out.
  ///
  /// In en, this message translates to:
  /// **'Does not have large trade limits.'**
  String get p2pCoordinatorBadgeNoLargeLimits;

  /// Caption under the description of the coordinator, free text of the federation list.
  ///
  /// In en, this message translates to:
  /// **'Coordinator description'**
  String get p2pCoordinatorDescription;

  /// Caption under the date the coordinator joined the federation.
  ///
  /// In en, this message translates to:
  /// **'Established'**
  String get p2pCoordinatorEstablished;

  /// Caption under the onion address of the web client of the coordinator.
  ///
  /// In en, this message translates to:
  /// **'Coordinator hosted web app'**
  String get p2pCoordinatorHostedWebApp;

  /// Section of the coordinator dialog that opens on its policies, free text of the federation list.
  ///
  /// In en, this message translates to:
  /// **'Policies'**
  String get p2pCoordinatorPolicies;

  /// Section of the coordinator dialog that opens on its limits, fees and book.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get p2pCoordinatorSummary;

  /// Caption under « {amount} Sats » in the summary of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Maximum order size'**
  String get p2pCoordinatorMaxOrderSize;

  /// Caption under « Onchain payouts disabled » in the summary of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Current onchain payout status'**
  String get p2pCoordinatorOnchainStatus;

  /// Caption under the on-chain payout fee, a percentage, in the summary of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Current onchain payout fee'**
  String get p2pCoordinatorCurrentOnchainFee;

  /// Caption under « {amount} Sats » when on-chain payouts are enabled.
  ///
  /// In en, this message translates to:
  /// **'Maximum onchain swap size'**
  String get p2pCoordinatorMaxSwapSize;

  /// Caption under the share of its profits a coordinator gives to the development fund.
  ///
  /// In en, this message translates to:
  /// **'Zaps voluntarily for development'**
  String get p2pCoordinatorDevFundZaps;

  /// Share of its profits a coordinator gives to the development fund; RoboSats writes it without translation. {percent} is a number written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of profits'**
  String p2pCoordinatorDevFundPercent(String percent);

  /// Caption under the number of public buy orders of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Public buy orders'**
  String get p2pCoordinatorPublicBuyOrders;

  /// Caption under the number of public sell orders of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Public sell orders'**
  String get p2pCoordinatorPublicSellOrders;

  /// Caption under the sats of all the public orders of a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Book liquidity'**
  String get p2pCoordinatorBookLiquidity;

  /// Caption under the number of robots active today on a coordinator.
  ///
  /// In en, this message translates to:
  /// **'Today active robots'**
  String get p2pCoordinatorActiveRobotsToday;

  /// Caption under the average premium of the last 24 hours on a coordinator.
  ///
  /// In en, this message translates to:
  /// **'24h non-KYC bitcoin premium'**
  String get p2pCoordinatorNonKycPremium;

  /// Caption under the price sources of a coordinator, a list of URLs it writes.
  ///
  /// In en, this message translates to:
  /// **'Market price sources (for multiple the median is calculated)'**
  String get p2pCoordinatorPriceSources;

  /// Section of the coordinator dialog that opens on its versions, node, commit and volumes.
  ///
  /// In en, this message translates to:
  /// **'Stats for Nerds'**
  String get p2pCoordinatorStatsForNerds;

  /// Word before the version of the coordinator, « Coordinator v0.8.8 »; RoboSats adds the version of its own client, which Troc leaves out.
  ///
  /// In en, this message translates to:
  /// **'Coordinator'**
  String get p2pCoordinatorVersionCoordinator;

  /// Caption under « Coordinator v0.8.8 ».
  ///
  /// In en, this message translates to:
  /// **'RoboSats version'**
  String get p2pCoordinatorRoboSatsVersion;

  /// Caption under the LND version of a coordinator, text it writes.
  ///
  /// In en, this message translates to:
  /// **'LND version'**
  String get p2pCoordinatorLndVersion;

  /// Caption under the Core Lightning version of a coordinator, text it writes (often « Not installed »).
  ///
  /// In en, this message translates to:
  /// **'CLN version'**
  String get p2pCoordinatorClnVersion;

  /// Caption under the Lightning node of a testnet coordinator; on mainnet the alias is shown alone, as in RoboSats. {alias} is the node alias, text the coordinator writes. Composed by RoboSats from « LN Node » and the alias.
  ///
  /// In en, this message translates to:
  /// **'LN Node: {alias}'**
  String p2pCoordinatorLnNodeAlias(String alias);

  /// Caption under the Git commit the coordinator runs.
  ///
  /// In en, this message translates to:
  /// **'Coordinator commit hash'**
  String get p2pCoordinatorCommitHash;

  /// Caption under the BTC traded on a coordinator in the last 24 hours.
  ///
  /// In en, this message translates to:
  /// **'24h contracted volume'**
  String get p2pCoordinatorVolume24h;

  /// Caption under the BTC traded on a coordinator since it started.
  ///
  /// In en, this message translates to:
  /// **'Lifetime contracted volume'**
  String get p2pCoordinatorVolumeLifetime;

  /// An amount of sats: in the summary of a coordinator, such as its maximum order size, and the amount of a swap order, given in BTC, which the official client writes in sats (`btcToSatsString`). RoboSats writes it without translation. {amount} is a number of sats written in the conventions of the language, or a range « min-max ».
  ///
  /// In en, this message translates to:
  /// **'{amount} Sats'**
  String p2pAmountSats(String amount);

  /// Contact button of a coordinator: Troc shows the address, to copy, and never opens a mail app.
  ///
  /// In en, this message translates to:
  /// **'Send Email'**
  String get p2pCoordinatorSendEmail;

  /// Contact button of a coordinator: Troc shows the address, to copy, and never opens a browser.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get p2pCoordinatorWebsite;

  /// Contact button of a coordinator: Troc shows the fingerprint of its OpenPGP key in groups of four. RoboSats offers to download the key, which Troc does not ship.
  ///
  /// In en, this message translates to:
  /// **'PGP Pubkey fingerprint'**
  String get p2pCoordinatorPgpFingerprint;

  /// Contact button of a coordinator, a brand name: Troc shows its public key, to copy, and never opens a Nostr gateway.
  ///
  /// In en, this message translates to:
  /// **'Nostr'**
  String get p2pCoordinatorNostr;

  /// Contact button of a coordinator, a brand name: Troc shows the link RoboSats opens, to copy.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get p2pCoordinatorTelegram;

  /// Contact button of a coordinator, a brand name: Troc shows the link RoboSats opens, to copy.
  ///
  /// In en, this message translates to:
  /// **'X'**
  String get p2pCoordinatorX;

  /// Contact button of a coordinator, a brand name: Troc shows the link RoboSats opens, to copy.
  ///
  /// In en, this message translates to:
  /// **'Reddit'**
  String get p2pCoordinatorReddit;

  /// Contact button of a coordinator, a brand name: Troc shows the channel, to copy.
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get p2pCoordinatorMatrix;

  /// Contact button of a coordinator, a brand name spelt as RoboSats does: Troc shows the link RoboSats opens, to copy.
  ///
  /// In en, this message translates to:
  /// **'Simplex'**
  String get p2pCoordinatorSimplex;

  /// Shown once a value is on the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get p2pCommonCopied;

  /// Title of the dialog opened by « Search » below the book.
  ///
  /// In en, this message translates to:
  /// **'Search order'**
  String get p2pSearchOrderTitle;

  /// Text of the « Search order » dialog; written in the RoboSats code only, absent from its translation files. Troc opens only an order of the public book until the Garage brings robots.
  ///
  /// In en, this message translates to:
  /// **'Enter here an order URL to search for it, even if it\'s password protected'**
  String get p2pSearchOrderText;

  /// Label of the field of « Search order », which turns red, without a text, when the URL is not …/order/<coordinator>/<id>.
  ///
  /// In en, this message translates to:
  /// **'Order URL'**
  String get p2pSearchOrderUrlLabel;

  /// Button that closes a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get p2pCommonCancel;

  /// Title of the dialog shown when a page needs a robot, such as an order searched by its URL that is not in the public book.
  ///
  /// In en, this message translates to:
  /// **'You do not have a Garage Key'**
  String get p2pNoRobotTitle;

  /// Text of the dialog shown when a page needs a robot.
  ///
  /// In en, this message translates to:
  /// **'Generate a Garage Key to get your first robot identity and start trading.'**
  String get p2pNoRobotText;

  /// Button of the no-robot dialog that leads to the Garage; disabled until the Garage exists.
  ///
  /// In en, this message translates to:
  /// **'I have a Garage Key'**
  String get p2pNoRobotHaveKey;

  /// Button that generates a Garage Key, in the no-robot dialog and the Garage; disabled until the Garage exists.
  ///
  /// In en, this message translates to:
  /// **'Generate Garage Key'**
  String get p2pGarageOnboardingGenerateKey;

  /// Title of the sheet that shows the link of the Lightning node of a coordinator (1ML on testnet, Amboss on mainnet), to copy.
  ///
  /// In en, this message translates to:
  /// **'LN Node'**
  String get p2pCoordinatorLnNode;

  /// The version of the coordinator, « Coordinator v0.8.8 », as RoboSats composes it; RoboSats adds the version of its own client, which Troc leaves out. {name} is the word « Coordinator », {version} the version it announces.
  ///
  /// In en, this message translates to:
  /// **'{name} v{version}'**
  String p2pCoordinatorVersionValue(String name, String version);

  /// The first 12 characters of the Lightning node key of a mainnet coordinator, followed by the name of the explorer the link leads to, as RoboSats writes it. {node} is hexadecimal.
  ///
  /// In en, this message translates to:
  /// **'{node}... (AMBOSS)'**
  String p2pCoordinatorNodeAmboss(String node);

  /// The first 12 characters of the Lightning node key of a testnet coordinator, followed by the name of the explorer the link leads to, as RoboSats writes it. {node} is hexadecimal.
  ///
  /// In en, this message translates to:
  /// **'{node}... (1ML)'**
  String p2pCoordinatorNode1ml(String node);

  /// The first 12 characters of the commit a coordinator runs, as RoboSats writes it. {commit} is text the coordinator writes.
  ///
  /// In en, this message translates to:
  /// **'{commit}...'**
  String p2pCoordinatorCommitShort(String commit);

  /// Label of a copy button: its tooltip, and what a screen reader announces.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get p2pCommonCopy;

  /// Choice of the horizontal axis of the depth chart, and header of the price column of the book in RoboSats.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get p2pBookColumnPrice;

  /// Not in the RoboSats texts, which writes it in code: legend of the vertical axis of the depth chart, the bitcoin the orders add up to.
  ///
  /// In en, this message translates to:
  /// **'BTC'**
  String get p2pChartBtc;

  /// Not in the RoboSats texts, whose button is an icon only: tooltip and screen-reader label of the « − » button of the depth chart, which widens its window, and of the « − » button of the map, which zooms out one level (the title of Leaflet's zoom control, in English only in the official client).
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get p2pChartZoomOut;

  /// Not in the RoboSats texts, whose button is an icon only: tooltip and screen-reader label of the « + » button of the depth chart, which narrows its window, and of the « + » button of the map, which zooms in one level (the title of Leaflet's zoom control, in English only in the official client).
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get p2pChartZoomIn;

  /// Not in the RoboSats texts, which composes it in code: the price at the centre of the depth chart on its price axis, between its zoom buttons. {price} is a price written in the conventions of the language, {currencyCode} a currency code such as EUR.
  ///
  /// In en, this message translates to:
  /// **'{price} {currencyCode}'**
  String p2pChartCenterPrice(String price, String currencyCode);

  /// Not in the RoboSats texts: part of the screen-reader summary of the depth chart and of the map, the number of orders of makers who buy that the chart, or the map, shows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 buy order} other{{count} buy orders}}'**
  String p2pChartBuyOrders(int count);

  /// Not in the RoboSats texts: part of the screen-reader summary of the depth chart and of the map, the number of orders of makers who sell that the chart, or the map, shows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sell order} other{{count} sell orders}}'**
  String p2pChartSellOrders(int count);

  /// Not in the RoboSats texts: what a screen reader says of the depth chart, which it cannot read. {center} is the value between the zoom buttons, such as « 2.00% » or « 93,330 EUR »; {buyOrders} and {sellOrders} are the two counts above.
  ///
  /// In en, this message translates to:
  /// **'Depth chart centered on {center}: {buyOrders} and {sellOrders}.'**
  String p2pChartSummary(String center, String buyOrders, String sellOrders);

  /// Not in the RoboSats texts: what a screen reader says of the depth chart when its axis cannot be drawn, such as the price axis when no order gives a market price in its currency.
  ///
  /// In en, this message translates to:
  /// **'Depth chart: nothing to draw on this axis.'**
  String get p2pChartSummaryNoAxis;

  /// Not in the RoboSats texts, whose map then shows no pin and says nothing: written over the map, and said by a screen reader, when no order it would show has a location. « Face to Face Location » is RoboSats' name for the position a maker sets (« Emplacement face à face »).
  ///
  /// In en, this message translates to:
  /// **'No order with a face to face location'**
  String get p2pMapNoLocation;

  /// Not in the RoboSats texts: what a screen reader says of the map before its pins and groups. {buyOrders} and {sellOrders} are the counts of p2pChartBuyOrders and p2pChartSellOrders, the orders with a location the map shows.
  ///
  /// In en, this message translates to:
  /// **'Map of the face to face locations: {buyOrders} and {sellOrders}. These orders are in the list too.'**
  String p2pMapSummary(String buyOrders, String sellOrders);

  /// Not in the RoboSats texts, whose groups show their count only: what a screen reader says of a group of pins on the map, and the title of the list of its orders, which a tap on a group that zooming cannot part opens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order here} other{{count} orders here}}'**
  String p2pMapOrdersHere(int count);

  /// Not in the RoboSats texts: what a screen reader says of the pin of an order on the map. {role} is p2pBookRoleSeller or p2pBookRoleBuyer, {amount} the amount or range of the order written in the conventions of the language, {currencyCode} its currency code, {coordinator} the name of its coordinator.
  ///
  /// In en, this message translates to:
  /// **'{role}, {amount} {currencyCode}, {coordinator}'**
  String p2pMapPin(
    String role,
    String amount,
    String currencyCode,
    String coordinator,
  );

  /// Button that moves on to the next step of the Garage wizard.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get p2pCommonContinue;

  /// Subtitle of the Garage welcome screen, where RoboSats shows its logo.
  ///
  /// In en, this message translates to:
  /// **'A Simple and Private LN P2P Exchange'**
  String get p2pGarageWelcomeTagline;

  /// Text of the box above « Start » on the Garage welcome screen.
  ///
  /// In en, this message translates to:
  /// **'Create a new robot and learn to use RoboSats'**
  String get p2pGarageWelcomeCreateRobot;

  /// Button of the Garage welcome screen: opens the three-step Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get p2pGarageWelcomeStart;

  /// Text above « Recovery » on the Garage welcome screen. RoboSats keeps « token » in Garage Key mode; the French text says « clé de garage » (decision of 2026-11-10).
  ///
  /// In en, this message translates to:
  /// **'Recover an existing robot using your token'**
  String get p2pGarageWelcomeRecoverHint;

  /// Text button of the Garage welcome screen: opens « Robot recovery », where the user pastes a Garage Key.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get p2pGarageWelcomeRecovery;

  /// Text button of the Garage welcome screen: shows the offers (RoboSats opens its guided search, which Troc does not have).
  ///
  /// In en, this message translates to:
  /// **'Search for Orders'**
  String get p2pGarageWelcomeSearchForOrders;

  /// Text button of the Garage welcome screen, disabled: creating an order comes in a later phase.
  ///
  /// In en, this message translates to:
  /// **'Fast Generate Order'**
  String get p2pGarageWelcomeFastGenerateOrder;

  /// Title of the first step of the Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'1. Generate your Garage Key'**
  String get p2pGarageOnboardingStep1Title;

  /// Text of the first step of the Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'Your Garage Key is a master key that derives unlimited robot identities. Generate it once and use it forever.'**
  String get p2pGarageOnboardingStep1Text;

  /// Bold start of the alert shown with a new Garage Key: the key is never part of the wallet backup.
  ///
  /// In en, this message translates to:
  /// **'Store it somewhere safe!'**
  String get p2pGarageOnboardingStoreItTitle;

  /// Rest of the alert shown with a new Garage Key.
  ///
  /// In en, this message translates to:
  /// **'This key is the master key to all your robots. Keep it secret and backed up securely.'**
  String get p2pGarageOnboardingStoreItText;

  /// Helper text under the Garage Key, in the wizard and on the profile.
  ///
  /// In en, this message translates to:
  /// **'Store your Garage Key safely'**
  String get p2pGarageKeyHelper;

  /// Error under the Garage Key field when what was typed is not a Garage Key and no more precise reason applies.
  ///
  /// In en, this message translates to:
  /// **'Invalid garage key'**
  String get p2pGarageKeyInvalid;

  /// Text of the first step of the wizard, about pasting a Garage Key the user already has.
  ///
  /// In en, this message translates to:
  /// **'Or paste an existing Garage Key to recover your robots.'**
  String get p2pGarageOnboardingPasteExisting;

  /// Small button with a die: replaces the Garage Key, after the delete confirmation when one is stored.
  ///
  /// In en, this message translates to:
  /// **'Generate new'**
  String get p2pGarageOnboardingGenerateNew;

  /// Title of the second step of the Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'2. Meet your robot identity'**
  String get p2pGarageOnboardingStep2Title;

  /// Text of the second step of the wizard, above the robot's avatar, and its label on the profile.
  ///
  /// In en, this message translates to:
  /// **'This is your trading avatar'**
  String get p2pGarageTradingAvatar;

  /// Followed by the robot's nickname, in bold between two bolts.
  ///
  /// In en, this message translates to:
  /// **'Hi! My name is'**
  String get p2pGarageHiMyNameIs;

  /// Tooltip and screen-reader label of the left arrow of the « Robot #N » navigator.
  ///
  /// In en, this message translates to:
  /// **'Previous account'**
  String get p2pGaragePreviousAccount;

  /// Tooltip and screen-reader label of the right arrow of the « Robot #N » navigator.
  ///
  /// In en, this message translates to:
  /// **'Next account'**
  String get p2pGarageNextAccount;

  /// Word before « #N » in the robot navigator (« Robot #3 »).
  ///
  /// In en, this message translates to:
  /// **'Robot'**
  String get p2pGarageRobotLabel;

  /// Title of the third step of the Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'3. Browse or create an order'**
  String get p2pGarageOnboardingStep3Title;

  /// Text of the third step of the Garage Key wizard.
  ///
  /// In en, this message translates to:
  /// **'RoboSats is a peer-to-peer marketplace. You can browse the public offers or create a new one.'**
  String get p2pGarageOnboardingStep3Text;

  /// Start of the help sentence of the third step, followed by the link p2pGarageOnboardingHelpLink.
  ///
  /// In en, this message translates to:
  /// **'If you need help on your RoboSats journey join our public support'**
  String get p2pGarageOnboardingHelpIntro;

  /// Name of the public RoboSats support group: shown with its link for copy, never opened.
  ///
  /// In en, this message translates to:
  /// **'SimpleX group'**
  String get p2pGarageOnboardingHelpLink;

  /// End of the help sentence of the third step, after « , ».
  ///
  /// In en, this message translates to:
  /// **'or visit the robot school for documentation.'**
  String get p2pGarageOnboardingHelpOutro;

  /// Button of the third step: shows the address of the RoboSats documentation for copy, never opened.
  ///
  /// In en, this message translates to:
  /// **'Learn RoboSats'**
  String get p2pGarageLearnRoboSats;

  /// Text button of the third step: opens the Garage profile.
  ///
  /// In en, this message translates to:
  /// **'See profile'**
  String get p2pGarageSeeProfile;

  /// Caption of the box that holds the Garage Key on the profile.
  ///
  /// In en, this message translates to:
  /// **'Garage Key'**
  String get p2pGarageKeyLabel;

  /// Tooltip of the red « Delete All » button of the profile.
  ///
  /// In en, this message translates to:
  /// **'Delete Garage Key and all robots'**
  String get p2pGarageProfileDeleteAllTooltip;

  /// Red button of the profile: opens « Delete Garage Key? ».
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get p2pGarageProfileDeleteAll;

  /// Title of the dialog where the user pastes a Garage Key to recover their robots.
  ///
  /// In en, this message translates to:
  /// **'Robot recovery'**
  String get p2pRecoveryTitle;

  /// Chip next to the title of « Robot recovery ».
  ///
  /// In en, this message translates to:
  /// **'Garage Key Mode'**
  String get p2pRecoveryModeGarageKey;

  /// Text of « Robot recovery »; « robo1... » is the literal start of a key, never translated.
  ///
  /// In en, this message translates to:
  /// **'Enter your garage key (robo1...) to recover all your robot accounts.'**
  String get p2pRecoveryGarageKeyText;

  /// Label of the field where the Garage Key is pasted, as RoboSats words it in both of its modes.
  ///
  /// In en, this message translates to:
  /// **'Paste token here'**
  String get p2pRecoveryPasteHere;

  /// Shown with a progress bar while the pasted key is stored.
  ///
  /// In en, this message translates to:
  /// **'Recovering your robot. This may take a moment.'**
  String get p2pRecoveryInProgress;

  /// Button of « Robot recovery », disabled until the field holds a Garage Key.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get p2pRecoveryRecover;

  /// Title of the confirmation before deleting the Garage Key of this network.
  ///
  /// In en, this message translates to:
  /// **'Delete Garage Key?'**
  String get p2pDeleteKeyTitle;

  /// Question of the delete confirmation; the capitals are RoboSats's own.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete this Garage Key and ALL associated robots?'**
  String get p2pDeleteKeyQuestion;

  /// Warning of the delete confirmation, with RoboSats's own emoji.
  ///
  /// In en, this message translates to:
  /// **'⚠️ This action cannot be undone!'**
  String get p2pDeleteCannotBeUndone;

  /// Followed by three bullet points.
  ///
  /// In en, this message translates to:
  /// **'Before deleting, make sure you have:'**
  String get p2pDeleteBeforeDeleting;

  /// First bullet point: the key is not part of the wallet backup.
  ///
  /// In en, this message translates to:
  /// **'Stored your Garage Key safely'**
  String get p2pDeleteKeyStoredKey;

  /// Second bullet point.
  ///
  /// In en, this message translates to:
  /// **'No active or pending orders in ANY robot'**
  String get p2pDeleteKeyNoActiveOrders;

  /// Third bullet point.
  ///
  /// In en, this message translates to:
  /// **'Exported any important data'**
  String get p2pDeleteExportedData;

  /// Red confirmation button of the delete confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete Garage Key'**
  String get p2pDeleteKeyConfirm;

  /// Error under the Garage Key field: the text of RoboSats's validator, which it never translates. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Must start with \"robo1\"'**
  String get p2pGarageKeyMustStartWith;

  /// Error under the Garage Key field when the text is not 55 to 65 characters long: the text of RoboSats's validator. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Invalid length'**
  String get p2pGarageKeyInvalidLength;

  /// Error under the Garage Key field when the text does not hold 32 bytes: the text of RoboSats's validator. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Invalid key data'**
  String get p2pGarageKeyInvalidData;

  /// Button of the profile: asks for the wallet's PIN, then shows the Garage Key. RoboSats shows the key at once; Troc hides it until the user authenticates again (owner's decision). Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Show Garage Key'**
  String get p2pGarageKeyReveal;

  /// Shown instead of the Garage Key when screenshot protection could not be turned on, as the wallet does for its seeds (screenPrivacyUnavailable). Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Screen protection could not be turned on, so the Garage Key stays hidden.'**
  String get p2pGarageScreenPrivacyUnavailable;

  /// The device's keystore is locked: a stored key, if any, is intact. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'The keystore is locked. Unlock your device, then try again.'**
  String get p2pGarageKeyLocked;

  /// The vault could not read the entry of this network. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'The Garage Key stored on this device cannot be read.'**
  String get p2pGarageKeyUnreadable;

  /// The entry of this network is there but is not a Garage Key. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'The Garage Key stored on this device is damaged.'**
  String get p2pGarageKeyUnusable;

  /// Under an unreadable or damaged key, above « Retry » and « Delete Garage Key ». Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Try again. If it keeps failing, delete it: the key and its robots are lost unless you kept a copy.'**
  String get p2pGarageKeyUnreadableHelp;

  /// The keystore did not store the new or pasted key. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'The Garage Key could not be saved. Try again.'**
  String get p2pGarageKeyNotSaved;

  /// The keystore did not delete the key: it may still be stored. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'The Garage Key could not be deleted. Try again.'**
  String get p2pGarageKeyNotDeleted;

  /// A key is already stored: it is never replaced without the delete confirmation. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'A Garage Key is already stored for this network.'**
  String get p2pGarageKeyAlreadyStored;

  /// No usable robot index was found from this key, which does not happen with a key drawn at random. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'No robot can be made from this Garage Key.'**
  String get p2pGarageRobotUnavailable;

  /// Button next to the Garage Key field: reads the clipboard once and puts its text in the field. It replaces the field's long-press menu, which Troc removes so that a key is never copied, shared or translated from it. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get p2pCommonPaste;

  /// Button next to the Garage Key field: empties it. Not in the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get p2pCommonClear;

  /// Warning on the robot step of the wizard and on the profile, right after « Generate Garage Key » or « Generate new » when the feature's database could not record that the key was drawn on this device: the key is stored, but its history is unknown, as for a key from elsewhere, so « Select Host » asks « Robots from elsewhere » (p2pRobotHistoryTitle) before its robots can reach a coordinator, and its delete asks the PIN. Not in the phase-1 catalogue (design note of #29, § 2.4).
  ///
  /// In en, this message translates to:
  /// **'This device could not record that it drew this Garage Key. Its robots will ask for your confirmation before they reach a coordinator. You can generate a new key instead.'**
  String get p2pGarageKeyHistoryNotRecorded;

  /// Title of the panel under the robot navigator of the Garage profile. The RoboSats profile dialog says « Coordinators that know your robot: » (`components/Dialogs/Profile.tsx`); in Troc a robot lives on one coordinator only, hence the singular. French from the RoboSats French text, in the singular.
  ///
  /// In en, this message translates to:
  /// **'Coordinator that knows your robot:'**
  String get p2pRobotCoordinatorTitle;

  /// Panel of a robot that no coordinator received from this device. Not in the RoboSats texts (design note of #29, § 2.2). Choosing a coordinator here is optional: nothing says a robot must be sent before trading.
  ///
  /// In en, this message translates to:
  /// **'No coordinator knows this robot yet.'**
  String get p2pRobotNoCoordinator;

  /// Button of the panel of a robot without a coordinator, and title of the sheet that lists the coordinators: the RoboSats label of a coordinator choice (`components/BookTable/BookControl.tsx`). French as the book filter « Select Host » (RoboSats French corrected).
  ///
  /// In en, this message translates to:
  /// **'Select Host'**
  String get p2pRobotSelectHost;

  /// Tooltip and screen reader label of the info button of a coordinator in the « Select Host » sheet, which opens the coordinator dialog. Not in the RoboSats texts, where the avatar opens it without a label. {coordinator} is the long alias of the coordinator.
  ///
  /// In en, this message translates to:
  /// **'Details of {coordinator}'**
  String p2pRobotHostDetails(String coordinator);

  /// Title of the confirmation after a coordinator is chosen in « Select Host ». Not in the RoboSats texts (design note of #29, § 2.2). {nickname} is the robot nickname, {coordinator} the long alias of the coordinator.
  ///
  /// In en, this message translates to:
  /// **'Send {nickname} to {coordinator}?'**
  String p2pRobotSendTitle(String nickname, String coordinator);

  /// First paragraph of the confirmation. Not in the RoboSats texts (design note of #29, § 2.2): the official client sends every robot it shows to every coordinator.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} will know this robot from now on. In Troc a robot lives on one coordinator only: this robot will never be sent to another one. To trade elsewhere, use another robot.'**
  String p2pRobotSendBody(String coordinator);

  /// Second paragraph of the confirmation. Not in the RoboSats texts (design note of #29, § 2.2).
  ///
  /// In en, this message translates to:
  /// **'If you also use this Garage Key in another app, that app may send this robot to every coordinator.'**
  String get p2pRobotSendOtherApp;

  /// Shown with a progress bar during the first contact of a robot with the coordinator chosen. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Building your robot!'**
  String get p2pGarageBuildingRobot;

  /// Shown with a progress bar while a robot is read back from its coordinator. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`); its French says « commandes », the glossary says « ordres ».
  ///
  /// In en, this message translates to:
  /// **'Looking for orders!'**
  String get p2pRobotLookingForOrders;

  /// Added under the progress line when a request of a robot has run for 30 seconds. Not in the RoboSats texts (design note of #29, § 2.2).
  ///
  /// In en, this message translates to:
  /// **'Still waiting for {coordinator}. Tor can take a minute.'**
  String p2pRobotStillWaiting(String coordinator);

  /// The order the robot is the maker or the taker of, as its coordinator says; plain text, since Troc has no page for it yet. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`). {orderId} is the number of the order.
  ///
  /// In en, this message translates to:
  /// **'Active order #{orderId}'**
  String p2pRobotActiveOrder(String orderId);

  /// The last order of the robot, when it has none in progress, as its coordinator says; plain text. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`). {orderId} is the number of the order.
  ///
  /// In en, this message translates to:
  /// **'Last order #{orderId}'**
  String p2pRobotLastOrder(String orderId);

  /// The coordinator knows no order of the robot. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`); its French says « commande », the glossary says « ordre ».
  ///
  /// In en, this message translates to:
  /// **'No existing orders found'**
  String get p2pRobotNoOrders;

  /// Information when the robot has a last order and no active one: Troc does not read that order yet, so any last order counts as a trade, as RoboSats counts an unknown status. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`), French of the phase-1 catalogue.
  ///
  /// In en, this message translates to:
  /// **'This robot was involved in a trade. Navigate to a new account for fresh privacy.'**
  String get p2pRobotUsedInTrade;

  /// Caption above the sats a coordinator owes the robot, shown when there are some. RoboSats text (`components/RobotInfo/index.tsx`); claiming them comes later.
  ///
  /// In en, this message translates to:
  /// **'Your compensations'**
  String get p2pRobotRewards;

  /// After a first contact whose answer carried a key pair other than the one sent, proven by the robot. Not in the RoboSats texts (design note of #29, § 2.2). {coordinator} is the long alias of the coordinator.
  ///
  /// In en, this message translates to:
  /// **'This robot already existed on {coordinator}.'**
  String p2pRobotAlreadyExisted(String coordinator);

  /// Panel of a robot bound to a coordinator of the other network, which happens only when the same Garage Key is in both slots. Not in the RoboSats texts (design note of #29, § 2.2). {network} is « testnet » or « mainnet ».
  ///
  /// In en, this message translates to:
  /// **'This robot lives on a {network, select, testnet{testnet} other{mainnet}} coordinator.'**
  String p2pRobotOnOtherNetwork(String network);

  /// Under a coordinator of the « Select Host » sheet that refused three robots with a nickname already taken in this run of the app, which is then disabled. Not in the RoboSats texts (design note of #29, § 3.5).
  ///
  /// In en, this message translates to:
  /// **'This coordinator refused too many robots.'**
  String get p2pRobotCoordinatorTooManyRefusals;

  /// A robot request that kept finding the connection to the coordinator busy. Not in the RoboSats texts (design note of #29, § 2.3). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'Too many requests are waiting for this coordinator. Try again in a moment.'**
  String get p2pRobotBusy;

  /// A first contact refused with a nickname already taken (error 7004), still taken 10 seconds later. Not in the RoboSats texts (design note of #29, § 2.3). No button: the robot navigator gives the next robot.
  ///
  /// In en, this message translates to:
  /// **'This robot\'s name is already taken on {coordinator}, so it cannot be created there. Use the next robot.'**
  String p2pRobotNicknameTaken(String coordinator);

  /// A robot bound to the coordinator, which says it does not know it. Not in the RoboSats texts (design note of #29, § 2.3). With « Retry », which makes a new first contact to that coordinator.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not know this robot yet.'**
  String p2pRobotNotCreated(String coordinator);

  /// A first contact whose key the coordinator found less than 12 hours old (error 1056). Not in the RoboSats texts (design note of #29, § 2.3). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator} refused the robot\'s key as too recent. Check your phone\'s date and time, then try again.'**
  String p2pRobotKeyTooRecent(String coordinator);

  /// A coordinator that refused the keys or the credentials of the robot. Not in the RoboSats texts (design note of #29, § 2.3). No button: another robot.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} refused this robot. It may run another version of RoboSats.'**
  String p2pRobotRefused(String coordinator);

  /// An answer whose hash id or nickname is not the robot's, or whose key pair the robot's token does not prove. Not in the RoboSats texts (design note of #29, § 2.3). No button.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} answered with another robot, or with keys this robot did not make. Do not use this robot there.'**
  String p2pRobotMismatch(String coordinator);

  /// An answer of the coordinator that cannot be read. Not in the RoboSats texts (design note of #29, § 2.3). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator} sent an answer Troc cannot read.'**
  String p2pRobotBadAnswer(String coordinator);

  /// A robot bound to a coordinator whose address or keys in the federation list of the app changed since. Not in the RoboSats texts (design note of #29, § 2.3). No button.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} changed its address or keys since this robot was sent to it. Nothing was sent. Until an update of the app has checked the change, use another robot.'**
  String p2pRobotCoordinatorChanged(String coordinator);

  /// The feature's database could not be read or written. Not in the RoboSats texts (design note of #29, § 2.3). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'Troc could not read its records on this device. Nothing was sent.'**
  String get p2pRobotStorage;

  /// Warning on a robot whose coordinator holds the Nostr key of the first formula of the official client. Not in the RoboSats texts (design note of #29, § 2.3).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} holds an old Nostr key for this robot, which it can compute: its notifications are not private. Prefer another robot for trading.'**
  String p2pRobotNostrOld(String coordinator);

  /// Warning on a robot whose coordinator holds no Nostr key of this robot. Not in the RoboSats texts (design note of #29, § 2.3).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} holds a Nostr key this app cannot use: notifications about this robot will not reach it.'**
  String p2pRobotNostrUnknown(String coordinator);

  /// This device could not make or prove the OpenPGP key pair of a robot: its clock is outside the dates a key can hold, or the work could not start. Not in the RoboSats texts, nor in the design note of #29, whose table has no row for it. With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'This phone could not make or check the keys of this robot. Check its date and time, then try again.'**
  String get p2pRobotKeyComputeFailed;

  /// A request refused because the robot is bound to another coordinator. Not in the RoboSats texts, nor in the design note of #29: the panel never offers it, and shows where the robot lives instead.
  ///
  /// In en, this message translates to:
  /// **'This robot lives on another coordinator. Nothing was sent.'**
  String get p2pRobotBoundElsewhere;

  /// Under the text of a first contact that failed, when the feature's database cannot be read right after it: the request may have left, so, unlike p2pRobotStorage, it does not say that nothing was sent. Not in the RoboSats texts (security review of step 5 of #29). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'Troc could not read its records on this device.'**
  String get p2pRobotRecordsUnreadable;

  /// Title of the dialog that « Select Host » opens first for a robot of a Garage Key of unknown history (pasted in, or whose draw this device could not record), once per key and network, and again after the key is pasted again. Not in the RoboSats texts (design note of #29, § 2.4): the official client sends every robot it shows to every coordinator, so it asks nothing.
  ///
  /// In en, this message translates to:
  /// **'Robots from elsewhere'**
  String get p2pRobotHistoryTitle;

  /// Body of the dialog « Robots from elsewhere ». Not in the RoboSats texts (design note of #29, § 2.4). Factual: a key from the user's own backup is pasted in too, and nothing here says that a robot must be sent to a coordinator before trading.
  ///
  /// In en, this message translates to:
  /// **'This Garage Key was pasted in, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Troc a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, generate a new Garage Key.'**
  String get p2pRobotHistoryBody;

  /// Button of the dialog « Robots from elsewhere » that records the acknowledgement and goes on to the « Select Host » sheet; « Cancel » records nothing. Bull's own label (`settingsDevModeUnderstandButton` of the wallet), as the design note of #29 asks (§ 2.6).
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get p2pRobotHistoryConfirm;
}

class _P2pLocalizationsDelegate
    extends LocalizationsDelegate<P2pLocalizations> {
  const _P2pLocalizationsDelegate();

  @override
  Future<P2pLocalizations> load(Locale locale) {
    return SynchronousFuture<P2pLocalizations>(lookupP2pLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'as',
    'bg',
    'bn',
    'cs',
    'de',
    'el',
    'en',
    'es',
    'fa',
    'fi',
    'fr',
    'hi',
    'hy',
    'it',
    'ka',
    'ko',
    'pt',
    'ru',
    'sw',
    'th',
    'tr',
    'uk',
    'vi',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_P2pLocalizationsDelegate old) => false;
}

P2pLocalizations lookupP2pLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'hi':
      {
        switch (locale.scriptCode) {
          case 'Latn':
            return P2pLocalizationsHiLatn();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return P2pLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return P2pLocalizationsAr();
    case 'as':
      return P2pLocalizationsAs();
    case 'bg':
      return P2pLocalizationsBg();
    case 'bn':
      return P2pLocalizationsBn();
    case 'cs':
      return P2pLocalizationsCs();
    case 'de':
      return P2pLocalizationsDe();
    case 'el':
      return P2pLocalizationsEl();
    case 'en':
      return P2pLocalizationsEn();
    case 'es':
      return P2pLocalizationsEs();
    case 'fa':
      return P2pLocalizationsFa();
    case 'fi':
      return P2pLocalizationsFi();
    case 'fr':
      return P2pLocalizationsFr();
    case 'hi':
      return P2pLocalizationsHi();
    case 'hy':
      return P2pLocalizationsHy();
    case 'it':
      return P2pLocalizationsIt();
    case 'ka':
      return P2pLocalizationsKa();
    case 'ko':
      return P2pLocalizationsKo();
    case 'pt':
      return P2pLocalizationsPt();
    case 'ru':
      return P2pLocalizationsRu();
    case 'sw':
      return P2pLocalizationsSw();
    case 'th':
      return P2pLocalizationsTh();
    case 'tr':
      return P2pLocalizationsTr();
    case 'uk':
      return P2pLocalizationsUk();
    case 'vi':
      return P2pLocalizationsVi();
    case 'zh':
      return P2pLocalizationsZh();
  }

  throw FlutterError(
    'P2pLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
