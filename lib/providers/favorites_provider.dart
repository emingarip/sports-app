import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'knowledge_graph_provider.dart';
import 'package:flutter/foundation.dart';

class FavoritesNotifier extends Notifier<Set<String>> {
  SupabaseClient get _client => Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  Set<String> build() {
    _initStream();
    
    _authSubscription?.cancel();
    _authSubscription = _client.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        _initStream();
      } else {
        state = {};
        _subscription?.cancel();
      }
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _authSubscription?.cancel();
    });

    return {};
  }

  void _initStream() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    _subscription?.cancel();
    _subscription = _client
        .from('user_favorite_matches')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen((events) {
      final favoriteMatchIds = events.map((e) => e['match_id'].toString()).toSet();
      state = favoriteMatchIds;
    });
  }

  Future<void> toggleFavorite(String matchId) async {
    final user = _client.auth.currentUser;
    if (user == null) return; 
    
    final isFavorite = state.contains(matchId);

    // Optimistically update
    if (isFavorite) {
      state = {...state}..remove(matchId);
    } else {
      state = {...state, matchId};
    }

    try {
      if (isFavorite) {
        await _client
            .from('user_favorite_matches')
            .delete()
            .match({'user_id': user.id, 'match_id': matchId});
      } else {
        await _client
            .from('user_favorite_matches')
            .insert({'user_id': user.id, 'match_id': matchId});
            
        // Track the favorited match in Knowledge Graph
        ref.read(knowledgeGraphProvider.notifier).trackEvent(
          eventType: 'match_favorited',
          entityType: 'match',
          entityId: matchId,
        );
      }
    } catch (e) {
      if (kDebugMode) print('Failed to toggle favorite: $e');
      // Revert if failed
      if (isFavorite) {
        state = {...state, matchId};
      } else {
        state = {...state}..remove(matchId);
      }
    }
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(() {
  return FavoritesNotifier();
});
