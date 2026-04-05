import 'dart:async';
import 'dart:math' as math;

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
  late final ScrollController _controlsScrollController;
  Timer? _searchDebounce;
  bool _lastInlineSearchOpen = false;
  int? _lastResultCount;
  bool? _lastDetachedResultCount;
  bool _isLayoutRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    final matchState = ref.read(matchStateProvider);
    _searchController =
        TextEditingController(text: matchState.inlineSearchQuery);
    _controlsScrollController = ScrollController();
    _searchFocusNode = FocusNode()
      ..addListener(() {
        if (!_searchFocusNode.hasFocus &&
            ref.read(matchStateProvider).inlineSearchQuery.trim().isEmpty &&
            ref.read(matchStateProvider).isInlineSearchOpen) {
          _searchDebounce?.cancel();
          _searchController.clear();
          ref.read(matchStateProvider.notifier).closeInlineSearch();
        }
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _controlsScrollController.dispose();
    _searchDebounce?.cancel();
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
    _syncControlsPosition(isInlineSearchOpen);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _FilterRowLayout.resolve(
            availableWidth: constraints.maxWidth,
            resultCount: resultCount,
          );
          _syncInitialLayout(
            isInlineSearchOpen: isInlineSearchOpen,
            resultCount: resultCount,
            detachedResultCount: layout.detachedResultCount,
          );

          return Row(
            children: [
              Expanded(
                child: _buildControlsScroller(
                  context,
                  ref,
                  statusFilter: statusFilter,
                  isStarred: isStarred,
                  layout: layout,
                ),
              ),
              if (layout.detachedResultCount) ...[
                SizedBox(width: layout.controlGap),
                _buildResultCountChip(context, layout),
              ],
              SizedBox(width: layout.searchGap),
              _buildSearchContainer(
                context,
                ref,
                isInlineSearchOpen: isInlineSearchOpen,
                layout: layout,
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncSearchInput(MatchState matchState) {
    if (!_searchFocusNode.hasFocus &&
        _searchController.text != matchState.inlineSearchQuery) {
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

  void _syncInitialLayout({
    required bool isInlineSearchOpen,
    required int resultCount,
    required bool detachedResultCount,
  }) {
    final resultCountChanged = _lastResultCount != resultCount;
    final detachedModeChanged = _lastDetachedResultCount != detachedResultCount;

    _lastResultCount = resultCount;
    _lastDetachedResultCount = detachedResultCount;

    if (!(resultCountChanged || detachedModeChanged) || _isLayoutRefreshQueued) {
      return;
    }

    _isLayoutRefreshQueued = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isLayoutRefreshQueued = false;
      if (!mounted) {
        return;
      }

      if (_controlsScrollController.hasClients && !isInlineSearchOpen) {
        _controlsScrollController.jumpTo(
          _controlsScrollController.position.minScrollExtent,
        );
      }

      setState(() {});
    });
  }

  void _handleInlineSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      ref.read(matchStateProvider.notifier).setInlineSearchQuery(value);
    });
  }

  void _closeInlineSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(matchStateProvider.notifier).closeInlineSearch();
  }

  void _syncControlsPosition(bool isInlineSearchOpen) {
    if (_lastInlineSearchOpen == isInlineSearchOpen) {
      return;
    }

    _lastInlineSearchOpen = isInlineSearchOpen;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controlsScrollController.hasClients) {
        return;
      }

      _animateControlsToTarget(isInlineSearchOpen);

      if (isInlineSearchOpen) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted || !_controlsScrollController.hasClients) {
            return;
          }
          _animateControlsToTarget(true);
        });
      }
    });
  }

  void _animateControlsToTarget(bool isInlineSearchOpen) {
    final target = isInlineSearchOpen
        ? _controlsScrollController.position.maxScrollExtent
        : _controlsScrollController.position.minScrollExtent;

    _controlsScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildControlsScroller(
    BuildContext context,
    WidgetRef ref, {
    required StatusFilter statusFilter,
    required bool isStarred,
    required _FilterRowLayout layout,
  }) {
    return SingleChildScrollView(
      controller: _controlsScrollController,
      clipBehavior: Clip.hardEdge,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(layout.statusGroupPadding),
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
                  layout: layout,
                ),
                SizedBox(width: layout.statusItemGap),
                _buildStatusToggle(
                  context,
                  ref,
                  label: 'Biten',
                  icon: Icons.check_circle,
                  iconColor: context.colors.textMedium,
                  isActive: statusFilter == StatusFilter.finished,
                  targetFilter: StatusFilter.finished,
                  layout: layout,
                ),
              ],
            ),
          ),
          SizedBox(width: layout.controlGap),
          GestureDetector(
            onTap: () {
              ref.read(matchStateProvider.notifier).toggleStarred();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: layout.chipHorizontalPadding,
                vertical: layout.chipVerticalPadding,
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
                    size: layout.chipIconSize,
                    color: isStarred
                        ? context.colors.onPrimaryContainer
                        : context.colors.textMedium,
                  ),
                  SizedBox(width: layout.chipContentGap),
                  Text(
                    layout.favoritesLabel,
                    style: TextStyle(
                      color: isStarred
                          ? context.colors.onPrimaryContainer
                          : context.colors.textMedium,
                      fontWeight:
                          isStarred ? FontWeight.w600 : FontWeight.w500,
                      fontSize: layout.chipTextSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!layout.detachedResultCount) ...[
            SizedBox(width: layout.controlGap),
            _buildResultCountChip(context, layout),
          ],
          SizedBox(width: layout.trailingControlsInset),
        ],
      ),
    );
  }

  Widget _buildResultCountChip(
    BuildContext context,
    _FilterRowLayout layout,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: layout.chipHorizontalPadding,
        vertical: layout.chipVerticalPadding,
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
            size: layout.chipIconSize,
            color: context.colors.textMedium,
          ),
          SizedBox(width: layout.chipContentGap),
          Text(
            layout.resultCountLabel,
            style: TextStyle(
              color: context.colors.textMedium,
              fontWeight: FontWeight.w600,
              fontSize: layout.chipTextSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchContainer(
    BuildContext context,
    WidgetRef ref, {
    required bool isInlineSearchOpen,
    required _FilterRowLayout layout,
  }) {
    return AnimatedContainer(
      key: const ValueKey('inline-search-container'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: isInlineSearchOpen ? layout.openSearchWidth : layout.closedSearchWidth,
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
                  color: context.colors.cardShadow.withValues(alpha: 0.06),
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
                    ref.read(matchStateProvider.notifier).openInlineSearch();
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
            padding: EdgeInsets.symmetric(horizontal: layout.searchHorizontalPadding),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: layout.searchIconSize,
                  color: context.colors.primary,
                ),
                SizedBox(width: layout.searchContentGap),
                Expanded(
                  child: TextField(
                    key: const ValueKey('inline-search-field'),
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: _handleInlineSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Mac ara',
                      hintStyle: TextStyle(
                        color: context.colors.textLow,
                        fontSize: layout.searchHintTextSize,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontSize: layout.searchTextSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('inline-search-close'),
                  tooltip: 'Aramayi kapat',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _closeInlineSearch();
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    size: layout.searchIconSize,
                    color: context.colors.textMedium,
                  ),
                ),
              ],
            ),
          );
        },
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
    required _FilterRowLayout layout,
  }) {
    return GestureDetector(
      onTap: () {
        final nextFilter = isActive ? StatusFilter.all : targetFilter;
        ref.read(matchStateProvider.notifier).setFilter(nextFilter);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: layout.toggleHorizontalPadding,
          vertical: layout.toggleVerticalPadding,
        ),
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
              size: layout.toggleIconSize,
              color: isActive ? iconColor : iconColor.withValues(alpha: 0.6),
            ),
            SizedBox(width: layout.toggleContentGap),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? context.colors.onPrimaryContainer
                    : context.colors.textMedium,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: layout.toggleTextSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRowLayout {
  final double controlGap;
  final double searchGap;
  final double closedSearchWidth;
  final double openSearchWidth;
  final double statusGroupPadding;
  final double statusItemGap;
  final double toggleHorizontalPadding;
  final double toggleVerticalPadding;
  final double toggleContentGap;
  final double toggleIconSize;
  final double toggleTextSize;
  final double chipHorizontalPadding;
  final double chipVerticalPadding;
  final double chipContentGap;
  final double chipIconSize;
  final double chipTextSize;
  final double searchHorizontalPadding;
  final double searchContentGap;
  final double searchIconSize;
  final double searchTextSize;
  final double searchHintTextSize;
  final double trailingControlsInset;
  final bool detachedResultCount;
  final String favoritesLabel;
  final String resultCountLabel;

  const _FilterRowLayout({
    required this.controlGap,
    required this.searchGap,
    required this.closedSearchWidth,
    required this.openSearchWidth,
    required this.statusGroupPadding,
    required this.statusItemGap,
    required this.toggleHorizontalPadding,
    required this.toggleVerticalPadding,
    required this.toggleContentGap,
    required this.toggleIconSize,
    required this.toggleTextSize,
    required this.chipHorizontalPadding,
    required this.chipVerticalPadding,
    required this.chipContentGap,
    required this.chipIconSize,
    required this.chipTextSize,
    required this.searchHorizontalPadding,
    required this.searchContentGap,
    required this.searchIconSize,
    required this.searchTextSize,
    required this.searchHintTextSize,
    required this.trailingControlsInset,
    required this.detachedResultCount,
    required this.favoritesLabel,
    required this.resultCountLabel,
  });

  factory _FilterRowLayout.resolve({
    required double availableWidth,
    required int resultCount,
  }) {
    final isCompact = availableWidth < 390;
    final isUltraCompact = availableWidth < 350;

    if (isUltraCompact) {
      return _FilterRowLayout(
        controlGap: 5,
        searchGap: 10,
        closedSearchWidth: 36,
        openSearchWidth: math.min(164, availableWidth * 0.48),
        statusGroupPadding: 3,
        statusItemGap: 3,
        toggleHorizontalPadding: 9,
        toggleVerticalPadding: 8,
        toggleContentGap: 4,
        toggleIconSize: 12,
        toggleTextSize: 10.5,
        chipHorizontalPadding: 8,
        chipVerticalPadding: 8,
        chipContentGap: 4,
        chipIconSize: 13,
        chipTextSize: 10.5,
        searchHorizontalPadding: 9,
        searchContentGap: 7,
        searchIconSize: 16,
        searchTextSize: 12.5,
        searchHintTextSize: 11.5,
        trailingControlsInset: 0,
        detachedResultCount: true,
        favoritesLabel: 'Fav',
        resultCountLabel: '$resultCount',
      );
    }

    if (isCompact) {
      return _FilterRowLayout(
        controlGap: 5,
        searchGap: 12,
        closedSearchWidth: 38,
        openSearchWidth: math.min(180, availableWidth * 0.50),
        statusGroupPadding: 3,
        statusItemGap: 3,
        toggleHorizontalPadding: 10,
        toggleVerticalPadding: 8,
        toggleContentGap: 4,
        toggleIconSize: 12,
        toggleTextSize: 11,
        chipHorizontalPadding: 9,
        chipVerticalPadding: 8,
        chipContentGap: 4,
        chipIconSize: 14,
        chipTextSize: 11,
        searchHorizontalPadding: 10,
        searchContentGap: 8,
        searchIconSize: 17,
        searchTextSize: 13,
        searchHintTextSize: 12,
        trailingControlsInset: 0,
        detachedResultCount: true,
        favoritesLabel: 'Favoriler',
        resultCountLabel: '$resultCount',
      );
    }

    return _FilterRowLayout(
      controlGap: 8,
      searchGap: 8,
      closedSearchWidth: 44,
      openSearchWidth: 232,
      statusGroupPadding: 4,
      statusItemGap: 4,
      toggleHorizontalPadding: 14,
      toggleVerticalPadding: 8,
      toggleContentGap: 6,
      toggleIconSize: 14,
      toggleTextSize: 12,
      chipHorizontalPadding: 12,
      chipVerticalPadding: 8,
      chipContentGap: 6,
      chipIconSize: 16,
      chipTextSize: 12,
      searchHorizontalPadding: 12,
      searchContentGap: 10,
      searchIconSize: 18,
      searchTextSize: 14,
      searchHintTextSize: 13,
      trailingControlsInset: 4,
      detachedResultCount: false,
      favoritesLabel: 'Favoriler',
      resultCountLabel: '$resultCount mac',
    );
  }
}
