import 'dart:async';
import '../../lib/models/match.dart';
import '../../lib/data/repositories/match_repository.dart';

/// In-memory mock implementation of [MatchRepository] for testing.
/// No Supabase connection required.
class MockMatchRepository implements MatchRepository {
  List<Match> _matches;
  final StreamController<List<Match>> _controller = StreamController<List<Match>>.broadcast();

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
  Stream<List<Match>> getMatchesStream() {
    // Emit current state immediately, then listen for updates
    Future.microtask(() => _controller.add(_matches));
    return _controller.stream;
  }

  void dispose() {
    _controller.close();
  }
}
