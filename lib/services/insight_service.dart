import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_insight.dart';

class InsightService {
  final SupabaseClient _client = Supabase.instance.client;

  // Fetch insights for a match
  Future<List<MatchInsight>> getInsightsForMatch(String matchId) async {
    final response = await _client
        .from('match_insights')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: false);

    return (response as List).map((json) {
      final agree = json['agree_count'] as int? ?? 0;
      final disagree = json['disagree_count'] as int? ?? 0;
      final unsure = json['unsure_count'] as int? ?? 0;
      final total = agree + disagree + unsure;
      
      int agreePercent = 0;
      int disagreePercent = 0;
      int unsurePercent = 0;
      
      if (total > 0) {
        agreePercent = ((agree / total) * 100).round();
        disagreePercent = ((disagree / total) * 100).round();
        unsurePercent = ((unsure / total) * 100).round();
      }

      return MatchInsight(
        id: json['id'],
        label: (json['type'] as String).toUpperCase(), // 'PRE-MATCH' or 'LIVE'
        text: json['text'],
        consensusData: ConsensusData(
          agreePercent: agreePercent,
          unsurePercent: unsurePercent,
          disagreePercent: disagreePercent,
        ),
      );
    }).toList();
  }

  // Trigger edge function to generate new insights
  Future<void> generateInsights(String matchId) async {
    await _client.functions.invoke('generate-insights', body: {
      'matchId': matchId,
    });
  }

  // Vote on an insight
  Future<void> voteInsight(String insightId, String matchId, UserVoteType vote, {String? reason, String? customReason}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    
    // Convert enum to string
    String voteString = 'unsure';
    if (vote == UserVoteType.agree) {
      voteString = 'agree';
    } else if (vote == UserVoteType.disagree) voteString = 'disagree';
    
    // Upsert vote
    await _client.from('user_insight_votes').upsert({
      'user_id': user.id,
      'insight_id': insightId,
      'vote': voteString,
      'disagree_reason': reason,
      'custom_reason': customReason,
    }, onConflict: 'user_id, insight_id');
  }
}
