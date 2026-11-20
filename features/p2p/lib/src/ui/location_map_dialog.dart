import 'dart:async';
import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/meeting_point.dart';
import '../domain/web_mercator.dart';
import 'map_chart_view.dart';
import 'widgets/trade_button.dart';

/// « Choose a location »: the map where the maker pins the meeting point of a face-to-face order (#189), the official client's `F2fMapDialog` in its interactive mode (`components/Dialogs/F2fMap.tsx`, opened by `MakerForm.tsx:651-665`, commit ff1998c), drawn as the book's map is drawn (`MapChartView`): the bundled world, no tile and no request, so nothing of a third party is asked and the official client's « Show tiles » is left out, as for the book's map (#30).
///
/// A drag moves the map and a pinch zooms it, « + » and « − » zoom too; a tap pins the place it reaches (`click`, `components/Map/index.tsx`). « Save » keeps the place pinned moved and rounded as the reference does ([MeetingPoint.randomized]), the place a tap reached never leaving the dialog; closing it keeps nothing. Under the map, the reference's line « To protect your privacy, the exact location you pin will be slightly randomized. », and the app's that the point is sent to the coordinator and published with the order.
///
/// Opened on the point saved ([initial], the point the order sends, already moved), at zoom 6 as the reference opens on a saved point; without one, on latitude 0 and longitude 0 at zoom 2, where the reference opens at zoom 6 (`zoom={maker.latitude === 0 && maker.longitude === 0 ? 2 : 6}` compares a `null` latitude with 0), which shows only sea.
/// Nothing reads the device's position: no permission is asked or used.
class LocationMapDialog extends StatefulWidget {
  /// The zoom on a point saved, and the zoom with none.
  static const double pointZoom = 6;
  static const double worldZoom = 2;

  /// The point saved, the one the order sends, or `null`.
  final OrderLocation? initial;

  /// Whether the pin is drawn in the primary colour rather than the secondary one: the reference colours it by its book's side (`orderType={fav?.type ?? 0}`, `MakerForm.tsx:659`; `fillColor`, `components/Map/index.tsx`), « Buy » setting that side to the sell orders', drawn in the primary colour.
  final bool primary;

  /// The draws that move the place pinned, `Math.random()`'s ([MeetingPoint.randomized]).
  final double Function() draw;

  const LocationMapDialog({
    super.key,
    required this.initial,
    required this.primary,
    required this.draw,
  });

  /// Opens the map over the whole screen: the meeting point saved, or `null` when it is closed without « Save ».
  static Future<OrderLocation?> show(
    BuildContext context, {
    required OrderLocation? initial,
    required bool primary,
    required double Function() draw,
  }) => showDialog<OrderLocation>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: LocationMapDialog(initial: initial, primary: primary, draw: draw),
    ),
  );

  @override
  State<LocationMapDialog> createState() => _LocationMapDialogState();
}

class _LocationMapDialogState extends State<LocationMapDialog> {
  late MapCamera _camera = switch (widget.initial) {
    final point? => switch (WebMercator.project(
      point.latitude,
      point.longitude,
    )) {
      final at? => MapCamera.at(
        zoom: LocationMapDialog.pointZoom,
        x: at.x,
        y: at.y,
      ),
      null => MapCamera.at(zoom: LocationMapDialog.worldZoom, x: 0.5, y: 0.5),
    },
    null => MapCamera.at(zoom: LocationMapDialog.worldZoom, x: 0.5, y: 0.5),
  };

  /// The place pinned: the point saved when the map opens, then the place of the last tap.
  late ({double latitude, double longitude})? _pinned =
      switch (widget.initial) {
        final point? => (latitude: point.latitude, longitude: point.longitude),
        null => null,
      };

  Path? _world;
  AssetBundle? _bundle;

