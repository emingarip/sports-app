import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/badge.dart';

/// Repository handling all Supabase interactions for the badge system.
class BadgeRepository {
  final SupabaseClient _client;

  BadgeRepository(this._client);

  /// Fetches all badge definitions.
  Future<List<Badge>> getAllBadges() async {
    final response = await _client
        .from('badges')
        .select()
        .order('sort_order', ascending: true);
    return (response as List<dynamic>)
        .map((e) => Badge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches all badge progress for a user.
  Future<List<UserBadge>> getUserBadges(String userId) async {
    final response = await _client
        .from('user_badges')
        .select()
        .eq('user_id', userId);
    return (response as List<dynamic>)
        .map((e) => UserBadge.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Gets or creates a user badge progress row.
  Future<UserBadge> getOrCreateUserBadge(String userId, String badgeId) async {
    final existing = await _client
        .from('user_badges')
        .select()
        .eq('user_id', userId)
        .eq('badge_id', badgeId)
        .maybeSingle();

    if (existing != null) {
      return UserBadge.fromJson(existing);
    }

    final newBadge = UserBadge(userId: userId, badgeId: badgeId);
    final inserted = await _client
        .from('user_badges')
        .insert(newBadge.toJson())
        .select()
        .single();
    return UserBadge.fromJson(inserted);
  }

  /// Updates progress and tier for a user badge.
  Future<UserBadge> updateBadgeProgress({
    required String userId,
    required String badgeId,
    required int newProgress,
    required int newTier,
    DateTime? unlockedAt,
    DateTime? lastTierUp,
  }) async {
    final data = <String, dynamic>{
      'progress': newProgress,
      'current_tier': newTier,
    };
    if (unlockedAt != null) data['unlocked_at'] = unlockedAt.toIso8601String();
    if (lastTierUp != null) data['last_tier_up'] = lastTierUp.toIso8601String();

    final result = await _client
        .from('user_badges')
        .update(data)
        .eq('user_id', userId)
        .eq('badge_id', badgeId)
        .select()
        .single();
    return UserBadge.fromJson(result);
  }

  /// Gets or creates the user's streak data.
  Future<UserStreak> getOrCreateStreak(String userId) async {
    final existing = await _client
        .from('user_streaks')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      return UserStreak.fromJson(existing);
    }

    await _client.from('user_streaks').insert({
      'user_id': userId,
      'current_streak': 0,
      'longest_streak': 0,
      'total_logins': 0,
    });

    return UserStreak(userId: userId);
  }

  /// Records a daily login and updates the streak.
  Future<UserStreak> recordDailyLogin(String userId) async {
    final streak = await getOrCreateStreak(userId);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // If already logged in today, skip
    if (streak.lastLoginDate != null) {
      final lastDate = DateTime(
        streak.lastLoginDate!.year,
        streak.lastLoginDate!.month,
        streak.lastLoginDate!.day,
      );
      if (lastDate == todayDate) return streak;
    }

    int newStreak = streak.currentStreak;
    if (streak.lastLoginDate != null) {
      final yesterday = todayDate.subtract(const Duration(days: 1));
      final lastDate = DateTime(
        streak.lastLoginDate!.year,
        streak.lastLoginDate!.month,
        streak.lastLoginDate!.day,
      );
      if (lastDate == yesterday) {
        newStreak += 1;
      } else {
        newStreak = 1; // Reset streak
      }
    } else {
      newStreak = 1;
    }

    final newLongest = newStreak > streak.longestStreak ? newStreak : streak.longestStreak;
    final newTotal = streak.totalLogins + 1;

    final result = await _client
        .from('user_streaks')
        .update({
          'current_streak': newStreak,
          'longest_streak': newLongest,
          'last_login_date': todayDate.toIso8601String().split('T').first,
          'total_logins': newTotal,
        })
        .eq('user_id', userId)
        .select()
        .single();

    return UserStreak.fromJson(result);
  }
}
