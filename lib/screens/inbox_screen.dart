import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'private_chat_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Get rooms I am in
      final myParticipants = await _supabase
          .from('chat_participants')
          .select('room_id')
          .eq('user_id', userId);

      if (myParticipants.isEmpty) {
        setState(() {
          _rooms = [];
          _isLoading = false;
        });
        return;
      }

      final roomIds = myParticipants.map((p) => p['room_id']).toList();

      // 2. Get the *other* participants in these rooms along with their user details
      final otherParticipants = await _supabase
          .from('chat_participants')
          .select('room_id, user_id, users(username, avatar_url, is_bot)')
          .inFilter('room_id', roomIds)
          .neq('user_id', userId);

      // 3. Get the latest message for each room
      List<Map<String, dynamic>> roomsData = [];
      for (var op in otherParticipants) {
        final roomId = op['room_id'];
        final userData = op['users'] ?? {};
        
        final latestMessageRes = await _supabase
            .from('private_messages')
            .select('content, created_at, is_read, sender_id')
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        roomsData.add({
          'room_id': roomId,
          'other_user_id': op['user_id'],
          'username': userData['username'] ?? 'Bilinmeyen Kullanıcı',
          'avatar_url': userData['avatar_url'],
          'is_bot': userData['is_bot'] ?? false,
          'latest_message': latestMessageRes?['content'] ?? 'Sohbeti başlatın',
          'last_time': latestMessageRes?['created_at'],
          'unread': latestMessageRes != null && 
                    latestMessageRes['sender_id'] != userId && 
                    latestMessageRes['is_read'] == false,
        });
      }

      // Sort by last message time
      roomsData.sort((a, b) {
        final tA = a['last_time'] != null ? DateTime.parse(a['last_time']) : DateTime.fromMillisecondsSinceEpoch(0);
        final tB = b['last_time'] != null ? DateTime.parse(b['last_time']) : DateTime.fromMillisecondsSinceEpoch(0);
        return tB.compareTo(tA);
      });

      if (mounted) {
        setState(() {
          _rooms = roomsData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading inbox: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text('Mesajlar', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textHigh)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _rooms.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadRooms,
                  color: context.colors.primary,
                  child: ListView.builder(
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      return _buildRoomTile(room);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: context.colors.textMedium.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Henüz hiç mesajınız yok.',
            style: TextStyle(color: context.colors.textMedium, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTile(Map<String, dynamic> room) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PrivateChatScreen(
              roomId: room['room_id'],
              otherUserId: room['other_user_id'],
              otherUsername: room['username'],
              otherAvatarUrl: room['avatar_url'],
              isBot: room['is_bot'],
            ),
          ),
        );
        _loadRooms(); // Refresh on back
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.colors.surfaceContainerHigh)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.colors.surfaceContainer,
                  backgroundImage: room['avatar_url'] != null 
                    ? NetworkImage(room['avatar_url']) 
                    : null,
                  child: room['avatar_url'] == null 
                    ? Text(room['username'].substring(0, 1).toUpperCase(), style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold))
                    : null,
                ),
                if (room['is_bot'] == true)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.smart_toy, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        room['username'],
                        style: TextStyle(color: context.colors.textHigh, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (room['last_time'] != null)
                        Text(
                          _formatTime(room['last_time']),
                          style: TextStyle(
                            color: room['unread'] ? context.colors.primary : context.colors.textLow, 
                            fontSize: 12,
                            fontWeight: room['unread'] ? FontWeight.bold : FontWeight.normal
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    room['latest_message'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: room['unread'] ? context.colors.textHigh : context.colors.textMedium,
                      fontWeight: room['unread'] ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14
                    ),
                  ),
                ],
              ),
            ),
            if (room['unread'])
              Container(
                margin: const EdgeInsets.only(left: 12),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
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
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return '${date.day}/${date.month}';
    } catch (e) {
      return '';
    }
  }
}
