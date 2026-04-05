import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/store_product.dart';
import '../models/store_purchase_result.dart';
import '../models/user_entitlement.dart';

class StoreService {
  final SupabaseClient _supabase;

  StoreService(this._supabase);

  Future<List<StoreProduct>> getActiveProducts() async {
    final response = await _supabase
        .from('store_products')
        .select()
        .eq('is_active', true)
        .order('price', ascending: true);

    return (response as List)
        .map((json) => StoreProduct.fromJson(json))
        .toList();
  }

  Future<List<UserEntitlement>> getMyEntitlements() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    final response = await _supabase
        .from('user_entitlements')
        .select()
        .eq('user_id', userId)
        .eq('is_active', true)
        .or('expires_at.is.null,expires_at.gte.now()');

    return (response as List)
        .map((json) => UserEntitlement.fromJson(json))
        .toList();
  }

  Future<StorePurchaseResult> buyStoreItem(String productCode) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Kullanici girisi yapilmamis.');
    }

    try {
      final requestId = const Uuid().v4();
      final response = await _supabase.functions.invoke(
        'buy-store-item',
        body: {
          'p_product_code': productCode,
          'p_request_id': requestId,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);
      final result = StorePurchaseResult.fromJson(data);
      if (!result.success) {
        throw Exception('Satin alma basarisiz oldu.');
      }

      return result;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) {
        throw Exception(details['error'] as String);
      }

      final reason = e.reasonPhrase;
      if (reason != null && reason.isNotEmpty) {
        throw Exception(reason);
      }

      throw Exception('Satin alma servisi gecici olarak kullanilamiyor.');
    } catch (e) {
      if (e.toString().contains('Insufficient K-Coin balance')) {
        throw Exception(
          'Yetersiz bakiye. K-Coin satin almalisiniz veya kazanmalisiniz.',
        );
      }
      throw Exception('Satin alma basarisiz oldu: $e');
    }
  }
}
