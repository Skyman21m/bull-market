// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'p2p_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class P2pLocalizationsFr extends P2pLocalizations {
  P2pLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get p2pTabLabel => 'P2P';

  @override
  String get p2pTestnetBanner => 'Utilisation du Bitcoin Testnet';

  @override
  String get p2pTorWaitingLine =>
      'La connexion aux coordinateurs passe uniquement par Tor.';

  @override
  String get p2pTorInitializing => 'Initialisation du service Tor';

  @override
  String get p2pTorConnecting => 'Connexion au réseau Tor';

  @override
  String get p2pTorConnected => 'Connecté au réseau Tor';

  @override
  String get p2pTorConnectionError => 'Erreur de connexion';

  @override
  String get p2pNavOffers => 'Offres';

  @override
  String get p2pNavCreate => 'Créer';

  @override
  String get p2pNavGarage => 'Garage';

  @override
  String get p2pNavOrder => 'Ordre';

  @override
  String get p2pCommonSearch => 'Rechercher';

  @override
  String get p2pBookViewList => 'Liste';

  @override
  String get p2pBookViewChart => 'Graphique';

  @override
  String get p2pBookViewMap => 'Carte';

  @override
  String get p2pBookFilterIWantTo => 'Je veux';

  @override
  String get p2pBookFilterAny => 'Tous';

  @override
  String get p2pBookFilterBuy => 'Acheter';

  @override
  String get p2pBookFilterSell => 'Vendre';

  @override
  String get p2pBookFilterSelectOrderType => 'Sélectionner le type d\'ordre';

  @override
  String get p2pBookFilterAndUse => 'et utiliser';

  @override
  String get p2pBookFilterSelectCurrency =>
      'Sélectionner la devise de paiement';

  @override
  String get p2pBookFilterPayWith => 'payer avec';

  @override
  String get p2pBookFilterSelectMethod => 'Sélectionner le mode de paiement';

  @override
  String get p2pBookFilterHostedBy => 'hébergé par';

  @override
  String get p2pBookFilterSelectHost => 'Sélectionner l\'hôte';

  @override
  String get p2pBookMakerStatusActive => 'Actif';

  @override
  String get p2pBookMakerStatusSeenRecently => 'Vu récemment';

  @override
  String get p2pBookMakerStatusInactive => 'Inactif';

  @override
  String get p2pBookRoleSeller => 'Vendeur';

  @override
  String get p2pBookRoleBuyer => 'Acheteur';

  @override
  String get p2pBookColumnAmount => 'Montant';

  @override
  String get p2pBookColumnPremium => 'Prime';

  @override
  String get p2pBookColumnBond => 'Caution';

  @override
  String p2pBookLowBond(String defaultBond) {
    return 'Caution basse : ce créateur a fixé une caution inférieure à la valeur par défaut de $defaultBond %. Une caution plus basse rend l\'échange moins sûr.';
  }

  @override
  String get p2pBookError => 'Une erreur s\'est produite.';

  @override
  String p2pBookEmptySell(String currencyCode) {
    return 'Aucun ordre trouvé pour vendre des BTC contre $currencyCode';
  }

  @override
  String p2pBookEmptyBuy(String currencyCode) {
    return 'Aucun ordre trouvé pour acheter des BTC contre $currencyCode';
  }

  @override
  String get p2pBookEmptyBeFirst => 'Soyez le premier à créer un ordre';

  @override
  String get p2pOrderHost => 'Hôte de l\'ordre';

  @override
  String get p2pOrderId => 'Numéro';

  @override
  String get p2pOrderFeeMaker => 'Créateur';

  @override
  String get p2pOrderFeeMakerTooltip => 'Frais du créateur';

  @override
  String get p2pOrderFeeTaker => 'Preneur';

  @override
  String get p2pOrderFeeTakerTooltip => 'Frais du preneur';

  @override
  String get p2pOrderOnchainEnabled => 'Paiements on-chain activés';

  @override
  String get p2pOrderOnchainDisabled => 'Paiements on-chain désactivés';

  @override
  String get p2pOrderDetailsDivider => 'Détails de l\'ordre';

  @override
  String get p2pOrderAmountRange => 'Fourchette de montant';

  @override
  String p2pOrderYouSendVia(String method, String amount) {
    return 'Vous envoyez via $method $amount';
  }

  @override
  String p2pOrderYouReceiveSats(String amount) {
    return 'Vous recevez $amount Sats (environ)';
  }

  @override
  String p2pOrderYouSendLightning(String amount) {
    return 'Vous envoyez via Lightning $amount Sats (environ)';
  }

  @override
  String p2pOrderYouReceiveVia(String method, String amount) {
    return 'Vous recevez via $method $amount';
  }

  @override
  String get p2pOrderSwapDestination => 'Destination de l\'échange';

  @override
  String get p2pOrderAcceptedMethods => 'Modes de paiement acceptés';

  @override
  String p2pOrderPriceAndPremiumValue(
    String price,
    String currencyCode,
    String premium,
  ) {
    return '$price $currencyCode/BTC - Prime : $premium %';
  }

  @override
  String get p2pOrderPriceAndPremium => 'Prix et prime';

  @override
  String get p2pOrderAmountOfSatoshis => 'Montant en satoshis';

  @override
  String get p2pOrderPremiumOverMarket => 'Prime sur le prix du marché';

  @override
  String get p2pOrderExpiresIn => 'Expire dans';

  @override
  String get p2pOrderExpired => 'L\'ordre a expiré';

  @override
  String get p2pOrderDeposit => 'Dépôt';

  @override
  String get p2pTakeOrder => 'Prendre l\'ordre';

  @override
  String get p2pCoordinatorOffline => 'Coordinateur hors ligne';

  @override
  String get p2pOrderMaker => 'Créateur de l\'ordre';

  @override
  String get p2pCommonRetry => 'Réessayer';

  @override
  String p2pBookCoordinatorsLoading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coordinateurs en cours de chargement',
      one: '1 coordinateur en cours de chargement',
    );
    return '$_temp0';
  }

  @override
  String p2pDurationHours(String hours) {
    return '$hours h';
  }

  @override
  String p2pDurationMinutes(String minutes) {
    return '$minutes min';
  }

  @override
  String p2pDurationHoursMinutes(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String p2pCountdownHms(String hours, String minutes, String seconds) {
    return '$hours h $minutes min $seconds s';
  }

  @override
  String get p2pBookOthers => 'Autres';

  @override
  String get p2pReversibleTitle => 'Paiements réversibles';

  @override
  String get p2pReversibleIntro =>
      'Cet ordre propose un ou plusieurs modes de paiement que la communauté a régulièrement signalés comme annulant leurs transactions.';

  @override
  String get p2pReversible80Days =>
      'Si vous recevez une transaction fiduciaire, elle peut être unilatéralement annulée jusqu\'à 80 jours après la conclusion de l\'échange.';

  @override
  String get p2pReversibleNoControl =>
      'RoboSats et ses coordinateurs n\'ont aucun contrôle sur le système fiduciaire.';

  @override
  String get p2pReversibleScammers =>
      'Des escrocs peuvent exploiter cette faille du système fiduciaire pour vous prendre à la fois vos bitcoins et votre monnaie fiduciaire.';

  @override
  String get p2pCommonAcknowledged => 'Compris';

  @override
  String get p2pCoordinatorNotice => 'Avis du coordinateur';

  @override
  String get p2pCoordinatorBadgeFounder =>
      'Fondateur : coordonne les échanges depuis la fédération de testnet.';

  @override
  String get p2pCoordinatorBadgeNotFounder => 'Pas un fondateur de fédération';

  @override
  String p2pCoordinatorBadgeDevFund(String percent) {
    return 'Soutien du fonds de développement : fait don de $percent % pour améliorer RoboSats.';
  }

  @override
  String get p2pCoordinatorBadgeGoodOpsec =>
      'Bonne sécurité opérationnelle : le coordinateur suit les meilleures pratiques pour protéger sa vie privée et la vôtre.';

  @override
  String get p2pCoordinatorBadgeOpsecCouldImprove =>
      'Les pratiques de confidentialité de ce coordinateur pourraient s\'améliorer';

  @override
  String get p2pCoordinatorBadgeLargeLimits =>
      'Limites élevées : le coordinateur accepte des échanges de grande taille.';

  @override
  String get p2pCoordinatorBadgeNoLargeLimits =>
      'N\'accepte pas d\'échanges de grande taille.';

  @override
  String get p2pCoordinatorDescription => 'Description du coordinateur';

  @override
  String get p2pCoordinatorEstablished => 'Date de création';

  @override
  String get p2pCoordinatorHostedWebApp =>
      'Application web hébergée par le coordinateur';

  @override
  String get p2pCoordinatorPolicies => 'Politiques';

  @override
  String get p2pCoordinatorSummary => 'Résumé';

  @override
  String get p2pCoordinatorMaxOrderSize => 'Taille maximale de l\'ordre';

  @override
  String get p2pCoordinatorOnchainStatus =>
      'Statut actuel des paiements on-chain';

  @override
  String get p2pCoordinatorCurrentOnchainFee =>
      'Frais actuels de paiement on-chain';

  @override
  String get p2pCoordinatorMaxSwapSize =>
      'Taille maximale d\'un échange on-chain';

  @override
  String get p2pCoordinatorDevFundZaps =>
      'Donne volontairement au développement';

  @override
  String p2pCoordinatorDevFundPercent(String percent) {
    return '$percent % des bénéfices';
  }

  @override
  String get p2pCoordinatorPublicBuyOrders => 'Ordres d\'achat publics';

  @override
  String get p2pCoordinatorPublicSellOrders => 'Ordres de vente publics';

  @override
  String get p2pCoordinatorBookLiquidity => 'Liquidité du carnet';

  @override
  String get p2pCoordinatorActiveRobotsToday => 'Robots actifs aujourd\'hui';

  @override
  String get p2pCoordinatorNonKycPremium => 'Prime bitcoin non-KYC en 24h';

  @override
  String get p2pCoordinatorPriceSources =>
      'Sources des prix du marché (pour plusieurs, la médiane est calculée)';

  @override
  String get p2pCoordinatorStatsForNerds => 'Stats pour les geeks';

  @override
  String get p2pCoordinatorVersionCoordinator => 'Coordinateur';

  @override
  String get p2pCoordinatorRoboSatsVersion => 'Version RoboSats';

  @override
  String get p2pCoordinatorLndVersion => 'Version LND';

  @override
  String get p2pCoordinatorClnVersion => 'Version CLN';

  @override
  String p2pCoordinatorLnNodeAlias(String alias) {
    return 'Nœud LN : $alias';
  }

  @override
  String get p2pCoordinatorCommitHash =>
      'Empreinte de la révision du coordinateur';

  @override
  String get p2pCoordinatorVolume24h => 'Volume des échanges sur 24h';

  @override
  String get p2pCoordinatorVolumeLifetime => 'Volume total des échanges';

  @override
  String p2pCoordinatorSatsValue(String amount) {
    return '$amount Sats';
  }

  @override
  String get p2pCoordinatorSendEmail => 'Envoyer un e-mail';

  @override
  String get p2pCoordinatorWebsite => 'Site web';

  @override
  String get p2pCoordinatorPgpFingerprint => 'Empreinte de la clé publique PGP';

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
  String get p2pCommonCopy => 'Copier';

  @override
  String get p2pCommonCopied => 'Copié !';

  @override
  String get p2pSearchOrderTitle => 'Rechercher un ordre';

  @override
  String get p2pSearchOrderText =>
      'Saisissez ici l\'URL d\'un ordre pour le retrouver, même s\'il est protégé par un mot de passe';

  @override
  String get p2pSearchOrderUrlLabel => 'URL de l\'ordre';

  @override
  String get p2pCommonCancel => 'Annuler';

  @override
  String get p2pNoRobotTitle => 'Vous n\'avez pas de clé de garage';

  @override
  String get p2pNoRobotText =>
      'Générez une clé de garage pour obtenir votre première identité de robot et commencer à échanger.';

  @override
  String get p2pNoRobotHaveKey => 'J\'ai une clé de garage';

  @override
  String get p2pGarageOnboardingGenerateKey => 'Générer une clé de garage';
}
