import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'match_detail_screen.dart';
import '../models/match.dart' as model;
import '../models/league.dart';
import '../models/notification.dart';
import '../widgets/league_group.dart';
import '../widgets/filter_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/sticky_header_delegate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/match_provider.dart';
import '../widgets/match_search_delegate.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/match_card.dart';
import '../providers/notification_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/knowledge_graph_provider.dart';
import '../widgets/notification_bell.dart';
import 'profile_screen.dart';

class HomeDashboard extends ConsumerStatefulWidget {
  final DateTime? initialDateOverride;

  const HomeDashboard({super.key, this.initialDateOverride});

  @override
  ConsumerState<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends ConsumerState<HomeDashboard> {
  int _selectedSportIndex = 0;
  final Set<String> _expandedLeagues = {};
  bool _hasInitializedExpansion = false;
  late final PageController _pageController;
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDateOverride != null) {
        ref
            .read(matchStateProvider.notifier)
            .setDate(widget.initialDateOverride!);
      }
    });

    // No default expansion on init; wait for live data.
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<Widget> _buildLeagueSlivers() {
    final matchState = ref.watch(matchStateProvider);

    if (matchState.isLoading) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Shimmer.fromColors(
              baseColor: context.colors.surfaceContainerLow,
              highlightColor: context.colors.surfaceContainer,
              child: Column(
                children:
                    List.generate(5, (index) => _buildSkeletonMatchCard()),
              ),
            ),
          ),
        )
      ];
    }

    final filtered = ref.watch(filteredMatchesProvider);
    if (filtered.isEmpty) {
      return [
        const EmptyState(message: "No matches available for this filter")
      ];
    }

    // We removed 'Senin İçin ✨' from here because it's now in Page 1 of the PageView
    // _buildPersonalizedFeed handles that view.

    // Flat Chronological Watchlist for Starred Filter
    if (matchState.isStarredFilter) {
      final starredList = List<model.Match>.from(filtered);
      starredList.sort((a, b) {
        if (a.status != b.status) {
          if (a.status == model.MatchStatus.live) return -1;
          if (b.status == model.MatchStatus.live) return 1;
          if (a.status == model.MatchStatus.upcoming) return -1;
          return 1;
        }
        return a.startTime.compareTo(b.startTime);
      });

      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final match = starredList[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: context.colors.surfaceContainerLow),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, top: 12, right: 12),
                                child: Row(children: [
                                  Image.network(
                                      match.leagueLogoUrl ??
                                          'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
                                      width: 14,
                                      height: 14,
                                      errorBuilder: (ctx, err, _) =>
                                          const Icon(Icons.shield, size: 14)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                        match.leagueName ?? 'Unknown League',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: context.colors.textLow,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ])),
                            MatchCard(match: match, hasBorder: false),
                          ])),
                );
              },
              childCount: starredList.length,
            ),
          ),
        )
      ];
    }

    final Map<String, List<model.Match>> leagueMap = {};
    for (var m in filtered) {
      if (m.isFeatured) {
        continue; // Skip displaying featured matches inside leagues
      }
      leagueMap.putIfAbsent(m.leagueId, () => []).add(m);
    }

    final List<League> sortedLeagues = [];
    for (var lId in leagueMap.keys) {
      // Dynamically create League model from live API matches data stream
      final representativeMatch = leagueMap[lId]!.first;
      sortedLeagues.add(League(
        id: lId,
        name: representativeMatch.leagueName ?? 'League $lId',
        logoUrl: representativeMatch.leagueLogoUrl ??
            'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
        tier: 3,
      ));
    }
    sortedLeagues.sort((a, b) => a.tier.compareTo(b.tier));

    if (!_hasInitializedExpansion &&
        sortedLeagues.isNotEmpty &&
        matchState.statusFilter == StatusFilter.all &&
        !matchState.isStarredFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _expandedLeagues.add(sortedLeagues.first.id);
            _hasInitializedExpansion = true;
          });
        }
      });
    }

    List<Widget> slivers = [];

    for (var league in sortedLeagues) {
      var matches = leagueMap[league.id]!;

      // Priority Match Sorting: Live > Upcoming > Finished
      matches.sort((a, b) {
        if (a.status != b.status) {
          if (a.status == model.MatchStatus.live) return -1;
          if (b.status == model.MatchStatus.live) return 1;
          if (a.status == model.MatchStatus.upcoming) return -1;
          return 1;
        }
        return a.startTime.compareTo(b.startTime);
      });

      slivers.add(LeagueGroup(
        league: league,
        matches: matches,
        isExpanded: matchState.statusFilter != StatusFilter.all || matchState.isStarredFilter ||
            _expandedLeagues.contains(league.id),
        onToggle: () {
          setState(() {
            if (_expandedLeagues.contains(league.id)) {
              _expandedLeagues.remove(league.id);
            } else {
              _expandedLeagues.add(league.id);
            }
          });
        },
      ));
    }

    if (slivers.isEmpty) {
      return [const EmptyState(message: "No non-featured matches available")];
    }
    return slivers;
  }

  model.Match? _getFeaturedMatch() {
    try {
      return ref
          .watch(matchStateProvider)
          .matches
          .firstWhere((m) => m.isFeatured);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<StatusFilter>(matchStateProvider.select((s) => s.statusFilter),
        (previous, next) {
      if (previous != next) {
        setState(() {
          _expandedLeagues.clear();
          final allMatches = ref.read(matchStateProvider).matches;
          if (next == StatusFilter.live) {
            _expandedLeagues.addAll(allMatches
                .where((m) => m.status == model.MatchStatus.live)
                .map((m) => m.leagueId));
          } else {
            if (allMatches.isNotEmpty) {
              _expandedLeagues.add(allMatches.first.leagueId);
            }
          }
        });
      }
    });

    ref.listen<bool>(matchStateProvider.select((s) => s.isStarredFilter),
        (previous, next) {
      if (previous != next && next) {
        setState(() {
          _expandedLeagues.clear();
          final allMatches = ref.read(matchStateProvider).matches;
          _expandedLeagues.addAll(
            allMatches.where((m) => m.isFavorite).map((m) => m.leagueId));
        });
      }
    });

    ref.listen<List<AppNotification>>(notificationProvider, (previous, next) {
      if (previous != null && next.length > previous.length) {
        final newNotifications =
            next.where((n) => !previous.any((p) => p.id == n.id)).toList();

        for (var n in newNotifications) {
          // Prevent historical notifications from flooding the screen on app startup
          // Only show SnackBars for genuinely recent events (last 2 minutes).
          final ageInMinutes = DateTime.now()
              .toUtc()
              .difference(n.createdAt.toUtc())
              .inMinutes
              .abs();
          if (ageInMinutes > 2) continue;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                      n.type == 'GOAL'
                          ? Icons.sports_soccer
                          : Icons.notifications_active,
                      color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(n.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text(n.message,
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: context.colors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });

    var featured = _getFeaturedMatch();
    final statusFilter = ref.watch(matchStateProvider).statusFilter;
    final isStarredFilter = ref.watch(matchStateProvider).isStarredFilter;

    return Scaffold(
      backgroundColor: context.colors.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(
                vertical: BorderSide(
                    color: context.colors.surfaceContainerLow, width: 2)),
          ),
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.deferToChild,
                onPointerDown: (_) {
                  if (ref.read(calendarOverlayProvider)) {
                    ref.read(calendarOverlayProvider.notifier).setState(false);
                  }
                },
                child: NestedScrollView(
                  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                      _buildAppBar(context),
                      _buildStickyContext(context),
                    ];
                  },
                  body: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      if (index == 1) {
                        ref.read(knowledgeGraphProvider.notifier).calculatePersonalizedFeed();
                      }
                    },
                    children: [
                      // Page 0: Main Feed
                      CustomScrollView(
                        slivers: [
                          if (featured != null &&
                              statusFilter == StatusFilter.all && !isStarredFilter)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 16.0),
                              sliver: SliverToBoxAdapter(
                                  child: _buildFeaturedMatchCard(featured)),
                            ),
                          ..._buildLeagueSlivers(),
                          const SliverToBoxAdapter(child: SizedBox(height: 120)),
                        ],
                      ),
                      // Page 1: Senin İçin ✨ Feed
                      _buildPersonalizedFeed(),
                    ],
                  ),
                ),
              ),
              _buildFloatingAudioRoom(),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI Components below (Top / Bottom app bars) ---

  Widget _buildPersonalizedFeed() {
    final personalizedList = ref.watch(personalizedMatchesProvider);
    
    if (personalizedList.isEmpty) {
      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState(message: "Sana özel öneriler oluşturuluyor... Bol bol maç incele!"),
            ),
          )
        ]
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: context.colors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text("Senin İçin", 
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.colors.textHigh,
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("İlgilendiğin maçlara göre yapay zeka tarafından senin için seçildi.", 
                  style: TextStyle(fontSize: 12, color: context.colors.textMedium)
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final match = personalizedList[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: context.colors.primary.withValues(alpha: 0.3)), // Special border for AI recs
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, top: 12, right: 12),
                                child: Row(children: [
                                  Image.network(
                                      match.leagueLogoUrl ??
                                          'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
                                      width: 14,
                                      height: 14,
                                      errorBuilder: (ctx, err, _) =>
                                          const Icon(Icons.shield, size: 14)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                        match.leagueName ?? 'Unknown League',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: context.colors.textLow,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  Icon(Icons.auto_awesome, size: 12, color: context.colors.primary),
                                  const SizedBox(width: 4),
                                  Text("Önerilen", style: TextStyle(
                                      fontSize: 10,
                                      color: context.colors.primary,
                                      fontWeight: FontWeight.bold)),
                                ])),
                            MatchCard(match: match, hasBorder: false),
                          ])),
                );
              },
              childCount: personalizedList.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      toolbarHeight: 64,
      collapsedHeight: 64,
      expandedHeight: 124, // 64 + 60 (bottom)
      backgroundColor: context.colors.background.withValues(alpha: 0.8),
      elevation: 0,
      centerTitle: false,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
            child: CircleAvatar(
              backgroundColor: context.colors.surfaceContainer,
              radius: 18,
              child:
                  Icon(Icons.person, color: context.colors.textMedium, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'KINETIC SCORES',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
            icon: Icon(Icons.search, color: context.colors.textMedium),
            onPressed: () {
              showSearch(
                context: context,
                delegate: MatchSearchDelegate(ref),
              );
            }),
        const NotificationBell(),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Column(
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                children: [
                  _buildSportChip(0, 'Football', Icons.sports_soccer),
                  _buildSportChip(1, 'Basketball', Icons.sports_basketball),
                  _buildSportChip(2, 'Tennis', Icons.sports_tennis),
                  _buildSportChip(3, 'E-Sports', Icons.sports_esports),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.surfaceContainerLow),
          ],
        ),
      ),
    );
  }

  Widget _buildSportChip(int index, String label, IconData icon) {
    final isSelected = _selectedSportIndex == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isSelected
                    ? context.colors.onPrimaryContainer
                    : context.colors.textMedium),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? context.colors.onPrimaryContainer
                      : context.colors.textMedium,
                )),
          ],
        ),
        selected: isSelected,
        onSelected: (val) {
          setState(() {
            _selectedSportIndex = index;
          });
        },
        backgroundColor: context.colors.surfaceContainerLow,
        selectedColor: context.colors.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  Widget _buildStickyContext(BuildContext context) {
    const dynamicHeight = 60.0;

    return SliverPersistentHeader(
      pinned: true,
      delegate: StickyHeaderDelegate(
        minHeight: dynamicHeight,
        maxHeight: dynamicHeight,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: context.colors.background.withValues(alpha: 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FilterRow(),
                  // Add a Page indicator dots
                  _buildPageIndicator(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonMatchCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      height: 80,
      decoration: BoxDecoration(
          color: Colors.white, // Color is overridden by Shimmer masks
          borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildFeaturedMatchCard(model.Match match) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.secondaryContainer.withValues(alpha: 0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.secondaryContainer
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: context.colors.secondaryContainer,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text("EL CLÁSICO • FEATURED",
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.secondaryContainer,
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                              child: _buildBentoTeam(
                                  match.homeTeam, match.homeLogo)),
                          Column(
                            children: [
                              Text("Starts at",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: context.colors.textLow)),
                              const SizedBox(height: 4),
                              Text(
                                  '${match.startTime.hour.toString().padLeft(2, '0')}:${match.startTime.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: context.colors.textHigh)),
                            ],
                          ),
                          Expanded(
                              child: _buildBentoTeam(
                                  match.awayTeam, match.awayLogo)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ]),
                      child: Icon(Icons.star,
                          color: context.colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: context.colors.surfaceContainer,
                          shape: BoxShape.circle),
                      child:
                          Icon(Icons.share, color: context.colors.textMedium),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoTeam(String name, String logourl) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Image.network(logourl,
              errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
        ),
        const SizedBox(height: 12),
        Text(name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
      ],
    );
  }

  Widget _buildFloatingAudioRoom() {
    return Positioned(
      bottom: 100,
      right: 24,
      child: GestureDetector(
        onTap: () {
          final allMatches = ref.read(matchStateProvider).matches;
          if (allMatches.isEmpty) return;
          final activeMatch = allMatches.firstWhere(
              (m) => m.status == model.MatchStatus.live,
              orElse: () => allMatches.first);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MatchDetailScreen(match: activeMatch)));
        },
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10)),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Color(0xFFEAB308), shape: BoxShape.circle),
                child:
                    const Icon(Icons.mic, color: Color(0xFF0F172A), size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("LIVE ROOM",
                      style: TextStyle(
                          color: Color(0xFFFACC15),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  Text("Match Reaction • 2.4k",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  _buildBar(12),
                  const SizedBox(width: 2),
                  _buildBar(8),
                  const SizedBox(width: 2),
                  _buildBar(10),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double page = 0.0;
        if (_pageController.position.haveDimensions) {
          page = _pageController.page ?? 0.0;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (index) {
              final isSelected = (page.round() == index);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                height: 6.0,
                width: isSelected ? 24.0 : 6.0,
                decoration: BoxDecoration(
                  color: isSelected ? context.colors.primary : context.colors.textLow.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3.0),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
