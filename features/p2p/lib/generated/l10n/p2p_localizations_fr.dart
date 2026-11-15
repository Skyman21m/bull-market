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
  String get p2pGarageWelcomeTagline =>
      'Une bourse d\'échange P2P LN simple et privée';

  @override
  String get p2pGarageWelcomeCreateRobot =>
      'Créer un nouveau robot et apprendre à utiliser RoboSats';

  @override
  String get p2pGarageWelcomeStart => 'Commencer';

  @override
  String get p2pGarageWelcomeRecoverHint =>
      'Récupérer un robot existant à l\'aide de votre clé de garage';

  @override
  String get p2pGarageWelcomeRecovery => 'Récupération';

  @override
  String get p2pGarageWelcomeSearchForOrders => 'Rechercher des ordres';

  @override
  String get p2pGarageWelcomeFastGenerateOrder => 'Générer un ordre rapidement';

  @override
  String get p2pGarageOnboardingStep1Title => '1. Générez votre clé de garage';

  @override
  String get p2pGarageOnboardingStep1Text =>
      'Votre clé de garage est une clé maîtresse dont dérive un nombre illimité d\'identités de robot. Générez-la une fois, utilisez-la pour toujours.';

  @override
  String get p2pGarageOnboardingStoreItTitle => 'Conservez-la en lieu sûr !';

  @override
  String get p2pGarageOnboardingStoreItText =>
      'Cette clé est la clé maîtresse de tous vos robots. Gardez-la secrète et sauvegardez-la en lieu sûr.';

  @override
  String get p2pGarageKeyHelper => 'Conservez votre clé de garage en sécurité';

  @override
  String get p2pGarageKeyInvalid => 'Clé de garage invalide';

  @override
  String get p2pGarageOnboardingPasteExisting =>
      'Ou collez une clé de garage existante pour récupérer vos robots.';

  @override
  String get p2pGarageOnboardingGenerateNew => 'Générer une nouvelle';

  @override
  String get p2pGarageOnboardingStep2Title =>
      '2. Découvrez votre identité robotique';

  @override
  String get p2pGarageTradingAvatar => 'Ceci est votre avatar d\'échange';

  @override
  String get p2pGarageHiMyNameIs => 'Bonjour, je m\'appelle';

  @override
  String get p2pGaragePreviousAccount => 'Compte précédent';

  @override
  String get p2pGarageNextAccount => 'Compte suivant';

  @override
  String get p2pGarageRobotLabel => 'Robot';

  @override
  String get p2pGarageOnboardingStep3Title => '3. Consulter ou créer un ordre';

  @override
  String get p2pGarageOnboardingStep3Text =>
      'RoboSats est une place de marché pair à pair. Vous pouvez consulter les offres publiques ou en créer une nouvelle.';

  @override
  String get p2pGarageOnboardingHelpIntro =>
      'Si vous avez besoin d\'aide dans votre parcours RoboSats, rejoignez notre entraide publique sur le';

  @override
  String get p2pGarageOnboardingHelpLink => 'groupe SimpleX';

  @override
  String get p2pGarageOnboardingHelpOutro =>
      'ou visitez l\'école des robots pour la documentation.';

  @override
  String get p2pGarageLearnRoboSats => 'Apprendre RoboSats';

  @override
  String get p2pGarageSeeProfile => 'Voir le profil';

  @override
  String get p2pGarageKeyLabel => 'Clé de garage';

  @override
  String get p2pGarageProfileDeleteAllTooltip =>
      'Supprimer la clé de garage et tous les robots';

  @override
  String get p2pGarageProfileDeleteAll => 'Tout supprimer';

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
  String get p2pDeleteKeyTitle => 'Supprimer la clé de garage ?';

  @override
  String get p2pDeleteKeyQuestion =>
      'Êtes-vous sûr de vouloir supprimer définitivement cette clé de garage et TOUS les robots associés ?';

  @override
  String get p2pDeleteCannotBeUndone =>
      '⚠️ Cette action ne peut pas être annulée !';

  @override
  String get p2pDeleteBeforeDeleting =>
      'Avant de supprimer, assurez-vous d\'avoir :';

  @override
  String get p2pDeleteKeyStoredKey =>
      'Conservé votre clé de garage en lieu sûr';

  @override
  String get p2pDeleteKeyNoActiveOrders =>
      'Aucun ordre actif ou en attente, sur TOUS vos robots';

  @override
  String get p2pDeleteExportedData => 'Exporté toutes les données importantes';

  @override
  String get p2pDeleteKeyConfirm => 'Supprimer la clé de garage';

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
  String get p2pGarageKeyHistoryNotRecorded =>
      'Cet appareil n’a pas pu enregistrer qu’il a généré cette clé de garage. Ses robots demanderont votre confirmation avant de rejoindre un coordinateur. Vous pouvez plutôt générer une nouvelle clé.';

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
      'Cette clé de garage a été collée, ou cet appareil n’a pas pu enregistrer qu’il l’a générée. Ses robots existent peut-être déjà chez des coordinateurs : l’application officielle RoboSats envoie chaque robot qu’elle affiche à tous les coordinateurs. Dans Bull Market, un robot ne vit que chez un seul coordinateur : si vous avez déjà utilisé cette clé, placez chaque robot chez le coordinateur où vous l’avez utilisé. Pour repartir de zéro, générez une nouvelle clé de garage.';

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
  String get p2pTakeSpecifyAmountFirst =>
      'Vous devez d\'abord spécifier un montant';

  @override
  String get p2pTakeSellingLater =>
      'La vente arrive dans une prochaine version.';

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
  String get p2pTakeKeyNotForTrades =>
      'Les robots d’une clé de garage collée ne peuvent pas prendre d’ordre ici. Générez une nouvelle clé de garage dans le Garage.';

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
  String get p2pTradeYouAreBuying => 'Vous ACHETEZ des BTC';

  @override
  String get p2pTradeCompatibleWallets => 'Voir Portefeuilles compatibles';

  @override
  String get p2pTradeCopyToClipboard => 'Copier dans le presse-papiers';

  @override
  String get p2pTradeHoldInvoiceBond =>
      'Ceci est une facture en attente, elle sera gelée dans votre portefeuille. Elle ne sera débitée que si vous annulez ou perdez un litige.';

  @override
  String get p2pTradeInvoiceQr => 'QR code de la facture de caution';

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
  String get p2pTradeTitleInfoGood => 'Vos informations sont correctes !';

  @override
  String get p2pTradeEscrowWait =>
      'Nous attendons que le vendeur verrouille le montant de la transaction.';

  @override
  String get p2pTradeEscrowWaitHangOn =>
      'Patientez un instant. Si le vendeur ne dépose pas, vous récupérerez automatiquement votre caution. De plus, vous recevrez une compensation (consultez les récompenses dans votre profil).';

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
    return 'Soumettre la facture pour $amountSats Sats';
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
  String p2pPayConfirmTitle(String amount) {
    return 'Payer $amount sats pour bloquer votre caution ?';
  }

  @override
  String p2pPayServiceFee(String serviceFee) {
    return 'Frais de swap : $serviceFee sats';
  }

  @override
  String p2pPayNetworkFee(String networkFee) {
    return 'Frais de réseau : environ $networkFee sats';
  }

  @override
  String p2pPayTotal(String total, String left) {
    return 'Total : $total sats. Reste dans Paiements instantanés : $left sats.';
  }

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
  String get p2pPayUnreadable =>
      'Bull Market ne peut pas lire où en est ce paiement.';

  @override
  String get p2pPayCancelNote =>
      'Un paiement de cette caution est en route depuis ce portefeuille. Annuler maintenant coûte les frais de swap, et le remboursement peut tarder.';

  @override
  String get p2pPayServiceRefunded =>
      'Swap échoué. Le swap a été remboursé. Les frais de swap ne sont pas remboursés.';

  @override
  String get p2pPayAskSupportExpired =>
      'Swap expiré. Les sats de cette caution sont peut-être sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pPayAskSupportExpiredSent =>
      'Swap expiré. Les sats de cette caution sont sortis de ce portefeuille. Contactez le support de Bull Bitcoin.';

  @override
  String get p2pEndChatBuyerHi =>
      'Dites bonjour ! Demandez les détails du paiement et appuyez sur « Confirmer l\'envoi » dès que le paiement est envoyé.';

  @override
  String get p2pEndBewareScams => '⚠️ Attention aux arnaques';

  @override
  String p2pEndConfirmSent(String amount, String currencyCode) {
    return 'Confirmer l\'envoi de $amount $currencyCode';
  }

  @override
  String p2pEndConfirmSentTitle(String amount, String currencyCode) {
    return '✅ Confirmez-vous avoir envoyé $amount $currencyCode ?';
  }

  @override
  String get p2pEndConfirmSentText =>
      'Confirmer permettra à votre pair de finaliser la transaction.';

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
    return 'Bull Market ne peut pas encore envoyer de déclaration de litige. Contactez $coordinator par l\'un de ses contacts ci-dessous, avec les informations qui identifient votre ordre.';
  }

  @override
  String p2pEndRewardsLater(String coordinator) {
    return 'Bull Market ne peut pas encore réclamer de récompenses : contactez $coordinator par l\'un de ses contacts ci-dessous.';
  }

  @override
  String p2pEndOrderId(String id) {
    return 'ID de l\'ordre : $id';
  }

  @override
  String p2pEndStepSendingRequest(String coordinator) {
    return 'Envoi de votre demande à $coordinator…';
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
}
