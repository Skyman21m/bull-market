# Phase 3 — A taken order compared with the Bull wallet's price, issue #249: design note

Decided by the owner on 2026-11-20 (« Oui pourquoi pas »): the payment rule he decided on 2026-11-17 for orders made here (`docs/design/phase-3-making-an-order.md` § 3.3) applies to orders taken here too.
This note settles, before any code, where a taker sees it, what is compared at each step and with which figures, and what it cannot do.
Paths of the reference are those of RoboSats at commit babf62e; paths of the app are under `features/p2p/lib/src/` unless written otherwise.

## 1. Today

**For a maker**, three comparisons with the Bull wallet's price exist, each information and never a lock:

- the maker bond and a maker seller's escrow, in the confirmation of « Pay with this wallet » (`PayBondFromWalletUsecase.rateOfBond`, `domain/usecases/trade/pay_bond_from_wallet_usecase.dart:130-173`; `WalletRateCheck.ofMakerBond`, `.ofMakerEscrow`, `domain/trade/wallet_rate_check.dart:38-83`);
- a maker buyer's payout, before « Submit » and before « Confirm … sent » (`CheckPayoutRateUsecase`, `domain/usecases/trade/check_payout_rate_usecase.dart`; `WalletRateCheck.ofMakerPayout`, `wallet_rate_check.dart:86-111`);
- the coordinator's price in the create form, before the make (`MakePriceCheck`, `domain/trade/make_price_check.dart`; `CheckMakePriceUsecase`).

**For a taker, nothing is compared with the Bull wallet's price**: `rateOfBond` answers `Ok(null)` for a `TakenSide` (`pay_bond_from_wallet_usecase.dart:145-146`), so the confirmation of the bond and of a taker seller's escrow (`_Confirmation`, `ui/trade/bond_payment_panel.dart:389-509`) shows no rate line; `CheckPayoutRateUsecase.termsOf` answers `null` for any trade not made here (`check_payout_rate_usecase.dart:27-31`), so a taker buyer's payout shows none either.

**What protects a taker today**, all against the coordinator's own price:

- the take is built from the order as the taker's robot read it just before the take and as the user saw it (`TradeTerms.takeRead`, `domain/trade/trade_terms.dart:186-212`; `TakeOrderUsecase.prepare` and `confirm`, #119), and its sats must stay within `TradeTolerances.price` (2 %) of the page's;
- the state machine checks, against the price of that read (`TakenSide.bookPrice`, premium included): the bond within 2 % (`BondAmountOutsideOrder`), the trade's sats fixed at the bond's lock within 2 % (`TradePriceOutsideOrder`), the escrow or the payout equal to `trade_satoshis`, and the implied fee within the announced taker fee (`TakerFeeAboveAnnounced`), `domain/trade/trade_status.dart:830-889`;
- the wallet pays at most `TradeTerms.bondCeiling` and `TakenSide.escrowCeiling` (`trade_terms.dart:75-81`, `:409-416`).

A coordinator that announces a false price *consistently* (its book, its bond, its trade sats) passes every one of these: the read is the coordinator's word.
The Bull wallet's price is the only reference the app has that does not come from the coordinator.

**What is already kept**: every figure the rule needs is in the taker's terms, stored at the take since phase 2 (`trade_terms`, `TradeTermsRecord` version 1, `data/p2p_tables.dart:159-218`): the amount taken (a range's amount chosen), the premium, the sats of an order priced in sats, the bond size, the book's price and the taker fee.
Nothing new needs storing, and an order taken before the version that brings the rule is covered as soon as its terms are readable.

**What the book says of the price today**: the book's rows show the premium (`OfferRow`, `ui/widgets/offer_row.dart:145-164`), which for an order priced in sats is the one the coordinator computes at its own price (`api/views.py:809-812`); the order details show « Price and premium » (the coordinator's price with the premium, `p2pOrderPriceAndPremium`, `ui/order_details_screen.dart:386-404`) and « You will receive / send … Sats (Approx) », and after « Take Order » the same figures from the robot's read with the bond estimate and its ceiling (`_Figures.ofRead`, `:433-463`).
Every one of them is the coordinator's figure; none is compared with anything outside it.

## 2. The reference

**How the coordinator fixes what a taker pays and receives.**

