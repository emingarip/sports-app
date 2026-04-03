import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

import 'ads/ad_helper_stub.dart'
    if (dart.library.io) 'ads/ad_helper_mobile.dart';

import '../services/supabase_service.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  /// Returns empty when rewarded ads are not configured for this build.
  String get rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const String.fromEnvironment('ADMOB_ANDROID_REWARDED_ID');
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const String.fromEnvironment('ADMOB_IOS_REWARDED_ID');
    }
    return '';
  }

  Future<void> initialize() async {
    if (!kIsWeb && rewardedAdUnitId.isNotEmpty) {
      await NativeAdHelper.initialize();
    } else {
      debugPrint('Rewarded ads disabled for this build.');
    }
  }

  void loadRewardedAd() {
    if (kIsWeb) {
      debugPrint('AdMob Web fallback strictly activated.');
      return;
    }
    final unitId = rewardedAdUnitId;
    if (unitId.isNotEmpty) {
      NativeAdHelper.loadRewardedAd(unitId);
    }
  }

  void showRewardedAd(BuildContext context,
      {required Function onEarnedReward}) {
    if (kIsWeb) {
      _showWebDirectLinkAd(context, onEarnedReward: onEarnedReward);
      return;
    }
    if (rewardedAdUnitId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Rewarded ads are not configured for this build.')),
      );
      return;
    }

    NativeAdHelper.showRewardedAd(context, onEarnedReward: () {
      onEarnedReward();
      loadRewardedAd();
    });
  }

  void _showWebDirectLinkAd(BuildContext context,
      {required Function onEarnedReward}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final String? configuredLink =
        await SupabaseService().getAppSetting('adsterra_direct_link');

    if (context.mounted) {
      Navigator.of(context).pop();
    }

    const String defaultLink =
        'https://www.highcpmgate.com/example-adsterra-link';
    final url = Uri.parse(configuredLink ?? defaultLink);

    if (!await launchUrl(url, webOnlyWindowName: '_blank')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Failed to load sponsor video. Please check popup blockers.')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WebAdTimerDialog(onEarnedReward: onEarnedReward),
    );
  }
}

class _WebAdTimerDialog extends StatefulWidget {
  final Function onEarnedReward;
  const _WebAdTimerDialog({required this.onEarnedReward});

  @override
  State<_WebAdTimerDialog> createState() => _WebAdTimerDialogState();
}

class _WebAdTimerDialogState extends State<_WebAdTimerDialog> {
  int _timeLeft = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 1) {
        setState(() => _timeLeft--);
      } else {
        _timer?.cancel();
        if (mounted) {
          Navigator.of(context).pop();
          widget.onEarnedReward();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: context.colors.primaryContainer.withValues(alpha: 0.5),
              width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ondemand_video_rounded,
                color: context.colors.primaryContainer, size: 48),
            const SizedBox(height: 16),
            Text(
              'Sponsor Message',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Lütfen sponsor bağlantısını kapatmadan $_timeLeft saniye açık tutun.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textMedium,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 64,
              width: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _timeLeft / 15,
                    strokeWidth: 6,
                    backgroundColor:
                        context.colors.outline.withValues(alpha: 0.2),
                    color: context.colors.primaryContainer,
                  ),
                  Center(
                    child: Text(
                      '$_timeLeft',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: context.colors.textHigh,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _timer?.cancel();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: context.colors.error.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Cancel & Lose Reward',
                    style: TextStyle(
                        color: context.colors.error,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
