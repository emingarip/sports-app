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
  static const _closedSearchWidth = 44.0;
  static const _openSearchWidth = 232.0;

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    final matchState = ref.read(matchStateProvider);
    _searchController =
        TextEditingController(text: matchState.inlineSearchQuery);
    _searchFocusNode = FocusNode()
      ..addListener(() {
        if (!_searchFocusNode.hasFocus &&
            ref.read(matchStateProvider).inlineSearchQuery.trim().isEmpty &&
            ref.read(matchStateProvider).isInlineSearchOpen) {
          ref.read(matchStateProvider.notifier).closeInlineSearch();
        }
      });
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
    final resultCount = ref.watch(matchListItemsProvider).length;

    _syncSearchInput(matchState);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: context.colors.surfaceContainer),
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
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                              fontWeight:
                                  isStarred ? FontWeight.w600 : FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: isInlineSearchOpen
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: context.colors.surfaceContainerLow,
                              ),
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
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            key: const ValueKey('inline-search-container'),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            width: isInlineSearchOpen ? _openSearchWidth : _closedSearchWidth,
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isInlineSearchOpen
                    ? context.colors.primary.withValues(alpha: 0.28)
                    : context.colors.surfaceContainerLow,
              ),
              boxShadow: isInlineSearchOpen
                  ? [
                      BoxShadow(
                        color:
                            context.colors.cardShadow.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showExpandedSearch =
                    isInlineSearchOpen && constraints.maxWidth > 132;

                if (!showExpandedSearch) {
                  return Material(
                    key: const ValueKey('inline-search-closed'),
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('inline-search-toggle'),
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        if (!isInlineSearchOpen) {
                          ref
                              .read(matchStateProvider.notifier)
                              .openInlineSearch();
                        }
                      },
                      child: Center(
                        child: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: isInlineSearchOpen
                              ? context.colors.primary
                              : context.colors.textMedium,
                        ),
                      ),
                    ),
                  );
                }

                return Padding(
                  key: const ValueKey('inline-search-open'),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('inline-search-field'),
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            ref
                                .read(matchStateProvider.notifier)
                                .setInlineSearchQuery(value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Mac ara',
                            hintStyle: TextStyle(
                              color: context.colors.textLow,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: TextStyle(
                            color: context.colors.textHigh,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('inline-search-close'),
                        tooltip: 'Aramayi kapat',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ref
                              .read(matchStateProvider.notifier)
                              .closeInlineSearch();
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: context.colors.textMedium,
                        ),
                      ),
                    ],
                  ),
                );
              },
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
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
