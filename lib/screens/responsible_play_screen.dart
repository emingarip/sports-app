import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/bankroll_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_shell.dart';

/// Responsible play, as a place rather than a footnote.
///
/// The legal/ethical frame (roadmap 0.2) promises loss-chasing warnings, a
/// cooling-off suggestion after a losing run and an 18+ statement. The cooling
/// mechanism was already implemented in [CoolingModeNotifier] but the only way
/// to reach it was a bankroll-screen button, and the only visible statement was
/// two lines of 11px grey text at the bottom of four screens. This screen gives
/// the commitment somewhere to live - and store review looks for exactly this.
class ResponsiblePlayScreen extends ConsumerWidget {
  const ResponsiblePlayScreen({super.key});

  static const List<({String name, String detail, String url})> _helplines = [
    (
      name: 'Yeşilay Danışmanlık Merkezi (YEDAM)',
      detail: 'Ücretsiz, gizli danışmanlık · 115',
      url: 'https://yedam.org.tr',
    ),
    (
      name: 'Kumar Bağımlılığı Bilgi Hattı',
      detail: 'Alo 191 Uyuşturucu ve Bağımlılıkla Mücadele',
      url: 'tel:191',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final coolingUntil = ref.watch(coolingModeProvider).value;
    final coolingActive =
        coolingUntil != null && coolingUntil.isAfter(DateTime.now());

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Sorumlu oyun',
          style: TextStyle(
            color: colors.textHigh,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ResponsiveShell(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _AgeStatement(),
            const SizedBox(height: 16),
            _CoolingCard(
              coolingUntil: coolingActive ? coolingUntil : null,
              onStart: (duration) => ref
                  .read(coolingModeProvider.notifier)
                  .startCooling(duration: duration),
              onStop: () => ref.read(coolingModeProvider.notifier).stopCooling(),
            ),
            const SizedBox(height: 16),
            const _WarningSigns(),
            const SizedBox(height: 16),
            const _HelpCard(helplines: _helplines),
          ],
        ),
      ),
    );
  }
}

class _AgeStatement extends StatelessWidget {
  const _AgeStatement();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '18+',
                  style: TextStyle(
                    color: colors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bu uygulama bahis oynatmaz',
                  style: TextStyle(
                    color: colors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Boskale bir analiz ve istatistik platformudur. Uygulama içinde '
            'para akışı yoktur, kupon oynatılmaz ve hiçbir bahis sitesine '
            'yönlendirme yapılmaz. Türkiye\'de sabit ihtimalli bahis yalnızca '
            'Spor Toto lisanslı operatörler üzerinden oynanabilir. '
            'Uygulamadaki K-Coin ekonomisi tamamen sanaldır ve gerçek para ile '
            'hiçbir noktada birleşmez.',
            style: TextStyle(
              color: colors.textMedium,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoolingCard extends StatelessWidget {
  const _CoolingCard({
    required this.coolingUntil,
    required this.onStart,
    required this.onStop,
  });

  final DateTime? coolingUntil;
  final void Function(Duration duration) onStart;
  final VoidCallback onStop;

  static const List<({String label, Duration duration})> _options = [
    (label: '24 saat', duration: Duration(hours: 24)),
    (label: '3 gün', duration: Duration(days: 3)),
    (label: '1 hafta', duration: Duration(days: 7)),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final until = coolingUntil;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_outline,
                  size: 18, color: colors.textMedium),
              const SizedBox(width: 8),
              Text(
                'Soğuma modu',
                style: TextStyle(
                  color: colors.textHigh,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            until == null
                ? 'Ara vermek istersen kupon paylaşımını geçici olarak '
                    'kapatabilirsin. Bülteni ve analizleri görmeye devam '
                    'edersin.'
                : 'Soğuma modu ${_formatUntil(until)} tarihine kadar açık. '
                    'Kupon paylaşımı bu süre boyunca kapalı.',
            style: TextStyle(
              color: colors.textMedium,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (until == null)
            Wrap(
              spacing: 8,
              children: [
                for (final option in _options)
                  OutlinedButton(
                    onPressed: () => onStart(option.duration),
                    child: Text(option.label),
                  ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Soğuma modunu kapat'),
            ),
        ],
      ),
    );
  }

  static String _formatUntil(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:'
        '${two(local.minute)}';
  }
}

class _WarningSigns extends StatelessWidget {
  const _WarningSigns();

  static const List<String> _signs = [
    'Kaybettiğini geri almak için normalden yüksek tutarla oynamak',
    'Planladığından daha sık ya da daha uzun süre oynamak',
    'Oynadığını yakınlarından saklamak',
    'Borçlanarak ya da ayrılmış parayı kullanarak oynamak',
    'Oynamadığında huzursuz ya da gergin hissetmek',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DİKKAT EDİLECEK İŞARETLER',
            style: TextStyle(
              color: colors.textLow,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          for (final sign in _signs)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.textLow,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sign,
                      style: TextStyle(
                        color: colors.textMedium,
                        fontSize: 13,
                        height: 1.45,
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

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.helplines});

  final List<({String name, String detail, String url})> helplines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DESTEK AL',
            style: TextStyle(
              color: colors.textLow,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          for (final line in helplines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _open(line.url),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    Icon(Icons.support_agent,
                        size: 18, color: colors.textMedium),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.name,
                            style: TextStyle(
                              color: colors.textHigh,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            line.detail,
                            style: TextStyle(
                              color: colors.textMedium,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new, size: 15, color: colors.textLow),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
