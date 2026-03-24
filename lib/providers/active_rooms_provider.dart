import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/models/audio_room.dart';
import 'package:sports_app/services/supabase_service.dart';

final activeRoomsProvider = StreamProvider.autoDispose<List<AudioRoom>>((ref) {
  return SupabaseService.client
      .from('audio_rooms')
      .stream(primaryKey: ['id'])
      .map((list) {
        final activeRooms = list
            .where((json) => json['status'] == 'active')
            .map((json) => AudioRoom.fromJson(json))
            .toList();
        
        activeRooms.sort((a, b) => b.listenerCount.compareTo(a.listenerCount));
        return activeRooms.take(10).toList();
      });
});

final matchRoomsProvider = StreamProvider.autoDispose.family<List<AudioRoom>, String>((ref, matchId) {
  return SupabaseService.client
      .from('audio_rooms')
      .stream(primaryKey: ['id'])
      .map((list) {
        final matchRooms = list
            .where((json) => json['status'] == 'active' && json['match_id'] == matchId)
            .map((json) => AudioRoom.fromJson(json))
            .toList();
            
        matchRooms.sort((a, b) => b.listenerCount.compareTo(a.listenerCount));
        return matchRooms;
      });
});
