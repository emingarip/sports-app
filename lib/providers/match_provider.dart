import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers/supabase_match_provider.dart';
import '../data/repositories/match_repository.dart';
import '../models/league.dart';
import '../models/match.dart' as model;
import '../models/match_list_view_model.dart';
import 'favorites_provider.dart';

final matchRepositoryProvider = Provider<MatchRepository>((ref) {
  return SupabaseMatchProvider();
});

enum StatusFilter { all, live, finished }

class LeagueMatchSection {
  final League league;
  final List<MatchListItemViewModel> items;

  const LeagueMatchSection({
    required this.league,
    required this.items,
  });

  bool get hasLiveMatch =>
      items.any((item) => item.match.status == model.MatchStatus.live);
}

class MatchState {
  final List<model.Match> matches;
  final StatusFilter statusFilter;
  final bool isStarredFilter;
  final bool isInlineSearchOpen;
  final String inlineSearchQuery;
  final DateTime selectedDate;
  final bool isLoading;

  MatchState({
    required this.matches,
    required this.statusFilter,
    required this.isStarredFilter,
    required this.isInlineSearchOpen,
    required this.inlineSearchQuery,
    required this.selectedDate,
    this.isLoading = false,
  });

  MatchState copyWith({
    List<model.Match>? matches,
    StatusFilter? statusFilter,
    bool? isStarredFilter,
    bool? isInlineSearchOpen,
    String? inlineSearchQuery,
    DateTime? selectedDate,
    bool? isLoading,
  }) {
    return MatchState(
      matches: matches ?? this.matches,
      statusFilter: statusFilter ?? this.statusFilter,
      isStarredFilter: isStarredFilter ?? this.isStarredFilter,
      isInlineSearchOpen: isInlineSearchOpen ?? this.isInlineSearchOpen,
      inlineSearchQuery: inlineSearchQuery ?? this.inlineSearchQuery,
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
    WidgetsBinding.instance.addObserver(this);
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
      isInlineSearchOpen: false,
      inlineSearchQuery: '',
      selectedDate: DateTime.now(),
    );
  }

  void _initStream(DateTime date) {
    final repo = ref.read(matchRepositoryProvider);
    _subscription?.cancel();
    _subscription = repo.getMatchesStream(date).listen((data) {
      state = state.copyWith(matches: data);
    });

    repo.fetchMatchesForDate(DateTime.now());
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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
      final now = DateTime.now();
      if (state.selectedDate.year == now.year &&
          state.selectedDate.month == now.month &&
          state.selectedDate.day == now.day) {
        ref.read(matchRepositoryProvider).fetchMatchesForDate(now);
      }
      _startPolling();
    } else if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.hidden) {
      debugPrint(
          'App in background: pausing match polling timer to save battery.');
      _pollingTimer?.cancel();
    }
  }

  void setFilter(StatusFilter filter) {
    state = state.copyWith(statusFilter: filter);
  }

  void toggleStarred() {
    state = state.copyWith(isStarredFilter: !state.isStarredFilter);
  }

  void openInlineSearch() {
    state = state.copyWith(isInlineSearchOpen: true);
  }

  void closeInlineSearch() {
    state = state.copyWith(
      isInlineSearchOpen: false,
      inlineSearchQuery: '',
    );
  }

  void clearInlineSearchQuery() {
    state = state.copyWith(inlineSearchQuery: '');
  }

  void setInlineSearchQuery(String query) {
    state = state.copyWith(
      isInlineSearchOpen: true,
      inlineSearchQuery: query,
    );
  }

  Future<void> setDate(DateTime date) async {
    if (_isSameCalendarDay(state.selectedDate, date)) {
      return;
    }

    state = state.copyWith(selectedDate: date, isLoading: true);

    try {
      _initStream(date);
      await ref.read(matchRepositoryProvider).fetchMatchesForDate(date);
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(isLoading: false);
    }
  }

  model.Match? get activeLiveMatch {
    if (state.matches.isEmpty) return null;
    return state.matches.firstWhere(
      (match) => match.status == model.MatchStatus.live,
      orElse: () => state.matches.first,
    );
  }
}

final matchStateProvider = NotifierProvider<MatchNotifier, MatchState>(() {
  return MatchNotifier();
});

bool _isSameCalendarDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

bool _isViewingToday(DateTime selectedDate, DateTime now) {
  return _isSameCalendarDay(selectedDate, now);
}

