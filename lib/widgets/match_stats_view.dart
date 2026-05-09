import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers/ai_sport_agent_stats_provider.dart';
import '../models/match.dart' as model;
import '../models/match_stats.dart';
import '../theme/app_theme.dart';

class MatchStatsView extends ConsumerStatefulWidget {
  final model.Match match;

  const MatchStatsView({super.key, required this.match});

  @override
  ConsumerState<MatchStatsView> createState() => _MatchStatsViewState();
}

class _MatchStatsViewState extends ConsumerState<MatchStatsView>
    with SingleTickerProviderStateMixin {
  late Future<MatchStatsReport> _statsFuture;
  late AnimationController _animController;
  late Animation<double> _animation;
  Timer? _retryTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _statsFuture =
        ref.read(aiSportAgentStatsProvider).fetchStats(widget.match.id);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _animation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
    _startLiveRetryTimer();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id) {
      _retryTimer?.cancel();
      _statsFuture =
          ref.read(aiSportAgentStatsProvider).fetchStats(widget.match.id);
      _startLiveRetryTimer();
    }
  }

  void _startLiveRetryTimer() {
    _retryTimer?.cancel();
    if (widget.match.status != model.MatchStatus.live) {
      return;
    }
    _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _isRefreshing) return;
      _refresh(silent: true);
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    _isRefreshing = true;
    final future =
        ref.read(aiSportAgentStatsProvider).fetchStats(widget.match.id);
    setState(() {
      _statsFuture = future;
    });
    if (!silent) {
      _animController
        ..reset()
        ..forward();
    }
    try {
      await future;
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<MatchStatsReport>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const _StatsEmptyState(
              title: 'Istatistikler yuklenemedi',
              message: 'Tekrar denemek icin asagi cek.',
            );
          }
          final report = snapshot.data;
          if (report == null || !report.hasData) {
            return _StatsEmptyState(
              title: widget.match.status == model.MatchStatus.live
                  ? 'Istatistik bekleniyor'
                  : 'Mac baslamadi',
              message: widget.match.status == model.MatchStatus.live
                  ? 'Canli mac verisi geldikce bu alan otomatik yenilenecek.'
                  : 'Istatistikler mac basladiktan sonra gorunur.',
            );
          }
          return AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 96),
                children: [
                  _StatsSummaryCard(report: report),
                  if (report.momentum.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _MomentumCard(report: report),
                  ],
                  const SizedBox(height: 20),
                  ...report.stats.map((stat) => _StatRow(
                        stat: stat,
                        animationValue: _animation.value,
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatsSummaryCard extends StatelessWidget {
  final MatchStatsReport report;

  const _StatsSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final updatedText = report.syncedAt == null
        ? 'Canli veri'
        : 'Guncelleme ${report.syncedAt!.toLocal().hour.toString().padLeft(2, '0')}:${report.syncedAt!.toLocal().minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Icon(Icons.bar_chart_rounded, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              updatedText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.colors.textMedium,
              ),
            ),
          ),
          _MiniCount(label: 'Shotmap', value: report.shotmapCount),
          const SizedBox(width: 8),
          _MiniCount(label: 'Rating', value: report.bestPlayersCount),
        ],
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  final String label;
  final int value;

  const _MiniCount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: context.colors.textMedium,
          ),
        ),
      ],
    );
  }
}

class _MomentumCard extends StatelessWidget {
  final MatchStatsReport report;

  const _MomentumCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final values = report.momentum.map((item) => item.value).toList();
    final homePressure = values.where((item) => item > 0).fold<double>(
          0,
          (sum, item) => sum + item.abs(),
        );
    final awayPressure = values.where((item) => item < 0).fold<double>(
          0,
          (sum, item) => sum + item.abs(),
        );
    final total = homePressure + awayPressure;
    final homeRatio = total == 0 ? 0.5 : homePressure / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOMENTUM',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: context.colors.textMedium,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Row(
              children: [
                Expanded(
                  flex: (homeRatio * 100).round().clamp(1, 99),
                  child: Container(height: 10, color: context.colors.primary),
                ),
                Expanded(
                  flex: ((1 - homeRatio) * 100).round().clamp(1, 99),
                  child: Container(height: 10, color: context.colors.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final MatchStatData stat;
  final double animationValue;

  const _StatRow({required this.stat, required this.animationValue});

  @override
  Widget build(BuildContext context) {
    final total = stat.total;
    var homeFlex = total == 0 ? 0.0 : stat.homeRatio * animationValue;
    var awayFlex = total == 0 ? 0.0 : stat.awayRatio * animationValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ValueText(value: stat.homeDisplay),
              Expanded(
                child: Text(
                  stat.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.textMedium,
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              _ValueText(value: stat.awayDisplay),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: homeFlex == 0.0 && total == 0
                        ? 0.0
                        : homeFlex.clamp(0.02, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: homeFlex > awayFlex
                            ? context.colors.primaryContainer
                            : context.colors.surfaceContainerHighest,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: awayFlex == 0.0 && total == 0
                        ? 0.0
                        : awayFlex.clamp(0.02, 1.0),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: awayFlex > homeFlex
                            ? context.colors.accent
                            : context.colors.surfaceContainerHighest,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  final String value;

  const _ValueText({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Text(
        value,
        style: TextStyle(
          color: context.colors.textHigh,
          fontFamily: 'Lexend',
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatsEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _StatsEmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 96),
      children: [
        Icon(Icons.query_stats_rounded,
            size: 46, color: context.colors.textMedium),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.colors.textMedium,
          ),
        ),
      ],
    );
  }
}
