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
  String get p2pTorWaitPhrase1 => 'Des sats à la vitesse de la lumière';

  @override
  String get p2pTorWaitPhrase2 => 'On épluche l’oignon, couche par couche';

  @override
  String get p2pTorWaitPhrase3 => 'Rebond de relais en relais';

  @override
  String get p2pTorWaitPhrase4 =>
      'Votre adresse IP reste cachée aux coordinateurs';

  @override
  String get p2pTorWaitPhrase5 => 'Réveil des robots';

  @override
  String get p2pTorWaitPhrase6 => 'Pas de KYC, juste des robots';

  @override
  String get p2pTorWaitPhrase7 => 'Pas vos clés, pas vos bitcoins';

  @override
  String get p2pTorWaitPhrase8 => 'Ne faites pas confiance, vérifiez';

  @override
  String get p2pTorWaitPhrase9 => 'La vie privée n’est pas un crime';

  @override
  String get p2pTorWaitPhrase10 => 'Soyez votre propre banque';

  @override
  String get p2pTorWaitPhrase11 => 'Tic tac, prochain bloc';

  @override
  String get p2pTorWaitPhrase12 => 'Chargement à faible préférence temporelle';

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
  String get p2pBookFilterIWant => 'Je veux';

  @override
  String get p2pBookFilterAnyType => 'Tout type';

  @override
  String get p2pBookFilterAnyCurrency => 'Toute devise';

  @override
  String get p2pBookFilterAnyMethod => 'Tout mode de paiement';

  @override
  String get p2pBookFilterAnyHost => 'Tout hôte';

  @override
  String p2pBookFilterMore(String first, int count) {
    return '$first +$count';
  }

  @override
  String get p2pBookFilterSubjectType => 'Type d\'ordre';

  @override
  String get p2pBookFilterSubjectCurrency => 'Devise';

  @override
  String get p2pBookFilterSubjectMethod => 'Mode de paiement';

  @override
  String get p2pBookFilterSubjectHost => 'Hôte';

  @override
  String p2pBookFilterChoices(String subject, String choices) {
    return '$subject : $choices';
  }

  @override
  String p2pBookFilterOrList(String others, String last) {
    return '$others ou $last';
  }

  @override
  String get p2pBookFilterListSeparator => ', ';

  @override
  String p2pBookFilterOrderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres',
      one: '1 ordre',
      zero: 'aucun ordre',
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
  String get p2pBookFilterMethodsWithoutOrders => 'Aucun ordre pour l\'instant';

  @override
  String get p2pBookFilterNoMethodFound => 'Aucun mode de paiement trouvé';

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
  String get p2pBookEmptyAnyCurrency => 'n\'importe quelle devise';

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
  String p2pBookCoordinatorsAnswered(int answered, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      answered,
      locale: localeName,
      other: '$answered coordinateurs sur $total ont répondu',
      one: '1 coordinateur sur $total a répondu',
      zero: '0 coordinateur sur $total a répondu',
    );
    return '$_temp0';
  }

  @override
  String p2pBookCoordinatorsOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coordinateurs hors ligne',
      one: '1 coordinateur hors ligne',
    );
    return '$_temp0';
  }

  @override
  String p2pBookCoordinatorAnswered(String name) {
    return '$name, a répondu';
  }

  @override
  String p2pBookCoordinatorAwaited(String name) {
    return '$name, en attente';
  }

  @override
  String p2pBookCoordinatorOffline(String name) {
    return '$name, hors ligne';
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
  String p2pAmountSats(String amount) {
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
  String get p2pCommonCopied => 'Copié !';

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
  String get p2pOrderNotAvailable => 'Cet ordre n\'est pas disponible';

  @override
  String get p2pGarageOnboardingGenerateKey => 'Générer une clé de garage';

  @override
  String get p2pCoordinatorLnNode => 'Nœud LN';

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
  String get p2pCommonCopy => 'Copier';

  @override
  String get p2pBookColumnPrice => 'Prix';

  @override
  String get p2pChartBtc => 'BTC';

  @override
  String get p2pChartZoomOut => 'Zoom arrière';

  @override
  String get p2pChartZoomIn => 'Zoom avant';

  @override
  String p2pChartCenterPrice(String price, String currencyCode) {
    return '$price $currencyCode';
  }

  @override
  String p2pChartBuyOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres d\'achat',
      one: '$count ordre d\'achat',
    );
    return '$_temp0';
  }

  @override
  String p2pChartSellOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres de vente',
      one: '$count ordre de vente',
    );
    return '$_temp0';
  }

  @override
  String p2pChartSummary(String center, String buyOrders, String sellOrders) {
    return 'Graphique de profondeur centré sur $center : $buyOrders et $sellOrders.';
  }

  @override
  String get p2pChartSummaryNoAxis =>
      'Graphique de profondeur : rien à tracer sur cet axe.';

  @override
  String get p2pMapNoLocation => 'Aucun ordre avec un emplacement face à face';

  @override
  String p2pMapSummary(String buyOrders, String sellOrders) {
    return 'Carte des emplacements face à face du carnet d\'ordres : $buyOrders et $sellOrders.';
  }

  @override
  String p2pMapOrdersHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordres ici',
      one: '$count ordre ici',
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
  String get p2pCommonContinue => 'Continuer';

  @override
  String get p2pGarageKeyInvalid => 'Clé de garage invalide';

  @override
  String get p2pGarageTradingAvatar => 'Ceci est votre avatar d\'échange';

  @override
  String get p2pGaragePreviousAccount => 'Compte précédent';

  @override
  String get p2pGarageNextAccount => 'Compte suivant';

  @override
  String get p2pGarageRobotLabel => 'Robot';

  @override
  String get p2pGarageKeyLabel => 'Clé de garage';

  @override
  String get p2pRecoveryTitle => 'Récupération du robot';

  @override
  String get p2pRecoveryModeGarageKey => 'Mode clé de garage';

  @override
  String get p2pRecoveryGarageKeyText =>
      'Saisissez votre clé de garage (robo1...) pour récupérer tous vos comptes robot.';

  @override
  String get p2pRecoveryPasteHere => 'Coller le jeton ici';

  @override
  String get p2pRecoveryInProgress =>
      'Récupération de votre robot. Cela peut prendre un moment.';

  @override
  String get p2pRecoveryRecover => 'Récupérer';

  @override
  String get p2pGarageKeyMustStartWith => 'Doit commencer par « robo1 »';

  @override
  String get p2pGarageKeyInvalidLength => 'Longueur invalide';

  @override
  String get p2pGarageKeyInvalidData => 'Données de clé invalides';

  @override
  String get p2pGarageKeyReveal => 'Afficher la clé de garage';

  @override
  String get p2pGarageScreenPrivacyUnavailable =>
      'La protection de l’écran n’a pas pu être activée : la clé de garage reste masquée.';

  @override
  String get p2pGarageKeyLocked =>
      'Le coffre de l’appareil est verrouillé. Déverrouillez votre appareil, puis réessayez.';

  @override
  String get p2pGarageKeyUnreadable =>
      'La clé de garage enregistrée sur cet appareil ne peut pas être lue.';

  @override
  String get p2pGarageKeyUnusable =>
      'La clé de garage enregistrée sur cet appareil est endommagée.';

  @override
  String get p2pGarageKeyUnreadableHelp =>
      'Réessayez. Si l’échec persiste, supprimez-la : la clé et ses robots sont perdus, sauf si vous en avez gardé une copie.';

  @override
  String get p2pGarageKeyNotSaved =>
      'La clé de garage n’a pas pu être enregistrée. Réessayez.';

  @override
  String get p2pGarageKeyNotDeleted =>
      'La clé de garage n’a pas pu être supprimée. Réessayez.';

  @override
  String get p2pGarageKeyAlreadyStored =>
      'Une clé de garage est déjà enregistrée pour ce réseau.';

  @override
  String get p2pGarageRobotUnavailable =>
      'Aucun robot ne peut être créé à partir de cette clé de garage.';

  @override
  String get p2pCommonPaste => 'Coller';

  @override
  String get p2pCommonClear => 'Effacer';

  @override
  String get p2pRobotCoordinatorTitle =>
      'Coordinateur qui connaît votre robot :';

  @override
  String get p2pRobotNoCoordinator =>
      'Aucun coordinateur ne connaît encore ce robot.';

  @override
  String get p2pRobotSelectHost => 'Sélectionner l\'hôte';

  @override
  String p2pRobotHostDetails(String coordinator) {
    return 'Détails de $coordinator';
  }

  @override
  String p2pRobotSendTitle(String nickname, String coordinator) {
    return 'Envoyer $nickname à $coordinator ?';
  }

  @override
  String p2pRobotSendBody(String coordinator) {
    return '$coordinator connaîtra ce robot désormais. Dans Bull Market, un robot ne vit que chez un seul coordinateur : ce robot ne sera jamais envoyé à un autre. Pour échanger ailleurs, utilisez un autre robot.';
  }

  @override
  String get p2pRobotSendOtherApp =>
      'Si vous utilisez aussi cette clé de garage dans une autre application, celle-ci peut envoyer ce robot à tous les coordinateurs.';

  @override
  String get p2pGarageBuildingRobot => 'Construction de votre robot !';

  @override
  String get p2pRobotLookingForOrders => 'Recherche d\'ordres !';

  @override
  String p2pRobotStillWaiting(String coordinator) {
    return 'Toujours en attente de $coordinator. Tor peut prendre une minute.';
  }

  @override
  String p2pRobotActiveOrder(String orderId) {
    return 'Ordre actif #$orderId';
  }

  @override
  String p2pRobotLastOrder(String orderId) {
    return 'Dernier ordre #$orderId';
  }

  @override
  String get p2pRobotNoOrders => 'Aucun ordre existant trouvé';

  @override
  String get p2pRobotUsedInTrade =>
      'Ce robot a participé à un échange. Passez à un nouveau compte pour préserver votre vie privée.';

  @override
  String get p2pRobotRewards => 'Vos compensations';

  @override
  String p2pRobotAlreadyExisted(String coordinator) {
    return 'Ce robot existait déjà chez $coordinator.';
  }

  @override
  String p2pRobotOnOtherNetwork(String network) {
    String _temp0 = intl.Intl.selectLogic(network, {
      'testnet': 'testnet',
      'other': 'mainnet',
    });
    return 'Ce robot vit chez un coordinateur $_temp0.';
  }

  @override
  String get p2pRobotCoordinatorTooManyRefusals =>
      'Ce coordinateur a refusé trop de robots.';

  @override
  String get p2pRobotBusy =>
      'Trop de requêtes attendent ce coordinateur. Réessayez dans un instant.';

  @override
  String p2pRobotNicknameTaken(String coordinator) {
    return 'Le nom de ce robot est déjà pris chez $coordinator : il ne peut pas y être créé. Utilisez le robot suivant.';
  }

  @override
  String p2pRobotNotCreated(String coordinator) {
    return '$coordinator ne connaît pas encore ce robot.';
  }

  @override
  String p2pRobotKeyTooRecent(String coordinator) {
    return '$coordinator a refusé la clé du robot, jugée trop récente. Vérifiez la date et l’heure de votre téléphone, puis réessayez.';
  }

  @override
  String p2pRobotRefused(String coordinator) {
    return '$coordinator a refusé ce robot. Il utilise peut-être une autre version de RoboSats.';
  }

  @override
  String p2pRobotMismatch(String coordinator) {
    return '$coordinator a répondu avec un autre robot, ou avec des clés que ce robot n’a pas créées. N’utilisez pas ce robot chez ce coordinateur.';
  }

  @override
  String p2pRobotBadAnswer(String coordinator) {
    return '$coordinator a envoyé une réponse que Bull Market ne peut pas lire.';
  }

  @override
  String p2pRobotCoordinatorChanged(String coordinator) {
    return '$coordinator a changé d’adresse ou de clés depuis que ce robot lui a été envoyé. Rien n’a été envoyé. Tant qu’une mise à jour de l’application n’a pas vérifié ce changement, utilisez un autre robot.';
  }

  @override
  String get p2pRobotStorage =>
      'Bull Market n’a pas pu lire ses enregistrements sur cet appareil. Rien n’a été envoyé.';

  @override
  String p2pRobotNostrOld(String coordinator) {
    return '$coordinator détient une ancienne clé Nostr de ce robot, qu’il peut calculer : ses notifications ne sont pas privées. Préférez un autre robot pour échanger.';
  }

  @override
  String p2pRobotNostrUnknown(String coordinator) {
    return '$coordinator détient une clé Nostr que cette application ne peut pas utiliser : les notifications concernant ce robot ne lui parviendront pas.';
  }

  @override
  String get p2pRobotKeyComputeFailed =>
      'Ce téléphone n’a pas pu créer ou vérifier les clés de ce robot. Vérifiez sa date et son heure, puis réessayez.';

  @override
  String get p2pRobotBoundElsewhere =>
      'Ce robot vit chez un autre coordinateur. Rien n’a été envoyé.';

  @override
  String get p2pRobotRecordsUnreadable =>
      'Bull Market n’a pas pu lire ses enregistrements sur cet appareil.';

  @override
  String get p2pRobotHistoryTitle => 'Robots venus d’ailleurs';

  @override
  String get p2pRobotHistoryBody =>
      'Cette clé de garage a été importée, ou cet appareil n’a pas pu enregistrer qu’il l’a générée. Ses robots existent peut-être déjà chez des coordinateurs : l’application officielle RoboSats envoie chaque robot qu’elle affiche à tous les coordinateurs. Dans Bull Market, un robot ne vit que chez un seul coordinateur : si vous avez déjà utilisé cette clé, placez chaque robot chez le coordinateur où vous l’avez utilisé. Pour repartir de zéro, revenez aux clés de garage internes.';

  @override
  String get p2pRobotHistoryConfirm => 'Je comprends';

  @override
  String p2pTakeAmountLabel(String currencyCode) {
    return 'Montant $currencyCode';
  }

  @override
  String get p2pTakeAmountHint =>
      'Saisissez le montant de fiat à échanger contre des bitcoins';

  @override
  String get p2pTakeTooLow => 'Trop bas';

  @override
  String get p2pTakeTooHigh => 'Trop élevé';

  @override
  String p2pTakeYouWillReceive(String satoshis) {
    return 'Vous recevrez $satoshis Sats (environ)';
  }

  @override
  String p2pTakeYouWillSend(String satoshis) {
    return 'Vous enverrez $satoshis Sats (environ)';
  }

  @override
  String get p2pTakeSpecifyAmountFirst =>
      'Vous devez d\'abord spécifier un montant';

  @override
  String get p2pStoreKeyTitle => 'Conservez votre clé de garage';

  @override
  String get p2pStoreKeyText =>
      'Votre clé de garage donne accès à tous vos comptes de robot. Conservez-la en lieu sûr. Vous pouvez simplement la copier dans une autre application.';

  @override
  String get p2pCommonGoBack => 'Retour';

  @override
  String get p2pCommonDone => 'Fait';

  @override
  String p2pTakeCoordinatorUnreadable(String coordinator) {
    return 'Impossible de joindre $coordinator. L’ordre n’a pas été pris.';
  }

  @override
  String get p2pTakeOrderChanged =>
      'Cet ordre a changé depuis son affichage. Il n’a pas été pris : rouvrez-le depuis le carnet.';

  @override
  String get p2pOrderDescription => 'Description de l\'ordre';

  @override
  String get p2pTakerBond => 'Caution du preneur';

  @override
  String p2pTakeBondEstimate(String estimate, String ceiling) {
    return '$estimate Sats, au plus $ceiling Sats';
  }

  @override
  String p2pTakeReadAt(String time) {
    return 'Lu par votre robot à $time';
  }

  @override
  String p2pTakeFreshRobot(String nickname) {
    return 'Robot neuf pour cet ordre : $nickname.';
  }

  @override
  String p2pOrderNewValue(String value) {
    return 'Nouvelle valeur : $value';
  }

  @override
  String get p2pTakeOrderChangedRead => 'L’ordre a changé.';

  @override
  String p2pTakeStepCheckingOrder(String coordinator) {
    return 'Vérification de l’ordre auprès de $coordinator';
  }

  @override
  String get p2pTakeStepCreatingRobot => 'Construction de votre robot !';

  @override
  String get p2pTakeStepReadingOrder => 'Votre robot lit l’ordre';

  @override
  String get p2pTakeStepReadingOrderAgain => 'Votre robot relit l’ordre';

  @override
  String p2pTakeStepSendingTake(String coordinator) {
    return 'Prise de l’ordre auprès de $coordinator';
  }

  @override
  String p2pTradeFirstRead(String coordinator) {
    return 'Votre robot lit l’ordre chez $coordinator';
  }

  @override
  String get p2pTakeAmountOutOfRange =>
      'Le montant indiqué est en dehors de la plage fixée par le créateur';

  @override
  String p2pTakeFeeTooHigh(String coordinator) {
    return '$coordinator demande des frais de preneur supérieurs à 1 %. L’ordre n’a pas été pris.';
  }

  @override
  String get p2pTakeTermsUnusable =>
      'Les conditions de cet ordre n’ont pas pu être vérifiées. Il n’a pas été pris.';

  @override
  String p2pTakeNotTakenAfter(String reason) {
    return '$reason L’ordre n’a pas été pris.';
  }

  @override
  String get p2pTakeNotRecorded =>
      'Bull Market n’a pas pu écrire ses enregistrements sur cet appareil. L’ordre n’a pas été pris.';

  @override
  String p2pTakeRobotNotNew(String coordinator) {
    return 'Le robot choisi pour cet ordre existait déjà chez $coordinator. L’ordre n’a pas été pris : réessayez.';
  }

  @override
  String get p2pTakeNotMade => 'L’ordre n’a pas été pris.';

  @override
  String get p2pTakeAlreadyMaker =>
      'Vous êtes déjà le créateur d’un ordre actif';

  @override
  String get p2pTakeAlreadyTaker =>
      'Vous êtes déjà le preneur d’un ordre actif';

  @override
  String get p2pTakeAlreadyTaking =>
      'Vous êtes déjà en train de prendre un ordre actif';

  @override
  String get p2pTakePaymentPending =>
      'Vous attendez encore un paiement d’un ordre récent';

  @override
  String p2pTakePenalty(String seconds) {
    return 'Vous devez attendre $seconds secondes pour prendre un ordre';
  }

  @override
  String get p2pTakeWaitPenalty =>
      'Attendez jusqu\'à ce que vous puissiez prendre un ordre';

  @override
  String get p2pTradeTabContract => 'Contrat';

  @override
  String p2pTradeStep(String step, String steps) {
    return '($step/$steps)';
  }

  @override
  String p2pTradeTitleLockBond(String amountSats) {
    return 'Bloquez $amountSats sats pour PRENDRE l’ordre';
  }

  @override
  String p2pTradeTitleLockBondPublish(String amountSats) {
    return 'Bloquez $amountSats sats pour PUBLIER l’ordre';
  }

  @override
  String p2pTradeTitleLockEscrow(String amountSats) {
    return 'Bloquez $amountSats sats en garantie';
  }

  @override
  String p2pTradeEscrowTimeWarning(String hours, String minutes) {
    return 'Vous risquez de perdre votre caution si vous ne bloquez pas la garantie. Le temps total disponible est de $hours h $minutes min.';
  }

  @override
  String get p2pTradeYouAreBuying => 'Vous ACHETEZ des BTC';

  @override
  String get p2pTradeYouAreSelling => 'Vous VENDEZ des BTC';

  @override
  String get p2pTradeCompatibleWallets => 'Voir Portefeuilles compatibles';

  @override
  String get p2pTradeCopyToClipboard => 'Copier dans le presse-papiers';

  @override
  String get p2pTradeHoldInvoiceBond =>
      'Ceci est une facture en attente, elle sera gelée dans votre portefeuille. Elle ne sera débitée que si vous annulez ou perdez un litige.';

  @override
  String p2pTradeHoldInvoiceEscrow(String currencyCode) {
    return 'Ceci est une facture en attente, elle sera gelée dans votre portefeuille. Elle sera remise à l\'acheteur une fois que vous aurez confirmé avoir reçu les $currencyCode.';
  }

  @override
  String get p2pTradeInvoiceQr => 'QR code de la facture de caution';

  @override
  String get p2pTradeEscrowQr => 'QR code de la facture de garantie';

  @override
  String get p2pTradeInvoiceExpires => 'Expire à';

  @override
  String get p2pTradeInvoiceNetwork => 'Réseau';

  @override
  String get p2pTradeInvoiceDescription => 'Description';

  @override
  String get p2pTradeNetworkMainnet => 'Bitcoin';

  @override
  String get p2pTradeNetworkTestnet => 'Bitcoin testnet';

  @override
  String get p2pTradePayOtherWallet => 'Payer avec un autre portefeuille';

  @override
  String get p2pTradeShowAnyway => 'Afficher quand même';

  @override
  String get p2pTradeBondLocked => 'Votre caution de preneur est bloquée';

  @override
  String get p2pTradeBondUnlocked => 'Votre caution de preneur est débloquée';

  @override
  String get p2pTradeBondSettled => 'Votre caution de preneur est débitée';

  @override
  String get p2pTradeTitlePayout => 'Indiquez où recevoir les sats';

  @override
  String p2pTradePayoutPrompt(String amountFiat, String currencyCode) {
    return 'Avant de vous laisser envoyer $amountFiat $currencyCode, nous voulons nous assurer que vous êtes en mesure de recevoir les BTC.';
  }

  @override
  String get p2pTradePayoutPromptNoAmount =>
      'Avant de vous laisser envoyer la monnaie fiat, nous voulons nous assurer que vous êtes en mesure de recevoir les BTC.';

  @override
  String get p2pTradeTitleInfoGood => 'Vos informations sont correctes !';

  @override
  String get p2pTradeTitleCollateralLocked =>
      'La garantie de l\'échange est bloquée !';

  @override
  String get p2pTradeEscrowWait =>
      'Nous attendons que le vendeur verrouille le montant de la transaction.';

  @override
  String get p2pTradeEscrowWaitHangOn =>
      'Patientez un instant. Si le vendeur ne dépose pas, vous récupérerez automatiquement votre caution. De plus, vous recevrez une compensation (consultez les récompenses dans votre profil).';

  @override
  String get p2pTradePayoutWait =>
      'Nous attendons que l\'acheteur publie une facture lightning. Une fois qu\'il l\'a fait, vous pourrez communiquer directement les détails du paiement.';

  @override
  String get p2pTradePayoutWaitHangOn =>
      'Patientez un instant. Si l\'acheteur ne coopère pas, vous récupérerez automatiquement la garantie de la transaction et votre caution. De plus, vous recevrez une compensation (consultez les récompenses dans votre profil).';

  @override
  String get p2pTradeExpiredNotTaken => 'Expiré sans avoir été pris';

  @override
  String get p2pTradeExpiredMakerBond => 'Caution du créateur non bloquée';

  @override
  String get p2pTradeExpiredEscrow => 'Dépôt de garantie non bloqué';

  @override
  String get p2pTradeExpiredInvoice => 'Facture non soumise';

  @override
  String get p2pTradeExpiredNeither =>
      'Ni dépôt de garantie bloqué ni facture soumise';

  @override
  String get p2pOrderCancelled => 'Cet ordre a été annulé';

  @override
  String get p2pTradeTitleChat => 'Discutez avec le vendeur';

  @override
  String get p2pTradeTitleChatWithBuyer => 'Discutez avec l\'acheteur';

  @override
  String get p2pTradeTitleDispute => 'Un litige a été ouvert';

  @override
  String get p2pTradeTitleStatementReceived =>
      'Nous avons reçu votre déclaration';

  @override
  String get p2pTradeTitleSendingSats => 'Tentative de paiement Lightning';

  @override
  String get p2pTradeTitleFinished => 'Échange terminé !';

  @override
  String get p2pTradeTitleRoutingFailed => 'Échec du routage Lightning';

  @override
  String get p2pTradeTitleStatements => 'Nous avons les déclarations';

  @override
  String get p2pTradeTitleDisputeWon => 'Vous avez gagné le litige';

  @override
  String get p2pTradeTitleDisputeLost => 'Vous avez perdu le litige';

  @override
  String get p2pTradeTitleUnknown => 'Statut d’ordre inconnu';

  @override
  String get p2pTradeStepLater =>
      'Bull Market ne peut pas encore afficher cette étape.';

  @override
  String get p2pTradeCopyUrl => 'Copier l\'URL';

  @override
  String get p2pTradeCopyOrderUrl => 'Copier l\'URL de l\'ordre';

  @override
  String get p2pTradeCancelOrder => 'Annuler l\'ordre';

  @override
  String get p2pTradeCancelUnilateral =>
      'Annulation unilatérale (caution en jeu !)';

  @override
  String get p2pTradeCancelWhilePayout =>
      '« Annuler » est désactivé pendant l’envoi de vos informations de paiement.';

  @override
  String get p2pTradeCancelTitle => 'Annuler l\'ordre?';

  @override
  String get p2pTradeCancelPreTakeText =>
      'Si l’ordre est annulé maintenant alors que vous avez déjà essayé de payer la facture, vous pourriez perdre votre caution.';

  @override
  String get p2pTradeCancelBack => 'Retour';

  @override
  String get p2pTradeConfirmCancellation => 'Confirmer l\'annulation';

  @override
  String get p2pTradeCancelBondText =>
      'Si l\'ordre est annulé maintenant, vous perdrez votre caution';

  @override
  String get p2pTradeConfirmCancel => 'Confirmer l\'annulation';

  @override
  String get p2pTradeCancelMovedOn =>
      'L’ordre a avancé avant l’annulation : rien n’a été annulé.';

  @override
  String p2pTradeCancelNotDoneAfter(String reason) {
    return '$reason Rien n’a été annulé.';
  }

  @override
  String get p2pTradeCancelUnknown =>
      'Bull Market ne sait pas encore si l’annulation a abouti. Il continue de vérifier.';

  @override
  String get p2pTradeCancelNeedsRead =>
      'Attendez que l’ordre soit relu avant d’annuler.';

  @override
  String get p2pTradeCancelOnlyTogether =>
      'À cette étape, seule une annulation collaborative existe, que RoboSats propose depuis le chat.';

  @override
  String get p2pTradeCancelNotPossible =>
      'Vous ne pouvez pas annuler cet ordre';

  @override
  String p2pTradeTakePending(String coordinator) {
    return 'Bull Market ne sait pas encore si la prise de l’ordre a abouti. Il continue de vérifier auprès de $coordinator.';
  }

  @override
  String p2pTradeTakeNeverSent(String coordinator) {
    return 'Cette prise d’ordre n’a jamais été envoyée à $coordinator.';
  }

  @override
  String p2pTradeReadsFailing(String coordinator, String time) {
    return 'Impossible de joindre $coordinator. Ce qui est affiché a été lu à $time.';
  }

  @override
  String get p2pTradeRecordProblem =>
      'Bull Market n’a pas pu écrire les enregistrements de cet échange sur cet appareil.';

  @override
  String p2pTradeClosedProblem(String coordinator) {
    return 'Cet échange a été clôturé sur cet appareil, mais $coordinator indique que ce robot en est le preneur.';
  }

  @override
  String get p2pTradeUnrestorable =>
      'Bull Market ne peut pas lire les enregistrements de cet échange. Rien n’est envoyé.';

  @override
  String p2pTradeCoordinatorGone(String coordinator) {
    return '$coordinator ne figure plus dans la liste des coordinateurs. Rien n’est envoyé.';
  }

  @override
  String get p2pTradeUnavailable =>
      'Bull Market ne peut pas ouvrir cet échange pour l’instant. Rien n’est envoyé.';

  @override
  String get p2pTradeKeyMissing =>
      'La clé de garage de cet échange n’est pas sur cet appareil. Rien n’est envoyé.';

  @override
  String p2pTradeWarnRole(String coordinator) {
    return '$coordinator attribue à ce robot un autre rôle que celui qu’il a pris. Ne payez rien.';
  }

  @override
  String p2pTradeWarnOrder(String coordinator) {
    return '$coordinator a répondu à propos d’un autre ordre. Ne payez rien.';
  }

  @override
  String get p2pTradeWarnTerms =>
      'Les conditions de l’ordre ne sont pas celles de l’ordre pris.';

  @override
  String get p2pTradeWarnUnexpected =>
      'Changement inattendu du côté du coordinateur.';

  @override
  String p2pTradeWarnRegressed(String coordinator) {
    return '$coordinator a envoyé un statut qui ne suit pas cet échange. Il a été ignoré.';
  }

  @override
  String p2pTradeWarnInconsistent(String coordinator) {
    return '$coordinator s’est contredit plus tôt dans cet échange.';
  }

  @override
  String get p2pTradeWarnHistoryUnknown =>
      'Cet échange a été retrouvé sans son historique : ses factures ne peuvent pas être comparées aux premières.';

  @override
  String get p2pTradeWarnBond =>
      'La caution demandée n’est pas celle de l’ordre pris.';

  @override
  String get p2pTradeWarnPrice =>
      'Le montant de l’échange ne correspond pas au prix de l’ordre.';

  @override
  String p2pTradeWarnAmounts(String coordinator) {
    return 'Les montants donnés par $coordinator ne concordent pas.';
  }

  @override
  String p2pTradeWarnDeadline(String coordinator) {
    return '$coordinator a avancé l’échéance.';
  }

  @override
  String p2pTradeWarnUnreadable(String coordinator) {
    return 'La facture envoyée par $coordinator est illisible. Elle n’est pas affichée.';
  }

  @override
  String p2pTradeWarnWrongNetwork(String coordinator) {
    return 'La facture envoyée par $coordinator est pour un autre réseau. Elle n’est pas affichée.';
  }

  @override
  String get p2pTradeWarnInvoiceAmount =>
      'Le montant de la facture n’est pas celui que demande l’ordre.';

  @override
  String get p2pTradeWarnExpired => 'Cette facture a expiré.';

  @override
  String get p2pTradeWarnExpiringSoon =>
      'Cette facture expire dans moins d’une minute.';

  @override
  String p2pTradeWarnHashChanged(String coordinator) {
    return '$coordinator a envoyé une nouvelle facture pour la même étape. Ne la payez pas.';
  }

  @override
  String p2pTradeWarnPayee(String coordinator) {
    return 'Cette facture ne vient pas du nœud Lightning connu de $coordinator. Ne la payez pas.';
  }

  @override
  String p2pActiveOrder(String orderId) {
    return 'Ordre actif #$orderId';
  }

  @override
  String get p2pTradeEnded => 'Cet échange est terminé pour ce robot.';

  @override
  String get p2pSatsUnit => 'Sats';

  @override
  String get p2pTradeYouAreSwappingIn => 'SWAP VERS Lightning';

  @override
  String get p2pTradeYouAreSwappingOut => 'SWAP DEPUIS Lightning';

  @override
  String get p2pPayoutTabLightning => 'Lightning';

  @override
  String get p2pPayoutTabOnchain => 'Onchain';

  @override
  String get p2pPayoutAdvancedOptions => 'Options avancées';

  @override
  String get p2pPayoutRoutingBudget => 'Budget de routage';

  @override
  String get p2pPayoutBudgetTooHigh => 'Trop élevé ! (C’est plus de 1 %)';

  @override
  String get p2pPayoutUnitPpm => 'PPM';

  @override
  String p2pPayoutSubmitInvoiceFor(String amountSats) {
    return 'Soumettre la facture pour $amountSats sats';
  }

  @override
  String get p2pPayoutCopyAmount => 'Copier le montant';

  @override
  String get p2pPayoutInvoiceField => 'Facture de paiement Lightning';

  @override
  String get p2pPayoutSubmit => 'Soumettre';

  @override
  String get p2pPayoutSubmitWhileCancelling =>
      '« Soumettre » est désactivé pendant l’annulation de l’échange.';

  @override
  String get p2pPayoutInvalidInvoiceAmount => 'Montant de facture invalide';

  @override
  String get p2pPayoutOnchainIntro =>
      'Le coordinateur RoboSats fera un échange et enverra les Sats à votre adresse onchain.';

  @override
  String get p2pPayoutSwapFee => 'Frais d\'échange';

  @override
  String p2pPayoutSwapFeeValue(String sats, String percent) {
    return '$sats Sats ($percent %)';
  }

  @override
  String get p2pPayoutMiningFee => 'Frais de minage';

  @override
  String p2pPayoutMiningFeeValue(String sats, String rate) {
    return '$sats Sats ($rate Sats/vByte)';
  }

  @override
  String get p2pPayoutFinalAmount => 'Montant final que vous recevrez';

  @override
  String get p2pPayoutAddressField => 'Adresse Bitcoin';

  @override
  String get p2pPayoutMiningFeeField => 'Frais de minage';

  @override
  String get p2pPayoutInvalid => 'Invalide';

  @override
  String get p2pPayoutFailureReason => 'Raison de l\'échec :';

  @override
  String get p2pPayoutRetrying => 'Nouvelle tentative !';

  @override
  String get p2pPayoutNextAttempt => 'Prochaine tentative dans';

  @override
  String p2pPayoutCountdown(String minutes, String seconds) {
    return '$minutes min $seconds s';
  }

  @override
  String get p2pPayoutInvoiceExpiredSubmitNew =>
      'Votre facture a expiré ou plus de 3 tentatives de paiement ont été effectuées. Soumettez une nouvelle facture.';

  @override
  String get p2pPayoutWillRetry =>
      'RoboSats essaiera de payer votre facture 3 fois avec une pause d\'une minute entre chaque. Si cela continue d\'échouer, vous pourrez soumettre une nouvelle facture. Vérifiez si vous avez suffisamment de liquidités entrantes. Rappelez-vous que les nœuds lightning doivent être en ligne pour recevoir les paiements.';

  @override
  String get p2pPayoutFailureNotYet => 'Le paiement n’a pas (encore) échoué';

  @override
  String get p2pPayoutFailureTimeout =>
      'Il reste des routes à essayer, mais le délai du paiement est dépassé.';

  @override
  String get p2pPayoutFailureNoRoute =>
      'Toutes les routes possibles ont été essayées et ont échoué pour de bon, ou il n’y avait aucune route vers la destination.';

  @override
  String get p2pPayoutFailureNonRecoverable =>
      'Une erreur irrécupérable s’est produite.';

  @override
  String get p2pPayoutFailureIncorrect =>
      'Les détails du paiement sont incorrects (hash inconnu, montant invalide ou delta CLTV final invalide).';

  @override
  String get p2pPayoutFailureBalance =>
      'Solde déverrouillé insuffisant dans le nœud RoboSats.';

  @override
  String p2pPayoutFailureUnknown(String coordinator) {
    return '$coordinator a donné une raison que cette application ne connaît pas.';
  }

  @override
  String get p2pPayoutRefusedEmptyInvoice =>
      'Vous avez soumis une facture vide';

  @override
  String get p2pPayoutRefusedNotInvoice =>
      'Ne ressemble pas à une facture lightning valide';

  @override
  String get p2pPayoutRefusedRouteHints =>
      'Les routes privées indiquées par la facture ne sont pas payables avec le budget de routage soumis. Cela peut être ajusté en activant les options avancées.';

  @override
  String get p2pPayoutRefusedNoAmount =>
      'La facture fournie n’a pas de montant explicite';

  @override
  String p2pPayoutRefusedWrongAmount(String amount) {
    return 'La facture fournie n’est pas de $amount Sats';
  }

  @override
  String get p2pPayoutRefusedExpired => 'La facture fournie a déjà expiré';

  @override
  String get p2pPayoutRefusedNewInvoice =>
      'Vous devez soumettre une NOUVELLE facture';

  @override
  String get p2pPayoutRefusedNotNow =>
      'Vous ne pouvez soumettre une facture qu’après expiration ou 3 tentatives échouées';

  @override
  String get p2pPayoutRefusedAddressNotNow =>
      'Vous ne pouvez pas soumettre d’adresse maintenant.';

  @override
  String get p2pPayoutRefusedNotBuyer =>
      'Seul l’acheteur de cet ordre peut fournir une facture d’acheteur.';

  @override
  String get p2pPayoutRefusedSignature =>
      'Le message en clair signé PGP n’est pas valide.';

  @override
  String get p2pPayoutRefusedNotParticipant =>
      'Vous n’êtes pas participant à cet ordre';

  @override
  String get p2pPayoutRefusedEmptyAddress =>
      'Vous avez soumis une adresse vide';

  @override
  String p2pPayoutRefusedFeeTooLow(String rate) {
    return 'Les frais de minage sont trop bas. Ils doivent être supérieurs à $rate Sat/vbyte';
  }

  @override
  String get p2pPayoutRefusedFeeTooLowNoRate =>
      'Les frais de minage sont trop bas.';

  @override
  String get p2pPayoutRefusedFeeTooHigh =>
      'Les frais de minage sont trop élevés, ils doivent être inférieurs à 500 Sats/vbyte';

  @override
  String get p2pPayoutRefusedDust =>
      'Le montant restant après déduction des frais de minage est proche de la limite de poussière.';

  @override
  String get p2pPayoutRefusedInvalidAddress => 'Adresse invalide';

  @override
  String get p2pPayoutRefusedUnverifiable =>
      'Impossible de valider l’adresse, vérifiez le backend bitcoind';

  @override
  String p2pPayoutRefusedOther(String coordinator) {
    return '$coordinator a refusé vos informations de paiement.';
  }

  @override
  String p2pPayoutNotReached(String coordinator) {
    return 'Vos informations de paiement ne sont pas parvenues à $coordinator : rien n’a été enregistré. Vous pouvez les soumettre de nouveau.';
  }

  @override
  String get p2pPayoutNeedsARead =>
      'Attendez que l’ordre soit relu pour donner vos informations de paiement.';

  @override
  String p2pPayoutNotAsked(String coordinator) {
    return '$coordinator ne demande pas vos informations de paiement maintenant.';
  }

  @override
  String p2pPayoutAmountUnknown(String coordinator) {
    return '$coordinator ne donne pas encore le montant à recevoir.';
  }

  @override
  String get p2pPayoutInvoiceUnreadable =>
      'Ce n’est pas une facture Lightning que cette application sait lire.';

  @override
  String get p2pPayoutInvoiceOtherNetwork =>
      'Cette facture est pour un autre réseau que celui de l’échange.';

  @override
  String get p2pPayoutInvoiceWholeSats =>
      'La facture doit demander exactement les Sats indiqués, sans fraction de sat.';

  @override
  String get p2pPayoutAddressMalformed => 'Ce n’est pas une adresse Bitcoin.';

  @override
  String get p2pPayoutAddressBadChecksum =>
      'Cette adresse contient une faute de frappe : sa somme de contrôle est fausse.';

  @override
  String get p2pPayoutAddressOtherNetwork =>
      'Cette adresse est pour un autre réseau que celui de l’échange.';

  @override
  String p2pPayoutAddressUnsupported(String coordinator) {
    return '$coordinator ne pourra peut-être pas payer ce type d’adresse.';
  }

  @override
  String p2pPayoutWarnExpiresFirst(
    String date,
    String time,
    String coordinator,
  ) {
    return 'Cette facture expire le $date à $time. Si le vendeur confirme après, $coordinator ne pourra pas la payer et vous en demandera une nouvelle.';
  }

  @override
  String p2pPayoutWarnBelowMinimum(String coordinator) {
    return 'Moins de 20 000 Sats arriveraient à cette adresse : $coordinator la refusera.';
  }

  @override
  String get p2pPayoutOnchainSwapOrder =>
      'Un ordre en bitcoin est payé sur Lightning uniquement.';

  @override
  String p2pPayoutSwapBelowMinimum(String coordinator) {
    return 'Le montant est sous le plus petit échange que propose $coordinator.';
  }

  @override
  String p2pPayoutSwapAboveMaximum(String coordinator) {
    return 'Le montant dépasse le plus grand échange que propose $coordinator.';
  }

  @override
  String p2pPayoutSwapDisabled(String coordinator) {
    return '$coordinator ne propose pas d’échange.';
  }

  @override
  String p2pPayoutSwapNoLiquidity(String coordinator) {
    return '$coordinator n’a pas assez de fonds onchain pour un échange.';
  }

  @override
  String p2pPayoutSwapUnavailable(String coordinator) {
    return '$coordinator ne propose pas de paiement onchain pour cet ordre.';
  }

  @override
  String p2pPayoutStepUnlocking(String coordinator) {
    return 'Lecture de votre robot chez $coordinator et déverrouillage de sa clé. La première fois, cela prend quelques secondes.';
  }

  @override
  String p2pPayoutStepReading(String coordinator) {
    return 'Lecture de l’ordre chez $coordinator…';
  }

  @override
  String p2pPayoutStepSending(String coordinator) {
    return 'Envoi de vos informations de paiement à $coordinator…';
  }

  @override
  String p2pPayoutStepReadingAfter(String coordinator) {
    return 'Nouvelle lecture de l’ordre chez $coordinator…';
  }

  @override
  String get p2pPayoutStepWaitingForOrder =>
      'Attente de la fin d’une autre action sur cet ordre…';

  @override
  String get p2pPayoutStepOpening => 'Ouverture de l’échange…';

  @override
  String p2pPayoutGiven(String coordinator) {
    return '$coordinator a reçu vos informations de paiement.';
  }

  @override
  String p2pPayoutUnknown(String coordinator) {
    return 'Bull Market ne sait pas encore si $coordinator a reçu vos informations de paiement. L’application continue de vérifier tant que cet écran reste ouvert.';
  }

  @override
  String p2pPayoutAskedAgain(String coordinator) {
    return '$coordinator demande toujours vos informations de paiement : les dernières n’ont pas été enregistrées. Vous pouvez les soumettre de nouveau.';
  }

  @override
  String get p2pPayoutChanged =>
      'Rien n’a été envoyé : ce qui est affiché a changé depuis que vous l’avez vu. Vérifiez-le de nouveau avant de soumettre.';

  @override
  String get p2pPayoutChangedAmount =>
      'Rien n’a été envoyé : le montant a changé depuis son affichage. Vérifiez-le de nouveau avant de soumettre.';

  @override
  String get p2pPayoutChangedExpiry =>
      'Rien n’a été envoyé : cette facture expire désormais avant la fin possible de l’étape. Vérifiez-la de nouveau avant de soumettre.';

  @override
  String get p2pPayoutChangedStatus =>
      'Rien n’a été envoyé : le statut de l’échange a changé depuis son affichage. Vérifiez de nouveau avant de soumettre.';

  @override
  String p2pPayoutNotSentKey(String coordinator) {
    return 'La clé de votre robot n’a pas pu être lue chez $coordinator. Rien n’a été envoyé.';
  }

  @override
  String p2pPayoutNotSentRead(String coordinator) {
    return 'Impossible de lire l’ordre chez $coordinator. Rien n’a été envoyé.';
  }

  @override
  String get p2pPayoutNotSentSign =>
      'La clé de votre robot n’a pas pu signer ceci. Rien n’a été envoyé.';

  @override
  String get p2pPayoutNotSentTrade =>
      'Cet échange ne peut pas être ouvert maintenant. Rien n’a été envoyé.';

  @override
  String p2pPayBalance(String balance) {
    return 'Paiements instantanés : $balance sats disponibles';
  }

  @override
  String get p2pPayWithThisWallet => 'Payer avec ce portefeuille';

  @override
  String get p2pPayQuoting => 'Calcul des frais de swap…';

  @override
  String get p2pPayRowCollateral => 'Garantie';

  @override
  String get p2pPayRowBond => 'Caution';

  @override
  String get p2pPayRowFees => 'Frais de swap et de réseau';

  @override
  String p2pPayAmountSats(String amount) {
    return '$amount sats';
  }

  @override
  String get p2pPayRowSwapFees => 'Frais de swap';

  @override
  String get p2pPayRowNetworkFee => 'Frais de réseau (estimation)';

  @override
  String get p2pPayRowTotal => 'Total à payer';

  @override
  String get p2pPayRowLeft => 'Solde après paiement';

  @override
  String get p2pPayEscrowHeld =>
      'Jusqu’à la fin de l’échange, ces sats sont chez le service de swap, pas dans ce portefeuille. Si l’échange est annulé, ils reviennent sur Paiements instantanés, moins les frais de swap et de réseau, parfois avec du retard.';

  @override
  String p2pPayRateWallet(
    String price,
    String currency,
    String expected,
    String gap,
  ) {
    return 'Au prix du portefeuille Bull, $price $currency/BTC, avec la prime de l’ordre, cette caution vaut $expected sats. Écart de la facture : $gap.';
  }

  @override
  String p2pPayRateWalletEscrow(
    String price,
    String currency,
    String amount,
    String expected,
    String gap,
  ) {
    return 'Au prix du portefeuille Bull, $price $currency/BTC, avec la prime de l’ordre, $amount $currency valent $expected sats. Écart de la garantie : $gap, frais du coordinateur compris.';
  }

  @override
  String p2pPayRateDetail(
    String amount,
    String currency,
    String price,
    String expected,
    String gap,
  ) {
    return 'Bull Wallet refait le calcul avec son propre prix : $amount $currency à $price $currency/BTC, prime comprise, font $expected sats. Le coordinateur demande $gap de plus, ses frais compris.';
  }

  @override
  String p2pPayAgainstFigures(String expected, String asked) {
    return 'Bull Wallet attendait $expected sats, le coordinateur en demande $asked.';
  }

  @override
  String p2pPayAgainstDetail(String price, String currency, String threshold) {
    return 'Bull Wallet refait le calcul avec son propre prix ($price $currency/BTC, prime comprise) et vous prévient au-delà de $threshold d’écart. Vérifiez l’ordre avant de payer.';
  }

  @override
  String get p2pPayUnverifiedDetail =>
      'Sans ce prix, il ne peut pas comparer le montant du coordinateur. Vous pouvez réessayer, ou payer sans cette vérification.';

  @override
  String get p2pPayEarlierNotBack =>
      'Une garantie précédente n’est pas revenue';

  @override
  String p2pPayEarlierOutTotal(String total) {
    return 'Avec celle-ci, $total sats seront hors de ce portefeuille.';
  }

  @override
  String p2pPayEarlierNotBackDetail(String sats) {
    return 'Vous avez déjà payé, ou tenté de payer, une garantie de $sats sats pour cet ordre avec ce portefeuille. Elle n’y est pas encore revenue.';
  }

  @override
  String get p2pPayNewContractTitle => 'Nouveau contrat';

  @override
  String get p2pPayNewContractLine =>
      'La prise précédente de cet ordre n’a pas abouti. Cette garantie vaut pour le nouveau contrat.';

  @override
  String get p2pPayConfirmAgainTitle => 'Les montants ont changé';

  @override
  String get p2pPayConfirmAgainLine =>
      'Vérifiez-les, puis confirmez à nouveau.';

  @override
  String get p2pPayConfirmStaleTitle => 'L’ordre a été repris entre-temps';

  @override
  String get p2pPayConfirmStaleLine =>
      'Cette confirmation n’est plus valable. Revenez en arrière.';

  @override
  String p2pPayConfirm(String total) {
    return 'Payer $total sats';
  }

  @override
  String get p2pPaySending => 'Envoi du paiement…';

  @override
  String p2pPaySent(String coordinator) {
    return 'Paiement envoyé. En attente du blocage de la caution chez $coordinator.';
  }

  @override
  String p2pPayEscrowSent(String coordinator) {
    return 'Paiement envoyé. En attente du blocage de la garantie chez $coordinator.';
  }

  @override
  String get p2pPayRefundPending =>
      'Le swap sera remboursé sous peu. Les frais de swap ne sont pas remboursés.';

  @override
  String get p2pPayRefunded =>
      'Le swap a été remboursé. Les frais de swap ne sont pas remboursés.';

  @override
  String p2pPaySettled(String coordinator) {
    return 'Votre caution a été conservée par $coordinator.';
  }

  @override
  String p2pPayEscrowSettled(String coordinator) {
    return '$coordinator a reçu la garantie.';
  }

  @override
  String get p2pPayUnderReview =>
      'Le swap est en cours de vérification. Contactez le support de Bull Bitcoin si cela dure.';

  @override
  String get p2pPayInterrupted =>
      'Le paiement a été interrompu avant l’envoi. Rien n’est encore sorti de ce portefeuille.';

  @override
  String get p2pPayMaybeSent =>
      'Le paiement a peut-être été envoyé. Son état sera mis à jour sous peu.';

  @override
  String get p2pPayAskSupport =>
      'Swap échoué. Les sats de cette caution sont peut-être sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayEscrowAskSupport =>
      'Swap échoué. Les sats de cette garantie sont peut-être sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String p2pPayUnderMinimum(String min) {
    return 'Montant inférieur à la limite de swap minimale : $min sats';
  }

  @override
  String get p2pPayUnderMinimumUnknown =>
      'Le montant est inférieur aux limites de swap';

  @override
  String p2pPayOverMaximum(String max) {
    return 'Montant supérieur à la limite de swap maximale : $max sats';
  }

  @override
  String get p2pPayOutsideLimits => 'Le montant est hors des limites de swap';

  @override
  String p2pPayNotEnough(String balance, String total) {
    return 'Pas assez dans Paiements instantanés ($balance sats) pour $total sats.';
  }

  @override
  String get p2pPayUnreachable =>
      'Serveur de swap indisponible. Veuillez réessayer plus tard.';

  @override
  String get p2pPayBusy => 'Trop de demandes. Veuillez réessayer plus tard.';

  @override
  String get p2pPayTooLate =>
      'Il reste trop peu de temps pour payer depuis ce portefeuille.';

  @override
  String get p2pPayFeesChanged =>
      'Les frais ont changé depuis votre confirmation. Vérifiez-les à nouveau.';

  @override
  String get p2pPayAlreadyPaid => 'Ce portefeuille a déjà payé cette facture.';

  @override
  String get p2pPayOrderMoved =>
      'L’ordre a changé avant le paiement. Rien n’a été payé.';

  @override
  String get p2pPayNotRecorded =>
      'Bull Market n’a pas pu écrire ses enregistrements sur cet appareil. Rien n’a été payé.';

  @override
  String get p2pPayWalletUnavailable =>
      'Ce portefeuille ne peut pas payer cette caution maintenant.';

  @override
  String get p2pPayEscrowShownBefore =>
      'Cette facture de garantie a déjà été présentée à cet appareil, pour cet ordre ou pour un autre. Elle n’est pas payée depuis ce portefeuille.';

  @override
  String get p2pPayConfirmAgain =>
      'Depuis votre confirmation, ce qui sortira de ce portefeuille, ou l’état d’une garantie précédente, a changé. Rien n’a été payé : vérifiez les chiffres ci-dessous et confirmez de nouveau.';

  @override
  String get p2pPayContractMoved =>
      'L’ordre a été repris avant le paiement : la confirmation valait pour la prise précédente. Rien n’a été payé.';

  @override
  String p2pEscrowEarlierOut(String sats, String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count garanties précédentes de cet ordre, payées ou tentées avec ce portefeuille, ne sont pas encore revenues',
      one:
          'Une garantie précédente de cet ordre, payée ou tentée avec ce portefeuille, n’est pas encore revenue',
    );
    return '$_temp0 : $sats sats. Avec celle-ci, $total sats seront hors de ce portefeuille pour les garanties de cet ordre, caution non comprise.';
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
          '$known garanties précédentes de cet ordre, payées ou tentées avec ce portefeuille, ne sont pas encore revenues : $sats sats',
      one:
          'Une garantie précédente de cet ordre, payée ou tentée avec ce portefeuille, n’est pas encore revenue : $sats sats',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count autres dont cet appareil ne connaît plus les montants',
      one: 'une autre dont cet appareil ne connaît plus le montant',
    );
    return '$_temp0, et $_temp1. Avec celle-ci, au moins $total sats seront hors de ce portefeuille pour les garanties de cet ordre, caution non comprise.';
  }

  @override
  String p2pEscrowEarlierOutAllUnknown(String total, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count garanties précédentes de cet ordre, payées ou tentées avec ce portefeuille, ne sont pas encore revenues ; cet appareil ne connaît plus leurs montants.',
      one:
          'Une garantie précédente de cet ordre, payée ou tentée avec ce portefeuille, n’est pas encore revenue ; cet appareil ne connaît plus son montant.',
    );
    return '$_temp0 Avec celle-ci, au moins $total sats seront hors de ce portefeuille pour les garanties de cet ordre, caution non comprise.';
  }

  @override
  String p2pEscrowEarlierKept(String sats, String coordinator) {
    return 'La garantie d’une prise précédente ($sats sats) a été encaissée par $coordinator : vérifiez cet ordre dans l’application officielle RoboSats avant d’en payer une autre.';
  }

  @override
  String p2pEscrowEarlierKeptUnknown(String coordinator) {
    return 'La garantie d’une prise précédente a été encaissée par $coordinator : vérifiez cet ordre dans l’application officielle RoboSats avant d’en payer une autre.';
  }

  @override
  String get p2pPayEscrowBondHeldToo =>
      'La caution de votre ordre a été payée avec ce portefeuille : elle est aussi hors de ce portefeuille jusqu’à la fin de l’ordre, et n’est pas dans ce total.';

  @override
  String get p2pPayEscrowBondMaybeHeldToo =>
      'Si la caution de votre ordre a été payée avec ce portefeuille, elle est aussi hors de ce portefeuille jusqu’à la fin de l’ordre, et n’est pas dans ce total.';

  @override
  String get p2pEscrowsEarlierTitle =>
      'Garanties des prises précédentes de cet ordre, payées ou tentées avec ce portefeuille :';

  @override
  String p2pEscrowsEarlierLine(String take, String state) {
    return 'Prise $take : $state';
  }

  @override
  String get p2pEscrowStateRefunded =>
      'revenue, remboursée sur ce portefeuille sans les frais de swap ni les frais de réseau';

  @override
  String get p2pEscrowStateNothingSent =>
      'revenue, rien n’est sorti de ce portefeuille';

  @override
  String get p2pEscrowStateRefundPending =>
      'pas encore revenue, le service de swap la rembourse';

  @override
  String get p2pEscrowStatePreparing =>
      'pas encore revenue, son swap était en préparation et n’a peut-être jamais été envoyé';

  @override
  String get p2pEscrowStateMaybeSent =>
      'pas encore revenue, le paiement a peut-être été envoyé';

  @override
  String get p2pEscrowStateWithService =>
      'pas encore revenue, chez le service de swap';

  @override
  String get p2pEscrowStateUnderReview =>
      'pas encore revenue, en vérification au service de swap ; contactez le support de Bull Bitcoin si cela dure';

  @override
  String get p2pEscrowStateAskSupport =>
      'pas encore revenue, le swap a échoué et ses sats sont peut-être sortis de ce portefeuille ; contactez le support de Bull Bitcoin';

  @override
  String get p2pEscrowStateUnknown =>
      'état inconnu, cet appareil ne peut pas dire où elle en est';

  @override
  String p2pEscrowStateHeld(String coordinator) {
    return 'pas encore revenue, payée par le service de swap et retenue par $coordinator';
  }

  @override
  String p2pEscrowStateKept(String coordinator) {
    return 'encaissée par $coordinator';
  }

  @override
  String p2pEscrowRefundUndoneHeld(String take, String coordinator) {
    return 'La garantie de la prise $take était en cours de remboursement, et elle est de nouveau retenue par $coordinator : vérifiez cet ordre dans l’application officielle RoboSats.';
  }

  @override
  String p2pEscrowRefundUndoneKept(String take, String coordinator) {
    return 'La garantie de la prise $take était en cours de remboursement, puis elle a été encaissée par $coordinator : vérifiez cet ordre dans l’application officielle RoboSats.';
  }

  @override
  String get p2pPayEscrowWalletUnavailable =>
      'Ce portefeuille ne peut pas payer cette garantie maintenant.';

  @override
  String get p2pPayServiceCouldNotPay =>
      'Swap échoué. Le swap sera remboursé sous peu. Les frais de swap ne sont pas remboursés.';

  @override
  String get p2pPayWithSwapService => 'Votre swap est en cours.';

  @override
  String p2pPayCoordinatorUnreachable(String coordinator) {
    return 'Impossible de joindre $coordinator. Rien n’a été payé.';
  }

  @override
  String p2pPayReadSuperseded(String coordinator) {
    return 'Impossible de lire l’ordre chez $coordinator pour l’instant. Rien n’a été payé.';
  }

  @override
  String get p2pPayStillSending =>
      'Envoi toujours en cours. Cela peut prendre quelques minutes.';

  @override
  String get p2pPayAskSupportSent =>
      'Swap échoué. Les sats de cette caution sont sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayEscrowAskSupportSent =>
      'Swap échoué. Les sats de cette garantie sont sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayUnreadable =>
      'Bull Market ne peut pas lire où en est ce paiement.';

  @override
  String get p2pPayCancelNote =>
      'Un paiement de cette caution est en route depuis ce portefeuille. Annuler maintenant coûte les frais de swap, et le remboursement peut tarder.';

  @override
  String get p2pPayEscrowCancelNote =>
      'Un paiement de cette garantie est en route depuis ce portefeuille. Annuler ne l’arrête pas : s’il arrive chez le coordinateur, celui-ci le rend, puis le service de swap le rembourse vers Paiements instantanés sans les frais de swap ni les frais de réseau. Le remboursement peut tarder.';

  @override
  String p2pPayLineBond(String line) {
    return 'Caution : $line';
  }

  @override
  String p2pPayLineEscrow(String line) {
    return 'Garantie : $line';
  }

  @override
  String get p2pPayServiceRefunded =>
      'Swap échoué. Le swap a été remboursé. Les frais de swap ne sont pas remboursés.';

  @override
  String get p2pPayAskSupportExpired =>
      'Swap expiré. Les sats de cette caution sont peut-être sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayEscrowAskSupportExpired =>
      'Swap expiré. Les sats de cette garantie sont peut-être sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayAskSupportExpiredSent =>
      'Swap expiré. Les sats de cette caution sont sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayEscrowAskSupportExpiredSent =>
      'Swap expiré. Les sats de cette garantie sont sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pEndChatBuyerHi =>
      'Dites bonjour ! Demandez les détails du paiement et appuyez sur « Confirmer l\'envoi » dès que le paiement est envoyé.';

  @override
  String p2pEndChatSellerHi(String amount, String currencyCode) {
    return 'Dites bonjour! Soyez serviable et concis. Faites-leur savoir comment vous envoyer les $amount $currencyCode.';
  }

  @override
  String get p2pEndBewareScams => '⚠️ Attention aux arnaques';

  @override
  String p2pEndConfirmSent(String amount, String currencyCode) {
    return 'Confirmer l\'envoi de $amount $currencyCode';
  }

  @override
  String p2pEndConfirmReceived(String amount, String currencyCode) {
    return 'Confirmer la réception de $amount $currencyCode';
  }

  @override
  String p2pEndConfirmSentTitle(String amount, String currencyCode) {
    return '✅ Confirmez-vous avoir envoyé $amount $currencyCode ?';
  }

  @override
  String p2pEndConfirmReceivedTitle(String amount, String currencyCode) {
    return '✅ Confirmez-vous avoir reçu $amount $currencyCode?';
  }

  @override
  String get p2pEndConfirmSentText =>
      'Confirmer permettra à votre pair de finaliser la transaction.';

  @override
  String get p2pEndConfirmReceivedText =>
      'Confirmer finalisera la transaction.';

  @override
  String get p2pEndEscrowReleased =>
      'Les satoshis dans le séquestre seront libérés à l\'acheteur :';

  @override
  String p2pEndOnlyConfirmAfter(String amount, String currencyCode) {
    return 'Confirmez seulement après que $amount $currencyCode soient arrivés sur votre compte.';
  }

  @override
  String get p2pEndNotConfirmingRisk =>
      'Si vous avez reçu le paiement et que vous ne cliquez pas sur confirmer, vous risquez de perdre votre caution.';

  @override
  String get p2pEndFiatReversal =>
      'Certains modes de paiement en fiat peuvent inverser leurs transactions jusqu\'à 80 jours après leur finalisation. Veuillez conserver ce jeton et les données de votre commande au cas où vous auriez besoin de les utiliser comme preuve.';

  @override
  String get p2pEndCannotBeUndone =>
      '⚠️ Cette action ne peut pas être annulée !';

  @override
  String get p2pEndFalseConfirmRisk =>
      'Si vous ne l\'avez pas encore envoyé et que vous continuez à confirmer faussement, vous risquez de perdre votre caution.';

  @override
  String get p2pEndConfirm => 'Confirmer';

  @override
  String get p2pEndWaitSeller =>
      'Attendez que le vendeur confirme avoir reçu le paiement.';

  @override
  String get p2pEndBuyerSentFiat =>
      'L\'acheteur a envoyé la monnaie fiat. Appuyez sur « Confirmer la réception » une fois que vous l\'avez reçue.';

  @override
  String p2pEndStepSending(String coordinator) {
    return 'Envoi de votre confirmation à $coordinator…';
  }

  @override
  String get p2pEndNeedsRead => 'Attendez que l’ordre soit relu.';

  @override
  String get p2pEndMovedOn =>
      'L’ordre a changé : votre confirmation n’a pas été envoyée.';

  @override
  String p2pEndReadFailed(String coordinator) {
    return 'L’ordre n’a pas pu être relu chez $coordinator : votre confirmation n’a pas été envoyée.';
  }

  @override
  String p2pEndNotDoneAfter(String reason) {
    return '$reason Votre confirmation n’a pas été envoyée.';
  }

  @override
  String get p2pEndUnknown =>
      'Bull Market ne sait pas encore si votre confirmation est passée et continue de vérifier.';

  @override
  String get p2pEndUnknownReceived =>
      'Bull Market ne sait pas encore si votre confirmation est passée. L\'application continue de lire l\'ordre ; si l\'échange ne se termine pas, confirmez de nouveau : une seconde confirmation ne peut pas libérer plus que l\'unique séquestre.';

  @override
  String get p2pEndSendingSats =>
      'RoboSats tente de payer votre facture lightning. Rappelez-vous que les nœuds lightning doivent être en ligne pour recevoir les paiements.';

  @override
  String get p2pEndTakingTooLong => 'Trop long ?';

  @override
  String get p2pEndTakingTooLongText =>
      'Les paiements Lightning sont généralement instantanés, mais parfois un nœud sur la route peut être inactif, ce qui peut entraîner un délai pouvant atteindre 24 heures pour que votre paiement arrive dans votre portefeuille.';

  @override
  String get p2pEndNeedsReadNotSent =>
      'Attendez que l’ordre soit relu. Votre confirmation n’a pas été envoyée.';

  @override
  String p2pEndRefusedBy(String coordinator) {
    return '$coordinator n’a pas enregistré votre confirmation.';
  }

  @override
  String p2pEndNotRecordedMovedOn(String coordinator) {
    return 'L’ordre a changé : $coordinator n’a pas enregistré votre confirmation.';
  }

  @override
  String p2pEndAmountDiffers(
    String coordinator,
    String readAmount,
    String readCurrency,
    String amount,
    String currencyCode,
  ) {
    return '$coordinator indique maintenant $readAmount $readCurrency ; l’ordre a été pris pour $amount $currencyCode.';
  }

  @override
  String p2pEndAmountMissing(
    String coordinator,
    String amount,
    String currencyCode,
  ) {
    return '$coordinator n’indique aucun montant pour cet ordre ; il a été pris pour $amount $currencyCode.';
  }

  @override
  String get p2pEndPaymentFailed => 'Paiement échoué ?';

  @override
  String get p2pEndUndoTitle => 'Annuler la confirmation de l\'envoi fiat ?';

  @override
  String get p2pEndUndoText =>
      'LISEZ. Si votre paiement au vendeur a été bloqué et qu\'il est absolument impossible de terminer la transaction, vous pouvez annuler votre confirmation de « Fiat envoyé ». Ne le faites que si vous et le vendeur avez DÉJÀ CONVENU dans le chat de procéder à une annulation collaborative. Après avoir confirmé, le bouton « Annulation collaborative » sera à nouveau visible. Ne cliquez sur ce bouton que si vous savez ce que vous faites. Les utilisateurs débutants de RoboSats sont fortement découragés de réaliser cette action ! Assurez-vous à 100 % que votre paiement a échoué et que le montant est dans votre compte.';

  @override
  String p2pEndWaitCountdown(String time) {
    return 'Attendez ($time)';
  }

  @override
  String get p2pEndCollabTitle => 'Annulation collaborative de l\'ordre ?';

  @override
  String get p2pEndCollabText =>
      'Le séquestre commercial a été publié. L\'ordre ne peut être annulé que si le créateur et le preneur sont d\'accord pour annuler.';

  @override
  String get p2pEndCollabPeerAsked => 'Votre pair a demandé l\'annulation';

  @override
  String get p2pEndCollabAccept => 'Accepter l\'annulation';

  @override
  String get p2pEndCollabAsk => 'Demande d\'annulation';

  @override
  String p2pEndCollabPeerAlert(String nickname) {
    return '$nickname demande une annulation collaborative';
  }

  @override
  String get p2pEndCollabAskedAlert =>
      'Vous avez demandé une annulation collaborative';

  @override
  String get p2pEndOrderOptions => 'Options de l’ordre';

  @override
  String get p2pEndCollabCancel => 'Annulation collaborative';

  @override
  String get p2pEndCollabAfterFiat =>
      'Les ordres ne peuvent pas être annulés si le fiat a été envoyé.';

  @override
  String p2pEndStepSendingRequest(String coordinator) {
    return 'Envoi de votre demande à $coordinator…';
  }

  @override
  String get p2pEndNotSentReadRefused =>
      'Rien n’a été envoyé : l’ordre relu à l’instant porte l’alerte affichée ci-dessus.';

  @override
  String get p2pEndNotSent => 'Rien n’a été envoyé.';

  @override
  String get p2pEndTradeMovedOn =>
      'L’échange a changé : votre demande n’a pas été envoyée.';

  @override
  String get p2pEndUnknownRequest =>
      'Bull Market ne sait pas encore si votre demande est passée et continue de vérifier.';

  @override
  String p2pEndRequestNotRecordedMovedOn(String coordinator) {
    return 'L’échange a changé : $coordinator n’a pas enregistré votre demande.';
  }

  @override
  String p2pEndRequestRefusedBy(String coordinator) {
    return '$coordinator n’a pas enregistré votre demande.';
  }

  @override
  String p2pEndRequestNotDoneAfter(String reason) {
    return '$reason Votre demande n’a pas été envoyée.';
  }

  @override
  String p2pEndOffline(String coordinator) {
    return '$coordinator est hors ligne : votre confirmation n’a pas été envoyée.';
  }

  @override
  String p2pEndRequestOffline(String coordinator) {
    return '$coordinator est hors ligne : votre demande n’a pas été envoyée.';
  }

  @override
  String get p2pEndOpenOptions => 'ouvrir les options';

  @override
  String p2pEndWaitSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Attendez $seconds secondes',
      one: 'Attendez 1 seconde',
    );
    return '$_temp0';
  }

  @override
  String p2pChatYouState(String state) {
    return 'Vous : $state';
  }

  @override
  String p2pChatPeerState(String state) {
    return 'Pair : $state';
  }

  @override
  String get p2pChatConnected => 'connecté';

  @override
  String get p2pChatDisconnected => 'déconnecté';

  @override
  String get p2pChatWaitingShort => '...attente';

  @override
  String get p2pChatTypeMessage => 'Écrivez un message';

  @override
  String get p2pChatWaitingForPeer => 'En attente du pair...';

  @override
  String get p2pChatSend => 'Envoyer';

  @override
  String p2pChatSignatureVerified(String nickname) {
    return 'Signature vérifiée de $nickname';
  }

  @override
  String p2pChatSignatureUnverified(String nickname) {
    return 'Impossible de vérifier la signature de $nickname';
  }

  @override
  String get p2pChatTokenBlocked =>
      'Aïe ! Vous venez d’envoyer le jeton de votre robot à votre pair dans le chat, c’est une idée catastrophique ! Tellement grave que votre message a été bloqué.';

  @override
  String get p2pChatGarageKeyBlocked =>
      'Ce message contient votre clé de garage, qui contrôle tous vos robots. Il ne sera pas envoyé.';

  @override
  String get p2pChatTooLong =>
      'Ce message est trop long. Raccourcissez-le pour l’envoyer.';

  @override
  String get p2pChatClosed => 'Les messages ne sont pas envoyés à cette étape.';

  @override
  String get p2pChatKeyChanged =>
      'Ce chat n’est plus sûr : la clé de votre pair a changé. Plus rien n’est envoyé ici. Ne vous fiez pas aux coordonnées de paiement reçues à partir de maintenant.';

  @override
  String p2pChatSending(String coordinator) {
    return 'Envoi du message à $coordinator…';
  }

  @override
  String p2pChatNotConfirmed(String coordinator) {
    return 'Non confirmé par $coordinator. Il peut encore parvenir à votre pair.';
  }

  @override
  String get p2pChatSendAgain => 'Renvoyer';

  @override
  String get p2pChatSendFailed => 'Le message n’a pas été envoyé. Réessayez.';

  @override
  String p2pChatSendRefused(String coordinator) {
    return '$coordinator n’a pas accepté le message. Réessayez.';
  }

  @override
  String get p2pChatTradeMoved =>
      'Le message n’a pas été envoyé : l’échange a avancé.';

  @override
  String p2pChatReadFailed(String coordinator) {
    return 'Impossible de lire le chat chez $coordinator. Nouvel essai…';
  }

  @override
  String get p2pChatUnavailable =>
      'Le chat ne peut pas être lu sur cet appareil.';

  @override
  String get p2pChatHistoryTooLarge =>
      'Ce chat est trop long pour être lu depuis son premier message.';

  @override
  String get p2pChatReadNewer => 'Lire seulement les messages récents';

  @override
  String p2pChatReading(String coordinator) {
    return 'Lecture du chat chez $coordinator…';
  }

  @override
  String get p2pChatSkipAwaited => 'Lecture des messages plus récents…';

  @override
  String get p2pChatEarlierHidden =>
      'Les messages précédents ne sont pas affichés.';

  @override
  String get p2pChatScreenPrivacyUnavailable =>
      'La protection de l’écran n’a pas pu être activée : le chat reste masqué.';

  @override
  String get p2pChatUnreadable => 'Ce message ne peut pas être lu.';

  @override
  String get p2pChatMarkAfterGap =>
      'Un message manque peut-être avant celui-ci.';

  @override
  String get p2pChatMarkRepeat => 'Ce message a déjà été affiché plus haut.';

  @override
  String get p2pChatMarkSentTwice => 'Vous avez envoyé ce message deux fois.';

  @override
  String get p2pChatMarkOutOfOrder =>
      'Ce message est peut-être plus ancien qu’il n’y paraît.';

  @override
  String get p2pChatAuditChat => 'Auditer le chat';

  @override
  String get p2pChatExport => 'Exporter';

  @override
  String get p2pChatExportCopyFailed =>
      'Le journal du chat n’a pas pu être copié.';

  @override
  String get p2pChatAuditTitle => 'Ne faites pas confiance, vérifiez';

  @override
  String get p2pChatAuditText =>
      'Votre communication est chiffrée de bout en bout avec OpenPGP. Vous pouvez vérifier la confidentialité de ce chat en utilisant n’importe quel outil basé sur la norme OpenPGP.';

  @override
  String get p2pChatYourPublicKey => 'Votre clé publique';

  @override
  String get p2pChatYourPublicKeyTooltip =>
      'Votre clé publique PGP. Votre correspondant l’utilise pour crypter les messages que vous êtes le seul à pouvoir lire.';

  @override
  String get p2pChatPeerPublicKey => 'Clé publique du correspondant';

  @override
  String get p2pChatPeerPublicKeyTooltip =>
      'La clé publique PGP de votre correspondant. Vous l’utilisez pour chiffrer les messages que lui seul peut lire et pour vérifier que votre correspondant a signé les messages entrants.';

  @override
  String get p2pChatYourEncryptedPrivateKey => 'Votre clé privée chiffrée';

  @override
  String get p2pChatYourEncryptedPrivateKeyTooltip =>
      'Votre clé privée chiffrée. Vous l’utilisez pour déchiffrer les messages que votre correspondant a chiffrés pour vous. Vous l’utilisez également pour signer les messages que vous envoyez.';

  @override
  String get p2pChatPassphrase =>
      'Phrase de passe de votre clé privée (à conserver précieusement !)';

  @override
  String get p2pChatPassphraseTooltip =>
      'La phrase de passe pour décrypter votre clé privée. Vous êtes le seul à la connaître ! Ne la partagez pas. C’est aussi votre jeton du robot.';

  @override
  String p2pChatAuditKeyFailed(String coordinator) {
    return 'La clé de votre robot n’a pas pu être lue chez $coordinator.';
  }

  @override
  String p2pChatFingerprint(String fingerprint) {
    return 'Empreinte : $fingerprint';
  }

  @override
  String get p2pChatSaveKeys => 'Clés';

  @override
  String get p2pChatSaveKeysTooltip =>
      'Enregistrer les accès dans un fichier JSON';

  @override
  String get p2pChatSaveMessages => 'Messages';

  @override
  String get p2pChatSaveMessagesTooltip =>
      'Enregistrer les messages dans un fichier JSON';

  @override
  String get p2pPayoutWalletGenerateInvoice => 'Générer une facture';

  @override
  String get p2pPayoutWalletGenerateAddress => 'Générer une nouvelle adresse';

  @override
  String get p2pPayoutWalletMakingInvoice => 'Création de la facture…';

  @override
  String get p2pPayoutWalletMakingAddress => 'Création d’une nouvelle adresse…';

  @override
  String get p2pPayoutWalletStillWaiting =>
      'Toujours en attente du portefeuille.';

  @override
  String get p2pPayoutWalletNoInvoice =>
      'Ce portefeuille ne peut pas créer de facture pour le moment.';

  @override
  String get p2pPayoutWalletNoAddress =>
      'Ce portefeuille ne peut pas donner d’adresse pour le moment.';

  @override
  String get p2pPayoutWalletAnotherWaiting =>
      'Ce portefeuille attend déjà un paiement de ce montant. Collez une facture d’un autre portefeuille, ou réessayez plus tard.';

  @override
  String get p2pPayoutWalletEarlierStillOpen =>
      'La facture précédente de ce portefeuille pour cet échange est encore ouverte, et le coordinateur n’en accepte qu’une nouvelle. Collez une facture d’un autre portefeuille, ou réessayez une fois qu’elle aura expiré.';

  @override
  String get p2pEndOpenDispute => 'Ouvrir un litige';

  @override
  String p2pEndDisputeWait(String hours, String minutes) {
    return 'Pour ouvrir un litige, vous devez attendre ${hours}h ${minutes}m';
  }

  @override
  String get p2pEndDisputeTitle => 'Voulez-vous ouvrir un litige ?';

  @override
  String get p2pEndDisputeText =>
      'Le personnel de RoboSats examinera les déclarations et les preuves fournies. Vous devez constituer un dossier complet, car le personnel ne peut pas lire le chat. Il est préférable de fournir une méthode de contact temporaire avec votre déclaration. Les satoshis dans le séquestre commercial seront envoyés au gagnant du litige, tandis que le perdant du litige perdra la caution.';

  @override
  String get p2pEndDisputeExport =>
      'Assurez-vous d\'EXPORTER le journal du chat. Le personnel pourrait demander votre journal de chat exporté en JSON pour résoudre les divergences. Il est de votre responsabilité de le stocker.';

  @override
  String get p2pEndDisagree => 'Être en désaccord';

  @override
  String get p2pEndAgreeDispute => 'Accepter et ouvrir un litige';

  @override
  String p2pEndStepSendingDispute(String coordinator) {
    return 'Ouverture du litige chez $coordinator…';
  }

  @override
  String get p2pEndDisputeWaitPeer =>
      'Nous attendons la déclaration de votre contrepartie commerciale. Si vous hésitez sur l\'état du litige ou si vous souhaitez ajouter plus d\'informations, contactez votre coordinateur de commande (l\'hôte) via l\'une de leurs méthodes de contact.';

  @override
  String get p2pEndDisputeSaveInfoPeer =>
      'Veuillez sauvegarder les informations nécessaires pour identifier votre commande et vos paiements : ID de l\'ordre ; hachages de paiement des cautions ou des comptes (vérifiez sur votre portefeuille lightning) ; montant exact de satoshis ; et surnom du robot. Vous devrez vous identifier en utilisant ces informations si vous contactez votre coordinateur de transaction.';

  @override
  String get p2pEndDisputeWaitResolution =>
      'Les deux déclarations ont été reçues, attendez que le personnel résolve le litige. Si vous hésitez sur l\'état du litige ou si vous souhaitez ajouter plus d\'informations, contactez votre coordinateur de commande (l\'hôte) via l\'une de leurs méthodes de contact. Si vous n\'avez pas fourni de méthode de contact, ou si vous n\'êtes pas sûr de l\'avoir bien rédigé, écrivez à votre coordinateur immédiatement.';

  @override
  String get p2pEndDisputeSaveInfoResolution =>
      'Veuillez enregistrer les informations nécessaires pour identifier votre commande et vos paiements : ID de l\'ordre ; hachages de paiement des cautions ou des comptes (vérifiez sur votre portefeuille lightning) ; montant exact de satoshis ; et surnom du robot. Vous devrez vous identifier en tant qu\'utilisateur impliqué dans cette transaction par e-mail (ou autres méthodes de contact).';

  @override
  String p2pEndDisputeWinner(String email) {
    return 'Vous pouvez réclamer le montant de résolution du litige (compte séquestre et caution de fidélité) à partir des récompenses de votre profil. Si le personnel peut vous aider en quoi que ce soit, n\'hésitez pas à contacter $email (ou via la méthode de contact temporaire que vous avez fournie).';
  }

  @override
  String p2pEndDisputeLoser(String email) {
    return 'Malheureusement, vous avez perdu le litige. Si vous pensez que c\'est une erreur, vous pouvez demander à rouvrir le cas en contactant votre coordinateur. Si vous pensez que votre coordinateur a été injuste, veuillez déposer une réclamation par e-mail à $email';
  }

  @override
  String p2pEndStatementLater(String coordinator) {
    return 'Bull Market ne peut pas encore envoyer de déclaration de litige. Contactez $coordinator par l’un de ses contacts ci-dessous, avec les informations qui identifient votre ordre.';
  }

  @override
  String p2pEndRewardsLater(String coordinator) {
    return 'Bull Market ne peut pas encore réclamer de récompenses : contactez $coordinator par l’un de ses contacts ci-dessous.';
  }

  @override
  String p2pEndStatementLaterNoContacts(String coordinator) {
    return 'Bull Market ne peut pas encore envoyer de déclaration de litige. Contactez $coordinator avec les informations qui identifient votre ordre.';
  }

  @override
  String p2pEndRewardsLaterNoContacts(String coordinator) {
    return 'Bull Market ne peut pas encore réclamer de récompenses : contactez $coordinator.';
  }

  @override
  String p2pEndOrderId(String id) {
    return 'ID de l’ordre : $id';
  }

  @override
  String get p2pEndDisputeTooEarly =>
      'Impossible d’ouvrir un litige pour l’instant. Vous devez attendre jusqu’à 18 heures avant l’expiration.';

  @override
  String get p2pEndDisputeNeedsRead =>
      'Attendez que l’ordre soit relu. Le litige n’a pas été ouvert.';

  @override
  String p2pEndDisputeReadFailed(String coordinator) {
    return 'L’ordre n’a pas pu être relu chez $coordinator : le litige n’a pas été ouvert.';
  }

  @override
  String get p2pEndDisputeMovedOn =>
      'L’échange a changé : le litige n’a pas été ouvert.';

  @override
  String p2pEndDisputeNotSentAfter(String reason) {
    return '$reason Le litige n’a pas été ouvert.';
  }

  @override
  String p2pEndDisputeNotRecordedMovedOn(String coordinator) {
    return 'L’échange a changé : $coordinator n’a pas ouvert le litige.';
  }

  @override
  String p2pEndDisputeOffline(String coordinator) {
    return '$coordinator est hors ligne : le litige n’a pas été ouvert.';
  }

  @override
  String p2pEndDisputeRefusedBy(String coordinator) {
    return '$coordinator n’a pas ouvert le litige.';
  }

  @override
  String get p2pEndDisputeUnknown =>
      'Bull Market ne sait pas encore si le litige a été ouvert et continue de vérifier : le litige s’affichera ici une fois ouvert.';

  @override
  String get p2pEndRateTrade => 'Évaluez votre expérience de trading';

  @override
  String p2pEndRateStar(String stars) {
    return '$stars sur 5';
  }

  @override
  String get p2pEndYourTxid => 'Votre TXID';

  @override
  String get p2pEndCopyTxid => 'Copier le TXID';

  @override
  String get p2pEndSendingCoins => 'Envoi des bitcoins en cours';

  @override
  String get p2pEndCopyAddress => 'Copier l’adresse';

  @override
  String get p2pSummaryTitle => 'Résumé de la transaction';

  @override
  String get p2pSummaryExport => 'Exporter le résumé de la transaction';

  @override
  String get p2pSummaryExportCopyFailed =>
      'Le résumé de la transaction n’a pas pu être copié.';

  @override
  String get p2pSummaryUserRole => 'Rôle utilisateur';

  @override
  String get p2pSummarySent => 'Envoyé';

  @override
  String get p2pSummaryReceived => 'Reçu';

  @override
  String get p2pSummaryBtcReceived => 'BTC reçus';

  @override
  String get p2pSummaryBtcSent => 'BTC envoyés';

  @override
  String get p2pSummaryTradeFee => 'Frais de transaction';

  @override
  String p2pSummarySats(String sats) {
    return '$sats Sats';
  }

  @override
  String p2pSummarySatsPercent(String sats, String percent) {
    return '$sats Sats ($percent%)';
  }

  @override
  String get p2pSummaryOnchainSwapFee => 'Frais d\'échange onchain';

  @override
  String get p2pSummaryMakerBond => 'Caution du créateur';

  @override
  String get p2pSummaryUnlocked => 'Débloqué';

  @override
  String get p2pSummaryRevenue => 'Revenu de la transaction du coordinateur';

  @override
  String get p2pSummaryRoutingBudget => 'Budget de routage';

  @override
  String p2pSummaryRate(String rate, String currencyCode) {
    return '$rate $currencyCode/BTC';
  }

  @override
  String get p2pSummaryContractRate => 'Taux de change du contrat';

  @override
  String get p2pEndRateUnknown =>
      'Bull Market ne sait pas si votre note est passée : l’ordre ne l’indique pas. Touchez une étoile pour l’envoyer de nouveau.';

  @override
  String get p2pEndRateNotSent => 'Votre note n’a pas été envoyée.';

  @override
  String p2pEndRateReadFailed(String coordinator) {
    return 'L’ordre n’a pas pu être relu chez $coordinator : votre note n’a pas été envoyée.';
  }

  @override
  String get p2pEndRateHost => 'Évaluez votre hôte';

  @override
  String p2pEndRateHostAsking(String coordinator) {
    return 'Demande à $coordinator l’autorisation de publier votre note…';
  }

  @override
  String p2pEndRateHostUnavailable(String coordinator) {
    return 'Votre note ne peut pas être publiée : $coordinator n’a pas pu être joint pour donner son autorisation, ou l’a refusée. Rouvrez cet échange pour réessayer.';
  }

  @override
  String p2pEndHostLovesYou(String coordinator) {
    return 'Merci ! $coordinator vous aime aussi';
  }

  @override
  String get p2pEndTellAFriend =>
      'RoboSats s\'améliore avec plus de liquidité et d\'utilisateurs. Parlez de Robosats à un ami bitcoiner!';

  @override
  String get p2pEndThanksForUsing => 'Merci d\'utiliser Robosats!';

  @override
  String p2pEndImprove(String simplex, String matrix, String github) {
    return 'Faites-nous savoir comment la plateforme pourrait être améliorée ($simplex / $matrix / $github)';
  }

  @override
  String get p2pEndImproveSimplex => 'SimpleX';

  @override
  String get p2pEndImproveMatrix => 'Matrix';

  @override
  String get p2pEndImproveGithub => 'Github';

  @override
  String get p2pMakeEnableAdvanced => 'Activer les options avancées';

  @override
  String get p2pMakeBuyOrSell => 'Acheter ou vendre bitcoin ?';

  @override
  String get p2pMakeBuy => 'Acheter';

  @override
  String get p2pMakeSell => 'Vendre';

  @override
  String get p2pMakeAmount => 'Montant';

  @override
  String get p2pMakeAmountHint => 'Montant de fiat à échanger contre bitcoin';

  @override
  String p2pMakeMoreThan(String minAmount) {
    return 'Doit être supérieur à $minAmount';
  }

  @override
  String p2pMakeLessThan(String maxAmount) {
    return 'Doit être inférieur à $maxAmount';
  }

  @override
  String get p2pMakePaymentMethods => 'Mode(s) de paiement fiat';

  @override
  String get p2pMakePaymentMethodsHint =>
      'Indiquez vos modes de paiement fiat préférés. Les modes rapides sont fortement recommandés.';

  @override
  String get p2pMakeAddCustomMethod =>
      'Ajouter un mode de paiement personnalisé';

  @override
  String get p2pMakeCustomMethodQuestion =>
      'Vous ne trouvez pas votre mode de paiement préféré dans la liste ?';

  @override
  String get p2pMakeCustomMethodText =>
      'Utilisez ce champ libre pour ajouter tout mode de paiement que vous souhaitez offrir.';

  @override
  String get p2pMakeCustomMethodLabel => 'Mode de paiement';

  @override
  String get p2pMakeCustomMethodEmpty => 'Ne peut pas être vide';

  @override
  String get p2pMakeCustomMethodNotShown =>
      'Les autres ne verraient pas ce texte tel que vous l’avez tapé. N’utilisez que des caractères visibles.';

  @override
  String get p2pMakeAddPaymentMethod => 'Ajouter un mode de paiement';

  @override
  String p2pMakeMustBeShorter(String max) {
    return 'Doit faire au plus $max caractères';
  }

  @override
  String p2pMakeRemoveMethod(String method) {
    return 'Retirer $method';
  }

  @override
  String get p2pMakePremium => 'Prime sur le marché (%)';

  @override
  String p2pMakePremiumTooHigh(String max) {
    return 'Doit être inférieur à $max %';
  }

  @override
  String p2pMakePremiumTooLow(String min) {
    return 'Doit être supérieur à $min %';
  }

  @override
  String get p2pMakeOrderFor => 'Ordre pour ';

  @override
  String get p2pMakeBuyBtcFor => 'Acheter BTC pour ';

  @override
  String get p2pMakeSellBtcFor => 'Vendre BTC pour ';

  @override
  String get p2pMakeAtMarketPrice => ' au prix du marché';

  @override
  String p2pMakeAtPremium(String premium) {
    return ' à une prime de $premium %';
  }

  @override
  String p2pMakeAtDiscount(String discount) {
    return ' à une remise de $discount %';
  }

  @override
  String p2pMakeEstimatedBond(String sats) {
    return 'Caution estimée : $sats sats';
  }

  @override
  String p2pMakeCurrentRate(String rate, String currencyCode) {
    return 'Taux actuel de l’ordre : $rate $currencyCode/BTC';
  }

  @override
  String get p2pMakeCurrentRateHint =>
      'Le taux de change actuel de votre ordre. Il suivra le marché.';

  @override
  String get p2pMakeCreateOrder => 'Créer l’ordre';

  @override
  String get p2pMakeLoading => 'Chargement…';

  @override
  String get p2pMakeChooseHost => 'Choisir le coordinateur de l’ordre';

  @override
  String get p2pMakeWhyLoadingCoordinators =>
      'Chargement de la liste des coordinateurs…';

  @override
  String get p2pMakeWhyPriceNotSynchronized =>
      'Le prix du bitcoin n’est pas synchronisé.';

  @override
  String get p2pMakeWhyNoSide =>
      'Veuillez choisir si vous souhaitez acheter ou vendre.';

  @override
  String get p2pMakeWhyOutsideLimits =>
      'Le montant est en dehors des limites autorisées.';

  @override
  String get p2pMakeWhyBadPaymentMethod =>
      'Le mode de paiement n’est pas valide.';

  @override
  String get p2pMakeWhyNoAmount => 'Veuillez saisir un montant.';

  @override
  String get p2pMakeWhyAmountNotPositive =>
      'Le montant doit être supérieur à 0.';

  @override
  String get p2pMakeWhyPremiumInvalid => 'La prime n’est pas valide.';

  @override
  String get p2pMakeWhyLimitsUnavailable =>
      'Les limites du coordinateur ne sont pas disponibles.';

  @override
  String get p2pMakeWhyPremiumNotANumber => 'La prime doit être un nombre.';

  @override
  String get p2pMakeWhyNoPaymentMethod =>
      'Veuillez sélectionner un mode de paiement.';

  @override
  String get p2pMakeWhyFormIncorrect =>
      'Vous devez remplir le formulaire correctement';

  @override
  String get p2pMakeAmountRange => 'Plage de montant';

  @override
  String get p2pMakeExactAmount => 'Montant exact';

  @override
  String get p2pMakeFrom => 'De';

  @override
  String get p2pMakeTo => 'à';

  @override
  String get p2pMakeDescription => 'Description';

  @override
  String get p2pMakeDescriptionHint =>
      'Vous pouvez ajouter plus de détails sur votre ordre.';

  @override
  String p2pMakeDescriptionTooLong(String max) {
    return 'Doit faire $max caractères ou moins';
  }

  @override
  String get p2pMakePassword => 'Mot de passe';

  @override
  String get p2pMakePasswordHint =>
      'Vous pouvez définir un mot de passe pour que seuls les robots avec qui vous le partagez puissent prendre cet ordre.';

  @override
  String get p2pMakePublicDuration => 'Durée publique (HH:mm)';

  @override
  String get p2pMakePublicDurationTitle => 'Durée de l’ordre public';

  @override
  String get p2pMakeEscrowDuration =>
      'Minuterie de dépôt de garantie/facture (HH:mm)';

  @override
  String get p2pMakeEscrowDurationTitle =>
      'Durée de l’étape de garantie/facture';

  @override
  String get p2pMakeBondSize => 'Taille de la caution de fidélité';

  @override
  String get p2pMakeBondSizeHint =>
      'Définissez votre engagement personnel, augmentez pour une meilleure assurance de sécurité';

  @override
  String p2pMakeBondSizeValue(String percent) {
    return '$percent %';
  }

  @override
  String get p2pMakeLocation => 'Emplacement face à face';

  @override
  String get p2pMakeLocationHint =>
      'Ajouter une géolocalisation pour un échange en face à face';

  @override
  String get p2pMakeWhyRangeInvalid => 'La plage de montant n’est pas valide.';

  @override
  String get p2pMakeRangeMaxBelowMin =>
      'Le maximum doit être supérieur au minimum.';

  @override
  String p2pMakeRangeMinAtLeast(String amount, String coordinator) {
    return 'Le minimum doit être d’au moins $amount chez $coordinator.';
  }

  @override
  String p2pMakeRangeMaxAtMost(String amount, String coordinator) {
    return 'Le maximum ne peut pas dépasser $amount chez $coordinator.';
  }

  @override
  String p2pMakeRangeMaxAtLeastFor(String min, String amount) {
    return 'Pour un minimum de $min, le maximum doit être d’au moins $amount.';
  }

  @override
  String p2pMakeRangeMaxAtMostFor(String min, String amount) {
    return 'Pour un minimum de $min, le maximum ne peut pas dépasser $amount.';
  }

  @override
  String p2pMakeRangeAccepted(String coordinator, String min, String max) {
    return 'Montants acceptés chez $coordinator : de $min à $max.';
  }

  @override
  String get p2pMakeRangeRatio =>
      'Le maximum doit valoir plus de 1,5 fois le minimum et au plus 14,95 fois.';

  @override
  String p2pMakeRangeMinAtMost(String amount, String coordinator) {
    return 'Le minimum ne peut pas dépasser $amount chez $coordinator : le maximum doit valoir plus de 1,5 fois le minimum.';
  }

  @override
  String p2pMakeRangeNoRoom(String coordinator) {
    return 'Aucune plage de montants n’est possible chez $coordinator avec cette prime : utilisez un montant exact.';
  }

  @override
  String get p2pMakeRangeNotPositive =>
      'Indiquez un minimum et un maximum supérieurs à 0.';

  @override
  String get p2pMakeWhyDescriptionInvalid => 'La description n’est pas valide.';

  @override
  String p2pMakeOptionsSentOpen(String options) {
    return 'Options avancées envoyées avec cet ordre : $options.';
  }

  @override
  String p2pMakeOptionsSentClosed(String options) {
    return 'Options avancées refermées, mais encore envoyées avec cet ordre : $options.';
  }

  @override
  String get p2pMakeOptionSentDescription => 'une description';

  @override
  String p2pMakeOptionSentPublicDuration(String duration) {
    return 'durée publique $duration';
  }

  @override
  String p2pMakeOptionSentEscrowDuration(String duration) {
    return 'délai de dépôt/facture $duration';
  }

  @override
  String p2pMakeOptionSentBondSize(String percent) {
    return 'caution de fidélité $percent';
  }

  @override
  String p2pMakeRateCompare(
    String walletPrice,
    String currency,
    String coordinator,
    String coordinatorPrice,
    String gap,
  ) {
    return 'Pour comparaison, prix indicatif du portefeuille Bull : $walletPrice $currency/BTC ($coordinator : $coordinatorPrice, écart $gap).';
  }

  @override
  String p2pMakeRateBelow(String coordinator, String threshold) {
    return 'Le prix annoncé par $coordinator est inférieur de plus de $threshold à celui du portefeuille Bull : votre caution serait plus élevée que prévu. Vérifiez-le avant de créer l’ordre.';
  }

  @override
  String p2pMakeRateBelowSell(String coordinator, String threshold) {
    return 'Le prix annoncé par $coordinator est inférieur de plus de $threshold à celui du portefeuille Bull : votre caution serait plus élevée que prévu, et vous bloqueriez plus de sats pour votre montant quand l’ordre sera pris. Vérifiez-le avant de créer l’ordre.';
  }

  @override
  String p2pMakeRateAbove(String coordinator, String threshold) {
    return 'Le prix annoncé par $coordinator est supérieur de plus de $threshold à celui du portefeuille Bull : vous recevriez moins de sats quand l’ordre sera pris. Vérifiez-le avant de créer l’ordre.';
  }

  @override
  String p2pMakeRateNotPriced(String currency, String coordinator) {
    return 'Le portefeuille Bull n’a pas de prix pour $currency : taux non vérifié. Vous faites confiance au prix annoncé par $coordinator : vérifiez-le vous-même avant de créer l’ordre.';
  }

  @override
  String p2pMakeRateUnverified(String currency) {
    return 'Le portefeuille Bull n’a pas pu lire son prix du bitcoin en $currency : taux non vérifié.';
  }

  @override
  String get p2pMakeRateReading =>
      'Lecture du prix du portefeuille Bull pour comparaison…';

  @override
  String get p2pMakeCreating => 'Création de votre ordre…';

  @override
  String p2pMakePending(String coordinator) {
    return 'Bull Market ne sait pas encore si $coordinator a créé votre ordre. Vérifiez-le de nouveau ci-dessous, ou écartez-le.';
  }

  @override
  String get p2pMakeNotMade => 'L’ordre n’a pas été créé.';

  @override
  String p2pMakeNotMadeAfter(String reason) {
    return '$reason L’ordre n’a pas été créé.';
  }

  @override
  String p2pMakeCoordinatorUnreadable(String coordinator) {
    return 'Impossible de joindre $coordinator. L’ordre n’a pas été créé.';
  }

  @override
  String p2pMakeFeeTooHigh(String coordinator) {
    return '$coordinator demande des frais de créateur supérieurs à 1 %. L’ordre n’a pas été créé.';
  }

  @override
  String get p2pMakeTermsUnusable =>
      'Les conditions de cet ordre n’ont pas pu être vérifiées. Il n’a pas été créé.';

  @override
  String get p2pMakeNotRecorded =>
      'Bull Market n’a pas pu écrire ses enregistrements sur cet appareil. L’ordre n’a pas été créé.';

  @override
  String p2pMakeRobotNotNew(String coordinator) {
    return 'Le robot choisi pour cet ordre existait déjà chez $coordinator. L’ordre n’a pas été créé : réessayez.';
  }

  @override
  String get p2pMakeTooBig => 'Votre ordre est trop gros.';

  @override
  String get p2pMakeTooSmall => 'Votre ordre est trop petit.';

  @override
  String get p2pMakeRangeTooNarrow =>
      'Le montant maximum de la plage doit dépasser d’au moins 50 % le montant minimum.';

  @override
  String get p2pMakeRangeMaxTooBig =>
      'Le montant maximum de votre ordre est trop gros.';

  @override
  String get p2pMakeRangeMinTooSmall =>
      'Le montant minimum de votre ordre est trop petit.';

  @override
  String get p2pMakeRangeTooWide =>
      'La plage de montant de votre ordre est trop large. Le montant maximum ne peut pas dépasser 15 fois le montant minimum.';

  @override
  String p2pMakeBookFull(String coordinator) {
    return 'Le carnet est complet chez $coordinator.';
  }

  @override
  String get p2pMakeClearForm => 'Effacer le formulaire';

  @override
  String get p2pMakeCurrentRateLabel => 'Taux actuel de l’ordre :';

  @override
  String p2pMakeCurrentRateUnit(String currencyCode) {
    return '$currencyCode/BTC';
  }

  @override
  String get p2pMakeNoHost =>
      'Aucun coordinateur ne peut être choisi pour l’instant.';

  @override
  String p2pMakePriceCheckChanged(String coordinator) {
    return 'Le prix annoncé par $coordinator a changé depuis son affichage. Vérifiez la comparaison, puis appuyez de nouveau sur « Créer l’ordre ».';
  }

  @override
  String get p2pMakePricesReadAgain =>
      'Les limites et les prix ont été relus et ont changé. Vérifiez le formulaire, puis appuyez de nouveau sur « Créer l’ordre ».';

  @override
  String get p2pMakePriceReadAtPress =>
      'La comparaison des prix vient d’être mise à jour. Vérifiez-la, puis appuyez de nouveau sur « Créer l’ordre ».';

  @override
  String get p2pTradeTitleOrderPublic => 'Votre ordre est public';

  @override
  String get p2pTradeTitleOrderPaused => 'Votre ordre est en pause';

  @override
  String p2pTradePublicWait(String hours, String minutes) {
    return 'Patientez pendant que les robots consultent le carnet. Cette boîte sonnera 🔊 dès qu’un robot prendra votre ordre ; vous aurez alors $hours h $minutes min pour répondre. Si vous ne répondez pas, vous risquez de perdre votre caution.';
  }

  @override
  String get p2pTradePublicExpiresUntaken =>
      'Si l’ordre expire sans être pris, votre caution vous sera rendue (aucune action nécessaire).';

  @override
  String p2pTradePublicOrdersFor(String currencyCode) {
    return 'Ordres publics pour $currencyCode';
  }

  @override
  String p2pTradePremiumRank(String rank) {
    return 'Classement de prime $rank %';
  }

  @override
  String p2pTradePremiumRankAmong(String currencyCode) {
    return 'Parmi les ordres publics en $currencyCode (plus élevé est moins cher)';
  }

  @override
  String get p2pTradePausedText =>
      'Votre ordre public a été mis en pause. Pour le moment, il ne peut être ni vu ni pris par d’autres robots. Vous pouvez choisir de le reprendre à tout moment.';

  @override
  String get p2pTradePauseOrder => 'Mettre en pause l’ordre public';

  @override
  String get p2pTradeUnpauseOrder => 'Reprendre l’ordre';

  @override
  String get p2pTradePauseNeedsRead =>
      'Attendez que l’ordre soit relu avant de le mettre en pause ou de le reprendre.';

  @override
  String get p2pTradePauseMovedOn =>
      'L’ordre a changé avant l’envoi de votre demande : rien n’a été envoyé. Il est affiché tel qu’il est maintenant.';

  @override
  String p2pTradePauseReadFailed(String coordinator) {
    return 'L’ordre n’a pas pu être relu chez $coordinator : rien n’a été envoyé.';
  }

  @override
  String p2pTradePauseNotDoneAfter(String reason) {
    return '$reason Votre demande n’a rien changé.';
  }

  @override
  String p2pTradePauseRefusedBy(String coordinator) {
    return '$coordinator a refusé la demande : votre demande n’a rien changé. L’ordre est affiché tel qu’il est maintenant.';
  }

  @override
  String p2pTradePauseUnknown(String coordinator) {
    return 'Bull Market ne sait pas encore si votre demande est arrivée chez $coordinator. Il vérifie de nouveau tant que cet écran est ouvert, et ne la renvoie jamais de lui-même. Ne réappuyez pas avant qu’une lecture montre où en est votre ordre : une seconde demande annulerait la première si celle-ci arrivait en retard.';
  }

  @override
  String p2pTradePauseNotReachedPaused(String coordinator) {
    return '$coordinator a accepté la demande, mais votre ordre n’est pas en pause : il est affiché tel qu’il est maintenant.';
  }

  @override
  String p2pTradePauseNotReachedPublic(String coordinator) {
    return '$coordinator a accepté la demande, mais votre ordre n’est pas public : il est affiché tel qu’il est maintenant.';
  }

  @override
  String get p2pTradePauseWhileCancel =>
      'L’ordre est en cours d’annulation : attendez la fin.';

  @override
  String get p2pTradePauseMayStillArrive =>
      'Une demande dont la réponse s’est perdue peut encore arriver et rendre votre ordre de nouveau public. Deux lectures qui le montrent en pause, à quelques minutes d’intervalle, cet écran ouvert, réduisent ce risque sans l’exclure : d’ici là, considérez qu’il peut être public.';

  @override
  String get p2pTradeCancelAfterPause =>
      'Votre annulation partira une fois la mise en pause ou la reprise terminée.';

  @override
  String get p2pTradeCancelMovedOnTapAgain =>
      'L’ordre a changé d’état avant l’annulation : rien n’a été annulé. Appuyez de nouveau sur « Annuler » si vous voulez toujours l’annuler.';

  @override
  String get p2pTradeStillPublic =>
      'Votre ordre est public : les robots peuvent le voir et le prendre.';

  @override
  String get p2pTradeMayBePublic =>
      'Tant qu’une lecture faite après votre demande ne le montre pas en pause, considérez votre ordre comme public : les robots peuvent le prendre.';

  @override
  String get p2pTradePublicAgain =>
      'Votre ordre est de nouveau public, alors qu’il avait été mis en pause depuis cette app : les robots peuvent le voir et le prendre.';

  @override
  String get p2pTradeMakerBondLocked => 'Votre caution de créateur est bloquée';

  @override
  String get p2pTradeMakerBondUnlocked =>
      'Votre caution de créateur est débloquée';

  @override
  String get p2pTradeMakerBondSettled =>
      'Votre caution de créateur est débitée';

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
    return '$coordinator a fixé $sats sats pour $amount $currencyCode quand votre ordre a été pris : un taux de $rate $currencyCode/BTC, $gap par rapport au taux à sa création ($createdRate).';
  }

  @override
  String get p2pTradeWarnContractSeenLate =>
      'Votre ordre a été pris de nouveau et cet échange a avancé sans que Bull Market en voie les étapes, comme quand votre clé de garage sert dans une autre app. Vérifiez l’échange dans cette app avant d’agir ici.';

  @override
  String p2pPendingMakeChecking(String coordinator) {
    return 'Vérification auprès de $coordinator…';
  }

  @override
  String p2pPendingMakeUnknown(String coordinator) {
    return 'Bull Market ne sait pas encore si $coordinator a créé cet ordre. Aucune caution n’est demandée tant qu’il ne le sait pas.';
  }

  @override
  String get p2pPendingMakeSetAside => 'Écarter';

  @override
  String get p2pPendingMakeSetAsideTitle => 'Écarter cet ordre ?';

  @override
  String p2pPendingMakeSetAsideText(String coordinator) {
    return 'Bull Market cessera de le vérifier. Un ordre peut encore exister chez $coordinator : aucune caution n’a été payée pour lui depuis cette app, et il expire de lui-même quelques minutes après sa création.';
  }

  @override
  String get p2pMakePendingFirst =>
      'Un de vos ordres est encore en cours de création. Vérifiez-le de nouveau ou écartez-le avant d’en créer un autre.';

  @override
  String p2pMakeSendingStay(String coordinator) {
    return 'Attendez la réponse de $coordinator avant de quitter : votre ordre est en cours de création.';
  }

  @override
  String get p2pPayoutRateReading =>
      'Lecture du prix du portefeuille Bull pour comparaison…';

  @override
  String p2pPayoutRateWallet(
    String price,
    String currency,
    String amount,
    String expected,
    String received,
    String gap,
  ) {
    return 'Au prix du portefeuille Bull, $price $currency/BTC, avec la prime de l’ordre, $amount $currency valent $expected sats. Vous recevez $received sats : écart $gap.';
  }

  @override
  String get p2pPayoutBreakdownTitle => 'Décompte, en sats';

  @override
  String get p2pPayoutBreakdownNotCompared =>
      'Pas de vérification Bull Wallet à cette étape';

  @override
  String get p2pPayoutBreakdownValue => 'Attendu par Bull Wallet';

  @override
  String p2pPayoutBreakdownPrice(String amount, String currency, String price) {
    return '$amount $currency à $price $currency/BTC, prime comprise';
  }

  @override
  String get p2pPayoutBreakdownGiven => 'Versé par le coordinateur';

  @override
  String get p2pPayoutBreakdownGap => 'Écart au prix Bull (indicatif)';

  @override
  String get p2pPayoutBreakdownCoordinatorFee =>
      'Frais du coordinateur, déjà déduits';

  @override
  String get p2pPayoutBreakdownRoutingBudget => 'Frais de routage Lightning';

  @override
  String get p2pPayoutBreakdownInvoice => 'Votre facture';

  @override
  String get p2pPayoutBreakdownSwapFee => 'Frais de swap';

  @override
  String get p2pPayoutBreakdownReceived => 'Vous recevrez';

  @override
  String get p2pPayoutBreakdownFees => 'Frais de routage et de swap';

  @override
  String get p2pPayoutBreakdownRoutingFees => 'Frais de routage';

  @override
  String get p2pPayoutBreakdownGapNotPriced => 'Écart au prix Bull';

  @override
  String get p2pPayoutBreakdownNotPriced => 'non coté';

  @override
  String get p2pPayoutBreakdownAgainst => 'Écart en votre défaveur';

  @override
  String p2pPayoutBreakdownAgainstFigures(String expected, String received) {
    return 'Bull Wallet attendait $expected sats, le coordinateur en verse $received.';
  }

  @override
  String p2pPayoutBreakdownAgainstDetail(String threshold) {
    return 'Bull Wallet refait le calcul avec son propre prix, prime comprise, et vous prévient au-delà de $threshold d’écart. Vérifiez l’ordre avant de continuer.';
  }

  @override
  String get p2pPayoutBreakdownUnverified => 'Montant non vérifié';

  @override
  String get p2pPayoutBreakdownUnverifiedLine =>
      'Bull Wallet n’a pas pu obtenir son prix du bitcoin.';

  @override
  String get p2pPayoutBreakdownUnverifiedDetail =>
      'Sans ce prix, il ne peut pas comparer le montant du coordinateur.';

  @override
  String get p2pPayoutRateTermsUnreadLine =>
      'Bull Wallet n’a pas pu relire les termes de l’ordre sur cet appareil.';

  @override
  String get p2pPayoutRateTermsUnreadDetail =>
      'Sans eux, il ne peut pas comparer le montant du coordinateur.';

  @override
  String get p2pPayoutFirstFewer => 'Moins de sats qu’à la première facture';

  @override
  String p2pPayoutFirstFewerFigures(String first, String now) {
    return 'Première demande : $first sats, le coordinateur en verse maintenant $now.';
  }

  @override
  String get p2pPayoutFirstFewerDetail =>
      'Pour un même contrat, le coordinateur doit redemander le même montant. Vous avez déjà envoyé votre paiement et aucun litige n’est plus possible à cette étape : contactez le coordinateur avant de donner cette facture.';

  @override
  String get p2pPayoutFirstUnknown => 'Non comparé à la première facture';

  @override
  String get p2pPayoutFirstUnknownDetail =>
      'Bull Market ne connaît le montant de la première facture que s’il l’a vu depuis le dernier démarrage de l’app. Comparez-le vous-même à celui-ci.';

  @override
  String p2pRateAgainstSinceMade(String gap) {
    return 'Écart de $gap en votre défaveur depuis la création de l’ordre';
  }

  @override
  String p2pRateAgainstSinceMadeDetail(String currency) {
    return 'Bull Wallet ne cote pas le $currency. Il compare donc le taux du coordinateur au moment de la prise à celui de la création de l’ordre. Le cours a pu bouger entre-temps.';
  }

  @override
  String get p2pPayoutBreakdownSmallGap =>
      'Un petit écart est normal : le coordinateur a sa propre source de prix.';

  @override
  String get p2pDetailShow => 'Voir le détail';

  @override
  String get p2pDetailHide => 'Masquer le détail';

  @override
  String p2pPayoutRateAgainst(String gap) {
    return 'Écart en votre défaveur $gap';
  }

  @override
  String p2pPayoutRateNotPriced(String currency, String coordinator) {
    return 'Le portefeuille Bull n’a pas de prix pour $currency : taux non vérifié. Vous faites confiance au prix annoncé par $coordinator : vérifiez-le vous-même avant de continuer.';
  }

  @override
  String p2pPayoutRateUnverified(String currency) {
    return 'Le portefeuille Bull n’a pas pu lire son prix du bitcoin en $currency : taux non vérifié. Vous pouvez réessayer, ou continuer sans cette vérification.';
  }

  @override
  String p2pTradeBreachWhatToDo(String coordinator) {
    return 'Pour suivre cet ordre en sécurité, ouvrez-le dans l’app officielle RoboSats avec votre clé de garage, et contactez $coordinator si quelque chose vous paraît anormal.';
  }

  @override
  String p2pPayoutRateSatsMissing(String coordinator) {
    return 'Taux non vérifié : $coordinator ne donne pas de sats pour cette étape de l’échange. Vérifiez-les vous-même avant de continuer.';
  }

  @override
  String get p2pTradeNoRingYet =>
      'Bull Market ne sonne pas encore : gardez cet écran ouvert, ou revenez-y souvent.';

  @override
  String get p2pTradeEscrowWaitMaker =>
      'Pour un ordre que vous avez créé : si le vendeur ne bloque pas sa garantie, votre ordre retourne dans le carnet et votre caution reste bloquée.';

  @override
  String get p2pTradePayoutWaitMaker =>
      'Pour un ordre que vous avez créé : si l’acheteur ne coopère pas, votre garantie revient, mais votre ordre retourne dans le carnet et votre caution reste bloquée.';

  @override
  String p2pPayoutRateToldMoved(String coordinator, String told, String asked) {
    return '$coordinator annonce maintenant $told sats pour ce contrat, mais a demandé avant une facture de $asked sats : Bull Market compare le plus petit des deux. Vérifiez la facture donnée avant de continuer.';
  }

  @override
  String p2pPayoutRateToldNow(String coordinator) {
    return 'Les sats reçus affichés ci-dessus sont ceux que $coordinator annonce maintenant : Bull Market ne garde pas votre facture après un redémarrage. Comparez-les vous-même au montant de votre facture.';
  }

  @override
  String get p2pTradeBondBackThroughSwap =>
      'Une caution payée avec ce portefeuille revient par le service de swap, moins ses frais, après un délai.';

  @override
  String get p2pPayoutRateNotSeen =>
      'Bull Market n’a pas vu la facture de paiement de ce contrat : n’envoyez pas l’argent avant d’avoir vérifié dans l’app officielle.';

  @override
  String get p2pTradeBondPaidHereBack =>
      'Votre caution a été payée avec ce portefeuille : une fois rendue, elle revient par le service de swap, moins ses frais, après un délai.';

  @override
  String get p2pTradeEscrowPaidHereBack =>
      'Votre garantie a été payée avec ce portefeuille : une fois rendue, elle revient par le service de swap, moins ses frais, après un délai.';

  @override
  String get p2pTradeBothPaidHereBack =>
      'Votre caution et votre garantie ont été payées avec ce portefeuille : une fois rendues, elles reviennent par le service de swap, moins ses frais, après un délai.';

  @override
  String get p2pTradeBondOrEscrowBackThroughSwap =>
      'Une caution ou une garantie payée avec ce portefeuille revient par le service de swap, moins ses frais, après un délai.';

  @override
  String get p2pOrderRecordsUnreadable =>
      'Bull Market n’a pas pu lire ses échanges : cet ordre est peut-être le vôtre, il ne peut donc pas être pris ici. Revenez en arrière et réessayez.';

  @override
  String get p2pRenewOrder => 'Renouveler l’ordre';

  @override
  String get p2pRenew => 'Renouveler';

  @override
  String p2pRenewIntro(String orderId) {
    return 'Renouvellement de l’ordre $orderId : un nouvel ordre est créé avec les termes que cet appareil en a gardés, sous un nouveau robot, et demande une nouvelle caution.';
  }

  @override
  String get p2pRenewTermsUnreadable =>
      'Cet ordre ne peut pas être renouvelé : les termes que cet appareil en a gardés n’ont pas pu être lus.';

  @override
  String get p2pRenewNotEnded =>
      'Cet ordre ne peut pas être renouvelé : cet appareil ne l’a pas vu expiré ou terminé.';

  @override
  String get p2pRenewCoordinatorGone =>
      'Cet ordre ne peut pas être renouvelé : son coordinateur n’est plus dans la liste, ou a changé d’adresse.';

  @override
  String get p2pRenewNotAsKept =>
      'Le formulaire ne montre pas exactement les termes gardés de cet ordre : rien ne peut être envoyé.';

  @override
  String get p2pRenewNoLongerAsKept =>
      'Cet ordre ne peut plus être renouvelé tel quel : créez un nouvel ordre.';

  @override
  String p2pTradeKeptTerms(String date, String summary) {
    return 'Créé ici le $date, avec les termes gardés sur cet appareil : $summary.';
  }

  @override
  String p2pSameTermsMade(String orderId, String stands) {
    return 'Un ordre aux mêmes termes a été créé ici après celui-ci : l’ordre $orderId, $stands.';
  }

  @override
  String get p2pSameTermsRunning => 'toujours en cours ici';

  @override
  String get p2pSameTermsExpired => 'expiré';

  @override
  String get p2pSameTermsCancelled => 'annulé';

  @override
  String get p2pSameTermsCompleted => 'mené à terme';

  @override
  String get p2pSameTermsEnded => 'terminé';

  @override
  String p2pSameTermsOpen(String orderId) {
    return 'Ouvrir l’ordre $orderId';
  }

  @override
  String get p2pSameTermsUnknown =>
      'Bull Market n’a pas pu lire ses enregistrements pour savoir si un ordre aux mêmes termes a été créé ici depuis celui-ci.';

  @override
  String get p2pRenewSameTermsTitle => 'Renouveler cet ordre ?';

  @override
  String get p2pRenewSameTermsGo => 'Renouveler quand même';

  @override
  String p2pTradeEndNotRead(String coordinator, String date) {
    return 'Cet ordre n’a pas pu être relu chez $coordinator : ce qui est affiché est ce que cet appareil a gardé à sa fin, le $date.';
  }

  @override
  String p2pTradeEndUnknown(String coordinator, String date) {
    return '$coordinator a répondu qu’il ne connaît pas cet ordre : ce qui est affiché est ce que cet appareil a gardé à sa fin, le $date.';
  }

  @override
  String p2pTradeEndOtherwise(String coordinator, String date) {
    return '$coordinator montre maintenant cet ordre autrement que cet appareil l’a gardé à sa fin, le $date.';
  }

  @override
  String p2pRenewEndNotConfirmed(String coordinator) {
    return 'La fin de cet ordre n’a pas été confirmée par $coordinator.';
  }

  @override
  String p2pRenewEndAlive(String coordinator) {
    return '$coordinator montre cet ordre encore en cours : il peut encore être pris ou demander une action de votre part, et des sats y sont peut-être encore bloqués.';
  }

  @override
  String p2pRenewEndOtherwise(String coordinator) {
    return '$coordinator montre cet ordre autrement que cet appareil l’a gardé.';
  }

  @override
  String p2pRenewSameTermsMade(String orderId, String stands) {
    return 'Un ordre aux mêmes termes a déjà été créé ici après celui-ci : l’ordre $orderId, $stands.';
  }

  @override
  String get p2pRenewSameTermsUnknown =>
      'Bull Market n’a pas pu vérifier si un ordre aux mêmes termes a déjà été créé ici.';

  @override
  String get p2pRenewOneMore =>
      'Renouveler crée un ordre de plus, sous un nouveau robot, avec une nouvelle caution à payer.';

  @override
  String get p2pSameTermsPending =>
      'Un ordre aux mêmes termes est encore en cours de création ici.';

  @override
  String p2pTradeEndReading(String coordinator) {
    return 'Relecture de cet ordre chez $coordinator…';
  }

  @override
  String p2pTradeEndAlive(String coordinator) {
    return '$coordinator montre maintenant cet ordre comme toujours en cours : il peut encore être pris ou demander une action de votre part, et des sats y sont peut-être encore bloqués. Vérifiez-le dans l’application officielle RoboSats avec votre clé de garage avant d’en créer un autre.';
  }

  @override
  String p2pTradeEndKeptEnded(String date) {
    return 'Cet appareil a gardé cet ordre comme terminé le $date.';
  }

  @override
  String get p2pRenewUnverified =>
      'Bull Market n’a pas pu vérifier si ce renouvellement a créé un ordre : plus rien ne peut être envoyé depuis cette page. Revenez en arrière, puis rouvrez l’ordre depuis le Garage ou « Ordre ».';

  @override
  String get p2pMakeSubmit => 'Soumettre';

  @override
  String get p2pMakeEditOrder => 'Modifier l’ordre';

  @override
  String get p2pMakeMatchesFound =>
      'Des ordres existants correspondent au vôtre !';

  @override
  String get p2pMakeSeeDetails => 'Voir le détail';

  @override
  String get p2pMakeHideDetails => 'Masquer le détail';

  @override
  String get p2pMakePasswordLine =>
      'Hors du carnet ; se prend avec son lien et le mot de passe.';

  @override
  String get p2pMakePasswordShare =>
      'Partagez le lien de l’ordre (« Copier l\'URL » sur sa page une fois créé) et le mot de passe avec les robots de votre choix.';

  @override
  String get p2pMakePasswordTakers =>
      'Qui a le lien et le mot de passe peut le prendre, dans Bull Market (« Rechercher un ordre ») ou dans l’application officielle RoboSats.';

  @override
  String get p2pMakePasswordReadable =>
      'Qui demande l’ordre au coordinateur par son numéro peut quand même lire son sens, sa monnaie, son montant, sa prime, son mode de paiement, sa caution, ses délais et le nom de votre robot ; ni sa description ni son lieu.';

  @override
  String get p2pMakePasswordHashOnly =>
      'Seule l’empreinte SHA-256 du mot de passe quitte cet appareil, et elle n’est pas gardée : renouveler l’ordre redemande le mot de passe.';

  @override
  String p2pMakePasswordOldCoordinator(String coordinator, String version) {
    return '$coordinator ($version) montre les ordres protégés à tous.';
  }

  @override
  String p2pMakePasswordUnknownVersion(String coordinator) {
    return 'Version de $coordinator inconnue : l’ordre protégé peut être visible de tous.';
  }

  @override
  String get p2pMakePasswordOldDetail =>
      'Avant la version 0.8.7 (avis GHSA-r6f6-x59j-8q69), un coordinateur donne le montant, la prime, le mode de paiement, le nom de votre robot et le lieu d’un ordre protégé à qui le demande, sans le mot de passe. L’ordre peut quand même être créé ; choisissez un autre coordinateur pour le garder privé.';

  @override
  String get p2pMakeOptionSentPassword => 'un mot de passe';

  @override
  String get p2pRenewPasswordAgain => 'Saisissez à nouveau le mot de passe';

  @override
  String get p2pRenewPasswordSame =>
      'Cet appareil ne garde pas le mot de passe : tapez le même qu’avant, celui que vous avez partagé, sinon l’ordre ne s’ouvrira pas avec lui.';

  @override
  String p2pMakeLocationSent(String point) {
    return 'Point envoyé : $point';
  }

  @override
  String get p2pMakeLocationRemove => 'Retirer le lieu';

  @override
  String get p2pMakeLocationRandomized =>
      'Pour protéger votre vie privée, l\'emplacement exact que vous épinglez sera légèrement randomisé.';

  @override
  String get p2pMakeLocationPublished =>
      'Envoyé au coordinateur ; publié avec l’ordre s’il n’a pas de mot de passe.';

  @override
  String get p2pMakeLocationDetail =>
      'Le point affiché est celui envoyé : l’endroit épinglé, déplacé jusqu’à 0,05° dans chaque sens (quelques kilomètres). Le coordinateur le montre avec l’ordre, et le publie sur Nostr pour un ordre sans mot de passe. Bull Market ne lit rien de la position de votre téléphone, seulement le point que vous épinglez.';

  @override
  String get p2pMapChooseLocation => 'Choisir un lieu';

  @override
  String get p2pMapSave => 'Enregistrer';

  @override
  String get p2pMapPinHint =>
      'Carte du monde : touchez un endroit pour l’épingler.';

  @override
  String p2pMapPinned(String point) {
    return 'Endroit épinglé : $point';
  }

  @override
  String get p2pPayoutTracePasted =>
      'La facture de paiement de ce contrat a été collée : les sats iront au portefeuille qui l’a faite.';

  @override
  String get p2pPayoutTracePastedAddress =>
      'L’adresse de paiement de ce contrat a été collée : les sats iront au portefeuille auquel elle appartient.';

  @override
  String get p2pPayoutTraceNotGivenHere =>
      'La facture ou l’adresse de paiement de ce contrat n’a pas été donnée depuis Bull Market : vérifiez où arriveront les sats.';

  @override
  String get p2pPayoutTraceUnknown =>
      'Bull Market ne sait pas si la facture ou l’adresse de paiement de ce contrat vient de ce portefeuille.';

  @override
  String p2pTermsShownAbove(
    String coordinator,
    String day,
    String time,
    String high,
    String own,
  ) {
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time, jusqu’à une prime de $high au lieu de $own.';
  }

  @override
  String p2pTermsShownBelow(
    String coordinator,
    String day,
    String time,
    String low,
    String own,
  ) {
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time, avec une prime descendue à $low au lieu de $own.';
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
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time, avec des primes de $low à $high au lieu de $own.';
  }

  @override
  String p2pTermsShownPremiums(
    String coordinator,
    String day,
    String time,
    String low,
    String high,
  ) {
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time, avec des primes de $low à $high.';
  }

  @override
  String p2pTermsShownPremiumAlone(
    String coordinator,
    String day,
    String time,
    String premium,
  ) {
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time, avec une prime de $premium.';
  }

  @override
  String p2pTermsShownOther(String coordinator, String day, String time) {
    return '$coordinator a montré cet échange avec d’autres conditions à partir du $day à $time.';
  }

  @override
  String get p2pTakeWrongPassword => 'Mot de passe incorrect';

  @override
  String get p2pTakePasswordMissing => 'Saisissez le mot de passe de l’ordre.';

  @override
  String get p2pTakeProtectedHidden =>
      'Ordre protégé : sa description et son lieu s’affichent une fois que vous l’avez pris.';

  @override
  String get p2pTradeMeetingPoint => 'Emplacement F2F';

  @override
  String get p2pTradeMeetingPointApproximate =>
      'L\'emplacement épinglé est approximatif. L\'emplacement exact du lieu de rencontre doit être échangé dans le chat crypté.';

  @override
  String get p2pMapShowTiles => 'Afficher les tuiles';

  @override
  String get p2pMapTilesTitle => 'Télécharger une carte haute résolution?';

  @override
  String get p2pMapTilesText =>
      'By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation.';

  @override
  String get p2pMapTilesClose => 'Fermer';

  @override
  String get p2pMapTilesAcknowledged => 'Confirmer';

  @override
  String get p2pMapTilesCredit => '© OpenStreetMap contributors';

  @override
  String get p2pMapTilesUnavailable => 'Tuiles de la carte indisponibles';

  @override
  String get p2pTakePriceAgainst => 'Prix en votre défaveur';

  @override
  String get p2pTakePriceFarBelow => 'Prix très en dessous du prix Bull';

  @override
  String p2pTakePriceFigures(
    String wallet,
    String currency,
    String coordinator,
  ) {
    return 'Bull Wallet compte $wallet $currency/BTC, le coordinateur $coordinator.';
  }

  @override
  String p2pTakePriceDetail(String threshold) {
    return 'Bull Wallet compare le prix du coordinateur, hors prime, à son propre prix et vous prévient au-delà de $threshold d’écart. Vérifiez l’ordre avant de le prendre.';
  }

  @override
  String get p2pTakePriceUnverified => 'Prix non vérifié';

  @override
  String get p2pTakePriceUnverifiedDetail =>
      'Sans ce prix, il ne peut pas comparer le prix du coordinateur. Vous pouvez réessayer, ou prendre l’ordre sans cette vérification.';

  @override
  String get p2pTakePageChangedTitle => 'La fiche a changé';

  @override
  String get p2pTakePageChangedLine =>
      'Relisez la ligne du prix, puis continuez à nouveau.';

  @override
  String get p2pHistoryShow => 'Voir l’historique';

  @override
  String get p2pHistoryHide => 'Masquer l’historique';

  @override
  String get p2pHistorySeeMore => 'Voir plus';

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
  String get p2pHistorySell => 'Vente';

  @override
  String get p2pHistoryBuy => 'Achat';

  @override
  String get p2pHistoryMadeHere => 'créé ici';

  @override
  String get p2pHistoryTakenHere => 'pris ici';

  @override
  String get p2pHistoryTraded => 'Échangé';

  @override
  String get p2pHistoryExpired => 'Expiré';

  @override
  String get p2pHistoryCancelled => 'Annulé';

  @override
  String get p2pHistoryDispute => 'Litige';

  @override
  String get p2pHistoryEndUnknown => 'Fin inconnue';

  @override
  String p2pGarageKeyNumber(int index) {
    return 'Clé de garage interne n° $index';
  }

  @override
  String get p2pGarageKeyMasked => 'robo1••••••••••••';

  @override
  String get p2pGaragePreviousKey => 'Clé de garage interne précédente';

  @override
  String get p2pGarageNextKey => 'Clé de garage interne suivante';

  @override
  String get p2pGarageNewKey => 'Nouvelle clé de garage interne';

  @override
  String get p2pGarageNewKeyTitle => 'Nouvelle clé de garage';

  @override
  String p2pGarageNewKeyText(int index) {
    return 'Vos échanges utiliseront la clé de garage interne n° $index. Les clés de garage précédentes restent accessibles dans le Garage.';
  }

  @override
  String p2pGarageNewKeyConfirm(int index) {
    return 'Créer la clé de garage interne n° $index';
  }

  @override
  String get p2pGarageKeyNoWallet =>
      'Aucun portefeuille Bitcoin par défaut : les clés de garage internes viennent de ses 12 mots.';

  @override
  String get p2pGarageKeyPassphrase =>
      'Ce portefeuille a une phrase secrète : ses 12 mots seuls ne donnent pas les clés de garage internes.';

  @override
  String get p2pGarageKeyNoWords =>
      'Ce portefeuille n\'a pas de mots : les clés de garage internes en viennent.';

  @override
  String get p2pGarageKeyMismatch =>
      'Les 12 mots de ce portefeuille ne redonnent pas la clé de garage interne enregistrée sur cet appareil. Rien n\'a été signé.';

  @override
  String get p2pGarageKeyLastIndex =>
      'Il n\'y a pas de clé de garage interne après celle-ci.';

  @override
  String get p2pGarageExternalKey => 'Clé de garage externe';

  @override
  String get p2pGarageKeyBackedUp =>
      'Sauvegardée par les 12 mots de votre Bull Wallet.';

  @override
  String get p2pGarageKeyNotBackedUp =>
      'Non sauvegardée par votre Bull Wallet : gardez-en une copie.';

  @override
  String get p2pGarageKeyExplain => 'Explication';

  @override
  String get p2pGarageInternalKeysTitle => 'Clés de garage internes';

  @override
  String get p2pGarageInternalKeysInfo =>
      'Vos clés de garage internes sont sauvegardées par les 12 mots de votre Bull Wallet : en réinstallant l\'app avec ces 12 mots, vous les retrouvez. Gardez-les précieusement et ne les partagez pas : qui détient une clé de garage contrôle ses robots.';

  @override
  String get p2pGarageExternalKeyInfo =>
      'Cette clé de garage n\'est pas sauvegardée par les 12 mots de votre Bull Wallet. Si vous perdez ce téléphone ou supprimez l\'app, vous ne la retrouverez qu\'avec votre propre copie : sauvegardez-la à part. Gardez-la précieusement et ne la partagez pas.';

  @override
  String get p2pGarageSwitchToExternal =>
      'Basculer sur la clé de garage externe';

  @override
  String get p2pGarageBackToInternal => 'Revenir aux clés de garage internes';

  @override
  String get p2pGarageImportExternal => 'Importer une clé de garage externe';

  @override
  String get p2pGarageDeleteExternal => 'Supprimer la clé de garage externe';

  @override
  String get p2pGarageDeleteExternalTitle =>
      'Supprimer la clé de garage externe ?';

  @override
  String get p2pGarageDeleteExternalText =>
      'Elle n\'est pas sauvegardée par votre Bull Wallet. Sans une copie, ses robots seront perdus pour cette app.';

  @override
  String p2pGarageDeleteExternalTrades(int count, String orders) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Les échanges $orders utilisent cette clé de garage : sans elle, vous ne pourrez plus les continuer.',
      one:
          'L\'échange $orders utilise cette clé de garage : sans elle, vous ne pourrez plus le continuer.',
    );
    return '$_temp0';
  }

  @override
  String get p2pGarageDeleteExternalUnread =>
      'Bull Wallet n\'a pas pu lire vos échanges : un échange en cours utilise peut-être cette clé de garage.';

  @override
  String get p2pGarageDeleteConfirm => 'Supprimer';

  @override
  String get p2pGarageNoticeTitle => 'Vos clés de garage';

  @override
  String get p2pGarageNoticeText =>
      'Votre clé de garage actuelle s\'appelle maintenant « Clé de garage externe ». Les clés de garage internes, sauvegardées par votre Bull Wallet, sont à côté : appuyez sur « Revenir aux clés de garage internes ».';

  @override
  String p2pGarageTradeInProgress(String orderId) {
    return 'Échange en cours #$orderId';
  }

  @override
  String p2pGarageKeyIsInternal(int index) {
    return 'C\'est déjà votre clé de garage interne n° $index.';
  }
}
