import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/match_detail_screen.dart' show ChatMessage, MessageType;

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;

  // Stream messages for a specific match
  Stream<List<ChatMessage>> streamMatchMessages(String matchId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at', ascending: true)
        .asyncMap((data) async {
          // Because stream() doesn't support joins natively in Supabase flutter,
          // we should ideally fetch users here or just use a view. 
          // For simplicity, let's fetch the relevant user details for the new messages.
          if (data.isEmpty) return [];
          
          final userIds = data.map((d) => d['user_id']).where((id) => id != null).toSet().toList();
          Map<String, dynamic> userMap = {};
          
          if (userIds.isNotEmpty) {
            final usersRes = await _client.from('users').select('id, username, avatar_url, is_bot').inFilter('id', userIds);
            for (var u in usersRes) {
              userMap[u['id']] = u;
            }
          }

          return data.map((json) {
            final isMe = json['user_id'] == _client.auth.currentUser?.id;
            
            // Format time from timestamp
            final createdAt = DateTime.parse(json['created_at']).toLocal();
            final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

            final uId = json['user_id'];
            final uData = userMap[uId] ?? {};
            
            return ChatMessage(
              id: json['id'] ?? '',
              type: isMe ? MessageType.me : (json['type'] == 'system_event' ? MessageType.systemEvent : MessageType.user),
              text: json['message'],
              username: uData['username'] ?? (isMe ? 'You' : 'Fan'),
              time: timeStr,
              userId: uId,
              avatarUrl: uData['avatar_url'],
              isBot: uData['is_bot'] == true,
            );
          }).toList();
        });
  }

  Future<void> sendMessage(String matchId, String text) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _client.from('chat_messages').insert({
      'match_id': matchId,
      'user_id': user.id,
      'message': text,
    });
  }

  // Get or create a private room with another user
  Future<String> getOrCreatePrivateRoom(String otherUserId) async {
    final myId = _client.auth.currentUser?.id;
    if (myId == null) throw Exception('User not logged in');
    if (myId == otherUserId) throw Exception('Cannot chat with yourself');

    // 1. Find rooms I am in
    final myRoomsRes = await _client.from('chat_participants').select('room_id').eq('user_id', myId);
    final myRoomIds = (myRoomsRes as List).map((r) => r['room_id'] as String).toList();

    if (myRoomIds.isNotEmpty) {
      // 2. See if the other user is in any of these rooms
      final sharedRoomRes = await _client
          .from('chat_participants')
          .select('room_id')
          .inFilter('room_id', myRoomIds)
          .eq('user_id', otherUserId)
          .limit(1)
          .maybeSingle();

      if (sharedRoomRes != null) {
        return sharedRoomRes['room_id'] as String;
      }
    }

    // 3. If no shared room, create a new one
    final newRoomRes = await _client.from('chat_rooms').insert({}).select('id').single();
    final newRoomId = newRoomRes['id'] as String;

    // 4. Add both participants
    await _client.from('chat_participants').insert([
      {'room_id': newRoomId, 'user_id': myId},
      {'room_id': newRoomId, 'user_id': otherUserId},
    ]);

    return newRoomId;
  }
}
