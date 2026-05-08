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
      pointsAwarded: _asInt(json['points_awarded']),
      newBalance: _asNullableInt(json['new_balance']),
      transactionId: _stringOrNull(json['transaction_id']),
      matchedRules: readStringList(json['matched_rules']),
      badgesAwarded: readStringList(json['badges_awarded']),
      alreadyApplied: json['already_applied'] == true,
    );
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