  /// The camera and the point under the fingers when a drag or a pinch started.
  MapCamera? _gestureCamera;
  Offset? _gestureFocal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (identical(bundle, _bundle)) return;
    _bundle = bundle;
    unawaited(
      MapChartView.outlineOf(bundle).then((outline) {
        if (mounted && identical(_bundle, bundle)) {
          setState(() => _world = outline);
        }
      }),
    );
  }

  void _move(MapCamera camera) {
    if (camera == _camera) return;
    setState(() => _camera = camera);
  }

  void _pin(Offset at, Size size) {
    final place = WebMercator.unproject(_camera.toMap(at, size));
    setState(() => _pinned = place);
  }

  /// « Save » (`onSave`, `F2fMap.tsx`): the place pinned, moved and rounded as the reference does.
  void _save() {
    final pinned = _pinned;
    if (pinned == null) return;
    final point = MeetingPoint.randomized(
      pinned.latitude,
      pinned.longitude,
      widget.draw,
    );
    if (point == null) return;
    Navigator.of(context).pop(point);
  }

  Map<Type, GestureRecognizerFactory> _gestures(Size size) => {
    ScaleGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
          () => ScaleGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..gestureSettings = const DeviceGestureSettings(
              touchSlop: MapChartView.touchSlop,
            )
            ..onStart = (details) {
              _gestureCamera = _camera;
              _gestureFocal = details.localFocalPoint;
            }
            ..onUpdate = (details) {
              final (camera, focal) = (_gestureCamera, _gestureFocal);
              if (camera == null || focal == null) return;
              final zoom = camera.zoom + math.log(details.scale) / math.ln2;
              _move(
                camera.zoomedTo(
                  zoom.isFinite ? zoom : camera.zoom,
                  anchor: focal,
                  to: details.localFocalPoint,
                  view: size,
                ),
              );
            }
            ..onEnd = (_) {
              _gestureCamera = null;
              _gestureFocal = null;
            },
        ),
    TapGestureRecognizer:
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
            ..onTapUp = (details) => _pin(details.localPosition, size),
        ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final mapColors = MapColors.of(colors);
    final pinned = _pinned;
    return Material(
      color: colors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BullSpacing.md,
                BullSpacing.xs,
                BullSpacing.xs,
                BullSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.p2pMapChooseLocation,
                        style: text.headlineSmall?.copyWith(color: colors.text),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    color: colors.text,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    if (!size.isFinite || size.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final pin = switch (pinned) {
                      final place? => switch (WebMercator.project(
                        place.latitude,
                        place.longitude,
                      )) {
                        final at? => _camera.toView(at.x, at.y, size),
                        null => null,
                      },
                      null => null,
                    };
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Semantics(
                            container: true,
                            label: l10n.p2pMapPinHint,
                            value: switch (pinned) {
                              final place? => l10n.p2pMapPinned(
                                meetingPointText(
                                  place.latitude,
                                  place.longitude,
                                ),
                              ),
                              null => null,
                            },
                            child: RawGestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              gestures: _gestures(size),
                              child: CustomPaint(
                                size: size,
                                painter: _LocationPainter(
                                  camera: _camera,
                                  world: _world,
                                  colors: mapColors,
                                  pin: pin,
                                  fill: widget.primary
                                      ? mapColors.sell
                                      : mapColors.buy,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: BullSpacing.xs,
                          top: BullSpacing.xs,
                          child: MapZoomButtons(
                            camera: _camera,
                            onZoom: (zoom) => _move(
                              _camera.zoomedTo(
                                zoom,
                                anchor: size.center(Offset.zero),
                                view: size,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(BullSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.p2pMakeLocationRandomized,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                  const Gap(BullSpacing.xxs),
                  Text(
                    l10n.p2pMakeLocationPublished,
                    style: text.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                  const Gap(BullSpacing.sm),
                  TradeButton(
                    label: l10n.p2pMapSave,
                    onPressed: pinned == null ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A place as the form and the map write it: its latitude, then its longitude, as numbers.
String meetingPointText(double latitude, double longitude) =>
    '$latitude, $longitude';

/// Paints the world and the pin of the place pinned, as the book's map paints its countries and its pins ([MapChartPainter]).
final class _LocationPainter extends CustomPainter {
  final MapCamera camera;
  final Path? world;
  final MapColors colors;

  /// Where the tip of the pin stands in the view, or `null` for none.
  final Offset? pin;
  final Color fill;

  const _LocationPainter({
    required this.camera,
    required this.world,
    required this.colors,
    required this.pin,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (world case final world?) {
      MapChartPainter.paintWorld(canvas, size, camera, world, colors);
    }
    if (pin case final at?) {
      MapChartPainter.paintPin(canvas, at, fill, colors);
    }
  }

  @override
  bool shouldRepaint(_LocationPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.world != world ||
      oldDelegate.colors != colors ||
      oldDelegate.pin != pin ||
      oldDelegate.fill != fill;
}