- The trade's sats are `calc_sats(amount, exchange_rate, premium)` = amount ÷ (rate × (1 + premium)) × 10⁸, truncated (`api/logics.py:256-275`); for an order priced in sats, the maker's sats whatever the price (`:264-265`), with a premium computed from the coordinator's rate and truncated to two decimals (`:277-295`).
- `exchange_rate` is the coordinator's median of several public sources (`api/utils.py:302-345`), cached 30 s and refreshed every minute (`robosats/celery/__init__.py:51-54`).
- The taker bond is made at the pre-taker's first read: `int(satoshis_now(order, take amount) × bond_size / 100)` (`api/logics.py:1402-1404`), on the amount taken, not on a range's maximum as the maker bond is.
- **The price is frozen when the taker bond locks** (`finalize_contract`, `api/logics.py:1332-1335`: « THE TRADE AMOUNT IS FINAL »); before that, the sats follow the coordinator's rate.
- A taker seller's escrow is `round(last_satoshis × (1 + taker fee))` (`api/logics.py:733-749`); a taker buyer's payout is `round(last_satoshis × (1 − taker fee))` (`:650-669`), the taker fee being 0.175 % by default.
- What a taker reads: as a non-participant, `price_now`, `premium_now` and `satoshis_now` of the whole order (`api/views.py:288-299`); as a pre-taker, the bond and its sats (`:381-396`); from 6, `trade_satoshis` (the escrow for a seller, the payout for a buyer) in every status but 9 (`:345-371`).

**What the official client shows a taker**: the coordinator's price and premium (`frontend/src/components/OrderDetails/index.tsx:461-490`), sats estimated from `satoshis_now` (`:192-215`), the book's price as `/api/limits/` price × (1 + premium) (`BookTable/index.tsx:418-437`), « Lock {{amountSats}} Sats » with `bond_satoshis` and `escrow_satoshis` (`TradeBox/index.tsx:382`, `:431`, `:482`, `:500`), and « Submit invoice for {{amountSats}} Sats » (`TradeBox/Forms/LightningPayout.tsx:558`).
It compares nothing with any price outside the coordinator.
The whole rule is a deliberate deviation from the reference, the owner's, as it is for a maker.

## 3. What is compared, step by step

**The figure expected** is the same at every payment, from the terms kept here only: the amount taken (`TakenSide.amount`) at the Bull wallet's price of the moment with the order's premium kept here (`TradeTerms.premium`), exactly, as `MakerTerms.satsAtPrice` computes it for a maker (`domain/trade/maker_terms.dart:332-341`); for the bond, times the bond size.
In the owner's example (a Bull wallet's price of 71,657 USD, a sell order at +3.5 %, 100 USD taken): 134,834 sats expected (134,834.5 exactly), a bond of 3 % of 4,045 sats (4,045.035).

| When | Who | The coordinator's figure | Compared with | Unfavourable side, red beyond 10 % | Follows from |
|---|---|---|---|---|---|
| The order page, once « Take Order » has shown the robot's read (nothing sent yet, no bond) | taker buyer, taker seller | the coordinator's price of a bitcoin without the premium: the read's price (`TakenSide.bookPrice`) ÷ (1 + premium) | the Bull wallet's price, as the create form compares it (`MakePriceCheck`) | as the form's rule (`MakePriceCheck.warnsFor`): a buyer both ways (above: fewer sats received; below: a larger bond; both ways being the form's choice by the coordinator of the work, not the owner's), a seller below (a larger bond and more sats locked) | the page's sats and bond estimate are this price applied to the amount |
| The bond, in the confirmation of « Pay with this wallet » (status 3) | both | the quote's invoice, the amount the wallet pays (`bond_satoshis`) | the bond expected: bond size × the amount taken at the Bull wallet's price with the premium | above (as the maker bond) | a fraction of the trade: for a seller, a bond too large means a trade too large; for a buyer, a trade too small shows as a bond too *small*, which this line does not warn of (the order page does, above) |
| The escrow, in the confirmation of « Pay with this wallet » (6, 7) | taker seller | the quote's invoice (`escrow_satoshis`, `last_satoshis` and the taker fee) | the amount taken at the Bull wallet's price with the premium | above | the taker fee shows in the gap: with the example's figures for a buy order, an honest escrow of 135,070 sats reads +0.18 %; red from 148,318 |
| The payout, before « Submit » (6, 8) | taker buyer | the invoice the payout panel asks (`PayoutAsk.buyerSats`, `trade_satoshis`) | the same | below | the taker fee shows in the gap: in the example an honest payout of 134,598 sats reads −0.18 %; red at 121,351 and below |
| « Confirm … sent » (9) | taker buyer | `satoshis_now` (`last_satoshis`) less the taker fee of the terms, compared with the smallest invoice this app saw asked at 6 or 8, as for a maker buyer | the same | below | at 9 the coordinator gives no `trade_satoshis` (`api/views.py:345-371`) |

