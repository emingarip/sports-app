import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/match_lineup.dart';

void main() {
  group('MatchLineupReport', () {
    test('parses tactical balance from API response', () {
      final report = MatchLineupReport.fromJson({
        'match_id': 'match-1',
        'status': 'available',
        'provider_slug': 'ai-sport-agent',
        'confirmed': true,
        'home': {
          'team': {'id': 'home', 'name': 'Home'},
          'formation': '4-2-3-1',
          'starters': [],
          'bench': [],
        },
        'away': {
          'team': {'id': 'away', 'name': 'Away'},
          'formation': '3-4-2-1',
          'starters': [],
          'bench': [],
        },
        'substitutions': [],
        'summary': {},
        'tactical_balance': {
          'home': {
            'formation': '4-2-3-1',
            'score': 0.24,
            'label': 'hafif avantaj',
          },
          'away': {
            'formation': '3-4-2-1',
            'score': -0.24,
            'label': 'hafif dezavantaj',
          },
          'sample_size': 128,
          'confidence': 0.72,
          'confidence_label': 'medium',
          'explanation': '4-2-3-1 vs 3-4-2-1 gecmis veride hafif avantaj.',
        },
      });

      expect(report.tacticalBalance, isNotNull);
      expect(report.tacticalBalance!.home.score, 0.24);
      expect(report.tacticalBalance!.home.label, 'hafif avantaj');
      expect(report.tacticalBalance!.away.score, -0.24);
      expect(report.tacticalBalance!.sampleSize, 128);
      expect(report.tacticalBalance!.confidence, 0.72);
      expect(report.tacticalBalance!.confidenceLabel, 'medium');
      expect(
        report.tacticalBalance!.explanation,
        '4-2-3-1 vs 3-4-2-1 gecmis veride hafif avantaj.',
      );
    });

    test('keeps tactical balance null when API does not provide it', () {
      final report = MatchLineupReport.fromJson({
        'match_id': 'match-1',
        'status': 'missing',
        'home': {'team': {}, 'starters': [], 'bench': []},
        'away': {'team': {}, 'starters': [], 'bench': []},
        'substitutions': [],
        'summary': {},
      });

      expect(report.tacticalBalance, isNull);
    });
  });
}
