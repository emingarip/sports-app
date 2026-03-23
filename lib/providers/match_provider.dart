import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart' as model;
import '../data/providers/supabase_match_provider.dart';
import '../data/repositories/match_repository.dart';
import 'favorites_provider.dart';

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return SupabaseMatchProvider();
});

class MatchState {
  final List<model.Match> matches;
  final String activeFilter;
  final DateTime selectedDate;
  final bool isLoading;

  MatchState({
    required this.matches,
    required this.activeFilter,
    required this.selectedDate,
    this.isLoading = false,
  });

  MatchState copyWith({
    List<model.Match>? matches,
    String? activeFilter,
    DateTime? selectedDate,
    bool? isLoading,
  }) {
    return MatchState(
      matches: matches ?? this.matches,
      activeFilter: activeFilter ?? this.activeFilter,
      selectedDate: selectedDate ?? this.selectedDate,
      isLoading: isLoading ?? this.isLoading,
    );
  }

}

class MatchNotifier extends Notifier<MatchState> {
  StreamSubscription<List<model.Match>>? _subscription;

  @override
  MatchState build() {
    // Keep subscription alive across rebuilds by avoiding immediate initialization if possible,
    // but here we are mounting a global stream.
    _initStream();
    
    ref.onDispose(() {
      _subscription?.cancel();
    });

    return MatchState(matches: [], activeFilter: 'All', selectedDate: DateTime.now());
  }

  void _initStream() {
    final repo = ref.read(matchRepositoryProvider);
    _subscription?.cancel();
    _subscription = repo.getMatchesStream().listen((data) {
      state = state.copyWith(matches: data);
    });
    
    // Explicitly seed the initial fetch for Today's matches since the default init 
    // bypasses the `setDate` network fetch correctly to avoid duplicate calls.
    repo.fetchMatchesForDate(DateTime.now());
  }

  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  Future<void> setDate(DateTime date) async {
    if (state.selectedDate.year == date.year && 
        state.selectedDate.month == date.month && 
        state.selectedDate.day == date.day) {
      return; // No need to re-fetch if same day
    }
    
    state = state.copyWith(selectedDate: date, isLoading: true);
    
    // Proactively fetch matches for the new date from the backend
    try {
      await ref.read(matchRepositoryProvider).fetchMatchesForDate(date);
    } finally {
      // Small delay ensures Realtime Stream has time to paint new rows before stripping skeleton
      await Future.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(isLoading: false);
    }
  }

  model.Match? get activeLiveMatch {
    if (state.matches.isEmpty) return null;
    return state.matches.firstWhere(
      (m) => m.status == model.MatchStatus.live, 
      orElse: () => state.matches.first,
    );
  }
}

final matchStateProvider = NotifierProvider<MatchNotifier, MatchState>(() {
  return MatchNotifier();
});

final filteredMatchesProvider = Provider<List<model.Match>>((ref) {
  final matchState = ref.watch(matchStateProvider);
  final favorites = ref.watch(favoritesProvider);
  
  return matchState.matches.where((m) {
    // Ensure the match falls on exactly the selected date for all filters (including Starred)
    final localStart = m.startTime.toLocal();
    final localSelected = matchState.selectedDate.toLocal();
    if (localStart.year != localSelected.year || 
        localStart.month != localSelected.month || 
        localStart.day != localSelected.day) {
      return false;
    }

    if (matchState.activeFilter == 'Starred ⭐') {
      return favorites.contains(m.id);
    }

    if (matchState.activeFilter == 'Live 🔴') return m.status == model.MatchStatus.live;
    if (matchState.activeFilter == 'Finished') return m.status == model.MatchStatus.finished;
    return true;
  }).toList();
});
