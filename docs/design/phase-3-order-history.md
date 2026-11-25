# Phase 3 — The history of finished orders (#253): design note

An addition of Bull Market, declared as such: the RoboSats reference (commit babf62e) has no history. Its Garage shows one « Last order #N » per robot (`frontend/src/basic/GaragePage/GarageKeyProfile.tsx`), and this app shows two such lines read from the device's records (#216, `docs/design/phase-3-making-an-order.md` § 2.2). The owner asked on 2026-11-21 to see more of them and to tell those that ended in a trade from the others; he decided on 2026-11-25, on the mock-up of the Garage (`docs/maquettes/garage-robot-neuf-historique.html` in the project's folder, not in this repository), where the history opens, how many lines it shows, what each line says and the words. This note settles in writing what « End unknown » covers, before any code, as he asked.

## 1. What the records keep of the end of an order

- A trade record (`trades`, `TradeRecord`) keeps times only: when it was written (`taken_at`), when its order was confirmed (`confirmed_at`), when it was closed (`closed_at`). It keeps no status: what the coordinator says of the order is read again from the coordinator.
- How an order ended is in its trail alone (`trade_trails`, `TradeTrailRecord.position`): the position of the last status this device read and stored, one of `TradePosition`. A trail only moves forward, never leaves an end (`TradeTrailRecord.whyNotReplace`, the trigger `trade_trails_forward`), and is never written again once its record is closed (`trade_trails_closed`).
- So the end of a finished order is the position of its stored trail, and the day of its end is the record's `closed_at`: the time this device read the end, which may be later than the time the coordinator ended the order (the phone off, the app closed).

## 2. What counts as finished

