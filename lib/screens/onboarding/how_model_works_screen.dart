import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'components/onboarding_bottom_bar.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'onboarding_ready_screen.dart';

/// The onboarding step the product pivot never got.
///
/// The other five screens onboard a *fan*: pick teams, pick leagues, allow
/// notifications. None of them mention the bulletin, the coupon or the model,
/// so a new user landed on a screen full of odds and green check marks with no
/// idea what any of it claimed. Three cards and an 18+ acknowledgement fix
/// that in about fifteen seconds.
class HowModelWorksScreen extends StatelessWidget {
  const HowModelWorksScreen({super.key});

  static const List<({IconData icon, String title, String body})> _cards = [
    (
      icon: Icons.list_alt,
      title: 'Bülteni izler',
      body: 'Günün iddaa bülteni ve her seçimin oranı saat başı kaydedilir.',
    ),
    (
      icon: Icons.calculate_outlined,
      title: 'Kendi olasılığını hesaplar',
      body: 'Takımların geçmiş maçlarındaki gol üretimi ve savunması '
          'modellenir; her seçim için bir yüzde çıkar.',
    ),
    (
      icon: Icons.check_circle_outline,
      title: 'Ucuz oranı işaretler',
      body: 'Model bir seçime oranın fiyatladığından yüksek şans veriyorsa '
          '"değerli oran" der. Değer yoksa bunu da söyler.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 0.83),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                children: [
                  const StepLabel(step: 5),
                  const SizedBox(height: 12),
                  Text(
                    'Kazanacak maçı değil,\nucuz oranı söyler.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: colors.textHigh,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final card in _cards) ...[
                    _ModelStepCard(
                      icon: card.icon,
                      title: card.title,
                      body: card.body,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  const _AgeNotice(),
                ],
              ),
            ),
            OnboardingBottomBar(
              primaryText: 'Anladım, başlayalım',
              onPrimaryPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OnboardingReadyScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelStepCard extends StatelessWidget {
  const _ModelStepCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: colors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.textMedium,
                    fontSize: 13,
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

class _AgeNotice extends StatelessWidget {
  const _AgeNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '18+',
              style: TextStyle(
                color: colors.error,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Boskale bahis oynatmaz, para akışı barındırmaz. Analiz ve '
              'istatistik sunar; oynama kararı ve işlemi sana ait.',
              style: TextStyle(
                color: colors.textMedium,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
