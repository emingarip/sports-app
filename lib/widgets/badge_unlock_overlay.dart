import 'dart:math';
import 'package:flutter/material.dart' hide Badge;
import '../theme/app_theme.dart';
import '../models/badge.dart';

/// A celebration overlay shown when a badge is unlocked.
/// Displays the badge icon with a confetti/shimmer effect and K-Coin reward.
class BadgeUnlockOverlay extends StatefulWidget {
  final Badge badge;
  final int tier;
  final VoidCallback? onDismiss;

  const BadgeUnlockOverlay({
    super.key,
    required this.badge,
    required this.tier,
    this.onDismiss,
  });

  /// Show the overlay as a dialog.
  static Future<void> show(BuildContext context, Badge badge, int tier) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Badge Unlock',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return BadgeUnlockOverlay(
          badge: badge,
          tier: tier,
          onDismiss: () => Navigator.of(context).pop(),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<BadgeUnlockOverlay> createState() => _BadgeUnlockOverlayState();
}

class _BadgeUnlockOverlayState extends State<BadgeUnlockOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final AnimationController _particleController;
  final List<_Particle> _particles = [];
  final _random = Random();

  @override
  void initState() {
    super.initState();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    // Generate confetti particles
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble() * 300 - 150,
        y: _random.nextDouble() * -400,
        speed: 1.0 + _random.nextDouble() * 2.0,
        size: 4.0 + _random.nextDouble() * 6.0,
        color: [
          const Color(0xFFFFD700),
          const Color(0xFFF44336),
          const Color(0xFF4CAF50),
          const Color(0xFF2196F3),
          const Color(0xFFFF9800),
          const Color(0xFF9C27B0),
        ][_random.nextInt(6)],
      ));
    }

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Color _tierColor(int tier) {
    switch (tier) {
      case 1:
        return const Color(0xFFCD7F32); // Bronze
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFFFD700); // Gold
      default:
        return Colors.grey;
    }
  }

  String _tierLabel(int tier) {
    switch (tier) {
      case 1:
        return 'BRONZ';
      case 2:
        return 'GÜMÜŞ';
      case 3:
        return 'ALTIN';
      default:
        return '';
    }
  }

  IconData _resolveIcon(String iconName) {
    const iconMap = <String, IconData>{
      'person_add': Icons.person_add,
      'verified': Icons.verified,
      'camera_alt': Icons.camera_alt,
      'visibility': Icons.visibility,
      'explore': Icons.explore,
      'casino': Icons.casino,
      'gps_fixed': Icons.gps_fixed,
      'local_fire_department': Icons.local_fire_department,
      'savings': Icons.savings,
      'shopping_cart': Icons.shopping_cart,
      'trending_up': Icons.trending_up,
      'emoji_events': Icons.emoji_events,
      'date_range': Icons.date_range,
      'loyalty': Icons.loyalty,
    };
    return iconMap[iconName] ?? Icons.military_tech;
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColor(widget.tier);
    final reward = widget.badge.kCoinReward * widget.tier;

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Confetti particles
                  ..._particles.map((p) {
                    final progress = _particleController.value;
                    return Positioned(
                      left: 150 + p.x * progress,
                      top: 200 + p.y * progress * p.speed,
                      child: Opacity(
                        opacity: (1 - progress).clamp(0.0, 1.0),
                        child: Transform.rotate(
                          angle: progress * pi * 4 * p.speed,
                          child: Container(
                            width: p.size,
                            height: p.size,
                            decoration: BoxDecoration(
                              color: p.color,
                              borderRadius: BorderRadius.circular(p.size / 4),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  // Main card
                  child!,
                ],
              );
            },
            child: Container(
              width: 300,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: tierColor.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: tierColor.withOpacity(0.3),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    '🎉 ROZET AÇILDI!',
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Badge icon with shimmer
                  AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, _) {
                      return Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            startAngle: 0,
                            endAngle: pi * 2,
                            transform: GradientRotation(_shimmerController.value * pi * 2),
                            colors: [
                              tierColor.withOpacity(0.1),
                              tierColor.withOpacity(0.4),
                              tierColor.withOpacity(0.1),
                            ],
                          ),
                          border: Border.all(color: tierColor, width: 3),
                        ),
                        child: Icon(
                          _resolveIcon(widget.badge.iconName),
                          size: 48,
                          color: tierColor,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Badge name
                  Text(
                    widget.badge.nameTr,
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Tier label
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: tierColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tierColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      _tierLabel(widget.tier),
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    widget.badge.descriptionTr,
                    style: TextStyle(
                      color: context.colors.textMedium,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // K-Coin reward
                  if (reward > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.monetization_on, color: context.colors.accent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '+$reward K-Coin',
                            style: TextStyle(
                              color: context.colors.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double x, y, speed, size;
  final Color color;
  _Particle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.color,
  });
}