A taker seller at 9 and later has nothing to compare, as a maker seller.

**What differs from a maker, and why.**

- **The decisive moment is before the bond locks.** A maker's sats are fixed up to 24 hours after the creation, often while the app is closed, so its comparisons at the payments are its only look at the price. A taker's are fixed by its own bond's lock, minutes after it saw them (§ 2), and walking away before that costs nothing (the pre-take runs out, or a cancel's 60-second penalty, the phase 2 note § 1.4); from 6 on, walking away costs the bond. So the order page and the bond carry the protection; the escrow's and the payout's lines tell the user what was fixed, and the market's move since.
- **A taker buyer's unfavourable side is not the bond's.** The maker's rule reads a bond as « more costs », which holds for a seller, maker or taker. For a taker buyer, a coordinator's price 20 % too high gives a bond of 3,370 sats (−16.69 %), no alert at the bond, then a payout of 112,165 sats (−16.81 %), red only once the bond is locked. The order page's line (+20.00 %, red for a buyer) is what tells it in time; this is why this note recommends it (§ 7).
- **The premium is the maker's**, chosen at the creation; the taker accepted it when it saw it on the page and it is kept in the terms from the robot's read. The rule compares with *that* premium, never with one read again.
- **A range**: the amount is the one the taker chose, kept in the terms; one contract only, so none of the maker's per-contract amounts (`trail.takenAmount`, `TradeSeen.contractAmountMoved`) applies.
- **An order priced in sats**: the sats are the maker's and the coordinator cannot move them (`TradePriceOutsideOrder` against `explicitSatoshis`); the premium kept is the coordinator's `premium_now`, computed at its own rate. With the same formula, the gap then measures how far the coordinator's rate is from the Bull wallet's, which is how far the premium the taker saw is from the premium against the Bull wallet's price: a red line says that the price the taker accepted is more than 10 % worse than it was shown to be. The same rule, said in the work's tests with an example.
- **The fee** is the taker's (at most 1 %, `TradeTolerances.takerFeeCeiling`), not added to the figure expected, so that it shows in the gap, as the maker fee does.

## 4. Edge cases

