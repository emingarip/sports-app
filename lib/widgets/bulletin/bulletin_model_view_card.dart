import 'package:flutter/material.dart';

import '../../models/bulletin.dart';
import '../../models/model_verdict.dart';
import '../../screens/model_explainer_screen.dart';
import '../../theme/app_theme.dart';

/// "Model Görüşü" card.
///
/// Leads with a verdict a bettor can act on and a sentence comparing the model
/// with the price. Every technical number (EV, Kelly, lambda, model version)
/// lives one tap down in [ModelVerdictDetail] - roadmap principle 0.1.6.
class BulletinModelViewCard extends StatelessWidget {
  final BulletinMatch match;
  final BulletinPrediction? prediction;

  const BulletinModelViewCard({
    super.key,
    required this.match,
    required this.prediction,
  });

  @override
  Widget build(BuildContext context) {
    final prediction = this.prediction;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: 12),
          if (prediction == null)
            const _EmptyNote(
              text: 'Model tahmini henüz üretilmedi. Maç yaklaştıkça oluşur.',
            )
          else ...[
            _VerdictSection(match: match, prediction: prediction),
            const SizedBox(height: 12),
            _ExpectedGoals(prediction: prediction),
            const SizedBox(height: 4),
            ModelVerdictDetail(
              prediction: prediction,
              pick: _topPick(prediction),
            ),
          ],
        ],
      ),
    );
  }

  static ValuePick? _topPick(BulletinPrediction prediction) {
    if (prediction.valuePicks.isEmpty) return null;
    return prediction.valuePicks
        .reduce((a, b) => b.expectedValue > a.expectedValue ? b : a);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.psychology, size: 18, color: context.colors.accent),
        const SizedBox(width: 8),
        Text(
          'MODEL GÖRÜŞÜ',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        const ModelBetaChip(),
        const Spacer(),
        // The old header showed the raw model version ("dc-v1") here. It told
        // the reader nothing; an explainer link does.
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Model nasıl çalışır?',
          icon: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: context.colors.textLow,
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ModelExplainerScreen()),
          ),
        ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textMedium,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Verdict-first block: icon + label, then the selection, then the
/// model-vs-price sentence. No EV percentage in sight.
class _VerdictSection extends StatelessWidget {
  const _VerdictSection({required this.match, required this.prediction});

  final BulletinMatch match;
  final BulletinPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final picks = [...prediction.valuePicks]
      ..sort((a, b) => b.expectedValue.compareTo(a.expectedValue));

    if (picks.isEmpty) {
      return _VerdictBanner(
        verdict: ModelVerdict.neutral,
        title: ModelVerdict.neutral.label,
        subtitle: 'Bu maçta oynanmaya değer bir oran bulunamadı.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final pick in picks.take(3)) ...[
          _PickBanner(match: match, pick: pick),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PickBanner extends StatelessWidget {
  const _PickBanner({required this.match, required this.pick});

  final BulletinMatch match;
  final ValuePick pick;

  @override
  Widget build(BuildContext context) {
    final market = match.marketByCode(pick.marketCode);
    final selection = market?.selectionByKey(pick.selectionKey);
    final marketLabel =
        bulletinMarketLabel(pick.marketCode, nameTr: market?.nameTr);
    final selectionLabel =
        bulletinSelectionLabel(pick.selectionKey, labelTr: selection?.labelTr);
    final verdict = ModelVerdict.fromExpectedValue(pick.expectedValue);

    return _VerdictBanner(
      verdict: verdict,
      title: verdict.label,
      selection: '$marketLabel • $selectionLabel',
      odds: pick.oddsDecimal,
      subtitle: modelVsMarketSentence(
        modelProbability: pick.modelProbability,
        oddsDecimal: pick.oddsDecimal,
      ),
    );
  }
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({
    required this.verdict,
    required this.title,
    required this.subtitle,
    this.selection,
    this.odds,
  });

  final ModelVerdict verdict;
  final String title;
  final String subtitle;
  final String? selection;
  final double? odds;

  @override
  Widget build(BuildContext context) {
    final color = verdict.color(context);
    final selectionText = selection;

    return Semantics(
      label: '${verdict.label}. ${selectionText ?? ''} $subtitle',
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(verdict.icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            if (selectionText != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selectionText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (odds != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      'oran ${odds!.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: context.colors.textHigh,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expected goals, stated as goals. The previous version labelled these
/// "Ev sahibi (λ)" - the model's internal symbol, shown to a bettor.
class _ExpectedGoals extends StatelessWidget {
  const _ExpectedGoals({required this.prediction});

  final BulletinPrediction prediction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Modelin beklediği skor',
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${prediction.lambdaHome.toStringAsFixed(1)}'
            ' - ${prediction.lambdaAway.toStringAsFixed(1)}',
            style: TextStyle(
              color: context.colors.textHigh,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