int? parseLiveMinute(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final match = RegExp(r'\d+').firstMatch(value);
  return match == null ? null : int.tryParse(match.group(0)!);
}

int scoreDifference(model.Match match) {
  final homeScore = int.tryParse(match.homeScore ?? '') ?? 0;
  final awayScore = int.tryParse(match.awayScore ?? '') ?? 0;
  return (homeScore - awayScore).abs();
}

bool isStartingSoonMatch(model.Match match, DateTime now) {
  if (match.status != model.MatchStatus.upcoming) return false;
  final difference = match.startTime.toLocal().difference(now.toLocal());
  return !difference.isNegative && difference <= const Duration(hours: 2);
}

bool isLiveCriticalMatch(model.Match match) {
  if (match.status != model.MatchStatus.live) return false;
  return scoreDifference(match) <= 1;
}

int _matchStatusPriority(model.MatchStatus status) {
  switch (status) {
    case model.MatchStatus.live:
      return 0;
    case model.MatchStatus.upcoming:
      return 1;
    case model.MatchStatus.finished:
      return 2;
  }
}

int compareMatches(model.Match a, model.Match b) {
  final priorityCompare =
      _matchStatusPriority(a.status).compareTo(_matchStatusPriority(b.status));
  if (priorityCompare != 0) return priorityCompare;

  final startTimeCompare = a.startTime.compareTo(b.startTime);
  if (startTimeCompare != 0) return startTimeCompare;

  final homeCompare = a.homeTeam.compareTo(b.homeTeam);
  if (homeCompare != 0) return homeCompare;

  return a.awayTeam.compareTo(b.awayTeam);
}

MatchPriorityBucket getMatchPriorityBucket(
  model.Match match, {
  required Set<String> favorites,
  required DateTime now,
}) {
  final isFavorite = favorites.contains(match.id);

  if (match.status == model.MatchStatus.live && isFavorite) {
    return MatchPriorityBucket.favoriteLive;
  }
  if (match.status == model.MatchStatus.live && isLiveCriticalMatch(match)) {
    return MatchPriorityBucket.liveCritical;
  }
  if (match.status == model.MatchStatus.live) {
    return MatchPriorityBucket.liveOther;
  }

  if (isStartingSoonMatch(match, now) && isFavorite) {
    return MatchPriorityBucket.favoriteStartingSoon;
  }
  if (isStartingSoonMatch(match, now)) {
    return MatchPriorityBucket.startingSoon;
  }
  if (match.status == model.MatchStatus.upcoming && isFavorite) {
    return MatchPriorityBucket.favoriteLaterToday;
  }
  if (match.status == model.MatchStatus.upcoming) {
    return MatchPriorityBucket.laterToday;
  }

  return MatchPriorityBucket.finished;
}

String _formatMatchTime(DateTime time) {
  final localTime = time.toLocal();
  return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
}

String buildMatchStatusLabel(model.Match match) {
  switch (match.status) {
    case model.MatchStatus.live:
      final minute = parseLiveMinute(match.liveMinute);
      if (minute != null) return '$minute. dk';
      return match.liveMinute ?? 'CANLI';
    case model.MatchStatus.upcoming:
      return _formatMatchTime(match.startTime);
    case model.MatchStatus.finished:
      return 'Tamamlandi';
  }
}

String? buildMatchReasonLabel(
  model.Match match, {
  required Set<String> favorites,
  required DateTime now,
}) {
  if (favorites.contains(match.id)) {
    return 'Favori';
  }
  if (isLiveCriticalMatch(match)) {
    return 'Canli kritik';
  }
  if (isStartingSoonMatch(match, now)) {
    return 'Yakinda basliyor';
  }
  if (match.isFeatured) {
    return 'One cikan mac';
  }
  return null;
}

String? buildMatchSecondaryLabel(model.Match match, DateTime now) {
  switch (match.status) {
    case model.MatchStatus.live:
      final difference = scoreDifference(match);
      final minute = parseLiveMinute(match.liveMinute) ?? 0;
      if (difference == 0) return 'Berabere';
      if (difference == 1) return '1 fark';
      if (minute >= 75) return 'Gec bolum';
      return null;
    case model.MatchStatus.upcoming:
      if (!isStartingSoonMatch(match, now)) return null;
      final difference = match.startTime.toLocal().difference(now.toLocal());
      final minutes = difference.inMinutes.clamp(0, 120);
      return '$minutes dk sonra';
    case model.MatchStatus.finished:
      return null;
  }
}

