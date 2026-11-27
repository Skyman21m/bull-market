import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/network_garage_key.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/last_orders_cubit.dart';
import '../../presentation/order_history_cubit.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../../presentation/robot_coordinator_cubit.dart';
import '../../presentation/robot_coordinator_state.dart';
import '../widgets/garage_key_clipboard.dart';
import '../widgets/robot_avatar.dart';
import 'account_navigator.dart';
import 'garage_reauthentication.dart';
import 'garage_key_card.dart';
import 'robot_nickname.dart';
import 'last_order_lines.dart';
import 'robot_coordinator_panel.dart';

/// The profile of the Garage, as the official client draws it (`basic/GaragePage/GarageKeyProfile.tsx` at commit ff1998c): the nickname, the avatar, the robot navigator, then the card of the Garage Key ([GarageKeyCard]), where the internal Garage Keys scroll, « New internal Garage Key » takes the place of « Delete All », and a button leads to the external Garage Key and back (#81).
///
/// The Garage Key is hidden until the user asks for it and passes the app's own re-authentication, the PIN the wallet asks before it shows its seeds, which [reauthenticate] brings from the shell; the official client shows it at once.
/// It is hidden again when the profile is left, when another key is shown and when the app goes to the background.
/// Without [reauthenticate] the key cannot be shown here at all.
/// Under the robot navigator, the panel of the robot shown ([RobotCoordinatorPanel]): the coordinator that knows it, if any, and what that coordinator says of its orders and rewards, with its own cubit for each robot, closed when the user moves to another robot.
/// The settings of the robot (Telegram, webhook, stealth invoices) and the claim of its rewards are not shown.
/// Under the navigator, « Last order #N » (#216, [LastOrderLines]): the reference's line of the robot shown, here read from the device's records, since each trade has a robot of its own; a tap shows that order's robot before its trade opens (#227, [GarageCubit.showOrderRobot]), so that the robot and the order on screen go together, as in the reference.
/// Above those lines, « Trade in progress #N » for each trade in progress of another Garage Key than the one shown, with its key, robot and coordinator (#81, decided on 2026-11-26), opening its trade with its own key.
/// Under those lines, « See history » (#253, an addition of Bull Market): the finished orders of every Garage Key of the network, each saying its key and its robot (#81), folded by default, each line opening its order as the lines above do.
class GarageProfile extends StatefulWidget {
  final GarageWithKey state;
  final GarageKeyClipboard clipboard;
  final P2pReauthentication? reauthenticate;

  /// Makes the cubit of the panel of the robot at an index of a Garage Key.
  final RobotCoordinatorCubit Function(NetworkGarageKey key, int index)
  robotCoordinator;

  /// Makes the cubit of the coordinator dialog, opened from « Select Host ».
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// Opens the trade of a « Last order #N » line (#216), read by the `LastOrdersCubit` above the Garage; `null`, and no such line, where the feature holds no trades.
  final Future<void> Function(TradeRecord record)? onOpenTrade;

  /// Makes the cubit of the history of finished orders of the key shown, under the « Last order #N » lines (#253); `null`, and no history, where the feature holds no trades.
  final OrderHistoryCubit Function(NetworkGarageKey key)? orderHistory;

  const GarageProfile({
    super.key,
    required this.state,
    required this.clipboard,
    required this.reauthenticate,
    required this.robotCoordinator,
    required this.coordinatorDetails,
    this.onOpenTrade,
    this.orderHistory,
  });

  @override
  State<GarageProfile> createState() => _GarageProfileState();
}

class _GarageProfileState extends State<GarageProfile> {
  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    final state = widget.state;
    final robot = state.robot;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.md),
      child: Column(
        children: [
          RobotNickname(nickname: robot.nickname),
          const Gap(BullSpacing.sm),
          Tooltip(
            message: l10n.p2pGarageTradingAvatar,
            child: RobotAvatar(seed: robot.hashId, size: 160),
          ),
          const Gap(BullSpacing.sm),
          AccountNavigator(
            index: robot.index,
            onPrevious: cubit.previous,
            onNext: cubit.next,
          ),
          // « Last order #N » under the robot navigator, where the reference puts it (`GarageKeyProfile.tsx:214-230`), from the device's records (#216); its robot shown first, then its trade opened (#227).
          if (widget.onOpenTrade case final open?)
            switch (widget.orderHistory) {
              // Under the lines, the history of the key shown (#253), with a cubit of its own for each key, made with the profile and closed with it: folded at each arrival in the Garage.
              final history? => BlocProvider<OrderHistoryCubit>(
                key: ValueKey(('history', state.key)),
                create: (_) => history(state.key)..start(),
                child: LastOrderLines(
                  historyKey: state.key,
                  keyNumbers: state.keyNumbers,
                  externalKey: state.externalKey,
                  inProgressElsewhere: state.inProgressElsewhere,
                  onOpen: (record) {
                    cubit.showOrderRobot(record);
                    return open(record);
                  },
                ),
              ),
              null => LastOrderLines(
                keyNumbers: state.keyNumbers,
                externalKey: state.externalKey,
                inProgressElsewhere: state.inProgressElsewhere,
                onOpen: (record) {
                  cubit.showOrderRobot(record);
                  return open(record);
                },
              ),
            },
          if (state.failure case final failure?) ...[
            const Gap(BullSpacing.xs),
            Text(
              failure.toTranslated(context),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const Gap(BullSpacing.md),
          // One cubit per robot shown and per key: moving to another robot closes it, which releases the robot.
          BlocProvider<RobotCoordinatorCubit>(
            key: ValueKey((state.key, robot.index)),
            create: (_) =>
                widget.robotCoordinator(state.key, robot.index)..load(),
            // The panel's read with no active order: the Garage may read the order of the record of the robot it opened on, once (#251, step 0).
            child: BlocListener<RobotCoordinatorCubit, RobotCoordinatorState>(
              listenWhen: (_, next) => switch (next) {
                RobotOnCoordinator(activity: RobotKnown(:final face)) =>
                  face.activeOrderId == null,
                _ => false,
              },
              listener: (_, _) => cubit.robotWithoutActiveOrder(robot.index),
              child: widget.onOpenTrade == null
                  ? RobotCoordinatorPanel(
                      nickname: robot.nickname,
                      network: state.network,
                      coordinatorDetails: widget.coordinatorDetails,
                      ordersNotServed: state.ordersNotServed,
                    )
                  // The orders the « Last order #N » lines open, so that the panel does not say them again (functional review of #220, R4).
                  : BlocBuilder<LastOrdersCubit, LastOrdersState>(
                      builder: (context, last) => RobotCoordinatorPanel(
                        nickname: robot.nickname,
                        network: state.network,
                        coordinatorDetails: widget.coordinatorDetails,
                        ordersNotServed: state.ordersNotServed,
                        lastOrdersShown: switch (last) {
                          LastOrdersListed(:final orders) => {
                            for (final record in orders)
                              (record.coordinatorAlias, record.orderId),
                          },
                          LastOrdersLoading() ||
                          LastOrdersUnreadable() => const {},
                        },
                      ),
                    ),
            ),
          ),
          const Gap(BullSpacing.md),
          // Built anew for each key: moving to another key hides the text of the one shown.
          GarageKeyCard(
            key: ValueKey(('card', state.key)),
            state: state,
            clipboard: widget.clipboard,
            reauthenticate: widget.reauthenticate,
          ),
        ],
      ),
    );
  }
}
