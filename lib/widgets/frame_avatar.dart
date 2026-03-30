import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' hide LinearGradient, RadialGradient;

class FrameAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? activeFrame;
  final double radius;
  final VoidCallback? onTap;

  const FrameAvatar({
    Key? key,
    this.avatarUrl,
    this.activeFrame,
    this.radius = 24.0,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Basic CircleAvatar
    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade800,
      backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
          ? NetworkImage(avatarUrl!)
          : null,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Icon(Icons.person, color: Colors.white, size: radius)
          : null,
    );

    // If there is no frame, just return the standard avatar, padded by the default border size to maintain alignment sizes
    if (activeFrame == null || activeFrame!.isEmpty) {
      if (onTap != null) {
        return GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(radius * 0.15),
            child: avatar,
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.all(radius * 0.15),
        child: avatar,
      );
    }

    // Determine decoration based on the active frame code or URL
    BoxDecoration? frameDecoration;
    double paddingRatio = 0.15; // 15% of radius goes to frame thickness
    Widget? dynamicOverlay;

    if (activeFrame!.startsWith('http://') || activeFrame!.startsWith('https://')) {
      final lowerUrl = activeFrame!.toLowerCase();
      if (lowerUrl.endsWith('.json') || lowerUrl.endsWith('.lottie')) {
        dynamicOverlay = Lottie.network(
          activeFrame!,
          fit: BoxFit.cover,
        );
        paddingRatio = 0.08;
      } else if (lowerUrl.endsWith('.riv')) {
        dynamicOverlay = RiveAnimation.network(
          activeFrame!,
          fit: BoxFit.cover,
        );
        paddingRatio = 0.08;
      } else if (lowerUrl.endsWith('.png') || lowerUrl.endsWith('.gif') || lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg') || lowerUrl.endsWith('.webp')) {
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(activeFrame!),
            fit: BoxFit.cover,
          ),
        );
        paddingRatio = 0.15;
      } else {
        // Unknown URL format, fallback
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 2),
        );
        paddingRatio = 0.08;
      }
    } else {
      switch (activeFrame) {
      case 'frame_gold_champion':
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFDB931), Color(0xFF996515)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withAlpha(150),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        );
        paddingRatio = 0.12;
        break;
      case 'frame_neon_fire':
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF007F), // Neon Pink
              Color(0xFFFF4500), // Orange Red
              Color(0xFF8A2BE2), // Blue Violet
              Color(0xFFFF007F), // Neon Pink again to smooth connection
            ],
            stops: [0.0, 0.33, 0.66, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF007F).withAlpha(180),
              blurRadius: 15,
              spreadRadius: 3,
            ),
          ],
        );
        paddingRatio = 0.16;
        break;
      case 'frame_diamond_frozen':
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFE0FFFF), Color(0xFF00BFFF), Color(0xFF00008B)],
            radius: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00BFFF).withAlpha(120),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        );
        paddingRatio = 0.14;
        break;
        default:
          // Unknown frame, fallback to a simple distinct generic border
          frameDecoration = BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 2),
          );
          paddingRatio = 0.08;
      }
    }

    Widget framedAvatar = Container(
      padding: EdgeInsets.all(radius * paddingRatio),
      decoration: frameDecoration,
      child: avatar,
    );

    if (dynamicOverlay != null) {
      // Create a fixed size box so the overlay can fill it precisely
      final double totalSize = (radius * 2) + (radius * paddingRatio * 2);
      framedAvatar = SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            framedAvatar,
            // Multiply overlay size slightly if they have built-in margins, usually 1.2x scale fits well.
            Positioned(
              left: -radius * 0.2,
              top: -radius * 0.2,
              right: -radius * 0.2,
              bottom: -radius * 0.2,
              child: IgnorePointer(
                child: dynamicOverlay,
              ),
            ),
          ],
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: framedAvatar,
      );
    }

    return framedAvatar;
  }
}
