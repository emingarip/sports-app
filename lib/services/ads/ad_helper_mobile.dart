import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class NativeAdHelper {
  static RewardedAd? _rewardedAd;
  static int _numRewardedLoadAttempts = 0;
  static const int maxFailedLoadAttempts = 3;

  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  static void loadRewardedAd(String adUnitId) {
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          debugPrint('\$ad loaded successfully.');
          _rewardedAd = ad;
          _numRewardedLoadAttempts = 0;
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('RewardedAd failed to load: \$error');
          _rewardedAd = null;
          _numRewardedLoadAttempts += 1;
          if (_numRewardedLoadAttempts < maxFailedLoadAttempts) {
            loadRewardedAd(adUnitId);
          }
        },
      ),
    );
  }

  static void showRewardedAd(BuildContext context, {required Function onEarnedReward}) {
    if (_rewardedAd == null) {
      debugPrint('Warning: attempt to show rewarded before loaded.');
      // Attempt to fire another load to have it ready for next time
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad is still loading. Please try again in a few seconds.')),
      );
      return;
    }
    
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) =>
          debugPrint('ad onAdShowedFullScreenContent.'),
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        debugPrint('\$ad onAdDismissedFullScreenContent.');
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        debugPrint('\$ad onAdFailedToShowFullScreenContent: \$error');
        ad.dispose();
      },
    );

    _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        debugPrint('\$ad rewarded user with: \${reward.amount} \${reward.type}');
        // Trigger the external completion function 
        onEarnedReward();
      },
    );

    _rewardedAd = null; // Mark local reference null so it refetches next block
  }
}
