class UserProfile {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final int reputationScore;
  final int virtualCurrencyBalance;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.reputationScore,
    required this.virtualCurrencyBalance,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      reputationScore: json['reputation_score'] as int? ?? 0,
      virtualCurrencyBalance: json['virtual_currency_balance'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar_url': avatarUrl,
      'reputation_score': reputationScore,
      'virtual_currency_balance': virtualCurrencyBalance,
    };
  }
}
