import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/badge_repository.dart';
import '../models/badge.dart' as badge_model;
import '../services/supabase_service.dart';
import 'wallet_provider.dart';

/// Provider for the badge repository instance.
final badgeRepositoryProvider = Provider<BadgeRepository>((ref) {
  return BadgeRepository();
});

/// State holding both definitions and user progress.
class BadgeState {
  final List<badge_model.Badge> definitions;
  final Map<String, badge_model.UserBadge> userProgress;
  final badge_model.UserStreak streak;
  final bool isLoading;

  const BadgeState({
    this.definitions = const [],
    this.userProgress = const {},
    this.streak = const badge_model.UserStreak(userId: ''),
    this.isLoading = true,
  });

  BadgeState copyWith({
    List<badge_model.Badge>? definitions,
    Map<String, badge_model.UserBadge>? userProgress,
    badge_model.UserStreak? streak,
    bool? isLoading,
  }) {
    return BadgeState(
      definitions: definitions ?? this.definitions,
      userProgress: userProgress ?? this.userProgress,
      streak: streak ?? this.streak,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Get user progress for a badge.
  badge_model.UserBadge progressFor(String badgeId) {
    return userProgress[badgeId] ??
        badge_model.UserBadge(userId: streak.userId, badgeId: badgeId);
  }

  /// All badges grouped by category.
  Map<String, List<badge_model.Badge>> get groupedByCategory {
    final map = <String, List<badge_model.Badge>>{};
    for (final badge in definitions) {
      map.putIfAbsent(badge.category, () => []).add(badge);
    }
    return map;
  }

  /// Recently unlocked badges (last 5).
  List<badge_model.Badge> get recentlyUnlocked {
    final unlocked = definitions.where((b) {
      final p = userProgress[b.id];
      return p != null && p.unlockedAt != null;
    }).toList();

    unlocked.sort((a, b) {
      final pa = userProgress[a.id]!;
      final pb = userProgress[b.id]!;
      final ta = pa.unlockedAt ?? DateTime(2000);
      final tb = pb.unlockedAt ?? DateTime(2000);
      return tb.compareTo(ta);
    });

    return unlocked.take(5).toList();
  }

  /// Total unlocked count.
  int get unlockedCount =>
      userProgress.values.where((p) => p.unlockedAt != null).length;
}

/// Badge notifier using Riverpod's Notifier pattern (v3.x compatible).
class BadgeNotifier extends Notifier<BadgeState> {
  @override
  BadgeState build() {
    _initialize();
    return const BadgeState();
  }

  BadgeRepository get _repo => ref.read(badgeRepositoryProvider);

  Future<void> _initialize() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      final definitions = await _repo.getAllBadges();
      final userBadges = await _repo.getUserBadges(user.id);
      final streak = await _repo.getOrCreateStreak(user.id);

      final progressMap = <String, badge_model.UserBadge>{};
      for (final ub in userBadges) {
        progressMap[ub.badgeId] = ub;
      }

      state = BadgeState(
        definitions: definitions,
        userProgress: progressMap,
        streak: streak,
        isLoading: false,
      );
    } catch (e) {
      if (kDebugMode) print('Badge init error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Sends an event to the GamificationSystem and refreshes badges.
  Future<void> triggerEvent(String eventType, [Map<String, dynamic>? metadata]) async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;
    try {
      await _repo.sendEvent(userId: user.id, eventType: eventType, metadata: metadata);
      // Wait slightly for rules to process, then refresh
      await Future.delayed(const Duration(milliseconds: 500));
      await refresh();
      // Invalidate WalletBalance to fetch new balance from Gamification API
      ref.invalidate(walletBalanceProvider);
    } catch (e) {
      if (kDebugMode) print('Event trigger error: $e');
    }
  }

  /// Record a daily login and check streak badges.
  Future<void> recordLogin() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    try {
      final newStreak = await _repo.recordDailyLogin(user.id);
      state = state.copyWith(streak: newStreak);

      // Refresh to fetch newly awarded badges or points
      await refresh();
      ref.invalidate(walletBalanceProvider);
    } catch (e) {
      if (kDebugMode) print('Record login error: $e');
    }
  }

  /// Force refresh all badge data.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _initialize();
  }
}

/// Main badge provider.
final badgeProvider = NotifierProvider<BadgeNotifier, BadgeState>(() {
  return BadgeNotifier();
});

