import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/knowledge_graph.dart';
import '../data/repositories/knowledge_graph_repository.dart';
import '../services/supabase_service.dart';
import 'match_provider.dart';
import '../models/match.dart' as model;

final knowledgeGraphRepositoryProvider = Provider<KnowledgeGraphRepository>((ref) {
  return KnowledgeGraphRepository(SupabaseService.client);
});

class KnowledgeGraphState {
  final List<UserInterest> currentInterests;
  final Map<String, double> matchScores; // Match ID -> Relevance Score
  final bool isLoading;

  const KnowledgeGraphState({
    this.currentInterests = const [],
    this.matchScores = const {},
    this.isLoading = false,
  });

  KnowledgeGraphState copyWith({
    List<UserInterest>? currentInterests,
    Map<String, double>? matchScores,
    bool? isLoading,
  }) {
    return KnowledgeGraphState(
      currentInterests: currentInterests ?? this.currentInterests,
      matchScores: matchScores ?? this.matchScores,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class KnowledgeGraphNotifier extends Notifier<KnowledgeGraphState> {
  @override
  KnowledgeGraphState build() {
    Future.microtask(_init);
    return const KnowledgeGraphState();
  }

  KnowledgeGraphRepository get _repo => ref.read(knowledgeGraphRepositoryProvider);

  Future<void> _init() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    state = state.copyWith(isLoading: true);
    final interests = await _repo.getUserInterests(user.id);
    state = state.copyWith(currentInterests: interests, isLoading: false);
  }

  /// Fire and forget tracking of user events
  void trackEvent({
    required String eventType,
    required String entityType,
    required String entityId,
    Map<String, dynamic> metadata = const {},
  }) {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    _repo.trackEvent(
      userId: user.id,
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      metadata: metadata,
    );

    // Soft-refresh the local state after tracking important events
    if (eventType == 'match_favorited' || eventType == 'prediction_placed') {
      Future.delayed(const Duration(seconds: 2), () {
        _init();
      });
    }
  }

  /// Fetches and scores active matches, then caches the scores in state
  Future<void> calculatePersonalizedFeed() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    final activeMatches = ref.read(matchStateProvider).matches;
    if (activeMatches.isEmpty) return;

    final matchData = activeMatches.map((m) => {
      'id': m.id,
      'home_team': m.homeTeam,
      'away_team': m.awayTeam,
      'league_id': m.leagueId,
    }).toList();

    state = state.copyWith(isLoading: true);
    final scoredList = await _repo.getPersonalizedMatchScores(
      userId: user.id,
      activeMatches: matchData,
    );

    final scoreMap = <String, double>{};
    for (final item in scoredList) {
      scoreMap[item['match_id'] as String] = (item['relevance_score'] as num).toDouble();
    }

    state = state.copyWith(matchScores: scoreMap, isLoading: false);
  }
}

final knowledgeGraphProvider = NotifierProvider<KnowledgeGraphNotifier, KnowledgeGraphState>(() {
  return KnowledgeGraphNotifier();
});

/// A derived provider that applies the personalized scores to the filtered match list
final personalizedMatchesProvider = Provider<List<model.Match>>((ref) {
  // We take the output of filteredMatchesProvider (so date/live filters still apply)
  final baseList = ref.watch(filteredMatchesProvider);
  final kgState = ref.watch(knowledgeGraphProvider);

  // If no scores are loaded, return an empty list
  if (kgState.matchScores.isEmpty) {
    return [];
  }

  // Filter to only include matches with a meaningful relevance score (>= 0.5)
  // The default fallback score from the backend is 0.1
  final personalizedList = baseList.where((m) {
    final score = kgState.matchScores[m.id] ?? 0.0;
    return score >= 0.5;
  }).toList();

  // Sort logically:
  // 1. First by Live vs Upcoming
  // 2. Then by relevance score
  // 3. Then by start time
  personalizedList.sort((a, b) {
    // 1. Live matches always win over upcoming/finished
    final aIsLive = a.status == model.MatchStatus.live;
    final bIsLive = b.status == model.MatchStatus.live;
    if (aIsLive && !bIsLive) return -1;
    if (!aIsLive && bIsLive) return 1;

    // 2. Compare Knowledge Graph scores
    final scoreA = kgState.matchScores[a.id] ?? 0.0;
    final scoreB = kgState.matchScores[b.id] ?? 0.0;
    
    // If there is a meaningful difference in score, rank by score
    if ((scoreA - scoreB).abs() > 0.01) {
      return scoreB.compareTo(scoreA); // Descending (higher score first)
    }

    // 3. Fallback to start time
    return a.startTime.compareTo(b.startTime);
  });

  return personalizedList;
});
