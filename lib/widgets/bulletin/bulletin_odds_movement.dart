import 'package:flutter/material.dart';

import '../../models/bulletin.dart';
import '../../theme/app_theme.dart';

/// "Oranlar" section: every market of the match with opening -> current odds
/// and the movement percentage.
class BulletinOddsMovement extends StatelessWidget {
  final BulletinMatch match;

  const BulletinOddsMovement({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    if (match.markets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: context.colors.outline.withValues(alpha: 0.2)),
        ),
        child: Text(
          'Bu maç için oran bulunamadı.',
          style: TextStyle(
            color: context.colors.textMedium,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'ORANLAR VE HAREKET',
            style: TextStyle(
              color: context.colors.textMedium,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final market in match.markets) _MarketOddsCard(market: market),
      ],
    );
  }
}

class _MarketOddsCard extends StatelessWidget {
  final BulletinMarket market;

  const _MarketOddsCard({required this.market});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: context.colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            market.displayName,
            style: TextStyle(
              color: context.colors.textHigh,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final selection in market.selections)
            _SelectionMovementRow(selection: selection),
        ],
      ),
    );
  }
}

class _SelectionMovementRow extends StatelessWidget {
  final BulletinSelection selection;

  const _SelectionMovementRow({required this.selection});

  @override
  Widget build(BuildContext context) {
    final movement = selection.movementPct;
    final hasMovement = movement != null && movement != 0;
    final movementColor = selection.isDropping || (movement ?? 0) < 0
        ? context.colors.liveAccent
        : context.colors.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selection.labelTr,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (selection.suspended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'KAPALI',
                style: TextStyle(
                  color: context.colors.textLow,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else ...[
            if (selection.openingOdds != null) ...[
              Text(
                selection.openingOdds!.toStringAsFixed(2),
                style: TextStyle(
                  color: context.colors.textLow,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  decoration: selection.openingOdds != selection.odds
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward,
                  size: 11,
                  color: context.colors.textLow,
                ),
              ),
            ],
            Text(
              selection.odds.toStringAsFixed(2),
              style: TextStyle(
                color: context.colors.textHigh,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (selection.isDropping) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_downward,
                size: 12,
                color: context.colors.liveAccent,
              ),
            ],
            if (hasMovement) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: movementColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  movement > 0
                      ? '+%${movement.toStringAsFixed(1)}'
                      : '-%${movement.abs().toStringAsFixed(1)}',
                  style: TextStyle(
                    color: movementColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
