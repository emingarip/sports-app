import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/badge.dart';

/// Repository handling all HTTP interactions for the badge system via GamificationSystem.
class BadgeRepository {
  final SupabaseClient _supabase;

  BadgeRepository({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  /// Fetches all badge definitions.
  Future<List<Badge>> getAllBadges() async {
    final response = await _supabase.functions.invoke(
      'gamification-api-bridge',
      body: {'action': 'get_badges'},
    );
    if (response.status == 200) {
      final json = response.data as Map<String, dynamic>;
      final List<dynamic> rules = json['badges'] ?? [];
      return rules.map((e) => Badge.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load badges: ${response.data}');
  }

  /// Fetches all badge progress for a user, as well as their stats.
  Future<(List<UserBadge>, Map<String, int>)> getUserBadges(String userId) async {
    final response = await _supabase.functions.invoke(
      'gamification-api-bridge',
      body: {
        'action': 'get_user_badges',
        'payload': {'user_id': userId},
      },
    );
    // 404 is handled inside the bridge or returns 404
    if (response.status == 200) {
      final json = response.data as Map<String, dynamic>;
      final List<dynamic> badges = json['rich_badge_info'] ?? json['rich_badges'] ?? [];
      final parsedBadges = badges.map((e) => UserBadge.fromJson(e as Map<String, dynamic>)).toList();
      
      final Map<String, dynamic> statsRaw = json['stats'] ?? {};
      final Map<String, int> stats = statsRaw.map((k, v) => MapEntry(k, v as int));
      
      return (parsedBadges, stats);
    }
    if (response.status == 404) {
      return (<UserBadge>[], <String, int>{});
    }
    throw Exception('Failed to load user badges: ${response.data}');
  }

  /// Gets or creates a user badge progress row.
  /// GamificationSystem handles this automatically, but we provide a fallback for local state.
  Future<UserBadge> getOrCreateUserBadge(String userId, String badgeId) async {
    final badgesResult = await getUserBadges(userId);
    final badges = badgesResult.$1;
    try {
      return badges.firstWhere((b) => b.badgeId == badgeId);
    } catch (_) {
      return UserBadge(userId: userId, badgeId: badgeId, progress: 0, currentTier: 0);
    }
  }

  /// Sends an event to GamificationSystem to be processed by the Rule Engine.
  Future<void> sendEvent({
    required String userId,
    required String eventType,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _supabase.functions.invoke(
      'gamification-api-bridge',
      body: {
        'action': 'send_event',
        'payload': {
          'user_id': userId,
          'event_type': eventType,
          'metadata': metadata ?? {},
        },
      },
    );
    if (response.status != 200 && response.status != 201) {
      throw Exception('Failed to send event to gamification system: ${response.data}');
    }
  }

  /// Updates progress and tier for a user badge.
  /// Deprecated: Logic is handled by backend now.
  Future<UserBadge> updateBadgeProgress({
    required String userId,
    required String badgeId,
    required int newProgress,
    required int newTier,
    DateTime? unlockedAt,
    DateTime? lastTierUp,
  }) async {
    // We mock this locally or refactor provider to avoid calling it, because the engine does the updates
    return UserBadge(userId: userId, badgeId: badgeId, progress: newProgress, currentTier: newTier, unlockedAt: unlockedAt, lastTierUp: lastTierUp);
  }

  /// Gets or creates the user's streak data.
  Future<UserStreak> getOrCreateStreak(String userId) async {
    final response = await _supabase.functions.invoke(
      'gamification-api-bridge',
      body: {
        'action': 'get_user_badges',
        'payload': {'user_id': userId},
      },
    );
    if (response.status == 200) {
      final json = response.data as Map<String, dynamic>;
      final stats = json['stats'] ?? {};
      return UserStreak(userId: userId, currentStreak: stats['daily_streak'] ?? 0);
    }
    return UserStreak(userId: userId);
  }

  /// Records a daily login and updates the streak.
  Future<UserStreak> recordDailyLogin(String userId) async {
    await sendEvent(userId: userId, eventType: 'daily_login');
    return getOrCreateStreak(userId);
  }
}

