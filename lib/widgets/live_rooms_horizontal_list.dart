import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/active_rooms_provider.dart';
import '../theme/app_theme.dart';
import '../providers/voice_room_provider.dart';

class LiveRoomsHorizontalList extends ConsumerWidget {
  const LiveRoomsHorizontalList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRoomsAsync = ref.watch(activeRoomsProvider);

    return activeRoomsAsync.when(
      data: (rooms) {
        if (rooms.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.mic_external_on, color: context.colors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Canlı Odalar', 
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: context.colors.textHigh,
                    )
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('CANLI', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 140,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                scrollDirection: Axis.horizontal,
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  return Container(
                    width: 200,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Card(
                      color: context.colors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: context.colors.primary.withValues(alpha: 0.3)),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (room.isPrivate) {
                            // Show PIN dialog for private rooms
                            _showPinDialog(context, ref, room.roomName);
                          } else {
                            ref.read(voiceRoomProvider.notifier).joinRoom(room.roomName);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (room.isPrivate) ...[
                                    Icon(Icons.lock, size: 16, color: context.colors.primary),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(room.roomName, 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: context.colors.surfaceContainer,
                                    child: Icon(Icons.person, size: 14, color: context.colors.textMedium),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Host ID: ${room.hostId.substring(0, 5)}...', // Placeholder for actual host name
                                      style: TextStyle(fontSize: 12, color: context.colors.textMedium),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Icon(Icons.headset, size: 14, color: context.colors.primary),
                                  const SizedBox(width: 4),
                                  Text('${room.listenerCount} Dinleyici', style: TextStyle(fontSize: 12, color: context.colors.textLow)),
                                  const Spacer(),
                                  const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
      loading: () => const _LiveRoomsSkeleton(),
      error: (e, st) => const SizedBox.shrink(), // Silently fail if rooms can't load
    );
  }

  void _showPinDialog(BuildContext context, WidgetRef ref, String roomName) {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).extension<AppColors>()!.surfaceContainer,
        title: Text('Özel Odaya Katıl', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textHigh)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bu odaya katılmak için PIN kodunu giriniz.', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMedium)),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textHigh),
              decoration: InputDecoration(
                hintText: 'PIN Kodu',
                hintStyle: TextStyle(color: Theme.of(context).extension<AppColors>()!.textLow),
                filled: true,
                fillColor: Theme.of(context).extension<AppColors>()!.surfaceContainerHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).extension<AppColors>()!.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              ref.read(voiceRoomProvider.notifier).joinRoom(roomName, pinCode: pinController.text);
            },
            child: const Text('Katıl'),
          ),
        ],
      ),
    );
  }
}

class _LiveRoomsSkeleton extends StatelessWidget {
  const _LiveRoomsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).extension<AppColors>()!.surfaceContainerLow,
      highlightColor: Theme.of(context).extension<AppColors>()!.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
             padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
             child: Container(width: 120, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
          ),
          SizedBox(
            height: 140,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (context, index) {
                return Container(
                  width: 200,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)
                  ),
                );
              }
            )
          )
        ]
      )
    );
  }
}
