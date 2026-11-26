import 'dart:async';

import 'package:flutter/widgets.dart';

/// What [MovedTapGuard] gives its builder: [onTap] wrapped so that a tap is ignored while the guarded widget has just moved; `null` stays `null`.
typedef GuardedTap = VoidCallback? Function(VoidCallback? onTap);

/// A guard for a button whose tap matters (« Pay », « Continue » before a take, and since #283 the « Confirm » of the dialog « Confirm … sent », the one tap that cannot be undone; « Submit », « Generate Invoice » and the chat step's « Confirm … sent » have none, the user's own gestures moving them just before their natural tap, review of #283, C2): when the layout moves it (something above it or around it grows, shrinks, appears or goes, as an alert of the screen that comes or goes, or « Retry » that brings its answer), a tap on it is ignored for [afterMove], since it was aimed at what stood there a moment before (« Show details », « Go back »; security review of #268, C1 and C2). It is no lock: the button stays drawn and enabled, nothing is refused or announced, and the next tap after the delay goes through; each new move starts the delay again.
///
/// Its place is measured after every frame on the screen with the scroll offsets of every [Scrollable] around it added back, so that scrolling (by the user, between tabs, or by the screen bringing the button into view) never sets it off, while a move of the layout does; one move is not seen, where the scroll offset changes with it by as much (the page scrolled to its end whose content under the button shrinks, so that the page is scrolled back: #267); its first place, when it appears, is only recorded. Its delay is a [Timer], so that tests advance it with `tester.pump(duration)`.
class MovedTapGuard extends StatefulWidget {
  final Widget Function(BuildContext context, GuardedTap guard) builder;

  const MovedTapGuard({super.key, required this.builder});

  /// How long a tap is ignored after a move: long enough for a tap aimed at what was there before the move, short enough that a second tap, aimed at the button now in view, pays.
  static const afterMove = Duration(milliseconds: 700);

  @override
  State<MovedTapGuard> createState() => _MovedTapGuardState();
}

class _MovedTapGuardState extends State<MovedTapGuard> {
  /// The place of the guarded widget in the scrolled content at the last frame; `null` before its first frame.
  Offset? _place;
  Timer? _moved;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void dispose() {
    _moved?.cancel();
    super.dispose();
  }

  /// Measures the place after each frame while mounted. A post-frame callback schedules no frame: nothing runs while the screen is still.
  void _watch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final place = _placeNow();
      final last = _place;
      if (place != null) {
        if (last != null && (place - last).distance > 0.5) {
          _moved?.cancel();
          _moved = Timer(MovedTapGuard.afterMove, () {});
        }
        _place = place;
      }
      _watch();
    });
  }

  /// The guarded widget's top left on the screen, with the scroll offset of every [Scrollable] around it added back along its axis: a scroll (of the page, between tabs, of a nested list, or the screen bringing the button into view) leaves it unchanged, and a move of the layout changes it, whatever the structure of the page; a move the scroll offset follows by as much (content under the widget that shrinks at the page's end) leaves it unchanged too (#267).
  Offset? _placeNow() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    var place = box.localToGlobal(Offset.zero);
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    ) {
      final position = scrollable.position;
      final scrolled = position.hasPixels ? position.pixels : 0.0;
      // Scrolling by d moves the content by d against the axis direction.
      place += switch (position.axisDirection) {
        AxisDirection.down => Offset(0, scrolled),
        AxisDirection.up => Offset(0, -scrolled),
        AxisDirection.right => Offset(scrolled, 0),
        AxisDirection.left => Offset(-scrolled, 0),
      };
    }
    return place;
  }

  VoidCallback? _guard(VoidCallback? onTap) => onTap == null
      ? null
      : () {
          // Just moved: the tap was aimed at what stood here before. Ignored, said nowhere; the button stays enabled.
          if (_moved?.isActive ?? false) return;
          onTap();
        };

  @override
  Widget build(BuildContext context) => widget.builder(context, _guard);
}
