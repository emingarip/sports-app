import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bulletin.dart';
import '../services/bulletin_service.dart';

final bulletinServiceProvider = Provider<BulletinService>(
  (ref) {
    return BulletinService();
  },
  name: 'bulletinServiceProvider',
);

/// Normalizes a date so that family providers cache per calendar day.
DateTime bulletinDateKey(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Bulletin matches (with nested odds) for a calendar day.
/// Always pass a key produced by [bulletinDateKey].
final bulletinProvider =
    FutureProvider.family<List<BulletinMatch>, DateTime>(
  (ref, date) async {
    final service = ref.read(bulletinServiceProvider);
    return await service.fetchBulletin(date: date);
  },
  name: 'bulletinProvider',
);

/// Latest time any bulletin row for the day was written, i.e. how fresh the
/// odds on screen are. The hourly sync stamps `updated_at`; without surfacing
/// it a user cannot tell a live price from an eight-hour-old one.
final bulletinLastUpdatedProvider =
    FutureProvider.family<DateTime?, DateTime>(
  (ref, date) async {
    final matches = await ref.watch(bulletinProvider(date).future);
    DateTime? latest;
    for (final match in matches) {
      final updatedAt = match.updatedAt;
      if (updatedAt == null) continue;
      if (latest == null || updatedAt.isAfter(latest)) latest = updatedAt;
    }
    return latest;
  },
  name: 'bulletinLastUpdatedProvider',
);

/// Keeps the visible bulletin in sync with the `bulletin_odds` realtime
/// channel.
///
/// Debounced: the hourly sync rewrites hundreds of rows in one burst, and
/// refetching per row would hammer the API for no benefit. Kept alive only
/// while something watches a bulletin day.
final bulletinRealtimeSyncProvider = Provider.family<void, DateTime>(
  (ref, date) {
    final service = ref.read(bulletinServiceProvider);
    Timer? debounce;

    final subscription = service.oddsChanges().listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(seconds: 3), () {
        ref.invalidate(bulletinProvider(date));
        ref.invalidate(bulletinPredictionsProvider(date));
      });
    });

    ref.onDispose(() {
      debounce?.cancel();
      subscription.cancel();
    });
  },
  name: 'bulletinRealtimeSyncProvider',
);

/// Bulletin matches keyed by the live-score (AI Sport Agent) match id, used to
/// enrich home match cards with odds. Only matches with a resolved agent link
/// are included. Always pass a key produced by [bulletinDateKey].
final bulletinByAgentMatchIdProvider =
    FutureProvider.family<Map<String, BulletinMatch>, DateTime>(
  (ref, date) async {
    final matches = await ref.watch(bulletinProvider(date).future);
    return {
      for (final match in matches)
        if (match.agentMatchId != null && match.agentMatchId!.isNotEmpty)
          match.agentMatchId!: match,
    };
  },
  name: 'bulletinByAgentMatchIdProvider',
);

/// Model predictions for the matches of a bulletin day, keyed by
/// `bulletin_match_id`. Always pass a key produced by [bulletinDateKey].
final bulletinPredictionsProvider =
    FutureProvider.family<Map<String, BulletinPrediction>, DateTime>(
  (ref, date) async {
    final matches = await ref.watch(bulletinProvider(date).future);
    if (matches.isEmpty) return const {};
    final service = ref.read(bulletinServiceProvider);
    return await service.fetchPredictions(
      matches.map((match) => match.id).toList(),
    );
  },
  name: 'bulletinPredictionsProvider',
);

/// Model prediction for a single bulletin match (analysis screen).
final bulletinPredictionProvider =
    FutureProvider.family<BulletinPrediction?, String>(
  (ref, bulletinMatchId) async {
    final service = ref.read(bulletinServiceProvider);
    return await service.fetchPrediction(bulletinMatchId);
  },
  name: 'bulletinPredictionProvider',
);

class BulletinFilterState {
  /// Market shown on the odds buttons of the bulletin list.
  final String marketCode;

  /// Selected competition name; null means all competitions.
  final String? leagueName;

  /// Show only matches that contain at least one model value pick.
  final bool onlyValuePicks;

  const BulletinFilterState({
    this.marketCode = 'MS',
    this.leagueName,
    this.onlyValuePicks = false,
  });

  BulletinFilterState copyWith({
    String? marketCode,
    String? leagueName,
    bool clearLeague = false,
    bool? onlyValuePicks,
  }) {
    return BulletinFilterState(
      marketCode: marketCode ?? this.marketCode,
      leagueName: clearLeague ? null : (leagueName ?? this.leagueName),
      onlyValuePicks: onlyValuePicks ?? this.onlyValuePicks,
    );
  }
}

class BulletinFilterNotifier extends Notifier<BulletinFilterState> {
  @override
  BulletinFilterState build() => const BulletinFilterState();

  void setMarket(String marketCode) {
    state = state.copyWith(marketCode: marketCode);
  }

  void setLeague(String? leagueName) {
    state = state.copyWith(leagueName: leagueName, clearLeague: leagueName == null);
  }

  void toggleOnlyValuePicks() {
    state = state.copyWith(onlyValuePicks: !state.onlyValuePicks);
  }
}

final bulletinFilterProvider =
    NotifierProvider<BulletinFilterNotifier, BulletinFilterState>(
  BulletinFilterNotifier.new,
  name: 'bulletinFilterProvider',
);
