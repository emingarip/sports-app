import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/badge.dart';
import '../providers/badge_provider.dart';

class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeState = ref.watch(badgeProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: context.colors.textHigh, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'ROZETLER',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
      ),
      body: badgeState.isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.colors.accent))
          : _buildContent(context, badgeState),
    );
  }

  Widget _buildContent(BuildContext context, BadgeState state) {
    final grouped = state.groupedByCategory;
    final categories = grouped.keys.toList();

    return CustomScrollView(
      slivers: [
        // Summary header
        SliverToBoxAdapter(
          child: _buildSummaryHeader(context, state),
        ),
        // Streak card
        SliverToBoxAdapter(
          child: _buildStreakCard(context, state.streak),
        ),
        // Badge categories
        ...categories.expand((category) {
          final badges = grouped[category]!;
          final categoryLabel = badges.first.categoryLabel;
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  categoryLabel,
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final badge = badges[index];
                    final progress = state.progressFor(badge.id);
                    return _BadgeGridItem(badge: badge, userBadge: progress);
                  },
                  childCount: badges.length,
                ),
              ),
            ),
          ];
        }),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildSummaryHeader(BuildContext context, BadgeState state) {
    final total = state.definitions.length;
    final unlocked = state.unlockedCount;
    final progress = total > 0 ? unlocked / total : 0.0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.colors.accent.withOpacity(0.15),
            context.colors.accent.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.colors.accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Circular progress
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: context.colors.outline.withOpacity(0.2),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(context.colors.accent),
                  strokeCap: StrokeCap.round,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$unlocked',
                      style: TextStyle(
                        color: context.colors.textHigh,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '/$total',
                      style: TextStyle(
                        color: context.colors.textMedium,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rozet Koleksiyonu',
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unlocked == 0
                      ? 'Başarılar seni bekliyor! 🚀'
                      : '$unlocked rozet açıldı, devam et! 💪',
                  style: TextStyle(
                    color: context.colors.textMedium,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, UserStreak streak) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.outline.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_fire_department,
                color: Color(0xFFFF9800), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${streak.currentStreak} Gün Seri',
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'En uzun: ${streak.longestStreak} gün · Toplam: ${streak.totalLogins} giriş',
                  style: TextStyle(
                    color: context.colors.textMedium,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 7-day dots
          Row(
            children: List.generate(7, (i) {
              final active = i < (streak.currentStreak % 7 == 0 && streak.currentStreak > 0 ? 7 : streak.currentStreak % 7);
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? const Color(0xFFFF9800)
                      : context.colors.outline.withOpacity(0.3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Individual badge grid item.
class _BadgeGridItem extends StatelessWidget {
  final Badge badge;
  final UserBadge userBadge;

  const _BadgeGridItem({required this.badge, required this.userBadge});

  Color _tierColor(int tier) {
    switch (tier) {
      case 1:
        return const Color(0xFFCD7F32);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFFFD700);
      default:
        return Colors.grey;
    }
  }

  IconData _resolveIcon(String iconName) {
    const iconMap = <String, IconData>{
      'person_add': Icons.person_add,
      'verified': Icons.verified,
      'camera_alt': Icons.camera_alt,
      'visibility': Icons.visibility,
      'explore': Icons.explore,
      'casino': Icons.casino,
      'gps_fixed': Icons.gps_fixed,
      'local_fire_department': Icons.local_fire_department,
      'savings': Icons.savings,
      'shopping_cart': Icons.shopping_cart,
      'trending_up': Icons.trending_up,
      'emoji_events': Icons.emoji_events,
      'date_range': Icons.date_range,
      'loyalty': Icons.loyalty,
    };
    return iconMap[iconName] ?? Icons.military_tech;
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = userBadge.isUnlocked;
    final tier = userBadge.currentTier;
    final tierColor = isUnlocked ? _tierColor(tier) : Colors.grey.shade600;

    // Progress towards next tier
    final nextTier = tier + 1;
    double progressValue = 0;
    if (!isUnlocked) {
      final target = badge.targetForTier(1);
      progressValue = target > 0 ? (userBadge.progress / target).clamp(0.0, 1.0) : 0;
    } else if (tier < badge.maxTier) {
      final target = badge.targetForTier(nextTier);
      progressValue = target > 0 ? (userBadge.progress / target).clamp(0.0, 1.0) : 0;
    } else {
      progressValue = 1.0; // Max tier reached
    }

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUnlocked
                ? tierColor.withOpacity(0.5)
                : context.colors.outline.withOpacity(0.2),
            width: isUnlocked ? 1.5 : 1,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: tierColor.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isUnlocked
                    ? tierColor.withOpacity(0.15)
                    : context.colors.surfaceVariant,
              ),
              child: Icon(
                _resolveIcon(badge.iconName),
                size: 26,
                color: isUnlocked ? tierColor : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                badge.nameTr,
                style: TextStyle(
                  color: isUnlocked
                      ? context.colors.textHigh
                      : context.colors.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 4,
                  backgroundColor: context.colors.outline.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                ),
              ),
            ),
            // Tier dots
            if (badge.maxTier > 1) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(badge.maxTier, (i) {
                  final filled = i < tier;
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? _tierColor(i + 1)
                          : context.colors.outline.withOpacity(0.3),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final isUnlocked = userBadge.isUnlocked;
    final tier = userBadge.currentTier;
    final tierColor = isUnlocked ? _tierColor(tier) : Colors.grey.shade600;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.outline.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tierColor.withOpacity(0.15),
                  border: Border.all(color: tierColor, width: 2),
                ),
                child: Icon(
                  _resolveIcon(badge.iconName),
                  size: 40,
                  color: tierColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                badge.nameTr,
                style: TextStyle(
                  color: context.colors.textHigh,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                badge.descriptionTr,
                style: TextStyle(
                  color: context.colors.textMedium,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Progress detail
              if (!isUnlocked || tier < badge.maxTier) ...[
                _buildProgressRow(context, tierColor),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: tierColor, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Maksimum seviyeye ulaştın! 🏆',
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              // Reward info
              if (badge.kCoinReward > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.colors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monetization_on,
                          color: context.colors.accent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Seviye başı +${badge.kCoinReward} K-Coin',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressRow(BuildContext context, Color tierColor) {
    final tier = userBadge.currentTier;
    final nextTier = tier + 1;
    final target = badge.targetForTier(nextTier > badge.maxTier ? badge.maxTier : nextTier);
    final progress = userBadge.progress;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'İlerleme',
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$progress / $target',
              style: TextStyle(
                color: context.colors.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: target > 0 ? (progress / target).clamp(0.0, 1.0) : 0,
            minHeight: 8,
            backgroundColor: context.colors.outline.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(tierColor),
          ),
        ),
      ],
    );
  }
}
