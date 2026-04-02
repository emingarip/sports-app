import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store_product.dart';
import '../models/user_entitlement.dart';

class StoreService {
  final SupabaseClient _supabase;

  StoreService(this._supabase);

  // Get active products for the store
  Future<List<StoreProduct>> getActiveProducts() async {
    final response = await _supabase
        .from('store_products')
        .select()
        .eq('is_active', true)
        .order('price', ascending: true);

    return (response as List).map((json) => StoreProduct.fromJson(json)).toList();
  }

  // Get valid entitlements for the current user
  Future<List<UserEntitlement>> getMyEntitlements() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _supabase
        .from('user_entitlements')
        .select()
        .eq('user_id', userId)
        .eq('is_active', true)
        .or('expires_at.is.null,expires_at.gte.now()'); // Filtering expired dynamically

    return (response as List).map((json) => UserEntitlement.fromJson(json)).toList();
  }

  // Purchase a store item via the atomic RPC transaction
  Future<bool> buyStoreItem(String productCode) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı girişi yapılmamış.');

    try {
      final response = await _supabase.functions.invoke('buy-store-item', body: {
        'p_product_code': productCode,
      });

      final data = response.data as Map<String, dynamic>;
      return data['success'] == true;
    } catch (e) {
      if (e.toString().contains('Insufficient K-Coin balance')) {
         throw Exception('Yetersiz bakiye. K-Coin satın almalısınız veya kazanmalısınız.');
      }
      throw Exception('Satın alma başarısız oldu: $e');
    }
  }
}
