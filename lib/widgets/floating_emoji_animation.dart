import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/providers/voice_room_provider.dart';
import 'dart:math';

class FloatingEmojiAnimation extends ConsumerWidget {
  const FloatingEmojiAnimation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emojiReactions = ref.watch(voiceRoomProvider).emojiReactions;

    return Stack(
      children: emojiReactions.map((reaction) {
        return _FloatingEmoji(key: ValueKey(reaction.id), emoji: reaction.emoji);
      }).toList(),
    );
  }
}

class _FloatingEmoji extends StatefulWidget {
  final String emoji;

  const _FloatingEmoji({super.key, required this.emoji});

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;
  late Animation<double> _opacityAnimation;
  final double _randomXOffset = (Random().nextDouble() * 100) - 50;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _positionAnimation = Tween<double>(begin: 0, end: -300).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);

    _controller.forward();
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
        return Positioned(
          bottom: 150 + _positionAnimation.value.abs(),
          right: 30 + _randomXOffset,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Text(
              widget.emoji,
              style: const TextStyle(fontSize: 32),
            ),
          ),
        );
      },
    );
  }
}
