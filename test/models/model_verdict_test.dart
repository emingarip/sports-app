import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/model_verdict.dart';
import 'package:sports_app/theme/app_theme.dart';

/// The verdict layer is the single place that turns the engine's numbers into
/// something a bettor reads. If it drifts, every screen drifts with it - so the
/// thresholds and the wording are pinned here.
void main() {
  group('ModelVerdict.fromExpectedValue', () {
    test('flags value at and above the 5% threshold', () {
      // Mirrors DEFAULT_EV_THRESHOLD in sports_api value_detection.py.
      expect(ModelVerdict.fromExpectedValue(0.05), ModelVerdict.value);
      expect(ModelVerdict.fromExpectedValue(0.42), ModelVerdict.value);
    });

    test('calls a clearly bad price out rather than staying quiet', () {
      // "Do not play" is an analysis result too (principle 0.1.2).
      expect(ModelVerdict.fromExpectedValue(-0.08), ModelVerdict.avoid);
      expect(ModelVerdict.fromExpectedValue(-0.5), ModelVerdict.avoid);
    });

    test('stays neutral in the band between the two thresholds', () {
      expect(ModelVerdict.fromExpectedValue(0.0), ModelVerdict.neutral);
      expect(ModelVerdict.fromExpectedValue(0.049), ModelVerdict.neutral);
      expect(ModelVerdict.fromExpectedValue(-0.079), ModelVerdict.neutral);
    });

    test('reports unknown instead of guessing when there is no estimate', () {
      expect(ModelVerdict.fromExpectedValue(null), ModelVerdict.unknown);
    });
  });

  group('ModelVerdict.fromProbabilityAndOdds', () {
    test('derives the same verdict the EV form would', () {
      // 0.60 * 2.00 - 1 = 0.20 -> value
      expect(
        ModelVerdict.fromProbabilityAndOdds(0.60, 2.00),
        ModelVerdict.value,
      );
      // 0.40 * 2.00 - 1 = -0.20 -> avoid
      expect(
        ModelVerdict.fromProbabilityAndOdds(0.40, 2.00),
        ModelVerdict.avoid,
      );
    });

    test('treats a missing or unplayable price as unknown', () {
      expect(ModelVerdict.fromProbabilityAndOdds(0.6, null), ModelVerdict.unknown);
      expect(ModelVerdict.fromProbabilityAndOdds(null, 2.0), ModelVerdict.unknown);
      // Odds of 1.00 pay nothing; EV would be a meaningless negative number.
      expect(ModelVerdict.fromProbabilityAndOdds(0.9, 1.0), ModelVerdict.unknown);
    });
  });

  group('user-facing copy', () {
    test('no verdict leaks engine vocabulary', () {
      // Principle 0.1.6: EV, Kelly, lambda and the model version belong in the
      // collapsed detail section, never in the headline copy.
      const forbidden = ['EV', 'Kelly', 'lambda', 'λ', 'dc-v1', 'logit'];
      for (final verdict in ModelVerdict.values) {
        for (final word in forbidden) {
          expect(
            verdict.label.contains(word),
            isFalse,
            reason: '${verdict.name}.label leaks "$word"',
          );
          expect(
            verdict.explanation.contains(word),
            isFalse,
            reason: '${verdict.name}.explanation leaks "$word"',
          );
        }
      }
    });

    test('every verdict has a distinct label, icon and explanation', () {
      final labels = ModelVerdict.values.map((v) => v.label).toSet();
      final icons = ModelVerdict.values.map((v) => v.icon).toSet();
      final explanations =
          ModelVerdict.values.map((v) => v.explanation).toSet();
      expect(labels.length, ModelVerdict.values.length);
      expect(icons.length, ModelVerdict.values.length);
      expect(explanations.length, ModelVerdict.values.length);
    });
  });

  group('modelVsMarketSentence', () {
    test('states both sides as whole percentages', () {
      expect(
        modelVsMarketSentence(modelProbability: 0.62, oddsDecimal: 1.85),
        'Model %62 diyor, oran %54 fiyatlıyor',
      );
    });

    test('reads as a tie when model and price agree', () {
      final sentence =
          modelVsMarketSentence(modelProbability: 0.50, oddsDecimal: 2.00);
      expect(sentence, 'Model %50 diyor, oran %50 fiyatlıyor');
    });
  });

  group('kellyAsBankrollShare', () {
    test('expresses the stake as a share of the bankroll', () {
      expect(kellyAsBankrollShare(0.025), 'Kasanın %2.5 kadarı');
      expect(kellyAsBankrollShare(0.12), 'Kasanın %12 kadarı');
    });

    test('says do-not-play rather than showing a zero stake', () {
      expect(kellyAsBankrollShare(0), 'Önerilmiyor');
      expect(kellyAsBankrollShare(null), 'Önerilmiyor');
      expect(kellyAsBankrollShare(-0.1), 'Önerilmiyor');
    });
  });

  testWidgets('beta chip states why it is there', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // ModelBetaChip reads the AppColors theme extension, so a bare
        // MaterialApp is not enough.
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ModelBetaChip()),
      ),
    );
    expect(find.text('beta'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('doğrulanmadı'));
  });
}
