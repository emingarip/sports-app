import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/bulletin.dart';

/// Parsing tests for the bulletin payload.
///
/// Everything the betting half of the app shows comes through these
/// constructors, and nothing covered them. A silently-dropped field here means
/// odds, a value pick or a whole market vanishing from the screen with no
/// error anywhere.
void main() {
  group('BulletinSelection.fromJson', () {
    test('reads the odds row the bridge writes', () {
      final selection = BulletinSelection.fromJson({
        'selection_key': 'over',
        'selection_label_tr': '2.5 Üst',
        'odds': 1.85,
        'opening_odds': 1.95,
        'movement_pct': -5.1,
        'is_dropping': true,
        'implied_prob': 0.54,
        'normalized_prob': 0.52,
        'suspended': false,
      });

      expect(selection.selectionKey, 'over');
      expect(selection.labelTr, '2.5 Üst');
      expect(selection.odds, 1.85);
      expect(selection.openingOdds, 1.95);
      expect(selection.isDropping, isTrue);
      expect(selection.suspended, isFalse);
    });

    test('accepts numeric strings, since Postgres numerics arrive as text', () {
      final selection = BulletinSelection.fromJson({
        'selection_key': 'home',
        'odds': '2.40',
        'implied_prob': '0.4167',
      });
      expect(selection.odds, closeTo(2.40, 1e-9));
      expect(selection.impliedProb, closeTo(0.4167, 1e-9));
    });

    test('falls back to the selection key when no Turkish label is stored', () {
      final selection = BulletinSelection.fromJson({
        'selection_key': 'draw',
        'odds': 3.4,
      });
      // bulletinSelectionLabelsTr covers the canonical keys.
      expect(selection.labelTr.isNotEmpty, isTrue);
    });

    test('treats a suspended selection as suspended', () {
      final selection = BulletinSelection.fromJson({
        'selection_key': 'away',
        'odds': 4.0,
        'suspended': true,
      });
      expect(selection.suspended, isTrue);
    });
  });

  group('BulletinPrediction.fromJson', () {
    test('reads the model payload including the blend breakdown', () {
      final prediction = BulletinPrediction.fromJson({
        'id': 'p1',
        'bulletin_match_id': 'm1',
        'sports_api_match_id': 'sa1',
        'model_version': 'dc-v1',
        'generated_at': '2026-08-20T12:00:00Z',
        'lambda_home': 1.62,
        'lambda_away': 1.08,
        'rho': -0.03,
        'market_probs': {
          'MS': {'home': 0.52, 'draw': 0.25, 'away': 0.23},
        },
        'value_picks': [
          {
            'market_code': 'MS',
            'selection_key': 'home',
            'model_probability': 0.52,
            'odds_decimal': 2.10,
            'implied_probability': 0.476,
            'expected_value': 0.092,
            'kelly_stake': 0.021,
            'dc_probability': 0.55,
            'market_probability': 0.49,
          },
        ],
      });

      expect(prediction.lambdaHome, closeTo(1.62, 1e-9));
      expect(prediction.probabilityFor('MS', 'draw'), closeTo(0.25, 1e-9));
      expect(prediction.isValuePick('MS', 'home'), isTrue);
      expect(prediction.isValuePick('MS', 'away'), isFalse);

      final pick = prediction.valuePicks.single;
      // Both blend inputs must survive parsing or the "Bilimsel ayrıntı"
      // section silently loses the DC / market split.
      expect(pick.dcProbability, closeTo(0.55, 1e-9));
      expect(pick.marketProbability, closeTo(0.49, 1e-9));
    });

    test('tolerates rows written before the blend fields existed', () {
      final prediction = BulletinPrediction.fromJson({
        'id': 'p2',
        'bulletin_match_id': 'm2',
        'model_version': 'dc-v1',
        'lambda_home': 1.2,
        'lambda_away': 1.4,
        'market_probs': {},
        'value_picks': [
          {
            'market_code': 'AU_2_5',
            'selection_key': 'over',
            'model_probability': 0.58,
            'odds_decimal': 1.90,
            'expected_value': 0.102,
          },
        ],
      });

      final pick = prediction.valuePicks.single;
      expect(pick.dcProbability, isNull);
      expect(pick.marketProbability, isNull);
      expect(pick.kellyStake, isNull);
      expect(pick.expectedValue, closeTo(0.102, 1e-9));
    });

    test('drops market entries with no usable probabilities', () {
      final prediction = BulletinPrediction.fromJson({
        'id': 'p3',
        'bulletin_match_id': 'm3',
        'market_probs': {
          'MS': {'home': 0.5, 'draw': 0.3, 'away': 0.2},
          'KG': <String, dynamic>{},
        },
        'value_picks': const [],
      });

      expect(prediction.marketProbs.containsKey('MS'), isTrue);
      expect(prediction.marketProbs.containsKey('KG'), isFalse);
      expect(prediction.probabilityFor('KG', 'yes'), isNull);
    });

    test('round-trips through toJson', () {
      final original = BulletinPrediction.fromJson({
        'id': 'p4',
        'bulletin_match_id': 'm4',
        'model_version': 'dc-v1',
        'lambda_home': 1.5,
        'lambda_away': 1.1,
        'market_probs': {
          'MS': {'home': 0.5, 'draw': 0.3, 'away': 0.2},
        },
        'value_picks': const [],
      });
      final restored = BulletinPrediction.fromJson(original.toJson());
      expect(restored.lambdaHome, original.lambdaHome);
      expect(
        restored.probabilityFor('MS', 'home'),
        original.probabilityFor('MS', 'home'),
      );
    });
  });

  group('BulletinMatch.fromJson', () {
    test('reads a bulletin row and reports its freshness', () {
      final match = BulletinMatch.fromJson({
        'id': 'm1',
        'sports_api_match_id': 'sa1',
        'event_date': '2026-08-20',
        'kickoff_at': '2026-08-20T17:00:00Z',
        'status': 'scheduled',
        'competition_name': 'Süper Lig',
        'home_team': 'Galatasaray',
        'away_team': 'Fenerbahçe',
        'mbs': 2,
        'updated_at': '2026-08-20T11:05:00Z',
      });

      expect(match.homeTeam, 'Galatasaray');
      expect(match.mbs, 2);
      // The freshness stamp in the bulletin header reads this.
      expect(match.updatedAt, isNotNull);
    });

    test('market and selection lookups return null instead of throwing', () {
      final match = BulletinMatch.fromJson({
        'id': 'm1',
        'home_team': 'A',
        'away_team': 'B',
        'kickoff_at': '2026-08-20T17:00:00Z',
      });
      expect(match.marketByCode('MS'), isNull);
    });
  });
}
