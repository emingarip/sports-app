import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/support_providers.dart';
import '../screens/private_chat_screen.dart';
import '../main.dart';

class GlobalSupportButton extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalSupportButton({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<GlobalSupportButton> createState() => _GlobalSupportButtonState();
}

class _GlobalSupportButtonState extends ConsumerState<GlobalSupportButton> {
  Offset? position; 
  bool isDragging = false;
  final double buttonSize = 56.0;

  void _snapToEdge(BoxConstraints constraints) {
    if (position == null) return;
    
    double targetX;
    // Nearest horizontal edge within constraints
    if (position!.dx + (buttonSize / 2) < constraints.maxWidth / 2) {
      targetX = 16; // Snap to left
    } else {
      targetX = constraints.maxWidth - buttonSize - 16; // Snap to right
    }

    // Keep within vertical bounds
    double minTop = MediaQuery.of(context).padding.top + 16;
    double maxBottom = constraints.maxHeight - MediaQuery.of(context).padding.bottom - buttonSize - 16;
    double targetY = position!.dy.clamp(minTop, maxBottom);

    setState(() {
      position = Offset(targetX, targetY);
      isDragging = false;
    });
  }

  Future<void> _handleTap() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      final supportRepo = ref.read(supportRepositoryProvider);
      final roomData = await supportRepo.prepareSupportRoom();

      if (!mounted) return;

      MyApp.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => PrivateChatScreen(
            roomId: roomData['room_id'],
            otherUserId: roomData['admin_id'],
            otherUsername: 'Canlı Destek',
          ),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Destek odası hazırlanamadı: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show if user is logged in
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Initialize position if null
        position ??= Offset(
          constraints.maxWidth - buttonSize - 16,
          constraints.maxHeight * 0.7,
        );

        return Stack(
          children: [
            widget.child,
            Positioned(
              left: position!.dx,
              top: position!.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() => isDragging = true),
                onPanUpdate: (details) {
                  setState(() {
                    position = Offset(
                      (position!.dx + details.delta.dx).clamp(0, constraints.maxWidth - buttonSize),
                      (position!.dy + details.delta.dy).clamp(0, constraints.maxHeight - buttonSize),
                    );
                  });
                },
                onPanEnd: (_) => _snapToEdge(constraints),
                onTap: _handleTap,
                child: AnimatedScale(
                  scale: isDragging ? 0.9 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: _buildButtonBody(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildButtonBody() {
    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFACC15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.headset_mic_rounded,
            color: Color(0xFF5B4B00),
            size: 28,
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
