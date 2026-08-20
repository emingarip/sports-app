import 'package:flutter/material.dart';

import '../../models/bulletin.dart';
import '../../models/model_verdict.dart';
import '../../theme/app_theme.dart';

/// "Model vs Piyasa" section: for every market present both in the model
/// probabilities and in the bulletin odds, compares model probability,
/// current odds, implied probability and the resulting expected value.
class BulletinMarketComparison extends StatelessWidget {
  final BulletinMatch match;
  final BulletinPrediction prediction;

  const BulletinMarketComparison({
    super.key,
    required this.match,
    required this.prediction,
  });

  @override
  Widget build(BuildContext context) {
    final markets = match.markets
        .where((market) =>
            prediction.marketProbs.containsKey(market.marketCode) &&
            market.selections.isNotEmpty)
        .toList();

    if (markets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'MODEL vs PİYASA',
            style: TextStyle(
              color: context.colors.textMedium,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final market in markets)
          _MarketComparisonCard(market: market, prediction: prediction),
      ],
    );
  }
}

class _MarketComparisonCard extends StatelessWidget {
  final BulletinMarket market;
  final BulletinPrediction prediction;

  const _MarketComparisonCard({
    required this.market,
    required this.prediction,
  });

  @override
  Widget build(BuildContext context) {
    final rows = market.selections
        .map((selection) {
          final modelProb = prediction.probabilityFor(
            market.marketCode,
            selection.selectionKey,
          );
          if (modelProb == null) return null;
          return (selection, modelProb);
        })
        .whereType<(BulletinSelection, double)>()
        .toList();

    if (rows.isEmpty) return const SizedBox.shrink();

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
          const SizedBox(height: 10),
          _buildHeaderRow(context),
          const SizedBox(height: 6),
          for (final (selection, modelProb) in rows)
            _buildSelectionRow(context, selection, modelProb),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    final style = TextStyle(
      color: context.colors.textLow,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );

    return Row(
      children: [
        Expanded(flex: 3, child: Text('SEÇİM', style: style)),
        Expanded(
            flex: 2,
            child: Text('MODEL', style: style, textAlign: TextAlign.center)),
        Expanded(
            flex: 2,
            child: Text('ORAN', style: style, textAlign: TextAlign.center)),
        // "IMA" (implied) and "EV" were engine vocabulary on a user-facing
        // table. The numbers are unchanged; only the labels and the last
        // column now speak the reader's language (principle 0.1.6).
        Expanded(
            flex: 2,
            child: Text('ORAN DİYOR',
                style: style, textAlign: TextAlign.center)),
        Expanded(
            flex: 3,
            child: Text('HÜKÜM', style: style, textAlign: TextAlign.end)),
      ],
    );
  }

  Widget _buildSelectionRow(
    BuildContext context,
    BulletinSelection selection,
    double modelProb,
  ) {
    final impliedProb = selection.impliedProb ??
        (selection.odds > 0 ? 1 / selection.odds : null);
    final ev = selection.odds > 0 ? modelProb * selection.odds - 1 : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 3,
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
          Expanded(
            flex: 2,
            child: Text(
              '%${(modelProb * 100).toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              selection.suspended ? '-' : selection.odds.toStringAsFixed(2),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              impliedProb == null
                  ? '-'
                  : '%${(impliedProb * 100).toStringAsFixed(0)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: _VerdictBadge(ev: ev),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictBadge extends StatelessWidget {
  final double? ev;

  const _VerdictBadge({required this.ev});

  @override
  Widget build(BuildContext context) {
    final value = ev;
    if (value == null) {
      return Text(
        '-',
        style: TextStyle(
          color: context.colors.textLow,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final verdict = ModelVerdict.fromExpectedValue(value);
    final color = verdict.color(context);
    final pct = (value.abs() * 100).toStringAsFixed(1);

    return Tooltip(
      // The raw edge stays reachable for anyone who wants it, without
      // occupying the column a bettor scans.
      message: '${verdict.explanation}\n'
          'Beklenen değer: ${value >= 0 ? '+' : '-'}%$pct',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(verdict.icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              _shortLabel(verdict),
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortLabel(ModelVerdict verdict) {
    switch (verdict) {
      case ModelVerdict.value:
        return 'Değerli';
      case ModelVerdict.avoid:
        return 'Düşük';
      case ModelVerdict.neutral:
        return 'Nötr';
      case ModelVerdict.unknown:
        return '-';
    }
  }
}
