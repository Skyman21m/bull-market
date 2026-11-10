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

  /// Label of the premium of an offer in the book.
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

  /// Not in the RoboSats texts: shown above the book while some coordinators have not answered yet; the orders of the others are already listed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 coordinator is still loading} other{{count} coordinators are still loading}}'**
  String p2pBookCoordinatorsLoading(int count);

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
