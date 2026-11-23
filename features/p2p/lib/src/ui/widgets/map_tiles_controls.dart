import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../map_tile_layer.dart';
import 'trade_dialog_body.dart';

/// « Show tiles » at the right of a map's title (#246), as the reference puts it (`F2fMap.tsx:105-125`, `MapChart/index.tsx:109-130`, commit babf62e): a small switch and a picture icon, under the tooltip « Show tiles », which a screen reader reads as the switch's name.
///
/// The first time on a map it opens the reference's dialog instead ([MapTilesDialog]): « Acknowledged » turns the tiles on, « Close » or a tap outside leaves them off; once acknowledged, it turns them on and off.
class MapTilesSwitch extends StatelessWidget {
  final MapTileLayer tiles;

  const MapTilesSwitch({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return Tooltip(
      message: l10n.p2pMapShowTiles,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BullSwitch(value: tiles.shown, onChanged: (_) => _toggle(context)),
          ExcludeSemantics(
            child: Icon(
              Icons.photo_size_select_actual,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    if (tiles.acknowledged) {
      tiles.shown ? tiles.hide() : tiles.show();
      return;
    }
    if (!await MapTilesDialog.show(context)) return;
    tiles
      ..acknowledge()
      ..show();
  }
}

/// « Download high resolution map? », the reference's dialog word for word (`F2fMap.tsx:69-99`, `MapChart/index.tsx:55-85`, commit babf62e), its texts from the reference's locale files, with no line added (the owner's decision of 2026-11-23).
class MapTilesDialog extends StatelessWidget {
  const MapTilesDialog({super.key});

  /// Whether « Acknowledged » was pressed.
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const MapTilesDialog(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pMapTilesTitle,
      text: l10n.p2pMapTilesText,
      backLabel: l10n.p2pMapTilesClose,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pMapTilesAcknowledged,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}

/// What a map shows over its tiles while they are shown (#246): at the bottom, the provider's credit « © OpenStreetMap contributors » in its right corner, as Leaflet's attribution control shows the reference's (`components/Map/index.tsx`, `osmTiles.ts:3-4`), and, when tiles in view failed or were refused, the app's one line « Map tiles unavailable » above it.
class MapTilesNotes extends StatelessWidget {
  final MapTileLayer tiles;

  const MapTilesNotes({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (!tiles.shown) return const SizedBox.shrink();
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    Widget note(String line, Color color) => DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(BullRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BullSpacing.xs,
          vertical: BullSpacing.xxs,
        ),
        child: Text(
          line,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(color: color),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (tiles.unavailable) ...[
          Semantics(
            liveRegion: true,
            child: note(l10n.p2pMapTilesUnavailable, colors.warning),
          ),
          const Gap(BullSpacing.xxs),
        ],
        note(l10n.p2pMapTilesCredit, colors.text),
      ],
    );
  }
}
