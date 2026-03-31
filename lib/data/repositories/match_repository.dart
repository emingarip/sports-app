import '../../models/match.dart';

abstract class MatchRepository {
  /// Fetch a one-time list of all matches
  Future<List<Match>> getMatches();

  /// Listen to a real-time stream of live matches for a specific date
  Stream<List<Match>> getMatchesStream(DateTime date);

  /// Proactively trigger the backend to fetch matches for a specific date
  Future<void> fetchMatchesForDate(DateTime date);

  /// Search the database for matches matching a text query
  Future<List<Match>> searchMatches(String query);
}
