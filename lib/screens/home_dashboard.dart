import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/match_list_view_model.dart';
import '../models/notification.dart';
import '../models/user_profile.dart';
import '../providers/badge_provider.dart';
import '../providers/knowledge_graph_provider.dart';
import '../providers/match_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/voice_room_provider.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_row.dart';
import '../widgets/frame_avatar.dart';
import '../widgets/global_announcement_card.dart';
import '../widgets/inbox_message_button.dart';
import '../widgets/league_group.dart';
import '../widgets/match_card.dart';
import '../widgets/match_search_delegate.dart';
import '../widgets/notification_bell.dart';
import '../widgets/sticky_header_delegate.dart';
import 'profile_screen.dart';
import 'voice_room_screen.dart';

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

    try {
      _onlinePresenceChannel = Supabase.instance.client.channel('online_users');
      _onlinePresenceChannel?.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          final userId = Supabase.instance.client.auth.currentUser?.id ??
              'anonymous_${DateTime.now().millisecondsSinceEpoch}';
          await _onlinePresenceChannel?.track({
            'user_id': userId,
            'online_at': DateTime.now().toIso8601String(),
          });
        }
      });
    } catch (_) {
      // Ignored in widget tests when Supabase is unavailable.
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
      // Ignore in tests if Supabase is not initialized.
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('AppLinks init error: $e');
    }

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
      ref.read(voiceRoomProvider.notifier).joinRoom(
            roomName,
            isPrivate: pinCode != null,
            pinCode: pinCode,
            forceIsHost: false,
          );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VoiceRoomScreen()),
      );
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _onlinePresenceChannel?.unsubscribe();
    _pageController.dispose();
    super.dispose();
  }

  void _resetExpandedLeagues() {
    _expandedLeagues.clear();
    _hasInitializedExpansion = false;
  }

  Set<String> _defaultExpandedLeagueIds(List<LeagueMatchSection> sections) {
    final liveLeagueIds = sections
        .where((section) => section.hasLiveMatch)
        .map((section) => section.league.id)
        .toSet();
    if (liveLeagueIds.isNotEmpty) {
      return liveLeagueIds;
    }
    return {sections.first.league.id};
  }

  String _buildEmptyStateMessage(MatchState matchState) {
    if (matchState.inlineSearchQuery.trim().isNotEmpty) {
      return 'Aramana uygun mac bulunamadi';
    }
    if (matchState.isStarredFilter) {
      return 'Favori mac bulunamadi';
    }
    if (matchState.statusFilter == StatusFilter.live) {
      return 'Su anda canli mac yok';
    }
    if (matchState.statusFilter == StatusFilter.finished) {
      return 'Bu filtrede biten mac yok';
    }
    return 'Secili tarih icin mac bulunamadi';
  }

  void _openMatchSearch() {
    showSearch(
      context: context,
      delegate: MatchSearchDelegate(ref),
    );
  }

  List<Widget> _buildMainFeedSlivers() {
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
        ),
      ];
    }

    final matchItems = ref.watch(matchListItemsProvider);
    if (matchItems.isEmpty) {
      return [EmptyState(message: _buildEmptyStateMessage(matchState))];
    }

    final inlineSearchQuery = matchState.inlineSearchQuery.trim();
    if (inlineSearchQuery.isNotEmpty) {
      return [
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            title: 'Arama Sonuclari',
            subtitle:
                '"$inlineSearchQuery" icin ${matchItems.length} mac bulundu.',
          ),
        ),
        _buildCardListSliver(matchItems),
      ];
    }

    final featuredItems = ref.watch(featuredMatchItemsProvider);
    final liveNowSection = ref.watch(liveNowSectionProvider);
    final startingSoonSection = ref.watch(startingSoonSectionProvider);
    final otherMatchesSection = ref.watch(otherMatchesSectionProvider);
    final leagueSections = ref.watch(leagueMatchSectionsProvider);

    if (!_hasInitializedExpansion &&
        leagueSections.isNotEmpty &&
        matchState.statusFilter == StatusFilter.all &&
        !matchState.isStarredFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _expandedLeagues.addAll(_defaultExpandedLeagueIds(leagueSections));
          _hasInitializedExpansion = true;
        });
      });
    }

    final slivers = <Widget>[];

    if (featuredItems.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            title: 'One Cikanlar',
            subtitle: 'En hizli bulunmasi gereken maclar once burada.',
          ),
        ),
      );
      slivers.add(_buildCardListSliver(featuredItems));
    }

    if (liveNowSection != null) {
      slivers.addAll(
        _buildFlatSectionSlivers(
          liveNowSection,
          subtitle: 'Canli ve oncelikli karsilasmalar.',
        ),
      );
    }

    if (startingSoonSection != null) {
      slivers.addAll(
        _buildFlatSectionSlivers(
          startingSoonSection,
          subtitle: 'Iki saat icinde baslayacak maclar.',
        ),
      );
    }

    if (otherMatchesSection != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            title: otherMatchesSection.title,
            subtitle: 'Tum diger maclar lig bazinda gruplanir.',
          ),
        ),
      );

      if (leagueSections.isEmpty) {
        slivers.add(_buildCardListSliver(otherMatchesSection.items));
      }
    }

    for (final section in leagueSections) {
      slivers.add(
        LeagueGroup(
          league: section.league,
          items: section.items,
          isExpanded: matchState.statusFilter != StatusFilter.all ||
              matchState.isStarredFilter ||
              _expandedLeagues.contains(section.league.id),
          onToggle: () {
            setState(() {
              if (_expandedLeagues.contains(section.league.id)) {
                _expandedLeagues.remove(section.league.id);
              } else {
                _expandedLeagues.add(section.league.id);
              }
            });
          },
        ),
      );
    }

    if (slivers.isEmpty) {
      return [EmptyState(message: _buildEmptyStateMessage(matchState))];
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<StatusFilter>(matchStateProvider.select((s) => s.statusFilter),
        (previous, next) {
      if (previous != next) {
        setState(() {
          _resetExpandedLeagues();
        });
      }
    });

    ref.listen<bool>(matchStateProvider.select((s) => s.isStarredFilter),
        (previous, next) {
      if (previous != next) {
        setState(() {
          _resetExpandedLeagues();
        });
      }
    });

    ref.listen<DateTime>(
        matchStateProvider.select((state) => state.selectedDate),
        (previous, next) {
      if (previous != next) {
        setState(() {
          _resetExpandedLeagues();
        });
      }
    });

    ref.listen<List<AppNotification>>(notificationProvider, (previous, next) {
      if (previous != null && next.length > previous.length) {
        final newNotifications =
            next.where((n) => !previous.any((p) => p.id == n.id)).toList();

        for (final notification in newNotifications) {
          final ageInMinutes = DateTime.now()
              .toUtc()
              .difference(notification.createdAt.toUtc())
              .inMinutes
              .abs();
          if (ageInMinutes > 2) {
            continue;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    notification.type == 'GOAL'
                        ? Icons.sports_soccer
                        : Icons.notifications_active,
                    color: context.colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.colors.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          notification.message,
                          style: TextStyle(
                            color: context.colors.onPrimaryContainer
                                .withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: context.colors.primaryContainer,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });

    return Scaffold(
      backgroundColor: context.colors.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(
              vertical: BorderSide(
                color: context.colors.surfaceContainerLow,
                width: 2,
              ),
            ),
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
                      CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: 16.0),
                              child: GlobalAnnouncementList(),
                            ),
                          ),
                          ..._buildMainFeedSlivers(),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 120),
                          ),
                        ],
                      ),
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

  Widget _buildPersonalizedFeed() {
    final personalizedList = ref.watch(personalizedMatchesProvider);

    if (personalizedList.isEmpty) {
      return const CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: 40),
            sliver: EmptyState(
              message:
                  'Sana ozel oneriler olusturuluyor... Bol bol mac incele!',
            ),
          ),
        ],
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
                    Icon(
                      Icons.auto_awesome,
                      color: context.colors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Senin Icin',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: context.colors.textHigh,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ilgilendigin maclara gore yapay zeka tarafindan secildi.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textMedium,
                  ),
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
                        color: context.colors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            top: 12,
                            right: 12,
                          ),
                          child: Row(
                            children: [
                              Image.network(
                                match.leagueLogoUrl ??
                                    'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
                                width: 14,
                                height: 14,
                                errorBuilder: (ctx, err, _) =>
                                    const Icon(Icons.shield, size: 14),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  match.leagueName ?? 'Unknown League',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.colors.textLow,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.auto_awesome,
                                size: 12,
                                color: context.colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Onerilen',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        MatchCard(match: match, hasBorder: false),
                      ],
                    ),
                  ),
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
      expandedHeight: 124,
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
                    child: Icon(
                      Icons.person,
                      color: context.colors.textMedium,
                      size: 20,
                    ),
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
                "Velocity Score'a katil ve aninda K-Coin kazan! Davet linkim: sportsapp://invite?ref=$userId",
              );
              ref.read(badgeProvider.notifier).triggerEvent('invite_friend');
            }
          },
        ),
        IconButton(
          icon: Icon(Icons.search, color: context.colors.textMedium),
          onPressed: _openMatchSearch,
        ),
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
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? context.colors.onPrimaryContainer
                  : context.colors.textMedium,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? context.colors.onPrimaryContainer
                    : context.colors.textMedium,
              ),
            ),
          ],
        ),
        selected: isSelected,
        onSelected: (value) {
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
    const dynamicHeight = 88.0;

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  List<Widget> _buildFlatSectionSlivers(
    MatchSectionViewModel section, {
    String? subtitle,
  }) {
    if (section.items.isEmpty) {
      return const [];
    }

    return [
      SliverToBoxAdapter(
        child: _buildSectionHeader(
          title: section.title,
          subtitle: subtitle,
        ),
      ),
      _buildCardListSliver(section.items),
    ];
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.colors.textHigh,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardListSliver(List<MatchListItemViewModel> items) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.surfaceContainerLow),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: MatchCard(
                  match: item.match,
                  hasBorder: false,
                  reasonLabel: item.reasonLabel,
                  statusLabel: item.statusLabel,
                  secondaryLabel: item.secondaryLabel,
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double page = 0.0;
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          page = _pageController.page ?? 0.0;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (index) {
              final isSelected = page.round() == index;
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
