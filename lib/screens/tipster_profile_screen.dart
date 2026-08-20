import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tipster.dart';
import '../providers/tipster_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/frame_avatar.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/tipster/coupon_feed_card.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';

/// Public tipster profile: skill metrics from `tipster_stats` (period 'all'),
/// market breakdown and the tipster's visible coupon history.
class TipsterProfileScreen extends ConsumerWidget {
  final String userId;

  /// Optional; used for an instant header while the stats load.
  final String? username;
  final String? avatarUrl;

  const TipsterProfileScreen({
    super.key,
    required this.userId,
    this.username,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final statsAsync = ref.watch(tipsterStatsProvider(userId));
    final couponsAsync = ref.watch(tipsterCouponsProvider(userId));
    final coupons = couponsAsync.value ?? const [];
    final displayName = username ?? coupons.firstOrNull?.username ?? 'Tipster';
    final displayAvatar = avatarUrl ?? coupons.firstOrNull?.avatarUrl;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Tipster Profili')),
      body: ResponsiveShell(
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.surface,
          onRefresh: () async {
            ref.invalidate(tipsterStatsProvider(userId));
            ref.invalidate(tipsterCouponsProvider(userId));
            await ref.read(tipsterCouponsProvider(userId).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(username: displayName, avatarUrl: displayAvatar),
              const SizedBox(height: 16),
              statsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, stack) => Text(
                  'Tipster istatistikleri yüklenemedi.',
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
                data: (stats) => _StatsSection(stats: stats),
              ),
              const SizedBox(height: 16),
              Text(
                'KUPON GEÇMİŞİ',
                style: TextStyle(
                  color: colors.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              couponsAsync.when(
                loading: () => const ListShimmer(itemCount: 3),
                error: (err, stack) => Text(
                  'Kupon geçmişi yüklenemedi.',
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
                data: (list) => list.isEmpty
                    ? Text(
                        'Görünür kupon yok.',
                        style:
                            TextStyle(color: colors.textMedium, fontSize: 13),
                      )
                    : Column(
                        children: [
                          for (final coupon in list)
                            CouponFeedCard(
                              coupon: coupon,
                              showTipsterHeader: false,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              const BulletinDisclaimer(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String username;
  final String? avatarUrl;

  const _Header({required this.username, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        FrameAvatar(avatarUrl: avatarUrl, radius: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            username,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textHigh,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsSection extends StatelessWidget {
  final TipsterStats? stats;

  const _StatsSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stats = this.stats;
    final roi = stats?.roi;
    final avgClv = stats?.avgClv;
    final winRate = stats?.winRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats == null || !stats.hasEnoughSample) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: colors.onErrorContainer),
                const SizedBox(width: 6),
                Text(
                  'Yetersiz veri (min. 10 sonuçlanmış kupon)',
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            _MetricCard(
              label: 'ROI',
              value: roi == null
                  ? '—'
                  : '${roi >= 0 ? '+' : ''}%${(roi * 100).toStringAsFixed(1)}',
              valueColor: roi == null
                  ? null
                  : (roi >= 0 ? colors.success : colors.error),
            ),
            const SizedBox(width: 8),
            _MetricCard(
              label: 'Ort. CLV',
              value: avgClv == null
                  ? '—'
                  : '${avgClv >= 0 ? '+' : ''}%${(avgClv * 100).toStringAsFixed(1)}',
              valueColor: avgClv == null
                  ? null
                  : (avgClv >= 0 ? colors.success : colors.error),
            ),
            const SizedBox(width: 8),
            _MetricCard(
              label: 'İsabet',
              value: winRate == null
                  ? '—'
                  : '%${(winRate * 100).toStringAsFixed(0)}',
            ),
            const SizedBox(width: 8),
            _MetricCard(
              label: 'Sonuçlanan',
              value: '${stats?.couponsSettled ?? 0}',
            ),
          ],
        ),
        if (stats != null && stats.marketBreakdown.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in stats.marketBreakdown.entries)
                _MarketChip(marketCode: entry.key, data: entry.value),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricCard({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? colors.textHigh,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: colors.textLow,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketChip extends StatelessWidget {
  final String marketCode;
  final Object? data;

  const _MarketChip({required this.marketCode, required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final map = data is Map ? data as Map : const {};
    final picks = (map['picks'] as num?)?.toInt() ?? 0;
    final won = (map['won'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Text(
        '$marketCode • $won/$picks',
        style: TextStyle(
          color: colors.textMedium,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
