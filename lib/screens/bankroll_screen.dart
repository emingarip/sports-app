import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coupon.dart';
import '../providers/bankroll_provider.dart';
import '../providers/coupon_provider.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';
import '../widgets/responsive_shell.dart';

/// Bankroll & discipline assistant: skill metrics (flat ROI, CLV), Kelly
/// stake calculator and responsible-play guardrails (loss-streak warnings,
/// cooling mode).
class BankrollScreen extends ConsumerStatefulWidget {
  const BankrollScreen({super.key});

  @override
  ConsumerState<BankrollScreen> createState() => _BankrollScreenState();
}

class _BankrollScreenState extends ConsumerState<BankrollScreen> {
  final TextEditingController _probabilityController = TextEditingController();
  final TextEditingController _oddsController = TextEditingController();

  @override
  void dispose() {
    _probabilityController.dispose();
    _oddsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final balance = ref.watch(walletBalanceProvider);
    final couponsAsync = ref.watch(myCouponsProvider);
    final coolingAsync = ref.watch(coolingModeProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Bankroll Asistanı')),
      body: ResponsiveShell(
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(myCouponsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BalanceCard(balance: balance),
              const SizedBox(height: 12),
              couponsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, stack) => _InfoCard(
                  icon: Icons.error_outline,
                  color: colors.error,
                  text: 'Kupon geçmişi yüklenemedi.',
                ),
                data: (coupons) => _PerformanceSection(
                  stats: BankrollStats.fromCoupons(coupons),
                  coupons: coupons,
                ),
              ),
              const SizedBox(height: 12),
              _CoolingCard(coolingUntil: coolingAsync.value),
              const SizedBox(height: 12),
              _KellyCalculator(
                probabilityController: _probabilityController,
                oddsController: _oddsController,
                balance: balance,
              ),
              const SizedBox(height: 12),
              const BulletinDisclaimer(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int? balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: colors.accent, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sanal Bankroll (K-Coin)',
                  style: TextStyle(
                    color: colors.textMedium,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  balance?.toString() ?? '—',
                  style: TextStyle(
                    color: colors.textHigh,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
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

class _PerformanceSection extends StatelessWidget {
  final BankrollStats stats;
  final List<AnalysisCoupon> coupons;

  const _PerformanceSection({required this.stats, required this.coupons});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PERFORMANS',
                style: TextStyle(
                  color: colors.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetricTile(
                    label: 'Sonuçlanan',
                    value: '${stats.settledCount}',
                  ),
                  _MetricTile(
                    label: 'İsabet',
                    value: stats.winRate == null
                        ? '—'
                        : '%${(stats.winRate! * 100).toStringAsFixed(0)}',
                  ),
                  _MetricTile(
                    label: 'ROI (flat)',
                    value: stats.flatRoi == null
                        ? '—'
                        : '%${(stats.flatRoi! * 100).toStringAsFixed(1)}',
                    valueColor: stats.flatRoi == null
                        ? null
                        : (stats.flatRoi! >= 0 ? colors.success : colors.error),
                  ),
                  _MetricTile(
                    label: 'Ort. CLV',
                    value: stats.avgClv == null
                        ? '—'
                        : '%${(stats.avgClv! * 100).toStringAsFixed(1)}',
                    valueColor: stats.avgClv == null
                        ? null
                        : (stats.avgClv! >= 0 ? colors.success : colors.error),
                  ),
                ],
              ),
              if (!stats.hasEnoughSample) ...[
                const SizedBox(height: 10),
                Text(
                  'Yetersiz örneklem: metriklerin anlamlı olması için en az '
                  '10 sonuçlanmış kupon gerekir. CLV (kapanış oranını yenme), '
                  'uzun vadeli becerinin en güvenilir ölçüsüdür.',
                  style: TextStyle(color: colors.textLow, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (stats.currentLossStreak >= 3) ...[
          const SizedBox(height: 8),
          _InfoCard(
            icon: Icons.warning_amber,
            color: context.colors.error,
            text: 'Üst üste ${stats.currentLossStreak} kayıp. Kayıp sonrası '
                'karar kalitesi düşer; bir süre ara vermeyi ve soğuma modunu '
                'açmayı düşün.',
          ),
        ],
        if (stats.stakeEscalation) ...[
          const SizedBox(height: 8),
          _InfoCard(
            icon: Icons.trending_up,
            color: context.colors.error,
            text: 'Son kuponlarında miktarları art arda yükseltmişsin. Bu, '
                'kayıp kovalama desenidir — Kelly önerisine dön ve sabit '
                'disiplinli miktarlarla oyna.',
          ),
        ],
        if (coupons.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'SON KUPONLAR',
            style: TextStyle(
              color: colors.textMedium,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          for (final coupon in coupons.take(10)) _CouponRow(coupon: coupon),
        ],
      ],
    );
  }
}

class _CouponRow extends StatelessWidget {
  final AnalysisCoupon coupon;

  const _CouponRow({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (statusColor, statusLabel) = switch (coupon.status) {
      'won' => (colors.success, 'KAZANDI'),
      'lost' => (colors.error, 'KAYBETTİ'),
      'void' => (colors.textLow, 'İPTAL'),
      _ => (colors.textMedium, 'BEKLİYOR'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.title?.isNotEmpty == true
                      ? coupon.title!
                      : '${coupon.selections.length} maçlı kupon',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Oran ${coupon.totalOdds.toStringAsFixed(2)}'
                  '${coupon.avgClv != null ? ' • CLV %${(coupon.avgClv! * 100).toStringAsFixed(1)}' : ''}'
                  '${coupon.stakeKcoin != null ? ' • ${coupon.stakeKcoin} K-Coin' : ''}',
                  style: TextStyle(color: colors.textLow, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoolingCard extends ConsumerWidget {
  final DateTime? coolingUntil;

  const _CoolingCard({required this.coolingUntil});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final active =
        coolingUntil != null && coolingUntil!.isAfter(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? colors.accent.withValues(alpha: 0.6)
              : colors.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.ac_unit, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'SOĞUMA MODU',
                style: TextStyle(
                  color: colors.textMedium,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            active
                ? 'Soğuma modu açık: '
                    '${coolingUntil!.toLocal().day.toString().padLeft(2, '0')}.'
                    '${coolingUntil!.toLocal().month.toString().padLeft(2, '0')} '
                    '${coolingUntil!.toLocal().hour.toString().padLeft(2, '0')}:'
                    '${coolingUntil!.toLocal().minute.toString().padLeft(2, '0')} '
                    'saatine kadar kupon paylaşımı kapalı.'
                : 'Kendini yorgun, tilt olmuş veya kayıp kovalarken '
                    'yakaladıysan 24 saatliğine kupon paylaşımını kilitle.',
            style: TextStyle(color: colors.textMedium, fontSize: 13),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: Icon(active ? Icons.lock_open : Icons.lock_outline, size: 16),
            label: Text(active ? 'Soğumayı bitir' : '24 saat soğuma başlat'),
            onPressed: () {
              final notifier = ref.read(coolingModeProvider.notifier);
              if (active) {
                notifier.stopCooling();
              } else {
                notifier.startCooling();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _KellyCalculator extends StatefulWidget {
  final TextEditingController probabilityController;
  final TextEditingController oddsController;
  final int? balance;

  const _KellyCalculator({
    required this.probabilityController,
    required this.oddsController,
    required this.balance,
  });

  @override
  State<_KellyCalculator> createState() => _KellyCalculatorState();
}

class _KellyCalculatorState extends State<_KellyCalculator> {
  double? _kelly;

  void _recompute() {
    final probability =
        double.tryParse(widget.probabilityController.text.replaceAll(',', '.'));
    final odds =
        double.tryParse(widget.oddsController.text.replaceAll(',', '.'));
    if (probability == null || odds == null || odds <= 1.0) {
      setState(() => _kelly = null);
      return;
    }
    final p =
        (probability > 1 ? probability / 100.0 : probability).clamp(0.0, 1.0);
    final b = odds - 1.0;
    final full = (b * p - (1.0 - p)) / b;
    setState(() => _kelly = full <= 0 ? 0.0 : full * 0.25);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final balance = widget.balance;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KELLY HESAPLAYICI (ÇEYREK)',
            style: TextStyle(
              color: colors.textMedium,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.probabilityController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _recompute(),
                  decoration: const InputDecoration(
                    labelText: 'Olasılık (%)',
                    hintText: '55',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.oddsController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _recompute(),
                  decoration: const InputDecoration(
                    labelText: 'Oran',
                    hintText: '2.10',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            switch (_kelly) {
              null => 'Olasılık ve oran gir; önerilen miktarı gör.',
              0.0 =>
                'Edge yok: modele göre bu bahsin beklenen değeri negatif — oynama.',
              _ => 'Önerilen miktar: bankroll\'un %${(_kelly! * 100).toStringAsFixed(1)}\'i'
                  '${balance != null ? ' (~${(_kelly! * balance).floor()} K-Coin)' : ''}. '
                  'Çeyrek Kelly, tahmin hatasına karşı bilinçli olarak temkinlidir.',
            },
            style: TextStyle(
              color: _kelly == 0.0 ? colors.error : colors.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? colors.textHigh,
              fontWeight: FontWeight.w900,
              fontSize: 16,
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
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
