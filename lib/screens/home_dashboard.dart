import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/match.dart' as model;
import '../models/league.dart';
import '../data/mock_data.dart';
import '../widgets/league_group.dart';
import '../widgets/filter_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/sticky_header_delegate.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _selectedSportIndex = 0;
  int _selectedBottomNavIndex = 0;
  String _activeFilter = 'All';
  
  late List<model.Match> _allMatches;
  final Set<String> _expandedLeagues = {};

  @override
  void initState() {
    super.initState();
    _allMatches = MockData.getMatches();
    // Default expansion
    if (MockData.leagues.isNotEmpty) {
      _expandedLeagues.add(MockData.leagues.first.id);
    }
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _activeFilter = filter;
      _expandedLeagues.clear();
      
      // Smart Auto-expansion rules
      if (filter == 'Live 🔴') {
        final liveLeagues = _allMatches
            .where((m) => m.status == model.MatchStatus.live)
            .map((m) => m.leagueId);
        _expandedLeagues.addAll(liveLeagues);
      } else if (filter == 'Starred ⭐') {
        final favLeagues = _allMatches
            .where((m) => m.isFavorite)
            .map((m) => m.leagueId);
        _expandedLeagues.addAll(favLeagues);
      } else {
        // Default expansion
         if (MockData.leagues.isNotEmpty) {
           _expandedLeagues.add(MockData.leagues.first.id);
         }
      }
    });
  }

  List<model.Match> _getFilteredMatches() {
    return _allMatches.where((m) {
      if (_activeFilter == 'Live 🔴') return m.status == model.MatchStatus.live;
      if (_activeFilter == 'Starred ⭐') return m.isFavorite;
      if (_activeFilter == 'Finished') return m.status == model.MatchStatus.finished;
      return true; // All
    }).toList();
  }

  List<Widget> _buildLeagueSlivers() {
    final filtered = _getFilteredMatches();
    if (filtered.isEmpty) {
      return [const EmptyState(message: "No matches available for this filter")];
    }

    final Map<String, List<model.Match>> leagueMap = {};
    for (var m in filtered) {
       if (m.isFeatured) continue; // Skip displaying featured matches inside leagues
       leagueMap.putIfAbsent(m.leagueId, () => []).add(m);
    }
    
    // Sort leagues by Tier
    final sortedLeagues = MockData.leagues.where((l) => leagueMap.containsKey(l.id)).toList()
       ..sort((a, b) => a.tier.compareTo(b.tier));

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
      return _allMatches.firstWhere((m) => m.isFeatured);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    var featured = _getFeaturedMatch();

    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: const BoxDecoration(
            color: AppTheme.background,
            border: Border.symmetric(vertical: BorderSide(color: AppTheme.surfaceContainerLow, width: 2)),
          ),
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildAppBar(context),
                  _buildStickyContext(),
                  
                  if (featured != null && (_activeFilter == 'All' || _activeFilter == 'Starred ⭐'))
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
      floating: true,
      backgroundColor: Colors.white.withOpacity(0.8),
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
          const CircleAvatar(
            backgroundColor: AppTheme.surfaceContainer,
            radius: 18,
            backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
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
        IconButton(icon: const Icon(Icons.search, color: AppTheme.textMedium), onPressed: () {}),
        IconButton(icon: const Icon(Icons.notifications_outlined, color: AppTheme.textMedium), onPressed: () {}),
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
             const Divider(height: 1, color: AppTheme.surfaceContainerLow),
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
            Icon(icon, size: 18, color: isSelected ? AppTheme.textHigh : AppTheme.textMedium),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? AppTheme.textHigh : AppTheme.textMedium,
            )),
          ],
        ),
        selected: isSelected,
        onSelected: (val) {
          setState(() {
            _selectedSportIndex = index;
          });
        },
        backgroundColor: AppTheme.surfaceContainerLow,
        selectedColor: AppTheme.primaryContainer,
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
              color: AppTheme.background.withOpacity(0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDateNavigatorContent(),
                  FilterRow(activeFilter: _activeFilter, onFilterChanged: _onFilterChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateNavigatorContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0, left: 16, right: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppTheme.textMedium),
            onPressed: () {},
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildRefinedDateTab('SUN', '17', false),
                _buildRefinedDateTab('MON', '18', false),
                _buildRefinedDateTab('TODAY', 'TUE 19', true),
                _buildRefinedDateTab('WED', '20', false),
                _buildRefinedDateTab('THU', '21', false),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppTheme.textMedium),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildRefinedDateTab(String day, String num, bool isToday) {
    return Column(
      children: [
        if (!isToday) ...[
          Text(day, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLow)),
          const SizedBox(height: 2),
          Text(num, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textLow)),
        ],
        if (isToday)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                Text(day, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
                Text(num, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFeaturedMatchCard(model.Match match) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
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
                color: AppTheme.secondaryContainer.withOpacity(0.1),
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
                          color: AppTheme.secondaryContainer.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.secondaryContainer, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Text("EL CLÁSICO • FEATURED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.secondaryContainer, letterSpacing: 1)),
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
                              const Text("Starts at", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLow)),
                              const SizedBox(height: 4),
                              Text('${match.startTime.hour.toString().padLeft(2, '0')}:${match.startTime.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
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
                      decoration: const BoxDecoration(color: AppTheme.primaryContainer, shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                      ]),
                      child: const Icon(Icons.star, color: AppTheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: AppTheme.surfaceContainer, shape: BoxShape.circle),
                      child: const Icon(Icons.share, color: AppTheme.textMedium),
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
            color: AppTheme.surfaceContainerLow,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
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
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, "Matches", Icons.sports_soccer),
            _buildNavItem(1, "Predictions", Icons.query_stats),
            _buildNavItem(2, "Community", Icons.groups),
            _buildNavItem(3, "Profile", Icons.person),
          ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = _selectedBottomNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBottomNavIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFACC15) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? AppTheme.textHigh : AppTheme.textMedium, size: 20),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isSelected ? AppTheme.textHigh : AppTheme.textMedium,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
