import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/repositories/k_coin_repository.dart';
import '../models/k_coin_package.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  
  try {
    final offerings = await Purchases.getOfferings();
    if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
      final rcPackages = offerings.current!.availablePackages;
      
      return supabasePackages.map((pkg) {
        if (pkg.storeProductId != null) {
          try {
            final rcPackage = rcPackages.firstWhere(
              (p) => p.storeProduct.identifier == pkg.storeProductId
            );
            return pkg.copyWith(displayPrice: rcPackage.storeProduct.priceString);
          } catch (_) {}
        }
        return pkg.copyWith(displayPrice: '\$${pkg.priceUsd}');
      }).toList();
    }
  } catch (e) {
    if (kDebugMode) print('RevenueCat offerings fetch failed: $e');
  }

  return supabasePackages.map((pkg) => pkg.copyWith(displayPrice: '\$${pkg.priceUsd}')).toList();
}

@Riverpod(keepAlive: true)
class WalletBalance extends _$WalletBalance {
  RealtimeChannel? _channel;

  @override
  int build() {
    _fetchInitialBalance();
    _subscribeToWalletChanges();
    
    ref.onDispose(() {
      _channel?.unsubscribe();
    });
    
    return 0; // Default until loaded
  }

  Future<void> _fetchInitialBalance() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;
    
    try {
      final repo = ref.read(kCoinRepositoryProvider);
      final balance = await repo.getUserBalance(user.id);
      state = balance;
    } catch (e) {
      if (kDebugMode) print('Error fetching balance: \$e');
    }
  }

  void _subscribeToWalletChanges() {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return;

    final client = SupabaseService.client;
    _channel = client.channel('public:users:wallet_\${user.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq, 
          column: 'id', 
          value: user.id
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          if (newRecord.containsKey('k_coin_balance')) {
            state = newRecord['k_coin_balance'] as int;
          }
        },
      )
      .subscribe();
  }

  Future<void> purchasePackage(KCoinPackage package) async {
    try {
      if (kIsWeb) {
        // Fallback for Web/Testing where Apple/Google IAP is absent
        final repo = ref.read(kCoinRepositoryProvider);
        await repo.processTransaction(
          amount: package.coinAmount, 
          transactionType: 'purchase',
          referenceId: package.id,
        );
        await _fetchInitialBalance();
        return;
      }

      final rcPackages = await RevenueCatService.getKCoinPackages();
      final productId = package.storeProductId ?? '';
      
      Package? rcPackage;
      try {
        rcPackage = rcPackages.firstWhere((p) => p.storeProduct.identifier == productId);
      } catch (_) {}

      if (rcPackage == null) {
        throw Exception("Product not found in Apple/Google Store yet. Please configure RevenueCat dashboard.");
      }

      final success = await RevenueCatService.purchasePackage(rcPackage);
      if (!success) {
        throw Exception("Purchase was cancelled or failed.");
      }
      
      // Note: Do NOT manually increment the balance here. 
      // The Supabase Webhook will securely increment it, and the Realtime _channel listener will automatically update the UI state.
    } catch (e) {
      if (kDebugMode) print('Purchase failed: \$e');
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
      await _fetchInitialBalance();
    } catch (e) {
      if (kDebugMode) print('Reward claim failed: \$e');
      rethrow;
    }
  }

  Future<bool> claimAdReward(int amount) async {
    try {
      final success = await SupabaseService().rewardUserCoins(amount);
      if (success) {
        await _fetchInitialBalance();
      }
      return success;
    } catch (e) {
      if (kDebugMode) print('Ad Reward claim failed: \$e');
      return false;
    }
  }
}
