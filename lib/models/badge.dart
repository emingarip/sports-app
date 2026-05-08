/// Badge model representing a badge definition from the database.
class Badge {
  final String id;
  final String category;
  final String nameTr;
  final String nameEn;
  final String descriptionTr;
  final String descriptionEn;
  final String iconName;
  final int maxTier;
  final String triggerType;
  final int triggerTarget;
  final int? tier2Target;
  final int? tier3Target;
  final int kCoinReward;
  final int sortOrder;

  const Badge({
    required this.id,
    required this.category,
    required this.nameTr,
    required this.nameEn,
    required this.descriptionTr,
    required this.descriptionEn,
    required this.iconName,
    this.maxTier = 3,
    required this.triggerType,
    required this.triggerTarget,
    this.tier2Target,
    this.tier3Target,
    this.kCoinReward = 0,
    this.sortOrder = 0,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ??
          json['criteria']?.toString() ??
          'Diğer',
      nameTr: json['name_tr']?.toString() ?? json['name']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? json['name']?.toString() ?? '',
      descriptionTr: json['description_tr']?.toString() ??
          json['description']?.toString() ??
          '',
      descriptionEn: json['description_en']?.toString() ??
          json['description']?.toString() ??
          '',
      iconName: json['icon_name']?.toString() ??
          json['icon']?.toString() ??
          'emoji_events',
      maxTier: _asInt(json['max_tier'], 1),
      triggerType: json['metric']?.toString() ??
          json['trigger_type']?.toString() ??
          'backend_triggered',
      triggerTarget: _asInt(json['target'] ?? json['trigger_target'], 1),
      tier2Target: _asNullableInt(json['tier2_target']),
      tier3Target: _asNullableInt(json['tier3_target']),
      kCoinReward: _asInt(json['k_coin_reward'] ?? json['points']),
      sortOrder: _asInt(json['sort_order']),
    );
  }

  /// Returns the target for a specific tier level.
  int targetForTier(int tier) {
    switch (tier) {
      case 1:
        return triggerTarget;
      case 2:
        return tier2Target ?? triggerTarget * 5;
      case 3:
        return tier3Target ?? triggerTarget * 20;
      default:
        return triggerTarget;
    }
  }

  /// Category display label.
  String get categoryLabel {
    switch (category) {
      case 'onboarding':
        return '🌟 Başlangıç';
      case 'engagement':
        return '⚽ Maç Takip';
      case 'prediction':
        return '🎯 Tahmin';
      case 'economy':
        return '💰 Ekonomi';
      case 'social':
        return '🏅 Topluluk';
      case 'streak':
        return '📅 Süreklilik';
      default:
        return category;
    }
  }
}

/// User's progress on a specific badge.
class UserBadge {
  final String? id;
  final String userId;
  final String badgeId;
  final int currentTier;
  final int progress;
  final DateTime? unlockedAt;
  final DateTime? lastTierUp;

  const UserBadge({
    this.id,
    required this.userId,
    required this.badgeId,
    this.currentTier = 0,
    this.progress = 0,
    this.unlockedAt,
    this.lastTierUp,
  });

  bool get isUnlocked => currentTier > 0;

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    return UserBadge(
      id: json['id']?.toString(),
      userId: json['user_id']?.toString() ?? 'me',
      badgeId: json['badge_id']?.toString() ?? json['id']?.toString() ?? '',
      currentTier: _asInt(json['current_tier'], 1),
      progress: _asInt(json['progress'] ?? json['points'], 1),
      unlockedAt: (json['unlocked_at'] != null)
          ? DateTime.tryParse(json['unlocked_at'].toString())
          : (json['earned_at'] != null
              ? DateTime.tryParse(json['earned_at'].toString())
              : null),
      lastTierUp: json['last_tier_up'] != null
          ? DateTime.tryParse(json['last_tier_up'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'badge_id': badgeId,
      'current_tier': currentTier,
      'progress': progress,
      if (unlockedAt != null) 'unlocked_at': unlockedAt!.toIso8601String(),
      if (lastTierUp != null) 'last_tier_up': lastTierUp!.toIso8601String(),
    };
  }
}

/// User's daily login streak data.
class UserStreak {
  final String userId;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastLoginDate;
  final int totalLogins;

  const UserStreak({
    required this.userId,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastLoginDate,
    this.totalLogins = 0,
  });

  factory UserStreak.fromJson(Map<String, dynamic> json) {
    return UserStreak(
      userId: json['user_id']?.toString() ?? '',
      currentStreak: _asInt(json['current_streak']),
      longestStreak: _asInt(json['longest_streak']),
      lastLoginDate: json['last_login_date'] != null
          ? DateTime.tryParse(json['last_login_date'].toString())
          : null,
      totalLogins: _asInt(json['total_logins']),
    );
  }
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
