import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/follow_repository.dart';

final followRepositoryProvider = Provider<FollowRepository>((ref) {
  return FollowRepository(Supabase.instance.client);
});

class FollowNotifier extends Notifier<AsyncValue<List<String>>> {
  @override
  AsyncValue<List<String>> build() {
    // Attempt to load the current user's follow list when the notifier initializes
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      _loadFollowing(currentUser.id);
    } else {
      return const AsyncValue.data([]);
    }
    return const AsyncValue.loading();
  }

  Future<void> _loadFollowing(String userId) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(followRepositoryProvider);
      final following = await repository.getFollowing(userId);
      state = AsyncValue.data(following);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null) {
      await _loadFollowing(currentUser.id);
    }
  }

  Future<void> toggleFollow(String targetUserId) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final currentList = state.value ?? [];
    final isCurrentlyFollowing = currentList.contains(targetUserId);

    // Optimistic UI Update
    if (isCurrentlyFollowing) {
      state = AsyncValue.data(List.from(currentList)..remove(targetUserId));
    } else {
      state = AsyncValue.data(List.from(currentList)..add(targetUserId));
    }

    try {
      final repository = ref.read(followRepositoryProvider);
      if (isCurrentlyFollowing) {
        await repository.unfollowUser(targetUserId);
      } else {
        await repository.followUser(targetUserId);
      }
      
      // Invalidate the counts for the target user so the UI refreshes
      ref.invalidate(followerCountProvider(targetUserId));
    } catch (e) {
      // Revert optimism on failure
      state = AsyncValue.data(currentList);
      rethrow; 
    }
  }
}

final followProvider = NotifierProvider<FollowNotifier, AsyncValue<List<String>>>(
  FollowNotifier.new,
);

/// A family provider to fetch the followers count for a specific user ID
final followerCountProvider = FutureProvider.family<int, String>((ref, userId) async {
  final repository = ref.read(followRepositoryProvider);
  return repository.getFollowerCount(userId);
});

/// A family provider to fetch the following count for a specific user ID
final followingCountProvider = FutureProvider.family<int, String>((ref, userId) async {
  final repository = ref.read(followRepositoryProvider);
  return repository.getFollowingCount(userId);
});
