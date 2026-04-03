import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/inbox_screen.dart';
import '../theme/app_theme.dart';

class InboxMessageButton extends StatefulWidget {
  const InboxMessageButton({super.key});

  @override
  State<InboxMessageButton> createState() => _InboxMessageButtonState();
}

class _InboxMessageButtonState extends State<InboxMessageButton>
    with WidgetsBindingObserver {
  SupabaseClient? _supabase;
  RealtimeChannel? _messageChannel;
  Timer? _refreshDebounce;

  int _unreadCount = 0;
  bool _isLoading = true;

  bool get _hasUnread => _unreadCount > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supabase = _resolveClient();
    _loadUnreadCount();
    _subscribeToMessageChanges();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshDebounce?.cancel();
    _messageChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  Future<void> _loadUnreadCount() async {
    final client = _supabase;
    if (client == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _unreadCount = 0;
        _isLoading = false;
      });
      return;
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _unreadCount = 0;
        _isLoading = false;
      });
      return;
    }

    try {
      final participantRows = await client
          .from('chat_participants')
          .select('room_id')
          .eq('user_id', userId);

      final roomIds = (participantRows as List)
          .map((row) => row['room_id'] as String?)
          .whereType<String>()
          .toList();

      if (roomIds.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _unreadCount = 0;
          _isLoading = false;
        });
        return;
      }

      final unreadCount = await client
          .from('private_messages')
          .count(CountOption.exact)
          .inFilter('room_id', roomIds)
          .neq('sender_id', userId)
          .eq('is_read', false);

      if (!mounted) {
        return;
      }

      setState(() {
        _unreadCount = unreadCount;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Failed to load unread private message count: $error');
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessageChanges() {
    final client = _supabase;
    if (client == null) {
      return;
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    _messageChannel = client
        .channel('private_message_badge_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'private_messages',
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 160),
      _loadUnreadCount,
    );
  }

  SupabaseClient? _resolveClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMessaging() async {
    await showMessagingOverlay(context);
    if (!mounted) {
      return;
    }
    await _loadUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _hasUnread
        ? context.colors.primary
        : (_isLoading ? context.colors.textLow : context.colors.textMedium);
    final backgroundColor = _hasUnread
        ? context.colors.primaryContainer.withValues(alpha: 0.42)
        : Colors.transparent;
    final badgeText = _unreadCount > 9 ? '9+' : '$_unreadCount';

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip:
                _hasUnread ? 'Mesajlar ($_unreadCount okunmamis)' : 'Mesajlar',
            onPressed: _openMessaging,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: Icon(
                _hasUnread
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                key: ValueKey(_hasUnread),
                color: iconColor,
              ),
            ),
          ),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 7,
            top: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              decoration: BoxDecoration(
                color: context.colors.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: context.colors.surfaceContainerLowest,
                  width: 1.5,
                ),
              ),
              child: Text(
                badgeText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onError,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
