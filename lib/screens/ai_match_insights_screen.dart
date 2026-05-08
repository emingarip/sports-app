import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers/ai_sport_agent_wizard_provider.dart';
import '../models/match.dart' as model;
import '../models/match_list_view_model.dart';
import '../models/store_product.dart';
import '../models/wizard_insight_report.dart';
import '../providers/favorites_provider.dart';
import '../providers/match_provider.dart';
import '../providers/store_provider.dart';
import '../theme/app_theme.dart';

class AiMatchInsightsScreen extends ConsumerStatefulWidget {
  const AiMatchInsightsScreen({super.key});

  @override
  ConsumerState<AiMatchInsightsScreen> createState() =>
      _AiMatchInsightsScreenState();
}

class _AiMatchInsightsScreenState extends ConsumerState<AiMatchInsightsScreen> {
  String? _selectedMatchId;
  Future<WizardInsightReport>? _reportFuture;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(matchListItemsProvider);
    final favorites = ref.watch(favoritesProvider);
    ref.watch(entitlementsProvider);
    final hasPremium =
        ref.watch(entitlementsProvider.notifier).hasAccess('ai_premium_base');
    final rankedItems = _rankWizardItems(items, favorites);

    if (rankedItems.isNotEmpty) {
      final selectedExists =
          rankedItems.any((item) => item.match.id == _selectedMatchId);
      if (_selectedMatchId == null || !selectedExists) {
        _selectedMatchId = rankedItems.first.match.id;
        _reportFuture = _loadReport(_selectedMatchId!);
      }
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background.withValues(alpha: 0.9),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Insights Sihirbazi',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.colors.textHigh,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: rankedItems.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                onRefresh: () => _refreshSelected(),
                child: FutureBuilder<WizardInsightReport>(
                  future: _reportFuture,
                  builder: (context, snapshot) {
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _MatchSelector(
                            items: rankedItems,
                            selectedMatchId: _selectedMatchId,
                            favorites: favorites,
                            onSelected: _selectMatch,
                          ),
                        ),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (snapshot.hasError)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _ErrorState(onRetry: _refreshSelected),
                          )
                        else if (!snapshot.hasData)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(),
                          )
                        else ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: _DecisionHeader(report: snapshot.data!),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate(
                                [
                                  ...snapshot.data!.cards.map(
                                    (card) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _Lockable(
                                        locked: card.isPremium && !hasPremium,
                                        onUnlock:
                                            _showPremiumPurchaseBottomSheet,
                                        child: _WizardCard(card: card),
                                      ),
                                    ),
                                  ),
                                  _MarketSection(
                                    markets: snapshot.data!.markets,
                                    hasPremium: hasPremium,
                                    onUnlock: _showPremiumPurchaseBottomSheet,
                                  ),
                                  const SizedBox(height: 120),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<WizardInsightReport> _loadReport(String matchId) {
    return ref.read(aiSportAgentWizardProvider).fetchReport(matchId);
  }

  void _selectMatch(model.Match match) {
    setState(() {
      _selectedMatchId = match.id;
      _reportFuture = _loadReport(match.id);
    });
  }

  Future<void> _refreshSelected() async {
    final matchId = _selectedMatchId;
    if (matchId == null) return;
    final future = _loadReport(matchId);
    setState(() => _reportFuture = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder renders the retry state.
    }
  }

  void _showPremiumPurchaseBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const _PremiumPurchaseModal(),
    );
  }
}

List<MatchListItemViewModel> _rankWizardItems(
  List<MatchListItemViewModel> items,
  Set<String> favorites,
) {
  final ranked = [...items];
  ranked.sort((a, b) {
    final favoriteCompare = (favorites.contains(b.match.id) ? 1 : 0)
        .compareTo(favorites.contains(a.match.id) ? 1 : 0);
    if (favoriteCompare != 0) return favoriteCompare;
    return compareMatchListItems(a, b);
  });
  return ranked;
}

class _MatchSelector extends StatelessWidget {
  final List<MatchListItemViewModel> items;
  final String? selectedMatchId;
  final Set<String> favorites;
  final ValueChanged<model.Match> onSelected;

