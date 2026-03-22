import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'match_room_screen.dart';
import '../models/match.dart' as model;
import '../models/league.dart';
import '../data/mock_data.dart';
import '../widgets/league_group.dart';
import '../widgets/filter_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/sticky_header_delegate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/match_provider.dart';
import '../widgets/custom_bottom_nav.dart';


class HomeDashboard extends ConsumerStatefulWidget {
  const HomeDashboard({super.key});

  @override
  ConsumerState<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends ConsumerState<HomeDashboard> {
  int _selectedSportIndex = 0;
  final Set<String> _expandedLeagues = {};
  late DateTime _calendarBaseDate;

  @override
  void initState() {
    super.initState();
    _calendarBaseDate = DateTime.now();
    if (MockData.leagues.isNotEmpty) {
      _expandedLeagues.add(MockData.leagues.first.id);
    }
  }

  List<Widget> _buildLeagueSlivers() {
    final filtered = ref.watch(matchStateProvider).filteredMatches;
    if (filtered.isEmpty) {
      return [const EmptyState(message: "No matches available for this filter")];
    }

    final Map<String, List<model.Match>> leagueMap = {};
    for (var m in filtered) {
       if (m.isFeatured) continue; // Skip displaying featured matches inside leagues
       leagueMap.putIfAbsent(m.leagueId, () => []).add(m);
    }
    
    final List<League> sortedLeagues = [];
    for (var lId in leagueMap.keys) {
      final found = MockData.leagues.where((l) => l.id == lId).toList();
      if (found.isNotEmpty) {
        sortedLeagues.add(found.first);
      } else {
        // Fallback to dynamic creation from live API matches data stream
        final representativeMatch = leagueMap[lId]!.first;
        sortedLeagues.add(League(
          id: lId,
          name: representativeMatch.leagueName ?? 'League $lId',
          logoUrl: representativeMatch.leagueLogoUrl ?? 'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
          tier: 3,
        ));
      }
    }
    sortedLeagues.sort((a, b) => a.tier.compareTo(b.tier));

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
         isExpanded: _expandedLeagues.contains(league.id),
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
             if (MockData.leagues.isNotEmpty) _expandedLeagues.add(MockData.leagues.first.id);
          }
        });
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
                  _buildStickyContext(),
                  
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
        IconButton(icon: Icon(Icons.search, color: context.colors.textMedium), onPressed: () {}),
        IconButton(icon: Icon(Icons.notifications_outlined, color: context.colors.textMedium), onPressed: () {}),
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

  Widget _buildStickyContext() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: StickyHeaderDelegate(
        minHeight: 124,
        maxHeight: 124,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: context.colors.background.withOpacity(0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDateNavigatorContent(),
                  const FilterRow(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateNavigatorContent() {
    final selectedDate = ref.watch(matchStateProvider).selectedDate;
    
    // Generate 5 days centered around _calendarBaseDate
    List<DateTime> visibleDates = List.generate(5, (index) {
      return _calendarBaseDate.add(Duration(days: index - 2));
    });

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: context.colors.textMedium),
            onPressed: () {
              setState(() {
                _calendarBaseDate = _calendarBaseDate.subtract(const Duration(days: 1));
              });
            },
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: visibleDates.map((date) {
                final isSelected = date.year == selectedDate.year &&
                                   date.month == selectedDate.month &&
                                   date.day == selectedDate.day;
                
                final now = DateTime.now();
                final isToday = date.year == now.year &&
                                date.month == now.month &&
                                date.day == now.day;

                final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
                final weekdayStr = days[date.weekday - 1];
                
                String dayStr = isToday ? 'TODAY' : weekdayStr;
                String numStr = isSelected ? '$weekdayStr ${date.day}' : '${date.day}';

                return GestureDetector(
                  onTap: () {
                    ref.read(matchStateProvider.notifier).setDate(date);
                  },
                  child: _buildRefinedDateTab(dayStr, numStr, isSelected),
                );
              }).toList(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: context.colors.textMedium),
            onPressed: () {
              setState(() {
                _calendarBaseDate = _calendarBaseDate.add(const Duration(days: 1));
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRefinedDateTab(String day, String num, bool isSelected) {
    return Column(
      children: [
        if (!isSelected) ...[
          Text(day, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.colors.textLow)),
          const SizedBox(height: 2),
          Text(num, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: context.colors.textLow)),
        ],
        if (isSelected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                Text(day, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: context.colors.onPrimaryContainer)),
                Text(num, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: context.colors.onPrimaryContainer)),
              ],
            ),
          ),
      ],
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
          Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(match: activeMatch)));
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
