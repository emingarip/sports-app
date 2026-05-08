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

    return _asMapList(response).map(StoreProduct.fromJson).toList();
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

    return _asMapList(response).map(UserEntitlement.fromJson).toList();
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

      final data = _asStringMap(response.data);
      final result = StorePurchaseResult.fromJson(data);
      if (!result.success) {
        throw Exception('Satin alma basarisiz oldu.');
      }

      return result;
    } on FunctionException catch (e) {
      final message = _functionErrorMessage(e);
      if (message != null) throw Exception(message);

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

  String? _functionErrorMessage(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] != null) {
      return _friendlyPurchaseError(details['error'].toString());
    }
    if (details is String && details.trim().isNotEmpty) {
      final text = details.trim();
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(text);
      return _friendlyPurchaseError(match?.group(1) ?? text);
    }
    final message = error.toString();
    if (message.contains('Insufficient K-Coin balance')) {
      return _friendlyPurchaseError('Insufficient K-Coin balance');
    }
    return null;
  }

  String _friendlyPurchaseError(String message) {
    if (message.contains('Insufficient K-Coin balance')) {
      return 'Yetersiz bakiye. K-Coin kazanmalisiniz veya bakiyenizi artirmalisiniz.';
    }
    if (message.contains('already owned')) {
      return 'Bu urun zaten hesabinizda aktif.';
    }
    if (message.contains('Product not found')) {
      return 'Urun su anda aktif degil.';
    }
    return message;
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! Iterable) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Map<String, dynamic> _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
