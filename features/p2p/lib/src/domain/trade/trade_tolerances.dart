/// Every tolerance of the checks of a trade, each with its reason (design note § 3.2, § 4.4, § 7 decision 4).
///
/// Change one only with its reason, and the tests around it: `trade_status_test.dart` checks each at its bound and one step past it.
abstract final class TradeTolerances {
  /// How far the sats of a trade may be from those of the amount at the book's price, as a fraction, both ways: 2 %.
  ///
  /// The coordinator fixes the sats at its own price at two moments after the book was read: when it makes the bond invoice, at the first read of the pre-take (`api/logics.py:1402-1404`), and when the bond locks, which freezes the trade (`:1332-1335`). Its price follows the market between them, so the sats move with it; 2 % covers the moves of a few minutes, to adjust after the first trials.
  /// Both ways, since a figure far from the order's, even in the user's favour, says the coordinator computed with other terms.
  static const double price = 0.02;

  /// The sats a figure of the coordinator may differ by from the same figure computed here in doubles: the coordinator truncates the bond (`int(...)`, `api/logics.py:1404`) and rounds the escrow and the payout (`round(...)`, `:666-668`, `:745-747`).
  static const int roundingSats = 1;

  /// The sats the implied taker fee may exceed the fee `/api/info/` announces by: the coordinator rounds the escrow and the payout to the sat (`api/logics.py:666-668`, `:745-747`).
  static const int feeSats = 1;

  /// How long an invoice must still be valid, at least, for this wallet to be asked to pay it: 60 s.
  ///
  /// The wallet pays through its swap service, which must create the swap, see the wallet's lockup and pay the invoice before it expires; how long that takes is not measured yet (#100, #8), and a taker bond lives 150 to 200 s in all (design note § 1.1). 60 s is a guess for the first trials, to replace with what they measure.
  static const Duration walletPaymentMargin = Duration(seconds: 60);

  /// How far two fiat amounts may be and still be the same: the coordinator keeps them with 8 decimals (`DecimalField(decimal_places=8)`, `api/models/order.py:77-84`, `api/models/take_order.py:8`).
  static const double fiatAmount = 5e-9;

  /// How far two percentages may be and still be the same: the coordinator keeps the premium and the bond size with 2 decimals (`api/models/order.py:91-96`, `:135-140`).
  static const double percent = 0.005;

  /// The highest taker fee `/api/info/` may announce for a take to be allowed, as a fraction of the trade: 1 %.
  ///
  /// The reference's default is 0.175 % (`FEE` 0.2 % × (1 − `MAKER_FEE_SPLIT` 0.125), `.env-sample:107-110`, `api/views.py:1042-1045`); the coordinators recorded on 2026-11-10 announce 0.17 % to 0.175 % on mainnet and 0.2625 % on testnet (`packages/robosats/test/fixtures/coordinator/*-info.json`). A fee checked only against what the coordinator itself announces would let it ask for anything: 1 % is about four times the highest seen, and a coordinator above it is refused before the take.
  static const double takerFeeCeiling = 0.01;

  /// How long after a deadline the coordinator's own loops have certainly acted on it: 1 minute.
  ///
  /// The order cleaner runs every 5 s (`api/management/commands/clean_orders.py:114-120`, it expires orders and pre-takes past their `expires_at`), and so does the invoice follower (`follow_invoices.py:27,33-34`, it settles or returns a bond that locked); a minute covers both with room for a slow coordinator.
  static const Duration coordinatorLoops = Duration(minutes: 1);

  /// How far ahead of the device's clock a stored trail's last read may be when the trade is resumed: 10 minutes.
  ///
  /// A phone corrects its clock from the network and may step it back by seconds or minutes between two runs of the app; a record from further ahead is not a clock step but a wrong record, and is refused.
  static const Duration clockStep = Duration(minutes: 10);

  /// The longest a pre-take can live when no answer has given its deadline yet: 30 minutes.
  ///
  /// A pre-take lasts the coordinator's taker-bond time (`EXP_TAKER_BOND_INVOICE`: 150 s by default in the code, `api/models/order.py:317-319`; 200 s in `.env-sample:167`), which nothing a taker reads before the pre-take states; 30 minutes is nine times the sample's, so that error 1044 right after a take becomes final within the hour even when the take's answer was lost.
  static const Duration longestPreTake = Duration(minutes: 30);
}
