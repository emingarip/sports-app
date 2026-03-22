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
        .map((data) {
          return data.map((json) {
            final isMe = json['user_id'] == _client.auth.currentUser?.id;
            
            // Format time from timestamp
            final createdAt = DateTime.parse(json['created_at']).toLocal();
            final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

            return ChatMessage(
              id: json['id'] ?? '',
              type: isMe ? MessageType.me : (json['type'] == 'system_event' ? MessageType.systemEvent : MessageType.user),
              text: json['message'],
              username: isMe ? 'You' : 'Fan',
              time: timeStr,
            );
          }).toList();
        });
  }

  // Send a new message
  Future<void> sendMessage(String matchId, String text) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _client.from('chat_messages').insert({
      'match_id': matchId,
      'user_id': user.id,
      'message': text,
    });
  }
}
