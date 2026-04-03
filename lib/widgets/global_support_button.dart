import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/support_providers.dart';
import '../screens/private_chat_screen.dart';
import '../services/navigation_service.dart';

class GlobalSupportButton extends ConsumerStatefulWidget {
  const GlobalSupportButton({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<GlobalSupportButton> createState() => _GlobalSupportButtonState();
}

class _GlobalSupportButtonState extends ConsumerState<GlobalSupportButton> {
  Offset? position;
  bool isDragging = false;
  final double buttonSize = 56.0;

  void _snapToEdge(Size screenSize) {
    if (position == null) return;
    
    // Safety padding
    const double padding = 16.0;
    final double maxX = screenSize.width - buttonSize - padding;
    final double maxY = screenSize.height - buttonSize - padding;
    final double minY = MediaQuery.of(context).padding.top + padding;

    double targetX;
    // Nearest horizontal edge
    if (position!.dx + (buttonSize / 2) < screenSize.width / 2) {
      targetX = padding; // Snap to left
    } else {
      targetX = maxX; // Snap to right
    }

    // Keep within vertical bounds
    double targetY = position!.dy.clamp(minY, maxY);

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

      NavigationService.navigatorKey.currentState?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'chat'),
          builder: (context) => PrivateChatScreen(
            roomId: roomData['roomId'] as String,
            otherUserId: roomData['adminId'] as String,
            otherUsername: roomData['adminName'] ?? 'Canlı Destek',
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
    // Check if visibility is explicitly disabled via provider
    final isVisible = ref.watch(supportButtonVisibilityProvider);
    if (!isVisible) return widget.child;

    // Only show if user is logged in
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return widget.child;

    final Size screenSize = MediaQuery.of(context).size;
    final double padding = 16.0;

    // Initialize position if null
    position ??= Offset(
      screenSize.width - buttonSize - padding,
      screenSize.height * 0.7,
    );

    // Clamping against CURRENT constraints to handle window resizing
    final double currentX = position!.dx.clamp(0.0, screenSize.width - buttonSize);
    final double currentY = position!.dy.clamp(0.0, screenSize.height - buttonSize);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: currentX,
          top: currentY,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onPanStart: (_) => setState(() => isDragging = true),
              onPanUpdate: (details) {
                setState(() {
                  position = Offset(
                    (position!.dx + details.delta.dx).clamp(0, screenSize.width - buttonSize),
                    (position!.dy + details.delta.dy).clamp(0, screenSize.height - buttonSize),
                  );
                });
              },
              onPanEnd: (_) => _snapToEdge(screenSize),
              onTap: _handleTap,
              child: AnimatedScale(
                scale: isDragging ? 0.9 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: _buildButtonBody(),
              ),
            ),
          ),
        ),
      ],
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
