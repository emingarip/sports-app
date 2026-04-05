import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/match_provider.dart';
import '../theme/app_theme.dart';

class FilterRow extends ConsumerStatefulWidget {
  const FilterRow({super.key});

  @override
  ConsumerState<FilterRow> createState() => _FilterRowState();
}

class _FilterRowState extends ConsumerState<FilterRow> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    final matchState = ref.read(matchStateProvider);
    _searchController =
        TextEditingController(text: matchState.inlineSearchQuery);
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchState = ref.watch(matchStateProvider);
    final statusFilter = matchState.statusFilter;
    final isStarred = matchState.isStarredFilter;
    final isInlineSearchOpen = matchState.isInlineSearchOpen;
    final searchQuery = matchState.inlineSearchQuery;
    final trimmedQuery = searchQuery.trim();
    final resultCount = ref.watch(matchListItemsProvider).length;

    _syncSearchInput(matchState);

    if (isInlineSearchOpen) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.surfaceContainerLow),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: context.colors.textMedium,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        ref
                            .read(matchStateProvider.notifier)
                            .setInlineSearchQuery(value);
                      },
                      decoration: InputDecoration(
                        hintText: 'Bu listedeki maci ara',
                        hintStyle: TextStyle(
                          color: context.colors.textLow,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                      ),
                      style: TextStyle(
                        color: context.colors.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trimmedQuery.isNotEmpty)
                    IconButton(
                      tooltip: 'Aramayi temizle',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref
                            .read(matchStateProvider.notifier)
                            .clearInlineSearchQuery();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: context.colors.textMedium,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Aramayi kapat',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(matchStateProvider.notifier).closeInlineSearch();
                    },
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 22,
                      color: context.colors.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.format_list_bulleted_rounded,
                  size: 14,
                  color: context.colors.textMedium,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trimmedQuery.isEmpty
                        ? 'Takim ve lig isimlerine gore filtrele'
                        : '$resultCount mac bulundu',
                    style: TextStyle(
                      color: context.colors.textMedium,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

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
                  label: 'Canli',
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              ref.read(matchStateProvider.notifier).openInlineSearch();
            },
            child: Container(
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
                    Icons.search_rounded,
                    size: 16,
                    color: context.colors.textMedium,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Mac ara',
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
                    '$resultCount mac',
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

  void _syncSearchInput(MatchState matchState) {
    if (_searchController.text != matchState.inlineSearchQuery) {
      _searchController.value = TextEditingValue(
        text: matchState.inlineSearchQuery,
        selection: TextSelection.collapsed(
          offset: matchState.inlineSearchQuery.length,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (matchState.isInlineSearchOpen && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      } else if (!matchState.isInlineSearchOpen && _searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    });
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
