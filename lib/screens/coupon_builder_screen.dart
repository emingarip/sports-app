import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coupon.dart';
import '../providers/bankroll_provider.dart';
import '../providers/coupon_provider.dart';
import '../providers/wallet_provider.dart';
import '../models/model_verdict.dart';
import '../theme/app_theme.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';
import '../widgets/responsive_shell.dart';

/// Analysis coupon builder: selections, combined odds vs combined model
/// probability, honest EV verdict, quarter-Kelly stake suggestion and the
/// server-authoritative share flow.
class CouponBuilderScreen extends ConsumerStatefulWidget {
  const CouponBuilderScreen({super.key, this.embedded = false});

  /// When hosted inside the Kupon tab the surrounding shell already supplies
  /// the app bar and title, so the screen drops its own chrome.
  final bool embedded;

  @override
  ConsumerState<CouponBuilderScreen> createState() =>
      _CouponBuilderScreenState();
}

class _CouponBuilderScreenState extends ConsumerState<CouponBuilderScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _stakeController = TextEditingController();
  bool _isPublic = true;
  bool _sharing = false;

  @override
  void dispose() {
    _titleController.dispose();
    _stakeController.dispose();
    super.dispose();
  }

  Future<void> _share(CouponDraft draft) async {
    final stakeText = _stakeController.text.trim();
    final stake = stakeText.isEmpty ? null : int.tryParse(stakeText);
    if (stakeText.isNotEmpty && (stake == null || stake <= 0)) {
      _showSnack('Geçersiz K-Coin miktarı.');
      return;
    }

    setState(() => _sharing = true);
    try {
      await ref.read(couponServiceProvider).shareCoupon(
            draft,
            title: _titleController.text.trim().isEmpty
                ? null
                : _titleController.text.trim(),
            stakeKcoin: stake,
            isPublic: _isPublic,
          );
      ref.read(couponDraftProvider.notifier).clear();
      ref.invalidate(myCouponsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Kupon paylaşıldı. Sonuçlar maçlar bitince işlenecek.');
    } catch (error) {
      _showSnack('Kupon paylaşılamadı: $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(couponDraftProvider);
    final balance = ref.watch(walletBalanceProvider);
    final coolingUntil = ref.watch(coolingModeProvider).value;
    final coolingActive =
        coolingUntil != null && coolingUntil.isAfter(DateTime.now());

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Analiz Kuponum'),
              actions: [
                if (!draft.isEmpty)
                  IconButton(
                    tooltip: 'Kuponu temizle',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(couponDraftProvider.notifier).clear(),
                  ),
              ],
            ),
      body: ResponsiveShell(
        child: draft.isEmpty
            ? _EmptyCoupon(colors: context.colors)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final selection in draft.selections)
                    _SelectionTile(
                      selection: selection,
                      onRemove: () => ref
                          .read(couponDraftProvider.notifier)
                          .removeSelection(selection.selectionId),
                    ),
                  const SizedBox(height: 8),
                  _SummaryCard(draft: draft, balance: balance),
                  if (draft.hasCorrelatedSelections) ...[
                    const SizedBox(height: 8),
                    const _WarningBanner(
                      icon: Icons.link,
                      text:
                          'Aynı maçtan birden fazla seçim var: seçimler bağımlı '
                          'olduğu için kombine olasılık olduğundan iyimser '
                          'hesaplanır.',
                    ),
                  ],
                  if (draft.hasStartedSelections) ...[
                    const SizedBox(height: 8),
                    const _WarningBanner(
                      icon: Icons.schedule,
                      text: 'Başlamış maç içeren kupon paylaşılamaz. İlgili '
                          'seçimleri çıkarın.',
                    ),
                  ],
                  if (coolingActive) ...[
                    const SizedBox(height: 8),
                    const _WarningBanner(
                      icon: Icons.ac_unit,
                      text: 'Soğuma modu açık: kupon paylaşımı geçici olarak '
                          'kilitli. Bankroll asistanından yönetebilirsin.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  _ShareForm(
                    titleController: _titleController,
                    stakeController: _stakeController,
                    isPublic: _isPublic,
                    onPublicChanged: (value) =>
                        setState(() => _isPublic = value),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sharing ||
                              draft.hasStartedSelections ||
                              coolingActive
                          ? null
                          : () => _share(draft),
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share),
                      label:
                          Text(_sharing ? 'Paylaşılıyor...' : 'Kuponu Paylaş'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const BulletinDisclaimer(),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class _EmptyCoupon extends StatelessWidget {
  final AppColors colors;

  const _EmptyCoupon({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 56, color: colors.textLow),
            const SizedBox(height: 12),
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
              'Bültendeki oran kutularına dokunarak analiz kuponuna '
              'seçim ekleyebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textMedium, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final CouponSelection selection;
  final VoidCallback onRemove;

  const _SelectionTile({required this.selection, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final modelProbability = selection.modelProbability;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selection.matchLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textHigh,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${selection.marketName}: ${selection.selectionLabel}',
                  style: TextStyle(
                    color: colors.textMedium,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (modelProbability != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Model olasılığı: %${(modelProbability * 100).toStringAsFixed(0)}',
                    style: TextStyle(color: colors.textLow, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            selection.odds.toStringAsFixed(2),
            style: TextStyle(
              color: colors.textHigh,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: colors.textLow),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final CouponDraft draft;
  final int? balance;

  const _SummaryCard({required this.draft, required this.balance});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final expectedValue = draft.expectedValue;
    final modelProbability = draft.combinedModelProb;
    final kelly = draft.kellyFraction();

    // The verdict is the same computation as before; only the wording changed.
    // A bettor does not read "EV %-4.2" - the honest sentence underneath it was
    // always the useful part (principle 0.1.6). The percentage moves into the
    // detail row below so nothing is lost.
    final verdict = ModelVerdict.fromExpectedValue(expectedValue);
    final verdictColor = verdict.color(context);
    final verdictText = switch (expectedValue) {
      null => 'Bazı seçimler için model tahmini yok; kuponun tamamı '
          'değerlendirilemiyor.',
      < 0 => 'Dürüst uyarı: modele göre bu kupon uzun vadede kaybettirir.',
      >= ModelVerdict.valueThreshold =>
        'Modele göre bu kupon oranların fiyatladığından daha iyi duruyor.',
      _ => 'Model ile oranlar birbirine yakın; belirgin bir avantaj yok.',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            label: 'Toplam Oran',
            value: draft.totalOdds.toStringAsFixed(2),
          ),
          _SummaryRow(
            label: 'Modele göre tutma şansı',
            value: modelProbability == null
                ? '—'
                : '%${(modelProbability * 100).toStringAsFixed(1)}',
          ),
          _SummaryRow(
            label: 'Oranlara göre tutma şansı',
            value: '%${(draft.combinedImpliedProb * 100).toStringAsFixed(1)}',
          ),
          if (kelly != null && balance != null)
            _SummaryRow(
              // "Ceyrek Kelly" is the method's name, not a recommendation a
              // reader can act on. The bankroll share is.
              label: 'Önerilen risk',
              value: kelly <= 0
                  ? 'Bu kuponu oynama'
                  : '${(kelly * balance!).floor()} K-Coin '
                      '(kasanın %${(kelly * 100).toStringAsFixed(1)} kadarı)',
            ),
          if (expectedValue != null)
            _SummaryRow(
              label: 'Beklenen değer (EV)',
              value: '${expectedValue >= 0 ? '+' : ''}'
                  '%${(expectedValue * 100).toStringAsFixed(1)}',
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: verdictColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(verdict.icon, size: 16, color: verdictColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    verdictText,
                    style: TextStyle(
                      color: verdictColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const ModelBetaChip(dense: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMedium,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.textHigh,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WarningBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: colors.onErrorContainer,
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

class _ShareForm extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController stakeController;
  final bool isPublic;
  final ValueChanged<bool> onPublicChanged;

  const _ShareForm({
    required this.titleController,
    required this.stakeController,
    required this.isPublic,
    required this.onPublicChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: titleController,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Kupon başlığı (opsiyonel)',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: stakeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'K-Coin miktarı (opsiyonel, sanal)',
            helperText:
                'K-Coin sanaldır; sicilin ROI ve CLV ile ölçülür, parayla değil.',
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: isPublic,
          onChanged: onPublicChanged,
          title: Text(
            'Herkese açık paylaş',
            style: TextStyle(
              color: colors.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'Açık kuponlar tipster siciline işlenir ve lider tablosunda sayılır.',
            style: TextStyle(color: colors.textMedium, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
