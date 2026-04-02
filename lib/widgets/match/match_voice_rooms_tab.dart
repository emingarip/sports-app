import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/audio_room.dart';
import '../../models/match.dart' as app_match;
import '../../providers/active_rooms_provider.dart';
import '../../providers/voice_room_provider.dart';
import '../../theme/app_theme.dart';
import '../shimmer_loading.dart';
import '../../screens/voice_room_screen.dart';

class MatchVoiceRoomsTab extends ConsumerStatefulWidget {
  final app_match.Match match;

  const MatchVoiceRoomsTab({
    Key? key,
    required this.match,
  }) : super(key: key);

  @override
  ConsumerState<MatchVoiceRoomsTab> createState() => _MatchVoiceRoomsTabState();
}

class _MatchVoiceRoomsTabState extends ConsumerState<MatchVoiceRoomsTab> {
  void _showCreateMatchRoomDialog() {
    final TextEditingController roomController = TextEditingController(
        text: '${widget.match.homeTeam} vs ${widget.match.awayTeam} Sohbeti');
    final TextEditingController pinController = TextEditingController();
    bool isPrivate = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: context.colors.surfaceContainerHigh,
              title: const Text('🗣️ Canlı Oda Başlat',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roomController,
                    decoration: InputDecoration(
                      hintText: 'Oda Adı',
                      filled: true,
                      fillColor: context.colors.surfaceContainerLow,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gizli Oda (Şifreli)',
                          style: TextStyle(color: context.colors.textMedium)),
                      Switch(
                        value: isPrivate,
                        onChanged: (val) => setState(() => isPrivate = val),
                        activeColor: context.colors.primary,
                      ),
                    ],
                  ),
                  if (isPrivate) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: InputDecoration(
                        hintText: '4 Haneli PIN',
                        filled: true,
                        fillColor: context.colors.surfaceContainerLow,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        counterText: '',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('İptal',
                      style: TextStyle(color: context.colors.textMedium)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final roomName = roomController.text.trim();
                    final pinCode = pinController.text.trim();

                    if (roomName.isNotEmpty) {
                      if (isPrivate &&
                          (pinCode.length != 4 ||
                              int.tryParse(pinCode) == null)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Lütfen 4 haneli sayısal bir PIN giriniz.')),
                        );
                        return;
                      }

                      // Show loading indicator
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) =>
                            const Center(child: CircularProgressIndicator()),
                      );

