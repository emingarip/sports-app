import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/bankroll_provider.dart';
import '../../screens/responsible_play_screen.dart';
import '../../theme/app_theme.dart';

/// Shows while responsible-play cooling mode is active.
///
/// The cooling state was already persisted and already blocked coupon sharing,
/// but it was only visible on the two screens that owned it. Someone who set a
/// cooling period and then opened the bulletin saw no sign of it at all -
/// exactly the moment the reminder is worth something. Renders nothing when
/// cooling is off, so it is safe to place on any screen.
class CoolingModeBanner extends ConsumerWidget {
  const CoolingModeBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coolingUntil = ref.watch(coolingModeProvider).value;
    if (coolingUntil == null || !coolingUntil.isAfter(DateTime.now())) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final local = coolingUntil.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResponsiblePlayScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.pause_circle_outline, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Soğuma modu açık — ${two(local.day)}.${two(local.month)} '
                    '${two(local.hour)}:${two(local.minute)} tarihine kadar '
                    'kupon paylaşımı kapalı.',
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: colors.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
