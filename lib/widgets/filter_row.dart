import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/match_provider.dart';
import '../theme/app_theme.dart';

class FilterRow extends ConsumerWidget {
  final VoidCallback? onSearch;

  const FilterRow({super.key, this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchState = ref.watch(matchStateProvider);
    final statusFilter = matchState.statusFilter;
    final isStarred = matchState.isStarredFilter;
    final resultCount = ref.watch(matchListItemsProvider).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleStarred();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isStarred
                    ? context.colors.primaryContainer
                    : context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isStarred
                      ? context.colors.primary
                      : context.colors.surfaceContainer,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isStarred ? Icons.star : Icons.star_border,
                    size: 16,
                    color: isStarred
                        ? context.colors.onPrimaryContainer
                        : context.colors.textMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Favoriler',
                    style: TextStyle(
                      color: isStarred
                          ? context.colors.onPrimaryContainer
                          : context.colors.textMedium,
                      fontWeight: isStarred ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onSearch != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSearch,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.colors.surfaceContainerLow),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: context.colors.textMedium,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Maç ara',
                      style: TextStyle(
                        color: context.colors.textMedium,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey('$statusFilter-$isStarred-$resultCount'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.colors.surfaceContainerLow),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 16,
                    color: context.colors.textMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$resultCount maç',
                    style: TextStyle(
                      color: context.colors.textMedium,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
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
        final nextFilter = isActive ? StatusFilter.all : targetFilter;
        ref.read(matchStateProvider.notifier).setFilter(nextFilter);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              isActive ? context.colors.primaryContainer : Colors.transparent,
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
                color: isActive
                    ? context.colors.onPrimaryContainer
                    : context.colors.textMedium,
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
