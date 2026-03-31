import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/match.dart' as model;
import '../data/providers/supabase_match_provider.dart';
import '../data/repositories/match_repository.dart';
import 'favorites_provider.dart';

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return SupabaseMatchProvider();
});

enum StatusFilter { all, live, finished }

class MatchState {
  final List<model.Match> matches;
  final StatusFilter statusFilter;
  final bool isStarredFilter;
  final DateTime selectedDate;
  final bool isLoading;

  MatchState({
    required this.matches,
    required this.statusFilter,
    required this.isStarredFilter,
    required this.selectedDate,
    this.isLoading = false,
  });

  MatchState copyWith({
    List<model.Match>? matches,
    StatusFilter? statusFilter,
    bool? isStarredFilter,
    DateTime? selectedDate,
    bool? isLoading,
  }) {
    return MatchState(
      matches: matches ?? this.matches,
      statusFilter: statusFilter ?? this.statusFilter,
      isStarredFilter: isStarredFilter ?? this.isStarredFilter,
      selectedDate: selectedDate ?? this.selectedDate,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class MatchNotifier extends Notifier<MatchState> with WidgetsBindingObserver {
  StreamSubscription<List<model.Match>>? _subscription;
  Timer? _pollingTimer;

  @override
  MatchState build() {
    // Register the observer to handle AppLifecycleState changes
    WidgetsBinding.instance.addObserver(this);

    // Keep subscription alive across rebuilds by avoiding immediate initialization if possible,
    // but here we are mounting a global stream.
    _initStream(DateTime.now());

    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
      _pollingTimer?.cancel();
    });

    return MatchState(
        matches: [],
        statusFilter: StatusFilter.all,
        isStarredFilter: false,
        selectedDate: DateTime.now());
  }

  void _initStream(DateTime date) {
    final repo = ref.read(matchRepositoryProvider);
    _subscription?.cancel();
    _subscription = repo.getMatchesStream(date).listen((data) {
      state = state.copyWith(matches: data);
    });

    // Explicitly seed the initial fetch for Today's matches since the default init
    // bypasses the `setDate` network fetch correctly to avoid duplicate calls.
    repo.fetchMatchesForDate(DateTime.now());

    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Only poll from edge function if looking at today's matches
      final now = DateTime.now();
      if (state.selectedDate.year == now.year &&
          state.selectedDate.month == now.month &&
          state.selectedDate.day == now.day) {
        ref.read(matchRepositoryProvider).fetchMatchesForDate(now);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed) {
      // App is back in foreground, fetch latest immediately and resume polling
      final now = DateTime.now();
      if (state.selectedDate.year == now.year &&
          state.selectedDate.month == now.month &&
          state.selectedDate.day == now.day) {
        ref.read(matchRepositoryProvider).fetchMatchesForDate(now);
      }
      _startPolling();
    } else if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden) {
      // App is in background/hidden, save battery by cancelling the periodic poll
      debugPrint(
          "🔋 App in background: Pausing match polling timer to save battery.");
      _pollingTimer?.cancel();
    }
  }

  void setFilter(StatusFilter filter) {
    state = state.copyWith(statusFilter: filter);
  }

  void toggleStarred() {
    state = state.copyWith(isStarredFilter: !state.isStarredFilter);
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
      // Re-init the stream boundary to the new selected date 24-hr window bounds
      _initStream(date);
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
    final localStart = m.startTime.toLocal();
    final localSelected = matchState.selectedDate.toLocal();
    final now = DateTime.now().toLocal();

    // Check if match started on the strictly selected day
    bool isSameDay = localStart.year == localSelected.year &&
        localStart.month == localSelected.month &&
        localStart.day == localSelected.day;

    // Check if the user is looking at the "Today" view dynamically
    bool isViewingToday = now.year == localSelected.year &&
        now.month == localSelected.month &&
        now.day == localSelected.day;

    // A match should be visible if it is same day, OR if it's currently LIVE and the user is viewing Today.
    // This catches matches that started late yesterday but are still crossing midnight.
    bool shouldShowByDate =
        isSameDay || (isViewingToday && m.status == model.MatchStatus.live);

    if (!shouldShowByDate) {
      return false;
    }

    if (matchState.isStarredFilter && !favorites.contains(m.id)) {
      return false;
    }

    if (matchState.statusFilter == StatusFilter.live &&
        m.status != model.MatchStatus.live) return false;
    if (matchState.statusFilter == StatusFilter.finished &&
        m.status != model.MatchStatus.finished) return false;

    return true;
  }).toList();
});