MatchListItemViewModel buildMatchListItemViewModel(
  model.Match match, {
  required Set<String> favorites,
  required DateTime now,
}) {
  return MatchListItemViewModel(
    match: match,
    priorityBucket: getMatchPriorityBucket(
      match,
      favorites: favorites,
      now: now,
    ),
    reasonLabel: buildMatchReasonLabel(
      match,
      favorites: favorites,
      now: now,
    ),
    statusLabel: buildMatchStatusLabel(match),
    secondaryLabel: buildMatchSecondaryLabel(match, now),
  );
}

int compareMatchListItems(MatchListItemViewModel a, MatchListItemViewModel b) {
  final bucketCompare =
      a.priorityBucket.index.compareTo(b.priorityBucket.index);
  if (bucketCompare != 0) return bucketCompare;

  final leftMatch = a.match;
  final rightMatch = b.match;

  if (leftMatch.status == model.MatchStatus.live &&
      rightMatch.status == model.MatchStatus.live) {
    final minuteCompare = (parseLiveMinute(rightMatch.liveMinute) ?? -1)
        .compareTo(parseLiveMinute(leftMatch.liveMinute) ?? -1);
    if (minuteCompare != 0) return minuteCompare;

    final diffCompare = scoreDifference(leftMatch).compareTo(
      scoreDifference(rightMatch),
    );
    if (diffCompare != 0) return diffCompare;

    final startCompare = leftMatch.startTime.compareTo(rightMatch.startTime);
    if (startCompare != 0) return startCompare;
  }

  if (leftMatch.status == model.MatchStatus.upcoming &&
      rightMatch.status == model.MatchStatus.upcoming) {
    final startCompare = leftMatch.startTime.compareTo(rightMatch.startTime);
    if (startCompare != 0) return startCompare;
  }

  if (leftMatch.status == model.MatchStatus.finished &&
      rightMatch.status == model.MatchStatus.finished) {
    final finishCompare = rightMatch.startTime.compareTo(leftMatch.startTime);
    if (finishCompare != 0) return finishCompare;
  }

  return compareMatches(leftMatch, rightMatch);
}

SearchMatchEntityType _matchedEntityTypeForScore({
  required bool teamMatched,
  required bool leagueMatched,
}) {
  if (teamMatched && leagueMatched) return SearchMatchEntityType.mixed;
  if (leagueMatched) return SearchMatchEntityType.league;
  return SearchMatchEntityType.team;
}

bool _matchesWordPrefix(String value, String token) {
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .any((part) => part.startsWith(token));
}

SearchMatchResultViewModel? scoreMatchSearchResult(
  model.Match match,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return null;

  final home = match.homeTeam.toLowerCase();
  final away = match.awayTeam.toLowerCase();
  final league = (match.leagueName ?? '').toLowerCase();
  final teamCorpus = '$home $away';
  final fullCorpus = '$teamCorpus $league';
  final tokens = normalizedQuery
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();

  final exactTeam = normalizedQuery == home || normalizedQuery == away;
  final exactLeague = normalizedQuery == league && league.isNotEmpty;
  final teamPrefix =
      home.startsWith(normalizedQuery) || away.startsWith(normalizedQuery);
  final leaguePrefix = league.isNotEmpty && league.startsWith(normalizedQuery);
  final teamTokenPrefix = tokens.isNotEmpty &&
      tokens.every(
        (token) =>
            _matchesWordPrefix(home, token) || _matchesWordPrefix(away, token),
      );
  final leagueTokenPrefix = league.isNotEmpty &&
      tokens.isNotEmpty &&
      tokens.every((token) => _matchesWordPrefix(league, token));
  final teamSubstring =
      teamCorpus.contains(normalizedQuery) && normalizedQuery.isNotEmpty;
  final leagueSubstring =
      league.contains(normalizedQuery) && normalizedQuery.isNotEmpty;
  final tokenSubstring =
      tokens.isNotEmpty && tokens.every((token) => fullCorpus.contains(token));

  if (!(exactTeam ||
      exactLeague ||
      teamPrefix ||
      leaguePrefix ||
      teamTokenPrefix ||
      leagueTokenPrefix ||
      teamSubstring ||
      leagueSubstring ||
      tokenSubstring)) {
    return null;
  }

  late final int score;
  late final bool teamMatched;
  late final bool leagueMatched;

  if (exactTeam) {
    score = 1000;
    teamMatched = true;
    leagueMatched = false;
  } else if (exactLeague) {
    score = 950;
    teamMatched = false;
    leagueMatched = true;
  } else if (teamPrefix) {
    score = 900;
    teamMatched = true;
    leagueMatched = false;
  } else if (leaguePrefix) {
    score = 850;
    teamMatched = false;
    leagueMatched = true;
  } else if (teamTokenPrefix) {
    score = 800;
    teamMatched = true;
    leagueMatched = false;
  } else if (leagueTokenPrefix) {
    score = 760;
    teamMatched = false;
    leagueMatched = true;
  } else if (teamSubstring) {
    score = 700;
    teamMatched = true;
    leagueMatched = leagueSubstring;
  } else if (leagueSubstring) {
    score = 650;
    teamMatched = false;
    leagueMatched = true;
  } else {
    score = 600;
    teamMatched = teamSubstring;
    leagueMatched = leagueSubstring || !teamSubstring;
  }

  return SearchMatchResultViewModel(
    match: match,
    score: score,
    matchedEntityType: _matchedEntityTypeForScore(
      teamMatched: teamMatched,
      leagueMatched: leagueMatched,
    ),
  );
}