  const _MatchSelector({
    required this.items,
    required this.selectedMatchId,
    required this.favorites,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          final match = item.match;
          final selected = match.id == selectedMatchId;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelected(match),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 238,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.primary.withValues(alpha: 0.12)
                    : context.colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? context.colors.primary
                      : context.colors.surfaceContainerHighest,
                ),
              ),
              child: Row(
                children: [
                  _Logo(url: match.homeLogo, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${match.homeTeam} - ${match.awayTeam}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textHigh,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (favorites.contains(match.id)) ...[
                              Icon(Icons.star,
                                  size: 14, color: context.colors.primary),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                item.statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.textMedium,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DecisionHeader extends StatelessWidget {
  final WizardInsightReport report;

  const _DecisionHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final color = switch (report.decision) {
      'PASS' => context.colors.error,
      'CONSIDER' => Colors.green.shade700,
      _ => context.colors.primary,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DecisionPill(label: report.decision, color: color),
              const Spacer(),
              _Metric(label: 'Guven', value: '${report.confidence}/100'),
              const SizedBox(width: 10),
              _Metric(label: 'Risk', value: report.riskLevel.toUpperCase()),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${report.match.homeTeam} - ${report.match.awayTeam}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            report.summary,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              height: 1.45,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionPill extends StatelessWidget {
  final String label;
  final Color color;

  const _DecisionPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _WizardCard extends StatelessWidget {
  final WizardCard card;

  const _WizardCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.title,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textHigh,
                  ),
                ),
              ),
              _Metric(label: card.signal, value: '${card.confidence}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            card.text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              height: 1.45,
              color: context.colors.textMedium,
            ),
          ),
          if (card.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: card.evidence
                  .map((item) => _EvidenceChip(item: item))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketSection extends StatelessWidget {
  final List<WizardMarketSignal> markets;
  final bool hasPremium;
  final VoidCallback onUnlock;

  const _MarketSection({
    required this.markets,
    required this.hasPremium,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    if (markets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            'Market Sinyalleri',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.colors.textHigh,
            ),
          ),
        ),
        ...markets.map(
          (market) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Lockable(
              locked: market.isPremium && !hasPremium,
              onUnlock: onUnlock,
              child: _MarketCard(market: market),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarketCard extends StatelessWidget {
  final WizardMarketSignal market;

  const _MarketCard({required this.market});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.analytics_outlined, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  market.title,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  market.text,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    height: 1.35,
                    color: context.colors.textMedium,
                  ),
                ),
              ],
            ),
          ),
          _Metric(label: market.signal, value: '${market.confidence}'),
        ],
      ),
    );
  }
}

class _Lockable extends StatelessWidget {
  final bool locked;
  final Widget child;
  final VoidCallback onUnlock;

  const _Lockable({
    required this.locked,
    required this.child,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: IgnorePointer(child: child),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color:
                  context.colors.surfaceContainerLowest.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Premium ile ac'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  final WizardEvidence item;

  const _EvidenceChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        '${item.label}: ${item.value}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textMedium,
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: context.colors.textMedium,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            color: context.colors.textHigh,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  final String url;
  final double size;

  const _Logo({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: context.colors.surfaceContainerHigh,
          child: Icon(Icons.sports_soccer, size: size * 0.55),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Analiz icin gorunen mac bulunamadi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textMedium),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: context.colors.error, size: 42),
            const SizedBox(height: 12),
            Text(
              'Sihirbaz raporu yuklenemedi.',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.bold,
                color: context.colors.textHigh,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumPurchaseModal extends ConsumerStatefulWidget {
  const _PremiumPurchaseModal();

  @override
  ConsumerState<_PremiumPurchaseModal> createState() =>
      _PremiumPurchaseModalState();
}

class _PremiumPurchaseModalState extends ConsumerState<_PremiumPurchaseModal> {
  bool _isPurchasing = false;

  Future<void> _buyProduct(StoreProduct product) async {
    setState(() => _isPurchasing = true);
    try {
      await ref.read(storeServiceProvider).buyStoreItem(product.productCode);
      await ref.read(entitlementsProvider.notifier).refresh();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(storeProductsProvider);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: productsAsync.when(
          data: (products) {
            StoreProduct? product;
            for (final item in products) {
              if (item.productCode.contains('premium_base') ||
                  item.productCode.contains('premium')) {
                product = item;
                break;
              }
            }
            final selectedProduct = product;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium,
                    size: 54, color: context.colors.primary),
                const SizedBox(height: 12),
                Text(
                  'Premium Analiz',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Market sinyalleri ve canli izleme planini ac.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textMedium),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selectedProduct == null || _isPurchasing
                        ? null
                        : () => _buyProduct(selectedProduct),
                    child: Text(
                      selectedProduct == null
                          ? 'Paket bulunamadi'
                          : _isPurchasing
                              ? 'Isleniyor...'
                              : 'Ac (${selectedProduct.price} K-Coin)',
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Text(
            'Paketler yuklenemedi.',
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ),
    );
  }
}
