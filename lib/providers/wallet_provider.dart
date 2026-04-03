import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/repositories/k_coin_repository.dart';
import '../models/k_coin_package.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/revenuecat_service.dart';

part 'wallet_provider.g.dart';

@riverpod
KCoinRepository kCoinRepository(Ref ref) {
  final client = SupabaseService.client;
  return KCoinRepository(client);
}

@riverpod
Future<List<KCoinPackage>> kCoinPackages(Ref ref) async {
  final repo = ref.watch(kCoinRepositoryProvider);
  final supabasePackages = await repo.getActivePackages();
  if (!RevenueCatService.isConfiguredForCurrentPlatform) {
    return supabasePackages
        .map((pkg) => pkg.copyWith(displayPrice: '\$${pkg.priceUsd}'))
        .toList();
  }

  try {
    final offerings = await Purchases.getOfferings();
    if (offerings.current != null &&
        offerings.current!.availablePackages.isNotEmpty) {
      final rcPackages = offerings.current!.availablePackages;

      return supabasePackages.map((pkg) {
        if (pkg.storeProductId != null) {
          try {
            final rcPackage = rcPackages.firstWhere(
                (p) => p.storeProduct.identifier == pkg.storeProductId);
            return pkg.copyWith(
                displayPrice: rcPackage.storeProduct.priceString);
          } catch (_) {}
        }
        return pkg.copyWith(displayPrice: '\$${pkg.priceUsd}');
      }).toList();
    }
  } catch (e) {
    if (kDebugMode) print('RevenueCat offerings fetch failed: $e');
  }

  return supabasePackages
      .map((pkg) => pkg.copyWith(displayPrice: '\$${pkg.priceUsd}'))
      .toList();
}

@Riverpod(keepAlive: true)
class WalletBalance extends _$WalletBalance {
  @override
  int build() {
    refreshBalance();
    return 0; // Default until loaded
  }

  Future<void> refreshBalance() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    try {
      final repo = ref.read(kCoinRepositoryProvider);
      final balance = await repo.getUserBalance(user.id);
      state = balance;
    } catch (e) {
      if (kDebugMode) print('Error fetching balance: $e');
    }
  }

  Future<void> purchasePackage(KCoinPackage package) async {
    try {
      if (kIsWeb) {
        throw UnsupportedError(
          'Web K-Coin purchases are disabled until a verified web checkout is integrated.',
        );
      }

      final rcPackages = await RevenueCatService.getKCoinPackages();
      final productId = package.storeProductId ?? '';

      Package? rcPackage;
      try {
        rcPackage = rcPackages
            .firstWhere((p) => p.storeProduct.identifier == productId);
      } catch (_) {}

      if (rcPackage == null) {
        throw Exception(
            "Product not found in Apple/Google Store yet. Please configure RevenueCat dashboard.");
      }

      final success = await RevenueCatService.purchasePackage(rcPackage);
      if (!success) {
        throw Exception("Purchase was cancelled or failed.");
      }

      // The RevenueCat webhook will asynchronously grant K-Coins to this user.
      // Wait a moment for the webhook to complete, then refresh.
      // (In a more robust setup, we'd listen to Realtime changes on the users table)
      await Future.delayed(const Duration(seconds: 2));
      await refreshBalance();
    } catch (e) {
      if (kDebugMode) print('Purchase failed: $e');
      rethrow;
    }
  }

  Future<void> claimTestReward() async {
    try {
      final repo = ref.read(kCoinRepositoryProvider);
      await repo.processTransaction(
        amount: 50,
        transactionType: 'daily_reward',
        referenceId: 'test_reward',
      );
      await refreshBalance();
    } catch (e) {
      if (kDebugMode) print('Reward claim failed: $e');
      rethrow;
    }
  }

  /// Claims ad reward and returns the full reward result from Gamification API.
  /// Returns null if the claim failed.
  Future<Map<String, dynamic>?> claimAdReward(int amount) async {
    try {
      final repo = ref.read(kCoinRepositoryProvider);
      final result = await repo.processTransaction(
        amount: amount,
        transactionType: 'ad_reward',
        referenceId: 'ad_reward',
      );
      await refreshBalance();
      return result;
    } catch (e) {
      if (kDebugMode) print('Ad Reward claim failed: $e');
      return null;
    }
  }
}
