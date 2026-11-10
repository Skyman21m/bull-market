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

  /// Libellé du 3e onglet de la barre du bas du portefeuille (entre Wallet et Exchange). Tient dans toutes les langues ; libellé définitif à confirmer (PLAN.md § 5 disait provisoirement « Buy NKYC P2P »).
  ///
  /// In en, this message translates to:
  /// **'P2P'**
  String get p2pTabLabel;

  /// fr.json : « Utilisation Testnet Bitcoin » (article manquant, ordre des mots anglais). Le portefeuille écrit « Bitcoin Testnet ». Bandeau en italique, seulement si le réseau P2P est testnet.
  ///
  /// In en, this message translates to:
  /// **'Using Testnet Bitcoin'**
  String get p2pTestnetBanner;

  /// Ligne affichée dans l'onglet P2P pendant que Tor se connecte (l'attente se fait dans l'onglet, pas au démarrage de l'app). Texte de la maquette validée du 10/11/2026.
  ///
  /// In en, this message translates to:
  /// **'Your trades only ever go through Tor.'**
  String get p2pTorWaitingLine;

  /// fr.json : « Initialisation du daemon Tor » ; « daemon » est de l'anglais. Aussi affiché dans le menu P2P.
  ///
  /// In en, this message translates to:
  /// **'Initializing Tor daemon'**
  String get p2pTorInitializing;

  /// État 'STARTING'. Sert aussi de titre à l'écran d'attente dans l'onglet (maquette).
  ///
  /// In en, this message translates to:
  /// **'Connecting to Tor network'**
  String get p2pTorConnecting;

  /// État 'ON'. La fédération (coordinateurs, carnet) ne se charge qu'après cet état.
  ///
  /// In en, this message translates to:
  /// **'Connected to Tor network'**
  String get p2pTorConnected;

  /// Valeur par défaut de l'état Tor chez RoboSats (affichée tant qu'aucun autre état n'est connu).
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get p2pTorConnectionError;

  /// Destination interne à l'onglet P2P (carnet d'ordres). « Offres » gardé car l'anglais dit Offers (glossaire).
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get p2pNavOffers;

  /// Destination centrale quand le robot n'a pas d'ordre actif ; aussi bouton de l'étape 3 de l'assistant. Ouvre le formulaire de création (phase 3) : en phase 1 le bouton peut rester grisé.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get p2pNavCreate;

  /// fr.json = EN (non traduit), mais le mot est identique en français.
  ///
  /// In en, this message translates to:
  /// **'Garage'**
  String get p2pNavGarage;

  /// Destination centrale quand le robot a un ordre actif ; sert aussi de titre à la page d'un ordre (maquette).
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get p2pNavOrder;

  /// fr.json = EN. Bouton étroit (segment du carnet, un quart de largeur) : « Rechercher » tient. Dans le carnet il ouvre « Search order » ; à l'étape 3 de l'assistant, la recherche guidée.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get p2pCommonSearch;

  /// fr.json : « Lister » (verbe, alors que les segments voisins sont des noms) ; la maquette reprenait « Lister ». Segment étroit (un quart de largeur).
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get p2pBookViewList;

  /// Segment du carnet et en-tête du graphique de profondeur. Segment étroit : « Graphique » est le plus long des quatre, à vérifier à 320 px.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get p2pBookViewChart;

  /// fr.json = EN. Segment du carnet, en-tête de la carte et titre de la carte du lieu de rencontre.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get p2pBookViewMap;

  /// Début de la phrase de filtres « Je veux [type] et utiliser [devise] payer avec [mode] hébergé par [hôte] ». Dans la recherche guidée, RoboSats ajoute « ... » après le texte.
  ///
  /// In en, this message translates to:
  /// **'I want to'**
  String get p2pBookFilterIWantTo;

  /// Valeur « indifférent » des quatre sélecteurs (type, devise, mode de paiement, hôte), et valeur de {currencyCode} dans le message de carnet vide. Le masculin pluriel ne s'accorde pas avec « devise » ; on garde un seul mot comme RoboSats.
  ///
  /// In en, this message translates to:
  /// **'ANY'**
  String get p2pBookFilterAny;

  /// Choisir « Acheter » montre les ordres de VENTE (type 1). Aussi bouton de la recherche guidée.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get p2pBookFilterBuy;

  /// Montre les ordres d'ACHAT (type 0).
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get p2pBookFilterSell;

  /// fr.json : « Sélectionner Type d'Ordre » (majuscules à l'anglaise, article manquant). Étiquette du sélecteur de type.
  ///
  /// In en, this message translates to:
  /// **'Select Order Type'**
  String get p2pBookFilterSelectOrderType;

  /// Mot de liaison, affiché seulement si la largeur le permet. Dans la recherche guidée, suivi de « ... ».
  ///
  /// In en, this message translates to:
  /// **'and use'**
  String get p2pBookFilterAndUse;

  /// fr.json : « Sélectionner la Devise de Paiement » (majuscules).
  ///
  /// In en, this message translates to:
  /// **'Select Payment Currency'**
  String get p2pBookFilterSelectCurrency;

  /// Mot de liaison en mode monnaie fiduciaire.
  ///
  /// In en, this message translates to:
  /// **'pay with'**
  String get p2pBookFilterPayWith;

  /// fr.json : « Sélectionner le Mode de Paiement » (majuscules). Version étroite (liste à choix unique).
  ///
  /// In en, this message translates to:
  /// **'Select Payment Method'**
  String get p2pBookFilterSelectMethod;

  /// Mot de liaison avant le sélecteur d'hôte.
  ///
  /// In en, this message translates to:
  /// **'hosted by'**
  String get p2pBookFilterHostedBy;

  /// fr.json : « Sélectionner Hôte » (article manquant, majuscule).
  ///
  /// In en, this message translates to:
  /// **'Select Host'**
  String get p2pBookFilterSelectHost;

  /// Absent de fr.json : valeur renvoyée par l'API (maker_status) et passée à t(). Info-bulle de la pastille verte d'activité du créateur.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get p2pBookMakerStatusActive;

  /// Absent de fr.json. Pastille orange.
  ///
  /// In en, this message translates to:
  /// **'Seen recently'**
  String get p2pBookMakerStatusSeenRecently;

  /// Absent de fr.json. Pastille rouge.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get p2pBookMakerStatusInactive;

  /// Ordre de type 1 (le créateur vend des BTC).
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get p2pBookRoleSeller;

  /// Ordre de type 0.
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get p2pBookRoleBuyer;

  /// En-tête de colonne ; aussi légende du montant fixe dans la fiche de l'ordre (où RoboSats l'affiche sans t(), donc toujours en anglais). Montants : 4 chiffres significatifs, fourchette « min-max » ; en échange, suffixe « M Sats ».
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get p2pBookColumnAmount;

  /// En-tête de colonne et choix d'abscisse du graphique.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get p2pBookColumnPremium;

  /// book/table
  ///
  /// In en, this message translates to:
  /// **'Bond'**
  String get p2pBookColumnBond;

  /// fr.json = EN. Info-bulle de la caution en orange quand elle est sous la valeur par défaut (3 %).
  ///
  /// In en, this message translates to:
  /// **'Low bond: This maker has set a bond below the default {defaultBond}%. Lower bonds mean reduced trade security.'**
  String p2pBookLowBond(String defaultBond);

  /// Message d'erreur générique du tableau (errorOverlayDefaultLabel). Les autres textes internes du tableau MUI (tri, filtres, colonnes) ne sont pas repris : ils n'ont pas d'équivalent dans l'interface du portefeuille.
  ///
  /// In en, this message translates to:
  /// **'An error occurred.'**
  String get p2pBookError;

  /// fr.json : « …vendre des BTC pour {currencyCode} » (« pour EUR » est maladroit). Affiché quand le filtre est « Vendre ». {currencyCode} vaut le code devise ou « Tous » (p2pBookFilterAny).
  ///
  /// In en, this message translates to:
  /// **'No orders found to sell BTC for {currencyCode}'**
  String p2pBookEmptySell(String currencyCode);

  /// Même correction. Affiché pour tout autre filtre que « Vendre » (RoboSats teste type 0, sinon ce texte).
  ///
  /// In en, this message translates to:
  /// **'No orders found to buy BTC for {currencyCode}'**
  String p2pBookEmptyBuy(String currencyCode);

  /// Sous le message de carnet vide, en couleur primaire.
  ///
  /// In en, this message translates to:
  /// **'Be the first one to create an order'**
  String get p2pBookEmptyBeFirst;

  /// Sous le nom long du coordinateur ; la ligne ouvre la fiche du coordinateur. (La maquette mettait aussi « Coordinateur » ailleurs : on garde « Hôte de l'ordre ».)
  ///
  /// In en, this message translates to:
  /// **'Order host'**
  String get p2pOrderHost;

  /// fr.json = EN. Légende sous le numéro de l'ordre (icône #). « Numéro » plutôt que l'abréviation anglaise.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get p2pOrderId;

  /// RoboSats n'affiche que l'initiale (« C ») devant les frais du créateur dans la ligne de frais : prendre le 1er caractère de la traduction, comme RoboSats.
  ///
  /// In en, this message translates to:
  /// **'Maker'**
  String get p2pOrderFeeMaker;

  /// Info-bulle de la ligne de frais et libellé de la fiche coordinateur.
  ///
  /// In en, this message translates to:
  /// **'Maker fee'**
  String get p2pOrderFeeMakerTooltip;

  /// Initiale « P » dans la ligne de frais (« C 0.025% · P 0.175% » dans la maquette).
  ///
  /// In en, this message translates to:
  /// **'Taker'**
  String get p2pOrderFeeTaker;

  /// order/details
  ///
  /// In en, this message translates to:
  /// **'Taker fee'**
  String get p2pOrderFeeTakerTooltip;

  /// fr.json : « Paiements onchain activés » ; graphie « on-chain » du portefeuille. Info-bulle de la puce verte « 🔗 x.x% ».
  ///
  /// In en, this message translates to:
  /// **'Onchain payouts enabled'**
  String get p2pOrderOnchainEnabled;

  /// fr.json : « …onchain désactivés » ; graphie « on-chain ». Info-bulle de l'icône grise ; aussi valeur rouge dans la fiche coordinateur.
  ///
  /// In en, this message translates to:
  /// **'Onchain payouts disabled'**
  String get p2pOrderOnchainDisabled;

  /// Puce du séparateur.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get p2pOrderDetailsDivider;

  /// RoboSats l'affiche ici en dur, sans t() (toujours en anglais) ; fr.json a la clé (venant du formulaire) : « Plage de Montant ». Glossaire : fourchette. Pour un montant fixe, la légende est « Amount » (p2pBookColumnAmount).
  ///
  /// In en, this message translates to:
  /// **'Amount Range'**
  String get p2pOrderAmountRange;

  /// Vu par l'acheteur de BTC. {method} = texte libre des modes de paiement, {amount} = montant + code devise.
  ///
  /// In en, this message translates to:
  /// **'You send via {method} {amount}'**
  String p2pOrderYouSendVia(String method, String amount);

  /// Sats calculés avec les frais du rôle et 0,1 % de budget de routage ; {amount} peut être une fourchette « min-max ».
  ///
  /// In en, this message translates to:
  /// **'You receive {amount} Sats (Approx)'**
  String p2pOrderYouReceiveSats(String amount);

  /// Vu par le vendeur de BTC.
  ///
  /// In en, this message translates to:
  /// **'You send via Lightning {amount} Sats (Approx)'**
  String p2pOrderYouSendLightning(String amount);

  /// order/details
  ///
  /// In en, this message translates to:
  /// **'You receive via {method} {amount}'**
  String p2pOrderYouReceiveVia(String method, String amount);

  /// Légende des modes quand la devise est BTC (ordre d'échange).
  ///
  /// In en, this message translates to:
  /// **'Swap destination'**
  String get p2pOrderSwapDestination;

  /// order/details
  ///
  /// In en, this message translates to:
  /// **'Accepted payment methods'**
  String get p2pOrderAcceptedMethods;

  /// fr.json : « - Prime: {premium}% » (typographie seulement : espaces avant « : » et « % »).
  ///
  /// In en, this message translates to:
  /// **'{price} {currencyCode}/BTC - Premium: {premium}%'**
  String p2pOrderPriceAndPremiumValue(
    String price,
    String currencyCode,
    String premium,
  );

  /// Légende quand le prix courant est connu.
  ///
  /// In en, this message translates to:
  /// **'Price and Premium'**
  String get p2pOrderPriceAndPremium;

  /// fr.json : « Montant de Satoshis » (majuscule, préposition). Ordre à montant de sats explicite sans prix courant.
  ///
  /// In en, this message translates to:
  /// **'Amount of Satoshis'**
  String get p2pOrderAmountOfSatoshis;

  /// Légende quand le prix courant est inconnu (valeur « x% »).
  ///
  /// In en, this message translates to:
  /// **'Premium over market price'**
  String get p2pOrderPremiumOverMarket;

  /// Compte à rebours « {h}h {mm}m {ss}s » (orange sous 25 %, rouge sous 10 %, gras sous 25 %). Format en dur chez RoboSats ; en français « 17 h 04 min 12 s » serait plus juste : à régler dans le composant de compte à rebours.
  ///
  /// In en, this message translates to:
  /// **'Expires in'**
  String get p2pOrderExpiresIn;

  /// Remplace le compte à rebours à zéro.
  ///
  /// In en, this message translates to:
  /// **'The order has expired'**
  String get p2pOrderExpired;

  /// Délai laissé pour le séquestre (« 3h »).
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get p2pOrderDeposit;

  /// Bouton contour. La prise elle-même est en phase 2 ; en phase 1 le bouton s'affiche et mène au dialogue « pas de robot » ou au rappel de sauvegarde.
  ///
  /// In en, this message translates to:
  /// **'Take Order'**
  String get p2pTakeOrder;

  /// Affiché à la place des sections quand le coordinateur ne répond pas (aussi une erreur que le client en lecture seule rencontre).
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

  /// Remplace les modes de paiement personnalisés ou au-delà des icônes affichées.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get p2pBookOthers;
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
