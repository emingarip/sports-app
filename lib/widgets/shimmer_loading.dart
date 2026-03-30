import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A widget that adds a shimmer animation effect to its child.
class ShimmerBase extends StatefulWidget {
  final Widget child;

  const ShimmerBase({super.key, required this.child});

  @override
  State<ShimmerBase> createState() => _ShimmerBaseState();
}

class _ShimmerBaseState extends State<ShimmerBase>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shimmerGradient = LinearGradient(
          colors: [
            context.colors.surfaceContainerLow,
            context.colors.surfaceContainerHighest,
            context.colors.surfaceContainerLow,
          ],
          stops: const [0.1, 0.5, 0.9],
          begin: Alignment(-1.0 - _controller.value * 2, -0.3),
          end: Alignment(1.0 + (_controller.value) * 2, 0.3),
          tileMode: TileMode.clamp,
        );
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return shimmerGradient.createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Generic container block used to build skeleton shapes
class ShimmerBlock extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Prebuilt Shimmer Layouts

class MatchCardShimmer extends StatelessWidget {
  const MatchCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerBase(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(26)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const ShimmerBlock(width: 40, height: 40, borderRadius: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: const [
                      ShimmerBlock(width: 80, height: 12),
                      SizedBox(height: 8),
                      ShimmerBlock(width: 60, height: 24),
                      SizedBox(height: 8),
                      ShimmerBlock(width: 100, height: 10),
                    ],
                  ),
                ),
              ),
              const ShimmerBlock(width: 40, height: 40, borderRadius: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class ListShimmer extends StatelessWidget {
  final int itemCount;
  const ListShimmer({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerBase(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBlock(width: 48, height: 48, borderRadius: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    const SizedBox(height: 4),
                    ShimmerBlock(width: double.infinity, height: 16),
                    SizedBox(height: 8),
                    ShimmerBlock(width: 100, height: 12),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileHeaderShimmer extends StatelessWidget {
  const ProfileHeaderShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShimmerBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 24),
          ShimmerBlock(width: 100, height: 100, borderRadius: 50),
          SizedBox(height: 16),
          ShimmerBlock(width: 150, height: 24),
          SizedBox(height: 8),
          ShimmerBlock(width: 80, height: 14),
          SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ShimmerBlock(width: 80, height: 60, borderRadius: 12),
              ShimmerBlock(width: 80, height: 60, borderRadius: 12),
              ShimmerBlock(width: 80, height: 60, borderRadius: 12),
            ],
          )
        ],
      ),
    );
  }
}
