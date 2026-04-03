import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/frame_avatar.dart';

enum PrivateChatPresentation { fullScreen, overlay }

Future<T?> showPrivateChatOverlay<T>(
  BuildContext context, {
  required String roomId,
  required String otherUserId,
  required String otherUsername,
  String? otherAvatarUrl,
  String? otherActiveFrame,
  bool isBot = false,
}) {
  final scrimColor =
      Theme.of(context).colorScheme.scrim.withValues(alpha: 0.58);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close private chat',
    barrierColor: scrimColor,
    useRootNavigator: true,
    routeSettings: const RouteSettings(name: 'private_chat'),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return PrivateChatScreen(
        roomId: roomId,
        otherUserId: otherUserId,
        otherUsername: otherUsername,
        otherAvatarUrl: otherAvatarUrl,
        otherActiveFrame: otherActiveFrame,
        isBot: isBot,
        presentation: PrivateChatPresentation.overlay,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class PrivateChatHeader extends StatelessWidget {
  final String otherUsername;
  final String subtitle;
  final String? otherAvatarUrl;
  final String? otherActiveFrame;
  final bool isBot;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const PrivateChatHeader({
    super.key,
    required this.otherUsername,
    required this.subtitle,
    this.otherAvatarUrl,
    this.otherActiveFrame,
    this.isBot = false,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            tooltip: 'Geri',
            icon: Icon(
              Icons.arrow_back_rounded,
              color: context.colors.textHigh,
            ),
          ),
        Stack(
          children: [
            FrameAvatar(
              avatarUrl: otherAvatarUrl,
              activeFrame: otherActiveFrame,
              radius: 18,
            ),
            if (isBot)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.colors.surfaceContainerLowest,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    size: 8,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                otherUsername,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: context.colors.textHigh,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: context.colors.textMedium,
                ),
              ),
            ],
          ),
        ),
        if (onClose != null)
          IconButton(
            onPressed: onClose,
            tooltip: 'Kapat',
            icon: Icon(
              Icons.close_rounded,
              color: context.colors.textHigh,
            ),
          ),
      ],
    );
  }
}

class PrivateChatThread extends ConsumerStatefulWidget {
  final String roomId;
  final String otherUserId;
  final bool embedInOverlay;

  const PrivateChatThread({
    super.key,
    required this.roomId,
    required this.otherUserId,
    this.embedInOverlay = false,
  });

  @override
  ConsumerState<PrivateChatThread> createState() => _PrivateChatThreadState();
}

