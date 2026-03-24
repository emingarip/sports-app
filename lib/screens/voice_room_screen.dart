import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:sports_app/providers/voice_room_provider.dart';

class VoiceRoomScreen extends ConsumerWidget {
  const VoiceRoomScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceRoomProvider);
    final notifier = ref.read(voiceRoomProvider.notifier);

    if (!state.isConnected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Voice Room')),
        body: Center(
          child: state.isConnecting
              ? const CircularProgressIndicator()
              : Text(state.error ?? 'Not connected to any room.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(state.currentRoomName ?? 'Voice Room'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            onPressed: () {
              notifier.leaveRoom();
              Navigator.of(context).pop();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: state.participants.length,
              itemBuilder: (context, index) {
                final participant = state.participants[index];
                return _ParticipantAvatar(participant: participant);
              },
            ),
          ),
          _buildControlPanel(context, state, notifier),
        ],
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, VoiceRoomState state, VoiceRoomNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FloatingActionButton(
              heroTag: 'mute_btn',
              onPressed: () => notifier.toggleMute(),
              backgroundColor: state.isMuted ? Colors.redAccent : Theme.of(context).primaryColor,
              child: Icon(
                state.isMuted ? Icons.mic_off : Icons.mic,
                color: Colors.white,
              ),
            ),
            FloatingActionButton(
              heroTag: 'leave_btn',
              onPressed: () {
                notifier.leaveRoom();
                Navigator.of(context).pop();
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  final Participant participant;

  const _ParticipantAvatar({required this.participant});

  @override
  Widget build(BuildContext context) {
    final isSpeaking = participant.isSpeaking;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSpeaking ? Colors.greenAccent : Colors.transparent,
              width: 3,
            ),
          ),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Colors.grey.shade800,
            child: Text(
              participant.name.isNotEmpty ? participant.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 24, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          participant.name.isNotEmpty ? participant.name : 'Unknown',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
