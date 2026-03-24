import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' hide ChatMessage;
import 'package:sports_app/services/livekit_service.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:sports_app/models/voice_chat_models.dart';
import 'dart:convert';

class VoiceRoomState {
  final bool isConnecting;
  final bool isConnected;
  final String? currentRoomName;
  final bool isMuted;
  final String? error;
  final List<Participant> participants;
  final bool isHost;
  final bool canSpeak;
  final Set<String> raisedHands;
  final List<ChatMessage> chatMessages;
  final List<EmojiReaction> emojiReactions;

  const VoiceRoomState({
    this.isConnecting = false,
    this.isConnected = false,
    this.currentRoomName,
    this.isMuted = true,
    this.error,
    this.participants = const [],
    this.isHost = false,
    this.canSpeak = false,
    this.raisedHands = const {},
    this.chatMessages = const [],
    this.emojiReactions = const [],
  });

  VoiceRoomState copyWith({
    bool? isConnecting,
    bool? isConnected,
    String? currentRoomName,
    bool? isMuted,
    String? error,
    List<Participant>? participants,
    bool? isHost,
    bool? canSpeak,
    Set<String>? raisedHands,
    List<ChatMessage>? chatMessages,
    List<EmojiReaction>? emojiReactions,
  }) {
    return VoiceRoomState(
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      currentRoomName: currentRoomName ?? this.currentRoomName,
      isMuted: isMuted ?? this.isMuted,
      error: error, // Can be null to clear
      participants: participants ?? this.participants,
      isHost: isHost ?? this.isHost,
      canSpeak: canSpeak ?? this.canSpeak,
      raisedHands: raisedHands ?? this.raisedHands,
      chatMessages: chatMessages ?? this.chatMessages,
      emojiReactions: emojiReactions ?? this.emojiReactions,
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

      bool isHost = false;
      if (user != null) {
        final roomData = await SupabaseService.client
            .from('audio_rooms')
            .select('host_id')
            .eq('room_name', roomName)
            .maybeSingle();
        if (roomData != null && roomData['host_id'] == user.id) {
          isHost = true;
        }
      }

      await _liveKitService.connect(roomName, participantName, isHost: isHost);
      
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
          isHost: isHost,
          canSpeak: isHost, // Hosts can speak by default
        );
      }
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        error: e.toString(),
      );
    }
  }

  Future<void> createAndJoinRoom(String matchId, String baseRoomName) async {
    final uniqueRoomName = '${baseRoomName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    
    state = state.copyWith(isConnecting: true, error: null);
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        await SupabaseService.client.from('audio_rooms').insert({
          'room_name': uniqueRoomName,
          'host_id': user.id,
          'match_id': matchId,
          'status': 'active',
          'listener_count': 0,
        });
      }
      
      await joinRoom(uniqueRoomName);
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        error: 'Failed to create room: $e',
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
      ..on<DataReceivedEvent>((e) {
        _handleDataReceived(e.data, e.participant);
      })
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

  void _handleDataReceived(List<int> data, RemoteParticipant? participant) {
    try {
      final jsonStr = utf8.decode(data);
      final payload = jsonDecode(jsonStr);
      
      if (payload['type'] == 'raise_hand' && state.isHost) {
        if (participant != null) {
          final newHands = Set<String>.from(state.raisedHands);
          newHands.add(participant.identity);
          state = state.copyWith(raisedHands: newHands);
          debugPrint('User ${participant.identity} raised hand!');
        }
      } else if (payload['type'] == 'hand_approved' && payload['targetIdentity'] == _liveKitService.room?.localParticipant?.identity) {
        // We were approved!
        debugPrint('Hand approved! Reconnecting as speaker.');
        becomeSpeaker();
      } else if (payload['type'] == 'chat') {
        final message = ChatMessage(
          sender: payload['sender'] ?? 'Unknown',
          text: payload['text'] ?? '',
          timestamp: DateTime.now(),
        );
        state = state.copyWith(chatMessages: [...state.chatMessages, message]);
      } else if (payload['type'] == 'emoji') {
        final reaction = EmojiReaction(
          id: DateTime.now().millisecondsSinceEpoch.toString() + payload['sender'],
          emoji: payload['emoji'] ?? '🔥',
          sender: payload['sender'] ?? 'Unknown',
        );
        state = state.copyWith(emojiReactions: [...state.emojiReactions, reaction]);
        
        // Remove emoji after a short delay so it doesn't pile up in state indefinitely
        Future.delayed(const Duration(seconds: 3), () {
          try {
            final newReactions = List<EmojiReaction>.from(state.emojiReactions)..removeWhere((e) => e.id == reaction.id);
            state = state.copyWith(emojiReactions: newReactions);
          } catch (_) {
            // Notifier might be disposed
          }
        });
      }
    } catch (e) {
      debugPrint('Error parsing data channel message: $e');
    }
  }

  Future<void> raiseHand() async {
    final room = _liveKitService.room;
    if (room != null && room.localParticipant != null) {
      final payload = jsonEncode({'type': 'raise_hand'});
      await room.localParticipant!.publishData(utf8.encode(payload), reliable: true);
    }
  }

  Future<void> approveHand(String targetIdentity) async {
    final room = _liveKitService.room;
    if (room != null && room.localParticipant != null && state.isHost) {
      final payload = jsonEncode({'type': 'hand_approved', 'targetIdentity': targetIdentity});
      await room.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      
      final newHands = Set<String>.from(state.raisedHands);
      newHands.remove(targetIdentity);
      state = state.copyWith(raisedHands: newHands);
    }
  }

  Future<void> sendChatMessage(String text) async {
    final room = _liveKitService.room;
    if (room != null && room.localParticipant != null) {
      final senderName = room.localParticipant!.identity;
      final payload = jsonEncode({
        'type': 'chat',
        'text': text,
        'sender': senderName,
      });
      await room.localParticipant!.publishData(utf8.encode(payload), reliable: true);
      
      // Add local echo
      final message = ChatMessage(
        sender: senderName,
        text: text,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(chatMessages: [...state.chatMessages, message]);
    }
  }

  Future<void> sendEmojiReaction(String emoji) async {
    final room = _liveKitService.room;
    if (room != null && room.localParticipant != null) {
      final senderName = room.localParticipant!.identity;
      final payload = jsonEncode({
        'type': 'emoji',
        'emoji': emoji,
        'sender': senderName,
      });
      // Use reliable: false for emojis as they are transient
      await room.localParticipant!.publishData(utf8.encode(payload), reliable: false);
      
      // Add local echo
      final reaction = EmojiReaction(
        id: DateTime.now().millisecondsSinceEpoch.toString() + senderName,
        emoji: emoji,
        sender: senderName,
      );
      state = state.copyWith(emojiReactions: [...state.emojiReactions, reaction]);
      
      Future.delayed(const Duration(seconds: 3), () {
        try {
          final newReactions = List<EmojiReaction>.from(state.emojiReactions)..removeWhere((e) => e.id == reaction.id);
          state = state.copyWith(emojiReactions: newReactions);
        } catch (_) {
          // Notifier might be disposed
        }
      });
    }
  }

  Future<void> becomeSpeaker() async {
    final currentRoom = state.currentRoomName;
    if (currentRoom != null) {
      await leaveRoom();
      
      final user = SupabaseService.client.auth.currentUser;
      final participantName = user?.userMetadata?['username'] ?? user?.email ?? 'Anonymous';
      
      state = state.copyWith(isConnecting: true, error: null);
      try {
        await _liveKitService.connect(currentRoom, participantName, isHost: false, canPublish: true);
        final room = _liveKitService.room;
        if (room != null) {
          _listenToRoomEvents(room);
          state = state.copyWith(
            isConnecting: false,
            isConnected: true,
            currentRoomName: currentRoom,
            participants: _getParticipants(room),
            isMuted: false, // Default unmuted when becoming a speaker
            isHost: false,
            canSpeak: true,
          );
          // ensure mic is enabled
          await room.localParticipant?.setMicrophoneEnabled(true);
        }
      } catch (e) {
        state = state.copyWith(isConnecting: false, error: 'Failed to reconnect as speaker: $e');
      }
    }
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
