import 'dart:async';
import 'package:sports_app/models/match.dart';
import 'package:sports_app/data/repositories/match_repository.dart';

/// In-memory mock implementation of [MatchRepository] for testing.
/// No Supabase connection required.
class MockMatchRepository implements MatchRepository {
  List<Match> _matches;
  final StreamController<List<Match>> _controller =
      StreamController<List<Match>>.broadcast();

  MockMatchRepository({List<Match>? initialMatches})
      : _matches = initialMatches ?? [];

  /// Replaces the internal match list and broadcasts an update.
  void setMatches(List<Match> matches) {
    _matches = matches;
    _controller.add(_matches);
  }

  /// Adds a single match and broadcasts.
  void addMatch(Match match) {
    _matches.add(match);
    _controller.add(_matches);
  }

  @override
  Future<List<Match>> getMatches() async => _matches;

  @override
  Stream<List<Match>> getMatchesStream(DateTime date) {
    // Emit current state immediately, then listen for updates
    Future.microtask(() => _controller.add(_matches));
    return _controller.stream;
  }

  @override
  Future<void> fetchMatchesForDate(DateTime date) async {
    // Mock implementation does nothing, as we set matches explicitly in tests
    return;
  }

  @override
  Future<List<Match>> searchMatches(String query) async {
    if (query.isEmpty) {
      return _matches;
    }
    final lowerCaseQuery = query.toLowerCase();
    return _matches
        .where((match) =>
            match.homeTeam.toLowerCase().contains(lowerCaseQuery) ||
            match.awayTeam.toLowerCase().contains(lowerCaseQuery) ||
            (match.leagueName?.toLowerCase().contains(lowerCaseQuery) ?? false))
        .toList();
  }

  void dispose() {
    _controller.close();
  }
}
