import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tipster_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/tipster/coupon_feed_card.dart';
import 'tipster_profile_screen.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';

/// Community coupon feed: public analysis coupons, newest first, with
/// like / comment / copy actions.
class CouponFeedScreen extends ConsumerWidget {
  const CouponFeedScreen({super.key, this.embedded = false});

  /// Hosted inside the Kupon tab, the shell owns the app bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final couponsAsync = ref.watch(publicCouponsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: embedded
          ? null
          : AppBar(
              backgroundColor: colors.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              title: Text(
                'TOPLULUK KUPONLARI',
                style: TextStyle(
                  color: colors.textHigh,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
      body: ResponsiveShell(
        child: couponsAsync.when(
          loading: () => const ListShimmer(itemCount: 6),
          error: (err, stack) => _ErrorState(
            onRetry: () => ref.invalidate(publicCouponsProvider),
          ),
          data: (coupons) => RefreshIndicator(
            color: colors.accent,
            backgroundColor: colors.surface,
            onRefresh: () async => ref.refresh(publicCouponsProvider.future),
            child: coupons.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    // +1: the responsible-play footer trails the feed. It was
                    // only on the four bulletin screens, so a user who lived
                    // in the community tab never saw it.
                    itemCount: coupons.length + 1,
                    itemBuilder: (context, index) {
                      if (index == coupons.length) {
                        return const BulletinDisclaimer();
                      }
                      final coupon = coupons[index];
                      return CouponFeedCard(
                        coupon: coupon,
                        onTipsterTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TipsterProfileScreen(
                                userId: coupon.userId,
                                username: coupon.username,
                                avatarUrl: coupon.avatarUrl,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 64),
        Icon(Icons.groups, size: 56, color: colors.textLow),
        const SizedBox(height: 12),
        Text(
          'Henüz paylaşılan kupon yok.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textHigh,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Bültenden seçim yapıp kuponunu herkese açık paylaşarak '
          'ilk tipsterlerden biri olabilirsin.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMedium, fontSize: 13),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Topluluk kuponları yüklenemedi.',
            style: TextStyle(
              color: colors.error,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}
