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
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';

const double _insightsShellMaxWidth = 600;

enum _InsightsMode { wizard, deck }

class AiMatchInsightsScreen extends ConsumerStatefulWidget {
  const AiMatchInsightsScreen({super.key});

  @override
  ConsumerState<AiMatchInsightsScreen> createState() =>
      _AiMatchInsightsScreenState();
}

class _AiMatchInsightsScreenState extends ConsumerState<AiMatchInsightsScreen> {
  String? _selectedMatchId;
  Future<WizardInsightReport>? _reportFuture;
  _InsightsMode _mode = _InsightsMode.wizard;
  int _deckIndex = 0;
  final List<int> _deckHistory = [];
  final Map<String, Future<WizardInsightReport>> _deckReportFutures = {};

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(matchListItemsProvider);
    final favorites = ref.watch(favoritesProvider);
    final entitlements = ref.watch(entitlementsProvider).asData?.value ?? [];
    final hasPremium = _hasAiPremiumAccess(entitlements);
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _insightsShellMaxWidth),
            child: _buildContent(
              rankedItems: rankedItems,
              favorites: favorites,
              hasPremium: hasPremium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required List<MatchListItemViewModel> rankedItems,
    required Set<String> favorites,
    required bool hasPremium,
  }) {
    if (rankedItems.isEmpty) {
      return const _EmptyState();
    }
    if (_deckIndex > rankedItems.length) {
      _deckIndex = rankedItems.length - 1;
    }
    if (_mode == _InsightsMode.deck) {
      return _buildDeckMode(rankedItems: rankedItems, favorites: favorites);
    }
    return RefreshIndicator(
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
                child: _ModeSwitcher(
                  mode: _mode,
                  onChanged: _setMode,
                ),
              ),
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
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _Lockable(
                              locked: card.isPremium && !hasPremium,
                              onUnlock: _showPremiumPurchaseBottomSheet,
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
    );
  }

  Widget _buildDeckMode({
    required List<MatchListItemViewModel> rankedItems,
    required Set<String> favorites,
  }) {
    final isFinished = _deckIndex >= rankedItems.length;
    final item = isFinished ? null : rankedItems[_deckIndex];
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _ModeSwitcher(
            mode: _mode,
            onChanged: _setMode,
          ),
        ),
        if (item == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _DeckFinished(
              reviewedCount: rankedItems.length,
              onRestart: _restartDeck,
            ),
          )
        else
          SliverFillRemaining(
            hasScrollBody: false,
            child: FutureBuilder<WizardInsightReport>(
              future: _deckReportFuture(item.match.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _DeckError(
                    onRetry: () {
                      setState(() {
                        _deckReportFutures.remove(item.match.id);
                      });
                    },
                    onSkip: _passDeckCard,
                  );
                }
                return _SwipeDeck(
                  key: ValueKey(item.match.id),
                  item: item,
                  report: snapshot.data!,
                  isFavorite: favorites.contains(item.match.id),
                  currentIndex: _deckIndex + 1,
                  totalCount: rankedItems.length,
                  canUndo: _deckHistory.isNotEmpty,
                  onPass: _passDeckCard,
                  onKeep: () {
                    _keepDeckCard(item.match.id);
                  },
                  onDetails: () => _openDeckDetails(item.match),
                  onUndo: _undoDeckCard,
                );
              },
            ),
          ),
      ],
    );
  }

  Future<WizardInsightReport> _loadReport(String matchId) {
    return ref.read(aiSportAgentWizardProvider).fetchReport(matchId);
  }

  Future<WizardInsightReport> _deckReportFuture(String matchId) {
    return _deckReportFutures.putIfAbsent(matchId, () => _loadReport(matchId));
  }

  void _setMode(_InsightsMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
  }

  void _selectMatch(model.Match match) {
    setState(() {
      _mode = _InsightsMode.wizard;
      _selectedMatchId = match.id;
      _reportFuture = _loadReport(match.id);
    });
  }

  void _passDeckCard() {
    setState(() {
      _deckHistory.add(_deckIndex);
      _deckIndex += 1;
    });
  }

  Future<void> _keepDeckCard(String matchId) async {
    final favorites = ref.read(favoritesProvider);
    if (!favorites.contains(matchId)) {
      await ref.read(favoritesProvider.notifier).toggleFavorite(matchId);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mac takibe alindi.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: 900),
      ),
    );
    _passDeckCard();
  }

  void _openDeckDetails(model.Match match) {
    _selectMatch(match);
  }

  void _undoDeckCard() {
    if (_deckHistory.isEmpty) return;
    setState(() {
      _deckIndex = _deckHistory.removeLast();
    });
  }

  void _restartDeck() {
    setState(() {
      _deckIndex = 0;
      _deckHistory.clear();
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

bool _hasAiPremiumAccess(Iterable<dynamic> entitlements) {
  return entitlements.any((entitlement) {
    final productCode = entitlement.productCode?.toString() ?? '';
    final isValid = entitlement.isValid == true;
    return isValid &&
        (productCode == 'ai_premium_base' ||
            productCode == 'ai_premium_monthly' ||
            productCode.contains('premium'));
  });
}

String _selectorSubtitle(model.Match match, String statusLabel) {
  if (match.status == model.MatchStatus.live &&
      match.homeScore != null &&
      match.awayScore != null) {
    return '$statusLabel  ${match.homeScore}-${match.awayScore}';
  }
  return statusLabel;
}

String _matchScoreText(WizardMatchSummary match) {
  if (match.homeScore == null || match.awayScore == null) {
    return 'Skor yok';
  }
  return '${match.homeScore}-${match.awayScore}';
}

String _matchStatusText(WizardMatchSummary match) {
  final description = match.statusDescription?.trim();
  if (description != null && description.isNotEmpty) return description;
  switch (match.status) {
    case 'live':
      return 'Canli';
    case 'finished':
      return 'Tamamlandi';
    case 'postponed':
      return 'Ertelendi';
    case 'cancelled':
      return 'Iptal';
    default:
      final local = match.kickoffAt.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ModeSwitcher extends StatelessWidget {
  final _InsightsMode mode;
  final ValueChanged<_InsightsMode> onChanged;

  const _ModeSwitcher({
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            _ModeButton(
              label: 'Sihirbaz',
              icon: Icons.auto_awesome,
              selected: mode == _InsightsMode.wizard,
              onTap: () => onChanged(_InsightsMode.wizard),
            ),
            _ModeButton(
              label: 'Hizli Tara',
              icon: Icons.swipe,
              selected: mode == _InsightsMode.deck,
              onTap: () => onChanged(_InsightsMode.deck),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? context.colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? context.colors.background
                    : context.colors.textMedium,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: selected
                      ? context.colors.background
                      : context.colors.textMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeDeck extends StatefulWidget {
  final MatchListItemViewModel item;
  final WizardInsightReport report;
  final bool isFavorite;
  final int currentIndex;
  final int totalCount;
  final bool canUndo;
  final VoidCallback onPass;
  final VoidCallback onKeep;
  final VoidCallback onDetails;
  final VoidCallback onUndo;

  const _SwipeDeck({
    super.key,
    required this.item,
    required this.report,
    required this.isFavorite,
    required this.currentIndex,
    required this.totalCount,
    required this.canUndo,
    required this.onPass,
    required this.onKeep,
    required this.onDetails,
    required this.onUndo,
  });

  @override
  State<_SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<_SwipeDeck> {
  Offset _dragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final decisionColor = _decisionColor(context, widget.report.decision);
    final rotation = (_dragOffset.dx / 620).clamp(-0.10, 0.10);
    final passOpacity = (-_dragOffset.dx / 120).clamp(0.0, 1.0);
    final keepOpacity = (_dragOffset.dx / 120).clamp(0.0, 1.0);
    final detailOpacity = (-_dragOffset.dy / 120).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 118),
      child: Column(
        children: [
          _DeckProgress(
            currentIndex: widget.currentIndex,
            totalCount: widget.totalCount,
            canUndo: widget.canUndo,
            onUndo: widget.onUndo,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() => _dragOffset += details.delta);
                },
                onPanEnd: (_) => _settleDrag(),
                onTap: widget.onDetails,
                child: Transform.translate(
                  offset: _dragOffset,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _DeckCard(
                          item: widget.item,
                          report: widget.report,
                          isFavorite: widget.isFavorite,
                          decisionColor: decisionColor,
                        ),
                        _SwipeStamp(
                          label: 'GEC',
                          color: context.colors.error,
                          alignment: Alignment.topRight,
                          opacity: passOpacity,
                        ),
                        _SwipeStamp(
                          label: 'TAKIP',
                          color: context.colors.success,
                          alignment: Alignment.topLeft,
                          opacity: keepOpacity,
                        ),
                        _SwipeStamp(
                          label: 'DETAY',
                          color: context.colors.primary,
                          alignment: Alignment.topCenter,
                          opacity: detailOpacity,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DeckActionButton(
                icon: Icons.close,
                color: context.colors.error,
                onPressed: widget.onPass,
              ),
              const SizedBox(width: 16),
              _DeckActionButton(
                icon: Icons.keyboard_arrow_up,
                color: context.colors.primary,
                large: true,
                onPressed: widget.onDetails,
              ),
              const SizedBox(width: 16),
              _DeckActionButton(
                icon: Icons.star,
                color: context.colors.success,
                onPressed: widget.onKeep,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Sola gec, saga takibe al, yukari detayli analiz',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _settleDrag() {
    final offset = _dragOffset;
    setState(() => _dragOffset = Offset.zero);
    if (offset.dy < -110) {
      widget.onDetails();
      return;
    }
    if (offset.dx > 115) {
      widget.onKeep();
      return;
    }
    if (offset.dx < -115) {
      widget.onPass();
    }
  }
}

class _DeckCard extends StatelessWidget {
  final MatchListItemViewModel item;
  final WizardInsightReport report;
  final bool isFavorite;
  final Color decisionColor;

  const _DeckCard({
    required this.item,
    required this.report,
    required this.isFavorite,
    required this.decisionColor,
  });

  @override
  Widget build(BuildContext context) {
    final match = item.match;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 560),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: decisionColor.withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.cardShadow.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamSnapshot(
                  logoUrl: match.homeLogo,
                  name: match.homeTeam,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Text(
                      _matchScoreText(report.match),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.colors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _matchStatusText(report.match),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: context.colors.textMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _TeamSnapshot(
                  logoUrl: match.awayLogo,
                  name: match.awayTeam,
                  alignment: CrossAxisAlignment.end,
                  textAlign: TextAlign.end,
                ),
              ),
              if (isFavorite)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child:
                      Icon(Icons.star, color: context.colors.primary, size: 22),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            match.leagueName ?? 'Futbol',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textMedium,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DecisionPill(label: report.decision, color: decisionColor),
              const Spacer(),
              _Metric(label: 'Guven', value: '${report.confidence}'),
              const SizedBox(width: 12),
              _Metric(label: 'Risk', value: report.riskLevel.toUpperCase()),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            report.summary,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.45,
              color: context.colors.textMedium,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: report.confidence.clamp(0, 100) / 100,
              minHeight: 8,
              backgroundColor: context.colors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(decisionColor),
            ),
          ),
          const SizedBox(height: 14),
          _QuickContextGrid(report: report),
          const SizedBox(height: 12),
          if (report.cards.isNotEmpty) _DeckReason(card: report.cards.first),
        ],
      ),
    );
  }
}

class _TeamSnapshot extends StatelessWidget {
  final String logoUrl;
  final String name;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;

  const _TeamSnapshot({
    required this.logoUrl,
    required this.name,
    required this.alignment,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        _Logo(url: logoUrl, size: 42),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
      ],
    );
  }
}

class _QuickContextGrid extends StatelessWidget {
  final WizardInsightReport report;

  const _QuickContextGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final quick = report.quickContext;
    final tiles = [
      _QuickContextTileData(
        icon: Icons.timeline,
        title: 'Form',
        value: _quickFormValue(quick.form),
        detail: quick.form.summary,
      ),
      _QuickContextTileData(
        icon: Icons.format_list_numbered,
        title: 'Lig',
        value: _quickStandingsValue(quick.standings),
        detail: quick.standings.summary,
      ),
      _QuickContextTileData(
        icon: Icons.compare_arrows,
        title: 'H2H',
        value: quick.h2h.matches > 0 ? '${quick.h2h.matches} mac' : 'Veri yok',
        detail: quick.h2h.summary,
      ),
      _QuickContextTileData(
        icon: Icons.flag,
        title: 'Anlam',
        value: quick.available ? 'Baglam' : 'Bekleniyor',
        detail: quick.stakes.summary,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.35,
      ),
      itemBuilder: (context, index) => _QuickContextTile(data: tiles[index]),
    );
  }
}

class _QuickContextTileData {
  final IconData icon;
  final String title;
  final String value;
  final String detail;

  const _QuickContextTileData({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });
}

class _QuickContextTile extends StatelessWidget {
  final _QuickContextTileData data;

  const _QuickContextTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, size: 16, color: context.colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: context.colors.textMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Text(
                    data.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _quickFormValue(WizardQuickForm form) {
  final home = form.home ?? '-';
  final away = form.away ?? '-';
  return '$home / $away';
}

String _quickStandingsValue(WizardQuickStandings standings) {
  final home = standings.homeRank == null ? '-' : '${standings.homeRank}.';
  final away = standings.awayRank == null ? '-' : '${standings.awayRank}.';
  return '$home / $away';
}

class _DeckReason extends StatelessWidget {
  final WizardCard card;

  const _DeckReason({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt, size: 18, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.colors.textMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckProgress extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final bool canUndo;
  final VoidCallback onUndo;

  const _DeckProgress({
    required this.currentIndex,
    required this.totalCount,
    required this.canUndo,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hizli analiz',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textHigh,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$currentIndex / $totalCount mac',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(Icons.undo),
          tooltip: 'Geri al',
        ),
      ],
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  final String label;
  final Color color;
  final Alignment alignment;
  final double opacity;

  const _SwipeStamp({
    required this.label,
    required this.color,
    required this.alignment,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    final left = alignment == Alignment.topLeft ? 12.0 : null;
    final right = alignment == Alignment.topRight ? 12.0 : null;
    final center = alignment == Alignment.topCenter;
    return Positioned(
      top: -38,
      left: center ? 0 : left,
      right: center ? 0 : right,
      child: Align(
        alignment: center ? Alignment.topCenter : Alignment.center,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: alignment == Alignment.topLeft
                ? -0.12
                : alignment == Alignment.topRight
                    ? 0.12
                    : 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color, width: 2),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool large;
  final VoidCallback onPressed;

  const _DeckActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 62.0 : 54.0;
    return SizedBox(
      width: size,
      height: size,
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: large ? 30 : 24),
      ),
    );
  }
}

class _DeckFinished extends StatelessWidget {
  final int reviewedCount;
  final VoidCallback onRestart;

  const _DeckFinished({
    required this.reviewedCount,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.done_all, size: 58, color: context.colors.success),
          const SizedBox(height: 18),
          Text(
            'Tarama tamamlandi',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$reviewedCount mac hizli analizden gecti.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textMedium),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh),
            label: const Text('Yeniden tara'),
          ),
        ],
      ),
    );
  }
}

class _DeckError extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const _DeckError({
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 130),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 46, color: context.colors.error),
          const SizedBox(height: 14),
          Text(
            'Kart yuklenemedi',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.bold,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onSkip,
                child: const Text('Gec'),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _decisionColor(BuildContext context, String decision) {
  switch (decision) {
    case 'PASS':
      return context.colors.error;
    case 'CONSIDER':
      return context.colors.success;
    default:
      return context.colors.primary;
  }
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
      height: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Mac sec',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.colors.textHigh,
              ),
            ),
          ),
          Expanded(
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
                    width: 254,
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
                        const SizedBox(width: 8),
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
                                        size: 14,
                                        color: context.colors.primary),
                                    const SizedBox(width: 4),
                                  ],
                                  Flexible(
                                    child: Text(
                                      _selectorSubtitle(
                                          match, item.statusLabel),
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
          ),
        ],
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
      padding: const EdgeInsets.all(16),
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
              _Metric(label: 'Guven', value: '${report.confidence}'),
              const SizedBox(width: 10),
              _Metric(label: 'Risk', value: report.riskLevel.toUpperCase()),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${report.match.homeTeam} - ${report.match.awayTeam}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _HeaderChip(
                icon: Icons.sports_soccer,
                text: _matchScoreText(report.match),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeaderChip(
                  icon: Icons.schedule,
                  text: _matchStatusText(report.match),
                ),
              ),
            ],
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
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: report.confidence.clamp(0, 100) / 100,
              minHeight: 6,
              backgroundColor: context.colors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.textMedium),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textMedium,
              ),
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

  StoreProduct? _findProduct(List<StoreProduct> products, String productCode) {
    for (final product in products) {
      if (product.productCode == productCode) return product;
    }
    return null;
  }

  Future<void> _buyProduct(StoreProduct product) async {
    setState(() => _isPurchasing = true);
    try {
      final result = await ref
          .read(storeServiceProvider)
          .buyStoreItem(product.productCode);
      if (result.newBalance != null) {
        ref
            .read(walletBalanceProvider.notifier)
            .setBalanceFromServer(result.newBalance!);
      } else {
        await ref.read(walletBalanceProvider.notifier).refreshBalance();
      }
      await ref.read(entitlementsProvider.notifier).refresh();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.title} aktif edildi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceAll('Exception: ', '')),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
            StoreProduct? product =
                _findProduct(products, 'ai_premium_monthly') ??
                    _findProduct(products, 'ai_premium_base');
            for (final item in products) {
              if (product != null) break;
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
