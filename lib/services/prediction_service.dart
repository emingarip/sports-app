import 'package:supabase_flutter/supabase_flutter.dart';

class PredictionService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get active predictions for a match
  Future<List<Map<String, dynamic>>> getActivePredictions(String matchId) async {
    final response = await _client
        .from('predictions')
        .select()
        .eq('match_id', matchId)
        .eq('resolved_status', 'pending');
        
    return List<Map<String, dynamic>>.from(response);
  }

  // Place a bet
  // [TODO KnowledgeGraph]: Call refs trackEvent(eventType: 'prediction_placed') when used
  Future<void> placeBet(String predictionId, int amount, int potentialPayout) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Use RPC to place bet and deduct balance securely in a transaction
    // Or just insert if we handle balance locally for MVP
    await _client.from('user_bets').insert({
      'user_id': user.id,
      'prediction_id': predictionId,
      'amount': amount,
      'potential_payout': potentialPayout,
      'status': 'pending'
    });
    
    // Deduct local user data balance (assuming users table has balance)
    // await _client.rpc('deduct_balance', params: {'user_id': user.id, 'amount': amount});
  }

  // Get my bets
  Future<List<Map<String, dynamic>>> getMyBets() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final response = await _client
        .from('user_bets')
        .select('''
          id,
          amount,
          potential_payout,
          status,
          predictions (
            title,
            matches (
              home_team,
              away_team
            )
          )
        ''')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (response as List).map((json) {
      final prediction = json['predictions'];
      final match = prediction['matches'];
      return {
        'id': json['id'],
        'match': '${match['home_team']} vs ${match['away_team']}',
        'prediction': prediction['title'],
        'staked': json['amount'],
        'potentialPayout': json['potential_payout'],
        'status': json['status'],
      };
    }).toList();
  }
}