class _PrivateChatThreadState extends ConsumerState<PrivateChatThread> {
  final _supabase = Supabase.instance.client;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    _markMessagesAsRead();
  }

  @override
  void didUpdateWidget(covariant PrivateChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.roomId != widget.roomId) {
      _subscription?.unsubscribe();
      _messages = [];
      _isLoading = true;
      _loadMessages();
      _subscribeToMessages();
      _markMessagesAsRead();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _subscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final response = await _supabase
          .from('private_messages')
          .select()
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _messages = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    _subscription = _supabase
        .channel('public:private_messages:room_${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            final newMessage = payload.newRecord;
            if (!mounted) {
              return;
            }

            setState(() {
              _messages.add(newMessage);
            });
            _scrollToBottom();

            if (newMessage['sender_id'] == widget.otherUserId) {
              _markAsRead(newMessage['id'] as String);
            }
          },
        )
        .subscribe();
  }

  Future<void> _markMessagesAsRead() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) {
      return;
    }

    try {
      await _supabase
          .from('private_messages')
          .update({'is_read': true})
          .eq('room_id', widget.roomId)
          .neq('sender_id', myId)
          .eq('is_read', false);
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _markAsRead(String messageId) async {
    try {
      await _supabase
          .from('private_messages')
          .update({'is_read': true}).eq('id', messageId);
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) {
      return;
    }

    setState(() => _isSending = true);
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'room_id': widget.roomId,
      'sender_id': myId,
      'content': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
    };

    setState(() {
      _messages.add(tempMessage);
      _messageController.clear();
    });
    _scrollToBottom();

    try {
      await _supabase.from('private_messages').insert({
        'room_id': widget.roomId,
        'sender_id': myId,
        'content': text,
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.removeWhere((message) => message['id'] == tempMessage['id']);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gonderilemedi: $error')),
      );
      setState(() {
        _messages.removeWhere((message) => message['id'] == tempMessage['id']);
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: context.colors.primaryContainer,
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isMe =
                        message['sender_id'] == _supabase.auth.currentUser?.id;
                    return _buildMessageBubble(context, message, isMe);
                  },
                ),
        ),
        _buildInputArea(context),
      ],
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Map<String, dynamic> message,
    bool isMe,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final bubbleColor = isMe
        ? context.colors.primaryContainer
        : context.colors.surfaceContainerLow;
    final messageColor =
        isMe ? context.colors.onPrimaryContainer : context.colors.textHigh;
    final metaColor = isMe
        ? context.colors.onPrimaryContainer.withValues(alpha: 0.72)
        : context.colors.textLow;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width *
              (widget.embedInOverlay ? 0.72 : 0.75),
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message['content'] ?? '',
              style: textTheme.bodyMedium?.copyWith(
                color: messageColor,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message['created_at'] as String?),
                  style: textTheme.labelSmall?.copyWith(
                    color: metaColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message['is_read'] == true ? Icons.done_all : Icons.check,
                    size: 12,
                    color: message['is_read'] == true
                        ? context.colors.success
                        : metaColor,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) {
      return '';
    }

    try {
      final date = DateTime.parse(isoTime).toLocal();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Widget _buildInputArea(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: widget.embedInOverlay
            ? context.colors.surfaceContainerLowest
            : context.colors.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: context.colors.outline.withValues(alpha: 0.14),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: !widget.embedInOverlay,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.colors.textHigh,
                ),
                onSubmitted: (_) => _sendMessage(),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: context.colors.textMedium,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: context.colors.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _isSending
                  ? context.colors.surfaceContainerHigh
                  : context.colors.primaryContainer,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _isSending ? null : _sendMessage,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    _isSending ? Icons.more_horiz : Icons.send_rounded,
                    color: _isSending
                        ? context.colors.textMedium
                        : context.colors.onPrimaryContainer,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivateChatScreen extends StatelessWidget {
  final String roomId;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final String? otherActiveFrame;
  final bool isBot;
  final PrivateChatPresentation presentation;

  const PrivateChatScreen({
    super.key,
    required this.roomId,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatarUrl,
    this.otherActiveFrame,
    this.isBot = false,
    this.presentation = PrivateChatPresentation.fullScreen,
  });

  void _close(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: presentation == PrivateChatPresentation.overlay,
    ).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = isBot ? 'Bot ile ozel mesaj' : 'Ozel mesaj';

    if (presentation == PrivateChatPresentation.fullScreen) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: context.colors.textHigh),
          titleSpacing: 0,
          title: PrivateChatHeader(
            otherUsername: otherUsername,
            subtitle: subtitle,
            otherAvatarUrl: otherAvatarUrl,
            otherActiveFrame: otherActiveFrame,
            isBot: isBot,
          ),
        ),
        body: PrivateChatThread(
          roomId: roomId,
          otherUserId: otherUserId,
        ),
      );
    }

    return _PrivateChatOverlayFrame(
      onClose: () => _close(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: PrivateChatHeader(
              otherUsername: otherUsername,
              subtitle: subtitle,
              otherAvatarUrl: otherAvatarUrl,
              otherActiveFrame: otherActiveFrame,
              isBot: isBot,
              onClose: () => _close(context),
            ),
          ),
          Divider(
            height: 1,
            color: context.colors.outline.withValues(alpha: 0.14),
          ),
          Expanded(
            child: PrivateChatThread(
              roomId: roomId,
              otherUserId: otherUserId,
              embedInOverlay: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivateChatOverlayFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback onClose;

  const _PrivateChatOverlayFrame({
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isCompact = screenSize.width < 700;
    final horizontalPadding = isCompact ? 10.0 : 24.0;
    final borderRadius = BorderRadius.circular(isCompact ? 28 : 30);
    final maxWidth = isCompact
        ? screenSize.width - (horizontalPadding * 2)
        : math.min(520.0, screenSize.width - (horizontalPadding * 2));
    final maxHeight = isCompact
        ? math.min(screenSize.height * 0.88, screenSize.height - 24)
        : math.min(760.0, screenSize.height - 48);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            mediaQuery.viewInsets.bottom + (isCompact ? 8 : 24),
          ),
          child: Align(
            alignment: isCompact ? Alignment.bottomCenter : Alignment.center,
            child: GestureDetector(
              onTap: () {},
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (isCompact && velocity > 900) {
                  onClose();
                }
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: context.colors.outline.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .shadowColor
                            .withValues(alpha: 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: borderRadius,
                    child: Material(
                      color: context.colors.surfaceContainerLowest,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: context.colors.outline
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
