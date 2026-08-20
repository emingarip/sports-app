import 'package:flutter/material.dart';

import '../models/model_verdict.dart';
import '../theme/app_theme.dart';
import '../widgets/bulletin/bulletin_disclaimer.dart';
import '../widgets/responsive_shell.dart';

/// Answers the question the interface used to leave hanging: what does
/// "değerli oran" mean, and why should anyone trust it?
///
/// Reachable from the info button on every model card and from onboarding.
/// Deliberately written without EV, Kelly or lambda in the body text - those
/// belong in the collapsed detail section of a specific prediction, not in the
/// explanation of the idea.
class ModelExplainerScreen extends StatelessWidget {
  const ModelExplainerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Model nasıl çalışır?',
          style: TextStyle(
            color: context.colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ResponsiveShell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: const [
            _Lead(),
            SizedBox(height: 20),
            _Step(
              index: '1',
              title: 'Bülteni ve oranları izler',
              body: 'Günün iddaa bülteni ve her seçimin oranı saat başı '
                  'kaydedilir. Oranın nereden nereye geldiğini de görebilirsin.',
            ),
            _Step(
              index: '2',
              title: 'Kendi olasılığını hesaplar',
              body: 'Takımların geçmiş maçlarındaki gol üretimi ve gol yeme '
                  'eğilimi, yakın maçlara daha çok ağırlık verilerek '
                  'modellenir. Model buradan her seçim için bir yüzde üretir.',
            ),
            _Step(
              index: '3',
              title: 'İkisini karşılaştırır',
              body: 'Model bir seçime oranın fiyatladığından belirgin olarak '
                  'daha yüksek şans veriyorsa, o oran "değerli" sayılır. '
                  'Değer bulunamazsa model bunu da söyler - "oynanmaz" da bir '
                  'analiz sonucudur.',
            ),
            SizedBox(height: 12),
            _VerdictLegend(),
            SizedBox(height: 20),
            _HonestyNote(),
            SizedBox(height: 8),
            BulletinDisclaimer(),
          ],
        ),
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Bu uygulama "kazanacak maçı" söylemez. Oranın, maçın gerçek '
      'ihtimaline göre ucuz mu pahalı mı olduğunu söyler.',
      style: TextStyle(
        color: context.colors.textHigh,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.45,
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.title, required this.body});

  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              index,
              style: TextStyle(
                color: context.colors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: context.colors.textMedium,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
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

/// The three badges a user will actually see on a card, explained in one line
/// each. Reuses [ModelVerdict] so the legend can never drift from the cards.
class _VerdictLegend extends StatelessWidget {
  const _VerdictLegend();

  @override
  Widget build(BuildContext context) {
    const verdicts = [
      ModelVerdict.value,
      ModelVerdict.neutral,
      ModelVerdict.avoid,
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KARTLARDAKİ İŞARETLER',
            style: TextStyle(
              color: context.colors.textLow,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          for (final verdict in verdicts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(verdict.icon, size: 17, color: verdict.color(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verdict.label,
                          style: TextStyle(
                            color: verdict.color(context),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          verdict.explanation,
                          style: TextStyle(
                            color: context.colors.textMedium,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
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

/// Principle 0.1.1 says calibration beats accuracy and that the honest state
/// of the model is shown to the user. Right now the honest state is "not yet
/// verified", so the screen says exactly that.
class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.science_outlined,
                size: 16,
                color: context.colors.textMedium,
              ),
              const SizedBox(width: 6),
              Text(
                'Model şu an beta',
                style: TextStyle(
                  color: context.colors.textHigh,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const ModelBetaChip(dense: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Modelin geçmiş performansı henüz yeterli örneklemle ölçülmedi. '
            'Ölçüm tamamlanana kadar işaretleri bir fikir olarak değerlendir, '
            'kesin bir tavsiye olarak değil. Sonuçlar ölçülünce burada '
            'yayınlanacak.',
            style: TextStyle(
              color: context.colors.textMedium,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