- **Finished**: a record closed (`closed_at` set) after its order was confirmed (`confirmed_at` set), made here or taken here: the very rule of the « Last order #N » lines (`ListLastOrdersUsecase.lastOrdersOf`).
- **Not an order**: a take or a make that never happened (closed without a confirmation: `closeNeverSent`, `TakeOrderUsecase._notMade`, `_closedUnsent`, `closePendingMake`), and a pending make, which has no order id. None is in the history.
- **In progress**: a record not closed. It is in « Order », the list of the active trades of the tab (`ActiveTradesCubit`, `ActiveTradesSheet`), never in the history, whatever its trail says. That includes an order that ended at its coordinator while this device did not read it (the phone off, the coordinator unreachable, the app closed): its record stays open until a read shows the end, at its next opening, and it is never shown in the history as finished. It includes too a trade whose coordinator left the federation list (`TradeCoordinatorGone`): it can be shown, never read again, so it stays in progress.
- **A trade recovered from a pasted key** (origin `recovered`) is left out, as from the « Last order #N » lines: it was neither made nor taken here, and no code writes one yet (`TradeRecordRepository.recordRecoveredTrade` has no caller, #79).
- **Another Garage Key**: the history lists the orders of the Garage Key shown and of the network shown only (the robot's key fingerprint, `RobotSlot.keyFingerprint`). The two « Last order #N » lines above it are left as they are, read from every key of the network.

## 3. For which records the end is known

The code closes a confirmed record only once an end is on disk:

- `TradeReader.keep` closes a record when the status it keeps is terminal and stored, or when the trail kept on disk is terminal;
- `TradeReader.closeAtEnd` closes a record whose stored trail already holds an end, when the app was killed between the trail and the close;
- every other close (`closeNeverSent`, `_notMade`, `_closedUnsent`, `closePendingMake`) is of a take or a make never confirmed, which is no order (§ 2).

So for a finished record written by this code since schema 4 (every APK given to the owner is of schema 8 or 9), the stored trail is at one of the seven terminal positions (`TradePosition.isTerminal`). Five of them say how the order ended; two do not.

| Stored position (the reference's status) | The line says | Why |
| --- | --- | --- |
| `succeeded` (14) | **Traded** · « Échangé » | the trade went through |
| `expired` (5) | **Expired** · « Expiré » | the order expired, at whatever step |
| `cancelled` (error 1043: cancelled by one side, 4, or both, 12) | **Cancelled** · « Annulé » | the order was cancelled |
| `makerLostDispute` (17), `takerLostDispute` (18) | **Dispute** · « Litige », in orange | the order ended by a dispute's resolution, whoever won it |
| `publicAgain` (taken here only) | **End unknown** · « Fin inconnue » | this robot is no longer a participant: the time to lock its bond ran out, its pre-take was cancelled, or it cancelled alone or let its step run out after its bond locked (`PreTakeEnded`, `BondForfeited`); the order went back to the book, and how it ends is not this device's to know |
| `notAvailable` (taken here only) | **End unknown** · « Fin inconnue » | the coordinator no longer shows the order to this robot (error 1044): another robot locked its bond first, or the order left the book otherwise (`TakenByAnother`, `BondForfeited`, `StatusUnknown`); how it ended is not known |
| any other position, no trail, or a trail this code does not read | **End unknown** · « Fin inconnue » | see § 4 |

A line says « Dispute » only when one side lost the dispute (17 or 18). A dispute the coordinator resolves otherwise ends at another status, which the line says as any order ending there: when the coordinator gives everything back to both sides, the order is cancelled and the line says « Cancelled »; when it settles the dispute as a trade, the line says « Traded ». So « Dispute » is never shown for those, though a dispute was opened (#273).

The last two terminal positions fit none of the four words that say an end: this device knows that its own part ended, not how the order did. They are never given an affirmative word; « End unknown » is what is true of them, and a sixth word is the owner's to decide (the pull request asks him).

A trail that recorded a breach of trust (`breached`) is drawn by its position all the same: the trade screen the line opens says the breach.

## 4. For which records the end is not known, and why

« End unknown » is shown for a finished record in exactly these cases, and only these:

1. **Its robot dropped out of the order** (`publicAgain`, `notAvailable`, § 3): the end of this device's part is known, the end of the order is not. The only case a trial will meet.
2. **No trail is stored**: a file of schema 3, whose trades had no trail yet (schema 4, #87, added them). No APK was ever of schema 3; a developer's file only.
3. **A trail this code does not read back**: a stored value of another type than this code writes, a version it does not know (a file written by a later version of the app, opened again by this one), a position it does not know, or a trail of another order, coordinator, network or role than its record. The database's constraints and triggers refuse all of these; a damaged file or a later version could still hold one.
4. **A trail at a position that is no end** on a closed record: no path of this code writes one (§ 3); a record closed by an earlier version of the code, or a damaged file, could hold one.

What « End unknown » does **not** cover: an order whose last read is older than its end. Its record is not closed, so it is not in the history (§ 2); the maquette's own line « when the app could never read the end (phone off, coordinator unreachable) » describes an order that stays in « Order » until its end is read.

A line whose end is unknown opens its order as every line does: the trade screen says what it says of the stored trail (« This order is not available », « This trade is over for this robot. », the trail that cannot be restored, …).

## 5. What the history reads, and when

- From the device only, nothing asked of a coordinator, nothing written: one statement over `trades` and `trade_trails` (`TradeRecordRepository.watchClosedTrades`), every closed record of the network with an order id and the last position of its trail, read again after each write of either table. No schema change.
- It is read from the moment the Garage shows its profile, as the « Last order #N » lines are, not from the moment the history opens: the link « See history » shows only when the history holds an order the two lines do not show, which the read decides, and reading the trails' position in the same statement costs nothing a second read would save. Nothing is drawn of it until the user opens it.
- The robot of each line is named from the Garage Key shown and the robot's index (`NetworkGarageKey.robotOf`, as « Last order #N » finds the robot it shows, #227): « Robot #N » as the account navigator writes it, and its nickname. An index the key does not give back as it is leaves the line with « Robot #N » alone; the history is never drawn without a key (the profile is shown only with a key read from the vault, so a locked vault shows no history at all).
- The newest end first (`closed_at`, then the higher order number, then the higher robot index), ten lines, then « See more », which adds ten at each tap while some are left.
- Records that cannot be read: the app's line that says so (`p2pRobotRecordsUnreadable`), never « no order ».

## 6. Privacy

- Folded at each arrival in the Garage, never remembered open: folded when the Garage is left, when a page covers it (a line tapped opens its order: coming back, it is folded), and when the app is hidden or paused, as the Garage Key shown is hidden then.
- The whole Garage is protected from screenshots, screen recording and the recent apps' preview (`PrivacyScreen` on `GarageView`) while the wallet's « Screen Privacy » is on: the history is inside it, so it follows that setting as the Garage Key does, with nothing of its own.
- Nothing logged: no order number, no robot name, no coordinator. The records print their robot without its key, and the history's values print counts or their type only: the cubit's state its counts, `ClosedTrade` and `FinishedOrder` their type alone (#273; they printed their record before).
