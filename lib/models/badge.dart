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
      id: json['id'] as String,
      category: json['category'] as String,
      nameTr: json['name_tr'] as String,
      nameEn: json['name_en'] as String,
      descriptionTr: json['description_tr'] as String,
      descriptionEn: json['description_en'] as String,
      iconName: json['icon_name'] as String,
      maxTier: json['max_tier'] as int? ?? 3,
      triggerType: json['trigger_type'] as String,
      triggerTarget: json['trigger_target'] as int,
      tier2Target: json['tier2_target'] as int?,
      tier3Target: json['tier3_target'] as int?,
      kCoinReward: json['k_coin_reward'] as int? ?? 0,
      sortOrder: json['sort_order'] as int? ?? 0,
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
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      badgeId: json['badge_id'] as String,
      currentTier: json['current_tier'] as int? ?? 0,
      progress: json['progress'] as int? ?? 0,
      unlockedAt: json['unlocked_at'] != null
          ? DateTime.parse(json['unlocked_at'] as String)
          : null,
      lastTierUp: json['last_tier_up'] != null
          ? DateTime.parse(json['last_tier_up'] as String)
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
      userId: json['user_id'] as String,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      lastLoginDate: json['last_login_date'] != null
          ? DateTime.parse(json['last_login_date'] as String)
          : null,
      totalLogins: json['total_logins'] as int? ?? 0,
    );
  }
}
