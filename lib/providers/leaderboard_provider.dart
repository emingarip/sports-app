import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final int kCoinBalance;
  final int reputationScore;

  LeaderboardUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.kCoinBalance,
    required this.reputationScore,
  });

  factory LeaderboardUser.fromJson(Map<String, dynamic> json) {
    return LeaderboardUser(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      kCoinBalance: json['k_coin_balance'] as int? ?? 0,
      reputationScore: json['reputation_score'] as int? ?? 0,
    );
  }
}

class LeaderboardNotifier extends AsyncNotifier<List<LeaderboardUser>> {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  FutureOr<List<LeaderboardUser>> build() async {
    return _fetchLeaderboard();
  }

  Future<List<LeaderboardUser>> _fetchLeaderboard() async {
    final response = await _client
        .from('users')
        .select('id, username, avatar_url, k_coin_balance, reputation_score')
        .order('k_coin_balance', ascending: false)
        .limit(50);

    final users = (response as List<dynamic>)
        .map((data) => LeaderboardUser.fromJson(data as Map<String, dynamic>))
        .toList();

    return users;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchLeaderboard());
  }
}

final leaderboardProvider = AsyncNotifierProvider<LeaderboardNotifier, List<LeaderboardUser>>(() {
  return LeaderboardNotifier();
});