List<SearchMatchResultViewModel> rankMatchSearchResults({
  required Iterable<model.Match> matches,
  required String query,
}) {
  final results = matches
      .map((match) => scoreMatchSearchResult(match, query))
      .whereType<SearchMatchResultViewModel>()
      .toList();

  results.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return compareMatches(a.match, b.match);
  });

  return results;
}

List<SearchMatchResultViewModel> mergeRankedSearchResults(
  Iterable<SearchMatchResultViewModel> left,
  Iterable<SearchMatchResultViewModel> right,
) {
  final merged = <String, SearchMatchResultViewModel>{};

  for (final result in [...left, ...right]) {
    final existing = merged[result.match.id];
    if (existing == null ||
        result.score > existing.score ||
        (result.score == existing.score &&
            compareMatches(result.match, existing.match) < 0)) {
      merged[result.match.id] = result;
    }
  }

  final results = merged.values.toList();
  results.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return compareMatches(a.match, b.match);
  });
  return results;
}

final baseFilteredMatchesProvider = Provider<List<model.Match>>((ref) {
  final matchState = ref.watch(matchStateProvider);
  final favorites = ref.watch(favoritesProvider);

  return matchState.matches.where((match) {
    final localStart = match.startTime.toLocal();
    final localSelected = matchState.selectedDate.toLocal();
    final now = DateTime.now().toLocal();

    final isSameDay = localStart.year == localSelected.year &&
        localStart.month == localSelected.month &&
        localStart.day == localSelected.day;

    final shouldShowByDate = isSameDay ||
        (_isViewingToday(localSelected, now) &&
            match.status == model.MatchStatus.live);

    if (!shouldShowByDate) return false;

    if (matchState.isStarredFilter && !favorites.contains(match.id)) {
      return false;
    }
    if (matchState.statusFilter == StatusFilter.live &&
        match.status != model.MatchStatus.live) {
      return false;
    }
    if (matchState.statusFilter == StatusFilter.finished &&
        match.status != model.MatchStatus.finished) {
      return false;
    }

    return true;
  }).toList();
});

final inlineSearchResultsProvider =
    Provider<List<SearchMatchResultViewModel>>((ref) {
  final query = ref.watch(
    matchStateProvider.select((state) => state.inlineSearchQuery.trim()),
  );

  if (query.isEmpty) {
    return const [];
  }

  return rankMatchSearchResults(
    matches: ref.watch(baseFilteredMatchesProvider),
    query: query,
  );
});

final filteredMatchesProvider = Provider<List<model.Match>>((ref) {
  final query = ref.watch(
    matchStateProvider.select((state) => state.inlineSearchQuery.trim()),
  );

  if (query.isEmpty) {
    return ref.watch(baseFilteredMatchesProvider);
  }

  return ref
      .watch(inlineSearchResultsProvider)
      .map((result) => result.match)
      .toList();
});

final sortedFilteredMatchesProvider = Provider<List<model.Match>>((ref) {
  final matches = [...ref.watch(filteredMatchesProvider)];
  matches.sort(compareMatches);
  return matches;
});

