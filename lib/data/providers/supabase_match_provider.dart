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
      homeLogo: data['home_logo_url'] ??
          'https://upload.wikimedia.org/wikipedia/en/thumb/5/53/Arsenal_FC.svg/1200px-Arsenal_FC.svg.png',
      awayLogo: data['away_logo_url'] ??
          'https://upload.wikimedia.org/wikipedia/en/thumb/c/cc/Chelsea_FC.svg/1200px-Chelsea_FC.svg.png',
      startTime: data['started_at'] != null
          ? DateTime.parse(data['started_at'])
          : DateTime.now(),
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
  Stream<List<model.Match>> getMatchesStream(DateTime date) {
    // Determine the exact bounds of the user's requested local day in UTC.
    // We expand 'startOfDay' back by 12 hours so we don't accidentally cut off matches
    // that started late "yesterday" but are still 'live' today across midnight.
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0)
        .subtract(const Duration(hours: 12))
        .toUtc()
        .toIso8601String();
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59)
        .toUtc()
        .toIso8601String();

    return _client
        .from('matches')
        .stream(primaryKey: ['id'])
        .gte('started_at', startOfDay)
        .order('started_at', ascending: true)
        .map((events) {
          // Apply the upper-bound filter client-side to strip matches beyond endOfDay
          return events
              .where((data) =>
                  (data['started_at'] as String).compareTo(endOfDay) <= 0)
              .map((data) => _mapMatch(data))
              .toList();
        });
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
      // In a real app we would log this properly using a telemetry service,
      // but for background syncing it's safe to silently fail rather than
      // polling the debug terminal every 10 seconds on expired active JWTs.
      // print("[SupabaseMatchProvider] Error fetching live matches: $e");
    }
  }

  @override
  Future<List<model.Match>> searchMatches(String query) async {
    final response = await _client
        .from('matches')
        .select('*')
        .or('home_team.ilike.%$query%,away_team.ilike.%$query%,league_name.ilike.%$query%')
        .order('started_at', ascending: false)
        .limit(50);

    return (response as List<dynamic>).map((data) => _mapMatch(data)).toList();
  }
}
