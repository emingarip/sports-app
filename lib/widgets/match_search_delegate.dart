import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../models/match.dart' as model;
import '../models/match_list_view_model.dart';
import '../providers/favorites_provider.dart';
import '../providers/match_provider.dart';
import '../screens/league_profile_screen.dart';
import '../screens/match_detail_screen.dart';
import '../screens/team_profile_screen.dart';
import '../theme/app_theme.dart';
import 'match_card.dart';

class MatchSearchDelegate extends SearchDelegate<model.Match?> {
  final WidgetRef ref;

  MatchSearchDelegate(this.ref)
      : super(
          searchFieldLabel: 'Takım veya lig ara...',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: context.colors.surfaceContainerLow,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.textMedium),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: context.colors.textMedium),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: context.colors.textHigh, fontSize: 18),
      ),
      scaffoldBackgroundColor: context.colors.background,
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) return [];
    return [
      IconButton(
        icon: Icon(Icons.clear, color: context.colors.textMedium),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back, color: context.colors.textMedium),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _DebouncedSearchDelegateWidget(
      query: query,
      ref: ref,
      delegate: this,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _DebouncedSearchDelegateWidget(
      query: query,
      ref: ref,
      delegate: this,
    );
  }
}

class _DebouncedSearchDelegateWidget extends ConsumerStatefulWidget {
  final String query;
  final WidgetRef ref;
  final MatchSearchDelegate delegate;

  const _DebouncedSearchDelegateWidget({
    required this.query,
    required this.ref,
    required this.delegate,
  });

  @override
  ConsumerState<_DebouncedSearchDelegateWidget> createState() =>
      _DebouncedSearchDelegateWidgetState();
}

class _DebouncedSearchDelegateWidgetState
    extends ConsumerState<_DebouncedSearchDelegateWidget> {
  Timer? _debounce;
  String _debouncedQuery = '';

  @override
  void initState() {
    super.initState();
    _debouncedQuery = widget.query;
    _scheduleDebounce();
  }

  @override
  void didUpdateWidget(covariant _DebouncedSearchDelegateWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) {
      _scheduleDebounce();
    }
  }

  void _scheduleDebounce() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _debouncedQuery != widget.query) {
        setState(() {
          _debouncedQuery = widget.query;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.white.withValues(alpha: 0.15),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  MatchListItemViewModel _buildSearchItem(model.Match match) {
    return buildMatchListItemViewModel(
      match,
      favorites: ref.read(favoritesProvider),
      now: DateTime.now(),
    );
  }

  Widget _buildList(List<SearchMatchResultViewModel> results) {
    if (results.isEmpty) {
      if (widget.query.trim().isEmpty) return const SizedBox.shrink();
      return Center(
        child: Text(
          'Sonuç bulunamadı: "${widget.query}"',
          style: TextStyle(color: context.colors.textMedium, fontSize: 16),
        ),
      );
    }

    final lowercaseQuery = widget.query.trim().toLowerCase();
    final matchedTeams = <String>{};
    final matchedLeagues = <String>{};

    for (final result in results) {
      final match = result.match;
      if (match.homeTeam.toLowerCase().contains(lowercaseQuery)) {
        matchedTeams.add(match.homeTeam);
      }
      if (match.awayTeam.toLowerCase().contains(lowercaseQuery)) {
        matchedTeams.add(match.awayTeam);
      }
      if ((match.leagueName ?? '').toLowerCase().contains(lowercaseQuery) &&
          match.leagueName != null) {
        matchedLeagues.add(match.leagueName!);
      }
    }

    final children = <Widget>[];

    if (matchedLeagues.isNotEmpty) {
      children.add(
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
          child: Text(
            'LİGLER',
            style: TextStyle(
              color: context.colors.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
      for (final league in matchedLeagues) {
        children.add(
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.emoji_events,
                color: context.colors.primary,
                size: 20,
              ),
            ),
            title: Text(
              league,
              style: TextStyle(
                color: context.colors.textHigh,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing:
                Icon(Icons.chevron_right, color: context.colors.textMedium),
            onTap: () {
              widget.delegate.close(context, null);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeagueProfileScreen(leagueName: league),
                ),
              );
            },
          ),
        );
      }
    }

    if (matchedTeams.isNotEmpty) {
      children.add(
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
          child: Text(
            'TAKIMLAR',
            style: TextStyle(
              color: context.colors.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
      for (final team in matchedTeams) {
        children.add(
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.shield, color: context.colors.primary, size: 20),
            ),
            title: Text(
              team,
              style: TextStyle(
                color: context.colors.textHigh,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing:
                Icon(Icons.chevron_right, color: context.colors.textMedium),
            onTap: () {
              widget.delegate.close(context, null);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeamProfileScreen(teamName: team),
                ),
              );
            },
          ),
        );
      }
    }

    children.add(
      Padding(
        padding:
            const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 12),
        child: Text(
          'MAÇLAR',
          style: TextStyle(
            color: context.colors.textMedium,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );

    for (final result in results) {
      final item = _buildSearchItem(result.match);
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: GestureDetector(
            onTap: () {
              widget.delegate.close(context, result.match);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchDetailScreen(match: result.match),
                ),
              );
            },
            child: MatchCard(
              match: result.match,
              hasBorder: true,
              reasonLabel: item.reasonLabel,
              statusLabel: item.statusLabel,
              secondaryLabel: item.secondaryLabel,
            ),
          ),
        ),
      );
    }

    children.add(const SizedBox(height: 24));
    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = widget.query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search,
                size: 64, color: context.colors.surfaceContainer),
            const SizedBox(height: 16),
            Text(
              'Takım veya lig ismine göre arayın',
              style: TextStyle(color: context.colors.textMedium, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final allMatches = ref.read(matchStateProvider).matches;
    final localResults = rankMatchSearchResults(
      matches: allMatches,
      query: widget.query,
    );

    if (_debouncedQuery != widget.query) {
      return _buildList(localResults);
    }

    final repository = ref.read(matchRepositoryProvider);
    return FutureBuilder<List<model.Match>>(
      future: repository.searchMatches(widget.query.trim()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (localResults.isNotEmpty) {
            return _buildList(localResults);
          }
          return _buildSkeleton();
        }

        if (snapshot.hasError) {
          return _buildList(localResults);
        }

        final backendResults = rankMatchSearchResults(
          matches: snapshot.data ?? const [],
          query: widget.query,
        );
        final mergedResults = mergeRankedSearchResults(
          localResults,
          backendResults,
        );

        return _buildList(mergedResults);
      },
    );
  }
}
