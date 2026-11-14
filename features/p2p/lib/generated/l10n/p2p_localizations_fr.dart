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
}
