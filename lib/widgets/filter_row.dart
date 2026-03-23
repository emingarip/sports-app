import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/match_provider.dart';

class FilterRow extends ConsumerWidget {
  const FilterRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchState = ref.watch(matchStateProvider);
    final statusFilter = matchState.statusFilter;
    final isStarred = matchState.isStarredFilter;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Group: Status Filters (Mutually Exclusive Toggle)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.colors.surfaceContainer),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusToggle(
                  context,
                  ref,
                  label: 'Canlı',
                  icon: Icons.fiber_manual_record,
                  iconColor: Colors.redAccent,
                  isActive: statusFilter == StatusFilter.live,
                  targetFilter: StatusFilter.live,
                ),
                const SizedBox(width: 4),
                _buildStatusToggle(
                  context,
                  ref,
                  label: 'Biten',
                  icon: Icons.check_circle,
                  iconColor: context.colors.textMedium,
                  isActive: statusFilter == StatusFilter.finished,
                  targetFilter: StatusFilter.finished,
                ),
              ],
            ),
          ),

          // Right Group: Utility Filter (Starred)
          GestureDetector(
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleStarred();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isStarred ? context.colors.primaryContainer : context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isStarred ? context.colors.primary : context.colors.surfaceContainer,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isStarred ? Icons.star : Icons.star_border, // Star outline when inactive
                    size: 16,
                    color: isStarred ? context.colors.onPrimaryContainer : context.colors.textMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Favoriler',
                    style: TextStyle(
                      color: isStarred ? context.colors.onPrimaryContainer : context.colors.textMedium,
                      fontWeight: isStarred ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusToggle(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool isActive,
    required StatusFilter targetFilter,
  }) {
    return GestureDetector(
      onTap: () {
        // Toggle behavior: if already active, clicking it sets it to ALL (off).
        final nextFilter = isActive ? StatusFilter.all : targetFilter;
        ref.read(matchStateProvider.notifier).setFilter(nextFilter);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? iconColor : iconColor.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? context.colors.onPrimaryContainer : context.colors.textMedium,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
