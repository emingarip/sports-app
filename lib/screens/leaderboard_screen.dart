import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/leaderboard_provider.dart';
import '../widgets/frame_avatar.dart';
import '../widgets/shimmer_loading.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  @override
  Widget build(BuildContext context) {
    final leaderboardState = ref.watch(leaderboardProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'GLOBAL RANKING',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.colors.textMedium),
            onPressed: () {
              ref.read(leaderboardProvider.notifier).refresh();
            },
          )
        ],
      ),
      body: leaderboardState.when(
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Text(
                'No ranking data found.',
                style: TextStyle(color: context.colors.textMedium),
              ),
            );
          }
          return RefreshIndicator(
            color: context.colors.accent,
            backgroundColor: context.colors.surface,
            onRefresh: () async {
              await ref.read(leaderboardProvider.notifier).refresh();
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildPodium(context, users),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        // Offset by 3 since top 3 are in the podium
                        final actualIndex = index + 3;
                        if (actualIndex >= users.length) return null;
                        return _buildListItem(context, users[actualIndex], actualIndex + 1);
                      },
                      childCount: users.length > 3 ? users.length - 3 : 0,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)), // Padding for bottom nav
              ],
            ),
          );
        },
        loading: () => const ListShimmer(itemCount: 7),
        error: (err, stack) => Center(
          child: Text(
            'Could not load leaderboard.\n$err',
            style: TextStyle(color: context.colors.error),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildPodium(BuildContext context, List<LeaderboardUser> users) {
    if (users.isEmpty) return const SizedBox.shrink();

    final first = users.isNotEmpty ? users[0] : null;
    final second = users.length > 1 ? users[1] : null;
    final third = users.length > 2 ? users[2] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (second != null) _buildPodiumItem(context, second, 2, 140, const Color(0xFFC0C0C0)),
          if (first != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPodiumItem(context, first, 1, 180, const Color(0xFFFFD700), isFirst: true),
            ),
          if (third != null) _buildPodiumItem(context, third, 3, 120, const Color(0xFFCD7F32)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(BuildContext context, LeaderboardUser user, int rank, double height, Color color, {bool isFirst = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isFirst)
          Icon(Icons.workspace_premium, color: color, size: 36),
        const SizedBox(height: 8),
        FrameAvatar(
          avatarUrl: user.avatarUrl,
          activeFrame: user.activeFrame,
          radius: isFirst ? 36 : 28,
        ),
        const SizedBox(height: 12),
        Container(
          width: isFirst ? 100 : 80,
          height: height,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: color.withValues(alpha: 0.5), width: isFirst ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                '#$rank',
                style: TextStyle(
                  color: color,
                  fontSize: isFirst ? 32 : 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  user.username,
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on, color: context.colors.accent, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${user.kCoinBalance}',
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListItem(BuildContext context, LeaderboardUser user, int rank) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#$rank',
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FrameAvatar(
            avatarUrl: user.avatarUrl,
            activeFrame: user.activeFrame,
            radius: 20,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              user.username,
              style: TextStyle(
                color: context.colors.textHigh,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.monetization_on, color: context.colors.accent, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${user.kCoinBalance}',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
