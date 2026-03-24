import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:sports_app/providers/voice_room_provider.dart';
import 'package:sports_app/widgets/live_chat_panel.dart';
import 'package:sports_app/widgets/floating_emoji_animation.dart';

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
          if (state.isHost && state.raisedHands.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${state.raisedHands.length}'),
                child: const Icon(Icons.pan_tool),
              ),
              onPressed: () => _showModerationSheet(context, state, notifier),
            ),
          IconButton(
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            onPressed: () {
              notifier.leaveRoom();
              Navigator.of(context).pop();
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
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
          const FloatingEmojiAnimation(),
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
            if (state.canSpeak)
              FloatingActionButton(
                heroTag: 'mute_btn',
                onPressed: () => notifier.toggleMute(),
                backgroundColor: state.isMuted ? Colors.redAccent : Theme.of(context).primaryColor,
                child: Icon(
                  state.isMuted ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                ),
              )
            else
              FloatingActionButton(
                heroTag: 'raise_hand_btn',
                onPressed: () {
                  notifier.raiseHand();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hand raised! Waiting for host...')));
                },
                backgroundColor: Colors.orangeAccent,
                child: const Icon(Icons.pan_tool, color: Colors.white),
              ),
            FloatingActionButton(
              heroTag: 'chat_btn',
              onPressed: () => _showChatSheet(context),
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.chat, color: Colors.white),
            ),
            FloatingActionButton(
              heroTag: 'emoji_btn',
              onPressed: () => notifier.sendEmojiReaction('🔥'),
              backgroundColor: Colors.orange,
              child: const Icon(Icons.local_fire_department, color: Colors.white),
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

  void _showChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: const LiveChatPanel(),
        );
      },
    );
  }

  void _showModerationSheet(BuildContext context, VoiceRoomState state, VoiceRoomNotifier notifier) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Raised Hands', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (state.raisedHands.isEmpty)
                const Text('No pending requests.'),
              ...state.raisedHands.map((identity) {
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(identity),
                  trailing: ElevatedButton(
                    onPressed: () {
                      notifier.approveHand(identity);
                      Navigator.pop(context);
                    },
                    child: const Text('Approve'),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  final Participant participant;

  const _ParticipantAvatar({required this.participant});

  @override
  Widget build(BuildContext context) {
    final isSpeaking = participant.isSpeaking;

    return GestureDetector(
      onTap: () => _showUserProfile(context, participant.identity),
      child: Column(
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
        // End of Text widget
      ],
      ),
    );
  }

  void _showUserProfile(BuildContext context, String identity) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.blueAccent,
                  child: Text(
                    identity.isNotEmpty ? identity[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 32, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(identity, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Since this is MVP, we show placeholder stats that would normally be fetched from `users` table
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCol('Followers', '120'),
                    _buildStatCol('Following', '45'),
                    _buildStatCol('Reputation', 'Great'),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.person_add),
                  label: const Text('Follow User'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCol(String label, String val) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
