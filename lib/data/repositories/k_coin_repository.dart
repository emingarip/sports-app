import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/k_coin_package.dart';
import '../../models/reward_claim_result.dart';

class KCoinRepository {
  final SupabaseClient _client;

  KCoinRepository(this._client);

  Future<int> getUserBalance(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select('k_coin_balance')
          .eq('id', userId)
          .maybeSingle();
      if (response != null) {
        return _asInt(response['k_coin_balance']);
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

    return _asMapList(response).map(KCoinPackage.fromJson).toList();
  }

  /// Sends a non-wallet event to the Gamification API and returns the raw result.
  /// Wallet-changing rewards must use [claimReward].
  Future<Map<String, dynamic>> sendEvent(
    String userId,
    String eventType,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'gamification-api-bridge',
        body: {
          'action': 'send_event',
          'payload': {
            'user_id': userId,
            'event_type': eventType,
            'metadata': metadata,
          },
        },
      );
      if (response.status == 200 || response.status == 201) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {
        'points_awarded': 0,
        'matched_rules': <String>[],
        'badges_awarded': <String>[],
      };
    } catch (_) {
      return {
        'points_awarded': 0,
        'matched_rules': <String>[],
        'badges_awarded': <String>[],
      };
    }
  }

  Future<RewardClaimResult> claimReward({
    required String eventType,
    required String referenceId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final normalizedReferenceId = referenceId.trim();
    if (normalizedReferenceId.isEmpty) {
      throw Exception('Reward reference_id is required.');
    }

    try {
      final response = await _client.functions.invoke(
        'claim-kcoin-reward',
        body: {
          'event_type': eventType,
          'reference_id': normalizedReferenceId,
          'metadata': metadata,
        },
      );

      final payload = response.data;
      if (payload is Map) {
        final data = Map<String, dynamic>.from(payload);
        if (response.status >= 200 && response.status < 300) {
          return RewardClaimResult.fromJson(data);
        }

        final errorMessage = data['error']?.toString().trim();
        if (errorMessage != null && errorMessage.isNotEmpty) {
          throw Exception(errorMessage);
        }
      }

      throw Exception('Reward service returned an unexpected response.');
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }

      final reason = error.reasonPhrase;
      if (reason != null && reason.isNotEmpty) {
        throw Exception(reason);
      }

      throw Exception('Reward claim could not be completed.');
    }
  }

  Future<List<Map<String, dynamic>>> getPurchasingHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final txResponse = await _client
          .from('k_coin_transactions')
          .select(
              'transaction_type, amount, reference_id, description, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final unifiedList = _asMapList(txResponse).map((row) {
        final transactionType =
            row['transaction_type']?.toString() ?? 'unknown';
        final amount = _asInt(row['amount']);

        return {
          'type': transactionType,
          'amount': amount,
          'title': _buildHistoryTitle(
            transactionType: transactionType,
            referenceId: row['reference_id']?.toString(),
            description: row['description']?.toString(),
          ),
          'reference_id': row['reference_id'],
          'is_positive': amount > 0,
          'created_at': row['created_at'],
        };
      }).toList(growable: true);

      try {
        final orphanTopups = await _client
            .from('k_coin_purchasing_history')
            .select('product_id, coins_granted, created_at')
            .eq('user_id', userId)
            .isFilter('ledger_transaction_id', null);

        for (final entry in _asMapList(orphanTopups)) {
          unifiedList.add({
            'type': 'topup',
            'amount': _asInt(entry['coins_granted']),
            'title':
                'K-Coin Package (${entry['product_id']?.toString() ?? 'Unknown'})',
            'is_positive': true,
            'created_at': entry['created_at'],
          });
        }
      } catch (_) {
        // Environments without the new ledger_transaction_id column can still
        // render ledger history without legacy audit rows.
      }

      unifiedList.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      return unifiedList;
    } catch (_) {
      return [];
    }
  }

  String _buildHistoryTitle({
    required String transactionType,
    required String? referenceId,
    required String? description,
  }) {
    if (description != null && description.trim().isNotEmpty) {
      return description.trim();
    }

    switch (transactionType) {
      case 'store_purchase':
      case 'purchase':
        return 'Store Purchase: ${referenceId ?? 'Unknown'}';
      case 'topup':
        return 'K-Coin Package (${referenceId ?? 'Unknown'})';
      case 'rewarded_ad':
        return 'Rewarded Ad Bonus';
      case 'daily_reward':
        return 'Daily Reward';
      case 'task_reward':
        return 'Task Reward';
      case 'prediction_stake':
        return 'Prediction Stake';
      case 'prediction_payout':
        return 'Prediction Payout';
      case 'prediction_refund':
        return 'Prediction Refund';
      case 'admin_adjustment':
        return 'Admin Balance Adjustment';
      default:
        return 'Transaction ($transactionType)';
    }
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! Iterable) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  int _asInt(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
