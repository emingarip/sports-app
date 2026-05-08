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
      final json = _asStringMap(response.data);
      final rules = _asMapList(json['badges']);
      return rules.map(Badge.fromJson).toList();
    }
    throw Exception('Failed to load badges: ${response.data}');
  }

  /// Fetches all badge progress for a user, as well as their stats.
  Future<(List<UserBadge>, Map<String, int>)> getUserBadges(
      String userId) async {
    final response = await _supabase.functions.invoke(
      'gamification-api-bridge',
      body: {
        'action': 'get_user_badges',
        'payload': {'user_id': userId},
      },
    );
    // 404 is handled inside the bridge or returns 404
    if (response.status == 200) {
      final json = _asStringMap(response.data);
      final badges = _asMapList(json['rich_badge_info'] ?? json['rich_badges']);
      final parsedBadges = badges.map(UserBadge.fromJson).toList();

      final statsRaw = _asStringMap(json['stats']);
      final stats = statsRaw.map((k, v) => MapEntry(k, _asInt(v)));

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
      return UserBadge(
          userId: userId, badgeId: badgeId, progress: 0, currentTier: 0);
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
      throw Exception(
          'Failed to send event to gamification system: ${response.data}');
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
    return UserBadge(
        userId: userId,
        badgeId: badgeId,
        progress: newProgress,
        currentTier: newTier,
        unlockedAt: unlockedAt,
        lastTierUp: lastTierUp);
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
      final json = _asStringMap(response.data);
      final stats = _asStringMap(json['stats']);
      return UserStreak(
        userId: userId,
        currentStreak: _asInt(stats['daily_streak']),
      );
    }
    return UserStreak(userId: userId);
  }

  /// Records a daily login and updates the streak.
  Future<UserStreak> recordDailyLogin(String userId) async {
    await sendEvent(userId: userId, eventType: 'daily_login');
    return getOrCreateStreak(userId);
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! Iterable) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
