import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tipster.dart';
import '../../providers/tipster_provider.dart';
import '../../screens/tipster_profile_screen.dart';
import '../../theme/app_theme.dart';
import '../frame_avatar.dart';
import '../shimmer_loading.dart';

/// Skill-based tipster ranking (CLV-first) with a Tümü / Bu Ay period
/// selector; embedded as the "Tipster" tab of the leaderboard screen.
class TipsterLeaderboardTab extends ConsumerStatefulWidget {
  const TipsterLeaderboardTab({super.key});

  @override
  ConsumerState<TipsterLeaderboardTab> createState() =>
      _TipsterLeaderboardTabState();
}

class _TipsterLeaderboardTabState extends ConsumerState<TipsterLeaderboardTab> {
  bool _thisMonth = false;

  String get _period {
    if (!_thisMonth) return 'all';
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leaderboardAsync = ref.watch(tipsterLeaderboardProvider(_period));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              _PeriodChip(
                label: 'Tümü',
                isSelected: !_thisMonth,
                onTap: () => setState(() => _thisMonth = false),
              ),
              const SizedBox(width: 8),
              _PeriodChip(
                label: 'Bu Ay',
                isSelected: _thisMonth,
                onTap: () => setState(() => _thisMonth = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: leaderboardAsync.when(
            loading: () => const ListShimmer(itemCount: 7),
            error: (err, stack) => Center(
              child: Text(
                'Tipster sıralaması yüklenemedi.',
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
            ),
            data: (entries) => RefreshIndicator(
              color: colors.accent,
              backgroundColor: colors.surface,
              onRefresh: () async =>
                  ref.refresh(tipsterLeaderboardProvider(_period).future),
              child: entries.isEmpty
                  ? _EmptyList(colors: colors)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: entries.length + 1,
                      itemBuilder: (context, index) {
                        if (index == entries.length) {
                          return const _Footnote();
                        }
                        return _TipsterRow(
                          entry: entries[index],
                          rank: index + 1,
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TipsterRow extends StatelessWidget {
  final TipsterLeaderboardEntry entry;
  final int rank;

  const _TipsterRow({required this.entry, required this.rank});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final avgClv = entry.avgClv;
    final roi = entry.roi;
    final clvColor = avgClv == null
        ? colors.textLow
        : (avgClv >= 0 ? colors.success : colors.error);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TipsterProfileScreen(
              userId: entry.userId,
              username: entry.username,
              avatarUrl: entry.avatarUrl,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: colors.textMedium,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FrameAvatar(avatarUrl: entry.avatarUrl, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textHigh,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.couponsSettled} sonuçlanan'
                    '${roi != null ? ' • ROI ${roi >= 0 ? '+' : ''}%${(roi * 100).toStringAsFixed(1)}' : ''}',
                    style: TextStyle(color: colors.textLow, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  avgClv == null
                      ? '—'
                      : '${avgClv >= 0 ? '+' : ''}%${(avgClv * 100).toStringAsFixed(1)}',
                  style: TextStyle(
                    color: clvColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Ort. CLV',
                  style: TextStyle(
                    color: colors.textLow,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.chipSelectedBackground
              : colors.chipBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? colors.accent.withValues(alpha: 0.6)
                : colors.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? colors.chipSelectedForeground
                : colors.textMedium,
          ),
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        'Sıralama kâra değil, kapanış oranını yenme (CLV) becerisine '
        'dayanır. Min. 10 sonuçlanmış kupon.',
        style: TextStyle(color: colors.textLow, fontSize: 11),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  final AppColors colors;

  const _EmptyList({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.leaderboard, size: 56, color: colors.textLow),
        const SizedBox(height: 12),
        Text(
          'Bu dönem için sıralanacak tipster yok.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textMedium,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const _Footnote(),
      ],
    );
  }
}