- **The Bull wallet's price unreadable** (no network, the service down, an answer outside the bounds of a price): nothing compared, the coordinator's price never cited, « rate not checked » in the warning colour with « Retry », everything still possible: the owner's decision of 2026-11-17, as for a maker. On the order page, the form's line for it.
- **A currency the Bull wallet does not price** (all but USD, CAD, CRC, EUR, MXN, ARS, COP): no figure; today the line of #181 in the warning colour. For an order made here the owner decided on 2026-11-20 a grey « not priced » line and an orange alert only when the rate at the take is more than 10 % worse than at the creation (#250, not applied yet). **The equivalent for a taken order is the grey line alone**: a taker's « creation » is the read it took on, and the state machine already warns, at 2 % rather than 10 %, when the bond or the trade's sats move from that read (`BondAmountOutsideOrder`, `TradePriceOutsideOrder`). No new alert; this note recommends it.
- **An order taken before this version**: its terms are kept (§ 1), so the rule applies to it from the first screen of the new version; records that cannot be read give no comparison, as for a maker (`TradeNotOpened`).
- **An order reached by its URL (#245)**: the same page, the same read (`prepareUnlisted` builds the terms from the robot's read); the Bull wallet's price is read at « Take Order » as for an order of the book, never when the page opens, though the robot reads the order then.
- **A pre-take run out, then taken again**: a new take, a fresh robot, a new read and new terms (`TakeOrderUsecase`), so a new comparison; a read changed under « Take Order » (`TakeOrderChanged`, `TakePreparationGone`) is compared again, with the Bull wallet's price already read when it is less than 3 minutes old (nothing sent then), as the create form does.
- **The price moving between the take and a payment**: the reference freezes the sats at the bond's lock (§ 2); the Bull wallet's price is read at the moment of paying, as the owner's rule says. The escrow comes within the escrow's time (30 minutes to 10 hours), « Confirm … sent » up to 24 hours after: an honest move of the market of more than 10 % then shows red, as it does for a maker; the trial script says so.
- **A premium of −100 %**, which `Premium.tryCreate` accepts (`packages/robosats/lib/src/coordinator/order_values.dart:159-160`): a price of zero, no figure expected: « rate not checked », never a division.

## 5. Where it shows

The existing lines, unchanged in their place and their words.
No new text: the rewording of all these alerts is #250, which waits for the owner's approval of « Textes à valider »; whatever #250 gives the maker's lines (« Bull Wallet », « prix Bull », the two-line alert) the taker's get with the same keys.

| Where | Widget | Texts reused word for word |
|---|---|---|
| The order page, under « Price and premium » once the read is shown | `PublicOrderDetailsCard` through `TakeOrderDetailsCard` (`ui/take_order_section.dart`), on `TakeOrderSection` and `UnlistedOrderScreen`; state in `TakeOrderCubit` | `p2pMakeRateCompare`, `p2pMakeRateReading`, `p2pMakeRateUnverified`, `p2pCommonRetry` |
| The bond's confirmation | `BondPaymentPanel` → `_Confirmation` → `_RateLines` | `p2pPayRateWallet`, `p2pPayRateWarning`, `p2pPayRateNotPriced`, `p2pPayRateUnverified`, `p2pCommonRetry` |
| A taker seller's escrow confirmation | the same `_Confirmation`, whose `_RateLines` takes the escrow's keys at the escrow step (today only `_EscrowConfirmation` uses them) | `p2pPayRateWalletEscrow`, `p2pPayRateWarningEscrow`, and the bond's `NotPriced` and `Unverified` lines |
| A taker buyer's payout and « Confirm … sent » | `PayoutRateLines` (`ui/trade/payout_rate_line.dart`) in `PayoutPanel` and the dialog of « Confirm … sent » (`LiveDialogLines`), from `PayoutRateCubit` | `p2pPayoutRateReading`, `p2pPayoutRateWallet`, `p2pPayoutRateWarning`, `p2pPayoutRateNotPriced`, `p2pPayoutRateUnverified`, `p2pPayoutRateSatsMissing`, `p2pPayoutRateToldMoved`, `p2pPayoutRateToldNow` |

**Current texts that do not fit a taker word for word**, for #250:

- `p2pMakeRateBelow`, `p2pMakeRateBelowSell`, `p2pMakeRateAbove`: « … when the order is taken », « Check it before creating the order. »;
- `p2pMakeRateNotPriced`: « … before creating the order. »;
- `p2pPayoutRateWalletAsked` (9, the invoice kept compared alone): « the {amount} {currency} asked here »: a taker asked nothing; until #250 the taker's line takes `p2pPayoutRateWallet`, whose « You receive {received} sats » is the invoice this app saw asked;
- `p2pPayoutRateNotSeen` is never reached by a taker (a contract seen late is a maker's case).

So the order page's red lines and its line for a currency not priced need #250's words; the bond, escrow and payout need none.
The gap from the rate at the creation (`RateGapLine`) stays a maker buyer's only.

## 6. What it does not protect against

- **A coordinator that lies within the threshold**: up to 10 % from the Bull wallet's price on the unfavourable side, plus the state machine's 2 %, is never red; on a trade of 100 USD, about 13,500 sats more locked by a seller or fewer received by a buyer, said only as a gap.
- **The Bull wallet's price itself**: one third party, read outside Tor over HTTPS from Bull Bitcoin's price API (`api.bullbitcoin.com`); a wrong price there gives a false alert or hides a coordinator's lie. Each read tells that service the IP address, the time and the currency; the order page's read adds a moment, « Take Order », a sign of an intent to take a given currency, which the coordinator sees at the same time over Tor: only an operator who sees both could tie them. The owner accepted the same reads for a maker on 2026-11-17.
- **A currency the Bull wallet does not price**: only the coordinator's own word, checked against itself at 2 %.
- **A payment from another wallet**: the bond and escrow lines live in the confirmation of « Pay with this wallet »; a bond or an escrow paid from the QR code is compared on the order page only.
- **A red line after the bond's lock**: it informs; not paying the escrow, or not giving a payout, loses the bond (3 % by default). Nothing in the app says « do not pay » (the owner's decision of 2026-11-20).
- **The coordinator's custody**: it holds every hold invoice's preimage and can settle an escrow of honest size unfairly; no price rule changes that.
- **Never a lock**: every line is information; the user may take, pay, submit and confirm whatever it says.

## 7. Decisions for the owner

One only, the rest following from his rules of 2026-11-17 and 2026-11-20.

1. **Show the comparison on the order page, once « Take Order » has read the order, before the take is sent?**
   This note recommends yes: it is the only moment a taker buyer is told of a price too high while walking away is still free, it shows whatever wallet then pays the bond, and it is the form's comparison before a make, which the owner called « bonne idée ».
   Yes costs one line on a page already full (red only beyond 10 %), a read of the Bull wallet's price outside Tor at « Take Order » even when the user then goes back, and the warning sentences to be written in #250, so that slice comes last.
   No costs nothing on the page, but a taker buyer then learns of a price too high only once the bond is locked; the bond's line would then have to warn a buyer of a bond too small, with a new text.

## 8. Work plan

**Slices**, each a pull request with the label `money`:

1. **Domain**: the exact computation shared by both sides (`satsAtPrice` of an amount, a premium and a price, moved out of `MakerTerms` into a pure function of `domain/trade`, a premium of −100 % and a price outside the bounds giving `null`); `WalletRateCheck.ofTakerBond`, `.ofTakerEscrow`, `.ofTakerPayout` (or the maker's three taking the amount, premium and bond size); `TakenSide.payoutAt` with the taker fee; `rateOfBond` answering for a `TakenSide` at both steps. No screen yet.
2. **The bond and a taker seller's escrow**: `_Confirmation` shows the rule for a taker, `_RateLines` choosing the escrow's keys at the escrow step.
3. **A taker buyer's payout**: `CheckPayoutRateUsecase.termsOf` giving a taker's terms too (a sealed type over `MakerTerms` and `TakenSide`), `subjectAt` without the maker's per-contract cases, `PayoutRateCubit` and `TradeScreen` unchanged otherwise.
4. **The order page** (if the owner says yes, after #250's words): `TakeOrderCubit` reads the Bull wallet's price once the read is shown, through `CheckMakePriceUsecase` as it is, at most once per 3 minutes per currency and on « Retry », never when the page opens; « Continue » pressed during the read waits for it and stops when the line changed, as « Create order » does (#181); `MakePriceCheck.warnsFor` given the taker's own side.

**Tests**, with the fake wallet port (a price read, not priced, unavailable) and `ScriptedCoordinator` playing a taker's coordinator, never a real one: the owner's example at each step and its bounds (4,449 and 4,450 sats for the bond; 148,317 and 148,318 for the escrow; 121,351 and 121,352 for the payout), a coordinator's price 20 % too high and 10 times too low for each role, a range taken below its maximum, an order priced in sats with a coordinator's rate 15 % off, a premium of −100 %, a currency not priced, a price unreadable then « Retry », a trade taken before the version (terms of version 1 written by a phase 2 fixture), the read changed under « Take Order », and an order reached by its URL.

**Mutants to kill**: the side inverted (`pays` and `receives`; the taker's side given to `warnsFor` as the order's type instead of the user's: a taker of a buy order is a seller); `>` for `≥` at the threshold; the bond size left out or applied to the escrow; a range's maximum in place of the amount taken; the premium's sign; the maker fee in place of the taker fee; the figure expected computed from `TakenSide.bookPrice` instead of the Bull wallet's price (a gap of zero, always); the price read when the page opens; `rateOfBond` answering `null` again for a taker.

**Reviews**: two, separate and independent, with no prior context: functional first, then security, on each slice.

**For the trial script** of the APK that brings it: the threshold unmeasured; seven currencies only; a bond or escrow paid from another wallet is compared on the order page only; an honest move of the market of more than 10 % before « Confirm … sent » shows red; the reads outside Tor; a red line after the bond's lock leaves only a choice between paying and losing the bond.
