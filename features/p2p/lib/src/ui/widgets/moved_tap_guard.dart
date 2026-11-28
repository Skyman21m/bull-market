import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What [MovedTapGuard] gives its builder: [onTap] wrapped so that a tap is ignored while the guarded widget has just moved; `null` stays `null`.
typedef GuardedTap = VoidCallback? Function(VoidCallback? onTap);

/// A guard for a button whose tap matters (« Pay », « Continue » before a take, since #283 the « Confirm » of the buyer's dialog « Confirm … sent », the declaration that the fiat was sent, since #293 the « Confirm » of the seller's dialog « Confirm … received », which releases the escrow, and since #298 the button that goes on of the dialogs a second tap on the button that opened them can reach as they open (« Confirm Cancel » at 6 and 7, which loses the bond, « Confirm cancellation », « Ask for Cancel » or « Accept Cancelation », « Renew anyway »), and since #301 « Agree and open dispute »; « Submit », « Generate Invoice » and the chat step's « Confirm … sent » have none, the user's own gestures moving them just before their natural tap, review of #283, C2): when the layout moves it (something above it or around it grows, shrinks, appears or goes, as an alert of the screen that comes or goes, or « Retry » that brings its answer), a tap on it is ignored for [afterMove], since it was aimed at what stood there a moment before (« Show details », « Go back »; security review of #268, C1 and C2). It is no lock: the button stays drawn and enabled, nothing is refused or announced, and the next tap after the delay goes through; each new move starts the delay again.
///
/// Its place is measured after every frame on the screen with the scroll offsets of every [Scrollable] around it added back, so that scrolling (by the user, between tabs, or by the screen bringing the button into view) does not set it off, while a move of the layout does. Android's stretch at the end of a scroll (`StretchingOverscrollIndicator`) is no scroll: it moves the content under the button for real while the scroll offset stays at its end, so that a fling that hits the end of a list sets it off (« Pay » ignores taps for about a second after a fling that hits the page's end, and a seller's dialog taller than the screen, flung to its end, ignores « Confirm » for about 0.6 s; functional review of #296, C1 and R1), which is the safe side: the stretch does move « Go back » and « Confirm », stacked 8 points apart. When it appears (the confirmation opened, the dialog opened, the card built anew as when the tab « Contract » is shown again), its first measure starts the delay too ([armsWhenShown]): a tap on a button that appeared less than [afterMove] ago is ignored, since a tap meant for a button just shown, whose amounts are still to read, is no ordinary gesture, while a second tap at the same place, aimed at what stood there (« Pay with this wallet » where « Pay » is brought into view), is (security review of #291, B1). A button that something drawn over it hid from the finger (a dialog's barrier, a sheet, a page pushed over its screen, on whatever navigator) and that a tap reaches again is shown again, and starts the delay too, whether it was built, moved or left in place meanwhile: the tap that closed what covered it may come twice, the second aimed at what stood there (#294). Its delay is a [Timer], so that tests advance it with `tester.pump(duration)`.
///
/// Its place on the screen alone is measured too, for the one move the first measure does not see, where the scroll offset changes with the layout by as much: the page scrolled to its end whose content under the button shrinks (« Hide details » under « Pay », a line under the card that goes) or whose viewport grows (the keyboard or a system bar that goes, a rotation) is brought back to its new end by the layout, so that everything above moves down on the screen and nothing moves in the content (#267, #288). A move on the screen sets it off when no [ScrollPosition] around it scrolled since the last measure made: a scroll, whether by a finger, a fling, an animation or a jump (`ensureVisible` when the confirmation opens), tells the position's listeners, and a bring back by the layout (`ScrollPosition.correctPixels`) tells nobody; while a finger holds the page, or a scroll runs, nothing is compared on the screen.
class MovedTapGuard extends StatefulWidget {
  final Widget Function(BuildContext context, GuardedTap guard) builder;

  /// Whether its first measure starts the delay, a tap on the button just shown being ignored (security review of #291, B1), and whether a tap that reaches it again after something drawn over it hid it starts the delay too (#294); `false` for « Continue », which is shown only once the robot's read the user waited for has come, where « Take Order » stood busy and took the taps meanwhile: no double tap reaches it, while a tap repeated after the read can at some sizes (320 × 640, text ×3; second security pass of #291), which opens « Store your garage key » for the external Garage Key and, since #318, sends the take for a key of the wallet's words, no money moving at that tap.
  final bool armsWhenShown;

  const MovedTapGuard({
    super.key,
    required this.builder,
    this.armsWhenShown = true,
  });

  /// How long a tap is ignored after a move: long enough for a tap aimed at what was there before the move, short enough that a second tap, aimed at the button now in view, pays.
  static const afterMove = Duration(milliseconds: 700);

  @override
  State<MovedTapGuard> createState() => _MovedTapGuardState();
}

class _MovedTapGuardState extends State<MovedTapGuard> {
  /// The place of the guarded widget in the scrolled content at the last measure made; `null` before its first measure.
  Offset? _place;

  /// The place of the guarded widget on the screen at the last measure made; `null` before its first measure.
  Offset? _onScreen;
  Timer? _moved;

  /// The scroll positions around the guarded widget, listened to: each tells its listeners when it scrolls.
  List<ScrollPosition> _positions = const [];

  /// Whether a position around scrolled since the last measure.
  var _scrolled = false;

  /// Whether a position around scrolled after this frame's layout and before this frame's measure (from another callback after the frame, as `ensureVisible` when the confirmation opens): the screen shows that scroll only at the next frame, so this measure would add the new scroll offset to the place on the screen before it; it is skipped, the next one recording.
  var _stale = false;

