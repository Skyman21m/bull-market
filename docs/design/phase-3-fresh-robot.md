# A fresh robot after a trade and for every take, issue #251: design note

**Status: written** (code on the branch `feat/p2p-fresh-robot`, « As the code wrote it » at the end of § 7). The design was written on 2026-11-25, before any code of [#251](https://github.com/Skyman21m/bull-market/issues/251), without any request to a coordinator or a relay, and without running the reference or the app.
Where the code later differs, the code and its pull requests are right, and this note is updated.
The owner decided the principle on 2026-11-20 (the issue's body): the Garage moves to a fresh robot after a successful trade, and an order is always taken with a robot that never served.
On 2026-11-25, on the mock-up of the Garage, he decided that the behaviour is the reference's, reproduced identically, including the moment the Garage moves to the next robot; that the Garage adds no line of its own when it moves, the reference's sentence on a robot involved in a trade staying (`p2pRobotUsedInTrade`); and that the order page may say, in one line, that a fresh robot is used for this order, only when the app changed robot by itself (issue #251, comment of 2026-11-25).
He recalled that the official app moves to the next robot as soon as an order is taken or made; § 1.8 checks that recollection against the code.
The five questions of § 6 were decided on 2026-11-25, each as recommended (§ 6).
Paths of the reference are those of RoboSats at commit babf62e (`frontend/src/…` for the client, `api/…` for the coordinator, `android/…` for the Android app); paths of the app are under `features/p2p/lib/src/` unless written otherwise.

## 1. The reference

### 1.1 Two modes of the Garage

The client's Garage has two modes, `legacy` (one token per robot, typed or generated) and `garageKey` (robots derived from one Garage Key by an account index, `models/GarageKey.model.ts:52-56`) (`models/Garage.model.ts:14`).
The model starts in `legacy` (`Garage.model.ts:63`), but « Generate » on a device without a Garage Key switches to `garageKey` and draws a key (`generateRobot`, `:539-545`), so a new user is in `garageKey` mode.
Every automatic move described below happens only in `garageKey` mode (`ensureReusableSlot`, `:239-241`); in `legacy` mode the robot never changes by itself, and the « change robot » button of the dialog of § 1.4 is disabled (`components/Dialogs/UsedRobotDialog.tsx:100-117`).
Bull Market's Garage is a Garage Key whose robots are numbered by index, so the `garageKey` mode is the one to compare with.
In that mode the robot shown in the Garage (the « current slot », `Garage.model.ts:75`, kept on disk with its account index, `:105-108`, `GarageKey.model.ts:129-135`) is the robot that makes and takes the next order: the make goes through `garage.getSlot()` (`Garage.model.ts:547-558`), the take through the same slot (`components/OrderDetails/TakeButton.tsx:328-338`).

### 1.2 When a robot counts as used

`Slot.isReusable` (`models/Slot.model.ts:293-309`) is the whole rule: a robot is reusable when it is not loading, has no active order, and has either no last order, or a last order whose status is known and is 4 (cancelled) or 5 (expired).
So a last order at 12 (collaboratively cancelled), 14 (successful trade), 17 or 18 (a dispute lost by one side), or of unknown status, makes the robot used; an active order makes it unusable for another order but not « used ».
The client moves an order from active to last at 4, 5, 12, 14, 17 and 18, or on any `bad_request` (`Slot.model.ts:216-223`, `:231-236`); 13, 15 and 16 stay active (the reference's own test, `models/__tests__/Garage.model.test.ts`, « keeps unsettled status %s active »).

**What the coordinator lets the client read.** `GET /api/robot/` gives `active_order_id` while the robot makes or takes an order in 0 to 3, 6 to 11 or 16, holds a live pre-take, or is the buyer at 13 or 15, and otherwise `last_order_id`, the last order it made or took (`api/views.py:727-737`, over `Logics.validate_already_maker_or_taker`, `api/logics.py:75-135`).
A pre-taker is not the order's taker until its bond locks (`order.taker` is set by `finalize_contract`, `api/logics.py:1326`), and a taker that cancels after its bond is removed again when the order goes back to the book (`publish_order`, `api/logics.py:1205-1219`): neither leaves a last order on the robot.
`GET /api/order/` answers error 1043 « This order has been cancelled » for an order at 4 **or** 12 (`api/views.py:259-260`, `api/errors.py:50`), never the status itself.
The client's `resolveBadRequestStatus` maps a `bad_request` containing « expired » to 5 and one containing « collaborativelly » to 12 (`Slot.model.ts:191-201`); the text of 1043 contains neither, and the web client hands the body of a 400 to the model (`services/api/ApiWebClient/index.ts:35-50`).
So, by reading the code and not by running it: a robot whose last order was cancelled, at 4 or at 12, is **used** in practice. Seen live, the order keeps the last status the client read before the cancel (never 4 or 5) with its status known (`Slot.model.ts:216-221`, `:242-254`); read after a restart, its status stays unknown (`ensureLastOrderStatus`, `:256-270`). The client's list `[4, 5]` and its tests (`Garage.model.test.ts`, « reconciles terminal status %s », which feed `{status: 4}` to the model) say the intent was « cancelled is reusable »; the coordinator never gives 4. An expired order is read with its status 5 and makes the robot reusable.

### 1.3 When the Garage moves by itself

`Garage.ensureReusableSlot` (`Garage.model.ts:233-298`) is the only automatic move. It is called:

- when the app starts, once the Garage Key, the mode and the slots are loaded, after clearing the manual navigation (`contexts/GarageContext.tsx:96-104`);
- each time the user opens the Garage page, after the robot is read again from every coordinator (`GarageContext.tsx:111-122`);
- after each poll of the active order while the Garage page is shown (`GarageContext.tsx:143-149`); the poll also clears the manual navigation when the order ends at 14, 17 or 18 (`:138-141`);
- after a recovery from the relays (`components/Dialogs/Recovery.tsx:76-80`, `basic/GaragePage/GarageKeyOnboarding.tsx:72-76`).

It moves nothing when the user moved with the arrows since (`manualNavigationActive`, `Garage.model.ts:247-254`, set by `nextAccount`, `previousAccount` and `setAccountIndex` called by hand, `:473-521`), when the robot shown has an active order (`:262-270`), or when it is reusable once its last order's status is resolved (`:276-285`).
Otherwise it takes `findNextUnusedAccount(current + 1)` (`:571-601`): the first index above the robot shown that has no slot on this device (taken at once, unchecked) or whose slot is reusable, within 100 indexes, beyond which it throws and nothing moves.
It then derives that robot, creates it and reads it on **every** coordinator of the federation (`createRobotFromGarageKey`, `:429-471`; `createRobot` builds one robot per coordinator alias, `:334-343`; `Slot.fetchRobot` reads them all, `Slot.model.ts:89-101`), and publishes the new account index to the Nostr relays (`publishAccountRecovery`, `Garage.model.ts:293-295`, `:523-537`).
Nothing is said to the user: the name, the avatar and « Robot #N » change (`basic/GaragePage/GarageKeyProfile.tsx:105-190`, `AccountNavigator.tsx:52-58`).

### 1.4 At the take and at the make

The reference never changes robot by itself at the take or the make. It asks.

- **Take.** « Take Order » on a robot that is not reusable opens the used-robot dialog instead of the take (`TakeButton.tsx:145-153`, `:392-401`): « Robot has an active order » or « Robot has completed a trade » (`UsedRobotDialog.tsx:45`); « This robot already has an active order in progress. » with « Each robot can only handle one order at a time. Switch to your next unused robot to take this order, or go back to manage the current one. », or « Each robot is a one-time identity. This robot has already completed a trade and cannot be used to take new orders. » with « You can switch to your next unused robot and take this order immediately, or go back. » (`:51-87`); for a range, « Your selected amount will be preserved after switching robots. » (`:88-92`); « Go back » and « Change Robot & Take Order » (`:96-115`). The latter moves to `findNextUnusedAccount(current + 1)` as a manual move, publishes the index, then takes; a failure says « Could not switch to a new robot. Please try again. » (`TakeButton.tsx:155-175`).
- **Make.** The same dialog, `action='make'`, when the robot shown has an order and is not reusable (`components/MakerForm/MakerForm.tsx:295-313`, `:666-673`), with « Change Robot & Create Order » (`:315-336`, `UsedRobotDialog.tsx:112-114`).
- **Renew** of a finished order refuses, in `garageKey` mode, a robot that is not reusable: « This robot was involved in a trade. Please navigate to a new account to create orders. » (`components/TradeBox/index.tsx:146-158`); after an expiry the same robot makes the order again.
- **« Start Again »** at the end of a trade only opens the create page (`TradeBox/Prompts/Successful.tsx:90-92`, `:270-273`): the robot changes there through the dialog above, or at the next visit of the Garage.

A take or a make with a reusable robot keeps that robot: during the trade it has an active order, and the Garage stays on it (§ 1.3).

### 1.5 What the old robot keeps

The old robot stays a slot of the Garage, reached by « Previous account » (`GarageKeyProfile.tsx:50-55`, `AccountNavigator.tsx:32-41`), with its « Last order #N » (`:214-230`), its « Claim Rewards » (`:232-240`) and, when it is not reusable and has no active order, the sentence « This robot was involved in a trade. Navigate to a new account for fresh privacy. » in an info alert and the avatar's tooltip, the avatar ringed in the error colour (`:144-179`).
The reference's « Last order #N » is the robot shown's own: after a move, the fresh robot shows none.

### 1.6 The coordinator

The coordinator forbids only a second active order: errors 1000 to 1003 (`api/logics.py:75-135`, `api/errors.py:3-6`).
A robot whose order ended at 4, 5, 12, 14, 17 or 18 may make or take again as far as the coordinator is concerned; « a robot is a one-time identity » is the client's rule.
A taker that does not lock its bond, or cancels its pre-take, is given a penalty that blocks its next take for a while (`kick_taker`, `api/logics.py:471-480`; error 1012), on that robot only.

### 1.7 The Android app

The Android app is the same client in a WebView: `android/AGENTS.md:4`, `:14`; `MainActivity.kt:445` loads `file:///android_asset/index.html`, the frontend's build with `window.RobosatsSettings = 'mobile-basic'` (`android/AGENTS.md:43`).
No Kotlin code reads or changes the robots, but for the notifications service, which reads the slots' Nostr keys (`android/app/src/main/java/com/robosats/models/NostrClient.kt:64-80`), and nothing in the files above depends on the client being mobile.
**Not established**: the bundle is not in the clone, so which frontend a given APK carries is not checked here; and how the Android HTTP bridge hands a 400 to the model (`services/api/ApiAndroidClient/index.ts:40-60`, then `WebAppInterface.kt`) was not followed to the end, so § 1.2's reading of a cancelled order holds for the web client and is assumed for Android.

### 1.8 The owner's recollection, checked

**Inexact as stated, and incomplete.** The official client does not move to a new robot because an order is taken or made: a take or a make with a robot that never served, or whose last order expired, keeps that robot for the order (§ 1.4).
What is right in it: when the robot shown has already served, « Take Order » and « Create Order » stop on a dialog whose main button changes robot then goes on, so to the user the robot changes at the moment of taking or making, after one more tap (§ 1.4).
What it misses: the Garage also moves by itself, with no tap, when the app starts, when the Garage is opened, and while it is shown, once the robot shown has a last order that ended in a trade, a cancellation or a dispute (or of unknown end), and never after an expiry (§ 1.2, § 1.3).

## 2. Bull Market today

### 2.1 Every trade already has a fresh robot

A take, a make and a renewal each reserve a robot through `TradeRobots.robotForNewTrade` (`domain/usecases/trade/take_order_usecase.dart:27`, `:640`; `make_order_usecase.dart:35`, `:506`; the renewal is a make, `ui/trade/trade_screen.dart:178`).
`InterimTradeRobots` gives the first usable robot of the network's Garage Key whose index has no binding to any coordinator, on either network, and no trade record, and binds it to the order's coordinator in the same statement (`domain/interim_trade_robots.dart:14-19`, `:30-85`; `data/trade_record_repository_impl.dart:28-51`).
Neither a binding nor a record is ever deleted, and the database refuses a second record of one robot (`domain/trade_record.dart:31`), so a robot is never used for a second order.
A key pasted in or acknowledged (`NewTradeStanding.keyDrawnHereOnly`, `trade_record.dart:223-249`) gives no robot for a trade at all (`GarageKeyNotForTradesFailure`, « The robots of a pasted Garage Key cannot take orders here. Generate a new Garage Key in the Garage. »). *Since #81 (decided on 2026-11-26) every key gives robots for trades, an imported one included, and that field, that failure and that text are gone (design note `docs/design/garage-key-from-the-words.md` § 3).*
**The robot shown in the Garage is never the one a trade uses**: the take and the make do not read it.
So the second half of the issue (« always with a robot that never served ») already holds, and holds more strictly than in the reference: a robot is never reused, not even after an expiry, a refused take or a reservation never sent.

### 2.2 What the Garage shows

| Case | Robot the Garage opens on (`GarageCubit._settle`, `presentation/garage_cubit.dart:287-341`) | While shown | Panel |
|---|---|---|---|
| An order made here in progress, its bond seen locked | its robot, the newest (`FollowMadeOrdersUsecase`, `domain/usecases/trade/follow_made_orders_usecase.dart:23-28`, `:88-103`; the owner's decisions of 2026-11-19, #227) | moves to the robot of each order made here whose bond is seen locked, until the user moves with the arrows (`garage_cubit.dart:51-52`, `:246-263`) | « Active order #N » |
| An order made here waiting for its bond | not followed | not followed | as below |
| A trade taken here in progress | not followed (only `TradeOrigin.madeHere` counts, `follow_made_orders_usecase.dart:94`) | not followed | as below |
| A trade ended, made or taken, of any end (succeeded, cancelled, expired, dispute) | the robot of the first « Last order #N » line, the newest end among the last order made and the last trade taken here (`follow_made_orders_usecase.dart:49-55`; `list_last_orders_usecase.dart:29-39`) | **stays**: a record that closes moves nothing | the coordinator's last order, and `p2pRobotUsedInTrade` whatever the end (`ui/garage/robot_coordinator_panel.dart:400-406`) |
| An order made here that ended while its page was closed | its record stays open, so the Garage stays on it as in progress, and it is in no « Last order » line until its page is opened (confirmed by the owner on his device, issue #251, comment of 2026-11-21) | as above | the coordinator's last order |
| No trade of the key | the first usable robot from index 0 (`garage_cubit.dart:310-312`) | | « No existing orders found », or « Select Host » for a robot no coordinator knows |
| The records cannot be read | the first usable robot from index 0, the lines saying `p2pRobotRecordsUnreadable` | | |

A tap on a « Last order #N » line shows that order's robot (`showOrderRobot`, `garage_cubit.dart:219-233`); the arrows show the next or previous usable robot (`:213-217`).
A robot reaches a coordinator from the Garage only through « Select Host » on the panel, which binds it; such a robot is then never used for a trade.

### 2.3 What the screens say of robots at a take

The order page says « Read by your robot at {time} » once « Take Order » has read the order with the reserved robot (`p2pTakeReadAt`, `ui/order_details_screen.dart:371`), and names no robot.
A reserved robot that the coordinator already knew is refused: « The robot chosen for this take already existed on {coordinator}. The order was not taken: try again. » (`p2pTakeRobotNotNew`); the next take reserves the next index.
« Start Again » is left out (`ui/trade/successful_panel.dart:27`, declared in `AGENTS.md`).

## 3. What « already served » means here

Two questions hide in « already served », and the reference answers both with `isReusable` because its robot shown is its trading robot:

1. **May the robot be used for a new order?** Here the answer is fixed and stays as it is: only a robot neither bound nor recorded (§ 2.1). Nothing in this note changes it.
2. **Should the Garage move away from it?** This is the reference's rule (§ 1.2, § 1.3), which the owner decided to reproduce. A robot is **served** when it has no trade in progress and its last order ended in a trade, a cancellation or a dispute, or its end is unknown; it is **not served** when it never had an order, when its last order expired, or when its take never started.

| State of a robot of a key drawn here | May trade here | Served (the Garage moves away) | The reference in the same case | Privacy |
|---|---|---|---|---|
| Never sent to a coordinator: no binding, no record | yes | no | no slot or a slot with no order: reusable | nothing known anywhere |
| Sent by « Select Host », no order | no (bound) | no | known to every coordinator, no order: reusable, it would trade with it | one coordinator knows a robot with no order |
| Reserved by a take not sent: the user backed out after the read of #119, or the take was refused before the coordinator acted (a wrong password, error 1045, #245; a penalty, 1012; 1000 to 1003) | no | no (no trade record confirmed, no « Last order » line, so the Garage never opens on it) | no `TakeOrder` or one expired, no last order: reusable, and reused | the coordinator saw the robot read one order |
| A pre-take that ran out or was cancelled (stored at `publicAgain` or `notAvailable`): its record was confirmed at the pre-take, a pre-taker reading as taker (`api/views.py:254`; `domain/usecases/trade/trade_reader.dart:722-729`, `:763-772`), so it is a « Last order #N » line once closed | no | no: the Garage opens on it when it is the newest line, as today | no last order (§ 1.2): reusable, reused | the coordinator saw it pre-take one order |
| An order made here waiting for its bond | no | no (in progress; not shown before its bond, the owner's decision of 2026-11-19) | active order: kept | |
| A trade in progress, made or taken, bond locked (1, 2, 6 to 11, 13, 15, 16) | no | no (in progress: the Garage opens on it) | active order: the Garage stays on it | |
| Ended in a successful trade (14) | no | **yes** | used: moves | the counterparty and the coordinator know the robot's trade |
| Ended in a dispute (17, 18) | no | **yes** | used: moves | as 14 |
| Ended cancelled, error 1043 (4 or 12, which neither client can tell apart) | no | **yes** | used in practice (§ 1.2) | as 14 when a counterparty was there, else as an expiry |
| Ended expired (5) | no | no | reusable: kept, renewed with the same robot | the book showed the order under the robot's name |
| A record closed whose end the trail does not tell (« End unknown » of #253) | no | **yes** | status unknown: used, moves | |
| A record still open whose order ended while the app did not read it | no | no until its end is read (§ 4.1, step 0) | the robot read again at each visit of the Garage resolves it (§ 1.3) | |
| The records cannot be read | the take refuses (`P2pStorageFailure`) | cannot be told: the Garage does not move | | |

For a key pasted or acknowledged, every robot may live elsewhere: it never trades here, and the Garage does not move by itself (§ 4.1).

**What each choice costs.**
Reusing a robot, as the reference does after an expiry, a refused take or a pre-take that ran out, ties the orders of that robot together at the coordinator, which sees one user behind them, and in the book, where the nickname is shown; never reusing one costs one index per take attempt or make, an index whose robot may be known to a coordinator without an order.
That cost falls on the recovery of #81: a scan of a key's indexes meets runs of robots with no order, and its gap limit must allow for them; it exists since phase 2 and this note adds none.
Moving the Garage costs nothing in privacy here, since the move is computed on the device and sends nothing (§ 5); in the reference each move creates the robot on every coordinator and publishes its index to the relays (§ 1.3).
A robot never reaches a second coordinator, by the rule « one robot, one coordinator » (`AGENTS.md`), so two coordinators can never link two trades by a robot.

## 4. The rule proposed

### 4.1 (a) The Garage

**Which robot the Garage shows.** A new pure function of the device's records gives it, read when the Garage is opened and again after each write of the records while it is shown, nothing asked of a coordinator (steps 1 to 4), in this order:

0. *(only if the owner answers yes to question 5)* when the robot it would open on has a record still open whose robot the panel's read says has no active order, the order is read once, as its page reads it when opened, and the record closes if it ended; the rule then runs again on the records as they are.
1. **A trade of the key in progress here, its bond seen locked**: the robot of the newest one (highest index), **made or taken**. Today only orders made here count (#227); a taken trade is added because the reference's robot shown is the one that took (§ 1.1). The owner's rule of 2026-11-19, never while an order waits for its bond, applies to both (`TradePosition.makerBondLocked`, `domain/trade/trade_edges.dart:88`, is true for a taker from 6 on).
2. **Else the newest finished trade of the key** (the first « Last order #N » line, when it is of the key): its robot when it is **not served** (§ 3: expired, or a take that never started), as today; when it is **served** (a trade, a dispute, a cancellation, an end unknown), **the fresh robot**.
3. **Else** the first usable robot from index 0, as today.
4. **Where the user left it by hand**: once the user moved with the arrows or tapped a « Last order #N » line, the Garage stays on that robot for the run of the app, and the steps above apply again only after a restart, or once a trade of the key ends at 14, 17 or 18 (the reference, `GarageContext.tsx:100`, `:138-141`; `Garage.model.ts:247-254`). The reference gives the hand back only when the active order of the robot shown ends at 14, 17 or 18 (`GarageContext.tsx:128-160` reads `garage.getSlot().activeOrder` only); here the end at 14, 17 or 18 of any trade of the key gives it back: a declared deviation. As the code wrote it, a trade's bond seen locked gives it back too (« As the code wrote it », § 7). Kept in memory, one object for the feature as `UnacknowledgedGarageKeys` is (`garage_cubit.dart:357-362`); today a visit forgets it when the Garage is left (`garage_cubit.dart:51-52`).

While the Garage is shown, a trade of the key that ends served moves it to the fresh robot at the next write of the records, as the reference's poll does on the Garage page, unless the user moved by hand.

**« The fresh robot »** is the robot the next trade would reserve: the first usable robot of the key whose index has no binding and no record, computed as `InterimTradeRobots` computes it (`_firstFreeRobot` over `NewTradeStanding.indexesInUse`, `interim_trade_robots.dart:115-146`), without reserving anything.
It is always above the robot of the trade that ended: each trade took the lowest free index, and nothing in use is ever freed.
The reference takes the first index above the robot shown that is new on the device or reusable (§ 1.3), which may be a robot it already sent everywhere; here a robot bound by « Select Host » is skipped, since it could not trade.
So in the ordinary case the robot shown is the one the next take or make will use, which is the reference's invariant.

**Index skipping and keys from elsewhere.** An index whose token or nickname a coordinator would refuse is skipped as the arrows and the trades skip it (`NetworkGarageKey.firstUsableRobot`); no « nickname already taken » can arise from the move, which sends nothing.
For a key pasted or acknowledged (`keyDrawnHereOnly` false), there is no fresh robot to trade with and the records hold no trade made or taken here with it: steps 1 and 2 never apply, and the Garage opens as today. The reference would move after reading the robot's last order on every coordinator; here a pasted key's robots are read only once bound (#79, open), so it would need that search first. Declared as a deviation. *Since #81 (decided on 2026-11-26) an imported key trades as any other, so it has its fresh robot and steps 1 and 2 apply to it as to every key.*

**When it cannot be computed.** Records that cannot be read: no move, the Garage opens on the first usable robot from index 0 and the lines say `p2pRobotRecordsUnreadable`, as today. A vault that cannot be read: as today. No usable index left: as today (`GarageRobotUnavailableFailure`), the Garage staying on the robot of the trade. A coordinator out of reach changes nothing: the move reads no coordinator.

**What the Garage says.** Nothing of its own: the name, the avatar, « Robot #N » and the panel change (a fresh robot has no binding: « Select Host », or the panel's text for a robot no coordinator knows); the « Last order #N » lines stay as they are (the issue's body); `p2pRobotUsedInTrade` stays and appears whenever the robot shown is served, so after « Previous account » to the robot of the trade.
One change to the sentence, to follow the reference: it is shown when the coordinator gives the robot shown a last order and no active order (as today), **except** when this device's records hold that very order for that robot with an end that is not served (an expiry, a take that never started), as the reference shows it only for a robot that is not reusable (`GarageKeyProfile.tsx:171-179`). An order this device does not hold (a pasted key's) keeps the sentence, as an unknown status does in the reference.
The reference's error ring and tooltip on the avatar are not reproduced (the panel's sentence carries it, as today).

### 4.2 (b) The take

**The robot**: unchanged. Every take reserves the first robot neither bound nor recorded (§ 2.1), whatever the Garage shows; no take ever uses a served robot, and none can.

**The line on the order page**, accepted by the owner on 2026-11-25, « only when the app changed robot by itself »: here that is when the robot reserved for the take is not the robot the Garage would show (§ 4.1) at the moment of « Take Order ».
That robot is computed **before** the reservation (after it, the reserved index is in use and the fresh robot is the next one: the line would always show), and kept with the preparation, so that preparing the same order again (`PreparedTakes.robotFor`, `domain/usecases/trade/prepared_takes.dart:21-27`) shows the same verdict.
In the ordinary case they are the same and nothing is said. The line shows when the Garage stays on a robot that will not trade: its last order expired, its take never started, another trade of the key is in progress (the reference's « Robot has an active order »), the user left the Garage on another robot by hand, or the robot shown was sent to a coordinator by « Select Host »; and when a concurrent reservation took the robot shown meanwhile.
It goes under « Read by your robot at {time} », with the reserved robot's nickname (`GarageRobotFace.of`, `presentation/garage_state.dart:109-129`), from the take's state, never from the Garage's cubit.
**The reference has no such line**: it asks before changing (§ 1.4). Its dialog would have here a single useful choice, since no take can use the robot shown; whether to keep the line or show the dialog is question 3.

### 4.3 A make and a renewal

A make and a renewal keep their fresh robot (§ 2.1).
The reference stops a make on the dialog of § 1.4 when the robot shown has served, and refuses a renewal after a trade (§ 1.4); here neither has a reason to (a renewal after a trade with a fresh robot was settled by #185 and #216).
The create form names no robot before the make, and the robot of an order made here appears in the Garage once its bond is locked (§ 4.1, step 1), which is where the reference shows it; whether to add the order page's line to the create form is question 4.

### 4.4 What the user sees, against the mock-up

| Mock-up of 2026-11-25 | This proposal |
|---|---|
| After a trade: the Garage moves alone; « Robot neuf. Le précédent a servi à l'échange #48213. » under the navigator (its question 4, option A) | the Garage moves alone; **no line** (the owner's decision of 2026-11-25); the move also happens after a cancellation, a dispute or an end unknown, never after an expiry |
| The « Last order » lines and « See history » stay | the same |
| « Previous account » brings back the old robot | the same, and the Garage then stays on it for the run of the app (§ 4.1, step 4) |
| At a take: « Robot neuf pour cet ordre : SilentOtter218. » under « Lu par votre robot », only when the app changed robot | the same line, shown when the robot of the take is not the robot the Garage would show; since every take already uses a fresh robot, that is after an expiry, a take that never started, another trade in progress, a move by hand or « Select Host », not « when the robot shown has been used » |
| Its question 6, « already served » = any trade, finished or in progress | § 3: in progress never moves the Garage; an expiry does not count; a cancellation and an end unknown do |

### 4.5 What the old robot still gives

« Previous account » shows it with its panel, its compensations (`p2pRobotRewards`; claiming them is #252, from the robot shown, so after « Previous account », as in the reference) and the reference's sentence.
Its « Last order #N » line, or its row of the history of #253, opens its trade screen, from which an order made here is renewed (with a fresh robot, #185, #216).
An open trade is reached from « Active trades » and its record (`TradeRobots.robotOfTrade`): nothing depends on the robot shown.

### 4.6 What it gives #253 and what it asks of it, and #81

- **#253** classifies how each finished order ended from the trail's last position (« Traded », « Expired », « Cancelled », « Dispute », « End unknown »). Step 2 of § 4.1 needs the same classification for the newest finished trade, plus « a take that never started » (`publicAgain`, `notAvailable`), which the reference counts as not served: one function of the domain for both, written once. If #253 merges first, this work reuses its table and adds that case; if #253 files such a take under « End unknown », the Garage reads the position itself for it.
- #253's rows name each order's robot (the owner's request of 2026-11-25), which answers the owner's remark on #251 (2026-11-21) that the « Last order » lines and the robot shown can differ with nothing to tell them apart: this note adds nothing to the lines.
- **A record whose end was never read** is #253's « End unknown » only once closed; while open it is not finished and is in no list, as today. Step 0 of § 4.1 (question 5) is the way this note proposes to close it.
- **#81** (keys derived from the wallet's seed): the rule reads indexes and records of the key in use and decides nothing about derivation, rotation or recovery; it sends nothing, so it publishes no index to relays (the reference's recovery event, § 1.3, is #79's and #81's to decide).
- **#216, #227**: the « Last order #N » lines and the tap that shows a line's robot are unchanged; step 1 widens #227's following to taken trades.

## 5. Threat model

**A hostile coordinator gains nothing from the move itself.** The move sends nothing: no request, no first contact, no relay event; a coordinator learns of a fresh robot only at its first take or make, as today. It cannot link robots by the time they were created (they are not created anywhere at the move, unlike the reference's, which reach every coordinator a few seconds after the previous trade's end, § 1.3), nor by an address or a session it never sees.
**What it can do.** The move follows what the trail stores, which is the coordinator's word: a coordinator that says an order ended in a trade moves the Garage, one that keeps saying it is in progress keeps the Garage on it. Both change only what the Garage shows. It cannot make the app consume robots by the move; it can, as today, make a take fail after its reservation, which costs one index per tap of the user.
**Step 0** (question 5) adds one read, over Tor, with the robot's token, to the coordinator that already knows that robot and its order, when the Garage opens on an open record whose order the panel already reads as not active: the read the order's page makes when opened. It reveals that the user opened the Garage at that time.
**Nothing depends on the robot shown.** Trades, bonds, escrows, payouts and compensations are reached from the records (`robotOfTrade`, `robotOfSlot`) and from the robot shown only for compensations, which stay reachable by « Previous account ». The reviews check that no use case reads the Garage's robot.
**Recovery on another device.** A key pasted there is a key from elsewhere: it never trades (§ 2.1), and the Garage there opens on robot 0. The fresh robots of this device are only indexes: nothing was created for them, so there is nothing to find until they trade. The robots that traded are found as today, by #79 and #81 (not built); the move changes nothing there. The official client given the same key would not learn this device's index, since nothing is published to the relays (an existing deviation, `AGENTS.md`).
**The Garage moving under the page of a trade** (security review of PR 274, C1). The Garage stays mounted under the pages pushed above the tab; when it left a robot, the panel of that robot closed and released it, and the release stopped every call of the robot, the watch and the chat of its trade's page above included: the page read nothing more and said « Cannot reach {coordinator} », wrongly, while a deadline of the trade could run (the bond of a trade just taken). It existed on `main` since #227 for two orders made here; this change widened it (trades taken here, a Garage left by hand that a bond locked gives back, a trade ending at 14, 17 or 18). The code now gives the calls of the Garage's panel an owner (`RobotCallOwner`), and a release stops only that owner's calls: a trade's calls (its watch, step 0's read, its chat, its actions) have none, go on, and keep the robot in use; the robot's Tor sessions are closed once nothing uses it any more (`RobotRequestLimiter.idle`, `ReleaseRobotUsecase`), never under a request to a coordinator in flight. The Nostr copies of a chat message are not counted: they go through the robot's Tor sessions outside the limiter and are not waited for, so when the Garage has left the robot of a trade, a copy sent just before the user leaves that trade's page may fail as the sessions close; the message itself still reaches the coordinator, and nothing is shown. It was already so before #274, whose release closed the sessions at once (security review of PR 274, R5; #275).
**Known limits** (security review of PR 274): after an automatic move the panels of two robots of the key may read their robot one after the other (R1). The vault is read once more per preparation of a take, for the Garage's robot (`GarageRobotUsecase`), and once more per step 0, for the robot of the order read (`TradeReader.open`, `InterimTradeRobots.robotOfSlot`); the Garage Key is held for the call only, in a local variable, never kept in a state (R2). A coordinator that hides `active_order_id` in its answer to `GET /api/robot/` and answers « expired » to `GET /api/order/` has the record of an order still public closed at the mere opening of the Garage (step 0), without the « Expired » screen being seen: the order leaves « Order » for « Last order #N » and the history, and the app no longer follows it, so a take of it would go unseen; it could already do so when the order's page was opened, and the order stays reachable from its « Last order #N » line and the history (R4; the owner's decision 5 kept, #275).
**Logs**: nothing new is logged; a robot's index, nickname or token never is.

## 6. Questions for the owner

**Decided by the owner on 2026-11-25** (issue #251, comment of that day), each as this note recommended: 1 A (after an expiry the Garage stays on its robot); 2 A (a robot serves for one order only, a declared deviation); 3 A (the line on the order page, not the reference's dialog); 4 A (nothing on the create form); 5 A (the Garage reads such an order once when it opens). The questions as they were asked:

1. **After an order that expired, the Garage: stay on its robot, as RoboSats, or move to a fresh robot as after a trade?** RoboSats stays, because there that robot may serve again. Here it never serves again, so the next take uses a fresh robot and the order page says so. A: stay, identical to RoboSats (recommended, your decision of 2026-11-25). B: move after an expiry too; the Garage then always shows the robot of the next order, a difference from RoboSats.
2. **Keep our rule that a robot serves for one order only?** RoboSats reuses the robot of an expired order, of a take refused or abandoned, and of a pre-take that ran out. Bull Market never reuses a robot, since phase 2. A: keep (recommended: no two orders tied together by one robot; changing it would touch how robots are kept, which needs your agreement and two reviews). B: reuse as RoboSats.
3. **At a take, the line you accepted, or the RoboSats window?** RoboSats asks, in a window (« Change Robot & Take Order » or « Go back »), when its robot has served. Here a take can only use a fresh robot, so the window would offer one useful choice. A: the line « Robot neuf pour cet ordre : … » (recommended, your answer of 2026-11-25). B: the RoboSats window, word for word, then the take with a fresh robot.
4. **At the creation of an order, say it too?** RoboSats has the same window when creating. Here nothing names the robot before the order is sent, and the order's robot appears in the Garage once its bond is locked. A: nothing (recommended). B: a line on the create form naming the robot that will be used.
5. **An order that ended while the app was closed keeps the Garage on its robot until its page is opened. Should the Garage read it by itself?** RoboSats reads the robot again each time the Garage is opened. A: the Garage reads that order once when it opens on it, as opening the order would (recommended: one request through Tor to the coordinator that already knows that robot). B: nothing, as today.

## 7. Work plan

**Slices**, each a pull request with two separate independent reviews (functional, then security and privacy), since they touch robots and the take:

1. **Domain, no screen.** The end of a finished trade from its trail's last position (shared with #253, § 4.6), « served » as § 3; `NextTradeRobot` (the fresh robot of a key without reserving: `firstFreeAmong` and `newTradeStandingOf`, the same code as `robotForNewTrade`, so that the two can never disagree); `GarageOpening`, the pure rule of § 4.1, steps 1 to 3, over the active trades with their standing, the « Last order » lines with their ends and that robot; `FollowMadeOrdersUsecase` widened to taken trades (renamed `FollowTradesUsecase` or kept, as the author judges). Files: `domain/usecases/trade/follow_made_orders_usecase.dart`, `domain/interim_trade_robots.dart` (the free-index function made reusable), new files in `domain/` and `domain/usecases/`, `locator` wiring.
2. **The Garage.** `GarageCubit` opens on `GarageOpening`, moves on a served end while shown, keeps step 4 in a feature-wide object (`GarageNavigation`), `showOrderRobot` and the arrows recorded there; the panel's sentence rule of § 4.1 (`robot_coordinator_panel.dart:400-406`, given the records' end of the robot's last order). Files: `presentation/garage_cubit.dart`, `presentation/garage_state.dart`, `ui/garage/garage_profile.dart`, `ui/garage/robot_coordinator_panel.dart`. No new text.
3. **The order page.** `TakeOrderCubit` computes the Garage's robot before the reservation (`GarageOpening` and `GarageNavigation`), keeps the verdict with the preparation, and shows the line under `p2pTakeReadAt` when the reserved robot differs; the same on `UnlistedOrderScreen` (#245). Files: `presentation/take_order_cubit.dart`, `ui/order_details_screen.dart`, `ui/take_order_section.dart`, `lib/l10n/p2p_en.arb`, `p2p_fr.arb`.
4. *(question 5, A)* **Step 0**: one read of an open record's order from the Garage, through the trade's reader as its page reads it, once per visit, then the rule again. Touches the trade reader's callers, never its writes.

Questions 3 B and 4 B would each add a slice (the dialog with the reference's texts, `UsedRobotDialog.tsx:45-115`; a line on the create form).

**Texts.** None for the Garage. The order page's line is the project's own, the reference having none: French as on the mock-up the owner accepted, « Robot neuf pour cet ordre : {nickname}. », English proposed « A fresh robot for this order: {nickname}. » (`p2pTakeFreshRobot`), read out when it appears; the 20 other languages get the generated English fallback. `p2pRobotUsedInTrade` keeps its words; its description in `p2p_en.arb` is corrected (it says that any last order counts as a trade).

**Tests**, with `ScriptedCoordinator` and the in-memory database, never a real coordinator:

- the rule over each row of § 3, for a made and a taken trade: 14, 17, 18, 1043, an end unknown move; 5, `publicAgain`, `notAvailable` stay; in progress never moves; a pending take, a make waiting for its bond and a reservation never sent are never opened on; a key pasted or acknowledged never moves; records unreadable;
- the fresh robot: equal to the robot the next `robotForNewTrade` reserves, on a key with skipped indexes, with a robot bound by « Select Host » above and below the last trade, with a reservation never sent; always above the robot of the trade that ended;
- the Garage by real gestures on the real composition (`P2pFeature().route` on `setUpP2pForTesting`), in English and in French: opened after a successful trade shows the next robot and keeps the « Last order » line; a trade ending while the Garage is shown moves it; « Previous account » then leaving and coming back keeps the old robot; a restart, or another trade ending at 14, applies the rule again; an expired order keeps its robot; the sentence shown for the robot of a trade and of a cancelled order, not for an expired one;
- the take: no line in the ordinary case; the line after an expiry, with another trade in progress, after a move by hand, after « Select Host »; the same verdict when the same order is prepared again; the take's robot never the Garage's when that one is bound;
- the capture test of the Garage and of the order page (`test/features/p2p/p2p_screens_capture_test.dart`), required by the CI.

**Mutants to kill**: the Garage moving after an expiry; not moving after 1043 or an end unknown; moving while a trade is in progress; following a taken trade before its bond locks; the fresh robot computed from the robot shown plus one instead of the free indexes (a robot bound by « Select Host » shown as fresh); the fresh robot computed after the reservation at the take (the line always shown); the verdict computed again at a second preparation; the hand navigation forgotten when the Garage is left, or kept across a trade ending at 14; a key from elsewhere moved; the sentence shown for an expired order of this device, or hidden for an order this device does not hold; any use case reading the Garage's robot; a coordinator request at the move.

**What the reviews check.** Functional: § 3 row by row against the reference's lines; the moment of the move against § 1.3; the lines of the mock-up and the owner's answers of 2026-11-25. Security and privacy: no request and no relay event at the move; the take's robot unchanged (`robotForNewTrade` and the schema untouched); nothing reachable from the robot shown alone; step 0's single read; nothing logged.

**As the code wrote it.** The four slices are four commits of one branch. `OrderEnd.served` (`domain/order_history.dart`) adds to #253's table the one distinction it lacked, a take that never started (`publicAgain`, `notAvailable`) has not served; the history shows the same words. `NextTradeRobot.of` (`domain/next_trade_robot.dart`) is the computation `InterimTradeRobots.robotForNewTrade` reserves, called by it, and the fresh robot of the Garage. `GarageRecords`, `GarageOpening` and `GarageNavigation` (`domain/garage_opening.dart`) are the rule of § 4.1, steps 1 to 3, and step 4; `FollowTradesUsecase` replaced `FollowMadeOrdersUsecase` (the trades in progress, the closed records with their trail's last position, and `NextTradeRobot` over the standing read again after each list). The first « Last order #N » line is taken from the closed records ordered as `watchTrades` orders them (by `taken_at`, then index), which may differ from the lines only for two records closed at the same microsecond. `GarageCubit` opens on `GarageNavigation.robotOf` and applies it after each write of the records; records that cannot be read move nothing. Step 4 differs from § 4.1 in one case the note did not name: a trade of the key whose bond is seen locked after the user left the Garage by hand gives the hand back to the rule, for any move by hand, the arrows as well as a tap on a « Last order #N » line, so that the Garage then shows the robot of the trade that has just started. For the tap this is what #227 did (a renewal is always opened from such a line, and the owner's decisions of 2026-11-19 show its robot once its bond locks). For the arrows it is a change from #227 while the Garage is shown: on `main` the arrows kept the hand until the Garage was left, and a bond locked meanwhile did not move it before the user's eyes. The reference does not move by itself after the arrows (`models/Garage.model.ts:473-521`, `contexts/GarageContext.tsx:128-160`); it is already on the robot of the trade because its take and make use the robot shown. To confirm with the owner. And, as § 4.1 now says, the end at 14, 17 or 18 of any trade of the key gives the hand back, where the reference reads only the active order of the robot shown. The panel's sentence follows § 4.1 (`GarageWithKey.ordersNotServed`). The take's screens read `GarageRobotUsecase` before calling the preparation and hand its answer to the use case, which keeps only whether a robot it reserves differs (`PreparedTakes`), never reads the Garage itself, and puts the nickname on `PreparedTake.freshRobot`; a robot kept for the order keeps its first verdict; an order by its URL reserves its robot at its read (`readUnlisted`) and keeps the verdict there. Step 0 is `GarageCubit.robotWithoutActiveOrder`, called by the profile when the panel of the robot opened on reads it with no active order, once per visit, through `WatchTradeUsecase.readOnce`: the trade's own watch, one read, then the end of the subscription, and nothing when another subscription reads the trade. After the security review of PR 274 (C1), the Garage's panel releases only its own calls (`RobotCallOwner`, § 5), a trade's calls going on, and the robot's sessions are closed when the robot is idle; step 0 is not run for a robot whose panel reads an active order (R3, a route test). Found on the way: `Stream.first` waits for the cancellation of the database's watches, which the take's screen must not wait for (`GarageRobotUsecase` takes the first value and cancels without waiting); the name `trades` is the repository's alone (`robot_bindings_architecture_test.dart`), so the cubit's records are `tradesOf`.

**To tell the owner before his trial**: the Garage changes robot after a trade, a cancellation, a dispute or an order of unknown end, never after an expiry, with no sentence; « Previous account » shows the old robot, and the Garage stays there until the app restarts or another trade ends; the order page says « Robot neuf pour cet ordre » only when the robot of the take is not the one the Garage shows; nothing is sent when the Garage changes robot; the official app given the same Garage Key does not learn which robot this app is on.

## 8. Not established

- The reference was read, not run: § 1.2's « a cancelled order makes the robot used » follows from the code of the client and the coordinator, against the client's own list and tests, which say the intent was the opposite for 4.
- The Android app's bundle and its HTTP bridge's handling of a 400 (§ 1.7).
- That a pre-take that ran out is always a confirmed record, so a « Last order #N » line: read from `showsTaker` (`domain/usecases/trade/trade_reader.dart:763-772`) and the coordinator (`api/views.py:254`), not run; a path where the pre-take was never read would leave it unconfirmed and out of the lines, and the rule keeps the Garage on its robot either way.
- What #253 will write for such a take and for a record of an old schema (§ 4.6). Established by its code: such a take is « End unknown » in the history, a record without a trail or with one not read back too; `OrderEnd.served` keeps the first not served and the second served.
- Step 0 was run against `ScriptedMakerCoordinator` only: one read of an order cancelled or expired while the app was closed, the record closed, the Garage moved or kept; not against a real coordinator.
