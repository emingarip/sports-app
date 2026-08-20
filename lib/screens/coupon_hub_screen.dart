import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/coupon_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/app_theme.dart';
import 'coupon_builder_screen.dart';
import 'coupon_feed_screen.dart';

/// First-class home for the coupon half of the product.
///
/// Before this screen, the analysis coupon was only reachable from a bar that
/// appeared once a selection was made, and the community feed only from an
/// icon-only button in the bulletin app bar. Two of the product's headline
/// promises had no entry point of their own, so most users never found them.
///
/// The tab it occupies previously held the AI insights screen, which is still
/// reachable from a match's detail page - it was never the second-most
/// important destination in a betting-analysis app.
class CouponHubScreen extends ConsumerStatefulWidget {
  const CouponHubScreen({super.key});

  @override
  ConsumerState<CouponHubScreen> createState() => _CouponHubScreenState();
}

class _CouponHubScreenState extends ConsumerState<CouponHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(couponDraftProvider);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'KUPON',
          style: TextStyle(
            color: colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.accent,
          unselectedLabelColor: colors.textMedium,
          indicatorColor: colors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          tabs: [
            Tab(
              text: draft.isEmpty ? 'Kuponum' : 'Kuponum (${draft.count})',
            ),
            const Tab(text: 'Topluluk'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (draft.isEmpty)
            const _EmptyDraftGuide()
          else
            const CouponBuilderScreen(embedded: true),
          const CouponFeedScreen(embedded: true),
        ],
      ),
    );
  }
}

/// An empty coupon used to be a dead end. It now points at the one place a
/// coupon can come from.
class _EmptyDraftGuide extends ConsumerWidget {
  const _EmptyDraftGuide();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 56, color: colors.textLow),
            const SizedBox(height: 14),
            Text(
              'Kuponun boş',
              style: TextStyle(
                color: colors.textHigh,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bültendeki oran kutularına dokunarak seçim ekle. Model her '
              'seçim ve kuponun tamamı için ne düşündüğünü burada söyler.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMedium,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => ref
                  .read(navigationProvider.notifier)
                  .setIndex(bulletinTabIndex),
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('Bültene git'),
            ),
          ],
        ),
      ),
    );
  }
}
