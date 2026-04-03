import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/chat_service.dart';

class SupportRepository {
  static const String supportId = '00000000-0000-0000-0000-000000000999';
  final _chatService = ChatService();
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> prepareSupportRoom() async {
    final roomId = await _chatService.getOrCreatePrivateRoom(supportId);
    
    // Fetch admin info for display
    final adminRes = await _supabase
        .from('users')
        .select('username, avatar_url, active_frame')
        .eq('id', supportId)
        .single();

    return {
      'roomId': roomId,
      'adminId': supportId,
      'adminName': adminRes['username'] ?? 'Müşteri Destek',
      'adminAvatarUrl': adminRes['avatar_url'],
      'adminActiveFrame': adminRes['active_frame'],
    };
  }
}
