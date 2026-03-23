class NotificationPreferences {
  final String userId;
  final bool notifyMatchStart;
  final bool notifyMatchEnd;
  final bool notifyGoals;
  final bool notifyPredictions;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationPreferences({
    required this.userId,
    this.notifyMatchStart = true,
    this.notifyMatchEnd = true,
    this.notifyGoals = true,
    this.notifyPredictions = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      notifyMatchStart: json['notify_match_start'] as bool? ?? true,
      notifyMatchEnd: json['notify_match_end'] as bool? ?? true,
      notifyGoals: json['notify_goals'] as bool? ?? true,
      notifyPredictions: json['notify_predictions'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'notify_match_start': notifyMatchStart,
      'notify_match_end': notifyMatchEnd,
      'notify_goals': notifyGoals,
      'notify_predictions': notifyPredictions,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    bool? notifyMatchStart,
    bool? notifyMatchEnd,
    bool? notifyGoals,
    bool? notifyPredictions,
  }) {
    return NotificationPreferences(
      userId: userId,
      notifyMatchStart: notifyMatchStart ?? this.notifyMatchStart,
      notifyMatchEnd: notifyMatchEnd ?? this.notifyMatchEnd,
      notifyGoals: notifyGoals ?? this.notifyGoals,
      notifyPredictions: notifyPredictions ?? this.notifyPredictions,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
