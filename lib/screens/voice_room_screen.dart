import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:sports_app/providers/voice_room_provider.dart';
import 'package:sports_app/widgets/live_chat_panel.dart';
import 'package:sports_app/widgets/floating_emoji_animation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sports_app/providers/follow_provider.dart';
import 'package:sports_app/services/navigation_service.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:sports_app/theme/app_theme.dart';

class VoiceRoomScreen extends ConsumerWidget {
  const VoiceRoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for room termination from host
    ref.listen<VoiceRoomState>(voiceRoomProvider, (previous, next) {
      if (previous != null &&
          previous.isConnected &&
          !next.isConnected &&
          next.error == 'room_ended') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Oda kapatıldı 👋'),
            backgroundColor: context.colors.liveAccent,
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    });

    final state = ref.watch(voiceRoomProvider);
    final notifier = ref.read(voiceRoomProvider.notifier);

    if (!state.isConnected) {
      // Don't show generic error if we are leaving normally due to room ended
      if (state.error == 'room_ended') {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

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
          if (state.isHost && state.isPrivate && state.pinCode != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.accent, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_person,
                        size: 16,
                        color: context.colors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'PIN: ${state.pinCode}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: context.colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.share, color: context.colors.primary),
            onPressed: () async {
              final roomNameEscaped =
                  Uri.encodeComponent(state.currentRoomName ?? '');
              var shareText = 'Spor odama katıl! Oda: ${state.currentRoomName}';

              if (state.isPrivate && state.pinCode != null) {
                shareText += '\nOda Şifresi: ${state.pinCode}';
              }

              String link;
              if (kIsWeb) {
                final baseUri = Uri.base;
                final params = {'room': state.currentRoomName!};
                if (state.isPrivate && state.pinCode != null) {
                  params['pin'] = state.pinCode!;
                }
                link = baseUri.replace(queryParameters: params).toString();
              } else {
                link = 'sportsapp://room?name=$roomNameEscaped';
                if (state.isPrivate && state.pinCode != null) {
                  link += '&pin=${state.pinCode}';
                }
              }

              shareText += '\n\nKatılmak için tıkla:\n$link';

              if (kIsWeb) {
                await Clipboard.setData(ClipboardData(text: shareText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Davet linki panoya kopyalandı!'),
                      backgroundColor: context.colors.success,
                    ),
                  );
                }
              } else {
                try {
                  await Share.share(shareText);
                } catch (e) {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Davet panoya kopyalandı!')),
                    );
                  }
                }
              }
            },
          ),
          if (state.isHost && state.raisedHands.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${state.raisedHands.length}'),
                child: const Icon(Icons.pan_tool),
              ),
              onPressed: () => _showModerationSheet(context, state, notifier),
            ),
          IconButton(
            icon: Icon(Icons.exit_to_app, color: context.colors.error),
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

  Widget _buildControlPanel(
      BuildContext context, VoiceRoomState state, VoiceRoomNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: context.colors.cardShadow.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (state.canSpeak)
              FloatingActionButton(
                heroTag: 'mute_btn',
                onPressed: () => notifier.toggleMute(),
                backgroundColor: state.isMuted
                    ? context.colors.error
                    : context.colors.primaryContainer,
                child: Icon(
                  state.isMuted ? Icons.mic_off : Icons.mic,
                  color: state.isMuted
                      ? context.colors.onErrorContainer
                      : context.colors.onPrimaryContainer,
                ),
              )
            else
              FloatingActionButton(
                heroTag: 'raise_hand_btn',
                onPressed: () {
                  notifier.raiseHand();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Hand raised! Waiting for host...'),
                      backgroundColor: context.colors.accent,
                    ),
                  );
                },
                backgroundColor: context.colors.accent,
                child: Icon(
                  Icons.pan_tool,
                  color: context.colors.onPrimaryContainer,
                ),
              ),
            FloatingActionButton(
              heroTag: 'chat_btn',
              onPressed: () => _showChatSheet(context),
              backgroundColor: context.colors.primary,
              child: Icon(Icons.chat, color: context.colors.surface),
            ),
            FloatingActionButton(
              heroTag: 'emoji_btn',
              onPressed: () => notifier.sendEmojiReaction('🔥'),
              backgroundColor: context.colors.liveAccentMuted,
              child: Icon(
                Icons.local_fire_department,
                color: context.colors.onPrimaryContainer,
              ),
            ),
            FloatingActionButton(
              heroTag: 'leave_btn',
              onPressed: () {
                notifier.leaveRoom();
                Navigator.of(context).pop();
              },
              backgroundColor: context.colors.error,
              child: Icon(
                Icons.call_end,
                color: context.colors.onErrorContainer,
              ),
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
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: const LiveChatPanel(),
        );
      },
    );
  }

  void _showModerationSheet(
      BuildContext context, VoiceRoomState state, VoiceRoomNotifier notifier) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Raised Hands',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (state.raisedHands.isEmpty) const Text('No pending requests.'),
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
      onTap: () =>
          _showUserProfile(context, participant.identity, participant.name),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpeaking ? context.colors.success : Colors.transparent,
                width: 3,
              ),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: context.colors.surfaceContainerHighest,
              child: Text(
                participant.name.isNotEmpty
                    ? participant.name[0].toUpperCase()
                    : '?',
                style: TextStyle(fontSize: 24, color: context.colors.textHigh),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            participant.name.isNotEmpty ? '@${participant.name}' : 'Unknown',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // End of Text widget
        ],
      ),
    );
  }

  void _showUserProfile(
      BuildContext context, String userId, String displayName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final followState = ref.watch(followProvider);
            final followingList = followState.value ?? [];
            final isFollowing = followingList.contains(userId);

            final followerCountAsync = ref.watch(followerCountProvider(userId));
            final followingCountAsync =
                ref.watch(followingCountProvider(userId));

            final followerCount = followerCountAsync.value ?? 0;
            final followingCount = followingCountAsync.value ?? 0;

            final isMe = SupabaseService.client.auth.currentUser?.id == userId;

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: context.colors.primaryContainer,
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 32,
                          color: context.colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(displayName,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatCol('Takipçi', followerCount.toString()),
                        _buildStatCol('Takip', followingCount.toString()),
                        _buildStatCol('İtibar', 'Harika'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (!isMe)
                      ElevatedButton.icon(
                        onPressed: () {
                          ref
                              .read(followProvider.notifier)
                              .toggleFollow(userId);
                        },
                        icon:
                            Icon(isFollowing ? Icons.check : Icons.person_add),
                        label: Text(isFollowing ? 'Takipten Çık' : 'Takip Et'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFollowing
                              ? context.colors.surfaceContainerHighest
                              : context.colors.primaryContainer,
                          foregroundColor: isFollowing
                              ? context.colors.textHigh
                              : context.colors.onPrimaryContainer,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      const SizedBox(height: 50), // Spacer for self
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCol(String label, String val) {
    final currentContext = NavigationService.navigatorKey.currentContext;
    final textLow = currentContext != null
        ? currentContext.colors.textLow
        : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(val,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(
          label,
          style: TextStyle(color: textLow, fontSize: 12),
        ),
      ],
    );
  }
}
