import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/store_service.dart';
import '../services/supabase_service.dart';
import '../models/store_product.dart';
import '../models/user_entitlement.dart';

// Provider for StoreService
final storeServiceProvider = Provider<StoreService>((ref) {
  return StoreService(SupabaseService.client);
});

// Provider for active store products listing
final storeProductsProvider = FutureProvider<List<StoreProduct>>((ref) async {
  final storeService = ref.read(storeServiceProvider);
  return storeService.getActiveProducts();
});

// AsyncNotifier for User Entitlements
class EntitlementsNotifier extends AsyncNotifier<List<UserEntitlement>> {
  @override
  Future<List<UserEntitlement>> build() async {
    final storeService = ref.read(storeServiceProvider);
    return storeService.getMyEntitlements();
  }

  // Helper method to easily check access
  bool hasAccess(String productCode) {
    if (!state.hasValue || state.value == null) return false;
    
    try {
      final entitlement = state.value!.firstWhere(
        (e) => e.productCode == productCode,
      );
      return entitlement.isValid;
    } catch (_) {
      // not found
      return false;
    }
  }

  // Call this after a successful purchase to refresh entitlements
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(storeServiceProvider).getMyEntitlements());
  }
}

// Global provider for User Entitlements
final entitlementsProvider = AsyncNotifierProvider<EntitlementsNotifier, List<UserEntitlement>>(() {
  return EntitlementsNotifier();
});
