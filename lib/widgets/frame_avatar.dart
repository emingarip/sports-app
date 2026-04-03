import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' as rive;

class FrameAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String? activeFrame;
  final double radius;
  final VoidCallback? onTap;

  const FrameAvatar({
    super.key,
    this.avatarUrl,
    this.activeFrame,
    this.radius = 24.0,
    this.onTap,
  });

  @override
  State<FrameAvatar> createState() => _FrameAvatarState();
}

class _FrameAvatarState extends State<FrameAvatar> {
  rive.FileLoader? _riveLoader;

  @override
  void initState() {
    super.initState();
    _initLoaderIfNeeded();
  }

  @override
  void didUpdateWidget(FrameAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeFrame != widget.activeFrame) {
      _initLoaderIfNeeded();
    }
  }

  void _initLoaderIfNeeded() {
    _riveLoader?.dispose();
    _riveLoader = null;
    
    if (widget.activeFrame != null && widget.activeFrame!.toLowerCase().endsWith('.riv')) {
      _riveLoader = rive.FileLoader.fromUrl(
        widget.activeFrame!,
        riveFactory: rive.Factory.rive,
      );
    }
  }

  @override
  void dispose() {
    _riveLoader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Basic CircleAvatar
    Widget avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: Colors.grey.shade800,
      backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
          ? NetworkImage(widget.avatarUrl!)
          : null,
      child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
          ? Icon(Icons.person, color: Colors.white, size: widget.radius)
          : null,
    );

    // If there is no frame, just return the standard avatar, padded by the default border size to maintain alignment sizes
    if (widget.activeFrame == null || widget.activeFrame!.isEmpty) {
      if (widget.onTap != null) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: EdgeInsets.all(widget.radius * 0.15),
            child: avatar,
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.all(widget.radius * 0.15),
        child: avatar,
      );
    }

    // Determine decoration based on the active frame code or URL
    BoxDecoration? frameDecoration;
    double paddingRatio = 0.15; // 15% of radius goes to frame thickness
    Widget? dynamicOverlay;

    if (widget.activeFrame!.startsWith('http://') || widget.activeFrame!.startsWith('https://')) {
      final lowerUrl = widget.activeFrame!.toLowerCase();
      if (lowerUrl.endsWith('.json') || lowerUrl.endsWith('.lottie')) {
        dynamicOverlay = Lottie.network(
          widget.activeFrame!,
          fit: BoxFit.cover,
        );
        paddingRatio = 0.08;
      } else if (lowerUrl.endsWith('.riv')) {
        dynamicOverlay = _riveLoader != null ? rive.RiveWidgetBuilder(
          fileLoader: _riveLoader!,
          builder: (context, state) => switch (state) {
            rive.RiveLoading() => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            rive.RiveFailed() => const Center(child: Icon(Icons.error_outline, size: 16)),
            rive.RiveLoaded() => rive.RiveWidget(
              controller: state.controller,
              fit: rive.Fit.cover,
            )
          },
        ) : const SizedBox();
        paddingRatio = 0.08;
      } else if (lowerUrl.endsWith('.png') || lowerUrl.endsWith('.gif') || lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg') || lowerUrl.endsWith('.webp')) {
        frameDecoration = BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(widget.activeFrame!),
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
      switch (widget.activeFrame) {
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
      padding: EdgeInsets.all(widget.radius * paddingRatio),
      decoration: frameDecoration,
      child: avatar,
    );

    if (dynamicOverlay != null) {
      // Create a fixed size box so the overlay can fill it precisely
      final double totalSize = (widget.radius * 2) + (widget.radius * paddingRatio * 2);
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
              left: -widget.radius * 0.2,
              top: -widget.radius * 0.2,
              right: -widget.radius * 0.2,
              bottom: -widget.radius * 0.2,
              child: IgnorePointer(
                child: dynamicOverlay,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.onTap != null) {
      return GestureDetector(
        onTap: widget.onTap,
        child: framedAvatar,
      );
    }

    return framedAvatar;
  }
}
