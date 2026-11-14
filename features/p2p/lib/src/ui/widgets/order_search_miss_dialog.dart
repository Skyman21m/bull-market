import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/order_search.dart';
import 'no_robot_dialog.dart';

/// What « Search order » shows for an order URL that the books received do not hold, where the official client opens the page of the order, which asks its coordinator for it with the user's robot (`components/Dialogs/GoToOrder.tsx` at commit ff1998c).
///
/// It opens at once and waits for [settle] (`BookCubit.settleSearchMiss`): for the book of the order's coordinator when it is still awaited, then for the vault, which takes a few seconds to believe that a slot is empty; an `Error` there is a bug, not caught, and leaves the wait.
/// The order found meanwhile closes it with that order, for the book to open its page.
/// A book that could not be had: « Coordinator offline », the feature's text for a coordinator that does not answer, and « Acknowledged », which closes it.
/// No Garage Key stored for the network: the official client's « You do not have a Garage Key » ([NoRobotDialog]).
/// A Garage Key stored, or one that cannot be read, since a failure is not an absence: the official client's « This order is not available », the text of a coordinator's refusal to show an order (error 1044 of `api/errors.py`), and « Acknowledged ».
/// The wait is as tall as that last answer, the most frequent, so that the card does not jump when it comes; the answer is announced to a screen reader.
/// A tap outside closes it, as in the official client, and abandons the search: nothing is read once it is gone.
class OrderSearchMissDialog extends StatefulWidget {
  /// The answer for the search, asked once, when the dialog opens, with whether the dialog is still there.
  final Future<OrderSearchMiss?> Function(bool Function() asked) settle;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  const OrderSearchMissDialog({
    super.key,
    required this.settle,
    this.onOpenGarage,
  });

  /// Opens the dialog; completes with the order found meanwhile, or `null`.
  static Future<PublicOrder?> show(
    BuildContext context, {
    required Future<OrderSearchMiss?> Function(bool Function() asked) settle,
    VoidCallback? onOpenGarage,
  }) => BullDialog.show<PublicOrder>(
    context: context,
    builder: (_) =>
        OrderSearchMissDialog(settle: settle, onOpenGarage: onOpenGarage),
  );

  @override
  State<OrderSearchMissDialog> createState() => _OrderSearchMissDialogState();
}

class _OrderSearchMissDialogState extends State<OrderSearchMissDialog> {
  /// The answer, `null` while it is awaited.
  OrderSearchMiss? _miss;

  @override
  void initState() {
    super.initState();
    unawaited(_settle());
  }

  Future<void> _settle() async {
    final miss = await widget.settle(() => mounted);
    if (!mounted || miss == null) return;
    if (miss case OrderSearchMissFound(:final order)) {
      Navigator.of(context).pop(order);
    } else {
      setState(() => _miss = miss);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return switch (_miss) {
      null || OrderSearchMissFound() => Stack(
        alignment: Alignment.center,
        children: [
          // Its size only: not read, not tapped, not focused.
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _message(context, l10n.p2pOrderNotAvailable),
          ),
          CircularProgressIndicator(color: colors.primary),
        ],
      ),
      OrderSearchMissOffline() => Semantics(
        liveRegion: true,
        child: _message(context, l10n.p2pCoordinatorOffline),
      ),
      OrderSearchMissNoGarageKey() => Semantics(
        liveRegion: true,
        child: NoRobotDialog(onOpenGarage: widget.onOpenGarage),
      ),
      OrderSearchMissNotAvailable() => Semantics(
        liveRegion: true,
        child: _message(context, l10n.p2pOrderNotAvailable),
      ),
    };
  }

  /// [title] and « Acknowledged », which closes the dialog.
  Widget _message(BuildContext context, String title) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.headlineLarge?.copyWith(color: colors.text)),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: P2pLocalizations.of(context).p2pCommonAcknowledged,
            onPressed: () => Navigator.of(context).pop(),
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ],
      ),
    );
  }
}
