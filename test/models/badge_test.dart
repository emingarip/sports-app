import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/badge.dart';

void main() {
  group('Badge models', () {
    test('parse numeric fields from strings and doubles', () {
      final badge = Badge.fromJson({
        'id': 123,
        'name': 'Daily Login',
        'target': '5',
        'max_tier': 3.0,
        'tier2_target': '10',
        'tier3_target': 20.0,
        'points': '50',
        'sort_order': '2',
      });

      expect(badge.id, '123');
      expect(badge.triggerTarget, 5);
      expect(badge.maxTier, 3);
      expect(badge.tier2Target, 10);
      expect(badge.tier3Target, 20);
      expect(badge.kCoinReward, 50);
      expect(badge.sortOrder, 2);
    });

    test('parse user badge and streak without exact int casts', () {
      final userBadge = UserBadge.fromJson({
        'id': 456,
        'user_id': 789,
        'badge_id': 321,
        'current_tier': '2',
        'progress': 12.0,
      });

      final streak = UserStreak.fromJson({
        'user_id': 789,
        'current_streak': '4',
        'longest_streak': 6.0,
        'total_logins': '8',
        'last_login_date': '2026-05-08T00:00:00Z',
      });

      expect(userBadge.id, '456');
      expect(userBadge.userId, '789');
      expect(userBadge.badgeId, '321');
      expect(userBadge.currentTier, 2);
      expect(userBadge.progress, 12);
      expect(streak.userId, '789');
      expect(streak.currentStreak, 4);
      expect(streak.longestStreak, 6);
      expect(streak.totalLogins, 8);
      expect(streak.lastLoginDate, isNotNull);
    });
  });
}
