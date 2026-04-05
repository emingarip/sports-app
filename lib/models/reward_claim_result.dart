class RewardClaimResult {
  final bool success;
  final int pointsAwarded;
  final int? newBalance;
  final String? transactionId;
  final List<String> matchedRules;
  final List<String> badgesAwarded;
  final bool alreadyApplied;

  const RewardClaimResult({
    required this.success,
    required this.pointsAwarded,
    required this.matchedRules,
    required this.badgesAwarded,
    this.newBalance,
    this.transactionId,
    this.alreadyApplied = false,
  });

  factory RewardClaimResult.fromJson(Map<String, dynamic> json) {
    List<String> readStringList(Object? value) {
      if (value is! List) {
        return const [];
      }

      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return RewardClaimResult(
      success: json['success'] == true,
      pointsAwarded: (json['points_awarded'] as num?)?.toInt() ?? 0,
      newBalance: (json['new_balance'] as num?)?.toInt(),
      transactionId: json['transaction_id'] as String?,
      matchedRules: readStringList(json['matched_rules']),
      badgesAwarded: readStringList(json['badges_awarded']),
      alreadyApplied: json['already_applied'] == true,
    );
  }
}
