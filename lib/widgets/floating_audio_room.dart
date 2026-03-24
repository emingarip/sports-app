import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/providers/voice_room_provider.dart';
import 'package:sports_app/screens/voice_room_screen.dart';

class FloatingAudioRoom extends ConsumerWidget {
  const FloatingAudioRoom({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceRoomProvider);
    final notifier = ref.read(voiceRoomProvider.notifier);

    if (!state.isConnected && !state.isConnecting) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (state.isConnected) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const VoiceRoomScreen()),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26, 
              blurRadius: 10, 
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            const _BlinkingMicIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.currentRoomName ?? 'Connecting...',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (state.isConnected)
                    Text(
                      '${state.participants.length} speaking/listening',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (state.isConnected)
              IconButton(
                icon: Icon(state.isMuted ? Icons.mic_off : Icons.mic, 
                  color: state.isMuted ? Colors.redAccent : Colors.greenAccent),
                onPressed: () => notifier.toggleMute(),
              ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => notifier.leaveRoom(),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingMicIcon extends StatefulWidget {
  const _BlinkingMicIcon();

  @override
  __BlinkingMicIconState createState() => __BlinkingMicIconState();
}

class __BlinkingMicIconState extends State<_BlinkingMicIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Icon(Icons.volume_up, color: Colors.greenAccent),
    );
  }
}
