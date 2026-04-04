import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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
import '../models/user_profile.dart';
import '../widgets/frame_avatar.dart';
import '../services/supabase_service.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'voice_room_screen.dart';
import '../providers/voice_room_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/global_announcement_card.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/badge_provider.dart';
import '../widgets/inbox_message_button.dart';

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

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  RealtimeChannel? _onlinePresenceChannel;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(badgeProvider.notifier).recordLogin();
      if (widget.initialDateOverride != null) {
        ref
            .read(matchStateProvider.notifier)
            .setDate(widget.initialDateOverride!);
      }
    });

    _initDeepLinks();
    _fetchProfile();

    // Track global online user présence
    try {
      _onlinePresenceChannel = Supabase.instance.client.channel('online_users');
      _onlinePresenceChannel?.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          final userId = Supabase.instance.client.auth.currentUser?.id ??
              'anonymous_${DateTime.now().millisecondsSinceEpoch}';
          await _onlinePresenceChannel?.track({
            'user_id': userId,
            'online_at': DateTime.now().toIso8601String()
          });
        }
      });
    } catch (_) {
      // Ignored for widget tests environment
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final data = await SupabaseService().getUserProfile(user.id);
        if (data != null && mounted) {
          setState(() {
            _profile = UserProfile.fromJson(data);
          });
        }
      }
    } catch (_) {
      // Ignore in tests if Supabase is not initialized
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was cold-started
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint("AppLinks init error: $e");
    }

    // Listen to incoming links while app is open
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    String? roomName;
    String? pinCode;

    if (uri.scheme == 'sportsapp' && uri.host == 'room') {
      roomName = uri.queryParameters['name'];
      pinCode = uri.queryParameters['pin'];
    } else if (uri.queryParameters.containsKey('room')) {
      roomName = uri.queryParameters['room'];
      pinCode = uri.queryParameters['pin'];
    }

    if (roomName != null && mounted) {
      // Auto join the room utilizing the PIN from link
      ref.read(voiceRoomProvider.notifier).joinRoom(
            roomName,
            isPrivate: pinCode != null,
            pinCode: pinCode,
            forceIsHost: false,
          );
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const VoiceRoomScreen()));
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _onlinePresenceChannel?.unsubscribe();
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
        isExpanded: matchState.statusFilter != StatusFilter.all ||
            matchState.isStarredFilter ||
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
                      color: context.colors.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(n.title,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: context.colors.onPrimaryContainer)),
                        Text(n.message,
                            style: TextStyle(
                              color: context.colors.onPrimaryContainer
                                  .withValues(alpha: 0.78),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: context.colors.primaryContainer,
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
                  headerSliverBuilder:
                      (BuildContext context, bool innerBoxIsScrolled) {
                    return <Widget>[
                      _buildAppBar(context),
                      _buildStickyContext(context),
                    ];
                  },
                  body: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      if (index == 1) {
                        ref
                            .read(knowledgeGraphProvider.notifier)
                            .calculatePersonalizedFeed();
                      }
                    },
                    children: [
                      // Page 0: Main Feed
                      CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: 16.0),
                              child: GlobalAnnouncementList(),
                            ),
                          ),
                          if (featured != null &&
                              statusFilter == StatusFilter.all &&
                              !isStarredFilter)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 8.0),
                              sliver: SliverToBoxAdapter(
                                  child: _buildFeaturedMatchCard(featured)),
                            ),
                          ..._buildLeagueSlivers(),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 120)),
                        ],
                      ),
                      // Page 1: Senin İçin ✨ Feed
                      _buildPersonalizedFeed(),
                    ],
                  ),
                ),
              ),
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
      return const CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 40),
          sliver: EmptyState(
              message:
                  "Sana özel öneriler oluşturuluyor... Bol bol maç incele!"),
        )
      ]);
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
                    Icon(Icons.auto_awesome,
                        color: context.colors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text("Senin İçin",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: context.colors.textHigh,
                            )),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    "İlgilendiğin maçlara göre yapay zeka tarafından senin için seçildi.",
                    style: TextStyle(
                        fontSize: 12, color: context.colors.textMedium)),
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
                            color: context.colors.primary.withValues(
                                alpha: 0.3)), // Special border for AI recs
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
                                  Icon(Icons.auto_awesome,
                                      size: 12, color: context.colors.primary),
                                  const SizedBox(width: 4),
                                  Text("Önerilen",
                                      style: TextStyle(
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              _fetchProfile();
            },
            child: _profile != null
                ? FrameAvatar(
                    avatarUrl: _profile!.avatarUrl,
                    activeFrame: _profile!.activeFrame,
                    radius: 18,
                  )
                : CircleAvatar(
                    backgroundColor: context.colors.surfaceContainer,
                    radius: 18,
                    child: Icon(Icons.person,
                        color: context.colors.textMedium, size: 20),
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
          icon: Icon(Icons.card_giftcard, color: context.colors.primary),
          tooltip: 'Davet Et & Kazan',
          onPressed: () {
            final userId = Supabase.instance.client.auth.currentUser?.id;
            if (userId != null) {
              Share.share(
                  "Velocity Score'a katıl ve anında K-Coin kazan! Davet linkim: sportsapp://invite?ref=$userId");
              ref.read(badgeProvider.notifier).triggerEvent('invite_friend');
            }
          },
        ),
        IconButton(
            icon: Icon(Icons.search, color: context.colors.textMedium),
            onPressed: () {
              showSearch(
                context: context,
                delegate: MatchSearchDelegate(ref),
              );
            }),
        const InboxMessageButton(),
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
    const dynamicHeight = 76.0;

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
            color: context.colors.cardShadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
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
                          boxShadow: [
                            BoxShadow(
                              color:
                                  context.colors.cardShadow.withValues(alpha: 0.12),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
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
                  color: isSelected
                      ? context.colors.primary
                      : context.colors.textLow.withValues(alpha: 0.3),
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
