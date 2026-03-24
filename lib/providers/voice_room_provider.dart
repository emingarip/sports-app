import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:sports_app/services/livekit_service.dart';
import 'package:sports_app/services/supabase_service.dart';

class VoiceRoomState {
  final bool isConnecting;
  final bool isConnected;
  final String? currentRoomName;
  final bool isMuted;
  final String? error;
  final List<Participant> participants;

  const VoiceRoomState({
    this.isConnecting = false,
    this.isConnected = false,
    this.currentRoomName,
    this.isMuted = true,
    this.error,
    this.participants = const [],
  });

  VoiceRoomState copyWith({
    bool? isConnecting,
    bool? isConnected,
    String? currentRoomName,
    bool? isMuted,
    String? error,
    List<Participant>? participants,
  }) {
    return VoiceRoomState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      currentRoomName: currentRoomName ?? this.currentRoomName,
      isMuted: isMuted ?? this.isMuted,
      error: error, // Can be null to clear
      participants: participants ?? this.participants,
    );
  }
}

class VoiceRoomNotifier extends Notifier<VoiceRoomState> {
  final LiveKitService _liveKitService = LiveKitService();
  EventsListener<RoomEvent>? _listener;

  @override
  VoiceRoomState build() {
    ref.onDispose(() {
      leaveRoom();
    });
    return const VoiceRoomState();
  }

  Future<void> joinRoom(String roomName) async {
    state = state.copyWith(isConnecting: true, error: null);
    
    try {
      final user = SupabaseService.client.auth.currentUser;
      final participantName = user?.userMetadata?['username'] ?? user?.email ?? 'Anonymous';

      await _liveKitService.connect(roomName, participantName);
      
      final room = _liveKitService.room;
      if (room != null) {
        _listenToRoomEvents(room);
        
        // Initial state
        state = state.copyWith(
          isConnecting: false,
          isConnected: true,
          currentRoomName: roomName,
          participants: _getParticipants(room),
          isMuted: !(room.localParticipant?.isMicrophoneEnabled() ?? false),
        );
      }
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        error: e.toString(),
      );
    }
  }

  void _listenToRoomEvents(Room room) {
    _listener?.dispose();
    _listener = room.createListener();

    _listener!
      ..on<ParticipantConnectedEvent>((e) => _updateParticipants())
      ..on<ParticipantDisconnectedEvent>((e) => _updateParticipants())
      ..on<TrackPublishedEvent>((e) => _updateParticipants())
      ..on<TrackUnpublishedEvent>((e) => _updateParticipants())
      ..on<ActiveSpeakersChangedEvent>((e) => _updateParticipants())
      ..on<RoomDisconnectedEvent>((e) {
        leaveRoom();
      });
  }

  void _updateParticipants() {
    final room = _liveKitService.room;
    if (room != null) {
      state = state.copyWith(participants: _getParticipants(room));
    }
  }

  List<Participant> _getParticipants(Room room) {
    final list = <Participant>[];
    if (room.localParticipant != null) {
      list.add(room.localParticipant!);
    }
    list.addAll(room.remoteParticipants.values);
    return list;
  }

  Future<void> leaveRoom() async {
    _listener?.dispose();
    _listener = null;
    await _liveKitService.disconnect();
    state = const VoiceRoomState(); // Reset state
  }

  Future<void> toggleMute() async {
    final room = _liveKitService.room;
    if (room != null && room.localParticipant != null) {
      final isCurrentlyMuted = !(room.localParticipant!.isMicrophoneEnabled());
      await room.localParticipant!.setMicrophoneEnabled(isCurrentlyMuted); // Toggle
      state = state.copyWith(isMuted: !isCurrentlyMuted);
    }
  }
}

final voiceRoomProvider = NotifierProvider<VoiceRoomNotifier, VoiceRoomState>(VoiceRoomNotifier.new);
