import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/reward_claim_result.dart';

void main() {
  test('RewardClaimResult parses settlement payloads', () {
    final result = RewardClaimResult.fromJson({
      'success': true,
      'points_awarded': 50,
      'new_balance': 1450,
      'transaction_id': 'tx_123',
      'matched_rules': ['Ad Watched Reward', 'Daily Multiplier'],
      'badges_awarded': ['first_ad'],
      'already_applied': false,
    });

    expect(result.success, isTrue);
    expect(result.pointsAwarded, 50);
    expect(result.newBalance, 1450);
    expect(result.transactionId, 'tx_123');
    expect(result.matchedRules, ['Ad Watched Reward', 'Daily Multiplier']);
    expect(result.badgesAwarded, ['first_ad']);
    expect(result.alreadyApplied, isFalse);
  });

  test('RewardClaimResult falls back safely for malformed arrays', () {
    final result = RewardClaimResult.fromJson({
      'success': true,
      'points_awarded': 0,
      'matched_rules': 'invalid',
      'badges_awarded': null,
      'already_applied': true,
    });

    expect(result.pointsAwarded, 0);
    expect(result.matchedRules, isEmpty);
    expect(result.badgesAwarded, isEmpty);
    expect(result.alreadyApplied, isTrue);
  });
}
