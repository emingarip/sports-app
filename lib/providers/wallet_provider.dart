import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/repositories/k_coin_repository.dart';
import '../models/k_coin_package.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'wallet_provider.g.dart';

@riverpod
KCoinRepository kCoinRepository(Ref ref) {
  final client = SupabaseService.client;
  return KCoinRepository(client);
}

@riverpod
Future<List<KCoinPackage>> kCoinPackages(Ref ref) {
  final repo = ref.watch(kCoinRepositoryProvider);
  return repo.getActivePackages();
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
      // In a real app, this would trigger the IAP payment sheet first.
      // After success, we grant the coins via backend.
      final repo = ref.read(kCoinRepositoryProvider);
      await repo.processTransaction(
        amount: package.coinAmount, 
        transactionType: 'purchase',
        referenceId: package.id,
      );
      // Eagerly fetch the new balance so the UI updates instantly
      await _fetchInitialBalance();
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
      // Eagerly fetch the new balance so the UI updates instantly
      await _fetchInitialBalance();
    } catch (e) {
      if (kDebugMode) print('Reward claim failed: \$e');
      rethrow;
    }
  }
}
