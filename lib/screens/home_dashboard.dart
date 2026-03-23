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
import '../widgets/custom_bottom_nav.dart';
import '../widgets/match_search_delegate.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/match_card.dart';
import '../providers/notification_provider.dart';
import '../widgets/notification_bell.dart';

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
  late final ScrollController _calendarScroller;

  @override
  void initState() {
    super.initState();
    _calendarScroller = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialDateOverride != null) {
        ref.read(matchStateProvider.notifier).setDate(widget.initialDateOverride!);
      }
      
      // Initial centering of the calendar on today (index 10000)
      if (_calendarScroller.hasClients) {
         final screenWidth = MediaQuery.of(context).size.width;
         final containerWidth = screenWidth > 600 ? 600.0 : screenWidth;
         final centerOffset = (10000 * 72.0) - (containerWidth / 2) + 36.0;
         _calendarScroller.jumpTo(centerOffset);
      }
    });

    // No default expansion on init; wait for live data.
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
                children: List.generate(5, (index) => _buildSkeletonMatchCard()),
              ),
            ),
          ),
        )
      ];
    }
    
    final filtered = ref.watch(filteredMatchesProvider);
    if (filtered.isEmpty) {
      return [const EmptyState(message: "No matches available for this filter")];
    }
    
    // Flat Chronological Watchlist for Starred Filter
    if (matchState.activeFilter == 'Starred ⭐') {
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
                        border: Border.all(color: context.colors.surfaceContainerLow),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
                            child: Row(
                              children: [
                                Image.network(match.leagueLogoUrl ?? 'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png', width: 14, height: 14, errorBuilder: (ctx, err, _) => const Icon(Icons.shield, size: 14)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(match.leagueName ?? 'Unknown League', style: TextStyle(fontSize: 10, color: context.colors.textLow, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ]
                            )
                          ),
                          MatchCard(match: match, hasBorder: false),
                        ]
                      )
                    ),
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
       if (m.isFeatured) continue; // Skip displaying featured matches inside leagues
       leagueMap.putIfAbsent(m.leagueId, () => []).add(m);
    }
    
    final List<League> sortedLeagues = [];
    for (var lId in leagueMap.keys) {
      // Dynamically create League model from live API matches data stream
      final representativeMatch = leagueMap[lId]!.first;
      sortedLeagues.add(League(
        id: lId,
        name: representativeMatch.leagueName ?? 'League $lId',
        logoUrl: representativeMatch.leagueLogoUrl ?? 'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
        tier: 3,
      ));
    }
    sortedLeagues.sort((a, b) => a.tier.compareTo(b.tier));

    if (!_hasInitializedExpansion && sortedLeagues.isNotEmpty && matchState.activeFilter == 'All') {
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
         isExpanded: matchState.activeFilter != 'All' || _expandedLeagues.contains(league.id),
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
      return ref.watch(matchStateProvider).matches.firstWhere((m) => m.isFeatured);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(matchStateProvider.select((s) => s.activeFilter), (previous, next) {
      if (previous != next) {
        setState(() {
          _expandedLeagues.clear();
          final allMatches = ref.read(matchStateProvider).matches;
          if (next == 'Live 🔴') {
            _expandedLeagues.addAll(allMatches.where((m) => m.status == model.MatchStatus.live).map((m) => m.leagueId));
          } else if (next == 'Starred ⭐') {
            _expandedLeagues.addAll(allMatches.where((m) => m.isFavorite).map((m) => m.leagueId));
          } else {
             if (allMatches.isNotEmpty) _expandedLeagues.add(allMatches.first.leagueId);
          }
        });
      }
    });

    ref.listen<List<AppNotification>>(notificationProvider, (previous, next) {
      if (previous != null && next.length > previous.length) {
        final newNotifications = next.where((n) => !previous.any((p) => p.id == n.id)).toList();
        
        for (var n in newNotifications) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(n.type == 'GOAL' ? Icons.sports_soccer : Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        Text(n.message, style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: context.colors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });

    var featured = _getFeaturedMatch();
    final activeFilter = ref.watch(matchStateProvider).activeFilter;

    return Scaffold(
      backgroundColor: context.colors.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(vertical: BorderSide(color: context.colors.surfaceContainerLow, width: 2)),
          ),
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildAppBar(context),
                  _buildStickyContext(context),
                  
                  if (featured != null && (activeFilter == 'All' || activeFilter == 'Starred ⭐'))
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                      sliver: SliverToBoxAdapter(child: _buildFeaturedMatchCard(featured)),
                    ),

                  ..._buildLeagueSlivers(),

                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
              _buildFloatingAudioRoom(),
              _buildBottomNavBar(),
            ],
          ),
        ),
      ),
    );
  }

  // --- UI Components below (Top / Bottom app bars) ---
  
  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      toolbarHeight: 64,
      collapsedHeight: 64,
      expandedHeight: 124, // 64 + 60 (bottom)
      backgroundColor: context.colors.background.withOpacity(0.8),
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
          CircleAvatar(
            backgroundColor: context.colors.surfaceContainer,
            radius: 18,
            child: Icon(Icons.person, color: context.colors.textMedium, size: 20),
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
          }
        ),
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
                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
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
            Icon(icon, size: 18, color: isSelected ? context.colors.onPrimaryContainer : context.colors.textMedium),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? context.colors.onPrimaryContainer : context.colors.textMedium,
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
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final dynamicHeight = 60.0 + (74.0 * textScale);
    
    return SliverPersistentHeader(
      pinned: true,
      delegate: StickyHeaderDelegate(
        minHeight: dynamicHeight,
        maxHeight: dynamicHeight,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: context.colors.background.withOpacity(0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDateNavigatorContent(context),
                  const FilterRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateNavigatorContent(BuildContext context) {
    final selectedDate = ref.watch(matchStateProvider).selectedDate;
    final now = DateTime.now();
    
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Stack(
         alignment: Alignment.center,
         children: [
           SizedBox(
            height: 25.0 + (45.0 * textScale), // Scales dynamically to prevent RenderFlex
            child: ListView.builder(
              controller: _calendarScroller,
              scrollDirection: Axis.horizontal,
              itemExtent: 72.0,
              itemCount: 20000,
              itemBuilder: (context, index) {
                 final int offsetFromToday = index - 10000;
                 final date = now.add(Duration(days: offsetFromToday));
                 
                 final isSelected = date.year == selectedDate.year &&
                                    date.month == selectedDate.month &&
                                    date.day == selectedDate.day;
                 
                 final isToday = date.year == now.year &&
                                 date.month == now.month &&
                                 date.day == now.day;

                 final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                 final weekdayStr = days[date.weekday - 1];
                 
                 String dayStr = isToday ? 'TODAY' : weekdayStr;
                 String numStr = isSelected ? '$weekdayStr ${date.day}' : '${date.day}';

                 return GestureDetector(
                   key: ValueKey('date_tab_$offsetFromToday'),
                   behavior: HitTestBehavior.opaque,
                   onTap: () {
                     HapticFeedback.lightImpact();
                     ref.read(matchStateProvider.notifier).setDate(date);
                     
                     // Smooth center
                     final screenWidth = MediaQuery.of(context).size.width;
                     final containerWidth = screenWidth > 600 ? 600.0 : screenWidth;
                     final targetOffset = (index * 72.0) - (containerWidth / 2) + 36.0;
                     _calendarScroller.animateTo(
                        targetOffset.clamp(0.0, _calendarScroller.position.maxScrollExtent), 
                        duration: const Duration(milliseconds: 300), 
                        curve: Curves.easeInOut
                     );
                   },
                   child: SizedBox(
                     width: 72,
                     child: _buildRefinedDateTab(dayStr, numStr, isSelected, isToday),
                   )
                 );
              },
            ),
          ),
          
          AnimatedBuilder(
            animation: _calendarScroller,
            builder: (context, child) {
              bool showSnapBtn = false;
              if (_calendarScroller.hasClients) {
                 final screenWidth = MediaQuery.of(context).size.width;
                 final containerWidth = screenWidth > 600 ? 600.0 : screenWidth;
                 final centerOffset = (10000 * 72.0) - (containerWidth / 2) + 36.0;
                 final currentOffset = _calendarScroller.offset;
                 
                 final differenceInPixels = (currentOffset - centerOffset).abs();
                 // Show button if scrolled 7 days (7 * 72.0 pixels) away
                 if (differenceInPixels >= (7 * 72.0)) {
                    showSnapBtn = true;
                 }
              }

              return Positioned(
                 right: 16,
                 child: IgnorePointer(
                   ignoring: !showSnapBtn,
                   child: AnimatedOpacity(
                     opacity: showSnapBtn ? 1.0 : 0.0, 
                     duration: const Duration(milliseconds: 300),
                     child: InkWell(
                        onTap: () {
                           HapticFeedback.selectionClick();
                           ref.read(matchStateProvider.notifier).setDate(now);
                           final screenWidth = MediaQuery.of(context).size.width;
                           final containerWidth = screenWidth > 600 ? 600.0 : screenWidth;
                           final targetOffset = (10000 * 72.0) - (containerWidth / 2) + 36.0;
                           _calendarScroller.animateTo(targetOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                           decoration: BoxDecoration(
                              color: context.colors.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]
                           ),
                           child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.today, size: 14, color: context.colors.onPrimaryContainer),
                                const SizedBox(width: 4),
                                Text("Bugün", style: TextStyle(color: context.colors.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12)),
                              ]
                           )
                        ),
                     )
                   ),
                 ),
              );
            }
          ),
         ]
      )
    );
  }

  Widget _buildRefinedDateTab(String day, String num, bool isSelected, [bool isToday = false]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: isSelected
          ? BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            )
          : const BoxDecoration(color: Colors.transparent),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              style: TextStyle(
                fontSize: isSelected ? 9 : 10,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                color: isSelected ? context.colors.onPrimaryContainer : context.colors.textLow,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              num,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isSelected ? context.colors.onPrimaryContainer : context.colors.textLow,
              ),
            ),
            if (isToday)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isSelected ? context.colors.onPrimaryContainer : context.colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
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
        borderRadius: BorderRadius.circular(16)
      ),
    );
  }

  Widget _buildFeaturedMatchCard(model.Match match) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 8)),
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
                color: context.colors.secondaryContainer.withOpacity(0.1),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.secondaryContainer.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: context.colors.secondaryContainer, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text("EL CLÁSICO • FEATURED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.colors.secondaryContainer, letterSpacing: 1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(child: _buildBentoTeam(match.homeTeam, match.homeLogo)),
                          Column(
                            children: [
                              Text("Starts at", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.textLow)),
                              const SizedBox(height: 4),
                              Text('${match.startTime.hour.toString().padLeft(2, '0')}:${match.startTime.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: context.colors.textHigh)),
                            ],
                          ),
                          Expanded(child: _buildBentoTeam(match.awayTeam, match.awayLogo)),
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
                      decoration: BoxDecoration(color: context.colors.primaryContainer, shape: BoxShape.circle, boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                      ]),
                      child: Icon(Icons.star, color: context.colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: context.colors.surfaceContainer, shape: BoxShape.circle),
                      child: Icon(Icons.share, color: context.colors.textMedium),
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
          child: Image.network(logourl, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
        ),
        const SizedBox(height: 12),
        Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
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
          final activeMatch = allMatches.firstWhere((m) => m.status == model.MatchStatus.live, orElse: () => allMatches.first);
          Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(match: activeMatch)));
        },
        child: Container(
          padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), 
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: Color(0xFFEAB308), shape: BoxShape.circle),
              child: const Icon(Icons.mic, color: Color(0xFF0F172A), size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("LIVE ROOM", style: TextStyle(color: Color(0xFFFACC15), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                Text("Match Reaction • 2.4k", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _buildBottomNavBar() {
    return const CustomBottomNav();
  }
}
