import 'dart:async';

import 'package:flutter/widgets.dart';

/// What [MovedTapGuard] gives its builder: [onTap] wrapped so that a tap is ignored while the guarded widget has just moved; `null` stays `null`.
typedef GuardedTap = VoidCallback? Function(VoidCallback? onTap);

/// A guard for a button that pays: when the layout moves it (something above it or around it grows, shrinks, appears or goes, as an alert of the screen that comes or goes, or « Retry » that brings its answer), a tap on it is ignored for [afterMove], since it was aimed at what stood there a moment before (« Show details », « Go back »; security review of #268, C1 and C2). It is no lock: the button stays drawn and enabled, nothing is refused or announced, and the next tap after the delay goes through; each new move starts the delay again.
///
/// Its place is measured after every frame in the coordinates of the content of the nearest [Scrollable], not of the screen, so that scrolling the page (by the user, or by the screen bringing the button into view) never sets it off; its first place, when it appears, neither. Its delay is a [Timer], so that tests advance it with `tester.pump(duration)`.
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

  /// The guarded widget's top left in the content of the nearest [Scrollable] (its place in the viewport plus the scroll offset), or on the screen when nothing scrolls it.
  Offset? _placeNow() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null || viewport == null || !viewport.attached) {
      return box.localToGlobal(Offset.zero);
    }
    final position = scrollable.position;
    final scrolled = position.hasPixels ? position.pixels : 0.0;
    final inViewport = box.localToGlobal(Offset.zero, ancestor: viewport);
    return switch (position.axis) {
      Axis.vertical => inViewport.translate(0, scrolled),
      Axis.horizontal => inViewport.translate(scrolled, 0),
    };
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
