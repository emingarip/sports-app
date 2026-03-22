import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/match.dart' as model;
import '../repositories/match_repository.dart';

class SupabaseMatchProvider implements MatchRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // Transform raw Supabase data into our agnostic Match model
  model.Match _mapMatch(Map<String, dynamic> data) {
    model.MatchStatus status;
    switch (data['status']) {
      case 'live':
        status = model.MatchStatus.live;
        break;
      case 'finished':
        status = model.MatchStatus.finished;
        break;
      default:
        status = model.MatchStatus.upcoming;
    }

    return model.Match(
      id: data['id'],
      leagueId: data['league_id'] ?? 'premier_league',
      leagueName: data['league_name'],
      leagueLogoUrl: data['league_logo_url'],
      homeTeam: data['home_team'],
      awayTeam: data['away_team'],
      homeLogo: data['home_logo_url'] ?? 'https://upload.wikimedia.org/wikipedia/en/thumb/5/53/Arsenal_FC.svg/1200px-Arsenal_FC.svg.png',
      awayLogo: data['away_logo_url'] ?? 'https://upload.wikimedia.org/wikipedia/en/thumb/c/cc/Chelsea_FC.svg/1200px-Chelsea_FC.svg.png',
      startTime: data['started_at'] != null ? DateTime.parse(data['started_at']) : DateTime.now(),
      status: status,
      homeScore: data['home_score']?.toString(),
      awayScore: data['away_score']?.toString(),
      liveMinute: data['minute'],
    );
  }

  @override
  Future<List<model.Match>> getMatches() async {
    final response = await _client
        .from('matches')
        .select('*')
        .order('started_at', ascending: false);
    
    return (response as List<dynamic>).map((data) => _mapMatch(data)).toList();
  }

  @override
  Stream<List<model.Match>> getMatchesStream() {
    return _client
        .from('matches')
        .stream(primaryKey: ['id'])
        .map((events) => events.map((data) => _mapMatch(data)).toList());
  }

  @override
  Future<void> fetchMatchesForDate(DateTime date) async {
    try {
      final year = date.year.toString();
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final formattedDate = '$year-$month-$day';

      await _client.functions.invoke(
        'sync-live-matches',
        queryParameters: {'date': formattedDate},
      );
    } catch (e) {
      // In a real app we would log this properly or surface to UI,
      // but for background syncing it's safe to silently fail or print.
      print('Failed to sync matches for date $date: $e');
    }
  }
}
