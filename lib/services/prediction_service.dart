import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PredictionService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get active predictions for a specific match
  Future<List<Map<String, dynamic>>> getActivePredictions(
      String matchId) async {
    final response = await _client
        .from('predictions')
        .select()
        .eq('match_id', matchId)
        .eq('status', 'open');

    return List<Map<String, dynamic>>.from(response);
  }

  // Get all active predictions globally with match details
  Future<List<Map<String, dynamic>>> getAllActivePredictions() async {
    final response = await _client
        .from('predictions')
        .select(
            '*, matches(home_team, away_team, status, home_score, away_score, minute)')
        .eq('status', 'open')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Place a bet securely via RPC
  // [TODO KnowledgeGraph]: Call refs trackEvent(eventType: 'prediction_placed') when used
  Future<void> placeBet(
      String predictionId, int amount, int potentialPayout) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Use RPC to place bet and deduct balance securely in a transaction
    await _client.rpc('place_bet', params: {
      'p_user_id': user.id,
      'p_prediction_id': predictionId,
      'p_amount': amount,
      'p_request_id': const Uuid().v4(),
    });
  }

  // Get my bets
  Future<List<Map<String, dynamic>>> getMyBets() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final response = await _client.from('user_bets').select('''
          id,
          amount_staked,
          potential_payout,
          status,
          predictions (
            prediction_type,
            matches (
              home_team,
              away_team
            )
          )
        ''').eq('user_id', user.id).order('created_at', ascending: false);

    return (response as List).map((json) {
      final prediction = json['predictions'];
      final match = prediction['matches'];
      return {
        'id': json['id'],
        'match': '${match['home_team']} vs ${match['away_team']}',
        'prediction': prediction['prediction_type'],
        'staked': json['amount_staked'],
        'potentialPayout': json['potential_payout'],
        'status': json['status'],
      };
    }).toList();
  }
}
