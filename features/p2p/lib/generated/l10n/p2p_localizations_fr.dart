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
  String get p2pTorWaitingLine => 'Vos échanges passent uniquement par Tor.';

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
}
