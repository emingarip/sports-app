import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bulletin.dart';
import '../providers/bulletin_provider.dart';
import '../providers/coupon_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bulletin/bulletin_date_selector.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';
import '../widgets/bulletin/bulletin_match_card.dart';
import '../widgets/bulletin/cooling_mode_banner.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/shimmer_loading.dart';
import 'bankroll_screen.dart';
import 'bulletin_match_analysis_screen.dart';
import 'coupon_builder_screen.dart';

/// Markets selectable from the bulletin filter row.
const List<(String, String)> _marketFilterOptions = [
  ('MS', 'MS'),
  ('AU_2_5', 'AU 2,5'),
  ('KG', 'KG'),
  ('IY_MS', 'İY/MS'),
  ('CS', 'Çifte Şans'),
];

class BulletinScreen extends ConsumerStatefulWidget {
  const BulletinScreen({super.key});

  @override
  ConsumerState<BulletinScreen> createState() => _BulletinScreenState();
}

class _BulletinScreenState extends ConsumerState<BulletinScreen> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = bulletinDateKey(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bulletinFilterProvider);
    final bulletinAsync = ref.watch(bulletinProvider(_selectedDate));
    final predictionsAsync =
        ref.watch(bulletinPredictionsProvider(_selectedDate));
    final couponDraft = ref.watch(couponDraftProvider);

    // Subscribes the visible day to the bulletin_odds realtime channel. The
    // publication existed since the tables were created but nothing listened,
    // so odds stayed stale until the whole screen was rebuilt.
    ref.watch(bulletinRealtimeSyncProvider(_selectedDate));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'BÜLTEN',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          // The community-coupons button used to live here as an icon with no
          // label; it is now the second tab of the Kupon destination. The
          // bankroll assistant keeps a shortcut because it is consulted
          // mid-selection, and it also has a labelled row in Profile.
          IconButton(
            tooltip: 'Bankroll asistanı',
            icon: Icon(
              Icons.account_balance_wallet_outlined,
              color: context.colors.textHigh,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BankrollScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ResponsiveShell(
            child: Column(
              children: [
                BulletinDateSelector(
                  selectedDate: _selectedDate,
                  onDateSelected: (date) {
                    setState(() {
                      _selectedDate = bulletinDateKey(date);
                    });
                  },
                ),
                const SizedBox(height: 8),
                // Cooling mode used to be invisible outside the two
                // screens that owned it; the bulletin is where the
                // reminder actually lands.
                const CoolingModeBanner(),
                _buildFilterRow(filter, bulletinAsync.value ?? const []),
                _buildHintCaption(),
                Expanded(
                  // Odds refresh hourly on the server. Without a manual gesture
                  // the only way to force a refetch was to leave and come back.
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: bulletinAsync.when(
                      loading: () => const ListShimmer(itemCount: 6),
                      error: (err, stack) => _buildErrorState(),
                      data: (matches) => _buildMatchList(
                        matches,
                        filter,
                        predictionsAsync.value ?? const {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Kupon çubuğu: alt navigasyon overlay'inin üstünde durur; FAB'a göre
          // daha görünür ve oran kutularını kapatmaz.
          if (!couponDraft.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 100,
              child: _CouponBar(
                count: couponDraft.count,
                totalOdds: couponDraft.totalOdds,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CouponBuilderScreen(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(
      BulletinFilterState filter, List<BulletinMatch> matches) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: filter.leagueName == null
                ? 'Lig: Tümü'
                : 'Lig: ${filter.leagueName}',
            isSelected: filter.leagueName != null,
            icon: Icons.filter_list,
            onTap: () => _openLeaguePicker(matches, filter),
          ),
          const SizedBox(width: 8),
          for (final (code, label) in _marketFilterOptions) ...[
            _FilterChip(
              label: label,
              isSelected: filter.marketCode == code,
              onTap: () =>
                  ref.read(bulletinFilterProvider.notifier).setMarket(code),
            ),
            const SizedBox(width: 8),
          ],
          _FilterChip(
            label: 'Value',
            isSelected: filter.onlyValuePicks,
            icon: Icons.stars,
            onTap: () => ref
                .read(bulletinFilterProvider.notifier)
                .toggleOnlyValuePicks(),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(bulletinProvider(_selectedDate));
    ref.invalidate(bulletinPredictionsProvider(_selectedDate));
    await ref.read(bulletinProvider(_selectedDate).future);
  }

  Widget _buildHintCaption() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 11, color: context.colors.textLow),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Orana dokun: kupona ekle · Maça dokun: analiz',
              style: TextStyle(
                color: context.colors.textLow,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _FreshnessStamp(date: _selectedDate),
        ],
      ),
    );
  }

  void _openLeaguePicker(
      List<BulletinMatch> matches, BulletinFilterState filter) {
    final counts = <String, int>{};
    for (final match in matches) {
      counts[match.competitionName] = (counts[match.competitionName] ?? 0) + 1;
    }
    final leagues = counts.keys.toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                dense: true,
                leading: Icon(
                  filter.leagueName == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: context.colors.accent,
                ),
                title: const Text(
                  'Tüm Ligler',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                trailing: Text('${matches.length}'),
                onTap: () {
                  ref.read(bulletinFilterProvider.notifier).setLeague(null);
                  Navigator.pop(sheetContext);
                },
              ),
              for (final league in leagues)
                ListTile(
                  dense: true,
                  leading: Icon(
                    filter.leagueName == league
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: context.colors.accent,
                  ),
                  title: Text(
                    league,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  trailing: Text('${counts[league]}'),
                  onTap: () {
                    ref.read(bulletinFilterProvider.notifier).setLeague(league);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatchList(
    List<BulletinMatch> matches,
    BulletinFilterState filter,
    Map<String, BulletinPrediction> predictions,
  ) {
    var filtered = matches;
    if (filter.leagueName != null) {
      filtered = filtered
          .where((match) => match.competitionName == filter.leagueName)
          .toList();
    }
    if (filter.onlyValuePicks) {
      filtered = filtered
          .where(
              (match) => predictions[match.id]?.valuePicks.isNotEmpty ?? false)
          .toList();
    }

    if (filtered.isEmpty) {
      return _buildEmptyState(
        matches.isEmpty
            ? 'Bu tarih için bülten henüz yayınlanmadı. İddaa bülteni genelde '
                'bir gün önceden açılır; aşağı çekerek tazeleyebilirsin.'
            : filter.onlyValuePicks
                ? 'Bu filtrelerde model değerli oran bulamadı. "Değer yok" da '
                    'bir sonuçtur - filtreyi kaldırıp bültenin tamamına '
                    'bakabilirsin.'
                : 'Filtrelere uyan maç bulunamadı.',
      );
    }

    // Group by competition, preserving kickoff order.
    final grouped = <String, List<BulletinMatch>>{};
    for (final match in filtered) {
      grouped.putIfAbsent(match.competitionName, () => []).add(match);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
            child: Text(
              entry.key.toUpperCase(),
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          for (final match in entry.value)
            BulletinMatchCard(
              match: match,
              prediction: predictions[match.id],
              marketCode: filter.marketCode,
              onTap: () => _openMatchAnalysis(match),
              selectedSelectionKeys: _selectedKeysFor(match, filter.marketCode),
              onSelectionTap: (market, selection) {
                ref.read(couponDraftProvider.notifier).toggleSelection(
                      match: match,
                      market: market,
                      selection: selection,
                      prediction: predictions[match.id],
                    );
              },
            ),
        ],
        const BulletinDisclaimer(),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 56,
              color: context.colors.surfaceContainerHighest,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textMedium,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Bülten yüklenirken bir sorun oluştu.',
            style: TextStyle(
              color: context.colors.error,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              ref.invalidate(bulletinProvider(_selectedDate));
              ref.invalidate(bulletinPredictionsProvider(_selectedDate));
            },
            child: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }

  Set<String> _selectedKeysFor(BulletinMatch match, String marketCode) {
    final draft = ref.watch(couponDraftProvider);
    return draft.selections
        .where(
            (s) => s.bulletinMatchId == match.id && s.marketCode == marketCode)
        .map((s) => s.selectionKey)
        .toSet();
  }

  void _openMatchAnalysis(BulletinMatch match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BulletinMatchAnalysisScreen(match: match),
      ),
    );
  }
}

/// "Oranlar 14:05'te güncellendi" - without it a user cannot tell a live price
/// from one the hourly sync wrote eight hours ago.
class _FreshnessStamp extends ConsumerWidget {
  const _FreshnessStamp({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatedAt = ref.watch(bulletinLastUpdatedProvider(date)).value;
    if (updatedAt == null) return const SizedBox.shrink();

    final local = updatedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final sameDay = DateTime.now().difference(local).inHours < 24;
    final stamp = sameDay
        ? '${two(local.hour)}:${two(local.minute)}'
        : '${two(local.day)}.${two(local.month)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 11, color: context.colors.textLow),
        const SizedBox(width: 3),
        Text(
          '$stamp güncellendi',
          style: TextStyle(
            color: context.colors.textLow,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CouponBar extends StatelessWidget {
  final int count;
  final double totalOdds;
  final VoidCallback onTap;

  const _CouponBar({
    required this.count,
    required this.totalOdds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.accent,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count seçim',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Toplam Oran ${totalOdds.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              const Text(
                'KUPONU GÖR',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: Colors.black,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colors.chipSelectedBackground
              : context.colors.chipBackground,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? context.colors.accent.withValues(alpha: 0.6)
                : context.colors.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? context.colors.chipSelectedForeground
                    : context.colors.textMedium,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? context.colors.chipSelectedForeground
                    : context.colors.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