  /// The time stamp of the frame of the last measure, to tell a scroll after the layout that came before this frame's measure from one that came after it.
  Duration? _measuredAt;

  /// Whether a tap reached the guarded widget at the last measure that could tell (part of it in view): `false` while something drawn over it takes that tap, `null` before such a measure (#294).
  bool? _reachable;

  /// The view the guarded widget is drawn in, where a tap is tried.
  FlutterView? _view;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listened to from the first frame: a scroll after that frame's layout, before the first measure, makes that measure stale.
    _listenTo(_positionsNow());
    _view = View.maybeOf(context);
  }

  @override
  void dispose() {
    _moved?.cancel();
    _listenTo(const []);
    super.dispose();
  }

  void _onScroll() {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.postFrameCallbacks &&
        _measuredAt != scheduler.currentSystemFrameTimeStamp) {
      _stale = true;
    }
    _scrolled = true;
  }

  /// Measures the place after each frame while mounted. A post-frame callback schedules no frame: nothing runs while the screen is still.
  void _watch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final positions = _positionsNow();
      _listenTo(positions);
      if (_stale) {
        // The scroll marked the layout dirty: the next frame comes, and its measure is compared with the last one.
        _stale = false;
      } else {
        _measure(positions);
        _measuredAt = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      }
      _watch();
    });
  }

  /// Compares the places with those of the last measure, sets the guard off when one moved, and records them.
  void _measure(List<ScrollPosition> positions) {
    final scrolling = positions.any(
      (position) => position.isScrollingNotifier.value,
    );
    final scrolled = _scrolled || scrolling;
    _scrolled = false;
    final onScreen = _onScreenNow();
    final place = _placeNow(onScreen, positions);
    if (onScreen == null || place == null) return;
    final last = _place;
    final lastOnScreen = _onScreen;
    final movedInContent = last != null && (place - last).distance > 0.5;
    // The page brought back by the layout, no scroll meanwhile (#288).
    final movedOnScreen =
        !scrolled &&
        lastOnScreen != null &&
        (onScreen - lastOnScreen).distance > 0.5;
    // Shown again: what was drawn over it no longer takes a tap there (#294). The tap is tried after every frame, a jump since the last measure included, whose layout this frame already shows, so that a jump in the very frame a dialog starts to close does not hide the uncovering for one more frame (#299). While a position around scrolls, only a tap that reaches the button is kept: a scrolling list may ignore the taps on its content (a finger, a fling, an animation; `Scrollable`), which is no cover, so that a tap that does not reach it then says nothing; but a scroll does not always ignore them (the settling after a jump, as a page view brought back to its page, or a bounce past an edge, take taps), so that a tap that reaches it always means it is shown (security review of #299, C1).
    final probe = _reachableNow(positions);
    final reachable = scrolling && probe != true ? null : probe;
    final uncovered = _reachable == false && reachable == true;
    if (reachable != null) _reachable = reachable;
    // Just appeared: the delay starts at its first measure (security review of #291, B1).
    if (((last == null || uncovered) && widget.armsWhenShown) ||
        movedInContent ||
        movedOnScreen) {
      _moved?.cancel();
      _moved = Timer(MovedTapGuard.afterMove, () {});
    }
    _place = place;
    _onScreen = onScreen;
  }

  /// Whether a tap at the middle of the guarded widget's part in view (on the screen and inside every [Scrollable] of [positions] around it) reaches it: `false` when something drawn over it takes that tap (a dialog's barrier, a sheet, a page pushed over its screen, on this navigator or another), `null` when no part of it is in view. A widget scrolled out of view and back is never taken for one covered, so that scrolling it away and back does not set the guard off.
  bool? _reachableNow(List<ScrollPosition> positions) {
    final box = context.findRenderObject();
    final view = _view;
    if (box is! RenderBox || !box.attached || !box.hasSize || view == null) {
      return null;
    }
    Rect onScreen(RenderBox of) => MatrixUtils.transformRect(
      of.getTransformTo(null),
      Offset.zero & of.size,
    );
    var shown = onScreen(
      box,
    ).intersect(Offset.zero & (view.physicalSize / view.devicePixelRatio));
    for (final position in positions) {
      final viewport = position.context.notificationContext?.findRenderObject();
      if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
        shown = shown.intersect(onScreen(viewport));
      }
    }
    if (shown.isEmpty) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, shown.center, view.viewId);
    return result.path.any((entry) => identical(entry.target, box));
  }

  /// The positions of every [Scrollable] around the guarded widget, from the nearest.
  List<ScrollPosition> _positionsNow() => [
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = Scrollable.maybeOf(scrollable.context)
    )
      scrollable.position,
  ];

  /// Listens to [positions], and no longer to those around before that are gone.
  void _listenTo(List<ScrollPosition> positions) {
    for (final position in _positions) {
      if (!positions.contains(position)) position.removeListener(_onScroll);
    }
    for (final position in positions) {
      if (!_positions.contains(position)) position.addListener(_onScroll);
    }
    _positions = positions;
  }

  /// The guarded widget's top left on the screen.
  Offset? _onScreenNow() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero);
  }

  /// The guarded widget's top left on the screen ([onScreen]), with the scroll offset of every position of [positions] added back along its axis: a scroll (of the page, between tabs, of a nested list, or the screen bringing the button into view) leaves it unchanged, and a move of the layout changes it, whatever the structure of the page; a move the scroll offset follows by as much (content under the widget that shrinks at the page's end) leaves it unchanged too, the place on the screen seeing it (#267, #288).
  Offset? _placeNow(Offset? onScreen, List<ScrollPosition> positions) {
    if (onScreen == null) return null;
    var place = onScreen;
    for (final position in positions) {
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
