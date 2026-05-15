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

    test('parses formation pair statistics from API response', () {
      final report = MatchLineupReport.fromJson({
        'match_id': 'match-1',
        'status': 'available',
        'home': {'team': {}, 'starters': [], 'bench': []},
        'away': {'team': {}, 'starters': [], 'bench': []},
        'substitutions': [],
        'summary': {},
        'formation_statistics': {
          'home_formation': '4-2-3-1',
          'away_formation': '4-5-1',
          'sample_size': 336,
          'min_reliable_sample_size': 30,
          'avg_total_goals': 2.955,
          'over_25_rate': 0.557,
          'btts_rate': 0.497,
          'result': {
            'home_win_rate': 0.557,
            'draw_rate': 0.183,
            'away_win_rate': 0.260,
            'home_avg_goals': 1.813,
            'away_avg_goals': 1.077,
            'avg_goal_diff': 0.737,
          },
          'first_half': {
            'avg_goals': 1.280,
            'over_05_rate': 0.735,
            'over_15_rate': 0.360,
            'home_avg_goals': 0.839,
            'away_avg_goals': 0.440,
          },
          'second_half': {
            'avg_goals': 1.676,
            'over_05_rate': 0.833,
            'over_15_rate': 0.500,
            'home_avg_goals': 1.009,
            'away_avg_goals': 0.667,
          },
        },
      });

      final stats = report.formationStatistics;
      expect(stats, isNotNull);
      expect(stats!.homeFormation, '4-2-3-1');
      expect(stats.awayFormation, '4-5-1');
      expect(stats.sampleSize, 336);
      expect(stats.hasReliableSample, isTrue);
      expect(stats.result.homeWinRate, 0.557);
      expect(stats.firstHalf!.over05Rate, 0.735);
      expect(stats.secondHalf!.over15Rate, 0.5);
    });
  });
}