                      try {
                        // Check if user is already hosting a room
                        final userId =
                            Supabase.instance.client.auth.currentUser?.id;
                        if (userId != null) {
                          final existingRooms = await Supabase.instance.client
                              .from('audio_rooms')
                              .select('id')
                              .eq('host_id', userId)
                              .eq('status', 'active');

                          if (!context.mounted) return;

                          if (existingRooms.isNotEmpty) {
                            Navigator.of(context).pop(); // close loading
                            Navigator.of(context).pop(); // close dialog
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Zaten aktif bir odanız bulunuyor. Önce onu kapatmalısınız.'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                        }

                        ref.read(voiceRoomProvider.notifier).createAndJoinRoom(
                              widget.match.id,
                              roomName,
                              isPrivate: isPrivate,
                              pinCode: isPrivate ? pinCode : null,
                            );

                        if (!context.mounted) return;
                        Navigator.of(context).pop(); // close loading
                        Navigator.of(context).pop(); // close dialog
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const VoiceRoomScreen()));
                      } catch (e) {
                        if (!context.mounted) return;
                        Navigator.of(context).pop(); // close loading
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPinEntryDialog(AudioRoom room) {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: context.colors.surfaceContainerHigh,
          title: const Text('🔒 Gizli Oda',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${room.roomName}\nodasına katılmak için PIN giriniz.',
                  style: TextStyle(color: context.colors.textMedium)),
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '4 Haneli PIN',
                  filled: true,
                  fillColor: context.colors.surfaceContainerLow,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('İptal',
                  style: TextStyle(color: context.colors.textMedium)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (pinController.text.trim() == room.pinCode) {
                  Navigator.of(context).pop();
                  ref.read(voiceRoomProvider.notifier).joinRoom(room.roomName);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const VoiceRoomScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Hatalı PIN kodu!'),
                        backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Katıl'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPremiumCreateBanner() {
    return GestureDetector(
      onTap: _showCreateMatchRoomDialog,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF15151A),
              Color(0xFF22222E),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                right: -40,
                top: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8A2BE2).withValues(alpha: 0.4),
                        blurRadius: 50,
                        spreadRadius: 20,
                      )
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 18.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8A2BE2), Color(0xFF4A00E0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8A2BE2)
                                .withValues(alpha: 0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: const Icon(Icons.mic_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Canlı Oda Başlat",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Taraftarlarla sesli etkileşime geç",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBentoRoomCard(AudioRoom room) {
    // Determine dynamic properties
    final isLive = room.listenerCount > 0;
    final primaryColor =
        isLive ? const Color(0xFF8B5CF6) : const Color(0xFF10B981);
    final secondaryColor =
        isLive ? const Color(0xFF6D28D9) : const Color(0xFF059669);

    return GestureDetector(
      onTap: () {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        final isHost = room.hostId == userId;

        if (room.isPrivate && !isHost) {
          _showPinEntryDialog(room);
        } else {
          ref.read(voiceRoomProvider.notifier).joinRoom(room.roomName);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const VoiceRoomScreen()));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Top Accent Line
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient:
                      LinearGradient(colors: [primaryColor, secondaryColor]),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Avatar & Status Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar with Gradient Ring
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                  colors: [primaryColor, secondaryColor],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight),
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                              child: Icon(Icons.face,
                                  color: primaryColor, size: 30),
                            ),
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: room.isPrivate
                                    ? const Color(0xFFEAB308)
                                    : const Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(
                                  room.isPrivate ? Icons.lock : Icons.verified,
                                  color: Colors.white,
                                  size: 10),
                            ),
                          ),
                        ],
                      ),
                      // Status Badge
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLive ? Colors.red : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: isLive
                                ? [
                                    BoxShadow(
                                        color:
                                            Colors.red.withValues(alpha: 0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: Text(
                            isLive ? "LIVE" : "SCHEDULED",
                            style: TextStyle(
                              color: isLive ? Colors.white : Colors.grey[400],
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  // Room Title & Host
                  Text(
                    room.roomName,
                    style: const TextStyle(
                        color: Color(0xFF191C1E),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        fontFamily: 'Lexend'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "@Host_User",
                    style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Outfit'),
                  ),

                  const Spacer(),
                  // Listeners Stack
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 28,
                        child: Stack(
                          children: List.generate(
                            room.listenerCount > 3
                                ? 3
                                : (room.listenerCount == 0
                                    ? 1
                                    : room.listenerCount),
                            (i) => Positioned(
                              left: i * 14.0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[200],
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    String.fromCharCode(65 +
                                        ((room.roomName.length + i * 3) % 26)),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "${room.listenerCount} LISTENING",
                          style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  // Tags Row
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text("ANALYSIS",
                            style: TextStyle(
                                color: primaryColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text("TACTICS",
                            style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchRoomsAsync = ref.watch(matchRoomsProvider(widget.match.id));

    return Column(
      children: [
        Container(
          color: context.colors.background,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: _buildPremiumCreateBanner(),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: matchRoomsAsync.when(
                  data: (rooms) {
                    if (rooms.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_off,
                                  size: 48,
                                  color: context.colors.surfaceContainerHigh),
                              const SizedBox(height: 16),
                              Text("Henüz oda açılmamış",
                                  style: TextStyle(
                                      color: context.colors.textMedium)),
                            ],
                          ),
                        ),
                      );
                    }
                    return SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 280, // Wider for detailed card
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent:
                            240, // Taller card for the rich Stitch design
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final room = rooms[index];
                          return _buildBentoRoomCard(room);
                        },
                        childCount: rooms.length,
                      ),
                    );
                  },
                  loading: () => const SliverFillRemaining(
                      child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: ListShimmer(itemCount: 4))),
                  error: (e, st) => SliverFillRemaining(
                      child: Center(child: Text('Hata: $e'))),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
      ],
    );
  }
}
