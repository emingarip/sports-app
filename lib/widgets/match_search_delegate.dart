import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../models/match.dart' as model;
import '../providers/match_provider.dart';
import '../theme/app_theme.dart';
import 'match_card.dart';
import '../screens/match_detail_screen.dart';
import '../screens/team_profile_screen.dart';
import '../screens/league_profile_screen.dart';

class MatchSearchDelegate extends SearchDelegate<model.Match?> {
  final WidgetRef ref;

  MatchSearchDelegate(this.ref) : super(
    searchFieldLabel: 'Takım veya Lig ara...',
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
  ConsumerState<_DebouncedSearchDelegateWidget> createState() => _DebouncedSearchDelegateWidgetState();
}

class _DebouncedSearchDelegateWidgetState extends ConsumerState<_DebouncedSearchDelegateWidget> {
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
      itemCount: 5, // Show 5 skeletons
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.white.withValues(alpha: 0.15),
          child: Container(
            height: 120, // MatchCard height
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(List<model.Match> matches) {
    if (matches.isEmpty) {
      if (widget.query.trim().isEmpty) return const SizedBox.shrink();
      return Center(
        child: Text(
          "Sonuç bulunamadı: \"${widget.query}\"",
          style: TextStyle(color: context.colors.textMedium, fontSize: 16),
        ),
      );
    }

    final lowercaseQuery = widget.query.trim().toLowerCase();
    final Set<String> matchedTeams = {};
    final Set<String> matchedLeagues = {};

    if (lowercaseQuery.isNotEmpty) {
      for (var m in matches) {
        if (m.homeTeam.toLowerCase().contains(lowercaseQuery)) {
          matchedTeams.add(m.homeTeam);
        }
        if (m.awayTeam.toLowerCase().contains(lowercaseQuery)) {
          matchedTeams.add(m.awayTeam);
        }
        if ((m.leagueName ?? '').toLowerCase().contains(lowercaseQuery)) {
          matchedLeagues.add(m.leagueName!);
        }
      }
    }

    final List<Widget> children = [];

    // Leagues Section
    if (matchedLeagues.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
          child: Text("LİGLER", style: TextStyle(color: context.colors.textMedium, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        )
      );
      for (var league in matchedLeagues) {
        children.add(
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: context.colors.surfaceContainer, shape: BoxShape.circle),
              child: Icon(Icons.emoji_events, color: context.colors.primary, size: 20),
            ),
            title: Text(league, style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMedium),
            onTap: () {
               widget.delegate.close(context, null);
               Navigator.push(context, MaterialPageRoute(builder: (c) => LeagueProfileScreen(leagueName: league)));
            },
          )
        );
      }
    }

    // Teams Section
    if (matchedTeams.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
          child: Text("TAKIMLAR", style: TextStyle(color: context.colors.textMedium, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        )
      );
      for (var team in matchedTeams) {
        children.add(
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: context.colors.surfaceContainer, shape: BoxShape.circle),
              child: Icon(Icons.shield, color: context.colors.primary, size: 20),
            ),
            title: Text(team, style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMedium),
            onTap: () {
               widget.delegate.close(context, null);
               Navigator.push(context, MaterialPageRoute(builder: (c) => TeamProfileScreen(teamName: team)));
            },
          )
        );
      }
    }

    // Matches Section
    children.add(
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 12),
        child: Text("MAÇLAR", style: TextStyle(color: context.colors.textMedium, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      )
    );

    for (var match in matches) {
      children.add(
        Padding(
           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
           child: GestureDetector(
             onTap: () {
               widget.delegate.close(context, match);
               Navigator.push(context, MaterialPageRoute(builder: (c) => MatchDetailScreen(match: match)));
             },
             child: MatchCard(
               match: match,
               hasBorder: true,
             ),
           ),
        )
      );
    }
    
    // Bottom padding
    children.add(const SizedBox(height: 24));

    return ListView(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final lowercaseQuery = widget.query.trim().toLowerCase();

    // If query is empty, show default hint
    if (lowercaseQuery.isEmpty) {
       return Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Icon(Icons.search, size: 64, color: context.colors.surfaceContainer),
             const SizedBox(height: 16),
             Text(
               "Takım veya lig ismine göre arayın", 
               style: TextStyle(color: context.colors.textMedium, fontSize: 16)
             ),
           ],
         ),
       );
    }

    // Always fetch local results instantly for zero-latency UX
    final allMatches = ref.read(matchStateProvider).matches;
    final localResults = allMatches.where((match) {
      final matchStr = '${match.homeTeam} ${match.awayTeam} ${match.leagueName}'.toLowerCase();
      return matchStr.contains(lowercaseQuery);
    }).toList();

    // If debouncer is hunting down the SAME query we are typing, wait for backend. 
    // If the input is fresh (still typing), we just return local results immediately!
    if (_debouncedQuery != widget.query) {
      return _buildList(localResults);
    }

    // Debounce timer elapsed! We now hit the backend.
    final repository = ref.read(matchRepositoryProvider);
    return FutureBuilder<List<model.Match>>(
      future: repository.searchMatches(widget.query.trim()),
      builder: (context, snapshot) {
         if (snapshot.connectionState == ConnectionState.waiting) {
            // While backend is fetching, STILL show local results if we have them, 
            // OR show skeleton if we have literally nothing locally.
            if (localResults.isNotEmpty) {
               return _buildList(localResults); 
            }
            return _buildSkeleton();
         }

         if (snapshot.hasError) {
             // Fallback to local on error
             return _buildList(localResults);
         }

         // Merge backend results with local results to ensure no dupes
         final backendResults = snapshot.data ?? [];
         final Set<String> seenIds = {};
         final List<model.Match> finalResults = [];

         for (var m in localResults) {
            finalResults.add(m);
            seenIds.add(m.id);
         }
         for (var m in backendResults) {
            if (!seenIds.contains(m.id)) {
               finalResults.add(m);
               seenIds.add(m.id);
            }
         }

         return _buildList(finalResults);
      }
    );
  }
}
