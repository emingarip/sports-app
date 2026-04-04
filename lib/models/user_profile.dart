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
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      reputationScore: json['reputation_score'] as int? ?? 0,
      kCoinBalance: json['k_coin_balance'] as int? ?? 0,
      activeFrame: json['active_frame'] as String?,
      activeThemeCode: json['active_theme_code'] as String? ?? 'classic',
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
