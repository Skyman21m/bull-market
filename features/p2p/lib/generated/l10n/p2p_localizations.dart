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

  /// Start of the filter sentence once an order type is chosen: « I want to [Buy] and use [EUR] pay with [Revolut] hosted by [Temple of Sats] ». While none is chosen it is p2pBookFilterIWant.
  ///
  /// In en, this message translates to:
  /// **'I want to'**
  String get p2pBookFilterIWantTo;

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

  /// Start of the filter sentence while no order type is chosen: « I want [Any type] and use [Any currency] pay with [Any payment method] hosted by [Any host] ». Once a type is chosen the sentence starts with p2pBookFilterIWantTo (« I want to [Buy] »).
  ///
  /// In en, this message translates to:
  /// **'I want'**
  String get p2pBookFilterIWant;

  /// The order type selector while no type is chosen, and the first entry of its list. It names its subject, since four selectors would otherwise all read « ANY » (#101, owner's request); RoboSats shows « ANY ».
  ///
  /// In en, this message translates to:
  /// **'Any type'**
  String get p2pBookFilterAnyType;

  /// The currency selector while no currency is chosen, and the entry at the top of its list that clears the choice. RoboSats shows « ANY »; its French word for the currency is « Devise ».
  ///
  /// In en, this message translates to:
  /// **'Any currency'**
  String get p2pBookFilterAnyCurrency;

  /// The payment method selector while no method is chosen, and the entry at the top of its list that clears the choice. RoboSats shows « ANY »; its French words for the payment method are « Mode de paiement ».
  ///
  /// In en, this message translates to:
  /// **'Any payment method'**
  String get p2pBookFilterAnyMethod;

  /// The host (coordinator) selector while no host is chosen, and the entry at the top of its list that clears the choice. RoboSats shows « ANY »; its French word for the host is « Hôte ».
  ///
  /// In en, this message translates to:
  /// **'Any host'**
  String get p2pBookFilterAnyHost;

  /// A selector with several choices: the first one chosen, then how many more, as RoboSats shows its hidden payment method tags (« +2 »).
  ///
  /// In en, this message translates to:
  /// **'{first} +{count}'**
  String p2pBookFilterMore(String first, int count);

  /// What the order type selector chooses, said by a screen reader before the choice (p2pBookFilterChoices).
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get p2pBookFilterSubjectType;

  /// What the currency selector chooses, said by a screen reader before the choices.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get p2pBookFilterSubjectCurrency;

  /// What the payment method selector chooses, said by a screen reader before the choices.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get p2pBookFilterSubjectMethod;

  /// What the host selector chooses, said by a screen reader before the choices.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get p2pBookFilterSubjectHost;

  /// What a screen reader says of a selector with a choice made: its subject, then every choice (p2pBookFilterOrList), such as « Currency: EUR, USD or CHF ».
  ///
  /// In en, this message translates to:
  /// **'{subject}: {choices}'**
  String p2pBookFilterChoices(String subject, String choices);

  /// Several choices of one selector, any of which an order may match: {others} is every choice but the last, joined with p2pBookFilterListSeparator, such as « EUR, USD or CHF ».
  ///
  /// In en, this message translates to:
  /// **'{others} or {last}'**
  String p2pBookFilterOrList(String others, String last);

  /// Between two choices of a list of choices but the last two (p2pBookFilterOrList).
  ///
  /// In en, this message translates to:
  /// **', '**
  String get p2pBookFilterListSeparator;

  /// In the payment method sheet of the book's filter: how many orders the filter would keep with this method alone, the other choices as they are (#118).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no orders} =1{1 order} other{{count} orders}}'**
  String p2pBookFilterOrderCount(int count);

  /// A row of the payment method sheet: the method's name, then p2pBookFilterOrderCount, such as « Instant SEPA · 12 orders » (#118).
  ///
  /// In en, this message translates to:
  /// **'{method} · {orders}'**
  String p2pBookFilterMethodWithCount(String method, String orders);

  /// What a screen reader says of a row of the payment method sheet, without the separator shown: « Instant SEPA, 12 orders ».
  ///
  /// In en, this message translates to:
  /// **'{method}, {orders}'**
  String p2pBookFilterMethodWithCountSemantics(String method, String orders);

  /// Heading of the payment method sheet above the methods no order of the book would be kept with, listed dimmed but still selectable (#118, the owner's request).
  ///
  /// In en, this message translates to:
  /// **'No orders right now'**
  String get p2pBookFilterMethodsWithoutOrders;

  /// The payment method sheet when no method matches the text typed in its search field.
  ///
  /// In en, this message translates to:
  /// **'No payment method found'**
  String get p2pBookFilterNoMethodFound;

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

  /// Empty book when the filter is « Sell ». {currencyCode} is the currency chosen, several joined by p2pBookFilterOrList (« EUR, USD or CHF »), or p2pBookEmptyAnyCurrency when none is.
  ///
  /// In en, this message translates to:
  /// **'No orders found to sell BTC for {currencyCode}'**
  String p2pBookEmptySell(String currencyCode);

  /// Empty book for any filter but « Sell » (RoboSats tests type 0, else this text). {currencyCode} is the currency chosen, several joined by p2pBookFilterOrList (« EUR, USD or CHF »), or p2pBookEmptyAnyCurrency when none is.
  ///
  /// In en, this message translates to:
  /// **'No orders found to buy BTC for {currencyCode}'**
  String p2pBookEmptyBuy(String currencyCode);

  /// The value of {currencyCode} in the empty book messages while no currency is chosen, where RoboSats puts « ANY ».
  ///
  /// In en, this message translates to:
  /// **'any currency'**
  String get p2pBookEmptyAnyCurrency;

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

  /// Button that closes a warning or a message the user has read.
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

  /// Text of the « Search order » dialog (`components/Dialogs/GoToOrder.tsx:52`); written in the RoboSats code only, absent from its translation files. Since #245 it holds here too: an order the books received do not hold, a password-protected one included, is read by the robot that would take it.
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

  /// Title of the dialog shown when a page needs a robot and no Garage Key is stored, such as an order searched by its URL that is not in the public book.
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

  /// The RoboSats text of a coordinator's refusal to show an order (error 1044), shown when an order searched by its URL is not in the public book and a Garage Key is stored, or cannot be read. Also on the trade screens (#88): the coordinator's message of error 1044 (`api/errors.py`), which the official client shows alone on the order page, an order that left the book just before a take, and an order public again that the book no longer lists.
  ///
  /// In en, this message translates to:
  /// **'This order is not available'**
  String get p2pOrderNotAvailable;

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

  /// Not in the RoboSats texts: what a screen reader says of the map before its pins and groups. {buyOrders} and {sellOrders} are the counts of p2pChartBuyOrders and p2pChartSellOrders: every order of the book received that has a location, whatever the filter of the list, as the map shows them.
  ///
  /// In en, this message translates to:
  /// **'Map of the face to face locations of the order book: {buyOrders} and {sellOrders}.'**
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

  /// Error under the Garage Key field when what was typed is not a Garage Key and no more precise reason applies.
  ///
  /// In en, this message translates to:
  /// **'Invalid garage key'**
  String get p2pGarageKeyInvalid;

  /// Text of the second step of the wizard, above the robot's avatar, and its label on the profile.
  ///
  /// In en, this message translates to:
  /// **'This is your trading avatar'**
  String get p2pGarageTradingAvatar;

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

  /// Caption of the box that holds the Garage Key on the profile.
  ///
  /// In en, this message translates to:
  /// **'Garage Key'**
  String get p2pGarageKeyLabel;

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
  /// **'{coordinator} will know this robot from now on. In Bull Market, a robot lives on one coordinator only: this robot will never be sent to another one. To trade elsewhere, use another robot.'**
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

  /// RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx:226`): « Last order #N » under the robot navigator of the Garage, the last finished order made here or trade taken here, from the records, which a tap opens (#216); the robot panel no longer says it as plain text (functional review of #220, R4). {orderId} is the number of the order.
  ///
  /// In en, this message translates to:
  /// **'Last order #{orderId}'**
  String p2pRobotLastOrder(String orderId);

  /// The coordinator knows no order of the robot. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`); its French says « commande », the glossary says « ordre ».
  ///
  /// In en, this message translates to:
  /// **'No existing orders found'**
  String get p2pRobotNoOrders;

  /// Information when the robot shown has a last order and no active one, unless this device holds that order finished with an end that has not served (an expiry, or a take that never started, #251): RoboSats says it for a robot that is not reusable, a last order of unknown status counting as used. RoboSats text (`basic/GaragePage/GarageKeyProfile.tsx`), French of the phase-1 catalogue.
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
  /// **'{coordinator} sent an answer Bull Market cannot read.'**
  String p2pRobotBadAnswer(String coordinator);

  /// A robot bound to a coordinator whose address or keys in the federation list of the app changed since. Not in the RoboSats texts (design note of #29, § 2.3). No button.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} changed its address or keys since this robot was sent to it. Nothing was sent. Until an update of the app has checked the change, use another robot.'**
  String p2pRobotCoordinatorChanged(String coordinator);

  /// The feature's database could not be read or written. Not in the RoboSats texts (design note of #29, § 2.3). With « Retry ».
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not read its records on this device. Nothing was sent.'**
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
  /// **'Bull Market could not read its records on this device.'**
  String get p2pRobotRecordsUnreadable;

  /// Title of the dialog that « Select Host » opens first for a robot of a Garage Key of unknown history (pasted in, or whose draw this device could not record), once per key and network, and again after the key is pasted again. Not in the RoboSats texts (design note of #29, § 2.4): the official client sends every robot it shows to every coordinator, so it asks nothing.
  ///
  /// In en, this message translates to:
  /// **'Robots from elsewhere'**
  String get p2pRobotHistoryTitle;

  /// Body of the dialog « Robots from elsewhere ». Not in the RoboSats texts (design note of #29, § 2.4). Factual: a key from the user's own backup is pasted in too, and nothing here says that a robot must be sent to a coordinator before trading.
  ///
  /// In en, this message translates to:
  /// **'This Garage Key was imported, or this device could not record that it drew it. Its robots may already exist on coordinators: the official RoboSats app sends each robot it shows to every coordinator. In Bull Market, a robot lives on one coordinator only: if you used this key before, put each robot on the coordinator where you used it. To start clean, go back to the internal Garage Keys.'**
  String get p2pRobotHistoryBody;

  /// Button of the dialog « Robots from elsewhere » that records the acknowledgement and goes on to the « Select Host » sheet; « Cancel » records nothing. Bull's own label (`settingsDevModeUnderstandButton` of the wallet), as the design note of #29 asks (§ 2.6).
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get p2pRobotHistoryConfirm;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Label of the amount field of a range order (`TakeButton.tsx:224`). {currencyCode} is the order's currency code, « Sats » for an order in bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Amount {currencyCode}'**
  String p2pTakeAmountLabel(String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Tooltip of the amount field of a range order (`TakeButton.tsx:218`).
  ///
  /// In en, this message translates to:
  /// **'Enter amount of fiat to exchange for bitcoin'**
  String get p2pTakeAmountHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Under the amount field when the amount typed is below the order's minimum (`TakeButton.tsx:129`).
  ///
  /// In en, this message translates to:
  /// **'Too low'**
  String get p2pTakeTooLow;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Under the amount field when the amount typed is above the order's maximum (`TakeButton.tsx:131`).
  ///
  /// In en, this message translates to:
  /// **'Too high'**
  String get p2pTakeTooHigh;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Under the amount field of a range sell order once the amount is valid (`TakeButton.tsx:291`). {satoshis} is a number of sats written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'You will receive {satoshis} Sats (Approx)'**
  String p2pTakeYouWillReceive(String satoshis);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Under the amount field of a range buy order, whose taker sells, once the amount is valid (`TakeButton.tsx:292`, #96). {satoshis} is a number of sats written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'You will send {satoshis} Sats (Approx)'**
  String p2pTakeYouWillSend(String satoshis);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Tooltip of « Take Order », disabled while the amount of a range order is empty or out of range (`TakeButton.tsx:251`).
  ///
  /// In en, this message translates to:
  /// **'You must specify an amount first'**
  String get p2pTakeSpecifyAmountFirst;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's. Title of the backup reminder shown before a take (`Dialogs/StoreToken.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Store your garage key'**
  String get p2pStoreKeyTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's. Text of the backup reminder shown before a take (`Dialogs/StoreToken.tsx`). The key itself is not shown there: it is shown only in the Garage, behind the PIN.
  ///
  /// In en, this message translates to:
  /// **'Your garage key provides access to all your robot accounts. Store it safely. You can simply copy it into another application.'**
  String get p2pStoreKeyText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Button that closes a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get p2pCommonGoBack;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Button of the backup reminder that goes on with the take (`Dialogs/StoreToken.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get p2pCommonDone;

  /// Not in the RoboSats texts: the project's own: the coordinator's book or fees could not be read just before the take, so nothing was sent with a robot. {coordinator} is its long alias.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {coordinator}. The order was not taken.'**
  String p2pTakeCoordinatorUnreadable(String coordinator);

  /// Not in the RoboSats texts: the project's own: the order read again just before the take differs from the one shown (anything but its price).
  ///
  /// In en, this message translates to:
  /// **'This order changed since it was shown. It was not taken: open it again from the book.'**
  String get p2pTakeOrderChanged;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), the title of its dialog « Order description » (`Dialogs/OrderDescription.tsx:38`); its `fr.json` leaves it in English, so the French is the project's own. Label of the maker's description among the order details once the robot that takes the order read it (#119).
  ///
  /// In en, this message translates to:
  /// **'Order description'**
  String get p2pOrderDescription;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). Label of the bond the take asks, among the order details once the robot that takes it read the order (#119).
  ///
  /// In en, this message translates to:
  /// **'Taker bond'**
  String get p2pTakerBond;

  /// Not in the RoboSats texts: the project's own: the bond the take asks, at the price the robot read, and the most the app accepts of the coordinator's bond invoice for it (#119). Both are numbers of sats, written already.
  ///
  /// In en, this message translates to:
  /// **'{estimate} Sats, at most {ceiling} Sats'**
  String p2pTakeBondEstimate(String estimate, String ceiling);

  /// Not in the RoboSats texts: the project's own: under the order details once the robot that takes the order read it (#119): when it read it; read out when it arrives. {time} is hours, minutes and seconds.
  ///
  /// In en, this message translates to:
  /// **'Read by your robot at {time}'**
  String p2pTakeReadAt(String time);

  /// Not in the RoboSats texts: the project's own (#251, the owner's decision of 2026-11-25, French as on the mock-up he accepted): under « Read by your robot at … » on the order page, only when the robot reserved for the take is not the robot the Garage would show; read out when it appears. {nickname} is the nickname of the robot that takes the order.
  ///
  /// In en, this message translates to:
  /// **'A fresh robot for this order: {nickname}.'**
  String p2pTakeFreshRobot(String nickname);

  /// Not in the RoboSats texts: the project's own: what a screen reader hears of a row of the order details whose value changed since the read the user saw before, when a confirmation found the order changed (#119, second interface review of #133).
  ///
  /// In en, this message translates to:
  /// **'New value: {value}'**
  String p2pOrderNewValue(String value);

  /// Not in the RoboSats texts: the project's own: over « Continue », from the start of the read made again when a confirmation found the order changed, then with the new read, whose changed rows are marked: nothing was taken (#119, review of #133).
  ///
  /// In en, this message translates to:
  /// **'The order changed.'**
  String get p2pTakeOrderChangedRead;

  /// Not in the RoboSats texts: the project's own: a step of the wait of a take (#119): the order read again from the coordinator's book, with its fees, anonymously. The reference has no such line, its robot existing before the take.
  ///
  /// In en, this message translates to:
  /// **'Checking the order with {coordinator}'**
  String p2pTakeStepCheckingOrder(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). The reference shows it while a robot is generated; here, a step of the wait of a take (#119): a fresh robot made and put on the coordinator.
  ///
  /// In en, this message translates to:
  /// **'Building your robot!'**
  String get p2pTakeStepCreatingRobot;

  /// Not in the RoboSats texts: the project's own: a step of the wait of a take (#119): the order read by the robot that will take it.
  ///
  /// In en, this message translates to:
  /// **'Your robot is reading the order'**
  String get p2pTakeStepReadingOrder;

  /// Not in the RoboSats texts: the project's own: a step of the wait after « Done » of « Store your garage key » (#119): the order read again by the same robot, before the take.
  ///
  /// In en, this message translates to:
  /// **'Your robot is reading the order again'**
  String get p2pTakeStepReadingOrderAgain;

  /// Not in the RoboSats texts: the project's own: a step of the wait after « Confirm » (#119): the take sent, and its answer awaited.
  ///
  /// In en, this message translates to:
  /// **'Taking the order with {coordinator}'**
  String p2pTakeStepSendingTake(String coordinator);

  /// Not in the RoboSats texts: the project's own: under the spinner of the trade screen before its first read, right after the take (review of #133): what it waits for. The reference has no such line, its trade page opening on an order it has already read.
  ///
  /// In en, this message translates to:
  /// **'Your robot is reading the order from {coordinator}'**
  String p2pTradeFirstRead(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1011 (`api/errors.py`), which the official client shows under « Take Order »; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The amount specified is outside the range specified by the maker'**
  String get p2pTakeAmountOutOfRange;

  /// Not in the RoboSats texts: the project's own: the coordinator announces a taker fee above the app's ceiling (`TradeTolerances.takerFeeCeiling`).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} asks for a taker fee above 1 %. The order was not taken.'**
  String p2pTakeFeeTooHigh(String coordinator);

  /// Not in the RoboSats texts: the project's own: the terms of the take cannot be built from the order read (`TradeTermsUnusable`).
  ///
  /// In en, this message translates to:
  /// **'The terms of this order could not be checked. It was not taken.'**
  String get p2pTakeTermsUnusable;

  /// Not in the RoboSats texts: the project's own: after the text of a failure of the robot or of the coordinator during a take. {reason} is that text, a sentence of the app.
  ///
  /// In en, this message translates to:
  /// **'{reason} The order was not taken.'**
  String p2pTakeNotTakenAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the records of the take could not be written before it was sent, so it was not sent.
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not write its records on this device. The order was not taken.'**
  String get p2pTakeNotRecorded;

  /// Not in the RoboSats texts: the project's own: the fresh robot of the take was already known to the coordinator; the next take uses another robot.
  ///
  /// In en, this message translates to:
  /// **'The robot chosen for this take already existed on {coordinator}. The order was not taken: try again.'**
  String p2pTakeRobotNotNew(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator answered the take with the order as it is, this robot not its taker.
  ///
  /// In en, this message translates to:
  /// **'The order was not taken.'**
  String get p2pTakeNotMade;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1000 (`api/errors.py`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are already maker of an active order'**
  String get p2pTakeAlreadyMaker;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1001 (`api/errors.py`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are already taker of an active order'**
  String get p2pTakeAlreadyTaker;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1002 (`api/errors.py`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are already taking an active order'**
  String get p2pTakeAlreadyTaking;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1003 (`api/errors.py`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are still pending a payment from a recent order'**
  String get p2pTakePaymentPending;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1012 (`api/errors.py`); the French is the project's. {seconds} is a whole number.
  ///
  /// In en, this message translates to:
  /// **'You need to wait {seconds} seconds to take an order'**
  String p2pTakePenalty(String seconds);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): a take refused for a penalty whose length is not known (`TakeButton.tsx:98`).
  ///
  /// In en, this message translates to:
  /// **'Wait until you can take an order'**
  String get p2pTakeWaitPenalty;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`). The second tab of the order page of a participant, open first (`basic/OrderPage/index.tsx:268`).
  ///
  /// In en, this message translates to:
  /// **'Contract'**
  String get p2pTradeTabContract;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the step of the trade after its title (`TradeBox/stepXofY.ts`). {step} and {steps} are small whole numbers.
  ///
  /// In en, this message translates to:
  /// **'({step}/{steps})'**
  String p2pTradeStep(String step, String steps);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at status 3 (`TradeBox/index.tsx:430`), which `fr.json` misses (design note § 1.7); the French is the design note's. {amountSats} is the bond in sats, written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'Lock {amountSats} Sats to TAKE order'**
  String p2pTradeTitleLockBond(String amountSats);

  /// The official client's text: the maker's title at status 0 (`TradeBox/index.tsx:379-389`, #180), which neither `en.json` nor `fr.json` lists (design note `docs/design/phase-3-making-an-order.md` § 1.11); the French is the project's, in the words of `p2pTradeTitleLockBond`. {amountSats} is the maker bond in sats (`bond_satoshis`), written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'Lock {amountSats} Sats to PUBLISH order'**
  String p2pTradeTitleLockBondPublish(String amountSats);

  /// The official client's text: the seller's title at 6 and 7, in the warning colour (`TradeBox/index.tsx:479-485`, `:497-503`, #96), which neither `en.json` nor `fr.json` lists (design note § 1.7); the French is the design note's. {amountSats} is the escrow in sats (`escrow_satoshis`), written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'Lock {amountSats} Sats as collateral'**
  String p2pTradeTitleLockEscrow(String amountSats);

  /// The official client's text (`Prompts/LockInvoice.tsx:48-56`, the escrow's `ExpirationWarning`, #96), which `fr.json` misses; the French is the project's. {hours} and {minutes} are the order's escrow time (`escrow_duration`) as the reference splits it.
  ///
  /// In en, this message translates to:
  /// **'You risk losing your bond if you do not lock the collateral. Total time available is {hours}h {minutes}m.'**
  String p2pTradeEscrowTimeWarning(String hours, String minutes);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c) (`Prompts/LockInvoice.tsx`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are BUYING BTC'**
  String get p2pTradeYouAreBuying;

  /// The official client's text (`Prompts/LockInvoice.tsx:79`, the bond of a taker who sells, #96), which neither `en.json` nor `fr.json` lists; the French is the project's, as for « You are BUYING BTC ».
  ///
  /// In en, this message translates to:
  /// **'You are SELLING BTC'**
  String get p2pTradeYouAreSelling;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/WalletsButton.tsx`). Here it shows the link, to copy: the app never opens it.
  ///
  /// In en, this message translates to:
  /// **'See Compatible Wallets'**
  String get p2pTradeCompatibleWallets;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): copies the bond invoice (`Prompts/LockInvoice.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get p2pTradeCopyToClipboard;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), under the bond's QR code (`Prompts/LockInvoice.tsx`).
  ///
  /// In en, this message translates to:
  /// **'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.'**
  String get p2pTradeHoldInvoiceBond;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), under the escrow's QR code (`Prompts/LockInvoice.tsx:30-33`, #96). {currencyCode} is the trade's currency.
  ///
  /// In en, this message translates to:
  /// **'This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the {currencyCode}.'**
  String p2pTradeHoldInvoiceEscrow(String currencyCode);

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the QR code of the bond invoice.
  ///
  /// In en, this message translates to:
  /// **'QR code of the bond invoice'**
  String get p2pTradeInvoiceQr;

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the QR code of the seller's escrow invoice (#96).
  ///
  /// In en, this message translates to:
  /// **'QR code of the escrow invoice'**
  String get p2pTradeEscrowQr;

  /// Not in the RoboSats texts: the project's own: label of the time of day the bond invoice expires at, among the facts read from it under the QR code (design note § 4.4).
  ///
  /// In en, this message translates to:
  /// **'Expires at'**
  String get p2pTradeInvoiceExpires;

  /// Not in the RoboSats texts: the project's own: label of the network of the bond invoice, among the facts read from it (design note § 4.4).
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get p2pTradeInvoiceNetwork;

  /// Not in the RoboSats texts: the project's own: label of the description of the bond invoice, the coordinator's text shown cleaned (design note § 4.4).
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get p2pTradeInvoiceDescription;

  /// Not in the RoboSats texts: the project's own: the network of an invoice for the main Bitcoin network.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin'**
  String get p2pTradeNetworkMainnet;

  /// Not in the RoboSats texts: the project's own: the network of an invoice for the Bitcoin test network.
  ///
  /// In en, this message translates to:
  /// **'Bitcoin testnet'**
  String get p2pTradeNetworkTestnet;

  /// Not in the RoboSats texts: the project's own, at the owner's request (2026-11-13): the section of the bond panel that holds the QR code and the copy, for any other Lightning wallet.
  ///
  /// In en, this message translates to:
  /// **'Pay with another wallet'**
  String get p2pTradePayOtherWallet;

  /// Not in the RoboSats texts: the project's own (design note § 3.2): shows the QR code an amount check hid.
  ///
  /// In en, this message translates to:
  /// **'Show anyway'**
  String get p2pTradeShowAnyway;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c) (`TradeBox/BondStatus.tsx`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your taker bond is locked'**
  String get p2pTradeBondLocked;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c) (`TradeBox/BondStatus.tsx`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your taker bond is unlocked'**
  String get p2pTradeBondUnlocked;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c) (`TradeBox/BondStatus.tsx`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your taker bond is settled'**
  String get p2pTradeBondSettled;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 6 and 8 for the buyer (`TradeBox/index.tsx:462`), which `fr.json` misses; the French is the design note's (§ 1.7).
  ///
  /// In en, this message translates to:
  /// **'Submit payout info'**
  String get p2pTradeTitlePayout;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Payout.tsx`). {amountFiat} is the amount of the trade in its currency, {currencyCode} the currency's code.
  ///
  /// In en, this message translates to:
  /// **'Before letting you send {amountFiat} {currencyCode}, we want to make sure you are able to receive the BTC.'**
  String p2pTradePayoutPrompt(String amountFiat, String currencyCode);

  /// The official client's « Before letting you send {{amountFiat}} {{currencyCode}}, we want to make sure you are able to receive the BTC. » (`Prompts/Payout.tsx`) without its figure: for an order made here whose range's amount taken is not known, or is read as another than the one kept with the contract, where the app writes no figure rather than the coordinator's (security review of #183, C2). The French is the project's, after the reference's.
  ///
  /// In en, this message translates to:
  /// **'Before letting you send the fiat, we want to make sure you are able to receive the BTC.'**
  String get p2pTradePayoutPromptNoAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 7 for the buyer (`TradeBox/index.tsx:494`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your info looks good!'**
  String get p2pTradeTitleInfoGood;

  /// The official client's text: the seller's title at 8 (`TradeBox/index.tsx:531`, #96), which neither `en.json` nor `fr.json` lists; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The trade collateral is locked!'**
  String get p2pTradeTitleCollateralLocked;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/EscrowWait.tsx`).
  ///
  /// In en, this message translates to:
  /// **'We are waiting for the seller to lock the trade amount.'**
  String get p2pTradeEscrowWait;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/EscrowWait.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Just hang on for a moment. If the seller does not deposit, you will get your bond back automatically. In addition, you will receive a compensation (check the rewards in your profile).'**
  String get p2pTradeEscrowWaitHangOn;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/PayoutWait.tsx`): the seller's wait at 8 (#96).
  ///
  /// In en, this message translates to:
  /// **'We are waiting for the buyer to post a lightning invoice. Once he does, you will be able to directly communicate the payment details.'**
  String get p2pTradePayoutWait;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/PayoutWait.tsx`): the seller's wait at 8 (#96).
  ///
  /// In en, this message translates to:
  /// **'Just hang on for a moment. If the buyer does not cooperate, you will get back the trade collateral and your bond automatically. In addition, you will receive a compensation (check the rewards in your profile).'**
  String get p2pTradePayoutWaitHangOn;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's label of expiry reason 0 (`api/models/order.py:57`), shown by `Prompts/Expired.tsx`; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Expired not taken'**
  String get p2pTradeExpiredNotTaken;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's label of expiry reason 1 (`api/models/order.py:58`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Maker bond not locked'**
  String get p2pTradeExpiredMakerBond;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's label of expiry reason 2 (`api/models/order.py:59`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Escrow not locked'**
  String get p2pTradeExpiredEscrow;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's label of expiry reason 3 (`api/models/order.py:60`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Invoice not submitted'**
  String get p2pTradeExpiredInvoice;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's label of expiry reason 4 (`api/models/order.py:61`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Neither escrow locked or invoice submitted'**
  String get p2pTradeExpiredNeither;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1043 (`api/errors.py`), which the official client shows alone on the order page; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'This order has been cancelled'**
  String get p2pOrderCancelled;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 9 and 10 for the buyer (`TradeBox/index.tsx:542`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Chat with the seller'**
  String get p2pTradeTitleChat;

  /// The official client's text: title at 9 and 10 for the seller (`TradeBox/index.tsx:542`, #96), which neither `en.json` nor `fr.json` lists; the French is the project's, as « Discutez avec le vendeur ».
  ///
  /// In en, this message translates to:
  /// **'Chat with the buyer'**
  String get p2pTradeTitleChatWithBuyer;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 11 (`TradeBox/index.tsx:583`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'A dispute has been opened'**
  String get p2pTradeTitleDispute;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 11 once the statement is in (`TradeBox/index.tsx:578`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'We have received your statement'**
  String get p2pTradeTitleStatementReceived;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 13 for the buyer (`TradeBox/index.tsx:605`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Attempting Lightning Payment'**
  String get p2pTradeTitleSendingSats;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 14 (`TradeBox/index.tsx:633`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Trade finished!'**
  String get p2pTradeTitleFinished;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 15 for the buyer (`TradeBox/index.tsx:657`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Lightning Routing Failed'**
  String get p2pTradeTitleRoutingFailed;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 16 (`TradeBox/index.tsx:695`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'We have the statements'**
  String get p2pTradeTitleStatements;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 17 for a taker (`TradeBox/index.tsx:712`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You have won the dispute'**
  String get p2pTradeTitleDisputeWon;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): title at 18 for a taker (`TradeBox/index.tsx:706`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You have lost the dispute'**
  String get p2pTradeTitleDisputeLost;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the default title of a status (`TradeBox/index.tsx:363`), which `fr.json` misses; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Unknown Order Status'**
  String get p2pTradeTitleUnknown;

  /// Not in the RoboSats texts: the project's own: in place of the prompt of a step that a later slice brings (chat, dispute, payout).
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot show this step yet.'**
  String get p2pTradeStepLater;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/CancelButton.tsx`): copies the order's address on its coordinator.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get p2pTradeCopyUrl;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): tooltip of « Copy URL ».
  ///
  /// In en, this message translates to:
  /// **'Copy order URL'**
  String get p2pTradeCopyOrderUrl;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): tooltip of « Cancel » while cancelling is free (the pre-take).
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get p2pTradeCancelOrder;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's: tooltip of « Cancel » once the bond is locked.
  ///
  /// In en, this message translates to:
  /// **'Unilateral cancelation (bond at risk!)'**
  String get p2pTradeCancelUnilateral;

  /// Not in the RoboSats texts: the project's own: why « Cancel » is off while a payout is given (#91), for the screen reader and a long press.
  ///
  /// In en, this message translates to:
  /// **'Cancel is off while your payout info is being sent.'**
  String get p2pTradeCancelWhilePayout;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): title of both cancel dialogs (`Dialogs/CancelOrder.tsx`, `TradeBox/Dialogs/ConfirmCancel.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Cancel the order?'**
  String get p2pTradeCancelTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's (`Dialogs/CancelOrder.tsx`, « loose » in the reference, spelled « lose » here).
  ///
  /// In en, this message translates to:
  /// **'If the order is cancelled now but you already tried to pay the invoice, you might lose your bond.'**
  String get p2pTradeCancelPreTakeText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): closes the cancel dialog of the pre-take without cancelling.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get p2pTradeCancelBack;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): cancels the pre-take (`Dialogs/CancelOrder.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Confirm cancellation'**
  String get p2pTradeConfirmCancellation;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/Dialogs/ConfirmCancel.tsx`).
  ///
  /// In en, this message translates to:
  /// **'If the order is cancelled now you will lose your bond.'**
  String get p2pTradeCancelBondText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): cancels once the bond is locked, which loses it (`TradeBox/Dialogs/ConfirmCancel.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Confirm Cancel'**
  String get p2pTradeConfirmCancel;

  /// Not in the RoboSats texts: the project's own: the coordinator refused the cancel because the status changed (error 1020).
  ///
  /// In en, this message translates to:
  /// **'The order moved on before the cancel: nothing was cancelled.'**
  String get p2pTradeCancelMovedOn;

  /// Not in the RoboSats texts: the project's own: after the text of a failure that kept a cancel from being sent. {reason} is that text, a sentence of the app.
  ///
  /// In en, this message translates to:
  /// **'{reason} Nothing was cancelled.'**
  String p2pTradeCancelNotDoneAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the cancel was sent and its outcome is unknown; the next reads tell.
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether the cancel went through. It keeps checking.'**
  String get p2pTradeCancelUnknown;

  /// Not in the RoboSats texts: the project's own: the status shown comes from no order read, so a cancel cannot be sent yet.
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again before cancelling.'**
  String get p2pTradeCancelNeedsRead;

  /// Not in the RoboSats texts: the project's own: a cancel asked at 8, where the coordinator takes only a collaborative cancel and the reference offers it from the chat only (#95); no screen offers a cancel at 8.
  ///
  /// In en, this message translates to:
  /// **'At this step only a collaborative cancel exists, which RoboSats offers from the chat.'**
  String get p2pTradeCancelOnlyTogether;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the coordinator's message of error 1021 (`api/errors.py`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You cannot cancel this order'**
  String get p2pTradeCancelNotPossible;

  /// Not in the RoboSats texts: the project's own: a take whose answer was lost, until a read tells whether this robot holds the order (#87).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether the take went through. It keeps checking with {coordinator}.'**
  String p2pTradeTakePending(String coordinator);

  /// Not in the RoboSats texts: the project's own: a pending take whose request never left (#87).
  ///
  /// In en, this message translates to:
  /// **'This take was never sent to {coordinator}.'**
  String p2pTradeTakeNeverSent(String coordinator);

  /// Not in the RoboSats texts: the project's own: three reads of the trade failed in a row; the last status read stays shown. {time} is the time of the last read, hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach {coordinator}. What is shown was read at {time}.'**
  String p2pTradeReadsFailing(String coordinator, String time);

  /// Not in the RoboSats texts: the project's own: a write of the trade's records failed after the coordinator answered; the trade goes on (#87).
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not write the records of this trade on this device.'**
  String get p2pTradeRecordProblem;

  /// Not in the RoboSats texts: the project's own: `TradeClosedFailure` (#87), shown, never dropped.
  ///
  /// In en, this message translates to:
  /// **'This trade was closed on this device, but {coordinator} shows this robot as its taker.'**
  String p2pTradeClosedProblem(String coordinator);

  /// Not in the RoboSats texts: the project's own: the trade's stored records are refused (#87); it is shown read-only.
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot read the records of this trade. Nothing is sent.'**
  String get p2pTradeUnrestorable;

  /// Not in the RoboSats texts: the project's own: the trade's coordinator left the federation list (#87); the trade is shown read-only.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} is no longer in the list of coordinators. Nothing is sent.'**
  String p2pTradeCoordinatorGone(String coordinator);

  /// Not in the RoboSats texts: the project's own: the trade cannot be read (no records, a binding that refuses the coordinator…), #87.
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot open this trade now. Nothing is sent.'**
  String get p2pTradeUnavailable;

  /// Not in the RoboSats texts: the project's own: the Garage Key whose robot holds the trade is not stored (#87).
  ///
  /// In en, this message translates to:
  /// **'The Garage Key of this trade is not on this device. Nothing is sent.'**
  String get p2pTradeKeyMissing;

  /// Not in the RoboSats texts: the project's own: `TradeRoleMismatch` (design note § 3.2).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} gives this robot another role than the one it took. Do not pay anything.'**
  String p2pTradeWarnRole(String coordinator);

  /// Not in the RoboSats texts: the project's own: `TradeOrderMismatch`.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} answered about another order. Do not pay anything.'**
  String p2pTradeWarnOrder(String coordinator);

  /// Not in the RoboSats texts: the project's own: `TradeTermsChanged`.
  ///
  /// In en, this message translates to:
  /// **'The terms of the order are not those of the order taken.'**
  String get p2pTradeWarnTerms;

  /// Not in the RoboSats texts: the project's own: `TradeStatusUnexpected` (design note § 3.2).
  ///
  /// In en, this message translates to:
  /// **'Unexpected change on the coordinator\'s side.'**
  String get p2pTradeWarnUnexpected;

  /// Not in the RoboSats texts: the project's own: `TradeStatusRegressed`.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} sent a status that does not follow this trade. It was ignored.'**
  String p2pTradeWarnRegressed(String coordinator);

  /// Not in the RoboSats texts: the project's own: `CoordinatorInconsistent`.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} contradicted itself earlier in this trade.'**
  String p2pTradeWarnInconsistent(String coordinator);

  /// Not in the RoboSats texts: the project's own: `TradeHistoryUnknown`.
  ///
  /// In en, this message translates to:
  /// **'This trade was found without its history: its invoices cannot be compared with the first ones.'**
  String get p2pTradeWarnHistoryUnknown;

  /// Not in the RoboSats texts: the project's own: `BondAmountOutsideOrder`.
  ///
  /// In en, this message translates to:
  /// **'The bond asked is not the bond of the order taken.'**
  String get p2pTradeWarnBond;

  /// Not in the RoboSats texts: the project's own: `TradePriceOutsideOrder`.
  ///
  /// In en, this message translates to:
  /// **'The trade amount does not match the order\'s price.'**
  String get p2pTradeWarnPrice;

  /// Not in the RoboSats texts: the project's own: `EscrowAmountMismatch`, `PayoutAmountMismatch` and `TakerFeeAboveAnnounced`.
  ///
  /// In en, this message translates to:
  /// **'The amounts {coordinator} gives do not add up.'**
  String p2pTradeWarnAmounts(String coordinator);

  /// Not in the RoboSats texts: the project's own: `DeadlineMovedBack`.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} moved the deadline earlier.'**
  String p2pTradeWarnDeadline(String coordinator);

  /// Not in the RoboSats texts: the project's own: `InvoiceUnreadable` (design note § 4.4).
  ///
  /// In en, this message translates to:
  /// **'The invoice {coordinator} sent cannot be read. It is not shown.'**
  String p2pTradeWarnUnreadable(String coordinator);

  /// Not in the RoboSats texts: the project's own: `InvoiceWrongNetwork` (design note § 4.4).
  ///
  /// In en, this message translates to:
  /// **'The invoice {coordinator} sent is for another network. It is not shown.'**
  String p2pTradeWarnWrongNetwork(String coordinator);

  /// Not in the RoboSats texts: the project's own: `InvoiceAmountMismatch`.
  ///
  /// In en, this message translates to:
  /// **'The invoice amount is not the amount the order asks for.'**
  String get p2pTradeWarnInvoiceAmount;

  /// Not in the RoboSats texts: the project's own: `InvoiceExpired`.
  ///
  /// In en, this message translates to:
  /// **'This invoice has expired.'**
  String get p2pTradeWarnExpired;

  /// Not in the RoboSats texts: the project's own: `InvoiceExpiringSoon`.
  ///
  /// In en, this message translates to:
  /// **'This invoice expires in less than a minute.'**
  String get p2pTradeWarnExpiringSoon;

  /// Not in the RoboSats texts: the project's own: `InvoiceHashChanged`.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} sent a new invoice for the same step. Do not pay it.'**
  String p2pTradeWarnHashChanged(String coordinator);

  /// Not in the RoboSats texts: the project's own: `InvoicePayeeNotCoordinator`, the design note's text (§ 4.4).
  ///
  /// In en, this message translates to:
  /// **'This invoice is not from {coordinator}\'s known Lightning node. Do not pay it.'**
  String p2pTradeWarnPayee(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`basic/GaragePage/GarageKeyProfile.tsx:209`): one line per active trade in the sheet « Order » opens when there are several. {orderId} is the order's number on its coordinator.
  ///
  /// In en, this message translates to:
  /// **'Active order #{orderId}'**
  String p2pActiveOrder(String orderId);

  /// Not in the RoboSats texts: the project's own: the stored records of the trade hold an end, and no read of it is there to show (#87, #88). No action.
  ///
  /// In en, this message translates to:
  /// **'This trade is over for this robot.'**
  String get p2pTradeEnded;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c): the unit the official client writes for an amount of an order in bitcoin, which it shows in sats (`TakeButton.tsx:82-83`, `Payout.tsx:70`).
  ///
  /// In en, this message translates to:
  /// **'Sats'**
  String get p2pSatsUnit;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c) (`Prompts/LockInvoice.tsx:78`, without « You are »), in place of « You are BUYING BTC » for an order in bitcoin (a swap), which `fr.json` misses; the French is the project's, worded on the English.
  ///
  /// In en, this message translates to:
  /// **'SWAPPING INTO Lightning'**
  String get p2pTradeYouAreSwappingIn;

  /// The official client's text (`Prompts/LockInvoice.tsx:78`, without « You are »), in place of « You are SELLING BTC » for an order in bitcoin whose taker sells (#96), which neither `en.json` nor `fr.json` lists; the French is the project's, worded on « SWAP VERS Lightning ».
  ///
  /// In en, this message translates to:
  /// **'SWAPPING OUT of Lightning'**
  String get p2pTradeYouAreSwappingOut;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Payout.tsx:95`): the tab of a Lightning payout.
  ///
  /// In en, this message translates to:
  /// **'Lightning'**
  String get p2pPayoutTabLightning;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Payout.tsx:107`): the tab of an on-chain payout.
  ///
  /// In en, this message translates to:
  /// **'Onchain'**
  String get p2pPayoutTabOnchain;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/LightningPayout.tsx:346`).
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get p2pPayoutAdvancedOptions;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/LightningPayout.tsx:391`).
  ///
  /// In en, this message translates to:
  /// **'Routing Budget'**
  String get p2pPayoutRoutingBudget;

  /// The official client's text (`Forms/LightningPayout.tsx:305` at commit ff1998c), which `en.json` and `fr.json` miss (shown untranslated there); the French is the project's: the routing budget above 10,000 ppm, said, not refused.
  ///
  /// In en, this message translates to:
  /// **'Too high! (That is more than 1%)'**
  String get p2pPayoutBudgetTooHigh;

  /// The official client's text (`Forms/LightningPayout.tsx:412` at commit ff1998c), which `en.json` and `fr.json` miss (shown untranslated there); the French is the project's: the unit of the routing budget, parts per million.
  ///
  /// In en, this message translates to:
  /// **'PPM'**
  String get p2pPayoutUnitPpm;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/LightningPayout.tsx:558`), « sats » in lower case as the owner decided for #250 (validated on 2026-11-24). {amountSats} is the amount the invoice must be for. Said only where no breakdown is drawn (amounts that do not agree), the breakdown's « Your invoice » in its place otherwise.
  ///
  /// In en, this message translates to:
  /// **'Submit invoice for {amountSats} sats'**
  String p2pPayoutSubmitInvoiceFor(String amountSats);

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the copy button beside « Submit invoice for … Sats », which the reference draws as an icon only (`Forms/LightningPayout.tsx:565-576`).
  ///
  /// In en, this message translates to:
  /// **'Copy the amount'**
  String get p2pPayoutCopyAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/LightningPayout.tsx:609`).
  ///
  /// In en, this message translates to:
  /// **'Payout Lightning Invoice'**
  String get p2pPayoutInvoiceField;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/LightningPayout.tsx:651`, `Forms/OnchainPayout.tsx:159`).
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get p2pPayoutSubmit;

  /// Not in the RoboSats texts: the project's own: why « Submit » is off while a cancel of the trade runs, for the screen reader and a long press.
  ///
  /// In en, this message translates to:
  /// **'Submit is off while the trade is being cancelled.'**
  String get p2pPayoutSubmitWhileCancelling;

  /// The official client's text (`Forms/LightningPayout.tsx:120` at commit ff1998c), which `en.json` and `fr.json` miss (shown untranslated there); the French is the project's: an invoice for another amount than the one asked.
  ///
  /// In en, this message translates to:
  /// **'Invalid invoice amount'**
  String get p2pPayoutInvalidInvoiceAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:61`).
  ///
  /// In en, this message translates to:
  /// **'RoboSats coordinator will do a swap and send the Sats to your onchain address.'**
  String get p2pPayoutOnchainIntro;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:71`).
  ///
  /// In en, this message translates to:
  /// **'Swap fee'**
  String get p2pPayoutSwapFee;

  /// The official client's figure (`Forms/OnchainPayout.tsx:66-70`): the swap fee in sats and as the coordinator's percentage.
  ///
  /// In en, this message translates to:
  /// **'{sats} Sats ({percent}%)'**
  String p2pPayoutSwapFeeValue(String sats, String percent);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:83`).
  ///
  /// In en, this message translates to:
  /// **'Mining fee'**
  String get p2pPayoutMiningFee;

  /// The official client's figure (`Forms/OnchainPayout.tsx:78-82`): the mining fee over 280 vB and its rate.
  ///
  /// In en, this message translates to:
  /// **'{sats} Sats ({rate} Sats/vByte)'**
  String p2pPayoutMiningFeeValue(String sats, String rate);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:101`).
  ///
  /// In en, this message translates to:
  /// **'Final amount you will receive'**
  String get p2pPayoutFinalAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:118`).
  ///
  /// In en, this message translates to:
  /// **'Bitcoin Address'**
  String get p2pPayoutAddressField;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:132`).
  ///
  /// In en, this message translates to:
  /// **'Mining Fee'**
  String get p2pPayoutMiningFeeField;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Forms/OnchainPayout.tsx:131`): a mining fee rate outside 2 to 500 sat/vB.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get p2pPayoutInvalid;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/RoutingFailed.tsx:36`).
  ///
  /// In en, this message translates to:
  /// **'Failure reason:'**
  String get p2pPayoutFailureReason;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/RoutingFailed.tsx:68`).
  ///
  /// In en, this message translates to:
  /// **'Retrying!'**
  String get p2pPayoutRetrying;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/RoutingFailed.tsx:145`).
  ///
  /// In en, this message translates to:
  /// **'Next attempt in'**
  String get p2pPayoutNextAttempt;

  /// The official client's countdown (`Prompts/RoutingFailed.tsx:76`, two digits each); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String p2pPayoutCountdown(String minutes, String seconds);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/RoutingFailed.tsx:95`).
  ///
  /// In en, this message translates to:
  /// **'Your invoice has expired or more than 3 payment attempts have been made. Submit a new invoice.'**
  String get p2pPayoutInvoiceExpiredSubmitNew;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/RoutingFailed.tsx:138`).
  ///
  /// In en, this message translates to:
  /// **'RoboSats will try to pay your invoice 3 times with a one minute pause in between. If it keeps failing, you will be able to submit a new invoice. Check whether you have enough inbound liquidity. Remember that lightning nodes must be online in order to receive payments.'**
  String get p2pPayoutWillRetry;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated (`Prompts/RoutingFailed.tsx:39`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Payment isn\'t failed (yet)'**
  String get p2pPayoutFailureNotYet;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'There are more routes to try, but the payment timeout was exceeded.'**
  String get p2pPayoutFailureTimeout;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'All possible routes were tried and failed permanently. Or there were no routes to the destination at all.'**
  String get p2pPayoutFailureNoRoute;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'A non-recoverable error has occurred.'**
  String get p2pPayoutFailureNonRecoverable;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Payment details are incorrect (unknown hash, invalid amount or invalid final CLTV delta).'**
  String get p2pPayoutFailureIncorrect;

  /// The coordinator's label (`api/models/ln_payment.py`, `LNPayment.FailureReason`, commit ff1998c), which the official client shows untranslated; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Insufficient unlocked balance in RoboSats\' node.'**
  String get p2pPayoutFailureBalance;

  /// Not in the RoboSats texts: the project's own: a failure label the package does not know (it keeps no coordinator text).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} gave a reason this app does not know.'**
  String p2pPayoutFailureUnknown(String coordinator);

  /// The coordinator's message for error 3000 (`api/errors.py:69`, commit ff1998c), which the official client shows under the field (`TradeBox/index.tsx:231-232`); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You submitted an empty invoice'**
  String get p2pPayoutRefusedEmptyInvoice;

  /// The coordinator's text (`api/lightning/lnd.py:463-533`, commit ff1998c), which the official client shows under the field; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Does not look like a valid lightning invoice'**
  String get p2pPayoutRefusedNotInvoice;

  /// The coordinator's text (`api/lightning/lnd.py`, commit ff1998c), which the official client shows under the field; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The invoice hinted private routes are not payable within the submitted routing budget. This can be adjusted with Advanced Options enabled.'**
  String get p2pPayoutRefusedRouteHints;

  /// The coordinator's text (`api/lightning/lnd.py:508-512`, commit ff1998c), which the official client shows under the field; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The invoice provided has no explicit amount'**
  String get p2pPayoutRefusedNoAmount;

  /// The coordinator's text (`api/lightning/lnd.py:514-520`, commit ff1998c), which the official client shows under the field; {amount} is the amount the coordinator expects, read from its own message (review of #132); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The invoice provided is not for {amount} Sats'**
  String p2pPayoutRefusedWrongAmount(String amount);

  /// The coordinator's text (`api/lightning/lnd.py:529-533`, commit ff1998c), which the official client shows under the field; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The invoice provided has already expired'**
  String get p2pPayoutRefusedExpired;

  /// The coordinator's message for error 3002 (`api/errors.py:71`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You must submit a NEW invoice'**
  String get p2pPayoutRefusedNewInvoice;

  /// The coordinator's message for error 3001 (`api/errors.py:70`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You can only submit an invoice after expiration or 3 failed attempts'**
  String get p2pPayoutRefusedNotNow;

  /// The coordinator's message for error 1016 (`api/errors.py:19`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You cannot submit an address now.'**
  String get p2pPayoutRefusedAddressNotNow;

  /// The coordinator's message for error 1017 (`api/errors.py:20`, commit ff1998c), also said for an address (1015); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Only the buyer of this order can provide a buyer invoice.'**
  String get p2pPayoutRefusedNotBuyer;

  /// The coordinator's message for error 1048 (`api/errors.py:55`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The PGP signed cleartext message is not valid.'**
  String get p2pPayoutRefusedSignature;

  /// The coordinator's message for error 1047 (`api/errors.py:54`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You are not a participant in this order'**
  String get p2pPayoutRefusedNotParticipant;

  /// The coordinator's message for error 4000 (`api/errors.py:77`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'You submitted an empty address'**
  String get p2pPayoutRefusedEmptyAddress;

  /// The coordinator's message for error 4001 (`api/errors.py:78`, commit ff1998c), {rate} its minimum; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The mining fee is too low. Must be higher than {rate} Sat/vbyte'**
  String p2pPayoutRefusedFeeTooLow(String rate);

  /// The start of the coordinator's message for error 4001 (`api/errors.py:78`, commit ff1998c), when its minimum could not be read; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The mining fee is too low.'**
  String get p2pPayoutRefusedFeeTooLowNoRate;

  /// The coordinator's message for error 4002 (`api/errors.py:79`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The mining fee is too high, must be less than 500 Sats/vbyte'**
  String get p2pPayoutRefusedFeeTooHigh;

  /// The coordinator's message for error 4003 (`api/errors.py:80`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'The amount remaining after subtracting mining fee is close to dust limit.'**
  String get p2pPayoutRefusedDust;

  /// The coordinator's text (`api/utils.py:106-121`, commit ff1998c), which the official client shows under the field; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get p2pPayoutRefusedInvalidAddress;

  /// The coordinator's text (`api/utils.py:106-121`, commit ff1998c); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Unable to validate address, check bitcoind backend'**
  String get p2pPayoutRefusedUnverifiable;

  /// Not in the RoboSats texts: the project's own: a refusal of the coordinator the reference has no text for, or that this app does not know (a request that never reached the coordinator has `p2pPayoutNotReached`).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} refused your payout info.'**
  String p2pPayoutRefusedOther(String coordinator);

  /// Not in the RoboSats texts: the project's own: the request never reached the coordinator (a busy transport every time, the robot released).
  ///
  /// In en, this message translates to:
  /// **'Your payout info did not reach {coordinator}: nothing was recorded. You can submit again.'**
  String p2pPayoutNotReached(String coordinator);

  /// Not in the RoboSats texts: the project's own: the status shown was not stored with its order, so nothing can be checked or sent from it.
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again to give your payout info.'**
  String get p2pPayoutNeedsARead;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not ask for your payout info now.'**
  String p2pPayoutNotAsked(String coordinator);

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not give the amount to receive yet.'**
  String p2pPayoutAmountUnknown(String coordinator);

  /// Not in the RoboSats texts: the project's own: in place of the decoder's error text that the reference shows.
  ///
  /// In en, this message translates to:
  /// **'This is not a Lightning invoice this app can read.'**
  String get p2pPayoutInvoiceUnreadable;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'This invoice is for another network than the trade\'s.'**
  String get p2pPayoutInvoiceOtherNetwork;

  /// Not in the RoboSats texts: the project's own: an invoice with no amount, or for a fraction of a sat (a deviation, `AGENTS.md`).
  ///
  /// In en, this message translates to:
  /// **'The invoice must ask for exactly the Sats shown, with no fraction of a sat.'**
  String get p2pPayoutInvoiceWholeSats;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'This is not a Bitcoin address.'**
  String get p2pPayoutAddressMalformed;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'This address has a typo: its checksum is wrong.'**
  String get p2pPayoutAddressBadChecksum;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'This address is for another network than the trade\'s.'**
  String get p2pPayoutAddressOtherNetwork;

  /// Not in the RoboSats texts: the project's own: a valid segwit address of a version the coordinator's node may not pay.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} may not be able to pay this kind of address.'**
  String p2pPayoutAddressUnsupported(String coordinator);

  /// Not in the RoboSats texts: the project's own: the invoice expires before the step's end and a day (design note § 4.4); information, never a refusal; {date} and {time} written as in the table above it.
  ///
  /// In en, this message translates to:
  /// **'This invoice expires on {date} at {time}. If the seller confirms after that, {coordinator} cannot pay it and will ask you for a new one.'**
  String p2pPayoutWarnExpiresFirst(
    String date,
    String time,
    String coordinator,
  );

  /// Not in the RoboSats texts: the project's own: what the address would receive is under the coordinator's minimum (`api/logics.py:815-820`); information, the coordinator refuses it.
  ///
  /// In en, this message translates to:
  /// **'Less than 20,000 Sats would reach this address: {coordinator} will refuse it.'**
  String p2pPayoutWarnBelowMinimum(String coordinator);

  /// Not in the RoboSats texts: the project's own: why « Onchain » is disabled for an order in bitcoin (`Prompts/Payout.tsx:98`).
  ///
  /// In en, this message translates to:
  /// **'An order in bitcoin is paid on Lightning only.'**
  String get p2pPayoutOnchainSwapOrder;

  /// Not in the RoboSats texts: the project's own: the coordinator's `swap_failure_reason`, which the reference does not show, read as a kind (`SwapRefusal`).
  ///
  /// In en, this message translates to:
  /// **'The amount is below the smallest swap {coordinator} offers.'**
  String p2pPayoutSwapBelowMinimum(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator's `swap_failure_reason`, read as a kind.
  ///
  /// In en, this message translates to:
  /// **'The amount is above the largest swap {coordinator} offers.'**
  String p2pPayoutSwapAboveMaximum(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator's `swap_failure_reason`, read as a kind.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not offer swaps.'**
  String p2pPayoutSwapDisabled(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator's `swap_failure_reason`, read as a kind.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not have enough on-chain funds for a swap.'**
  String p2pPayoutSwapNoLiquidity(String coordinator);

  /// Not in the RoboSats texts: the project's own: no on-chain payout offered, for a reason the app does not know.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} does not offer an on-chain payout for this order.'**
  String p2pPayoutSwapUnavailable(String coordinator);

  /// Not in the RoboSats texts: the project's own: the wait before the payout is signed (the owner's request: each wait says what it waits for).
  ///
  /// In en, this message translates to:
  /// **'Reading your robot from {coordinator} and unlocking its key. The first time takes a few seconds.'**
  String p2pPayoutStepUnlocking(String coordinator);

  /// Not in the RoboSats texts: the project's own: the read just before the payout is signed.
  ///
  /// In en, this message translates to:
  /// **'Reading the order from {coordinator}…'**
  String p2pPayoutStepReading(String coordinator);

  /// Not in the RoboSats texts: the project's own: the payout sent, its answer awaited.
  ///
  /// In en, this message translates to:
  /// **'Sending your payout info to {coordinator}…'**
  String p2pPayoutStepSending(String coordinator);

  /// Not in the RoboSats texts: the project's own: the read after the answer.
  ///
  /// In en, this message translates to:
  /// **'Reading the order again from {coordinator}…'**
  String p2pPayoutStepReadingAfter(String coordinator);

  /// Not in the RoboSats texts: the project's own: a take, a cancel or another payout of the order is under way, and the payout waits for it.
  ///
  /// In en, this message translates to:
  /// **'Waiting for another action on this order to end…'**
  String get p2pPayoutStepWaitingForOrder;

  /// Not in the RoboSats texts: the project's own: the trade opened from its records, the first thing « Submit » does.
  ///
  /// In en, this message translates to:
  /// **'Opening the trade…'**
  String get p2pPayoutStepOpening;

  /// Not in the RoboSats texts: the project's own: the coordinator recorded the payout.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} received your payout info.'**
  String p2pPayoutGiven(String coordinator);

  /// Not in the RoboSats texts: the project's own: the payout may have been recorded; nothing is sent again.
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether {coordinator} received your payout info. It keeps checking while this screen is open.'**
  String p2pPayoutUnknown(String coordinator);

  /// Not in the RoboSats texts: the project's own: a read sent after a payout that was received or may have been still shows the coordinator asking for one.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} still asks for your payout info: the last you gave was not recorded. You can submit again.'**
  String p2pPayoutAskedAgain(String coordinator);

  /// Not in the RoboSats texts: the project's own: what the user would see changed with the read just before signing, other than the amount, the invoice's expiry or the status; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent: what is shown changed since you saw it. Check it again before you submit.'**
  String get p2pPayoutChanged;

  /// Not in the RoboSats texts: the project's own: the amount asked or received changed with the read just before signing; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent: the amount changed since it was shown. Check it again before you submit.'**
  String get p2pPayoutChangedAmount;

  /// Not in the RoboSats texts: the project's own: with the read just before signing, the invoice now expires before the step's end and a day; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent: this invoice now expires before the step could end. Check it again before you submit.'**
  String get p2pPayoutChangedExpiry;

  /// Not in the RoboSats texts: the project's own: the status carries a warning it did not with the read just before signing; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent: the trade\'s status changed since it was shown. Check it again before you submit.'**
  String get p2pPayoutChangedStatus;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'The key of your robot could not be read from {coordinator}. Nothing was sent.'**
  String p2pPayoutNotSentKey(String coordinator);

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'Could not read the order from {coordinator}. Nothing was sent.'**
  String p2pPayoutNotSentRead(String coordinator);

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'The key of your robot could not sign this. Nothing was sent.'**
  String get p2pPayoutNotSentSign;

  /// Not in the RoboSats texts: the project's own.
  ///
  /// In en, this message translates to:
  /// **'This trade cannot be opened now. Nothing was sent.'**
  String get p2pPayoutNotSentTrade;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: the Instant payments wallet's spendable balance, as the wallet reads it.
  ///
  /// In en, this message translates to:
  /// **'Instant payments: {balance} sats available'**
  String p2pPayBalance(String balance);

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: the button that asks the swap service for its quote; nothing is paid before the confirmation.
  ///
  /// In en, this message translates to:
  /// **'Pay with this wallet'**
  String get p2pPayWithThisWallet;

  /// The panel of « Pay with this wallet » (#100, #135): ours, with the wallet's label « Swap fees » (`transactionDetailLabelSwapFees`); the wallet has no text for asking them; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Getting the swap fees…'**
  String get p2pPayQuoting;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the first row of the lean confirmation of « Pay with this wallet » for a collateral (a maker seller's, #188, and a taker seller's, #249): the invoice's sats, which the coordinator asks.
  ///
  /// In en, this message translates to:
  /// **'Collateral'**
  String get p2pPayRowCollateral;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the first row of the lean confirmation of « Pay with this wallet » for a bond (a maker's, #180, and a taker's, #249), in place of p2pPayRowCollateral: the invoice's sats, which the coordinator asks; « bond » / « caution » as the reference's words for it.
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get p2pPayRowBond;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the second row of the lean confirmation: the swap fees and the network fee together, the sum of the two rows of its detail (p2pPayRowSwapFees, p2pPayRowNetworkFee), so that the row, the total and the invoice add up.
  ///
  /// In en, this message translates to:
  /// **'Swap and network fees'**
  String get p2pPayRowFees;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): an amount of the lean confirmation's rows, « sats » in lower case as the owner's vocabulary of 2026-11-24 writes it (p2pAmountSats, « Sats », stays for the other screens). {amount} is a number of sats written in the conventions of the language.
  ///
  /// In en, this message translates to:
  /// **'{amount} sats'**
  String p2pPayAmountSats(String amount);

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): in the detail of the lean confirmation of a bond or a collateral (#250), the swap service's fee, the wallet's label (`transactionDetailLabelSwapFees`), in French with the reference's word « swap ».
  ///
  /// In en, this message translates to:
  /// **'Swap fees'**
  String get p2pPayRowSwapFees;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): in the detail of the lean confirmation of a bond or a collateral (#250), the wallet's estimate of the Liquid network fee, kept by the wording the owner validated on 2026-11-24.
  ///
  /// In en, this message translates to:
  /// **'Network fee (estimate)'**
  String get p2pPayRowNetworkFee;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): in bold under a rule, the lean confirmation's total: what « Pay » takes out of the wallet (the invoice, the swap fees and the network fee), the same sats as the button and as the alert's « this one ».
  ///
  /// In en, this message translates to:
  /// **'Total to pay'**
  String get p2pPayRowTotal;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): in the confirmation's detail: what stays in the wallet's Instant payments once the total has left it.
  ///
  /// In en, this message translates to:
  /// **'Balance after payment'**
  String get p2pPayRowLeft;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): in the detail of a collateral's confirmation only (#97): the facts of a whole trade paid through the swap service (the service holds the payin until the coordinator settles or cancels the hold invoice, and refunds it to the wallet without its fees when it is cancelled); informs, never stops; never for a bond.
  ///
  /// In en, this message translates to:
  /// **'Until the trade ends, these sats are with the swap service, not in this wallet. If the trade is cancelled, they come back to Instant payments, less the swap and network fees, sometimes with a delay.'**
  String get p2pPayEscrowHeld;

  /// The confirmation of « Pay with this wallet » for the maker bond at status 0 (#180), the project's own text for the owner's payment rule of 2026-11-17 (RoboSats has no such rule, design note § 3.3): the bond the order implies at the wallet's own price of a bitcoin, read at the moment of paying, with the order's premium, and how far the invoice is from it. {price} is that price, {currency} the order's currency code, {expected} the bond expected in sats, {gap} the gap of the invoice with its sign and percent sign.
  ///
  /// In en, this message translates to:
  /// **'At the Bull wallet\'s price, {price} {currency}/BTC, with the order\'s premium, this bond is worth {expected} sats. Gap of the invoice: {gap}.'**
  String p2pPayRateWallet(
    String price,
    String currency,
    String expected,
    String gap,
  );

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the confirmation of a maker seller's collateral (#188), the owner's payment rule of 2026-11-17: {amount} is the contract's amount (the fixed amount, or a range's amount its take chose), {expected} its sats at the Bull wallet's price with the order's premium, {gap} how far the collateral asked is from them; the coordinator adds its maker fee (0.025 % by default, at most 1 %) to the collateral, so the gap includes it, and the text says so (#187, R1).
  ///
  /// In en, this message translates to:
  /// **'At the Bull wallet\'s price, {price} {currency}/BTC, with the order\'s premium, {amount} {currency} are worth {expected} sats. Gap of the collateral: {gap}, the coordinator\'s fee included.'**
  String p2pPayRateWalletEscrow(
    String price,
    String currency,
    String amount,
    String expected,
    String gap,
  );

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): in the detail of a collateral's confirmation, within the owner's threshold, when the coordinator asks more than Bull Wallet expects: {amount} the contract's amount or the amount taken, {price} the Bull wallet's price, {expected} the sats expected at it with the order's premium, rounded down, {gap} how much more is asked, in percent without its sign (the collateral includes the coordinator's fee). For a bond, or a collateral asked at or below the sats expected, the detail keeps p2pPayRateWallet or p2pPayRateWalletEscrow.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet redoes the calculation with its own price: {amount} {currency} at {price} {currency}/BTC, premium included, come to {expected} sats. The coordinator asks {gap} more, its fees included.'**
  String p2pPayRateDetail(
    String amount,
    String currency,
    String price,
    String expected,
    String gap,
  );

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the red alert's second line in the confirmation of a bond or a collateral, under p2pPayoutBreakdownAgainst, always shown with it above the buttons. {expected} the sats Bull Wallet expects at its own price with the order's premium (for a bond, its bond size of them), rounded down; {asked} the invoice's sats, the figure compared.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet expected {expected} sats, the coordinator asks {asked}.'**
  String p2pPayAgainstFigures(String expected, String asked);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the red alert's explanation, in the confirmation's detail, in place of the comparison's paragraph. {price} the Bull wallet's price of a bitcoin, {threshold} the owner's threshold, such as « 10% ».
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet redoes the calculation with its own price ({price} {currency}/BTC, premium included) and warns you beyond a {threshold} gap. Check the order before paying.'**
  String p2pPayAgainstDetail(String price, String currency, String threshold);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the explanation of « Amount not checked » (p2pPayoutBreakdownUnverified), in the confirmation's detail; « Pay » stays offered.
  ///
  /// In en, this message translates to:
  /// **'Without this price, it cannot compare the coordinator\'s amount. You can try again, or pay without this check.'**
  String get p2pPayUnverifiedDetail;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the bold line of the red alert of a maker seller's confirmation (#187, #188, the owner's decision of 2026-11-19: an alert, never a lock) when one earlier collateral of the order, of a known amount, paid or attempted with this wallet, has not come back; several, or an amount not known, keep p2pEscrowEarlierOut and its variants.
  ///
  /// In en, this message translates to:
  /// **'A previous collateral has not come back'**
  String get p2pPayEarlierNotBack;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the second line of p2pPayEarlierNotBack: {total} the earlier collateral's sats and this one's, each with its fees, the same sats as « Pay » for this one. The order's bond is not in it: p2pPayEscrowBondHeldToo says so beside it when this wallet paid the bond.
  ///
  /// In en, this message translates to:
  /// **'With this one, {total} sats will be out of this wallet.'**
  String p2pPayEarlierOutTotal(String total);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the explanation of p2pPayEarlierNotBack, in the confirmation's detail: {sats} the earlier collateral's sats with its fees.
  ///
  /// In en, this message translates to:
  /// **'You already paid, or tried to pay, a collateral of {sats} sats for this order with this wallet. It has not come back to it yet.'**
  String p2pPayEarlierNotBackDetail(String sats);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the bold line of a neutral block (no alert colour) of a maker seller's confirmation from the order's second take on (#188, design note § 4.3).
  ///
  /// In en, this message translates to:
  /// **'New contract'**
  String get p2pPayNewContractTitle;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the second line of p2pPayNewContractTitle.
  ///
  /// In en, this message translates to:
  /// **'The previous take of this order did not go through. This collateral is for the new contract.'**
  String get p2pPayNewContractLine;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the bold line of an orange block of a maker seller's confirmation shown again (#187, #188): just before the payment, under its lock, more was out than the confirmation before showed, or an earlier collateral's state changed; nothing was paid.
  ///
  /// In en, this message translates to:
  /// **'The amounts have changed'**
  String get p2pPayConfirmAgainTitle;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the second line of p2pPayConfirmAgainTitle.
  ///
  /// In en, this message translates to:
  /// **'Check them, then confirm again.'**
  String get p2pPayConfirmAgainLine;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the bold line of a red block of a maker seller's confirmation (#188) when a read shows the order taken again while it is open: its « Pay » would pay nothing and is not offered; never shown with p2pPayConfirmAgainTitle.
  ///
  /// In en, this message translates to:
  /// **'The order was taken again meanwhile'**
  String get p2pPayConfirmStaleTitle;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 1, the payment of the collateral, and of the bond in the same form); the English is composed on the model of the French, as #250 gives its examples): the second line of p2pPayConfirmStaleTitle.
  ///
  /// In en, this message translates to:
  /// **'This confirmation is no longer valid. Go back.'**
  String get p2pPayConfirmStaleLine;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: the confirmation's button, the only tap that pays.
  ///
  /// In en, this message translates to:
  /// **'Pay {total} sats'**
  String p2pPayConfirm(String total);

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: while the payment is made.
  ///
  /// In en, this message translates to:
  /// **'Sending the payment…'**
  String get p2pPaySending;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: the payment left this wallet; the coordinator has not locked the bond yet.
  ///
  /// In en, this message translates to:
  /// **'Payment sent. Waiting for {coordinator} to see your bond locked.'**
  String p2pPaySent(String coordinator);

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPaySent`: the payment left this wallet; the coordinator has not locked the escrow yet; « collateral » as the reference's title of the escrow (« Lock {{amountSats}} Sats as collateral »), « garantie » in French as the project's (#96).
  ///
  /// In en, this message translates to:
  /// **'Payment sent. Waiting for {coordinator} to see the collateral locked.'**
  String p2pPayEscrowSent(String coordinator);

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendFailedRefunding`, then ours for the fees (the wallet has no text for it); in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap will be refunded shortly. The swap fees are not refunded.'**
  String get p2pPayRefundPending;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendCompletedRefunded`, then ours for the fees; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap has been refunded. The swap fees are not refunded.'**
  String get p2pPayRefunded;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: the hold invoice was settled: the bond is lost, as with any wallet.
  ///
  /// In en, this message translates to:
  /// **'Your bond was kept by {coordinator}.'**
  String p2pPaySettled(String coordinator);

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): the swap paid the escrow's hold invoice and the coordinator charged it, said in the panel only while the escrow step is still shown; « collateral » as the reference's title of the escrow (« Lock {{amountSats}} Sats as collateral »), « garantie » in French as the project's (#96).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} received the collateral.'**
  String p2pPayEscrowSettled(String coordinator);

  /// The panel of « Pay with this wallet » (#100, #135): ours (the wallet shows no text for a manual review), worded as its swap statuses; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap is under review. Contact Bull Bitcoin support if it lasts.'**
  String get p2pPayUnderReview;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: a payment signed and saved but never broadcast; this wallet does not pay the invoice again.
  ///
  /// In en, this message translates to:
  /// **'The payment was interrupted before it was sent. Nothing left this wallet yet.'**
  String get p2pPayInterrupted;

  /// The panel of « Pay with this wallet » (#100, #135): ours: a broadcast whose outcome is unknown, which the wallet's watcher settles.
  ///
  /// In en, this message translates to:
  /// **'The payment may have been sent. Its status will update shortly.'**
  String get p2pPayMaybeSent;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendFailed` (in sentence case), then ours: support is the only way out; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayAskSupport;

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPayAskSupport` (the wallet's `coreSwapsLnSendFailed`, then ours); in French the wallet's sentence with the reference's word for the swap, « swap », as the bond's.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. The sats of this collateral may have left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayEscrowAskSupport;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's Send screen, `sendErrorAmountBelowMinimum`; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Amount below minimum swap limit: {min} sats'**
  String p2pPayUnderMinimum(String min);

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's Send screen, `sendErrorAmountBelowSwapLimits`, when the service gives no minimum; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Amount is below swap limits'**
  String get p2pPayUnderMinimumUnknown;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's Send screen, `sendErrorAmountAboveMaximum`; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Amount above maximum swap limit: {max} sats'**
  String p2pPayOverMaximum(String max);

  /// The panel of « Pay with this wallet » (#100, #135): ours, worded on the wallet's `sendErrorAmountBelowSwapLimits` / `sendErrorAmountAboveSwapLimits`: the service did not say which limit; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Amount is outside swap limits'**
  String get p2pPayOutsideLimits;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: a refusal.
  ///
  /// In en, this message translates to:
  /// **'Not enough in Instant payments ({balance} sats) for {total} sats.'**
  String p2pPayNotEnough(String balance, String total);

  /// The panel of « Pay with this wallet » (#100, #135): ours, worded on the wallet's `mempoolErrorServerUnavailable` with « Swap » so that the user does not take the coordinator for down.
  ///
  /// In en, this message translates to:
  /// **'Swap server is unavailable. Please try again later.'**
  String get p2pPayUnreachable;

  /// The panel of « Pay with this wallet » (#100, #135): ours: the swap service answered « too many requests »; the wallet's « Rate limited » is jargon (« taux » reads as an interest rate in French).
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get p2pPayBusy;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: a refusal.
  ///
  /// In en, this message translates to:
  /// **'Too little time is left to pay from this wallet.'**
  String get p2pPayTooLate;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: a refusal; nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'The fees changed since you confirmed. Check them again.'**
  String get p2pPayFeesChanged;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4: a refusal: the wallet never pays an invoice twice.
  ///
  /// In en, this message translates to:
  /// **'This wallet already paid this invoice.'**
  String get p2pPayAlreadyPaid;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4, not in the study's table: the read just before the payment no longer offers the invoice confirmed.
  ///
  /// In en, this message translates to:
  /// **'The order moved on before the payment. Nothing was paid.'**
  String get p2pPayOrderMoved;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4, not in the study's table: the payment's record is written before the wallet is asked.
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not write its records on this device. Nothing was paid.'**
  String get p2pPayNotRecorded;

  /// The panel of « Pay with this wallet » at status 3 (#100), the project's own text (RoboSats has no such panel: the owner's request), from the study of #100 § 4, not in the study's table: the other refusals of the wallet (no Instant payments wallet, unreadable, other network, too many coins, a quote no longer valid).
  ///
  /// In en, this message translates to:
  /// **'This wallet cannot pay this bond now.'**
  String get p2pPayWalletUnavailable;

  /// The panel of « Pay with this wallet » at status 6 and 7 of an order made here whose user sells (#187), the project's own text (RoboSats has no such panel: the owner's request): the collateral invoice shown has a payment hash this device already saw (an earlier take's collateral, another payment recorded for the order, or a payment of another trade), whether or not it was ever paid; « collateral » as the reference's title of the escrow, « garantie » in French as the project's (#96).
  ///
  /// In en, this message translates to:
  /// **'This collateral invoice was already presented to this device, for this order or another one. It is not paid from this wallet.'**
  String get p2pPayEscrowShownBefore;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the confirmation of a maker seller's collateral shown again (#187, #188), at its top in the warning colour: just before the payment, under its lock, more was out than the confirmation showed (this collateral's quote costing more, more sats of earlier collaterals not back, or one the coordinator kept since): nothing was paid, the figures below are those now, and the next « Pay » pays (the owner's decision of 2026-11-19: no lock). Says « or the state of an earlier collateral », true when only an earlier collateral turned kept (security review of #187, R12).
  ///
  /// In en, this message translates to:
  /// **'Since you confirmed, what will leave this wallet, or the state of an earlier collateral, changed. Nothing was paid: check the figures below and confirm again.'**
  String get p2pPayConfirmAgain;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the panel of « Pay with this wallet » of a maker seller's collateral (#188, security review of #187, R2), when the payment is refused because the contract the confirmation stated is no longer the trail's (`BondPayContractNotConfirmed`): the confirmation always states its contract since #188, so this is the order taken again meanwhile.
  ///
  /// In en, this message translates to:
  /// **'The order was taken again before the payment: the confirmation was for the earlier take. Nothing was paid.'**
  String get p2pPayContractMoved;

  /// The confirmation of a maker seller's collateral (#187, shown since #188), the project's own text (RoboSats has no such panel: the owner's request): the red alert of the owner's decision of 2026-11-19 (no lock, an alert), the user free to pay. {sats} the sats of the earlier collaterals not back yet (a refund pending included, which Bull's own code does not take as final), {total} those and this collateral's. {count} how many; the sats are what each took out of the wallet (the confirmed quote's total, fees included), so that the total and the confirmation's « Pay » button speak of the same sats. The total counts the collaterals only: a maker bond paid from this wallet, held for the order's life, is not in it, and the text says so (security review of #187, C5).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{An earlier collateral of this order, paid or attempted with this wallet, has not come back yet} other{{count} earlier collaterals of this order, paid or attempted with this wallet, have not come back yet}}: {sats} sats. With this one, {total} sats will be out of this wallet for the collaterals of this order, bond not included.'**
  String p2pEscrowEarlierOut(String sats, String total, int count);

  /// As p2pEscrowEarlierOut (#187), the project's own text (RoboSats has no such panel: the owner's request), when some earlier collaterals not back were paid before the app started again: their sats are not kept on the device (schema 8). {count} how many. {known} how many have an amount this device knows. The total counts the collaterals only: a maker bond paid from this wallet, held for the order's life, is not in it, and the text says so (security review of #187, C5).
  ///
  /// In en, this message translates to:
  /// **'{known, plural, =1{An earlier collateral of this order, paid or attempted with this wallet, has not come back yet: {sats} sats} other{{known} earlier collaterals of this order, paid or attempted with this wallet, have not come back yet: {sats} sats}}, and {count, plural, =1{1 more whose amount this device no longer knows} other{{count} more whose amounts this device no longer knows}}. With this one, at least {total} sats will be out of this wallet for the collaterals of this order, bond not included.'**
  String p2pEscrowEarlierOutUnknown(
    String sats,
    String total,
    int count,
    int known,
  );

  /// As p2pEscrowEarlierOut (#187), the project's own text, when no earlier collateral not back has an amount this device knows (paid before the app started again; schema 8 keeps no amount). {count} how many, {total} this collateral's sats. The total counts the collaterals only: a maker bond paid from this wallet, held for the order's life, is not in it, and the text says so (security review of #187, C5).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{An earlier collateral of this order, paid or attempted with this wallet, has not come back yet; this device no longer knows its amount.} other{{count} earlier collaterals of this order, paid or attempted with this wallet, have not come back yet; this device no longer knows their amounts.}} With this one, at least {total} sats will be out of this wallet for the collaterals of this order, bond not included.'**
  String p2pEscrowEarlierOutAllUnknown(String total, int count);

  /// The confirmation of a maker seller's collateral (#187, shown since #188), the project's own text (RoboSats has no such panel: the owner's request): an earlier collateral of the order paid with this wallet was settled, the coordinator kept it (a red alert, apart from those not back yet, the owner's decision of 2026-11-19). {coordinator} the coordinator's name of the federation list.
  ///
  /// In en, this message translates to:
  /// **'The collateral of an earlier take ({sats} sats) was kept by {coordinator}: check this order in the official RoboSats app before paying another one.'**
  String p2pEscrowEarlierKept(String sats, String coordinator);

  /// As p2pEscrowEarlierKept (#187), the project's own text (RoboSats has no such panel: the owner's request), for a collateral whose sats this device no longer knows (paid before the app started again).
  ///
  /// In en, this message translates to:
  /// **'The collateral of an earlier take was kept by {coordinator}: check this order in the official RoboSats app before paying another one.'**
  String p2pEscrowEarlierKeptUnknown(String coordinator);

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the confirmation of a maker seller's collateral (#188), in red beside p2pEscrowEarlierOut and its variants, whose total leaves the bond out (security review of #187, C5), when the trade's records say the maker bond was paid with this wallet.
  ///
  /// In en, this message translates to:
  /// **'Your order\'s bond was paid with this wallet: it is out of this wallet too until the order ends, and is not in this total.'**
  String get p2pPayEscrowBondHeldToo;

  /// As p2pPayEscrowBondHeldToo (#188), the project's own, when the records cannot tell whether the maker bond was paid with this wallet.
  ///
  /// In en, this message translates to:
  /// **'If your order\'s bond was paid with this wallet, it is out of this wallet too until the order ends, and is not in this total.'**
  String get p2pPayEscrowBondMaybeHeldToo;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the trade screen of a maker seller's order taken more than once (#188), above one line per earlier take, whatever the status, the trade's end included, until each is back (design note § 2.3, § 4.3).
  ///
  /// In en, this message translates to:
  /// **'Collaterals of earlier takes of this order, paid or attempted with this wallet:'**
  String get p2pEscrowsEarlierTitle;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a line under p2pEscrowsEarlierTitle (#188): {take} counts the takes from 1, {state} one of the p2pEscrowState… texts.
  ///
  /// In en, this message translates to:
  /// **'Take {take}: {state}'**
  String p2pEscrowsEarlierLine(String take, String state);

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): the swap was refunded (back).
  ///
  /// In en, this message translates to:
  /// **'back, refunded to this wallet without the swap fees and the network fee'**
  String get p2pEscrowStateRefunded;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): nothing was sent: an attempt that failed or expired with nothing sent, or no swap order of this feature for it (back).
  ///
  /// In en, this message translates to:
  /// **'back, nothing left this wallet'**
  String get p2pEscrowStateNothingSent;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): a refund pending, which Bull's own code does not take as final (not back yet, security review of #187, C2).
  ///
  /// In en, this message translates to:
  /// **'not back yet, the swap service is refunding it'**
  String get p2pEscrowStateRefundPending;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): a swap order prepared or signed and never known as sent (counted not back, with no limit of time, security review of #187, R8).
  ///
  /// In en, this message translates to:
  /// **'not back yet, its swap was being prepared and may never have been sent'**
  String get p2pEscrowStatePreparing;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): a broadcast whose outcome is not known (not back yet).
  ///
  /// In en, this message translates to:
  /// **'not back yet, the payment may have been sent'**
  String get p2pEscrowStateMaybeSent;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): sent to the swap service, not yet seen paying the invoice (not back yet).
  ///
  /// In en, this message translates to:
  /// **'not back yet, with the swap service'**
  String get p2pEscrowStateWithService;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): the swap service's manual review (not back yet).
  ///
  /// In en, this message translates to:
  /// **'not back yet, under review at the swap service; contact Bull Bitcoin support if it lasts'**
  String get p2pEscrowStateUnderReview;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): a swap failed or expired whose funds may have left (not back yet).
  ///
  /// In en, this message translates to:
  /// **'not back yet, the swap failed and its sats may have left this wallet; contact Bull Bitcoin support'**
  String get p2pEscrowStateAskSupport;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): the records, or the wallet's, cannot be read, or the wallet does not hold the payment recorded (security review of #187, R6); counted not back.
  ///
  /// In en, this message translates to:
  /// **'state unknown, this device cannot tell where it stands'**
  String get p2pEscrowStateUnknown;

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): the swap service paid the hold invoice and the coordinator holds it (`P2pWalletPaymentPending`, not back yet).
  ///
  /// In en, this message translates to:
  /// **'not back yet, paid by the swap service and held by {coordinator}'**
  String p2pEscrowStateHeld(String coordinator);

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): a state of p2pEscrowsEarlierLine (#188): settled, the coordinator kept it (`P2pWalletPaymentPaid`), said in the colour of an error.
  ///
  /// In en, this message translates to:
  /// **'kept by {coordinator}'**
  String p2pEscrowStateKept(String coordinator);

  /// Not in the RoboSats texts: the project's own (RoboSats has no « Pay with this wallet »: the owner's request): the trade screen of a maker seller's order (#188, security review of #187, C2): in red, an escrow whose refund was pending and which the wallet's records now show paying the hold invoice again; a refund pending is not final in Bull's own code. {take} counts the takes from 1.
  ///
  /// In en, this message translates to:
  /// **'The collateral of take {take} was being refunded, and is now held by {coordinator} again: check this order in the official RoboSats app.'**
  String p2pEscrowRefundUndoneHeld(String take, String coordinator);

  /// As p2pEscrowRefundUndoneHeld (#188), the project's own, when the wallet's records now show it settled (`P2pWalletPaymentPaid`).
  ///
  /// In en, this message translates to:
  /// **'The collateral of take {take} was being refunded, and was then kept by {coordinator}: check this order in the official RoboSats app.'**
  String p2pEscrowRefundUndoneKept(String take, String coordinator);

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPayWalletUnavailable`; « collateral » as the reference's title of the escrow (« Lock {{amountSats}} Sats as collateral »), « garantie » in French as the project's (#96).
  ///
  /// In en, this message translates to:
  /// **'This wallet cannot pay this collateral now.'**
  String get p2pPayEscrowWalletUnavailable;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendFailed` (in sentence case) and `coreSwapsLnSendFailedRefunding`, then ours for the fees; at status 3, where the bond was never locked; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. Swap will be refunded shortly. The swap fees are not refunded.'**
  String get p2pPayServiceCouldNotPay;

  /// The panel of « Pay with this wallet » (#100, #135): the first sentence of the wallet's `transactionSwapDescLnSendDefault`: a payment sent, outside a trade going on; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Your swap is in progress.'**
  String get p2pPayWithSwapService;

  /// The panel of « Pay with this wallet » (#100), the project's own text, not in the study's table, worded on the take's: the order could not be read again just before the payment; « Pay with this wallet » stays offered.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {coordinator}. Nothing was paid.'**
  String p2pPayCoordinatorUnreachable(String coordinator);

  /// The panel of « Pay with this wallet » (#100), the project's own text: the read just before the payment was overtaken twice by another read of the trade, so its answer was not kept (#141); the order did not necessarily move on. « Pay with this wallet » stays offered.
  ///
  /// In en, this message translates to:
  /// **'Could not read the order from {coordinator} just now. Nothing was paid.'**
  String p2pPayReadSuperseded(String coordinator);

  /// The panel of « Pay with this wallet » (#100, #135): ours: after 30 s of « Sending the payment… ».
  ///
  /// In en, this message translates to:
  /// **'Still sending. This can take a few minutes.'**
  String get p2pPayStillSending;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendFailed` (in sentence case), then ours: its funding was broadcast; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. The sats of this bond left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayAskSupportSent;

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPayAskSupportSent`; in French the wallet's sentence with the reference's word for the swap, « swap », as the bond's.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. The sats of this collateral left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayEscrowAskSupportSent;

  /// The panel of « Pay with this wallet » (#100), the project's own text, not in the study's table: the records, or the wallet's, cannot be read; nothing is paid.
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot read where this payment stands.'**
  String get p2pPayUnreadable;

  /// The panel of « Pay with this wallet » (#100, #135): ours, not the reference's: under its text of the cancel dialog at status 3, for a payment on its way; with the wallet's label « Swap fees »; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'A payment of this bond is on its way from this wallet. Cancelling now costs the swap fees, and the refund may take time.'**
  String get p2pPayCancelNote;

  /// The panel of « Pay with this wallet » (#97), the project's own text: under the reference's text of the cancel dialog at 6 and 7 (the bond lost), for a payment of the escrow on its way. The reference does not cancel the escrow's hold invoice when the taker cancels (`api/logics.py` case 4.b, `publish_order` detaches it); its invoice follower returns a payment that locks it afterwards (`follow_invoices.py`, « Weird! »), the swap service then refunding the wallet; in French the wallet's sentence with the reference's word for the swap, « swap », as the bond's.
  ///
  /// In en, this message translates to:
  /// **'A payment of this collateral is on its way from this wallet. Cancelling does not stop it: if it reaches the coordinator, the coordinator returns it, then the swap service refunds it to Instant payments without the swap fees and the network fee. The refund may take time.'**
  String get p2pPayEscrowCancelNote;

  /// The panel of « Pay with this wallet » (#97), the project's own text: the line after the bond's step, prefixed with the payment's name while a payment of the escrow is followed too, so that the two lines are told apart; {line} is one of the swap's lines (« Swap will be refunded shortly. … »).
  ///
  /// In en, this message translates to:
  /// **'Bond: {line}'**
  String p2pPayLineBond(String line);

  /// The panel of « Pay with this wallet » (#97), the project's own text: the line after the escrow's step, always prefixed with the payment's name; « collateral » as the reference's title of the escrow, « garantie » in French as the project's (#96); {line} is one of the swap's lines.
  ///
  /// In en, this message translates to:
  /// **'Collateral: {line}'**
  String p2pPayLineEscrow(String line);

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendFailed` (in sentence case) and `coreSwapsLnSendCompletedRefunded`, then ours for the fees; at status 3, the refund done; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap failed. Swap has been refunded. The swap fees are not refunded.'**
  String get p2pPayServiceRefunded;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendExpired` (in sentence case), then ours: support is the only way out; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap expired. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayAskSupportExpired;

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPayAskSupportExpired`; in French the wallet's sentence with the reference's word for the swap, « swap », as the bond's.
  ///
  /// In en, this message translates to:
  /// **'Swap expired. The sats of this collateral may have left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayEscrowAskSupportExpired;

  /// The panel of « Pay with this wallet » (#100, #135): the wallet's `coreSwapsLnSendExpired` (in sentence case), then ours: its funding was broadcast; in French the wallet's sentence with the reference's word for the swap, « swap » (« SWAP VERS Lightning »), since the wallet's French word, « échange », is the P2P screens' word for the trade.
  ///
  /// In en, this message translates to:
  /// **'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayAskSupportExpiredSent;

  /// The panel of « Pay with this wallet » at status 6 and 7, the seller's escrow (#97), the project's own text (RoboSats has no such panel: the owner's request): as the bond's `p2pPayAskSupportExpiredSent`; in French the wallet's sentence with the reference's word for the swap, « swap », as the bond's.
  ///
  /// In en, this message translates to:
  /// **'Swap expired. The sats of this collateral left this wallet. Contact Bull Bitcoin support.'**
  String get p2pPayEscrowAskSupportExpiredSent;

  /// The official client's text, from its code (`TradeBox/Prompts/Chat.tsx:114-118`, commit ff1998c): `en.json` and `fr.json` have no entry, the French is the project's: the buyer's prompt at 9 (#95).
  ///
  /// In en, this message translates to:
  /// **'Say hi! Ask for payment details and click \'Confirm Sent\' as soon as the payment is sent.'**
  String get p2pEndChatBuyerHi;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:119-127`): the seller's prompt at 9 (#96). {amount} and {currencyCode} are the trade's, as the button writes them.
  ///
  /// In en, this message translates to:
  /// **'Say hi! Be helpful and concise. Let them know how to send you {amount} {currencyCode}.'**
  String p2pEndChatSellerHi(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:176-188`), shown as text: the reference's link to its documentation is not opened (#95).
  ///
  /// In en, this message translates to:
  /// **'⚠️ Beware scams'**
  String get p2pEndBewareScams;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:215-225`): the buyer's button at 9 (#95). {amount} is the trade's amount, {currencyCode} its currency.
  ///
  /// In en, this message translates to:
  /// **'Confirm {amount} {currencyCode} sent'**
  String p2pEndConfirmSent(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:237-247`): the seller's button at 9 (disabled) and 10 (#96).
  ///
  /// In en, this message translates to:
  /// **'Confirm {amount} {currencyCode} received'**
  String p2pEndConfirmReceived(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatSent.tsx`): the dialog's title (#95).
  ///
  /// In en, this message translates to:
  /// **'✅ Confirm you sent {amount} {currencyCode}?'**
  String p2pEndConfirmSentTitle(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): the dialog's title (#96).
  ///
  /// In en, this message translates to:
  /// **'✅ Confirm you received {amount} {currencyCode}?'**
  String p2pEndConfirmReceivedTitle(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatSent.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Confirming will allow your peer to finalize the trade.'**
  String get p2pEndConfirmSentText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): the dialog's first text (#96).
  ///
  /// In en, this message translates to:
  /// **'Confirming will finalize the trade.'**
  String get p2pEndConfirmReceivedText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): above the dialog's list (#96).
  ///
  /// In en, this message translates to:
  /// **'The satoshis in the escrow will be released to the buyer:'**
  String get p2pEndEscrowReleased;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): the list's first item (#96).
  ///
  /// In en, this message translates to:
  /// **'Only confirm after {amount} {currencyCode} have arrived to your account.'**
  String p2pEndOnlyConfirmAfter(String amount, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): the list's second item (#96).
  ///
  /// In en, this message translates to:
  /// **'If you have received the payment and do not click confirm, you risk losing your bond.'**
  String get p2pEndNotConfirmingRisk;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatReceived.tsx`): the list's third item (#96). « This token » is the reference's word for the robot's token, which the app keeps in the Garage Key.
  ///
  /// In en, this message translates to:
  /// **'Some fiat payment methods might reverse their transactions up to 80 days after they are completed. Please keep this token and your order data in case you need to use them as proof.'**
  String get p2pEndFiatReversal;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatSent.tsx`), in the warning colour (#95).
  ///
  /// In en, this message translates to:
  /// **'⚠️ This action cannot be undone!'**
  String get p2pEndCannotBeUndone;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatSent.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'If you have not yet sent it and you still proceed to falsely confirm, you risk losing your bond.'**
  String get p2pEndFalseConfirmRisk;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmFiatSent.tsx`): the dialog's button that sends (#95).
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get p2pEndConfirm;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's (`Prompts/Chat.tsx:141`): the buyer's prompt at 10 (#95).
  ///
  /// In en, this message translates to:
  /// **'Wait for the seller to confirm they have received the payment.'**
  String get p2pEndWaitSeller;

  /// The official client's text (`Prompts/Chat.tsx:146`): the seller's prompt at 10 (#96), which neither `en.json` nor `fr.json` lists; the French is the project's, worded as the buyer's prompt at 9 (« appuyez », the button's French).
  ///
  /// In en, this message translates to:
  /// **'The buyer has sent the fiat. Click \'Confirm Received\' once you receive it.'**
  String get p2pEndBuyerSentFiat;

  /// Not in the RoboSats texts: the project's own: the confirmation sent, its answer awaited (#95).
  ///
  /// In en, this message translates to:
  /// **'Sending your confirmation to {coordinator}…'**
  String p2pEndStepSending(String coordinator);

  /// Not in the RoboSats texts: the project's own: under « Confirm … sent », off while the status shown does not offer it (not read from an order, not stored) (#95).
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again.'**
  String get p2pEndNeedsRead;

  /// Not in the RoboSats texts: the project's own: the read just before sending, or the coordinator, shows another status than the one the user confirmed at (#95).
  ///
  /// In en, this message translates to:
  /// **'The order moved on: your confirmation was not sent.'**
  String get p2pEndMovedOn;

  /// Not in the RoboSats texts: the project's own: the read just before sending failed or could not be stored (#95).
  ///
  /// In en, this message translates to:
  /// **'The order could not be read again from {coordinator}: your confirmation was not sent.'**
  String p2pEndReadFailed(String coordinator);

  /// Not in the RoboSats texts: the project's own: the confirmation refused before the coordinator acted, or never sent; {reason} says why (#95).
  ///
  /// In en, this message translates to:
  /// **'{reason} Your confirmation was not sent.'**
  String p2pEndNotDoneAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the answer was lost; the screen shows the order as read again, and nothing is sent again by itself (#95).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether your confirmation went through. It keeps checking.'**
  String get p2pEndUnknown;

  /// Not in the RoboSats texts: the project's own (#96): what the seller's « Confirm … received » gave when its answer was lost or unreadable, or came at 10 (the reference coordinator answers `200` at 10 when it could not settle the escrow, `api/logics.py:1716-1735`, and does not try again by itself). The reads go on; a second `confirm` cannot release more than the one escrow nor pay the buyer twice (`Logics.pay_buyer`).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether your confirmation went through. It keeps reading the order; if the trade does not finish, confirm again: a second confirmation cannot release more than the one escrow.'**
  String get p2pEndUnknownReceived;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/SendingSats.tsx`): the buyer at 13 (#95).
  ///
  /// In en, this message translates to:
  /// **'RoboSats is trying to pay your lightning invoice. Remember that lightning nodes must be online in order to receive payments.'**
  String get p2pEndSendingSats;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/SendingSats.tsx`), in bold (#95).
  ///
  /// In en, this message translates to:
  /// **'Taking too long?'**
  String get p2pEndTakingTooLong;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/SendingSats.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Lightning payments are usually instantaneous, but sometimes a node in the route may be down, which can cause your payout to take up to 24 hours to arrive in your wallet.'**
  String get p2pEndTakingTooLongText;

  /// Not in the RoboSats texts: the project's own: the status shown no longer offered « Confirm … sent » when it was confirmed (not read yet, not stored) (#95).
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again. Your confirmation was not sent.'**
  String get p2pEndNeedsReadNotSent;

  /// Not in the RoboSats texts: the project's own: the confirmation left and the coordinator refused it before acting (1047, the empty 400 of its form check, the authentication's), never said « not sent » (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} did not record your confirmation.'**
  String p2pEndRefusedBy(String coordinator);

  /// Not in the RoboSats texts: the project's own: the confirmation left and the coordinator refused it, the order no longer at 9 (1029) (#95).
  ///
  /// In en, this message translates to:
  /// **'The order moved on: {coordinator} did not record your confirmation.'**
  String p2pEndNotRecordedMovedOn(String coordinator);

  /// Not in the RoboSats texts: the project's own: under « Confirm … sent », when the order read gives another amount or currency than the trade's terms, which the button keeps (#95; a warning informs, it does not block).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} now gives {readAmount} {readCurrency}; the order was taken for {amount} {currencyCode}.'**
  String p2pEndAmountDiffers(
    String coordinator,
    String readAmount,
    String readCurrency,
    String amount,
    String currencyCode,
  );

  /// Not in the RoboSats texts: the project's own: under « Confirm … sent », when the order read gives no amount for a range order, the button keeping the trade's terms (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} gives no amount for this order; it was taken for {amount} {currencyCode}.'**
  String p2pEndAmountMissing(
    String coordinator,
    String amount,
    String currencyCode,
  );

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:228-237`): the buyer's button at 10 (#95).
  ///
  /// In en, this message translates to:
  /// **'Payment failed?'**
  String get p2pEndPaymentFailed;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmUndoFiatSent.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Revert the confirmation of fiat sent?'**
  String get p2pEndUndoTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), in French typography (« » and non-breaking spaces) (`Dialogs/ConfirmUndoFiatSent.tsx`), in full (#95).
  ///
  /// In en, this message translates to:
  /// **'READ. In case your payment to the seller has been blocked and it is absolutely impossible to finish the trade, you can revert your confirmation of \"Fiat sent\". Do so only if you and the seller have ALREADY AGREED in the chat to proceed to a collaborative cancellation. After confirming, the \"Collaborative cancel\" button will be visible again. Only click this button if you know what you are doing. First time users of RoboSats are highly discouraged from performing this action! Make 100% sure your payment has failed and the amount is in your account.'**
  String get p2pEndUndoText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmUndoFiatSent.tsx`): the button that sends, off for 60 seconds from the dialog's opening, {time} the seconds left (#95).
  ///
  /// In en, this message translates to:
  /// **'Wait ({time})'**
  String p2pEndWaitCountdown(String time);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmCollabCancel.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Collaborative cancel the order?'**
  String get p2pEndCollabTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmCollabCancel.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade escrow has been posted. The order can be cancelled only if both, maker and taker, agree to cancel.'**
  String get p2pEndCollabText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmCollabCancel.tsx`), after the text when the peer asked (#95).
  ///
  /// In en, this message translates to:
  /// **'Your peer has asked for cancellation'**
  String get p2pEndCollabPeerAsked;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmCollabCancel.tsx`), the reference's spelling (#95).
  ///
  /// In en, this message translates to:
  /// **'Accept Cancelation'**
  String get p2pEndCollabAccept;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmCollabCancel.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Ask for Cancel'**
  String get p2pEndCollabAsk;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/CollabCancelAlert.tsx`): {nickname} is the peer's (#95).
  ///
  /// In en, this message translates to:
  /// **'{nickname} is asking for a collaborative cancel'**
  String p2pEndCollabPeerAlert(String nickname);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/CollabCancelAlert.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'You asked for a collaborative cancellation'**
  String get p2pEndCollabAskedAlert;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c); its `fr.json` leaves it in English, the French is the project's (`Prompts/Chat.tsx:262`): the dialog behind « … » (#95).
  ///
  /// In en, this message translates to:
  /// **'Order options'**
  String get p2pEndOrderOptions;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:345`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Collaborative Cancel'**
  String get p2pEndCollabCancel;

  /// The official client's text, from its code (`TradeBox/Prompts/Chat.tsx:330`, commit ff1998c): `en.json` and `fr.json` have no entry, the French is the project's: why « Collaborative Cancel » is off at 10 (#95).
  ///
  /// In en, this message translates to:
  /// **'Orders can\'t be cancelled if fiat has been sent.'**
  String get p2pEndCollabAfterFiat;

  /// Not in the RoboSats texts: the project's own: a request of the chat step sent, its answer awaited: « Payment failed? » or the collaborative cancel's ask or acceptance (#95).
  ///
  /// In en, this message translates to:
  /// **'Sending your request to {coordinator}…'**
  String p2pEndStepSendingRequest(String coordinator);

  /// Not in the RoboSats texts: the project's own: an action of the chat step (« Confirm … sent », …) pressed while the order read just before it is refused by the state machine (a read of a coordinator that changed the order's terms, a status that does not follow the trade): nothing was sent, and the alert of that read is shown above (security review of #219, C2). Where the order really moved on, p2pEndMovedOn and its siblings.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent: the order read just now carries the alert shown above.'**
  String get p2pEndNotSentReadRefused;

  /// Not in the RoboSats texts: the project's own: an action of the chat step pressed while the order read just before it shows no order and carries no alert to point at (an order the coordinator says cancelled, error 1043): only that nothing was sent (security review of #219, R5). With an alert, p2pEndNotSentReadRefused.
  ///
  /// In en, this message translates to:
  /// **'Nothing was sent.'**
  String get p2pEndNotSent;

  /// Not in the RoboSats texts: the project's own: « Payment failed? » not sent, the read just before sending showing another status than the one the user acted at (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade moved on: your request was not sent.'**
  String get p2pEndTradeMovedOn;

  /// Not in the RoboSats texts: the project's own: the answer of « Payment failed? » was lost; nothing is sent again by itself (#95).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether your request went through. It keeps checking.'**
  String get p2pEndUnknownRequest;

  /// Not in the RoboSats texts: the project's own: « Payment failed? » left and the coordinator refused it, the order no longer at 10 (1031) (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade moved on: {coordinator} did not record your request.'**
  String p2pEndRequestNotRecordedMovedOn(String coordinator);

  /// Not in the RoboSats texts: the project's own: « Payment failed? » left and the coordinator refused it before acting (1030, 1047, the empty 400, the authentication's) (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} did not record your request.'**
  String p2pEndRequestRefusedBy(String coordinator);

  /// Not in the RoboSats texts: the project's own: « Payment failed? » never left; {reason} says why (#95).
  ///
  /// In en, this message translates to:
  /// **'{reason} Your request was not sent.'**
  String p2pEndRequestNotDoneAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the coordinator is not on the trade's network, the confirmation never left (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} is offline: your confirmation was not sent.'**
  String p2pEndOffline(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator is not on the trade's network, « Payment failed? » never left (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} is offline: your request was not sent.'**
  String p2pEndRequestOffline(String coordinator);

  /// The official client's label of « … » (`Prompts/Chat.tsx:211`, its `aria-label`, not in `en.json`): what a screen reader reads of the button; the French is the project's (#95).
  ///
  /// In en, this message translates to:
  /// **'open options'**
  String get p2pEndOpenOptions;

  /// Not in the RoboSats texts: the project's own: what a screen reader reads of « Wait ({{time}}) » (#95), plural-aware.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Wait 1 second} other{Wait {seconds} seconds}}'**
  String p2pEndWaitSeconds(int seconds);

  /// The chat panel (#93): the reference's header, `t('You') + ': '` and the state (`ChatHeader/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'You: {state}'**
  String p2pChatYouState(String state);

  /// The chat panel (#93): the reference's header, `t('Peer') + ': '` and the state (`ChatHeader/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Peer: {state}'**
  String p2pChatPeerState(String state);

  /// The chat panel (#93): the reference's (`ChatHeader/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'connected'**
  String get p2pChatConnected;

  /// The chat panel (#93): the reference's (`ChatHeader/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'disconnected'**
  String get p2pChatDisconnected;

  /// The chat panel (#93): the reference's, the peer's state while its key is not known (`ChatHeader/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'...waiting'**
  String get p2pChatWaitingShort;

  /// The chat panel (#93): the reference's label of the field (`EncryptedApiChat/index.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get p2pChatTypeMessage;

  /// The chat panel (#93): the reference's tooltip of the disabled send, also in place of a peer's message that waits for the peer's key; the reference leaves it untranslated in French: ours, with its word « Pair ».
  ///
  /// In en, this message translates to:
  /// **'Waiting for peer...'**
  String get p2pChatWaitingForPeer;

  /// The chat panel (#93): ours: the spoken name and tooltip of the send button, which in the reference has only an icon.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get p2pChatSend;

  /// The chat panel (#93): the reference's tooltip of a message's tick (`MessageCard/index.tsx`); the reference has no French for it: ours.
  ///
  /// In en, this message translates to:
  /// **'Verified signature by {nickname}'**
  String p2pChatSignatureVerified(String nickname);

  /// The chat panel (#93): the reference's tooltip of a message's cross (`MessageCard/index.tsx`); the reference has no French for it: ours.
  ///
  /// In en, this message translates to:
  /// **'Cannot verify signature of {nickname}'**
  String p2pChatSignatureUnverified(String nickname);

  /// The chat panel (#93): the reference's alert when the text holds the robot's token (`EncryptedApiChat/index.tsx:210`, its « robot robot.token » read as « robot token »), not translated by the reference: ours in French.
  ///
  /// In en, this message translates to:
  /// **'Aye! You just sent your own robot token to your peer in chat, that\'s a catastrophic idea! So bad your message was blocked.'**
  String get p2pChatTokenBlocked;

  /// The chat panel (#93): ours: the text holds a Garage Key, said as the user types.
  ///
  /// In en, this message translates to:
  /// **'This message holds your Garage Key, which controls all your robots. It will not be sent.'**
  String get p2pChatGarageKeyBlocked;

  /// The chat panel (#93): ours: the text is over the coordinator's limit.
  ///
  /// In en, this message translates to:
  /// **'This message is too long. Shorten it to send it.'**
  String get p2pChatTooLong;

  /// The chat panel (#93): ours: the status shown is not one where a message is posted.
  ///
  /// In en, this message translates to:
  /// **'Messages are not sent at this step.'**
  String get p2pChatClosed;

  /// The chat panel (#93): ours: one wording for a peer's key that changed after it was pinned and one that is not the peer's; also the greyed « Send »'s tooltip.
  ///
  /// In en, this message translates to:
  /// **'This chat is no longer secure: your peer’s key changed. Nothing more is sent here. Do not trust payment details received from now on.'**
  String get p2pChatKeyChanged;

  /// The chat panel (#93): ours: the wait of a send.
  ///
  /// In en, this message translates to:
  /// **'Sending the message to {coordinator}…'**
  String p2pChatSending(String coordinator);

  /// The chat panel (#93): ours: a message whose post had no known outcome and that the chat does not show; never « not sent ».
  ///
  /// In en, this message translates to:
  /// **'Not confirmed by {coordinator}. It may still reach your peer.'**
  String p2pChatNotConfirmed(String coordinator);

  /// The chat panel (#93): ours: sends a message not confirmed again, the user's tap only.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get p2pChatSendAgain;

  /// The chat panel (#93): ours: the trade or the robot's key could not be opened; nothing left.
  ///
  /// In en, this message translates to:
  /// **'The message was not sent. Try again.'**
  String get p2pChatSendFailed;

  /// The chat panel (#93): ours: the coordinator refused the message before storing it.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} did not take the message. Try again.'**
  String p2pChatSendRefused(String coordinator);

  /// The chat panel (#93): ours: the last read of the order no longer allows a message.
  ///
  /// In en, this message translates to:
  /// **'The message was not sent: the trade has moved on.'**
  String get p2pChatTradeMoved;

  /// The chat panel (#93): ours: the last read failed; the chat as it was stays shown.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the chat from {coordinator}. Trying again…'**
  String p2pChatReadFailed(String coordinator);

  /// The chat panel (#93): ours: the trade or the robot's key could not be opened for a read.
  ///
  /// In en, this message translates to:
  /// **'The chat cannot be read on this device.'**
  String get p2pChatUnavailable;

  /// The chat panel (#93): ours: the history from the start is over what a read takes.
  ///
  /// In en, this message translates to:
  /// **'This chat is too long to be read from its first message.'**
  String get p2pChatHistoryTooLarge;

  /// The chat panel (#93): ours: the user's choice when the history is too long.
  ///
  /// In en, this message translates to:
  /// **'Read only the newer messages'**
  String get p2pChatReadNewer;

  /// The chat panel (#93): ours: the first read of the chat (Tor, and the robot's key for the messages), until one succeeds or fails.
  ///
  /// In en, this message translates to:
  /// **'Reading the chat from {coordinator}…'**
  String p2pChatReading(String coordinator);

  /// The chat panel (#93): ours: « Read only the newer messages » chosen, waiting for a newer read of the order.
  ///
  /// In en, this message translates to:
  /// **'Reading the newer messages…'**
  String get p2pChatSkipAwaited;

  /// The chat panel (#93): ours: after « Read only the newer messages ».
  ///
  /// In en, this message translates to:
  /// **'Earlier messages are not shown.'**
  String get p2pChatEarlierHidden;

  /// The chat panel (#93): the Garage's text, for the chat.
  ///
  /// In en, this message translates to:
  /// **'Screen protection could not be turned on, so the chat stays hidden.'**
  String get p2pChatScreenPrivacyUnavailable;

  /// The chat panel (#93): ours: a message that is not encrypted, too long, or not for this robot.
  ///
  /// In en, this message translates to:
  /// **'This message cannot be read.'**
  String get p2pChatUnreadable;

  /// The chat panel (#93): ours: a gap in the coordinator's numbering.
  ///
  /// In en, this message translates to:
  /// **'A message may be missing before this one.'**
  String get p2pChatMarkAfterGap;

  /// The chat panel (#93): ours: the same signed message at a second number.
  ///
  /// In en, this message translates to:
  /// **'This message was already shown above.'**
  String get p2pChatMarkRepeat;

  /// The chat panel (#93): ours: a message this robot sent again after a post with no known outcome.
  ///
  /// In en, this message translates to:
  /// **'You sent this message twice.'**
  String get p2pChatMarkSentTwice;

  /// The chat panel (#93): ours: its signature is older than an earlier message of the same author.
  ///
  /// In en, this message translates to:
  /// **'This message may be older than it looks.'**
  String get p2pChatMarkOutOfOrder;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's button of « Order options » (`Prompts/Chat.tsx`); the reference leaves it untranslated in French: ours.
  ///
  /// In en, this message translates to:
  /// **'Audit Chat'**
  String get p2pChatAuditChat;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's button of « Order options » (`Prompts/Chat.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get p2pChatExport;

  /// « Export » of « Order options » (#157): ours, not in the reference (whose export cannot fail): the clipboard refused the export; the button tries again.
  ///
  /// In en, this message translates to:
  /// **'The chat log could not be copied.'**
  String get p2pChatExportCopyFailed;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's title (`Dialogs/AuditPGP.tsx`), untranslated by the reference: ours in French.
  ///
  /// In en, this message translates to:
  /// **'Don\'t trust, verify'**
  String get p2pChatAuditTitle;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's (`Dialogs/AuditPGP.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Your communication is end-to-end encrypted with OpenPGP. You can verify the privacy of this chat using any tool based on the OpenPGP standard.'**
  String get p2pChatAuditText;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's.
  ///
  /// In en, this message translates to:
  /// **'Your public key'**
  String get p2pChatYourPublicKey;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Your PGP public key. Your peer uses it to encrypt messages only you can read.'**
  String get p2pChatYourPublicKeyTooltip;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's.
  ///
  /// In en, this message translates to:
  /// **'Peer public key'**
  String get p2pChatPeerPublicKey;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's tooltip (its English source, the English file's text having a typo).
  ///
  /// In en, this message translates to:
  /// **'Your peer PGP public key. You use it to encrypt messages only he can read and to verify your peer signed the incoming messages.'**
  String get p2pChatPeerPublicKeyTooltip;

  /// « Don't trust, verify » (#93): the reference's (`Dialogs/AuditPGP.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Your encrypted private key'**
  String get p2pChatYourEncryptedPrivateKey;

  /// « Don't trust, verify » (#93): the reference's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Your encrypted private key. You use it to decrypt the messages that your peer encrypted for you. You also use it to sign the messages you send.'**
  String get p2pChatYourEncryptedPrivateKeyTooltip;

  /// « Don't trust, verify » (#93): the reference's; the value shown is the robot's token.
  ///
  /// In en, this message translates to:
  /// **'Your private key passphrase (keep secure!)'**
  String get p2pChatPassphrase;

  /// « Don't trust, verify » (#93): the reference's tooltip (its English source).
  ///
  /// In en, this message translates to:
  /// **'The passphrase to decrypt your private key. Only you know it! Do not share. It is also your robot token.'**
  String get p2pChatPassphraseTooltip;

  /// « Don't trust, verify » (#93): ours, the payout panel's words: the robot's key could not be had for the export; with « Retry ».
  ///
  /// In en, this message translates to:
  /// **'The key of your robot could not be read from {coordinator}.'**
  String p2pChatAuditKeyFailed(String coordinator);

  /// « Don't trust, verify » and the chat's actions (#93): ours: the key's fingerprint in groups of four, to compare with the peer's outside the app (the rules of #92).
  ///
  /// In en, this message translates to:
  /// **'Fingerprint: {fingerprint}'**
  String p2pChatFingerprint(String fingerprint);

  /// « Don't trust, verify » and the chat's actions (#93): the reference's button; hands the public keys to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get p2pChatSaveKeys;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Save credentials as a JSON file'**
  String get p2pChatSaveKeysTooltip;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's button; hands the messages to the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get p2pChatSaveMessages;

  /// « Don't trust, verify » and the chat's actions (#93): the reference's tooltip.
  ///
  /// In en, this message translates to:
  /// **'Save messages as a JSON file'**
  String get p2pChatSaveMessagesTooltip;

  /// The wallet's slot of the payout panel (#90): the button of the Lightning tab, the wallet's own words for the same act (`receiveGenerateInvoice`, « Generate Invoice » / « Générer une facture »); the reference has no wallet.
  ///
  /// In en, this message translates to:
  /// **'Generate Invoice'**
  String get p2pPayoutWalletGenerateInvoice;

  /// The wallet's slot of the payout panel (#90): the button of the Onchain tab, the wallet's own words (`receiveGenerateAddress`, « Generate New Address » / « Générer une nouvelle adresse »).
  ///
  /// In en, this message translates to:
  /// **'Generate New Address'**
  String get p2pPayoutWalletGenerateAddress;

  /// The wallet's slot of the payout panel (#90): ours, what the wait for the wallet's invoice waits for, with the bar (the owner's rule: every wait says what it waits for).
  ///
  /// In en, this message translates to:
  /// **'Generating the invoice…'**
  String get p2pPayoutWalletMakingInvoice;

  /// The wallet's slot of the payout panel (#90): ours, the wait for a new address of the wallet.
  ///
  /// In en, this message translates to:
  /// **'Generating a new address…'**
  String get p2pPayoutWalletMakingAddress;

  /// The wallet's slot of the payout panel (#90): ours, after 30 s of a wait for the wallet.
  ///
  /// In en, this message translates to:
  /// **'Still waiting for the wallet.'**
  String get p2pPayoutWalletStillWaiting;

  /// The wallet's slot of the payout panel (#90): ours, when the wallet cannot give an invoice for another reason than the swap's limits or its server (no Instant payments wallet, a wallet that cannot be read, an answer that does not fit).
  ///
  /// In en, this message translates to:
  /// **'This wallet cannot create an invoice now.'**
  String get p2pPayoutWalletNoInvoice;

  /// The wallet's slot of the payout panel (#90): ours, when the wallet cannot give a new address of its Bitcoin wallet (none, or it cannot be read).
  ///
  /// In en, this message translates to:
  /// **'This wallet cannot give an address now.'**
  String get p2pPayoutWalletNoAddress;

  /// The wallet's slot of the payout panel (#90): ours, when the wallet already waits for the payment of another invoice of this amount (made for another payout, by its own Receive screen, or before a restart), which its swap store would answer instead of a new one (security review of #150); it ends at that order's deadline, which may be hours away, so no time is said.
  ///
  /// In en, this message translates to:
  /// **'This wallet is already waiting for a payment of this amount. Paste an invoice from another wallet, or try again later.'**
  String get p2pPayoutWalletAnotherWaiting;

  /// The wallet's slot of the payout panel (#90): ours, at status 15, when the wallet gives again the invoice it gave for this trade before the payout failed (it still waits for its payment): the coordinator refuses the same invoice (« You must submit a NEW invoice », `api/logics.py:878-880`), so it is not put in the field.
  ///
  /// In en, this message translates to:
  /// **'This wallet\'s earlier invoice for this trade is still open, and the coordinator takes only a new one. Paste an invoice from another wallet, or try again once it has expired.'**
  String get p2pPayoutWalletEarlierStillOpen;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Chat.tsx:310-324`): the button of « Order options » (#95).
  ///
  /// In en, this message translates to:
  /// **'Open Dispute'**
  String get p2pEndOpenDispute;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), and the countdown its prompt adds (`Prompts/Chat.tsx:86-96`, « {{hours}}h {{minutes}}m », the minutes on two digits): under « Open Dispute », off until 18 hours before the chat's end (#95).
  ///
  /// In en, this message translates to:
  /// **'To open a dispute you need to wait {hours}h {minutes}m'**
  String p2pEndDisputeWait(String hours, String minutes);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), in French typography (`Dialogs/ConfirmDispute.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Do you want to open a dispute?'**
  String get p2pEndDisputeTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmDispute.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'The RoboSats staff will examine the statements and evidence provided. You need to build a complete case, as the staff cannot read the chat. It is best to provide a burner contact method with your statement. The satoshis in the trade escrow will be sent to the dispute winner, while the dispute loser will lose the bond.'**
  String get p2pEndDisputeText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmDispute.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Make sure to EXPORT the chat log. The staff might request your exported chat log JSON in order to solve discrepancies. It is your responsibility to store it.'**
  String get p2pEndDisputeExport;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmDispute.tsx`): the dialog's button that goes back, its focus (#95).
  ///
  /// In en, this message translates to:
  /// **'Disagree'**
  String get p2pEndDisagree;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Dialogs/ConfirmDispute.tsx`): the button that sends (#95).
  ///
  /// In en, this message translates to:
  /// **'Agree and open dispute'**
  String get p2pEndAgreeDispute;

  /// Not in the RoboSats texts: the project's own: « Open Dispute » sent, its answer awaited (#95).
  ///
  /// In en, this message translates to:
  /// **'Opening the dispute at {coordinator}…'**
  String p2pEndStepSendingDispute(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/DisputeWaitPeer.tsx`): 11, this robot's statement received (#95).
  ///
  /// In en, this message translates to:
  /// **'We are waiting for your trade counterpart statement. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods.'**
  String get p2pEndDisputeWaitPeer;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), in French typography (`Prompts/DisputeWaitPeer.tsx`): 11 (#95).
  ///
  /// In en, this message translates to:
  /// **'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself using that information if you contact your trade coordinator.'**
  String get p2pEndDisputeSaveInfoPeer;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/DisputeWaitResolution.tsx`): 16 (#95).
  ///
  /// In en, this message translates to:
  /// **'Both statements have been received, wait for the staff to resolve the dispute. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods. If you did not provide a contact method, or are unsure whether you wrote it right, write your coordinator immediately.'**
  String get p2pEndDisputeWaitResolution;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`), in French typography (`Prompts/DisputeWaitResolution.tsx`): 16 (#95).
  ///
  /// In en, this message translates to:
  /// **'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself as the user involved in this trade via email (or other contact methods).'**
  String get p2pEndDisputeSaveInfoResolution;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/DisputeWinner.tsx`): 17 for a taker; {email} is the coordinator's (#95).
  ///
  /// In en, this message translates to:
  /// **'You can claim the dispute resolution amount (escrow and fidelity bond) from your profile rewards. If there is anything the staff can help with, do not hesitate to contact to {email} (or via your provided burner contact method).'**
  String p2pEndDisputeWinner(String email);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/DisputeLoser.tsx`), without a full stop as the reference: 18 for a taker; {email} is the coordinator's (#95).
  ///
  /// In en, this message translates to:
  /// **'Unfortunately you have lost the dispute. If you think this is a mistake you can ask to re-open the case by contacting your coordinator. If you think your coordinator was unfair, please fill a claim via email to {email}'**
  String p2pEndDisputeLoser(String email);

  /// Not in the RoboSats texts: the project's own: at 11, in place of the reference's statement form, which comes in a later phase (#95, design note § 2.7).
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot send a dispute statement yet. Contact {coordinator} through one of its contacts below, with the information to identify your order.'**
  String p2pEndStatementLater(String coordinator);

  /// Not in the RoboSats texts: the project's own: at 17, the reference's « claim from your profile rewards » not being in Bull Market yet (#95, design note § 2.7).
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot claim rewards yet: contact {coordinator} through one of its contacts below.'**
  String p2pEndRewardsLater(String coordinator);

  /// Not in the RoboSats texts: the project's own: « p2pEndStatementLater » when the app's list of coordinators has no contact for the trade's coordinator, so that no contact is said to be below (#160).
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot send a dispute statement yet. Contact {coordinator} with the information to identify your order.'**
  String p2pEndStatementLaterNoContacts(String coordinator);

  /// Not in the RoboSats texts: the project's own: « p2pEndRewardsLater » when the app's list of coordinators has no contact for the trade's coordinator, so that no contact is said to be below (#160).
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot claim rewards yet: contact {coordinator}.'**
  String p2pEndRewardsLaterNoContacts(String coordinator);

  /// Not in the RoboSats texts: the project's own: at 11 and 16, the order's number to give the coordinator, which the reference asks to save (#95).
  ///
  /// In en, this message translates to:
  /// **'Order ID: {id}'**
  String p2pEndOrderId(String id);

  /// The reference coordinator's own text of its error 1054 (`api/errors.py:62` at commit ff1998c), which the official client shows as the answer's `bad_request`: « Open Dispute » refused as too early by the coordinator, its clock the judge (#95). Not in `en.json` nor `fr.json`: the French is ours.
  ///
  /// In en, this message translates to:
  /// **'Cannot open a dispute yet. You need to wait until 18 hours before expiry.'**
  String get p2pEndDisputeTooEarly;

  /// Not in the RoboSats texts: the project's own: « Open Dispute » from a status not marked stored, nothing sent (#95).
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again. The dispute was not opened.'**
  String get p2pEndDisputeNeedsRead;

  /// Not in the RoboSats texts: the project's own: the read before « Open Dispute » failed (Tor, the coordinator), nothing sent (#95).
  ///
  /// In en, this message translates to:
  /// **'The order could not be read again from {coordinator}: the dispute was not opened.'**
  String p2pEndDisputeReadFailed(String coordinator);

  /// Not in the RoboSats texts: the project's own: the trade moved on before « Open Dispute » was sent, nothing sent (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade moved on: the dispute was not opened.'**
  String get p2pEndDisputeMovedOn;

  /// Not in the RoboSats texts: the project's own: « Open Dispute » never left (a busy robot, an error before sending); {reason} is a full sentence of the app (#95).
  ///
  /// In en, this message translates to:
  /// **'{reason} The dispute was not opened.'**
  String p2pEndDisputeNotSentAfter(String reason);

  /// Not in the RoboSats texts: the project's own: « Open Dispute » left and the coordinator refused it, the trade having moved on (1013) (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade moved on: {coordinator} did not open the dispute.'**
  String p2pEndDisputeNotRecordedMovedOn(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator is not on the trade's network, « Open Dispute » never left (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} is offline: the dispute was not opened.'**
  String p2pEndDisputeOffline(String coordinator);

  /// Not in the RoboSats texts: the project's own: any other refusal of « Open Dispute » by the coordinator (#95).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} did not open the dispute.'**
  String p2pEndDisputeRefusedBy(String coordinator);

  /// Not in the RoboSats texts: the project's own: the answer to « Open Dispute » was lost and the read after does not show it yet; never sent again by itself (#95).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether the dispute was opened. It keeps checking: the dispute shows here once it is open.'**
  String get p2pEndDisputeUnknown;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): above the buyer's five stars at 14, which send `rate_platform` (#95).
  ///
  /// In en, this message translates to:
  /// **'Rate your trade experience'**
  String get p2pEndRateTrade;

  /// Not in the RoboSats texts: the project's own: what a screen reader says of each star of « Rate your trade experience », whose reference (MUI `Rating`) reads its own label (#95).
  ///
  /// In en, this message translates to:
  /// **'{stars} of 5'**
  String p2pEndRateStar(String stars);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): the buyer paid on chain, its transaction in the mempool or confirmed; the button beside it copies the transaction id (#95).
  ///
  /// In en, this message translates to:
  /// **'Your TXID'**
  String get p2pEndYourTxid;

  /// Not in the RoboSats texts: the project's own: the spoken name of the copy button beside « Your TXID », an icon only in the reference (#95).
  ///
  /// In en, this message translates to:
  /// **'Copy the TXID'**
  String get p2pEndCopyTxid;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): the buyer's on-chain payout waits in the coordinator's queue. Its French is ours: `fr.json` leaves it in English (#95).
  ///
  /// In en, this message translates to:
  /// **'Sending coins'**
  String get p2pEndSendingCoins;

  /// Not in the RoboSats texts: the project's own: the spoken name of the copy button beside « Sending coins », which copies the payout's address, an icon only in the reference (#95).
  ///
  /// In en, this message translates to:
  /// **'Copy the address'**
  String get p2pEndCopyAddress;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Trade Summary'**
  String get p2pSummaryTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`): the tooltip, and the spoken name, of the button that copies the summary as JSON, as the reference does on a phone (`utils/saveFile.ts`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Export trade summary'**
  String get p2pSummaryExport;

  /// Not in the RoboSats texts: the project's own: the clipboard refused the export of the trade summary (#95).
  ///
  /// In en, this message translates to:
  /// **'The trade summary could not be copied.'**
  String get p2pSummaryExportCopyFailed;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'User role'**
  String get p2pSummaryUserRole;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`): under the fiat the buyer sent (#95).
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get p2pSummarySent;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`): under the fiat the seller received (#95).
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get p2pSummaryReceived;

  /// The official client's text (`TradeBox/TradeSummary.tsx` at commit ff1998c), written in English in its code with no entry in `en.json`; its French is ours (#95).
  ///
  /// In en, this message translates to:
  /// **'BTC received'**
  String get p2pSummaryBtcReceived;

  /// The official client's text (`TradeBox/TradeSummary.tsx` at commit ff1998c), written in English in its code with no entry in `en.json`; its French is ours (#95).
  ///
  /// In en, this message translates to:
  /// **'BTC sent'**
  String get p2pSummaryBtcSent;

  /// The official client's text (`TradeBox/TradeSummary.tsx` at commit ff1998c), written in English in its code with no entry in `en.json`; its French is ours (#95).
  ///
  /// In en, this message translates to:
  /// **'Trade fee'**
  String get p2pSummaryTradeFee;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`{{miningFeeSats}} Sats`, `{{revenueSats}} Sats`, `{{routingFeeSats}} Sats`, and the received or sent sats, `TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'{sats} Sats'**
  String p2pSummarySats(String sats);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`{{tradeFeeSats}} Sats ({{tradeFeePercent}}%)`, `{{swapFeeSats}} Sats ({{swapFeePercent}}%)`, `{{bondSats}} Sats ({{bondPercent}}%)`, `TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'{sats} Sats ({percent}%)'**
  String p2pSummarySatsPercent(String sats, String percent);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Onchain swap fee'**
  String get p2pSummaryOnchainSwapFee;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Maker bond'**
  String get p2pSummaryMakerBond;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`): beside each side's bond (#95).
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get p2pSummaryUnlocked;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Coordinator trade revenue'**
  String get p2pSummaryRevenue;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Routing budget'**
  String get p2pSummaryRoutingBudget;

  /// The official client's text (`TradeBox/TradeSummary.tsx` at commit ff1998c): the contract's price, written in its code (#95).
  ///
  /// In en, this message translates to:
  /// **'{rate} {currencyCode}/BTC'**
  String p2pSummaryRate(String rate, String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`TradeBox/TradeSummary.tsx`) (#95).
  ///
  /// In en, this message translates to:
  /// **'Contract exchange rate'**
  String get p2pSummaryContractRate;

  /// Not in the RoboSats texts: the project's own: the answer to « Rate your trade experience » was lost; no read can tell a rating, so nothing keeps checking, and only a new tap sends again (#95).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know whether your rating went through: the order does not show it. Tap a star to send it again.'**
  String get p2pEndRateUnknown;

  /// Not in the RoboSats texts: the project's own: « Rate your trade experience » not sent, the status shown not offering it (no order read at 14); the reference sends its stars with no such check (#95).
  ///
  /// In en, this message translates to:
  /// **'Your rating was not sent.'**
  String get p2pEndRateNotSent;

  /// Not in the RoboSats texts: the project's own: the read just before « Rate your trade experience » failed, nothing sent; the reference reads nothing before its rating (#95).
  ///
  /// In en, this message translates to:
  /// **'The order could not be read again from {coordinator}: your rating was not sent.'**
  String p2pEndRateReadFailed(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): above the five stars that rate the trade's coordinator on Nostr, followed by its name in bold (#95).
  ///
  /// In en, this message translates to:
  /// **'Rate your host'**
  String get p2pEndRateHost;

  /// Not in the RoboSats texts: the project's own: under the stars of « Rate your host », off while the token the coordinator gives for a rating (`POST /api/review/`) is asked; the reference leaves its stars on and drops a tap made before the token (#95).
  ///
  /// In en, this message translates to:
  /// **'Asking {coordinator} for permission to publish your rating…'**
  String p2pEndRateHostAsking(String coordinator);

  /// Not in the RoboSats texts: the project's own: under the stars of « Rate your host », which stay off: no token for a rating, whether the coordinator refused it (1052) or could not be asked (Tor, a coordinator unreachable or busy), which the app does not tell apart; the token is asked again only when the trade is opened again; the reference says nothing and publishes nothing (#95).
  ///
  /// In en, this message translates to:
  /// **'Your rating cannot be published: {coordinator} could not be asked for permission, or refused it. Open this trade again to try again.'**
  String p2pEndRateHostUnavailable(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): « Thank you! {{shortAlias}} loves you too », with the coordinator's long alias, after five stars of « Rate your host » (#95).
  ///
  /// In en, this message translates to:
  /// **'Thank you! {coordinator} loves you too'**
  String p2pEndHostLovesYou(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): under the thanks for five stars of « Rate your host » (#95).
  ///
  /// In en, this message translates to:
  /// **'RoboSats gets better with more liquidity and users. Tell a bitcoiner friend about Robosats!'**
  String get p2pEndTellAFriend;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): after one to four stars of « Rate your host » (#95).
  ///
  /// In en, this message translates to:
  /// **'Thank you for using Robosats!'**
  String get p2pEndThanksForUsing;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`) (`Prompts/Successful.tsx`): `let_us_know_hot_to_improve`, after one to four stars of « Rate your host », its punctuation in the text; each placeholder is replaced by the name of a link (`p2pEndImproveSimplex`, `p2pEndImproveMatrix`, `p2pEndImproveGithub`), shown for copy; the names are those of the reference's code, since its translation puts « Telegram » on the SimpleX link and « Github » on the Matrix one (#95).
  ///
  /// In en, this message translates to:
  /// **'Let us know how the platform could improve ({simplex} / {matrix} / {github})'**
  String p2pEndImprove(String simplex, String matrix, String github);

  /// The name of the RoboSats group on SimpleX in the reference's code (`Prompts/Successful.tsx`), a link shown for copy after « Let us know how the platform could improve » (#95).
  ///
  /// In en, this message translates to:
  /// **'SimpleX'**
  String get p2pEndImproveSimplex;

  /// The name of the RoboSats group on Matrix in the reference's code (`Prompts/Successful.tsx`), a link shown for copy after « Let us know how the platform could improve » (#95).
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get p2pEndImproveMatrix;

  /// The name of the issues of the RoboSats repository in the reference's code (`Prompts/Successful.tsx`), a link shown for copy after « Let us know how the platform could improve » (#95).
  ///
  /// In en, this message translates to:
  /// **'Github'**
  String get p2pEndImproveGithub;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 486), with its French (`fr.json`, line 486). The switch of the create form's advanced options (`MakerForm.tsx:700-722`), shown disabled in this version (#181).
  ///
  /// In en, this message translates to:
  /// **'Enable advanced options'**
  String get p2pMakeEnableAdvanced;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 482), with its French (`fr.json`, line 482). The label over « Buy » and « Sell » in the create form (`MakerForm.tsx:752`), followed by « * » as the reference writes it; the French adds the space before « ? » of French typography.
  ///
  /// In en, this message translates to:
  /// **'Buy or Sell Bitcoin?'**
  String get p2pMakeBuyOrSell;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 123), with its French (`fr.json`, line 123). The button « Buy » of the create form (`MakerForm.tsx:787`).
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get p2pMakeBuy;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 131), with its French (`fr.json`, line 131). The button « Sell » of the create form (`MakerForm.tsx:821`), a choice as « Buy » since #188.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get p2pMakeSell;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 139), with its French (`fr.json`, line 139). The label of the amount field of the create form (`MakerForm.tsx:894`), followed by « * » as the reference marks a required field.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get p2pMakeAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 480), with its French (`fr.json`, line 480). The tooltip of the amount field of the create form (`MakerForm.tsx:869-873`).
  ///
  /// In en, this message translates to:
  /// **'Amount of fiat to exchange for bitcoin'**
  String get p2pMakeAmountHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 500), with its French (`fr.json`, line 500). Under the amount field when it is below the form's minimum (`MakerForm.tsx:884-887`); {minAmount} is that minimum to 2 significant digits, as the reference writes it.
  ///
  /// In en, this message translates to:
  /// **'Must be more than {minAmount}'**
  String p2pMakeMoreThan(String minAmount);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 498), with its French (`fr.json`, line 498). Under the amount field when it is above the form's maximum (`MakerForm.tsx:888-891`); {maxAmount} is that maximum to 2 significant digits.
  ///
  /// In en, this message translates to:
  /// **'Must be less than {maxAmount}'**
  String p2pMakeLessThan(String maxAmount);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 493), with its French (`fr.json`, line 493). The label of the payment methods of the create form (`MakerForm.tsx:951`), followed by « * »; the French writes « fiat » in lower case, as the catalogue does.
  ///
  /// In en, this message translates to:
  /// **'Fiat Payment Method(s)'**
  String get p2pMakePaymentMethods;

  /// The official client's text, not passed to its translation (`MakerForm.tsx:955`), so absent from `en.json` and `fr.json`; the French is the project's. The tooltip of the payment methods of the create form.
  ///
  /// In en, this message translates to:
  /// **'Enter your preferred fiat payment methods. Fast methods are highly recommended.'**
  String get p2pMakePaymentMethodsHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 255), with its French (`fr.json`, line 255). The button beside the payment methods of the create form (`MakerForm.tsx:962-993`) and the title of its dialog (`Dialogs/AddNewPaymentMethodDialog.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Add custom payment method'**
  String get p2pMakeAddCustomMethod;

  /// The official client's text (`Dialogs/AddNewPaymentMethodDialog.tsx`), whose key has no entry in `en.json` nor `fr.json` at commit ff1998c; the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find your favorite payment method in the list?'**
  String get p2pMakeCustomMethodQuestion;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 260), with its French (`fr.json`, line 260). In the dialog « Add custom payment method » (`Dialogs/AddNewPaymentMethodDialog.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Use this free input to add any payment method you would like to offer.'**
  String get p2pMakeCustomMethodText;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 259), with its French (`fr.json`, line 259). The field of the dialog « Add custom payment method ».
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get p2pMakeCustomMethodLabel;

  /// The official client's text (`Dialogs/AddNewPaymentMethodDialog.tsx`), whose key has no entry in `en.json` nor `fr.json` at commit ff1998c; the French is the project's. Under the field of « Add custom payment method » when nothing is typed but spaces.
  ///
  /// In en, this message translates to:
  /// **'Can\'t be empty'**
  String get p2pMakeCustomMethodEmpty;

  /// Not in the RoboSats texts: the project's own: under the field of « Add custom payment method » when the text has an invisible character, a space other than an ordinary one, or a mark out of place, which the coordinator would show to every robot (#181, from the security review of #194; `isShownAsWritten`).
  ///
  /// In en, this message translates to:
  /// **'Others would not see this text as you typed it. Use visible characters only.'**
  String get p2pMakeCustomMethodNotShown;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 256), with its French (`fr.json`, line 256). The button that adds the text typed in « Add custom payment method ».
  ///
  /// In en, this message translates to:
  /// **'Add payment method'**
  String get p2pMakeAddPaymentMethod;

  /// Adapted from the official client's « Must be shorter than 65 characters » (`frontend/static/locales/en.json` at commit ff1998c, line 502; `MakerForm.tsx:995-999`), shown under the payment methods when their text is longer than the reference's own bound of 50 characters (`MakerForm.tsx:227`): the figure is the true one, 50, where the reference's text says 65 (the owner's decision of 2026-11-17, #181). {max} is 50.
  ///
  /// In en, this message translates to:
  /// **'Must be at most {max} characters'**
  String p2pMakeMustBeShorter(String max);

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the cross of a payment method chosen in the create form, which takes it off as the reference's chip does (`AutocompletePayments.tsx`, `onDelete`). {method} is the method's name.
  ///
  /// In en, this message translates to:
  /// **'Remove {method}'**
  String p2pMakeRemoveMethod(String method);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 511), with its French (`fr.json`, line 511). The label of the premium field of the create form (`MakerForm.tsx:1034`), followed by « * ».
  ///
  /// In en, this message translates to:
  /// **'Premium over Market (%)'**
  String get p2pMakePremium;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 499), with its French (`fr.json`, line 499). Under the premium field above 999 (`MakerForm.tsx:241-243`); {max} is 999. The French adds the space before « % » of French typography.
  ///
  /// In en, this message translates to:
  /// **'Must be less than {max}%'**
  String p2pMakePremiumTooHigh(String max);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 501), with its French (`fr.json`, line 501). Under the premium field at -100 or below (`MakerForm.tsx:244-246`); {min} is -100.
  ///
  /// In en, this message translates to:
  /// **'Must be more than {min}%'**
  String p2pMakePremiumTooLow(String min);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 506), with its French (`fr.json`, line 506). The start of the create form's summary while neither « Buy » nor « Sell » is chosen (`MakerForm.tsx:585-588`), followed by the amount and the currency: the trailing space is the reference's.
  ///
  /// In en, this message translates to:
  /// **'Order for '**
  String get p2pMakeOrderFor;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 481), with its French (`fr.json`, line 481). The start of the create form's summary for « Buy » (`MakerForm.tsx:589-592`), followed by the amount and the currency.
  ///
  /// In en, this message translates to:
  /// **'Buy BTC for '**
  String get p2pMakeBuyBtcFor;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 514), with its French (`fr.json`, line 514). The start of the create form's summary for « Sell » (`MakerForm.tsx:593-594`, #188), followed by the amount and the currency: the trailing space is the reference's.
  ///
  /// In en, this message translates to:
  /// **'Sell BTC for '**
  String get p2pMakeSellBtcFor;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 475), with its French (`fr.json`, line 475). The end of the create form's summary at a premium of 0 (`MakerForm.tsx:610-613`): the leading space is the reference's.
  ///
  /// In en, this message translates to:
  /// **' at market price'**
  String get p2pMakeAtMarketPrice;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 474), with its French (`fr.json`, line 474). The end of the create form's summary at a positive premium (`MakerForm.tsx:614-615`); {premium} is the premium.
  ///
  /// In en, this message translates to:
  /// **' at a {premium}% premium'**
  String p2pMakeAtPremium(String premium);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 473), with its French (`fr.json`, line 473). The end of the create form's summary at a negative premium (`MakerForm.tsx:616`); {discount} is the premium without its sign.
  ///
  /// In en, this message translates to:
  /// **' at a {discount}% discount'**
  String p2pMakeAtDiscount(String discount);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 490), with its French (`fr.json`, line 490). Under the create form's summary (`MakerForm.tsx:618-622`, `Estimated Bond` then « : » and « Sats »); {sats} is the bond in sats as the reference estimates it (`utils/bondCalculator.ts`).
  ///
  /// In en, this message translates to:
  /// **'Estimated Bond: {sats} Sats'**
  String p2pMakeEstimatedBond(String sats);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 505); its `fr.json` says « commande », the French is the project's, in the vocabulary of its catalogue (« ordre »). At the foot of the create form (`MakerForm.tsx:1347-1350`): the coordinator's price with the premium, to 5 significant digits.
  ///
  /// In en, this message translates to:
  /// **'Order current rate: {rate} {currencyCode}/BTC'**
  String p2pMakeCurrentRate(String rate, String currencyCode);

  /// The official client's text (`MakerForm.tsx:1345`), whose key has no entry in `en.json` nor `fr.json` at commit ff1998c; the French is the project's. The tooltip of « Order current rate ».
  ///
  /// In en, this message translates to:
  /// **'Your order\'s current exchange rate. Rate will move with the market.'**
  String get p2pMakeCurrentRateHint;

  /// The official client's label (`basic/MakerPage/index.tsx`, `submitButtonLabel`), whose key has no entry in `en.json` nor `fr.json` at commit ff1998c; the French is the project's. The button of the create form.
  ///
  /// In en, this message translates to:
  /// **'Create order'**
  String get p2pMakeCreateOrder;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 537); its `fr.json` leaves it in English, the French is the project's. The coordinator choice of the create form while the coordinators are drawn (`SelectCoordinator.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get p2pMakeLoading;

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the coordinator of the create form, whose tap opens « Select Host » as the reference's select opens its list (`SelectCoordinator.tsx`).
  ///
  /// In en, this message translates to:
  /// **'Choose the coordinator of the order'**
  String get p2pMakeChooseHost;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 496); its `fr.json` leaves it in English, the French is the project's. Why « Create order » is disabled (`MakerForm.tsx:518-520`).
  ///
  /// In en, this message translates to:
  /// **'Loading coordinator list...'**
  String get p2pMakeWhyLoadingCoordinators;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 521), with its French (`fr.json`, line 521). Why « Create order » is disabled (`MakerForm.tsx:524-526`): the coordinator's limits are being read, or give no price for the currency.
  ///
  /// In en, this message translates to:
  /// **'The Bitcoin price is not synchronized.'**
  String get p2pMakeWhyPriceNotSynchronized;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 510), with its French (`fr.json`, line 510). Why « Create order » is disabled (`MakerForm.tsx:527-529`).
  ///
  /// In en, this message translates to:
  /// **'Please select if you want to buy or sell.'**
  String get p2pMakeWhyNoSide;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 522), with its French (`fr.json`, line 522). Why « Create order » is disabled (`MakerForm.tsx:530-536`).
  ///
  /// In en, this message translates to:
  /// **'The amount is outside the allowed limits.'**
  String get p2pMakeWhyOutsideLimits;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 527); its `fr.json` says « méthode », the French is the project's, in the vocabulary of the catalogue (« mode de paiement »). Why « Create order » is disabled (`MakerForm.tsx:537-539`).
  ///
  /// In en, this message translates to:
  /// **'The payment method is not valid.'**
  String get p2pMakeWhyBadPaymentMethod;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 508), with its French (`fr.json`, line 508). Why « Create order » is disabled (`MakerForm.tsx:540-542`): nothing typed, or no number.
  ///
  /// In en, this message translates to:
  /// **'Please enter an amount.'**
  String get p2pMakeWhyNoAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 523), with its French (`fr.json`, line 523). Why « Create order » is disabled (`MakerForm.tsx:546-548`).
  ///
  /// In en, this message translates to:
  /// **'The amount must be greater than 0.'**
  String get p2pMakeWhyAmountNotPositive;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 528), with its French (`fr.json`, line 528). Why « Create order » is disabled (`MakerForm.tsx:549-551`).
  ///
  /// In en, this message translates to:
  /// **'The premium is not valid.'**
  String get p2pMakeWhyPremiumInvalid;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 525); its `fr.json` leaves it in English, the French is the project's. Why « Create order » is disabled (`MakerForm.tsx:552-554`): the coordinator's limits could not be read; said at once here, since without them nothing else can be judged.
  ///
  /// In en, this message translates to:
  /// **'The coordinator limits are not available.'**
  String get p2pMakeWhyLimitsUnavailable;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 529), with its French (`fr.json`, line 529). Why « Create order » is disabled (`MakerForm.tsx:555-557`): something typed in the premium that is no number.
  ///
  /// In en, this message translates to:
  /// **'The premium must be a number.'**
  String get p2pMakeWhyPremiumNotANumber;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 509); its `fr.json` says « méthode », the French is the project's, in the vocabulary of the catalogue. Why « Create order » is disabled (`MakerForm.tsx:558-560`).
  ///
  /// In en, this message translates to:
  /// **'Please select a payment method.'**
  String get p2pMakeWhyNoPaymentMethod;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 533), with its French (`fr.json`, line 533). Why « Create order » is disabled when no other reason applies (`MakerForm.tsx:564`).
  ///
  /// In en, this message translates to:
  /// **'You must fill the form correctly'**
  String get p2pMakeWhyFormIncorrect;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 478), with its French (`fr.json`, line 478) in the catalogue's case. The label of the switch of the advanced options when a range is chosen (`MakerForm.tsx:833-849`, #183).
  ///
  /// In en, this message translates to:
  /// **'Amount Range'**
  String get p2pMakeAmountRange;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 491), with its French (`fr.json`, line 491). The label of the switch of the advanced options when an exact amount is chosen (`MakerForm.tsx:848`, #183).
  ///
  /// In en, this message translates to:
  /// **'Exact Amount'**
  String get p2pMakeExactAmount;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 470), with its French (`fr.json`, line 470). Before the range's minimum (`AmountRange.tsx:147`, #183).
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get p2pMakeFrom;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 471), with its French (`fr.json`, line 471). Between the range's minimum and maximum (`AmountRange.tsx:178`, #183).
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get p2pMakeTo;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 484), with its French (`fr.json`, line 484). The label of the order's description in the advanced options (`MakerForm.tsx:1062`, #183).
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get p2pMakeDescription;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 531); its `fr.json` keeps it in English, the French is the project's. The tooltip of « Description » (`MakerForm.tsx:1058`, #183).
  ///
  /// In en, this message translates to:
  /// **'You can add more details about your order.'**
  String get p2pMakeDescriptionHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 497), its figure 240 as a placeholder; its `fr.json` keeps it in English, the French is the project's. Under « Description » when it is longer than {max} characters (`MakerForm.tsx:1079-1083`, #183).
  ///
  /// In en, this message translates to:
  /// **'Must be equal to or shorter than {max} characters'**
  String p2pMakeDescriptionTooLong(String max);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 507), with its French (`fr.json`, line 507). The label of the order's password in the advanced options (`MakerForm.tsx:1096`), and of the renewal's (`Prompts/Expired.tsx:53`), #189.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get p2pMakePassword;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 532); its `fr.json` keeps it in English, the French is the project's. The tooltip of « Password » (`MakerForm.tsx:1091-1093`).
  ///
  /// In en, this message translates to:
  /// **'You can optionally set a password so that only the robots you share it with can take this order.'**
  String get p2pMakePasswordHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 512), with its French (`fr.json`, line 512). The label of the time the order stays public (`MakerForm.tsx:1139`, #183).
  ///
  /// In en, this message translates to:
  /// **'Public Duration (HH:mm)'**
  String get p2pMakePublicDuration;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 513), with its French (`fr.json`, line 513). The title of the picker of « Public Duration (HH:mm) » (`MakerForm.tsx:1121`, #183).
  ///
  /// In en, this message translates to:
  /// **'Public order length'**
  String get p2pMakePublicDurationTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 488), with its French (`fr.json`, line 488). The label of the time each side has for its step once the order is taken (`MakerForm.tsx:1175`, #183).
  ///
  /// In en, this message translates to:
  /// **'Escrow/Invoice Timer (HH:mm)'**
  String get p2pMakeEscrowDuration;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 489); its French (`fr.json`, line 489, « dépôt fiduciaire ») is replaced by the project's, in the vocabulary of the catalogue (« garantie »). The title of the picker of « Escrow/Invoice Timer (HH:mm) » (`MakerForm.tsx:1156`, #183).
  ///
  /// In en, this message translates to:
  /// **'Escrow/invoice step length'**
  String get p2pMakeEscrowDurationTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 494); its French (`fr.json`, line 494, « garantie de fidélité ») says « caution » here, the word of the catalogue for a bond. The label of the bond's slider (`MakerForm.tsx:1227`, #183).
  ///
  /// In en, this message translates to:
  /// **'Fidelity Bond Size'**
  String get p2pMakeBondSize;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 515), with its French (`fr.json`, line 515). The tooltip of « Fidelity Bond Size » (`MakerForm.tsx:1217`, #183).
  ///
  /// In en, this message translates to:
  /// **'Set the skin-in-the-game, increase for higher safety assurance'**
  String get p2pMakeBondSizeHint;

  /// As the official client writes the bond's value and marks (`valueLabelFormat={(x) => x + '%'}`, `MakerForm.tsx:1238-1245`), {percent} the size written with the locale's separator; French puts a space before the sign, as the catalogue does (#183).
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String p2pMakeBondSizeValue(String percent);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 492), with its French (`fr.json`, line 492). The button of a face-to-face trade's location (`MakerForm.tsx:1022`), which opens the map (#189).
  ///
  /// In en, this message translates to:
  /// **'Face to Face Location'**
  String get p2pMakeLocation;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 477), with its French (`fr.json`, line 477). The tooltip of « Face to Face Location » (`MakerForm.tsx:1004`).
  ///
  /// In en, this message translates to:
  /// **'Add geolocation for a face to face trade'**
  String get p2pMakeLocationHint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 524), with its French (`fr.json`, line 524). Why « Create order » is disabled (`MakerForm.tsx:543-545`, #183).
  ///
  /// In en, this message translates to:
  /// **'The amount range is not valid.'**
  String get p2pMakeWhyRangeInvalid;

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « to » is below « From ».
  ///
  /// In en, this message translates to:
  /// **'The maximum must be above the minimum.'**
  String get p2pMakeRangeMaxBelowMin;

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « From » is below the smallest amount the form takes for this coordinator, currency and premium; {amount} is that amount with its currency code, {coordinator} the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'The minimum must be at least {amount} with {coordinator}.'**
  String p2pMakeRangeMinAtLeast(String amount, String coordinator);

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « to » is above the largest amount the form takes for this coordinator, currency and premium (its largest order, or the size limit of a young coordinator); {amount} is that amount with its currency code, {coordinator} the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'The maximum cannot exceed {amount} with {coordinator}.'**
  String p2pMakeRangeMaxAtMost(String amount, String coordinator);

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « to » is less than 1.5 times « From »; {min} is the minimum typed and {amount} the smallest maximum taken beside it, each with the currency code.
  ///
  /// In en, this message translates to:
  /// **'For a minimum of {min}, the maximum must be at least {amount}.'**
  String p2pMakeRangeMaxAtLeastFor(String min, String amount);

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « to » is more than about 15 times « From »; {min} is the minimum typed and {amount} the largest maximum taken beside it, each with the currency code.
  ///
  /// In en, this message translates to:
  /// **'For a minimum of {min}, the maximum cannot exceed {amount}.'**
  String p2pMakeRangeMaxAtMostFor(String min, String amount);

  /// Not in the RoboSats texts: the project's own (#225). In the range's box of the create form, under the slider, always shown: what a range must keep, which the official client leaves to be guessed. The two amounts under the slider's ends (the form's smallest and largest amount for this coordinator, currency and premium, `updateAmountLimits`, `MakerForm.tsx:140-158`): {min} without its currency, {max} with the currency code, {coordinator} the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'Amounts accepted with {coordinator}: {min} to {max}.'**
  String p2pMakeRangeAccepted(String coordinator, String min, String max);

  /// Not in the RoboSats texts: the project's own (#225). In the range's box of the create form, under the slider, always shown: what a range must keep, which the official client leaves to be guessed. The ratio the form's check of the bounds takes (`AmountRange.tsx:57-77`): from 1.5 times, where a maximum of exactly 1.5 times a minimum with decimals can be refused by a rounding of the multiplication (the reference's own), to 14.95 times.
  ///
  /// In en, this message translates to:
  /// **'The maximum must be more than 1.5 times the minimum and at most 14.95 times it.'**
  String get p2pMakeRangeRatio;

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». « From » is so high that 1.5 times it is above the largest amount the form takes; {amount} is the largest minimum that leaves room for a maximum, with its currency code, {coordinator} the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'The minimum cannot exceed {amount} with {coordinator}: the maximum must be more than 1.5 times it.'**
  String p2pMakeRangeMinAtMost(String amount, String coordinator);

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». The form's largest amount is under 1.5 times its smallest (the premium, a young coordinator's size limit, or limits the coordinator gives crossed): nothing typed can be taken; {coordinator} is the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'No range of amounts is possible with {coordinator} at this premium: use an exact amount.'**
  String p2pMakeRangeNoRoom(String coordinator);

  /// Not in the RoboSats texts: the project's own (#225). Where the official client only says « The amount range is not valid. » (`MakerForm.tsx:543-545`) and draws the field at fault in red, the form says which rule the range typed breaks, with the bound it takes, in the range's box and under « Create order ». A bound is zero, negative or no number while the coordinator's price is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Type a minimum and a maximum above 0.'**
  String get p2pMakeRangeNotPositive;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 526), with its French (`fr.json`, line 526). Why « Create order » is disabled (`MakerForm.tsx:561-563`, #183).
  ///
  /// In en, this message translates to:
  /// **'The description is not valid.'**
  String get p2pMakeWhyDescriptionInvalid;

  /// Not in the RoboSats texts: the project's own: under the create form's summary, the advanced options open, the options sent that differ from the defaults (security review of #183, C1). {options} is the list of `p2pMakeOptionSent…` joined by commas.
  ///
  /// In en, this message translates to:
  /// **'Advanced options sent with this order: {options}.'**
  String p2pMakeOptionsSentOpen(String options);

  /// Not in the RoboSats texts: the project's own: under the create form's summary, in the warning colour, the advanced options closed, the options that the reference still sends (`buildOrderAttributes`, `MakerForm.tsx:257-275`) and that differ from the defaults (security review of #183, C1). {options} is the list of `p2pMakeOptionSent…` joined by commas.
  ///
  /// In en, this message translates to:
  /// **'Advanced options closed, but still sent with this order: {options}.'**
  String p2pMakeOptionsSentClosed(String options);

  /// Not in the RoboSats texts: the project's own: in the list of the options sent, that a description is attached (its text is never repeated there).
  ///
  /// In en, this message translates to:
  /// **'a description'**
  String get p2pMakeOptionSentDescription;

  /// Not in the RoboSats texts: the project's own: in the list of the options sent, the public duration as HH:mm.
  ///
  /// In en, this message translates to:
  /// **'public duration {duration}'**
  String p2pMakeOptionSentPublicDuration(String duration);

  /// Not in the RoboSats texts: the project's own: in the list of the options sent, the escrow/invoice timer as HH:mm.
  ///
  /// In en, this message translates to:
  /// **'escrow/invoice timer {duration}'**
  String p2pMakeOptionSentEscrowDuration(String duration);

  /// Not in the RoboSats texts: the project's own: in the list of the options sent, the bond size as `p2pMakeBondSizeValue` writes it.
  ///
  /// In en, this message translates to:
  /// **'fidelity bond {percent}'**
  String p2pMakeOptionSentBondSize(String percent);

  /// Not in the RoboSats texts: the project's own, the owner's words of 2026-11-17, the coordinator named alone after the functional review of #181 (no « de {coordinator} », which French would elide before a vowel): under « Order current rate » in the create form (#181), the Bull wallet's price of a bitcoin beside the chosen coordinator's, both without the premium, and how far the coordinator's is from the wallet's. {walletPrice} and {coordinatorPrice} are the prices, {currency} the currency code, {coordinator} the coordinator's name, {gap} the gap with its sign and percent sign.
  ///
  /// In en, this message translates to:
  /// **'For comparison, the Bull wallet\'s indicative price: {walletPrice} {currency}/BTC ({coordinator}: {coordinatorPrice}, gap {gap}).'**
  String p2pMakeRateCompare(
    String walletPrice,
    String currency,
    String coordinator,
    String coordinatorPrice,
    String gap,
  );

  /// Not in the RoboSats texts: the project's own: the red warning of the create form (#181) when the coordinator's price is more than the owner's threshold below the Bull wallet's; « Create order » stays offered. {threshold} is the threshold, such as « 10% ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator}\'s price is more than {threshold} below the Bull wallet\'s: your bond would be larger than it should be. Check it before creating the order.'**
  String p2pMakeRateBelow(String coordinator, String threshold);

  /// Not in the RoboSats texts: the project's own: the red warning of the create form (#188) for a sell order when the coordinator's price is more than the owner's threshold below the Bull wallet's (the side that costs a seller: selling too low); « Create order » stays offered. {threshold} is the threshold, such as « 10% ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator}\'s price is more than {threshold} below the Bull wallet\'s: your bond would be larger than it should be, and you would lock more sats for your amount when the order is taken. Check it before creating the order.'**
  String p2pMakeRateBelowSell(String coordinator, String threshold);

  /// Not in the RoboSats texts: the project's own: the red warning of the create form (#181) when the coordinator's price is more than the owner's threshold above the Bull wallet's, for a buy order or a form with no side chosen (a seller locks fewer sats then, and is not warned of it, #188); « Create order » stays offered.
  ///
  /// In en, this message translates to:
  /// **'{coordinator}\'s price is more than {threshold} above the Bull wallet\'s: you would receive fewer sats when the order is taken. Check it before creating the order.'**
  String p2pMakeRateAbove(String coordinator, String threshold);

  /// Not in the RoboSats texts: the project's own: in the create form (#181), the order's currency is one the Bull wallet does not price: no figure, no « Retry » (the owner's decision of 2026-11-17 in the evening, his words of the maker bond's line, written for the creation).
  ///
  /// In en, this message translates to:
  /// **'The Bull wallet has no price for {currency}: rate not checked. You are trusting {coordinator}\'s price: check it yourself before creating the order.'**
  String p2pMakeRateNotPriced(String currency, String coordinator);

  /// Not in the RoboSats texts: the project's own: in the create form (#181), the Bull wallet prices the currency but its price could not be read; shown in the warning colour with « Retry »; « Create order » stays offered.
  ///
  /// In en, this message translates to:
  /// **'The Bull wallet\'s price of a bitcoin in {currency} could not be read: rate not checked.'**
  String p2pMakeRateUnverified(String currency);

  /// Not in the RoboSats texts: the project's own: in the create form (#181), while the Bull wallet's price is read.
  ///
  /// In en, this message translates to:
  /// **'Reading the Bull wallet\'s price for comparison…'**
  String get p2pMakeRateReading;

  /// Not in the RoboSats texts: the project's own (design note § 3.10): under « Create order » while the make runs, and for a make whose outcome is not known yet.
  ///
  /// In en, this message translates to:
  /// **'Creating your order…'**
  String get p2pMakeCreating;

  /// Not in the RoboSats texts: the project's own (design note § 3.10): a make whose answer was lost, which stays pending and is resolved from its line of « Active trades » (#182); the form makes nothing more meanwhile.
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether {coordinator} made your order. Check it again below, or set it aside.'**
  String p2pMakePending(String coordinator);

  /// Not in the RoboSats texts: the project's own: a make the coordinator certainly did not make, or that never left.
  ///
  /// In en, this message translates to:
  /// **'The order was not created.'**
  String get p2pMakeNotMade;

  /// Not in the RoboSats texts: the project's own: after the text of why a make did not happen. {reason} is that text, a sentence of the app.
  ///
  /// In en, this message translates to:
  /// **'{reason} The order was not created.'**
  String p2pMakeNotMadeAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the coordinator's fees or limits could not be read just before the make, so nothing was sent with a robot. {coordinator} is its long alias.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {coordinator}. The order was not created.'**
  String p2pMakeCoordinatorUnreadable(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator announces a maker fee above the app's ceiling (`TradeTolerances.makerFeeCeiling`).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} asks for a maker fee above 1 %. The order was not created.'**
  String p2pMakeFeeTooHigh(String coordinator);

  /// Not in the RoboSats texts: the project's own: the terms of the make cannot be built from what the coordinator gave (`MakerTermsUnusable`).
  ///
  /// In en, this message translates to:
  /// **'The terms of this order could not be checked. It was not created.'**
  String get p2pMakeTermsUnusable;

  /// Not in the RoboSats texts: the project's own: the records of the make could not be written before it was sent, so it was not sent.
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not write its records on this device. The order was not created.'**
  String get p2pMakeNotRecorded;

  /// Not in the RoboSats texts: the project's own: the fresh robot of the make was already known to the coordinator; the next make uses another robot.
  ///
  /// In en, this message translates to:
  /// **'The robot chosen for this order already existed on {coordinator}. The order was not created: try again.'**
  String p2pMakeRobotNotNew(String coordinator);

  /// The start of the coordinator's message of error 1004 (`api/errors.py:7`, commit ff1998c), which the official client shows; the sizes it gives are not kept. The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order is too big.'**
  String get p2pMakeTooBig;

  /// The start of the coordinator's message of error 1005 (`api/errors.py:8`, commit ff1998c), which the official client shows; the sizes it gives are not kept. The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order is too small.'**
  String get p2pMakeTooSmall;

  /// The coordinator's message of error 1006 (`api/errors.py:9`, commit ff1998c), which the official client shows, with a final full stop; a range refused by the coordinator (#183). The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Maximum range amount must be at least 50 percent higher than the minimum amount.'**
  String get p2pMakeRangeTooNarrow;

  /// The start of the coordinator's message of error 1007 (`api/errors.py:10`, commit ff1998c), which the official client shows; the sizes it gives are not kept (#183). The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order maximum amount is too big.'**
  String get p2pMakeRangeMaxTooBig;

  /// The start of the coordinator's message of error 1008 (`api/errors.py:11`, commit ff1998c), which the official client shows; the sizes it gives are not kept (#183). The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order minimum amount is too small.'**
  String get p2pMakeRangeMinTooSmall;

  /// The coordinator's message of error 1009 (`api/errors.py:12`, commit ff1998c), which the official client shows, with a final full stop; a range refused by the coordinator (#183). The French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order amount range is too large. Max amount can only be 15 times bigger than min amount.'**
  String get p2pMakeRangeTooWide;

  /// Not in the RoboSats texts: the project's own, after the coordinator's error 1037 (`api/errors.py:44`, commit ff1998c: « The RoboSats {coordinator_alias} coordinator book is at full capacity! Current limit is {max_public_orders} orders »), which the official client shows; written by the project, without the coordinator's limit, followed by « The order was not created. ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator}\'s book is full.'**
  String p2pMakeBookFull(String coordinator);

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 483), with its French (`fr.json`, line 483). The tooltip of the bin at the top left of the create form (`MakerForm.tsx:676-698`), which empties the form (`clearMaker`).
  ///
  /// In en, this message translates to:
  /// **'Clear form'**
  String get p2pMakeClearForm;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 505); its `fr.json` says « commande », the French is the project's, in the vocabulary of its catalogue (« ordre »). The start of the line « Order current rate: » while the rate is not known yet, followed by a placeholder and the currency, as the reference draws it with a skeleton (`MakerForm.tsx:1351-1361`).
  ///
  /// In en, this message translates to:
  /// **'Order current rate:'**
  String get p2pMakeCurrentRateLabel;

  /// The end of the line « Order current rate: » while the rate is not known yet (`MakerForm.tsx:1360`): the currency per bitcoin.
  ///
  /// In en, this message translates to:
  /// **'{currencyCode}/BTC'**
  String p2pMakeCurrentRateUnit(String currencyCode);

  /// Not in the RoboSats texts: the project's own: the create form (#181) when no coordinator of the network takes a new robot (each refused too many robots in this run of the app, or none is listed), with « Retry », which lists them again.
  ///
  /// In en, this message translates to:
  /// **'No coordinator can be chosen right now.'**
  String get p2pMakeNoHost;

  /// Not in the RoboSats texts: the project's own: the make read the coordinator's price again just before it would reserve a robot, and the price check under the form would not be the one the user saw (`MakePriceCheckChanged`, security review of #181, C1); nothing was sent with a robot, the form shows the new check. « Create order » is the button's label.
  ///
  /// In en, this message translates to:
  /// **'{coordinator}\'s price changed since it was shown. Check the comparison, then press \"Create order\" again.'**
  String p2pMakePriceCheckChanged(String coordinator);

  /// Not in the RoboSats texts: the project's own: « Create order » read the coordinator's limits and the Bull wallet's price again, more than 3 minutes old, and the form now shows another request or another price check: the press went no further (security review of #181, C2).
  ///
  /// In en, this message translates to:
  /// **'The limits and prices were read again and changed. Check the form, then press \"Create order\" again.'**
  String get p2pMakePricesReadAgain;

  /// Not in the RoboSats texts: the project's own: « Create order » was pressed while the Bull wallet's price was being read; once read, the form shows another price check than at the press, so the press went no further (second security review of #181, R8).
  ///
  /// In en, this message translates to:
  /// **'The price comparison has just been updated. Check it, then press \"Create order\" again.'**
  String get p2pMakePriceReadAtPress;

  /// The official client's text: the maker's title at status 1 (`TradeBox/index.tsx:390-405`, #182), the English of its code, which neither `en.json` nor `fr.json` lists (design note § 1.11); the French is the project's.
  ///
  /// In en, this message translates to:
  /// **'Your order is public'**
  String get p2pTradeTitleOrderPublic;

  /// The official client's text: the maker's title at status 2 (`TradeBox/index.tsx:406-420`, #182), the English of its code, which neither `en.json` nor `fr.json` lists; the French is the project's. Since #184 the order is paused from this app too (the pause button of status 1).
  ///
  /// In en, this message translates to:
  /// **'Your order is paused'**
  String get p2pTradeTitleOrderPaused;

  /// The official client's text, word for word (`TradeBox/Prompts/PublicWait.tsx:86-89`, #182, design note § 7, proposal 6), which `en.json` and `fr.json` do not list; the French is the project's. Bull Market does not ring yet (no notification before the end of the project): said in the trial script. {hours} and {minutes} are the order's escrow duration, whole hours then the minutes left (`depositHoursMinutes`, `:42-50`).
  ///
  /// In en, this message translates to:
  /// **'Be patient while robots check the book. This box will ring 🔊 once a robot takes your order, then you will have {hours}h {minutes}m to reply. If you do not reply, you risk losing your bond.'**
  String p2pTradePublicWait(String hours, String minutes);

  /// The official client's text (`frontend/static/locales/en.json:774`, `TradeBox/Prompts/PublicWait.tsx:95`, #182) and its French (`fr.json:774`).
  ///
  /// In en, this message translates to:
  /// **'If the order expires untaken, your bond will return to you (no action needed).'**
  String get p2pTradePublicExpiresUntaken;

  /// The official client's text (`frontend/static/locales/en.json:777`, `TradeBox/Prompts/PublicWait.tsx:109-111`, #182); the French is `fr.json:777`'s with « ordres » for « commandes », the app's word. Under the count of the book's orders in {currencyCode}, the order's currency code.
  ///
  /// In en, this message translates to:
  /// **'Public orders for {currencyCode}'**
  String p2pTradePublicOrdersFor(String currencyCode);

  /// The official client's text « Premium rank » (`frontend/static/locales/en.json:776`, `fr.json:776`) followed by the rank, as `TradeBox/Prompts/PublicWait.tsx:141` writes them (#182). {rank} is a whole number, or 0.5 when the book holds at most one order of the same currency and side (the reference's own value).
  ///
  /// In en, this message translates to:
  /// **'Premium rank {rank}%'**
  String p2pTradePremiumRank(String rank);

  /// The official client's text (`frontend/static/locales/en.json:773`, `TradeBox/Prompts/PublicWait.tsx:142-144`, #182); the French is `fr.json:773`'s with « ordres » for « commandes ».
  ///
  /// In en, this message translates to:
  /// **'Among public {currencyCode} orders (higher is cheaper)'**
  String p2pTradePremiumRankAmong(String currencyCode);

  /// The official client's text (`frontend/static/locales/en.json:764`, `TradeBox/Prompts/Paused.tsx:23-33`, #182); the French is `fr.json:764`'s with « ordre » for « commande ».
  ///
  /// In en, this message translates to:
  /// **'Your public order has been paused. At the moment it cannot be seen or taken by other robots. You can choose to unpause it at any time.'**
  String get p2pTradePausedText;

  /// The official client's text (`frontend/static/locales/en.json:775`, the tooltip of the pause button, `TradeBox/Prompts/PublicWait.tsx:118-130`, #184): the tooltip and the screen reader's label of the pause button of a maker's public order; the French is `fr.json:775`'s with « ordre » for « commande ».
  ///
  /// In en, this message translates to:
  /// **'Pause the public order'**
  String get p2pTradePauseOrder;

  /// The official client's text (`frontend/static/locales/en.json:763`, `TradeBox/Prompts/Paused.tsx:30-35`, #184): the button of a maker's paused order; the French is `fr.json:763`'s with « ordre » for « commande ».
  ///
  /// In en, this message translates to:
  /// **'Unpause Order'**
  String get p2pTradeUnpauseOrder;

  /// Not in the RoboSats texts: the project's own: the status shown comes from no order read, or was not stored: nothing was sent (#184).
  ///
  /// In en, this message translates to:
  /// **'Wait until the order is read again before pausing or unpausing it.'**
  String get p2pTradePauseNeedsRead;

  /// Not in the RoboSats texts: the project's own: the order read just before the pause or the unpause no longer showed the status the user saw (paused or unpaused from another app, taken, expired): the request, a toggle, would have gone the other way, so nothing was sent (#184).
  ///
  /// In en, this message translates to:
  /// **'The order changed before your request left: nothing was sent. It is shown as it is now.'**
  String get p2pTradePauseMovedOn;

  /// Not in the RoboSats texts: the project's own: the read just before the pause or the unpause failed or could not be stored (#184).
  ///
  /// In en, this message translates to:
  /// **'The order could not be read again from {coordinator}: nothing was sent.'**
  String p2pTradePauseReadFailed(String coordinator);

  /// Not in the RoboSats texts: the project's own: a pause or an unpause that never left, after its reason (#184).
  ///
  /// In en, this message translates to:
  /// **'{reason} Your request changed nothing.'**
  String p2pTradePauseNotDoneAfter(String reason);

  /// Not in the RoboSats texts: the project's own: the coordinator refused the pause or the unpause before acting (1032, 1033, 1047, the empty 400, the authentication's): never the coordinator's text (#184).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} refused the request: your request changed nothing. The order is shown as it is now.'**
  String p2pTradePauseRefusedBy(String coordinator);

  /// Not in the RoboSats texts: the project's own: the answer to a pause or an unpause was lost or unreadable, and the read after it does not show the order where the user asked (#184): the request is a toggle, so it is never sent again by itself.
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether your request reached {coordinator}. It checks again while this screen is open, and never sends it again by itself. Do not tap again until a read shows where your order is: a second request would undo the first if the first arrives late.'**
  String p2pTradePauseUnknown(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator accepted a pause and the read after it does not show the order paused: toggled twice (paused from another app meanwhile), taken, expired, or a coordinator that answers falsely (#184; named after the functional review, R5).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} accepted the request, but your order is not paused: it is shown as it is now.'**
  String p2pTradePauseNotReachedPaused(String coordinator);

  /// Not in the RoboSats texts: the project's own: the coordinator accepted an unpause (« Unpause Order ») and the read after it does not show the order public: toggled twice (unpaused from another app meanwhile), expired, or a coordinator that answers falsely (#184; named after the functional review, R5).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} accepted the request, but your order is not public: it is shown as it is now.'**
  String p2pTradePauseNotReachedPublic(String coordinator);

  /// Not in the RoboSats texts: the project's own: the pause button and « Unpause Order » are off while a cancel of the order runs, and this line says why (#184, functional review B1).
  ///
  /// In en, this message translates to:
  /// **'The order is being cancelled: wait until it ends.'**
  String get p2pTradePauseWhileCancel;

  /// Not in the RoboSats texts: the project's own: after a pause or an unpause whose outcome was unknown, once a read sent after the request showed the order paused: a request still on its way could toggle it; kept until a second read, three minutes after the first, still shows it paused (security review of #184, C2). It says that the two reads lower the risk without ruling it out, the transport giving no sure bound for a request still on its way (#214, security review of #184, R-a); the reference's « it cannot be seen or taken by other robots » is not shown while it is (R-b).
  ///
  /// In en, this message translates to:
  /// **'A request whose answer was lost may still arrive and make your order public again. Two reads that show it paused, minutes apart, with this screen open, lower that risk without ruling it out: until then, count on it being possibly public.'**
  String get p2pTradePauseMayStillArrive;

  /// Not in the RoboSats texts: the project's own: a cancel tapped while a pause or an unpause of the order runs waits for it behind the order's lock (security review of #184, R3).
  ///
  /// In en, this message translates to:
  /// **'Your cancel will leave once the pause or unpause ends.'**
  String get p2pTradeCancelAfterPause;

  /// Not in the RoboSats texts: the project's own: the coordinator refused a maker's cancel of its public or paused order because the status moved (1020), as after a pause or an unpause the cancel waited for: what to do (security review of #184, R1).
  ///
  /// In en, this message translates to:
  /// **'The order changed state before the cancel: nothing was cancelled. Tap \"Cancel\" again if you still want to cancel it.'**
  String get p2pTradeCancelMovedOnTapAgain;

  /// Not in the RoboSats texts: the project's own: after a pause that did not happen, while the order is read public: a public order can be taken, the maker's bond then at stake (design note § 3.4, #184).
  ///
  /// In en, this message translates to:
  /// **'Your order is public: robots can see it and take it.'**
  String get p2pTradeStillPublic;

  /// Not in the RoboSats texts: the project's own: after a pause or an unpause whose outcome is not known, until a read sent after the request shows the order paused: the order may be public, and can then be taken; shown in place of the reference's « it cannot be seen or taken » (#184, security review C1).
  ///
  /// In en, this message translates to:
  /// **'Until a read made after your request shows it paused, count on your order being public: robots can take it.'**
  String get p2pTradeMayBePublic;

  /// Not in the RoboSats texts: the project's own: an order this screen saw paused by its own pause, read public again with no tap here asking it (from another app with the same Garage Key, or a coordinator) (#184).
  ///
  /// In en, this message translates to:
  /// **'Your order is public again, although it was paused from this app: robots can see it and take it.'**
  String get p2pTradePublicAgain;

  /// The official client's text, built as `Your ${isMaker ? 'maker' : 'taker'} bond is ${status}` (`TradeBox/BondStatus.tsx:39`, #182), which `en.json` and `fr.json` do not list for a maker; the French is the project's, in the words of `p2pTradeBondLocked`.
  ///
  /// In en, this message translates to:
  /// **'Your maker bond is locked'**
  String get p2pTradeMakerBondLocked;

  /// The official client's text (`TradeBox/BondStatus.tsx:39`, #182); the French is the project's, in the words of `p2pTradeBondUnlocked`.
  ///
  /// In en, this message translates to:
  /// **'Your maker bond is unlocked'**
  String get p2pTradeMakerBondUnlocked;

  /// The official client's text (`TradeBox/BondStatus.tsx:39`, #182); the French is the project's, in the words of `p2pTradeBondSettled`.
  ///
  /// In en, this message translates to:
  /// **'Your maker bond is settled'**
  String get p2pTradeMakerBondSettled;

  /// Not in the RoboSats texts: the project's own (design note § 3.3, « The gap », #182): before « Submit » of the payout and in « Confirm … sent » of a maker buyer, information only. {sats} is the order's sats fixed at the take (`satoshis_now`), {amount} the contract's amount, {rate} and {createdRate} rates of a bitcoin written as « Order current rate », {gap} the gap in percent with its sign, such as « +2.50% ».
  ///
  /// In en, this message translates to:
  /// **'{coordinator} fixed {sats} sats for {amount} {currencyCode} when your order was taken: a rate of {rate} {currencyCode}/BTC, {gap} from the rate when you made it ({createdRate}).'**
  String p2pTradeRateGap(
    String coordinator,
    String sats,
    String amount,
    String currencyCode,
    String rate,
    String gap,
    String createdRate,
  );

  /// Not in the RoboSats texts: the project's own: a next contract seen late (`ContractSeenLate`, design note § 3.2, #178), information and not a breach, said for as long as that contract lasts (#182); it replaces « Unexpected change on the coordinator's side », which read as an alert.
  ///
  /// In en, this message translates to:
  /// **'Your order was taken again and this trade moved on without Bull Market seeing its steps, as when your Garage Key is used in another app. Check the trade in that app before acting here.'**
  String get p2pTradeWarnContractSeenLate;

  /// Not in the RoboSats texts: the project's own: a pending make being resolved (`MakeOrderUsecase.resolve`, design note § 3.4, #182).
  ///
  /// In en, this message translates to:
  /// **'Checking with {coordinator}…'**
  String p2pPendingMakeChecking(String coordinator);

  /// Not in the RoboSats texts: the project's own: a pending make that a resolution left pending (design note § 3.4, #182).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not know yet whether {coordinator} made this order. No bond is asked until it knows.'**
  String p2pPendingMakeUnknown(String coordinator);

  /// Not in the RoboSats texts: the project's own: the way out of a pending make that does not resolve (reviews of #179, #182): the app stops checking it, never makes it again.
  ///
  /// In en, this message translates to:
  /// **'Set aside'**
  String get p2pPendingMakeSetAside;

  /// Not in the RoboSats texts: the project's own: the title of the dialog of « Set aside » (#182).
  ///
  /// In en, this message translates to:
  /// **'Set this order aside?'**
  String get p2pPendingMakeSetAsideTitle;

  /// Not in the RoboSats texts: the project's own: what « Set aside » does (#182, functional review of #179): an order made but never shown waits at 0 for a bond nobody sees and expires 300 s after its creation by default (`api/logics.py:329-338`).
  ///
  /// In en, this message translates to:
  /// **'Bull Market will stop checking it. An order may still exist at {coordinator}: no bond was paid for it from this app, and it expires on its own a few minutes after it was made.'**
  String p2pPendingMakeSetAsideText(String coordinator);

  /// Not in the RoboSats texts: the project's own: why « Create order » is disabled while a pending make of the network exists (security review of #181, S2; #182).
  ///
  /// In en, this message translates to:
  /// **'An order of yours is still being created. Check it again or set it aside before creating another.'**
  String get p2pMakePendingFirst;

  /// Not in the RoboSats texts: the project's own: going back while the make is sent (security review of #181, S1; #182): the page stays, so that the user is taken to the order or to its pending make.
  ///
  /// In en, this message translates to:
  /// **'Wait for {coordinator}\'s answer before leaving: your order is being created.'**
  String p2pMakeSendingStay(String coordinator);

  /// Not in the RoboSats texts: the project's own: the Bull wallet's price being read for the owner's payment rule on a maker buyer's side (design note § 3.3, #182).
  ///
  /// In en, this message translates to:
  /// **'Reading the Bull wallet\'s price for comparison…'**
  String get p2pPayoutRateReading;

  /// Not in the RoboSats texts: the project's own: the owner's payment rule on a maker buyer's side (decided on 2026-11-17, design note § 3.3, #182), before « Submit » of the payout and in « Confirm … sent »: information. {price} is the Bull wallet's price of a bitcoin without the premium, written as « Order current rate »; {expected} the sats {amount} is worth at it with the premium, rounded down; {received} the sats the coordinator gives the buyer (`trade_satoshis`); {gap} their gap in percent with its sign.
  ///
  /// In en, this message translates to:
  /// **'At the Bull wallet\'s price, {price} {currency}/BTC, with the order\'s premium, {amount} {currency} are worth {expected} sats. You receive {received} sats: gap {gap}.'**
  String p2pPayoutRateWallet(
    String price,
    String currency,
    String amount,
    String expected,
    String received,
    String gap,
  );

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): the title of the lean breakdown of the payout's sats, above the tabs of the payout panel (« Submit payout info »); the reference shows no breakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown, in sats'**
  String get p2pPayoutBreakdownTitle;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): a discreet line under the breakdown's title at 15 (the payout failed, a new invoice asked) on a page where the owner's payment rule does not run (since #237 the rule runs at 15 as at 6 and 8 wherever it is on the page, so the line is said only without it), so that the figures do not look checked (security review of #228, C2).
  ///
  /// In en, this message translates to:
  /// **'No Bull Wallet check at this step'**
  String get p2pPayoutBreakdownNotCompared;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): in the detail, the sats the contract's amount is worth at the Bull wallet's price with the order's premium (`WalletRateCheck.ofMakerPayout`, `.ofTakenPayout`, the owner's payment rule of 2026-11-17, #182, #249), only when the rule compared at 6 or 8; never a figure of the creation's price (#234).
  ///
  /// In en, this message translates to:
  /// **'Expected by Bull Wallet'**
  String get p2pPayoutBreakdownValue;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown), « prime » as the reference's French locale writes it, the owner's correction of 2026-11-21; the English is composed on the model of the French, as #250 gives its examples): under p2pPayoutBreakdownValue, what it is computed from: {amount} the contract's amount as asked here or taken, {price} the Bull wallet's price of a bitcoin without the premium, written as the reference's « Order current rate ».
  ///
  /// In en, this message translates to:
  /// **'{amount} {currency} at {price} {currency}/BTC, premium included'**
  String p2pPayoutBreakdownPrice(String amount, String currency, String price);

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): the sats the coordinator pays the contract for the buyer, `trade_satoshis`, its `invoice_amount` (`api/logics.py:650-669`, `api/views.py:345-371`): the trade's sats less its fee, what the rule compares; in the alert colour beside the red alert.
  ///
  /// In en, this message translates to:
  /// **'Paid by the coordinator'**
  String get p2pPayoutBreakdownGiven;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is #250's own example): the gap of the sats paid by the coordinator from the sats Bull Wallet expects, in percent with its sign, as the rule computes it (`WalletRateCompared.gapHundredths`); « (indicative) » is not said once the line is the red alert. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Gap to the Bull price (indicative)'**
  String get p2pPayoutBreakdownGap;

  /// Not in the RoboSats texts: the project's own (#228, the owner's request after the trial of 2026-11-18): the coordinator's fee taken out of the payout before the sats given (`api/logics.py:650-669`): the order's `satoshis_now` (its `last_satoshis`, `api/views.py:324`) less `trade_satoshis`, two figures of the same read, never computed from the announced rate; the state machine checks it against the announced fee (`MakerFeeAboveAnnounced`, `TakerFeeAboveAnnounced`) and the breakdown is not said while it disagrees.
  ///
  /// In en, this message translates to:
  /// **'Coordinator\'s fee, already deducted'**
  String get p2pPayoutBreakdownCoordinatorFee;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): in the detail, the sats paid less the invoice: what the coordinator may spend to route the payment, the reference's « Routing Budget » of the advanced options (`routing_budget_ppm`, `api/logics.py:869-872`, `Forms/LightningPayout.tsx:110-113`).
  ///
  /// In en, this message translates to:
  /// **'Lightning routing fees'**
  String get p2pPayoutBreakdownRoutingBudget;

  /// Not in the RoboSats texts: the project's own (#228, the owner's request after the trial of 2026-11-18): the amount the invoice must be for, in bold: the reference's « Submit invoice for {{amountSats}} Sats » and its copy (`Forms/LightningPayout.tsx:556-577`), which the breakdown replaces.
  ///
  /// In en, this message translates to:
  /// **'Your invoice'**
  String get p2pPayoutBreakdownInvoice;

  /// Not in the RoboSats texts: the project's own (#228, the owner's request after the trial of 2026-11-18): the swap service's fee of the invoice this wallet made (`P2pWalletInvoice.fee`): the wallet's label (`transactionDetailLabelSwapFees`), in French with the reference's word « swap », as `p2pPayServiceFee`.
  ///
  /// In en, this message translates to:
  /// **'Swap fees'**
  String get p2pPayoutBreakdownSwapFee;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): in bold, the sats paid by the coordinator less the fees above: what reaches Instant payments once the invoice this wallet made is paid (`P2pWalletInvoice.received`, the swap service's announced amount, not guaranteed by an atomic exchange), or the invoice's amount while no invoice of this wallet is in the field; in the future, nothing is received yet.
  ///
  /// In en, this message translates to:
  /// **'You will receive'**
  String get p2pPayoutBreakdownReceived;

  /// Not in the RoboSats texts: the project's own (#228; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): on arrival, the Lightning routing budget and the swap service's fee of the invoice this wallet made, together, taken from the sats paid by the coordinator; detailed in « Show details ».
  ///
  /// In en, this message translates to:
  /// **'Routing and swap fees'**
  String get p2pPayoutBreakdownFees;

  /// Not in the RoboSats texts: the project's own (#228; the line of the red alert's mock-up of the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): on arrival, the Lightning routing budget alone, while no invoice of this wallet gives a swap fee (none made yet, or one pasted from another wallet).
  ///
  /// In en, this message translates to:
  /// **'Routing fees'**
  String get p2pPayoutBreakdownRoutingFees;

  /// Not in the RoboSats texts: the project's own (#250; the owner's « not priced » line validated on 2026-11-24, « Textes à valider », a currency the wallet does not price; the English is composed on the model of the French, as #250 gives its examples): the grey line's label, with p2pPayoutBreakdownNotPriced as its value, nothing else. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Gap to the Bull price'**
  String get p2pPayoutBreakdownGapNotPriced;

  /// Not in the RoboSats texts: the project's own (#250; the owner's « not priced » line validated on 2026-11-24; the English is composed on the model of the French, as #250 gives its examples): the value of p2pPayoutBreakdownGapNotPriced, in grey: the Bull wallet has no price for the order's currency, so no figure is compared. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'not quoted'**
  String get p2pPayoutBreakdownNotPriced;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is #250's own example): the red alert's bold line, which takes the place of p2pPayoutBreakdownGap beyond the owner's threshold, with a warning icon before it and the gap on the right. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Gap against you'**
  String get p2pPayoutBreakdownAgainst;

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English on #250's example « Bull Wallet expected X sats, the coordinator asks / pays Y »): the red alert's second line, always shown with it. {expected} is the sats the contract's amount is worth at the Bull wallet's price with the order's premium, rounded down; {received} the sats the coordinator pays the contract (`trade_satoshis`), the figure compared; also the second line of the rule's red alert at 9 and in « Confirm … sent ».
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet expected {expected} sats, the coordinator pays {received}.'**
  String p2pPayoutBreakdownAgainstFigures(String expected, String received);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is composed on the model of the French, as #250 gives its examples): the red alert's explanation, in the breakdown's detail, under the alert drawn alone above the form, and as the third line of the rule's red alert at 9 and in « Confirm … sent », where there is no detail. {threshold} is the owner's threshold as a percentage, such as « 10% ». Nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet redoes the calculation with its own price, premium included, and warns you beyond a {threshold} gap. Check the order before going on.'**
  String p2pPayoutBreakdownAgainstDetail(String threshold);

  /// Not in the RoboSats texts: the project's own (#250; the owner's « Bull price unavailable » alert validated on 2026-11-24, « Textes à valider », screen 1, the same rule; the English is composed on the model of the French, as #250 gives its examples): the orange line in the place of the gap when the Bull wallet's price could not be read, with « Retry ». Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Amount not checked'**
  String get p2pPayoutBreakdownUnverified;

  /// Not in the RoboSats texts: the project's own (#250; validated on 2026-11-24 with p2pPayoutBreakdownUnverified; the English is composed on the model of the French, as #250 gives its examples): its second line, always shown with it. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet could not get its bitcoin price.'**
  String get p2pPayoutBreakdownUnverifiedLine;

  /// Not in the RoboSats texts: the project's own (#250; the first sentence of the explanation validated on 2026-11-24 with p2pPayoutBreakdownUnverified; the English is composed on the model of the French, as #250 gives its examples): in the detail. The validated explanation's second sentence (« … or pay without this check ») speaks of paying, which a buyer does not do at the payout: left out here, to be shown to the owner.
  ///
  /// In en, this message translates to:
  /// **'Without this price, it cannot compare the coordinator\'s amount.'**
  String get p2pPayoutBreakdownUnverifiedDetail;

  /// Not in the RoboSats texts: the project's own (#237; proposed to the owner, not validated: the validated second line of « Amount not checked », p2pPayoutBreakdownUnverifiedLine, speaks of the Bull wallet's price, which was never asked here; the English is composed on the model of the French): under p2pPayoutBreakdownUnverified, in the warning colour, at a buyer's payout (6, 8, 15), at 9 and in « Confirm … sent », when this device's records of the trade could not be read now (the database, the vault or the robot's binding refused the read), so that nothing was compared; « Retry » reads them again.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet could not read this order\'s terms on this device.'**
  String get p2pPayoutRateTermsUnreadLine;

  /// Not in the RoboSats texts: the project's own (#237; proposed to the owner, not validated, on the model of p2pPayoutBreakdownUnverifiedDetail, whose « this price » would be false here; the English is composed on the model of the French): the explanation of p2pPayoutRateTermsUnreadLine, « them » being the order's terms: in the payout breakdown's detail, and under the two lines at 9 and in « Confirm … sent », where no detail holds it.
  ///
  /// In en, this message translates to:
  /// **'Without them, it cannot compare the coordinator\'s amount.'**
  String get p2pPayoutRateTermsUnreadDetail;

  /// Not in the RoboSats texts: the project's own (#281, from a security review, not a decision of the owner; proposed to the owner, not validated; the English is composed on the model of the French): the bold line of a red alert, in the payout breakdown at 15 (the payout failed, a new invoice is asked), when the sats the coordinator now pays (`trade_satoshis`) are fewer than the largest it asked at 6 or 8 for the same contract, as this run of the app saw them; in RoboSats both are the same sum, to the sat.
  ///
  /// In en, this message translates to:
  /// **'Fewer sats than the first invoice'**
  String get p2pPayoutFirstFewer;

  /// Not in the RoboSats texts: the project's own (#281; proposed to the owner, not validated; on the model of the validated p2pPayoutBreakdownAgainstFigures): the second line of the alert p2pPayoutFirstFewer, always shown with it. {first} is the largest sum the coordinator paid the contract (`trade_satoshis`) at 6 or 8, {now} the one it pays at 15, before the routing budget, the « Paid by the coordinator » of the breakdown.
  ///
  /// In en, this message translates to:
  /// **'First asked: {first} sats, the coordinator now pays {now}.'**
  String p2pPayoutFirstFewerFigures(String first, String now);

  /// Not in the RoboSats texts: the project's own (#281; proposed to the owner, not validated): the explanation of p2pPayoutFirstFewer, in the breakdown's detail, or under the alert where no detail holds it. At 15 the fiat is already sent and RoboSats opens no dispute any more (`open_dispute` only at 9 and 10): what is left is to contact the coordinator; no recourse is promised.
  ///
  /// In en, this message translates to:
  /// **'For the same contract, the coordinator must ask the same amount again. You have already sent your payment and no dispute can be opened at this step: contact the coordinator before giving this invoice.'**
  String get p2pPayoutFirstFewerDetail;

  /// Not in the RoboSats texts: the project's own (#281; proposed to the owner, not validated; on the model of the validated p2pPayoutBreakdownNotCompared): a discreet line under the gap to the Bull price in the payout breakdown at 15, when this run of the app kept nothing of the invoice asked at 6 or 8 for the contract (the app started again since, or the trade screen not shown at 6 or 8), so that the sum now asked cannot be compared with it.
  ///
  /// In en, this message translates to:
  /// **'Not compared with the first invoice'**
  String get p2pPayoutFirstUnknown;

  /// Not in the RoboSats texts: the project's own (#281; proposed to the owner, not validated): the explanation of p2pPayoutFirstUnknown, in the breakdown's detail, in place of « A small gap is normal », which this screen can no longer say at 15.
  ///
  /// In en, this message translates to:
  /// **'Bull Market knows the first invoice\'s amount only if it saw it since the app last started. Compare it yourself with this one.'**
  String get p2pPayoutFirstUnknownDetail;

  /// Not in the RoboSats texts: the project's own (#237; the wording the owner validated on 2026-11-24 on the page « Textes à valider », section « Monnaie que le portefeuille Bull ne cote pas », after his decision of 2026-11-20; the English is a faithful translation of the French): an orange alert line with the warning icon, under the grey « not quoted » line, only for an order made here in a currency the Bull wallet does not price, when the contract's sats fixed at the take are more than 10 % fewer (a buyer) or more (a seller) than its amount's sats at the rate of the creation; never within the threshold, never in the user's favour, never for an order taken here. {gap} the gap in sats, in percent without its sign, always above 10.00 %.
  ///
  /// In en, this message translates to:
  /// **'Gap of {gap} against you since the order was made'**
  String p2pRateAgainstSinceMade(String gap);

  /// Not in the RoboSats texts: the project's own (#237; the wording the owner validated on 2026-11-24, as p2pRateAgainstSinceMade; the English is a faithful translation of the French): the explanation of p2pRateAgainstSinceMade, behind « Show details » in the payout breakdown and in a collateral's confirmation, and under the alert at 9 and in « Confirm … sent », where no detail holds it. {currency} the order's currency code.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet does not quote {currency}. It therefore compares the coordinator\'s rate at the take with its rate when the order was made. The market may have moved in between.'**
  String p2pRateAgainstSinceMadeDetail(String currency);

  /// Not in the RoboSats texts: the project's own (#250; the wording the owner validated on 2026-11-24 for #250 (« Textes à valider », screen 2, the payout breakdown); the English is #250's own example): last in the detail, only beside a comparison within the owner's threshold, never beside an alert. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'A small gap is normal: the coordinator has its own price source.'**
  String get p2pPayoutBreakdownSmallGap;

  /// Not in the RoboSats texts: the project's own (#250; the lean layout validated by the owner on 2026-11-24, « Voir le détail ⌄ », the chevron drawn as an icon; the English is composed on the model of the French, as #250 gives its examples): in the payout breakdown's card under the gap's line, opens the detail in the card under it (the validated mock-up, the owner's decision of 2026-11-24). Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get p2pDetailShow;

  /// Not in the RoboSats texts: the project's own (#250; « Masquer le détail ⌃ », validated on 2026-11-24, the chevron drawn as an icon; the English is composed on the model of the French, as #250 gives its examples): closes the detail opened by p2pDetailShow. Also, since #250's second slice, in the lean confirmation of a bond or a collateral (« Pay with this wallet »), with the same words.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get p2pDetailHide;

  /// Not in the RoboSats texts: the project's own (#250; the red alert's bold line validated by the owner on 2026-11-24, « ⚠ Écart en votre défaveur −15,83 % », its icon drawn apart; the English is #250's own example): the first line of the rule's red alert where no breakdown is drawn (« Confirm … sent » and the chat step at 9, or the payout without its panel), followed by p2pPayoutBreakdownAgainstFigures. {gap} is the gap with its sign, such as « -15.83% ».
  ///
  /// In en, this message translates to:
  /// **'Gap against you {gap}'**
  String p2pPayoutRateAgainst(String gap);

  /// Not in the RoboSats texts: the project's own: the owner's payment rule on a maker buyer's side for a currency the Bull wallet does not price (#182, as `p2pPayRateNotPriced` for the bond): no figure, no « Retry ».
  ///
  /// In en, this message translates to:
  /// **'The Bull wallet has no price for {currency}: rate not checked. You are trusting {coordinator}\'s price: check it yourself before going on.'**
  String p2pPayoutRateNotPriced(String currency, String coordinator);

  /// Not in the RoboSats texts: the project's own: the Bull wallet's price could not be read for the owner's payment rule on a maker buyer's side (#182), with « Retry ».
  ///
  /// In en, this message translates to:
  /// **'The Bull wallet\'s price of a bitcoin in {currency} could not be read: rate not checked. You can try again, or go on without the check.'**
  String p2pPayoutRateUnverified(String currency);

  /// Not in the RoboSats texts: the project's own: under the warnings of an order made here once its coordinator contradicted the trade's history (a breach, `CoordinatorInconsistent`, design note § 6 row 8, #182): what to do, nothing blocked by it.
  ///
  /// In en, this message translates to:
  /// **'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact {coordinator} if something looks wrong.'**
  String p2pTradeBreachWhatToDo(String coordinator);

  /// Not in the RoboSats texts: the project's own: the owner's payment rule on a maker buyer's side when the order read gives no sats the buyer receives (#182): nothing compared, said rather than nothing.
  ///
  /// In en, this message translates to:
  /// **'Rate not checked: {coordinator} gives no sats for this step of the trade. Check them yourself before going on.'**
  String p2pPayoutRateSatsMissing(String coordinator);

  /// Not in the RoboSats texts: the project's own, under the reference's « This box will ring 🔊… » (#182, functional review): the app neither rings nor follows the order outside the trade's screen (the background service and notifications come at the end of the project).
  ///
  /// In en, this message translates to:
  /// **'Bull Market does not ring yet: keep this screen open, or come back to it often.'**
  String get p2pTradeNoRingYet;

  /// Not in the RoboSats texts: the project's own, under the reference's « Your info looks good! » texts at 7 for a maker (#182, functional review): the reference says the bond comes back, which is a taker's case; for a maker the order goes back to the book with its bond locked (`api/logics.py:404-421`).
  ///
  /// In en, this message translates to:
  /// **'For an order you made: if the seller does not lock the collateral, your order goes back to the book and your bond stays locked.'**
  String get p2pTradeEscrowWaitMaker;

  /// Not in the RoboSats texts: the project's own: under the reference's « you will get back the trade collateral and your bond automatically » at 8 (`Prompts/PayoutWait.tsx`), a taker's case: for a maker seller whose buyer gives no payout, the collateral is returned and the order published again with its maker bond locked (`api/logics.py:445-458`, #188); in the warning colour, as p2pTradeEscrowWaitMaker.
  ///
  /// In en, this message translates to:
  /// **'For an order you made: if the buyer does not cooperate, your collateral comes back, but your order goes back to the book and your bond stays locked.'**
  String get p2pTradePayoutWaitMaker;

  /// Not in the RoboSats texts: the project's own: at 9, the coordinator's figure of now (`satoshis_now` less the maker fee) differs from the invoice's sats it asked at 6 or 8 for the same contract, which this app kept in memory (#182, security review C2): the smaller compared, said in the alert colour. {told} and {asked} are sats amounts as written by the app.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} now gives {told} sats for this contract, but asked for an invoice of {asked} sats before: Bull Market compares the smaller. Check the invoice you gave before going on.'**
  String p2pPayoutRateToldMoved(String coordinator, String told, String asked);

  /// Not in the RoboSats texts: the project's own: at 9, no invoice's sats kept in memory for the contract (most often the app started again between 8 and 9, a normal case; #204 will keep it, schema 9): what is compared is the coordinator's figure of now, said as such (#182, security review C2), in the text colour, not bold, the user asked to compare it with the invoice given (#207, functional review U3). It does not say the app was restarted, which the app cannot tell (an invoice given from another app gives the same line).
  ///
  /// In en, this message translates to:
  /// **'The sats you receive shown above are those {coordinator} gives now: Bull Market does not keep your invoice after a restart. Compare them yourself with your invoice\'s amount.'**
  String p2pPayoutRateToldNow(String coordinator);

  /// Not in the RoboSats texts: the project's own, under the reference's texts that say a bond is returned (« If the order expires untaken, your bond will return to you », « you will get your bond back automatically », « Your … bond is unlocked ») (#182, second review): a bond paid with this wallet is a payment of the swap service, which refunds it less its fees, with no duration promised. Since #207, only when the trade's payment records cannot tell whether the bond was paid with this wallet (records that cannot be read, a payment whose end is not known): said as a condition, true in every case; `p2pTradeBondPaidHereBack` when they say it was.
  ///
  /// In en, this message translates to:
  /// **'A bond paid with this wallet comes back through the swap service, less its fees, after a delay.'**
  String get p2pTradeBondBackThroughSwap;

  /// Not in the RoboSats texts: the project's own, in the alert colour: at 9, a contract seen late (another taker, `ContractSeenLate`) whose payout invoice this app never saw: what is compared is the coordinator's own figure, never checked (#182, second security review R9), and the line stays when the coordinator gives no sats or amounts that do not add up (#207, R13). Nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'Bull Market has not seen this contract\'s payout invoice: do not send the money before checking in the official app.'**
  String get p2pPayoutRateNotSeen;

  /// Not in the RoboSats texts: the project's own, under the reference's texts that say a bond is returned (« If the order expires untaken, your bond will return to you », « you will get your bond back automatically », « Your … bond is unlocked »), only when the trade's payment records say the bond was paid with this wallet (#207, functional review U2): a bond paid with this wallet is a payment of the swap service, which refunds it less its fees, with no duration promised.
  ///
  /// In en, this message translates to:
  /// **'Your bond was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.'**
  String get p2pTradeBondPaidHereBack;

  /// Not in the RoboSats texts: the project's own, at 8 for a seller under « If the buyer does not cooperate, you will get back the trade collateral and your bond automatically », when the trade's payment records say the escrow, not the bond, was paid with this wallet (#207, functional review U2); « collateral » as the reference's title of the escrow (« Lock {{amountSats}} Sats as collateral »), « garantie » in French as the project's (#96).
  ///
  /// In en, this message translates to:
  /// **'Your collateral was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.'**
  String get p2pTradeEscrowPaidHereBack;

  /// Not in the RoboSats texts: the project's own, at 8 for a seller under « If the buyer does not cooperate, you will get back the trade collateral and your bond automatically », when the trade's payment records say both the bond and the escrow were paid with this wallet (#207, functional review U2).
  ///
  /// In en, this message translates to:
  /// **'Your bond and collateral were paid with this wallet: once returned, they come back through the swap service, less its fees, after a delay.'**
  String get p2pTradeBothPaidHereBack;

  /// Not in the RoboSats texts: the project's own, at 8 for a seller, when the trade's payment records cannot tell whether the bond or the escrow was paid with this wallet (records that cannot be read, a payment whose end is not known): said as a condition, true in every case (#207, functional review U2).
  ///
  /// In en, this message translates to:
  /// **'A bond or collateral paid with this wallet comes back through the swap service, less its fees, after a delay.'**
  String get p2pTradeBondOrEscrowBackThroughSwap;

  /// Not in the RoboSats texts: the project's own: the page of an order of the book opened while the records of this device's trades could not be read (or were not read within 10 s), in place of « Take Order »: the order may be one this device made, which a take would spend a robot on before the database refuses it (#182, security review R3; #207).
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not read its trades: this order may be yours, so it cannot be taken here. Go back and try again.'**
  String get p2pOrderRecordsUnreadable;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 757); its `fr.json` says « Renouveler la commande », the French is the app's, which says « ordre » (design note § 1.11). The button of an order made here once it expired (`Prompts/Expired.tsx:78-96`, #185), and the title of its renewal's page.
  ///
  /// In en, this message translates to:
  /// **'Renew Order'**
  String get p2pRenewOrder;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 791), with its French (`fr.json`, line 791). The button of an order made here at « Trade finished! » (`Prompts/Successful.tsx:276-285`, #185).
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get p2pRenew;

  /// Not in the RoboSats texts: the project's own: at the top of a renewal's page (#185), which the reference does not have (its renewal sends at once): what « Create order » will make.
  ///
  /// In en, this message translates to:
  /// **'Renewing order {orderId}: a new order is made with the terms this device kept of it, under a new robot, and asks for a new bond.'**
  String p2pRenewIntro(String orderId);

  /// Not in the RoboSats texts: the project's own: a renewal's page when the records of the order cannot be read, or do not restore (#185); nothing is sent.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be renewed: the terms this device kept of it could not be read.'**
  String get p2pRenewTermsUnreadable;

  /// Not in the RoboSats texts: the project's own: a renewal's page when the trail this device stored of the order is not at a status where the reference offers a renewal (#185); nothing is sent.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be renewed: this device has not seen it expired or finished.'**
  String get p2pRenewNotEnded;

  /// Not in the RoboSats texts: the project's own: a renewal's page when the order's coordinator left the federation list on its network, or changed address (#185); nothing is sent.
  ///
  /// In en, this message translates to:
  /// **'This order cannot be renewed: its coordinator is no longer in the list, or has moved.'**
  String get p2pRenewCoordinatorGone;

  /// Not in the RoboSats texts: the project's own: under « Create order » of a renewal's page when the form, filled with the kept terms, would not send exactly them (#185); never expected, said rather than a button that does nothing.
  ///
  /// In en, this message translates to:
  /// **'The form does not show exactly the terms kept of this order: nothing can be sent.'**
  String get p2pRenewNotAsKept;

  /// Not in the RoboSats texts: the project's own: under « Create order » of a renewal's page (#185, functional review R3) when the form or the make refuses the kept terms (an amount outside the coordinator's limits now, a currency it no longer prices, a payment method or option no longer accepted), which cannot be changed on that page; the reference sends and shows the coordinator's refusal, leaving the user with nothing to do.
  ///
  /// In en, this message translates to:
  /// **'This order can no longer be renewed as it was: create a new order.'**
  String get p2pRenewNoLongerAsKept;

  /// Not in the RoboSats texts: the project's own: on the trade screen of an order made here where its renewal is offered (#216): the day it was made and the terms this device kept of it, what a renewal sends. {summary} is the create form's summary of those terms (p2pMakeBuyBtcFor, the amount, the currency, p2pMakeAtMarketPrice or its siblings).
  ///
  /// In en, this message translates to:
  /// **'Made here on {date}, with the terms kept on this device: {summary}.'**
  String p2pTradeKeptTerms(String date, String summary);

  /// Not in the RoboSats texts: the project's own: on the trade screen of an order made here where its renewal is offered, when the records hold an order made here after it with the very terms kept of it, on its coordinator (#217): a renewal, or an order made again by hand, which may since have been cancelled or have expired; only what is established is said (functional review of #220, R1). {orderId} is the newest such order still running here, else the newest; {stands} is p2pSameTermsRunning or one of its siblings.
  ///
  /// In en, this message translates to:
  /// **'An order with the same terms was made here after this one: order {orderId}, {stands}.'**
  String p2pSameTermsMade(String orderId, String stands);

  /// Not in the RoboSats texts: the project's own: {stands} of p2pSameTermsMade and p2pRenewSameTermsText: the record of that order is open on this device.
  ///
  /// In en, this message translates to:
  /// **'still running here'**
  String get p2pSameTermsRunning;

  /// Not in the RoboSats texts: the project's own: {stands} of p2pSameTermsMade and p2pRenewSameTermsText: this device saw that order expire.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get p2pSameTermsExpired;

  /// Not in the RoboSats texts: the project's own: {stands} of p2pSameTermsMade and p2pRenewSameTermsText: this device saw that order cancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get p2pSameTermsCancelled;

  /// Not in the RoboSats texts: the project's own: {stands} of p2pSameTermsMade and p2pRenewSameTermsText: this device saw that order's trade end with success.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get p2pSameTermsCompleted;

  /// Not in the RoboSats texts: the project's own: {stands} of p2pSameTermsMade and p2pRenewSameTermsText: this device saw that order end otherwise.
  ///
  /// In en, this message translates to:
  /// **'ended'**
  String get p2pSameTermsEnded;

  /// Not in the RoboSats texts: the project's own: the button under p2pSameTermsMade that opens the trade of that order in place of the page (#217).
  ///
  /// In en, this message translates to:
  /// **'Open order {orderId}'**
  String p2pSameTermsOpen(String orderId);

  /// Not in the RoboSats texts: the project's own: on the trade screen of an order made here where its renewal is offered, when the records or the terms kept of the order cannot be read (#217): never shown as « none ».
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not read its records to tell whether an order with the same terms was made here since this one.'**
  String get p2pSameTermsUnknown;

  /// Not in the RoboSats texts: the project's own: the title of the dialog « Renew Order » or « Renew » opens when an order with the same terms was made here after this one (#217); the reference, which renews with the same robot, has the coordinator refuse a second active order (`api/logics.py:75-100`, error 1000).
  ///
  /// In en, this message translates to:
  /// **'Renew this order?'**
  String get p2pRenewSameTermsTitle;

  /// Not in the RoboSats texts: the project's own: the button of « Renew this order? » that opens the renewal's page (#217); « Go back » opens nothing.
  ///
  /// In en, this message translates to:
  /// **'Renew anyway'**
  String get p2pRenewSameTermsGo;

  /// Not in the RoboSats texts: the project's own: a trade opened again at its end (an expired order, a successful end), whose one read got no answer to tell from: out of reach, a timeout, a transport error, an answer that does not parse (#216, functional review of #220, C1). The status shown is the one the records hold.
  ///
  /// In en, this message translates to:
  /// **'This order could not be read again from {coordinator}: what is shown is what this device kept when it ended, on {date}.'**
  String p2pTradeEndNotRead(String coordinator, String date);

  /// Not in the RoboSats texts: the project's own: a trade opened again at its end whose one read was answered that the coordinator does not know the order (error 1042, or a 404) (#216, functional review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} answered that it does not know this order: what is shown is what this device kept when it ended, on {date}.'**
  String p2pTradeEndUnknown(String coordinator, String date);

  /// Not in the RoboSats texts: the project's own: a trade opened again at its end whose one read was answered otherwise than the end kept (another status, cancelled, not available, another order, other terms): said under the state machine's alerts of that answer (#216, functional review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} now shows this order otherwise than this device kept it when it ended, on {date}.'**
  String p2pTradeEndOtherwise(String coordinator, String date);

  /// Not in the RoboSats texts: the project's own: a reason in « Renew this order? »: the one read of the end opened again runs, got no answer, or was answered that the order is unknown (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'The end of this order was not confirmed by {coordinator}.'**
  String p2pRenewEndNotConfirmed(String coordinator);

  /// Not in the RoboSats texts: the project's own: a reason in « Renew this order? »: the one read of the end opened again shows the order at a status that is no end (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} shows this order still running: it may still be taken or need an action from you, and sats may still be locked in it.'**
  String p2pRenewEndAlive(String coordinator);

  /// Not in the RoboSats texts: the project's own: a reason in « Renew this order? »: the one read of the end opened again shows another end, or other terms (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} shows this order otherwise than this device kept it.'**
  String p2pRenewEndOtherwise(String coordinator);

  /// Not in the RoboSats texts: the project's own: a reason in « Renew this order? » (#217), as p2pSameTermsMade.
  ///
  /// In en, this message translates to:
  /// **'An order with the same terms was already made here after this one: order {orderId}, {stands}.'**
  String p2pRenewSameTermsMade(String orderId, String stands);

  /// Not in the RoboSats texts: the project's own: a reason in « Renew this order? »: the records could not tell, or did not answer within 10 seconds (security review of #220, C3, R3).
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not check whether an order with the same terms was already made here.'**
  String get p2pRenewSameTermsUnknown;

  /// Not in the RoboSats texts: the project's own: the last sentence of « Renew this order? », after its reasons (#217).
  ///
  /// In en, this message translates to:
  /// **'Renewing makes one more order, under a new robot, with a new bond to pay.'**
  String get p2pRenewOneMore;

  /// Not in the RoboSats texts: the project's own: on the trade screen of an order made here where its renewal is offered, and in « Renew this order? »: a make of the same terms on the same coordinator, made after this order, whose answer was lost, still pending (security review of #220, R2).
  ///
  /// In en, this message translates to:
  /// **'An order with the same terms is still being created here.'**
  String get p2pSameTermsPending;

  /// Not in the RoboSats texts: the project's own: a trade opened again at its end while its one read runs: the end the records hold is not confirmed yet, so it is not said over (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'Reading this order again from {coordinator}…'**
  String p2pTradeEndReading(String coordinator);

  /// Not in the RoboSats texts: the project's own: the alert of a trade opened again at its end whose one read shows the order at a status that is no end (0, 1, 2, 3, 6 to 11, 13, 15, 16), while this device's record of it is closed and nothing follows it any more (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'{coordinator} now shows this order as still running: it may still be taken or need an action from you, and sats may still be locked in it. Check it in the official RoboSats app with your Garage Key before you create another.'**
  String p2pTradeEndAlive(String coordinator);

  /// Not in the RoboSats texts: the project's own: in place of « This trade is over for this robot. » when the coordinator shows the order still running (p2pTradeEndAlive): where the end shown comes from (security review of #220, C1).
  ///
  /// In en, this message translates to:
  /// **'This device kept this order as ended on {date}.'**
  String p2pTradeEndKeptEnded(String date);

  /// Not in the RoboSats texts: the project's own: under « Create order » of a renewal's page when whether the renewal made an order cannot be told: an order of the network confirmed while the page was open whose terms could not be read, or the page's own make no longer pending (confirmed or closed since) (security review of #220, R1, N1): the page sends nothing more, and says how to go on; « Order » is the tab's entry (p2pNavOrder).
  ///
  /// In en, this message translates to:
  /// **'Bull Market could not check whether this renewal made an order: nothing more can be sent from this page. Go back, then open the order again from the Garage or « Order ».'**
  String get p2pRenewUnverified;

  /// The official client's label (`basic/MakerPage/index.tsx:145`, `submitButtonLabel`, its key `Submit` in `frontend/static/locales/en.json` at commit ff1998c), with its French (`fr.json`): the button of the create form while orders of the book match the one being made and are not shown (#186); it only shows them.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get p2pMakeSubmit;

  /// The official client's text (`components/MakerForm/MakerForm.tsx:1323`, `en.json` at commit ff1998c), with its French (`fr.json`, « l’ordre » as the reference writes it): the tooltip of the pencil beside « Create order » while the orders that match are shown, which unfolds the form's fields (#186).
  ///
  /// In en, this message translates to:
  /// **'Edit order'**
  String get p2pMakeEditOrder;

  /// The official client's title (`basic/MakerPage/index.tsx:109`, `en.json` at commit ff1998c) above the orders of the book that resemble the one being made, once « Submit » is pressed (#186); its French is `fr.json`'s in the vocabulary of the P2P catalogue (« ordre », where the reference writes « Commandes existantes correspondent aux vôtres ! »).
  ///
  /// In en, this message translates to:
  /// **'Existing orders match yours!'**
  String get p2pMakeMatchesFound;

  /// Not in the RoboSats texts: the project's own: the line that unfolds, under a field of the create form, the explanation shown only on demand (the owner's rule of 2026-11-20: screens kept bare, explanations on demand), #189.
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get p2pMakeSeeDetails;

  /// Not in the RoboSats texts: the project's own: the same line once the explanation is unfolded, which folds it again (#189).
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get p2pMakeHideDetails;

  /// Not in the RoboSats texts: the project's own: the short line under « Password » once one is typed (#189): the coordinator leaves a protected order out of its book (`api/views.py:788-790`); it is taken with its URL (« Search order ») and the password (#245).
  ///
  /// In en, this message translates to:
  /// **'Kept out of the book; taken with its link and the password.'**
  String get p2pMakePasswordLine;

  /// Not in the RoboSats texts: the project's own: in the detail of « Password » (#189), how a protected order is shared, with the reference's « Copy URL » (`TradeBox/CancelButton.tsx:58`).
  ///
  /// In en, this message translates to:
  /// **'Share the order\'s link (« Copy URL » on its page once it is made) and the password with the robots you choose.'**
  String get p2pMakePasswordShare;

  /// Not in the RoboSats texts: the project's own: in the detail of « Password » (#189; since #245 this app takes a protected order reached by its URL).
  ///
  /// In en, this message translates to:
  /// **'Whoever has the link and the password can take it, in Bull Market (« Search order ») or in the official RoboSats app.'**
  String get p2pMakePasswordTakers;

  /// Not in the RoboSats texts: the project's own: in the detail of « Password » (#189), what `GET /api/order/` still shows of a protected public order to a robot that is no participant (`ListOrderSerializer`, `api/serializers.py:83-107`, and `api/views.py:248-299`: type, currency, amount, premium, payment method, bond size, escrow duration, expiry, maker's nickname; location and description removed).
  ///
  /// In en, this message translates to:
  /// **'Whoever asks the coordinator for the order by its number can still read its side, currency, amount, premium, payment method, bond, timers and your robot\'s name; not its description nor its location.'**
  String get p2pMakePasswordReadable;

  /// Not in the RoboSats texts: the project's own: in the detail of « Password » (#189).
  ///
  /// In en, this message translates to:
  /// **'Only the password\'s SHA-256 leaves this device, and it is not kept: renewing the order asks for the password again.'**
  String get p2pMakePasswordHashOnly;

  /// Not in the RoboSats texts: the project's own: the alert in one short line, in the warning colour, under « Password » once a password is typed, or near the summary while the field is not in the form, on a coordinator whose `/api/info/` gives a version older than 0.8.7 (#189; advisory GHSA-r6f6-x59j-8q69 as the design note § 2.4 reports it). Never a lock.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} ({version}) shows protected orders to anyone.'**
  String p2pMakePasswordOldCoordinator(String coordinator, String version);

  /// Not in the RoboSats texts: the project's own: the alert in one short line, in the warning colour, under « Password » once a password is typed, or near the summary while the field is not in the form, on a coordinator whose `/api/info/` could not be read (#189). Never a lock.
  ///
  /// In en, this message translates to:
  /// **'Version of {coordinator} unknown: a protected order may be visible to anyone.'**
  String p2pMakePasswordUnknownVersion(String coordinator);

  /// Not in the RoboSats texts: the project's own: in the detail of the alert of a coordinator older than 0.8.7 or of unknown version (#189; design note § 2.4).
  ///
  /// In en, this message translates to:
  /// **'Before version 0.8.7 (advisory GHSA-r6f6-x59j-8q69), a coordinator gives a protected order\'s amount, premium, payment method, your robot\'s name and its location to whoever asks for it, without the password. The order can still be made; choose another coordinator to keep it private.'**
  String get p2pMakePasswordOldDetail;

  /// Not in the RoboSats texts: the project's own: in the list of the options sent, that a password protects the order (its text is never repeated there), #189.
  ///
  /// In en, this message translates to:
  /// **'a password'**
  String get p2pMakeOptionSentPassword;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 756); its `fr.json` keeps it in English, the French is the project's. The tooltip of the renewal's « Password » (`Prompts/Expired.tsx:49`); here, as its field's error and why « Create order » is disabled while it is empty, the reference drawing the field in red (`:58`, `:84-89`), #189.
  ///
  /// In en, this message translates to:
  /// **'Enter a password again'**
  String get p2pRenewPasswordAgain;

  /// Not in the RoboSats texts: the project's own: in the detail of the renewal's « Password » (#189).
  ///
  /// In en, this message translates to:
  /// **'This device does not keep the password: type the same one as before, the one you shared, or the order will not open with it.'**
  String get p2pRenewPasswordSame;

  /// Not in the RoboSats texts: the project's own: under « Face to Face Location » once a point is saved, the point the order sends, already moved as the reference moves it (#189). {point} is the latitude and the longitude, as « 48.8571, 2.3498 ».
  ///
  /// In en, this message translates to:
  /// **'Point sent: {point}'**
  String p2pMakeLocationSent(String point);

  /// Not in the RoboSats texts: the project's own: the tooltip of the button that removes the meeting point saved (#189; the reference removes it only with the last face-to-face method).
  ///
  /// In en, this message translates to:
  /// **'Remove the location'**
  String get p2pMakeLocationRemove;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 530), with its French (`fr.json`, line 530). Under the map where the location is chosen (`MakerForm.tsx:656-658`), and in the detail of « Face to Face Location » (#189).
  ///
  /// In en, this message translates to:
  /// **'To protect your privacy, the exact location you pin will be slightly randomized.'**
  String get p2pMakeLocationRandomized;

  /// Not in the RoboSats texts: the project's own: under the map where the location is chosen, beside the reference's line (#189; `api/nostr.py:28-30`, `:151-153`: an order with a password is not published on Nostr).
  ///
  /// In en, this message translates to:
  /// **'Sent to the coordinator; published with the order unless it has a password.'**
  String get p2pMakeLocationPublished;

  /// Not in the RoboSats texts: the project's own: in the detail of « Face to Face Location » (#189; `F2fMap.tsx` `onSave`, `api/views.py:291-298`, `api/nostr.py:29`, `:151-153`).
  ///
  /// In en, this message translates to:
  /// **'The point shown is the one sent: the place you pinned, moved by up to 0.05° each way (a few kilometres). The coordinator shows it with the order, and publishes it on Nostr with an order without a password. Bull Market reads nothing of your phone\'s position, only the point you pin.'**
  String get p2pMakeLocationDetail;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 374), with its French (`fr.json`, line 374). The title of the map where the meeting point is chosen (`F2fMap.tsx`), #189.
  ///
  /// In en, this message translates to:
  /// **'Choose a location'**
  String get p2pMapChooseLocation;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c, line 375), with its French (`fr.json`, line 375). The button of the map that keeps the place pinned, moved as the reference moves it (`F2fMap.tsx`), #189.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get p2pMapSave;

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the map where the meeting point is chosen (#189).
  ///
  /// In en, this message translates to:
  /// **'World map: tap a place to pin it.'**
  String get p2pMapPinHint;

  /// Not in the RoboSats texts: the project's own: what a screen reader says of the pin of the map where the meeting point is chosen (#189). {point} is the latitude and the longitude.
  ///
  /// In en, this message translates to:
  /// **'Place pinned: {point}'**
  String p2pMapPinned(String point);

  /// Not in the RoboSats texts: the project's own (#204, schema 9), in the alert colour, before « Confirm … sent » of a buyer and in its dialog: the payout invoice of the contract the trade stands at was pasted, not made by this wallet during the run that submitted it (any wallet's, this one's copied by hand included). Information; nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'This contract\'s payout invoice was pasted: the sats will go to the wallet that made it.'**
  String get p2pPayoutTracePasted;

  /// Not in the RoboSats texts: the project's own (#204, schema 9), in the alert colour, before « Confirm … sent » of a buyer and in its dialog: the on-chain payout address of the contract the trade stands at was pasted, not given by this wallet. Information; nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'This contract\'s payout address was pasted: the sats will go to the wallet it belongs to.'**
  String get p2pPayoutTracePastedAddress;

  /// Not in the RoboSats texts: the project's own (#204, schema 9), in the alert colour, before « Confirm … sent » of a buyer and in its dialog: this device recorded no payout for the contract the trade stands at (given from another app with the same Garage Key, or not by this device at all). Nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'This contract\'s payout invoice or address was not given from Bull Market: check where the sats will arrive.'**
  String get p2pPayoutTraceNotGivenHere;

  /// Not in the RoboSats texts: the project's own (#204, schema 9), in the alert colour, before « Confirm … sent » of a buyer and in its dialog: a contract under way before this version recorded payouts, or records that cannot be read. Never said as « given elsewhere ». Nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'Bull Market cannot tell whether this contract\'s payout invoice or address came from this wallet.'**
  String get p2pPayoutTraceUnknown;

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms ({day} and {time}, the device's), and the highest premium reads showed ({high}), every one above the order's own ({own}, from its terms kept here). Said once the terms are back; never less than was seen (security reviews of schema 9, C1, R8); nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}, up to a premium of {high} instead of {own}.'**
  String p2pTermsShownAbove(
    String coordinator,
    String day,
    String time,
    String high,
    String own,
  );

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms ({day} and {time}, the device's), and the lowest premium reads showed ({low}), every one below the order's own ({own}, from its terms kept here). Said once the terms are back; never less than was seen (security reviews of schema 9, C1, R8); nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}, with a premium down to {low} instead of {own}.'**
  String p2pTermsShownBelow(
    String coordinator,
    String day,
    String time,
    String low,
    String own,
  );

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms ({day} and {time}, the device's), and the lowest and the highest premium reads showed ({low}, {high}), on both sides of the order's own ({own}, from its terms kept here). Said once the terms are back; never less than was seen (security reviews of schema 9, C1, R8); nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}, with premiums from {low} to {high} instead of {own}.'**
  String p2pTermsShownBoth(
    String coordinator,
    String day,
    String time,
    String low,
    String high,
    String own,
  );

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms ({day} and {time}, the device's), and the lowest and the highest premium reads showed ({low}, {high}), the order's own not at hand (its terms not read). Said once the terms are back; never less than was seen (security reviews of schema 9, C1, R8); nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}, with premiums from {low} to {high}.'**
  String p2pTermsShownPremiums(
    String coordinator,
    String day,
    String time,
    String low,
    String high,
  );

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms ({day} and {time}, the device's), and the one other premium reads showed ({premium}), the order's own not at hand (its terms not read). Said once the terms are back; never less than was seen (security reviews of schema 9, C1, R8); nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}, with a premium of {premium}.'**
  String p2pTermsShownPremiumAlone(
    String coordinator,
    String day,
    String time,
    String premium,
  );

  /// Not in the RoboSats texts: the project's own (#231, schema 9), in the alert colour, under the trade's warnings until its end and in the dialog of « Confirm … sent »: from when a read first showed this trade with other terms than its own (currency, amount, bond, durations, payment method…), no read having shown another premium. {day} and {time} are the device's. Said once the terms are back; nothing is blocked.
  ///
  /// In en, this message translates to:
  /// **'{coordinator} showed this trade with other terms from {day} at {time}.'**
  String p2pTermsShownOther(String coordinator, String day, String time);

  /// The coordinator's message for error 1045 (`api/errors.py:52`, commit ff1998c), which the official client shows under its take button (`TakeButton.tsx:360-366`); not in its translations, so the French is the project's (#245).
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get p2pTakeWrongPassword;

  /// Not in the RoboSats texts: the project's own: under « Take Order » or « Continue » of a protected order pressed with « Password » empty: nothing is sent (the reference sends the take without a password and gets error 1045), #245.
  ///
  /// In en, this message translates to:
  /// **'Enter the order\'s password.'**
  String get p2pTakePasswordMissing;

  /// Not in the RoboSats texts: the project's own: above « Password » on the page of a protected order, whose description and location the coordinator hides from a robot that takes no part in it (`api/views.py:294-298`) and gives with the take (`:248-252`, `:280`, `:320-321`), #245.
  ///
  /// In en, this message translates to:
  /// **'Protected order: its description and location are shown once you take it.'**
  String get p2pTakeProtectedHidden;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), the tooltip of the map of an order's place (`components/OrderDetails/index.tsx:411`); on the « Order » tab of a trade of a protected order, once the coordinator gives the place to a participant (#245).
  ///
  /// In en, this message translates to:
  /// **'F2F location'**
  String get p2pTradeMeetingPoint;

  /// The official client's text (`frontend/static/locales/en.json` at commit ff1998c), under the map of an order's place (`components/OrderDetails/index.tsx:292-294`), #245.
  ///
  /// In en, this message translates to:
  /// **'The pinned location is approximate. The exact location for the meeting place must be exchanged in the encrypted chat.'**
  String get p2pTradeMeetingPointApproximate;

  /// The official client's text (`frontend/static/locales/en.json` at commit babf62e, line 206), with its French (`fr.json`, line 206). The tooltip of the switch at the right of a map's title (`F2fMap.tsx:105`, `MapChart/index.tsx:109`), #246.
  ///
  /// In en, this message translates to:
  /// **'Show tiles'**
  String get p2pMapShowTiles;

  /// The official client's text (`frontend/static/locales/en.json` at commit babf62e, line 205), with its French (`fr.json`, line 205). The title of the dialog « Show tiles » opens the first time on a map (`F2fMap.tsx:75`, `MapChart/index.tsx:61`), #246.
  ///
  /// In en, this message translates to:
  /// **'Download high resolution map?'**
  String get p2pMapTilesTitle;

  /// The official client's text (`frontend/static/locales/en.json` at commit babf62e, line 203), left in English in its French file (`fr.json`, line 203), so in English in French too. The body of the dialog of « Show tiles » (`F2fMap.tsx:77-79`, `MapChart/index.tsx:63-65`), word for word with no line added (the owner's decision of 2026-11-23, #246).
  ///
  /// In en, this message translates to:
  /// **'By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation.'**
  String get p2pMapTilesText;

  /// The official client's text (`frontend/static/locales/en.json` at commit babf62e, line 204), with its French (`fr.json`, line 204). The button of the dialog of « Show tiles » that leaves the tiles off (`F2fMap.tsx:87`, `MapChart/index.tsx:73`), #246.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get p2pMapTilesClose;

  /// The official client's text (`frontend/static/locales/en.json` at commit babf62e, line 202), with its French (`fr.json`, line 202). The button of the dialog of « Show tiles » that turns the tiles on (`F2fMap.tsx:96`, `MapChart/index.tsx:82`), #246.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get p2pMapTilesAcknowledged;

  /// The tile provider's credit as the official client shows it on the map (`OSM_TILE_ATTRIBUTION`, `components/Map/osmTiles.ts:3-4` at commit babf62e), not in its translations, so the same in every language; shown while the tiles are, as the policy of OpenStreetMap's tiles asks (#246).
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get p2pMapTilesCredit;

  /// Not in the RoboSats texts: the project's own: one line over a map whose tiles in view failed or were refused by the provider, the countries staying in their squares; the official client shows the provider's error picture (#246).
  ///
  /// In en, this message translates to:
  /// **'Map tiles unavailable'**
  String get p2pMapTilesUnavailable;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the bold line of the red alert under « Price and premium » when the coordinator's price, without the premium, is more than the threshold above the Bull wallet's for a taker buyer, or below it for a taker seller; the gap, with its sign, on its right. « Continue » stays offered.
  ///
  /// In en, this message translates to:
  /// **'Price against you'**
  String get p2pTakePriceAgainst;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the bold line of the red alert for a taker buyer when the coordinator's price, without the premium, is more than the threshold below the Bull wallet's (a larger bond), as the create form warns a buyer both ways; the gap, with its sign, on its right.
  ///
  /// In en, this message translates to:
  /// **'Price far below the Bull price'**
  String get p2pTakePriceFarBelow;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the second line of the red alert: {wallet} the Bull wallet's price of a bitcoin, {coordinator} the coordinator's, both without the premium, {currency} the order's currency code.
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet uses {wallet} {currency}/BTC, the coordinator {coordinator}.'**
  String p2pTakePriceFigures(
    String wallet,
    String currency,
    String coordinator,
  );

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the third line of the red alert, its explanation, said under its two lines since the order page has no detail to hold it. {threshold} the owner's threshold, such as « 10% ».
  ///
  /// In en, this message translates to:
  /// **'Bull Wallet compares the coordinator\'s price, premium excluded, with its own price and warns you beyond a {threshold} gap. Check the order before taking it.'**
  String p2pTakePriceDetail(String threshold);

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the bold line of the orange block when the Bull wallet's price could not be read, with « Retry » on its right; its second line is p2pPayoutBreakdownUnverifiedLine.
  ///
  /// In en, this message translates to:
  /// **'Price not checked'**
  String get p2pTakePriceUnverified;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed to the owner on 2026-11-24 on the model of the words he validated for #250, not validated; the English is composed on the model of the French: the third line of « Price not checked »; « Continue » stays offered.
  ///
  /// In en, this message translates to:
  /// **'Without this price, it cannot compare the coordinator\'s price. You can try again, or take the order without this check.'**
  String get p2pTakePriceUnverifiedDetail;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed on 2026-11-25, after the functional review of this slice, on the model of the words the owner validated for #250, not validated; the English is composed on the model of the French: the bold line of an orange block over « Continue » when « Continue » was pressed while the Bull wallet's price was read and the page, once it was read, shows a line of the comparison it did not show at the press (the red alert, « Price not checked » or « not quoted »): nothing was sent, a press again goes on. On the model of p2pPayConfirmAgainTitle.
  ///
  /// In en, this message translates to:
  /// **'This page has changed'**
  String get p2pTakePageChangedTitle;

  /// Not in the RoboSats texts: the project's own (#249, slice 4: the order page, once « Take Order » has shown the robot's read, before the take is sent; option B decided by the owner on 2026-11-24, the alert only). Proposed on 2026-11-25, after the functional review of this slice, on the model of the words the owner validated for #250, not validated; the English is composed on the model of the French: the second line of p2pTakePageChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Read the price line again, then continue again.'**
  String get p2pTakePageChangedLine;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): under the « Last order #N » lines of the Garage, opens the history of finished orders in place, with a chevron drawn as an icon; shown only when the history holds an order those lines do not show.
  ///
  /// In en, this message translates to:
  /// **'See history'**
  String get p2pHistoryShow;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): folds the history opened by p2pHistoryShow.
  ///
  /// In en, this message translates to:
  /// **'Hide history'**
  String get p2pHistoryHide;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): under the tenth line of the history, and under each tenth after it: ten older orders more, while some are left.
  ///
  /// In en, this message translates to:
  /// **'See more'**
  String get p2pHistorySeeMore;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): the first line of an order of the history, in bold: its number and its coordinator's name. {orderId} is the number of the order, {coordinator} the coordinator's name.
  ///
  /// In en, this message translates to:
  /// **'#{orderId} · {coordinator}'**
  String p2pHistoryTitle(String orderId, String coordinator);

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): the second line of an order of the history, in grey: p2pHistorySell or p2pHistoryBuy, p2pHistoryMadeHere or p2pHistoryTakenHere, then the day this device read its end, in the app's short date.
  ///
  /// In en, this message translates to:
  /// **'{side} · {origin} · {day}'**
  String p2pHistoryFacts(String side, String origin, String day);

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): the third line of an order of the history, in grey, which the owner decided on 2026-11-25 each line has: its robot, « Robot #N » as the account navigator writes it, then its nickname; « Robot #N » alone when the Garage Key shown does not give the nickname. {robot} is « Robot #N », {nickname} the robot's nickname.
  ///
  /// In en, this message translates to:
  /// **'{robot} · {nickname}'**
  String p2pHistoryRobotNamed(String robot, String nickname);

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): in the history, an order where this device's robot sold bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get p2pHistorySell;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): in the history, an order where this device's robot bought bitcoin.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get p2pHistoryBuy;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): in the history, an order this device made.
  ///
  /// In en, this message translates to:
  /// **'made here'**
  String get p2pHistoryMadeHere;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): in the history, an order this device took.
  ///
  /// In en, this message translates to:
  /// **'taken here'**
  String get p2pHistoryTakenHere;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): how an order of the history ended, on the right of its line: the trade went through (14).
  ///
  /// In en, this message translates to:
  /// **'Traded'**
  String get p2pHistoryTraded;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): how an order of the history ended, in grey: the order expired (5).
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get p2pHistoryExpired;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): how an order of the history ended, in grey: the order was cancelled (error 1043).
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get p2pHistoryCancelled;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): how an order of the history ended, in orange: the order ended by a dispute's resolution (17 or 18), whoever won it.
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get p2pHistoryDispute;

  /// Not in the RoboSats texts: the project's own (#253, an addition of Bull Market: the reference has no history; the words of the mock-up the owner validated on 2026-11-25; the English is composed on the model of the French): how an order of the history ended, in grey, when the records do not say it: this device's robot dropped out of the order (public again without it, or no longer shown to it, where only its own part is known to have ended), or no trail of it can be read (design note `docs/design/phase-3-order-history.md` § 4). Never an affirmative word.
  ///
  /// In en, this message translates to:
  /// **'End unknown'**
  String get p2pHistoryEndUnknown;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the card on an internal Garage Key (a key of the default wallet's words), between its arrows, and the key's line in the history and in a trade in progress of another key. {index} is its number, from 0.
  ///
  /// In en, this message translates to:
  /// **'Internal Garage Key #{index}'**
  String p2pGarageKeyNumber(int index);

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key from the wallet's words, design note `docs/design/garage-key-from-the-words.md`). The masked text of the Garage Key field before the re-authentication: the prefix of every key and dots, never any part of the key.
  ///
  /// In en, this message translates to:
  /// **'robo1••••••••••••'**
  String get p2pGarageKeyMasked;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The tooltip and screen reader label of « ‹ » in the title of the card.
  ///
  /// In en, this message translates to:
  /// **'Previous internal Garage Key'**
  String get p2pGaragePreviousKey;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The tooltip and screen reader label of « › » in the title of the card; disabled on the highest internal Garage Key, it creates nothing.
  ///
  /// In en, this message translates to:
  /// **'Next internal Garage Key'**
  String get p2pGarageNextKey;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of the card on an internal Garage Key, in place of the official client's « Delete All »: it asks « New Garage Key » (p2pGarageNewKeyTitle).
  ///
  /// In en, this message translates to:
  /// **'New internal Garage Key'**
  String get p2pGarageNewKey;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the confirmation of « New internal Garage Key ».
  ///
  /// In en, this message translates to:
  /// **'New Garage Key'**
  String get p2pGarageNewKeyTitle;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The text of « New Garage Key ». {index} is the number of the internal Garage Key it creates, the one after the highest.
  ///
  /// In en, this message translates to:
  /// **'Your trades will use internal Garage Key #{index}. Earlier Garage Keys stay within reach in the Garage.'**
  String p2pGarageNewKeyText(int index);

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of « New Garage Key » that creates the key. {index} is its number.
  ///
  /// In en, this message translates to:
  /// **'Create internal Garage Key #{index}'**
  String p2pGarageNewKeyConfirm(int index);

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). Why the internal Garage Keys cannot be shown: there is no default Bitcoin wallet.
  ///
  /// In en, this message translates to:
  /// **'No default Bitcoin wallet: the internal Garage Keys come from its 12 words.'**
  String get p2pGarageKeyNoWallet;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). Why the internal Garage Keys cannot be shown: the default wallet has a passphrase.
  ///
  /// In en, this message translates to:
  /// **'This wallet has a passphrase: its 12 words alone do not give the internal Garage Keys.'**
  String get p2pGarageKeyPassphrase;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). Why the internal Garage Keys cannot be shown: the default wallet's secret has no words.
  ///
  /// In en, this message translates to:
  /// **'This wallet has no words: the internal Garage Keys come from them.'**
  String get p2pGarageKeyNoWords;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). Why an internal Garage Key is refused: the words give another key than the one recorded (another default wallet).
  ///
  /// In en, this message translates to:
  /// **'The 12 words of this wallet do not give back the internal Garage Key recorded on this device. Nothing was signed.'**
  String get p2pGarageKeyMismatch;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). Why « New internal Garage Key » did nothing: the highest possible index is reached.
  ///
  /// In en, this message translates to:
  /// **'There is no internal Garage Key after this one.'**
  String get p2pGarageKeyLastIndex;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the card on the external Garage Key (the key the vault kept from before #81, or one imported), without arrows; the title of its explanation; its line in the history and in a trade in progress of another key.
  ///
  /// In en, this message translates to:
  /// **'External Garage Key'**
  String get p2pGarageExternalKey;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The line under the field of an internal Garage Key, before its ⓘ.
  ///
  /// In en, this message translates to:
  /// **'Backed up by the 12 words of your Bull Wallet.'**
  String get p2pGarageKeyBackedUp;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The line under the field of the external Garage Key, in the warning colour, before its ⓘ.
  ///
  /// In en, this message translates to:
  /// **'Not backed up by your Bull Wallet: keep a copy of it.'**
  String get p2pGarageKeyNotBackedUp;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The tooltip and screen reader label of the ⓘ of the card, which opens the explanation of the key shown.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get p2pGarageKeyExplain;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the explanation the ⓘ of an internal Garage Key opens.
  ///
  /// In en, this message translates to:
  /// **'Internal Garage Keys'**
  String get p2pGarageInternalKeysTitle;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The explanation of the internal Garage Keys, opened by the ⓘ of the card, closed by « Got it » (p2pCommonAcknowledged).
  ///
  /// In en, this message translates to:
  /// **'Your internal Garage Keys are backed up by the 12 words of your Bull Wallet: reinstall the app with these 12 words and you find them again. Keep them safe and do not share them: whoever holds a Garage Key controls its robots.'**
  String get p2pGarageInternalKeysInfo;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The explanation of the external Garage Key, opened by the ⓘ of the card, closed by « Got it » (p2pCommonAcknowledged).
  ///
  /// In en, this message translates to:
  /// **'This Garage Key is not backed up by the 12 words of your Bull Wallet. If you lose this phone or delete the app, you will only find it again with your own copy: back it up separately. Keep it safe and do not share it.'**
  String get p2pGarageExternalKeyInfo;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of the card on an internal Garage Key when an external Garage Key exists, and of the internal side when the words cannot give a key: it shows the external Garage Key.
  ///
  /// In en, this message translates to:
  /// **'Switch to the external Garage Key'**
  String get p2pGarageSwitchToExternal;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of the card on the external Garage Key: it shows the last internal Garage Key shown, else the highest.
  ///
  /// In en, this message translates to:
  /// **'Back to internal Garage Keys'**
  String get p2pGarageBackToInternal;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The discreet link of the card on an internal Garage Key while there is no external Garage Key: it opens today's « Robot recovery ».
  ///
  /// In en, this message translates to:
  /// **'Import an external Garage Key'**
  String get p2pGarageImportExternal;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of the card on the external Garage Key, in the error colour: it asks « Delete the external Garage Key? » (p2pGarageDeleteExternalTitle).
  ///
  /// In en, this message translates to:
  /// **'Delete the external Garage Key'**
  String get p2pGarageDeleteExternal;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the confirmation of « Delete the external Garage Key ».
  ///
  /// In en, this message translates to:
  /// **'Delete the external Garage Key?'**
  String get p2pGarageDeleteExternalTitle;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The text of « Delete the external Garage Key? ».
  ///
  /// In en, this message translates to:
  /// **'It is not backed up by your Bull Wallet. Without a copy, its robots will be lost to this app.'**
  String get p2pGarageDeleteExternalText;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The line in the warning colour of « Delete the external Garage Key? » when trades of that key are in progress; « Delete » stays enabled. {count} is how many, {orders} their numbers, each with its « # », joined with commas (« #48120, #48121 »).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Trade {orders} uses this Garage Key: without it, you will not be able to continue it.} other{Trades {orders} use this Garage Key: without it, you will not be able to continue them.}}'**
  String p2pGarageDeleteExternalTrades(int count, String orders);

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The button of « Delete the external Garage Key? » that deletes it.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get p2pGarageDeleteConfirm;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The title of the notice shown once, at the first opening of the Garage after the update when the vault kept a Garage Key.
  ///
  /// In en, this message translates to:
  /// **'Your Garage Keys'**
  String get p2pGarageNoticeTitle;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The text of « Your Garage Keys », closed by « Got it » (p2pCommonAcknowledged); the names in it are p2pGarageExternalKey and p2pGarageBackToInternal.
  ///
  /// In en, this message translates to:
  /// **'Your current Garage Key is now called « External Garage Key ». The internal Garage Keys, backed up by your Bull Wallet, are next to it: tap « Back to internal Garage Keys ».'**
  String get p2pGarageNoticeText;

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). The line of the Garage, under the robot navigator, for a trade in progress of another Garage Key than the one shown; under it, in grey, its key, robot and coordinator. {orderId} is the order's number.
  ///
  /// In en, this message translates to:
  /// **'Trade in progress #{orderId}'**
  String p2pGarageTradeInProgress(String orderId);

  /// Not in the RoboSats texts: the project's own (#81, the Garage Key card of the mock-up decided on 2026-11-26; 'Garage Key' always written in full). In « Robot recovery », when the key pasted is one of the internal Garage Keys activated on this device: it is not imported. {index} is its number.
  ///
  /// In en, this message translates to:
  /// **'This is already your internal Garage Key #{index}.'**
  String p2pGarageKeyIsInternal(int index);
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
