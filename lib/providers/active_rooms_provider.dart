import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/models/audio_room.dart';
import 'package:sports_app/services/supabase_service.dart';

final activeRoomsProvider = FutureProvider.autoDispose<List<AudioRoom>>((ref) async {
  try {
    final response = await SupabaseService.client
        .from('audio_rooms')
        .select()
        .eq('status', 'active')
        .order('listener_count', ascending: false)
        .limit(10);
        
    return (response as List).map((json) => AudioRoom.fromJson(json)).toList();
  } catch (e) {
    throw Exception('Failed to load active rooms: $e');
  }
});

final matchRoomsProvider = FutureProvider.autoDispose.family<List<AudioRoom>, String>((ref, matchId) async {
  try {
    final response = await SupabaseService.client
        .from('audio_rooms')
        .select()
        .eq('status', 'active')
        .eq('match_id', matchId)
        .order('listener_count', ascending: false);
        
    return (response as List).map((json) => AudioRoom.fromJson(json)).toList();
  } catch (e) {
    throw Exception('Failed to load match rooms: $e');
  }
});
