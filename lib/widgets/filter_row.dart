import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/match_provider.dart';

class FilterRow extends ConsumerWidget {
  const FilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchState = ref.watch(matchStateProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStatusChip(
            context,
            label: 'Live',
            isActive: matchState.isLiveOnly,
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleLiveFilter();
            },
            leading: const _LiveDot(),
          ),
          const SizedBox(width: 10),
          _buildStatusChip(
            context,
            label: 'Finished',
            isActive: matchState.isFinishedOnly,
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleFinishedFilter();
            },
          ),
          const SizedBox(width: 10),
          _buildStarredToggle(
            context,
            isActive: matchState.starredOnly,
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleStarredFilter();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context, {
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? context.colors.primaryContainer
              : context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? context.colors.primary
                : context.colors.surfaceVariant.withValues(alpha: 0.7),
            width: isActive ? 1.6 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? context.colors.onPrimaryContainer
                    : context.colors.textMedium,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarredToggle(
    BuildContext context, {
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isActive
              ? context.colors.primaryContainer
              : context.colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? context.colors.primary
                : context.colors.surfaceVariant.withValues(alpha: 0.7),
            width: isActive ? 1.6 : 1.2,
          ),
        ),
        child: Icon(
          isActive ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 20,
          color: isActive
              ? context.colors.onPrimaryContainer
              : context.colors.textMedium,
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFFF4B3E),
        shape: BoxShape.circle,
      ),
    );
  }
}
