import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'no_robot_dialog.dart';

/// What « Search order » shows for an order URL that the books received do not hold, where the official client opens the page of the order, which asks its coordinator for it with the user's robot (`components/Dialogs/GoToOrder.tsx` at commit ff1998c).
///
/// No Garage Key stored for the network: the official client's « You do not have a Garage Key » ([NoRobotDialog]).
/// A Garage Key stored, or one that cannot be read, since a failure is not an absence: the official client's « This order is not available », the text of a coordinator's refusal to show an order (error 1044 of `api/errors.py`), and « Acknowledged », which closes it.
/// It opens at once and waits for [lacksGarageKey] meanwhile, as the vault takes a few seconds to believe that a slot is empty; an `Error` there is a bug, not caught, and leaves the wait.
/// A tap outside closes it, as in the official client.
class OrderSearchMissDialog extends StatefulWidget {
  /// Whether no Garage Key is stored for the network of the book (`BookCubit.lacksGarageKey`), asked once, when the dialog opens.
  final Future<bool> Function() lacksGarageKey;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  const OrderSearchMissDialog({
    super.key,
    required this.lacksGarageKey,
    this.onOpenGarage,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<bool> Function() lacksGarageKey,
    VoidCallback? onOpenGarage,
  }) => BullDialog.show<void>(
    context: context,
    builder: (_) => OrderSearchMissDialog(
      lacksGarageKey: lacksGarageKey,
      onOpenGarage: onOpenGarage,
    ),
  );

  @override
  State<OrderSearchMissDialog> createState() => _OrderSearchMissDialogState();
}

class _OrderSearchMissDialogState extends State<OrderSearchMissDialog> {
  /// The answer of the vault, `null` while it is awaited.
  bool? _lacksGarageKey;

  @override
  void initState() {
    super.initState();
    unawaited(_await());
  }

  Future<void> _await() async {
    final lacks = await widget.lacksGarageKey();
    if (mounted) setState(() => _lacksGarageKey = lacks);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return switch (_lacksGarageKey) {
      null => Padding(
        padding: const EdgeInsets.all(BullSpacing.lg),
        child: Center(child: CircularProgressIndicator(color: colors.primary)),
      ),
      true => NoRobotDialog(onOpenGarage: widget.onOpenGarage),
      false => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.p2pOrderNotAvailable,
              style: text.headlineLarge?.copyWith(color: colors.text),
            ),
            const Gap(BullSpacing.lg),
            BullButton.big(
              label: l10n.p2pCommonAcknowledged,
              onPressed: () => Navigator.of(context).pop(),
              bgColor: colors.primary,
              textColor: colors.onPrimary,
            ),
          ],
        ),
      ),
    };
  }
}
