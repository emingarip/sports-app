import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bulletin.dart';
import '../providers/bulletin_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';
import '../widgets/bulletin/bulletin_market_comparison.dart';
import '../widgets/bulletin/bulletin_model_view_card.dart';
import '../widgets/bulletin/bulletin_odds_movement.dart';
import '../widgets/responsive_shell.dart';

const List<String> _turkishMonthsShort = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// "Maç Analiz Merkezi": model view, model-vs-market comparison and odds
/// movement for a single bulletin match.
class BulletinMatchAnalysisScreen extends ConsumerWidget {
  final BulletinMatch match;

  const BulletinMatchAnalysisScreen({super.key, required this.match});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictionAsync = ref.watch(bulletinPredictionProvider(match.id));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: context.colors.textHigh,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'MAÇ ANALİZ MERKEZİ',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: ResponsiveShell(
        maxWidth: ResponsiveShell.wideMaxWidth,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            predictionAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => _buildPredictionError(context, ref),
              data: (prediction) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BulletinModelViewCard(match: match, prediction: prediction),
                  if (prediction != null) ...[
                    const SizedBox(height: 20),
                    BulletinMarketComparison(
                      match: match,
                      prediction: prediction,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            BulletinOddsMovement(match: match),
            const BulletinDisclaimer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  match.competitionName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textMedium,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (match.mbs != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'MBS ${match.mbs}',
                    style: TextStyle(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatKickoff(match.kickoffAt),
            style: TextStyle(
              color: context.colors.textLow,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  match.homeTeam,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'vs',
                  style: TextStyle(
                    color: context.colors.textLow,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  match.awayTeam,
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionError(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: context.colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            'Model tahmini yüklenemedi.',
            style: TextStyle(
              color: context.colors.error,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                ref.invalidate(bulletinPredictionProvider(match.id)),
            child: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }

  String _formatKickoff(DateTime? kickoffAt) {
    final local = kickoffAt?.toLocal();
    if (local == null) return 'Saat bilgisi yok';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '${local.day} ${_turkishMonthsShort[local.month - 1]} • $time';
  }
}
