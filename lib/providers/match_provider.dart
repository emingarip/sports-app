import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart' as model;
import '../data/providers/supabase_match_provider.dart';
import '../data/repositories/match_repository.dart';
import 'favorites_provider.dart';

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return SupabaseMatchProvider();
});

enum MatchStatusFilter { all, live, finished }

class MatchState {
  final List<model.Match> matches;
  final MatchStatusFilter statusFilter;
  final bool starredOnly;
  final DateTime selectedDate;
  final bool isLoading;

  MatchState({
    required this.matches,
    this.statusFilter = MatchStatusFilter.all,
    this.starredOnly = false,
    required this.selectedDate,
    this.isLoading = false,
  });

  bool get isAll => statusFilter == MatchStatusFilter.all && !starredOnly;
  bool get isLiveOnly => statusFilter == MatchStatusFilter.live;
  bool get isFinishedOnly => statusFilter == MatchStatusFilter.finished;
  String get filterSelectionKey =>
      '${statusFilter.name}:${starredOnly ? 1 : 0}';

  MatchState copyWith({
    List<model.Match>? matches,
    MatchStatusFilter? statusFilter,
    bool? starredOnly,
    DateTime? selectedDate,
    bool? isLoading,
  }) {
    return MatchState(
      matches: matches ?? this.matches,
      statusFilter: statusFilter ?? this.statusFilter,
      starredOnly: starredOnly ?? this.starredOnly,
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

    return MatchState(matches: [], selectedDate: DateTime.now());
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
    switch (filter) {
      case 'Live 🔴':
        toggleLiveFilter();
        break;
      case 'Finished':
        toggleFinishedFilter();
        break;
      case 'Starred ⭐':
        toggleStarredFilter();
        break;
      default:
        clearFilters();
    }
  }

  void clearFilters() {
    state = state.copyWith(
      statusFilter: MatchStatusFilter.all,
      starredOnly: false,
    );
  }

  void toggleLiveFilter() {
    state = state.copyWith(
      statusFilter: state.statusFilter == MatchStatusFilter.live
          ? MatchStatusFilter.all
          : MatchStatusFilter.live,
    );
  }

  void toggleFinishedFilter() {
    state = state.copyWith(
      statusFilter: state.statusFilter == MatchStatusFilter.finished
          ? MatchStatusFilter.all
          : MatchStatusFilter.finished,
    );
  }

  void toggleStarredFilter() {
    state = state.copyWith(starredOnly: !state.starredOnly);
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

    if (matchState.starredOnly && !favorites.contains(m.id)) {
      return false;
    }

    if (matchState.statusFilter == MatchStatusFilter.live) {
      return m.status == model.MatchStatus.live;
    }

    if (matchState.statusFilter == MatchStatusFilter.finished) {
      return m.status == model.MatchStatus.finished;
    }

    return true;
  }).toList();
});
