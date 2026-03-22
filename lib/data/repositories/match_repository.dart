import '../../models/match.dart';

abstract class MatchRepository {
  /// Fetch a one-time list of all matches
  Future<List<Match>> getMatches();

  /// Listen to a real-time stream of live matches
  Stream<List<Match>> getMatchesStream();

  /// Proactively trigger the backend to fetch matches for a specific date
  Future<void> fetchMatchesForDate(DateTime date);
}
