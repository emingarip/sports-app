import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bulletin.dart';

/// The plain-language layer over the model's output.
///
/// Roadmap principle 0.1.6: science is the engine's language, not the
/// interface's. A bettor does not read EV, Kelly or lambda. Everything the
/// model produces is funnelled through this one place so the wording, the icon
/// and the colour of a verdict cannot drift between screens. The numbers are
/// not deleted - they move behind [ModelVerdictDetail], one tap away.
enum ModelVerdict {
  /// Odds are priced above what the model believes: worth playing.
  value,

  /// Odds are clearly below the model's probability. Saying "do not play" is
  /// an analysis result too (principle 0.1.2).
  avoid,

  /// Neither side has an edge worth acting on.
  neutral,

  /// The model produced nothing for this selection.
  unknown;

  /// Edge above which a selection is called out as value. Mirrors
  /// `DEFAULT_EV_THRESHOLD` in `sports_api/app/ml/value_detection.py`.
  static const double valueThreshold = 0.05;

  /// Below this the model thinks the price is genuinely bad, not just flat.
  static const double avoidThreshold = -0.08;

  /// Derives the verdict from expected value, the one number that already
  /// encodes "model probability vs offered odds".
  static ModelVerdict fromExpectedValue(double? expectedValue) {
    if (expectedValue == null) return ModelVerdict.unknown;
    if (expectedValue >= valueThreshold) return ModelVerdict.value;
    if (expectedValue <= avoidThreshold) return ModelVerdict.avoid;
    return ModelVerdict.neutral;
  }

  /// Derives the verdict from a model probability and an offered price.
  static ModelVerdict fromProbabilityAndOdds(
    double? modelProbability,
    double? oddsDecimal,
  ) {
    if (modelProbability == null || oddsDecimal == null || oddsDecimal <= 1.0) {
      return ModelVerdict.unknown;
    }
    return fromExpectedValue(modelProbability * oddsDecimal - 1.0);
  }

  String get label {
    switch (this) {
      case ModelVerdict.value:
        return 'DEĞERLİ ORAN';
      case ModelVerdict.avoid:
        return 'ORAN DÜŞÜK';
      case ModelVerdict.neutral:
        return 'DEĞER YOK';
      case ModelVerdict.unknown:
        return 'MODEL GÖRÜŞÜ YOK';
    }
  }

  /// One sentence a bettor can act on, without a single technical term.
  String get explanation {
    switch (this) {
      case ModelVerdict.value:
        return 'Model bu seçime, oranın fiyatladığından daha yüksek şans veriyor.';
      case ModelVerdict.avoid:
        return 'Model bu seçime, oranın fiyatladığından daha düşük şans veriyor.';
      case ModelVerdict.neutral:
        return 'Model ile oran birbirine yakın; belirgin bir avantaj yok.';
      case ModelVerdict.unknown:
        return 'Bu maç için yeterli geçmiş veri yok.';
    }
  }

  IconData get icon {
    switch (this) {
      case ModelVerdict.value:
        return Icons.check_circle_rounded;
      case ModelVerdict.avoid:
        return Icons.report_problem_rounded;
      case ModelVerdict.neutral:
        return Icons.remove_circle_outline_rounded;
      case ModelVerdict.unknown:
        return Icons.help_outline_rounded;
    }
  }

  Color color(BuildContext context) {
    switch (this) {
      case ModelVerdict.value:
        return context.colors.success;
      case ModelVerdict.avoid:
        return context.colors.error;
      case ModelVerdict.neutral:
      case ModelVerdict.unknown:
        return context.colors.textLow;
    }
  }
}

/// "Model %62 diyor, oran %54 fiyatlıyor" - the same information an EV
/// percentage carries, without asking the reader to know what EV is.
String modelVsMarketSentence({
  required double modelProbability,
  required double oddsDecimal,
}) {
  final modelPercent = (modelProbability * 100).round();
  final impliedPercent = (100 / oddsDecimal).round();
  return 'Model %$modelPercent diyor, oran %$impliedPercent fiyatlıyor';
}

/// Fractional-Kelly stake expressed as a bankroll share rather than as "Kelly".
String kellyAsBankrollShare(double? kellyStake) {
  if (kellyStake == null || kellyStake <= 0) return 'Önerilmiyor';
  final percent = kellyStake * 100;
  final text =
      percent >= 10 ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1);
  return 'Kasanın %$text kadarı';
}

/// The value layer is not yet backed by a walk-forward backtest
/// (`sports_api/app/ml/backtest.py` exists but its ROI has not been measured on
/// production data). Until it is, every surface showing a verdict says so.
/// Remove once `GET /api/v1/model/backtest` reports a meaningful sample.
class ModelBetaChip extends StatelessWidget {
  const ModelBetaChip({super.key, this.dense = false});

  final bool dense;

  static const String tooltip =
      'Beta: modelin geçmiş performansı henüz doğrulanmadı.';

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 5 : 7,
          vertical: dense ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: context.colors.textLow.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'beta',
          style: TextStyle(
            color: context.colors.textMedium,
            fontSize: dense ? 8 : 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Collapsed home for every number the plain-language layer hides: EV, Kelly,
/// expected goals, model version, and the model/market split behind a blended
/// probability. Curious users lose nothing; the default reader is not taxed.
class ModelVerdictDetail extends StatelessWidget {
  const ModelVerdictDetail({
    super.key,
    required this.prediction,
    this.pick,
  });

  final BulletinPrediction prediction;
  final ValuePick? pick;

  @override
  Widget build(BuildContext context) {
    final selected = pick;
    final rows = <(String, String)>[
      ('Beklenen gol (ev)', prediction.lambdaHome.toStringAsFixed(2)),
      ('Beklenen gol (deplasman)', prediction.lambdaAway.toStringAsFixed(2)),
      if (selected != null)
        (
          'Beklenen değer (EV)',
          '${selected.expectedValue >= 0 ? '+' : ''}'
              '%${(selected.expectedValue * 100).toStringAsFixed(1)}'
        ),
      if (selected != null)
        (
          'Model olasılığı',
          '%${(selected.modelProbability * 100).toStringAsFixed(1)}'
        ),
      if (selected?.impliedProbability != null)
        (
          'Oranın ima ettiği',
          '%${(selected!.impliedProbability! * 100).toStringAsFixed(1)}'
        ),
      if (selected?.dcProbability != null)
        (
          'Saf model (Dixon-Coles)',
          '%${(selected!.dcProbability! * 100).toStringAsFixed(1)}'
        ),
      if (selected?.marketProbability != null)
        (
          'Piyasa (marj arındırılmış)',
          '%${(selected!.marketProbability! * 100).toStringAsFixed(1)}'
        ),
      if (selected?.kellyStake != null)
        (
          'Çeyrek Kelly payı',
          '%${(selected!.kellyStake! * 100).toStringAsFixed(2)}'
        ),
      if (prediction.modelVersion.isNotEmpty)
        ('Model sürümü', prediction.modelVersion),
      if (prediction.generatedAt != null)
        ('Üretildi', _formatTimestamp(prediction.generatedAt!)),
    ];

    return Theme(
      // ExpansionTile draws its own divider lines; the design system forbids
      // 1px section borders (design_system.md, "The No-Line Rule").
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: context.colors.textMedium,
        collapsedIconColor: context.colors.textLow,
        title: Text(
          'Bilimsel ayrıntı',
          style: TextStyle(
            color: context.colors.textMedium,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: context.colors.textMedium,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value,
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}
