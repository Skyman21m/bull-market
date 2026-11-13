import 'dart:async';

import 'package:flutter/widgets.dart';

/// Closes the dialog or the sheet it is in once [until] completes: what the robot panel opened (« Robots from elsewhere », « Select Host », « Send {nickname} to {coordinator}? », and the coordinator dialog behind an info button of « Select Host ») goes away with it, so that it never stays above a Garage it does not belong to (another robot, another key or network, the Garage left).
///
/// Its own route is removed, whatever sits above it, at once and without its animation, and the future its opener awaits completes with `null`, as a dismissal: nothing is recorded or sent (security review of step 6).
class ClosesWithPanel extends StatefulWidget {
  /// Completes when the panel that opened the route is gone.
  final Future<void> until;

  final Widget child;

  const ClosesWithPanel({super.key, required this.until, required this.child});

  @override
  State<ClosesWithPanel> createState() => _ClosesWithPanelState();
}

class _ClosesWithPanelState extends State<ClosesWithPanel> {
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    // Out of the frame that disposed the panel: a navigator cannot change while the tree is locked.
    unawaited(
      widget.until.then((_) {
        final route = _route;
        if (!mounted || route == null || !route.isActive) return;
        route.navigator?.removeRoute(route);
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
