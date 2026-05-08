class UserProfile {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final int reputationScore;
  final int kCoinBalance;
  final String? activeFrame;
  final String activeThemeCode;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.reputationScore,
    required this.kCoinBalance,
    this.activeFrame,
    this.activeThemeCode = 'classic',
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      avatarUrl: _stringOrNull(json['avatar_url']),
      reputationScore: _asInt(json['reputation_score']),
      kCoinBalance: _asInt(json['k_coin_balance']),
      activeFrame: _stringOrNull(json['active_frame']),
      activeThemeCode: _stringOrNull(json['active_theme_code']) ?? 'classic',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar_url': avatarUrl,
      'reputation_score': reputationScore,
      'k_coin_balance': kCoinBalance,
      'active_frame': activeFrame,
      'active_theme_code': activeThemeCode,
    };
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
