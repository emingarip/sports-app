import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _selectedSportIndex = 0;
  int _selectedBottomNavIndex = 0;
  String _activeFilter = 'All';
  final Map<String, bool> _expandedLeagues = {
    'premier_league': true,
    'la_liga': true,
    'league_two': false,
  };

  @override
  Widget build(BuildContext context) {
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
              
              if (_activeFilter == 'All' || _activeFilter == 'Starred ⭐')
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                  sliver: SliverToBoxAdapter(child: _buildFeaturedMatchCard()),
                ),

              _buildLeagueGroup(
                id: 'premier_league',
                name: 'Premier League',
                logo: 'https://upload.wikimedia.org/wikipedia/en/thumb/f/f2/Premier_League_Logo.svg/1200px-Premier_League_Logo.svg.png',
                totalMatches: 8,
                matches: [
                  _buildMatchRow(
                    isLive: true,
                    statusTime: "75'",
                    homeTeam: "Arsenal",
                    homeScore: "2",
                    awayTeam: "Chelsea",
                    awayScore: "1",
                    homeLogo: "https://upload.wikimedia.org/wikipedia/en/thumb/5/53/Arsenal_FC.svg/1200px-Arsenal_FC.svg.png",
                    awayLogo: "https://upload.wikimedia.org/wikipedia/en/thumb/c/cc/Chelsea_FC.svg/1200px-Chelsea_FC.svg.png",
                    actionText: "PREDICT",
                    hasBorder: true,
                  ),
                ],
              ),

              _buildLeagueGroup(
                id: 'la_liga',
                name: 'La Liga',
                logo: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/LaLiga.svg/1200px-LaLiga.svg.png',
                totalMatches: 12,
                matches: [
                  _buildMatchRow(
                     isLive: false,
                     statusTime: "Full Time",
                     homeTeam: "R. Madrid",
                     homeScore: "3",
                     awayTeam: "Barcelona",
                     awayScore: "1",
                     homeLogo: "https://upload.wikimedia.org/wikipedia/en/thumb/5/56/Real_Madrid_CF.svg/1200px-Real_Madrid_CF.svg.png",
                     awayLogo: "https://upload.wikimedia.org/wikipedia/en/thumb/4/47/FC_Barcelona_%28crest%29.svg/1200px-FC_Barcelona_%28crest%29.svg.png",
                     actionText: "STATS",
                     hasBorder: false,
                  ),
                ],
              ),

              _buildLeagueGroup(
                id: 'league_two',
                name: 'English League Two',
                logo: 'https://upload.wikimedia.org/wikipedia/en/thumb/f/f2/Premier_League_Logo.svg/1200px-Premier_League_Logo.svg.png', 
                totalMatches: 24,
                matches: [
                  _buildMatchRow(
                    isLive: false,
                    statusTime: "Upcoming",
                    homeTeam: "Wrexham",
                    homeScore: "-",
                    awayTeam: "Notts Co",
                    awayScore: "-",
                    homeLogo: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/Wrexham_AFC_logo.svg/1200px-Wrexham_AFC_logo.svg.png",
                    awayLogo: "https://upload.wikimedia.org/wikipedia/en/thumb/e/e0/Notts_County_Logo.svg/1200px-Notts_County_Logo.svg.png",
                    actionText: "ODDS 2.10",
                    hasBorder: false,
                  ),
                ],
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          _buildFloatingAudioRoom(),
          _buildBottomNavBar(),
        ],
      ),
    )));
  }

  // --- Widgets ---
  
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
        IconButton(
          icon: const Icon(Icons.search, color: AppTheme.textMedium),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: AppTheme.textMedium),
          onPressed: () {},
        ),
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
      delegate: _StickyHeaderDelegate(
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
                  _buildQuickFilters(),
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

  Widget _buildQuickFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('All'),
          _buildFilterChip('Live 🔴'),
          _buildFilterChip('Starred ⭐'),
          _buildFilterChip('Finished'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _activeFilter = label;
            // Smart Filter Expansion Logic
            if (label == 'Live 🔴') {
              _expandedLeagues['premier_league'] = true; // Pretend it has a live match
              _expandedLeagues['league_two'] = false;
            } else if (label == 'Finished') {
              _expandedLeagues['la_liga'] = true;
              _expandedLeagues['premier_league'] = false;
            }
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceContainerHigh.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppTheme.surfaceContainerLowest : AppTheme.textHigh,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeagueGroup({
    required String id,
    required String name,
    required String logo,
    required List<Widget> matches,
    required int totalMatches,
  }) {
    bool isExpanded = _expandedLeagues[id] ?? false;

    // Filter hiding logic for UX Strategy Demonstration
    if (_activeFilter == 'Live 🔴' && id != 'premier_league') return const SliverToBoxAdapter(child: SizedBox());
    if (_activeFilter == 'Finished' && id == 'premier_league') return const SliverToBoxAdapter(child: SizedBox());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              minHeight: 48,
              maxHeight: 48,
              child: Container(
                color: AppTheme.background,
                alignment: Alignment.center,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _expandedLeagues[id] = !isExpanded;
                    });
                  },
                  child: Row(
                    children: [
                      Image.network(logo, width: 24, height: 24, errorBuilder: (ctx, err, _) => const Icon(Icons.shield, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textHigh), overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                           color: AppTheme.surfaceContainerLow,
                           borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text("$totalMatches Matches", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMedium)),
                      ),
                      const SizedBox(width: 8),
                      Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.textMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isExpanded)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.surfaceContainerLow),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: matches,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchRow({
    required bool isLive,
    required String statusTime,
    required String homeTeam,
    required String homeScore,
    required String awayTeam,
    required String awayScore,
    required String homeLogo,
    required String awayLogo,
    required String actionText,
    required bool hasBorder,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: hasBorder ? const Border(bottom: BorderSide(color: AppTheme.surfaceContainerLow)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Time/Status
          SizedBox(
            width: 48,
            child: Column(
              children: [
                if (isLive) const Text("LIVE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppTheme.error, letterSpacing: 1.5)),
                if (!isLive) Text(statusTime.replaceAll(" ", "\n"), textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.textLow, letterSpacing: 0.5, height: 1.1)),
                if (isLive) Text(statusTime, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.error)),
              ],
            ),
          ),
          
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Home
                Expanded(
                  child: Column(
                    children: [
                      Image.network(homeLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                      const SizedBox(height: 4),
                      Text(homeTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
                // Score
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FittedBox(
                    child: Row(
                      children: [
                        Text(homeScore, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isLive ? AppTheme.textHigh : AppTheme.textLow)),
                        const SizedBox(width: 8),
                        const Text("-", style: TextStyle(fontSize: 16, color: AppTheme.surfaceContainer)),
                        const SizedBox(width: 8),
                        Text(awayScore, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
                      ],
                    ),
                  ),
                ),
                // Away
                Expanded(
                  child: Column(
                    children: [
                      Image.network(awayLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                      const SizedBox(height: 4),
                      Text(awayTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Action button
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isLive ? Colors.transparent : AppTheme.surfaceContainerLow,
                  border: isLive ? Border.all(color: AppTheme.secondaryContainer) : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isLive ? AppTheme.secondary : AppTheme.textLow,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFeaturedMatchCard() {
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
          // Top right blob
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
                          Expanded(child: _buildBentoTeam("R. Madrid", "https://upload.wikimedia.org/wikipedia/en/thumb/5/56/Real_Madrid_CF.svg/1200px-Real_Madrid_CF.svg.png")),
                          Column(
                            children: const [
                              Text("Starts at", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLow)),
                              SizedBox(height: 4),
                              Text("21:00", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
                            ],
                          ),
                          Expanded(child: _buildBentoTeam("Barcelona", "https://upload.wikimedia.org/wikipedia/en/thumb/4/47/FC_Barcelona_%28crest%29.svg/1200px-FC_Barcelona_%28crest%29.svg.png")),
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
      bottom: 100, // Above bottom nav
      right: 24,
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A), // slate-900
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
              decoration: const BoxDecoration(
                color: Color(0xFFEAB308), // yellow-500
                shape: BoxShape.circle,
              ),
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
            // Fake animation bars
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
          color: isSelected ? const Color(0xFFFACC15) : Colors.transparent, // yellow-400
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

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double minHeight;
  final double maxHeight;

  _StickyHeaderDelegate({required this.child, required this.minHeight, required this.maxHeight});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
  }
}
