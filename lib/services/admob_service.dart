import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

import 'ads/ad_helper_stub.dart' if (dart.library.io) 'ads/ad_helper_mobile.dart';

import '../services/supabase_service.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  /// Returns the ad unit ID for rewarded video. 
  /// ALWAYS use test ads during development to prevent account suspension.
  String get rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android Test Rewarded Ad Unit ID
      return const String.fromEnvironment('ADMOB_ANDROID_REWARDED_ID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS Test Rewarded Ad Unit ID
      return const String.fromEnvironment('ADMOB_IOS_REWARDED_ID', defaultValue: 'ca-app-pub-3940256099942544/1712485313');
    }
    return ''; // Web or unsupported
  }

  Future<void> initialize() async {
    if (!kIsWeb) {
      await NativeAdHelper.initialize();
    }
  }

  /// Pre-loads a rewarded ad so it's ready to explicitly display instantly when requested.
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

  /// Displays the ad and triggers the callback if the user finishes watching.
  void showRewardedAd(BuildContext context, {required Function onEarnedReward}) {
    if (kIsWeb) {
      _showWebDirectLinkAd(context, onEarnedReward: onEarnedReward);
      return;
    }

    NativeAdHelper.showRewardedAd(context, onEarnedReward: () {
      onEarnedReward();
      // Preload next
      loadRewardedAd();
    });
  }

  void _showWebDirectLinkAd(BuildContext context, {required Function onEarnedReward}) async {
    // Show a quick loader while fetching the dynamic URL from Supabase
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // 1. Fetch live admin configuration
    final String? configuredLink = await SupabaseService().getAppSetting('adsterra_direct_link');
    
    if (context.mounted) {
      Navigator.of(context).pop(); // Dismiss loader
    }

    // Fallback to safety default if network/config fails
    const String defaultLink = 'https://www.highcpmgate.com/example-adsterra-link';
    final url = Uri.parse(configuredLink ?? defaultLink);
    
    if (!await launchUrl(url, webOnlyWindowName: '_blank')) {
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Failed to load sponsor video. Please check popup blockers.')),
         );
      }
      return;
    }

    // 2. Show the countdown dialog
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
  int _timeLeft = 15; // Set back to 15 in prod
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
          Navigator.of(context).pop(); // Auto-close dialog
          widget.onEarnedReward(); // Give the coins!
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
          border: Border.all(color: context.colors.primaryContainer.withValues(alpha: 0.5), width: 2),
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
            Icon(Icons.ondemand_video_rounded, color: context.colors.primaryContainer, size: 48),
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
              'Lütfen Sponsor bağlantısını kapatmadan $_timeLeft saniye açık tutun!',
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
                    value: _timeLeft / 15, // 1.0 -> 0.0
                    strokeWidth: 6,
                    backgroundColor: context.colors.outline.withValues(alpha: 0.2),
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
                  side: BorderSide(color: context.colors.error.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Cancel & Lose Reward', style: TextStyle(color: context.colors.error, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
