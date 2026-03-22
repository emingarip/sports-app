import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/k_coin_package.dart';

class KCoinRepository {
  final SupabaseClient _client;

  KCoinRepository(this._client);

  Future<int> getUserBalance(String userId) async {
    final response = await _client
        .from('users')
        .select('k_coin_balance')
        .eq('id', userId)
        .single();
    return response['k_coin_balance'] as int? ?? 0;
  }

  Future<List<KCoinPackage>> getActivePackages() async {
    final response = await _client
        .from('k_coin_packages')
        .select()
        .eq('is_active', true)
        .order('coin_amount', ascending: true);
        
    return (response as List).map((e) => KCoinPackage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> processTransaction({
    required int amount,
    required String transactionType,
    String? referenceId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    await _client.rpc('process_k_coin_transaction', params: {
      'p_user_id': userId,
      'p_amount': amount,
      'p_transaction_type': transactionType,
      'p_reference_id': referenceId,
    });
  }
}
