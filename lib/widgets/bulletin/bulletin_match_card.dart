import 'package:flutter/material.dart';

import '../../models/bulletin.dart';
import '../../models/model_verdict.dart';
import '../../theme/app_theme.dart';

/// One compact bulletin row (bettor-familiar layout):
/// kickoff+MBS | stacked team names | odds boxes for the selected market.
/// Tapping the row opens the analysis screen; tapping an odds box toggles it
/// on the coupon draft. Markets with more than four selections scroll
/// horizontally instead of squeezing.
class BulletinMatchCard extends StatelessWidget {
  final BulletinMatch match;
  final BulletinPrediction? prediction;
  final String marketCode;
  final VoidCallback onTap;

  /// Tapping an odds button adds/removes it on the coupon draft.
  final void Function(BulletinMarket market, BulletinSelection selection)?
      onSelectionTap;

  /// Selection keys of this match+market currently on the coupon draft.
  final Set<String> selectedSelectionKeys;

  const BulletinMatchCard({
    super.key,
    required this.match,
    required this.prediction,
    required this.marketCode,
    required this.onTap,
    this.onSelectionTap,
    this.selectedSelectionKeys = const {},
  });

  @override
  Widget build(BuildContext context) {
    final market = match.marketByCode(marketCode);
    final selections = market?.selections ?? const <BulletinSelection>[];
    final scrollable = selections.length > 4;

    final oddsBoxes = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selections.isEmpty)
          const _NoOddsBox()
        else
          for (final selection in selections) ...[
            _OddsBox(
              selection: selection,
              isValue: prediction?.isValuePick(
                    market!.marketCode,
                    selection.selectionKey,
                  ) ??
                  false,
              isSelected:
                  selectedSelectionKeys.contains(selection.selectionKey),
              onTap: onSelectionTap == null || selection.suspended
                  ? null
                  : () => onSelectionTap!(market!, selection),
            ),
            if (selection != selections.last) const SizedBox(width: 4),
          ],
      ],
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: context.colors.outline.withValues(alpha: 0.10),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kickoffLabel(match.kickoffAt),
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  if (match.mbs != null)
                    Text(
                      'MBS ${match.mbs}',
                      style: TextStyle(
                        color: context.colors.textLow,
                        fontWeight: FontWeight.w700,
                        fontSize: 8.5,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.homeTeam,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    match.awayTeam,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (scrollable)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 232),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: oddsBoxes,
                ),
              )
            else
              oddsBoxes,
          ],
        ),
      ),
    );
  }

  static String _kickoffLabel(DateTime? kickoffAt) {
    final local = kickoffAt?.toLocal();
    if (local == null) return '--:--';
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _NoOddsBox extends StatelessWidget {
  const _NoOddsBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '-',
        style: TextStyle(
          color: context.colors.textLow,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _OddsBox extends StatelessWidget {
  final BulletinSelection selection;
  final bool isValue;
  final bool isSelected;
  final VoidCallback? onTap;

  const _OddsBox({
    required this.selection,
    required this.isValue,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final suspended = selection.suspended;

    final Color backgroundColor;
    final Color borderColor;
    if (isSelected) {
      backgroundColor = context.colors.accent.withValues(alpha: 0.18);
      borderColor = context.colors.accent;
    } else if (isValue) {
      backgroundColor = context.colors.success.withValues(alpha: 0.10);
      borderColor = context.colors.success.withValues(alpha: 0.55);
    } else {
      backgroundColor = context.colors.surfaceVariant.withValues(alpha: 0.5);
      borderColor = context.colors.outline.withValues(alpha: 0.18);
    }

    final semanticLabel = [
      selection.labelTr,
      suspended ? 'askida' : 'oran ${selection.odds.toStringAsFixed(2)}',
      if (isValue) ModelVerdict.value.label.toLowerCase(),
      if (isSelected) 'kuponda',
    ].join(', ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        // The star alone does not say what it means; the tooltip does, and the
        // model explainer says it properly.
        child: Tooltip(
          message: isValue
              ? '${ModelVerdict.value.label}: ${ModelVerdict.value.explanation}'
              : selection.labelTr,
          child: Container(
            width: 56,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: borderColor, width: isSelected ? 1.6 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isValue) ...[
                      Icon(
                        Icons.star_rounded,
                        size: 9,
                        color: context.colors.success,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Text(
                        selection.labelTr,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textLow,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      suspended ? '-' : selection.odds.toStringAsFixed(2),
                      style: TextStyle(
                        color: isSelected
                            ? context.colors.accent
                            : suspended
                                ? context.colors.textLow
                                : context.colors.textHigh,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    if (selection.isDropping && !suspended) ...[
                      const SizedBox(width: 1),
                      Icon(
                        Icons.arrow_downward,
                        size: 10,
                        color: context.colors.liveAccent,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
