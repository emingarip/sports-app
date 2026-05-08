import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final int kCoinBalance;
  final int reputationScore;
  final String? activeFrame;

  LeaderboardUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.kCoinBalance,
    required this.reputationScore,
    this.activeFrame,
  });

  factory LeaderboardUser.fromJson(Map<String, dynamic> json) {
    return LeaderboardUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Kullanici',
      avatarUrl: _stringOrNull(json['avatar_url']),
      kCoinBalance: _asInt(json['k_coin_balance']),
      reputationScore: _asInt(json['reputation_score']),
      activeFrame: _stringOrNull(json['active_frame']),
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
        .select(
            'id, username, avatar_url, k_coin_balance, reputation_score, active_frame')
        .order('k_coin_balance', ascending: false)
        .limit(50);

    final users = _asMapList(response).map(LeaderboardUser.fromJson).toList();

    return users;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchLeaderboard());
  }
}

final leaderboardProvider =
    AsyncNotifierProvider<LeaderboardNotifier, List<LeaderboardUser>>(
  () {
    return LeaderboardNotifier();
  },
  name: 'leaderboardProvider',
);

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! Iterable) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
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
