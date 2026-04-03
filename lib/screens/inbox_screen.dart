import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/frame_avatar.dart';
import 'private_chat_screen.dart';

enum InboxPresentation { fullScreen, overlay }

Future<T?> showMessagingOverlay<T>(BuildContext context) {
  final scrimColor =
      Theme.of(context).colorScheme.scrim.withValues(alpha: 0.52);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close messages',
    barrierColor: scrimColor,
    useRootNavigator: true,
    routeSettings: const RouteSettings(name: 'messaging_overlay'),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) {
      return const InboxScreen(presentation: InboxPresentation.overlay);
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
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class InboxRoomSummary {
  final String roomId;
  final String otherUserId;
  final String username;
  final String? avatarUrl;
  final String? activeFrame;
  final bool isBot;
  final String latestMessage;
  final String? lastTime;
  final bool unread;

  const InboxRoomSummary({
    required this.roomId,
    required this.otherUserId,
    required this.username,
    this.avatarUrl,
    this.activeFrame,
    required this.isBot,
    required this.latestMessage,
    this.lastTime,
    required this.unread,
  });
}

class InboxScreen extends StatefulWidget {
  final InboxPresentation presentation;

  const InboxScreen({
    super.key,
    this.presentation = InboxPresentation.fullScreen,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _supabase = Supabase.instance.client;

  List<InboxRoomSummary> _rooms = [];
  bool _isLoading = true;
  InboxRoomSummary? _selectedRoom;

  bool get _isOverlay => widget.presentation == InboxPresentation.overlay;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {
            _rooms = [];
            _isLoading = false;
          });
        }
        return;
      }

      final myParticipants = await _supabase
          .from('chat_participants')
          .select('room_id')
          .eq('user_id', userId);

      if (myParticipants.isEmpty) {
        if (mounted) {
          setState(() {
            _rooms = [];
            _selectedRoom = null;
            _isLoading = false;
          });
        }
        return;
      }

      final roomIds =
          myParticipants.map((participant) => participant['room_id']).toList();

      final otherParticipants = await _supabase
          .from('chat_participants')
          .select(
              'room_id, user_id, users(username, avatar_url, is_bot, active_frame)')
          .inFilter('room_id', roomIds)
          .neq('user_id', userId);

      final roomsData = <InboxRoomSummary>[];
      for (final participant in otherParticipants) {
        final roomId = participant['room_id'] as String;
        final userData = participant['users'] as Map<String, dynamic>? ?? {};

        final latestMessageResponse = await _supabase
            .from('private_messages')
            .select('content, created_at, is_read, sender_id')
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        roomsData.add(
          InboxRoomSummary(
            roomId: roomId,
            otherUserId: participant['user_id'] as String,
            username:
                (userData['username'] as String?) ?? 'Bilinmeyen Kullanici',
            avatarUrl: userData['avatar_url'] as String?,
            activeFrame: userData['active_frame'] as String?,
            isBot: userData['is_bot'] == true,
            latestMessage: (latestMessageResponse?['content'] as String?) ??
                'Sohbeti baslatin',
            lastTime: latestMessageResponse?['created_at'] as String?,
            unread: latestMessageResponse != null &&
                latestMessageResponse['sender_id'] != userId &&
                latestMessageResponse['is_read'] == false,
          ),
        );
      }

      roomsData.sort((a, b) {
        final timeA = a.lastTime != null
            ? DateTime.parse(a.lastTime!)
            : DateTime.fromMillisecondsSinceEpoch(0);
        final timeB = b.lastTime != null
            ? DateTime.parse(b.lastTime!)
            : DateTime.fromMillisecondsSinceEpoch(0);
        return timeB.compareTo(timeA);
      });

      if (!mounted) {
        return;
      }

      final currentSelectedId = _selectedRoom?.roomId;
      setState(() {
        _rooms = roomsData;
        _selectedRoom = currentSelectedId == null
            ? null
            : roomsData.cast<InboxRoomSummary?>().firstWhere(
                  (room) => room?.roomId == currentSelectedId,
                  orElse: () => null,
                );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => _isLoading = false);
      debugPrint('Error loading inbox: $error');
    }
  }

  void _closeOverlay() {
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  Future<void> _openRoom(InboxRoomSummary room) async {
    if (_isOverlay) {
      setState(() {
        _selectedRoom = room;
      });
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          roomId: room.roomId,
          otherUserId: room.otherUserId,
          otherUsername: room.username,
          otherAvatarUrl: room.avatarUrl,
          otherActiveFrame: room.activeFrame,
          isBot: room.isBot,
        ),
      ),
    );
    await _loadRooms();
  }

  Future<void> _handleBackFromConversation() async {
    setState(() {
      _selectedRoom = null;
    });
    await _loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOverlay) {
      return _buildOverlayLayout(context);
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.textHigh),
        title: Text(
          'Mesajlar',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textHigh,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
      body: _buildListContent(context),
    );
  }

  Widget _buildOverlayLayout(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isCompact = screenSize.width < 860;
    final horizontalPadding = isCompact ? 12.0 : 20.0;
    final maxWidth = isCompact
        ? screenSize.width - (horizontalPadding * 2)
        : math.min(980.0, screenSize.width - (horizontalPadding * 2));
    final maxHeight = isCompact
        ? screenSize.height - 28
        : math.min(820.0, screenSize.height - 40);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closeOverlay,
      child: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            isCompact ? 20 : 20,
            horizontalPadding,
            mediaQuery.viewInsets.bottom + (isCompact ? 12 : 20),
          ),
          child: Align(
            alignment: isCompact ? Alignment.bottomCenter : Alignment.center,
            child: GestureDetector(
              onTap: () {},
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (isCompact && _selectedRoom == null && velocity > 900) {
                  _closeOverlay();
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
                    borderRadius: BorderRadius.circular(isCompact ? 30 : 32),
                    border: Border.all(
                      color: context.colors.outline.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .shadowColor
                            .withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isCompact ? 30 : 32),
                    child: Material(
                      color: context.colors.surfaceContainerLowest,
                      child: isCompact
                          ? _buildCompactOverlayContent(context)
                          : _buildWideOverlayContent(context),
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

  Widget _buildCompactOverlayContent(BuildContext context) {
    final selectedRoom = _selectedRoom;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.outline.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: selectedRoom == null
                ? KeyedSubtree(
                    key: const ValueKey('inbox-list'),
                    child: Column(
                      children: [
                        _buildOverlayTopBar(context),
                        Divider(
                          height: 1,
                          color: context.colors.outline.withValues(alpha: 0.14),
                        ),
                        Expanded(child: _buildListContent(context)),
                      ],
                    ),
                  )
                : KeyedSubtree(
                    key: ValueKey('conversation-${selectedRoom.roomId}'),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          child: PrivateChatHeader(
                            otherUsername: selectedRoom.username,
                            subtitle: selectedRoom.isBot
                                ? 'Bot ile ozel mesaj'
                                : 'Ozel mesaj',
                            otherAvatarUrl: selectedRoom.avatarUrl,
                            otherActiveFrame: selectedRoom.activeFrame,
                            isBot: selectedRoom.isBot,
                            onBack: _handleBackFromConversation,
                            onClose: _closeOverlay,
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: context.colors.outline.withValues(alpha: 0.14),
                        ),
                        Expanded(
                          child: PrivateChatThread(
                            roomId: selectedRoom.roomId,
                            otherUserId: selectedRoom.otherUserId,
                            embedInOverlay: true,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideOverlayContent(BuildContext context) {
    return Column(
      children: [
        _buildOverlayTopBar(context),
        Divider(
          height: 1,
          color: context.colors.outline.withValues(alpha: 0.14),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 340,
                child: _buildListContent(context),
              ),
              VerticalDivider(
                width: 1,
                color: context.colors.outline.withValues(alpha: 0.14),
              ),
              Expanded(
                child: _selectedRoom == null
                    ? _buildConversationPlaceholder(context)
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            child: PrivateChatHeader(
                              otherUsername: _selectedRoom!.username,
                              subtitle: _selectedRoom!.isBot
                                  ? 'Bot ile ozel mesaj'
                                  : 'Ozel mesaj',
                              otherAvatarUrl: _selectedRoom!.avatarUrl,
                              otherActiveFrame: _selectedRoom!.activeFrame,
                              isBot: _selectedRoom!.isBot,
                            ),
                          ),
                          Divider(
                            height: 1,
                            color:
                                context.colors.outline.withValues(alpha: 0.14),
                          ),
                          Expanded(
                            child: PrivateChatThread(
                              roomId: _selectedRoom!.roomId,
                              otherUserId: _selectedRoom!.otherUserId,
                              embedInOverlay: true,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mesajlar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          IconButton(
            onPressed: _closeOverlay,
            tooltip: 'Kapat',
            icon: Icon(
              Icons.close_rounded,
              color: context.colors.textHigh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListContent(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: context.colors.primaryContainer,
        ),
      );
    }

    if (_rooms.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _loadRooms,
      color: context.colors.primaryContainer,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _rooms.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: context.colors.outline.withValues(alpha: 0.08),
        ),
        itemBuilder: (context, index) {
          final room = _rooms[index];
          return _buildRoomTile(context, room);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: context.colors.textMedium,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Henuz hic mesajin yok.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Canli chatlerden veya destek ekranindan yeni bir sohbet baslatabilirsin.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textMedium,
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTile(BuildContext context, InboxRoomSummary room) {
    final isSelected = _isOverlay && _selectedRoom?.roomId == room.roomId;

    return InkWell(
      onTap: () => _openRoom(room),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: isSelected
            ? context.colors.primaryContainer.withValues(alpha: 0.14)
            : Colors.transparent,
        child: Row(
          children: [
            Stack(
              children: [
                FrameAvatar(
                  avatarUrl: room.avatarUrl,
                  activeFrame: room.activeFrame,
                  radius: 26,
                ),
                if (room.isBot)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.smart_toy,
                        size: 10,
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: context.colors.textHigh,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (room.lastTime != null)
                        Text(
                          _formatTime(room.lastTime!),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: room.unread
                                        ? context.colors.primary
                                        : context.colors.textLow,
                                    fontWeight: room.unread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.latestMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: room.unread
                                        ? context.colors.textHigh
                                        : context.colors.textMedium,
                                    fontWeight: room.unread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                      if (room.unread) ...[
                        const SizedBox(width: 12),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: context.colors.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationPlaceholder(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_chat_read_rounded,
                size: 40,
                color: context.colors.textMedium,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Bir sohbet sec',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Soldaki listeden bir konusma secerek mesajasma akisini bu panelde acabilirsin.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textMedium,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final date = DateTime.parse(isoTime).toLocal();
      final now = DateTime.now();
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }

      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }
}
