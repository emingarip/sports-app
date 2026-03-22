import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification.dart';

class NotificationNotifier extends Notifier<List<AppNotification>> {
  SupabaseClient get _client => Supabase.instance.client;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  RealtimeChannel? _realtimeSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  List<AppNotification> build() {
    _initStreams();
    
    _authSubscription?.cancel();
    _authSubscription = _client.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        _initStreams();
      } else {
        state = [];
        _subscription?.cancel();
        _realtimeSubscription?.unsubscribe();
      }
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _realtimeSubscription?.unsubscribe();
      _authSubscription?.cancel();
    });

    return [];
  }

  void _initStreams() {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // 1. Initial Fetch via Stream (for catching up on history/read status)
    _subscription?.cancel();
    _subscription = _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(50)
        .listen((events) {
      final notifications = events.map((e) => AppNotification.fromJson(e)).toList();
      state = notifications;
    });

    // 2. We don't necessarily need a separate RealtimeChannel if .stream() 
    // already gives us updates. Supabase .stream() listens to all changes 
    // (INSERT, UPDATE, DELETE) natively via WebSockets!
    // So the above _subscription is actually enough to keep `state` perfectly in sync.
  }

  Future<void> markAsRead(String id) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }
}

final notificationProvider = NotifierProvider<NotificationNotifier, List<AppNotification>>(() {
  return NotificationNotifier();
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationProvider);
  return notifications.where((n) => !n.isRead).length;
});