final matchListItemsProvider = Provider<List<MatchListItemViewModel>>((ref) {
  final favorites = ref.watch(favoritesProvider);
  final now = DateTime.now();
  final query = ref.watch(
    matchStateProvider.select((state) => state.inlineSearchQuery.trim()),
  );

  final items = (query.isEmpty
          ? ref.watch(filteredMatchesProvider)
          : ref
              .watch(inlineSearchResultsProvider)
              .map((result) => result.match))
      .map((match) {
    return buildMatchListItemViewModel(
      match,
      favorites: favorites,
      now: now,
    );
  }).toList();

  if (query.isEmpty) {
    items.sort(compareMatchListItems);
  }
  return items;
});

MatchListItemViewModel _ensureFeaturedReason(MatchListItemViewModel item) {
  if (item.reasonLabel != null) return item;
  return item.copyWith(reasonLabel: 'One cikan mac');
}

final featuredMatchItemsProvider =
    Provider<List<MatchListItemViewModel>>((ref) {
  final items = ref.watch(matchListItemsProvider);
  final activeItems = items
      .where((item) => item.match.status != model.MatchStatus.finished)
      .toList();
  final source = activeItems.isNotEmpty ? activeItems : items;
  return source.take(3).map(_ensureFeaturedReason).toList();
});

final featuredMatchIdsProvider = Provider<Set<String>>((ref) {
  return ref
      .watch(featuredMatchItemsProvider)
      .map((item) => item.match.id)
      .toSet();
});

final remainingMatchItemsProvider =
    Provider<List<MatchListItemViewModel>>((ref) {
  final featuredIds = ref.watch(featuredMatchIdsProvider);
  return ref
      .watch(matchListItemsProvider)
      .where((item) => !featuredIds.contains(item.match.id))
      .toList();
});

final liveNowSectionProvider = Provider<MatchSectionViewModel?>((ref) {
  final items = ref
      .watch(remainingMatchItemsProvider)
      .where((item) => item.match.status == model.MatchStatus.live)
      .toList();
  if (items.isEmpty) return null;
  return MatchSectionViewModel(title: 'Canli Simdi', items: items);
});

final startingSoonSectionProvider = Provider<MatchSectionViewModel?>((ref) {
  final now = DateTime.now();
  final items = ref
      .watch(remainingMatchItemsProvider)
      .where((item) => isStartingSoonMatch(item.match, now))
      .toList();
  if (items.isEmpty) return null;
  return MatchSectionViewModel(title: 'Yakinda Basliyor', items: items);
});

final otherMatchesSectionProvider = Provider<MatchSectionViewModel?>((ref) {
  final now = DateTime.now();
  final items = ref.watch(remainingMatchItemsProvider).where((item) {
    return item.match.status != model.MatchStatus.live &&
        !isStartingSoonMatch(item.match, now);
  }).toList();
  if (items.isEmpty) return null;
  return MatchSectionViewModel(
    title: 'Diger Maclar',
    items: items,
    groupedByLeague: true,
  );
});

final leagueMatchSectionsProvider = Provider<List<LeagueMatchSection>>((ref) {
  final otherSection = ref.watch(otherMatchesSectionProvider);
  if (otherSection == null) return const [];

  final groupedItems = <String, List<MatchListItemViewModel>>{};
  for (final item in otherSection.items) {
    groupedItems.putIfAbsent(item.match.leagueId, () => []).add(item);
  }

  final sections = groupedItems.entries.map((entry) {
    final representative = entry.value.first.match;
    return LeagueMatchSection(
      league: League(
        id: entry.key,
        name: representative.leagueName ?? 'League ${entry.key}',
        logoUrl: representative.leagueLogoUrl ??
            'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
        tier: 3,
      ),
      items: entry.value,
    );
  }).toList();

  sections.sort((a, b) {
    final aPriority = a.items
        .map((item) => item.priorityBucket.index)
        .fold<int>(999, math.min);
    final bPriority = b.items
        .map((item) => item.priorityBucket.index)
        .fold<int>(999, math.min);
    final priorityCompare = aPriority.compareTo(bPriority);
    if (priorityCompare != 0) return priorityCompare;

    final startCompare =
        a.items.first.match.startTime.compareTo(b.items.first.match.startTime);
    if (startCompare != 0) return startCompare;

    return a.league.name.compareTo(b.league.name);
  });

  return sections;
});
