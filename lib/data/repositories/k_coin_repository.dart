import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../models/k_coin_package.dart';

class KCoinRepository {
  final SupabaseClient _client;
  final String _baseUrl;

  KCoinRepository(this._client, {String? baseUrl})
      : _baseUrl = baseUrl ?? dotenv.env['GAMIFICATION_API_URL'] ?? 'http://gamification.boskale.com/api/v1';

  Future<int> getUserBalance(String userId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/users/$userId'));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return (json['points'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<List<KCoinPackage>> getActivePackages() async {
    final response = await _client
        .from('k_coin_packages')
        .select()
        .eq('is_active', true)
        .order('coin_amount', ascending: true);
        
    return (response as List).map((e) => KCoinPackage.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sends an event to the Gamification API and returns the reward result.
  /// Response includes: points_awarded, matched_rules, badges_awarded.
  Future<Map<String, dynamic>> sendEvent(String userId, String eventType, Map<String, dynamic> metadata) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/events'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'event_type': eventType,
        'metadata': metadata,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send event to gamification system');
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {'points_awarded': 0, 'matched_rules': <String>[], 'badges_awarded': <String>[]};
    }
  }

  /// Sends a transaction event and returns the reward result from the Gamification API.
  Future<Map<String, dynamic>> processTransaction({
    required int amount,
    required String transactionType,
    String? referenceId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    // Send Gamification Event for the transaction
    return await sendEvent(userId, transactionType, {
      'amount': amount,
      'reference_id': referenceId,
    });
  }

  Future<List<Map<String, dynamic>>> getPurchasingHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      // 1. Fetch real-money top-ups
      final topupsResponse = await _client
          .from('k_coin_purchasing_history')
          .select()
          .eq('user_id', userId);

      // 2. Fetch store transactions (e.g. buying a frame)
      final txResponse = await _client
          .from('k_coin_transactions')
          .select()
          .eq('user_id', userId);

      List<Map<String, dynamic>> unifiedList = [];

      for (var row in (topupsResponse as List)) {
        unifiedList.add({
          'type': 'topup',
          'amount': row['coins_granted'] ?? 0,
          'title': 'K-Coin Paketi (${row['product_id'] ?? 'Bilinmiyor'})',
          'is_positive': true,
          'created_at': row['created_at'],
        });
      }

      for (var row in (txResponse as List)) {
        final String tType = row['transaction_type'] ?? 'unknown';
        final int amount = row['amount'] ?? 0;
        String title = '';
        if (tType == 'purchase' || tType == 'store_purchase') {
          title = 'Mağaza: ${row['reference_id'] ?? 'Bilinmiyor'}';
        } else if (tType == 'reward' || tType == 'daily_reward') {
          title = 'Günlük K-Coin Ödülü';
        } else {
          title = 'İşlem ($tType)';
        }

        unifiedList.add({
          'type': tType,
          'amount': amount,
          'title': title,
          'reference_id': row['reference_id'],
          'is_positive': amount > 0,
          'created_at': row['created_at'],
        });
      }

      // 3. Sort by created_at descending
      unifiedList.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      return unifiedList;
    } catch (e) {
      return [];
    }
  }
}

