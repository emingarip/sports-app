import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/match_room_screen.dart' show ChatMessage, MessageType;

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;

  // Stream messages for a specific match
  Stream<List<ChatMessage>> streamMatchMessages(String matchId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at', ascending: true)
        .map((data) {
          return data.map((json) {
            final isMe = json['user_id'] == _client.auth.currentUser?.id;
            
            // Format time from timestamp
            final createdAt = DateTime.parse(json['created_at']).toLocal();
            final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

            return ChatMessage(
              id: json['id'],
              type: isMe ? MessageType.me : MessageType.user,
              text: json['text'],
              username: json['username'],
              time: timeStr,
            );
          }).toList();
        });
  }

  // Send a new message
  Future<void> sendMessage(String matchId, String text) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // Fetch user profile to get username, default to 'Fan' if not found
    final profileData = await _client.from('users').select('username').eq('id', user.id).maybeSingle();
    final username = profileData?['username'] ?? 'Fan';

    await _client.from('chat_messages').insert({
      'match_id': matchId,
      'user_id': user.id,
      'username': username,
      'text': text,
    });
  }
}
