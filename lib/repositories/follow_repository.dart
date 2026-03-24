import 'package:supabase_flutter/supabase_flutter.dart';

class FollowRepository {
  final SupabaseClient _client;

  FollowRepository(this._client);

  /// Fetch all User IDs that the target user is following
  Future<List<String>> getFollowing(String userId) async {
    final response = await _client
        .from('user_follows')
        .select('followed_id')
        .eq('follower_id', userId);
    
    return (response as List).map((row) => row['followed_id'] as String).toList();
  }

  /// Get total count of followers for a user
  Future<int> getFollowerCount(String userId) async {
    final count = await _client
        .from('user_follows')
        .count(CountOption.exact)
        .eq('followed_id', userId);
    return count;
  }
  
  /// Get total count of users the target user is following
  Future<int> getFollowingCount(String userId) async {
    final count = await _client
        .from('user_follows')
        .count(CountOption.exact)
        .eq('follower_id', userId);
    return count;
  }

  /// Follow a specific user
  Future<void> followUser(String targetUserId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) throw Exception('User not logged in');

    await _client.from('user_follows').insert({
      'follower_id': currentUserId,
      'followed_id': targetUserId,
    });
  }

  /// Unfollow a specific user
  Future<void> unfollowUser(String targetUserId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) throw Exception('User not logged in');
    
    await _client.from('user_follows').delete()
        .eq('follower_id', currentUserId)
        .eq('followed_id', targetUserId);
  }
}
