import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/knowledge_graph.dart';
import 'package:flutter/foundation.dart';

class KnowledgeGraphRepository {
  final SupabaseClient _client;

  KnowledgeGraphRepository(this._client);

  /// Records a user event (e.g., match_viewed, prediction_placed).
  /// Designed to be fire-and-forget.
  Future<void> trackEvent({
    required String userId,
    required String eventType,
    required String entityType,
    required String entityId,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _client.from('user_events').insert({
        'user_id': userId,
        'event_type': eventType,
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': metadata,
        // created_at is handled by DB default
      });
      // The DB trigger `async_update_interests` will automatically recalculate interests.
    } catch (e) {
      if (kDebugMode) print('Failed to track event $eventType: $e');
    }
  }

  /// Fetches the user's top interests
  Future<List<UserInterest>> getUserInterests(String userId) async {
    try {
      final response = await _client
          .from('user_interests')
          .select()
          .eq('user_id', userId)
          .order('interest_score', ascending: false)
          .limit(20);

      return (response as List).map((json) => UserInterest.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('Failed to fetch user interests: $e');
      return [];
    }
  }

  /// Manually triggers recalculation of interests
  Future<void> recalculateInterests(String userId) async {
    try {
      await _client.rpc('recalculate_user_interests', params: {'p_user_id': userId});
    } catch (e) {
      if (kDebugMode) print('Failed to recalculate interests: $e');
    }
  }

  /// Gets match IDs scored by personalized relevance for a given user.
  /// Pass in the current active match data to score them against user interests.
  Future<List<Map<String, dynamic>>> getPersonalizedMatchScores({
    required String userId,
    required List<Map<String, dynamic>> activeMatches,
  }) async {
    if (activeMatches.isEmpty) return [];

    try {
      // Create lightweight JSON representation for the DB function
      final matchData = activeMatches.map((m) => {
        'id': m['id'],
        'home': m['home_team'],
        'away': m['away_team'],
        'league': m['league_id'] ?? 'default',
      }).toList();

      final response = await _client.rpc(
        'get_personalized_match_scores',
        params: {
          'p_user_id': userId,
          'p_match_data': matchData,
        },
      );

      // response is a list of {match_id: 'x', relevance_score: 1.5}
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (kDebugMode) print('Failed to calculate personalized scores: $e');
      return [];
    }
  }
}
