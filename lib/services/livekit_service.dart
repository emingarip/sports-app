import 'package:flutter/foundation.dart';

import 'package:livekit_client/livekit_client.dart';
import 'package:sports_app/services/supabase_service.dart';

class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();

  factory LiveKitService() {
    return _instance;
  }

  LiveKitService._internal();

  Room? room;

  Future<String> _fetchToken(String roomName, String participantName, {String? userId, bool isHost = false, bool canPublish = false, String? pinCode}) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'livekit-token',
        body: {'roomName': roomName, 'participantName': participantName, 'userId': userId, 'isHost': isHost, 'canPublish': canPublish, if (pinCode != null) 'pinCode': pinCode},
      );
      
      if (response.status != 200) {
        throw Exception('Failed to fetch token: ${response.data}');
      }
      return response.data['token'] as String;
    } catch (e) {
      debugPrint('Error invoking livekit-token: $e');
      rethrow;
    }
  }

  Future<void> connect(String roomName, String participantName, {String? userId, bool isHost = false, bool canPublish = false, String? pinCode}) async {
    try {
      final token = await _fetchToken(roomName, participantName, userId: userId, isHost: isHost, canPublish: canPublish, pinCode: pinCode);
      
      const url = String.fromEnvironment('LIVEKIT_URL', defaultValue: 'wss://boskalecom-2zi7gj0y.livekit.cloud');

      if (url.contains('your-livekit-project')) {
          debugPrint('WARNING: LIVEKIT_URL is not set via dart-define. Using placeholder.');
      }

      const roomOptions = RoomOptions(
        adaptiveStream: true,
        dynacast: true,
      );

      room = Room();
      await room!.connect(url, token, roomOptions: roomOptions);
      
      debugPrint('Connected to LiveKit room: $roomName');
    } catch (e) {
      debugPrint('Error connecting to LiveKit room: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await room?.disconnect();
    room = null;
    debugPrint('Disconnected from LiveKit room');
  }
}
