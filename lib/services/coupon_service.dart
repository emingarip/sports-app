import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coupon.dart';
import '../models/tipster.dart';

/// Analysis coupon operations backed by the server-authoritative
/// `share_coupon` / `copy_coupon` RPCs, the `analysis_coupons` table and the
/// tipster social tables (likes, comments, stats, leaderboard).
class CouponService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Row shape used by the social feed: coupon + author + likes.
  static const String _feedSelect =
      '*, users(username, avatar_url), coupon_likes(user_id)';

  /// Shares the coupon draft. Odds are re-validated and locked server-side;
  /// throws when a selection's match has already kicked off or odds are stale.
  Future<void> shareCoupon(
    CouponDraft draft, {
    String? title,
    int? stakeKcoin,
    bool isPublic = true,
  }) async {
    if (draft.isEmpty) {
      throw ArgumentError('Kupon boş; önce seçim ekleyin.');
    }
    await _client.rpc('share_coupon', params: {
      'p_selections':
          draft.selections.map((selection) => selection.toRpcJson()).toList(),
      'p_title': title,
      'p_stake_kcoin': stakeKcoin,
      'p_is_public': isPublic,
    });
  }

  /// The signed-in user's coupons, newest first.
  Future<List<AnalysisCoupon>> fetchMyCoupons({int limit = 100}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('analysis_coupons')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(AnalysisCoupon.fromJson)
        .toList();
  }

  /// Public coupons for the social feed, newest first, with the author
  /// (username, avatar) and like info embedded.
  Future<List<AnalysisCoupon>> fetchPublicCoupons({int limit = 50}) async {
    final currentUserId = _client.auth.currentUser?.id;
    final rows = await _client
        .from('analysis_coupons')
        .select(_feedSelect)
        .eq('is_public', true)
        .order('created_at', ascending: false)
        .limit(limit);

    return _asCoupons(rows, currentUserId: currentUserId);
  }

  /// A tipster's coupon history, newest first. RLS already hides other
  /// users' private coupons; the explicit filter just keeps the intent clear.
  Future<List<AnalysisCoupon>> fetchUserCoupons(
    String userId, {
    int limit = 50,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;

    var query = _client
        .from('analysis_coupons')
        .select(_feedSelect)
        .eq('user_id', userId);
    if (userId != currentUserId) {
      query = query.eq('is_public', true);
    }
    final rows =
        await query.order('created_at', ascending: false).limit(limit);

    return _asCoupons(rows, currentUserId: currentUserId);
  }

  /// Likes a coupon for the signed-in user (idempotent via upsert).
  Future<void> likeCoupon(String couponId) async {
    final userId = _requireUserId();
    await _client.from('coupon_likes').upsert(
      {'coupon_id': couponId, 'user_id': userId},
      onConflict: 'coupon_id,user_id',
      ignoreDuplicates: true,
    );
  }

  /// Removes the signed-in user's like from a coupon.
  Future<void> unlikeCoupon(String couponId) async {
    final userId = _requireUserId();
    await _client
        .from('coupon_likes')
        .delete()
        .eq('coupon_id', couponId)
        .eq('user_id', userId);
  }

  /// Comments on a coupon, oldest first.
  Future<List<CouponComment>> fetchComments(String couponId) async {
    final rows = await _client
        .from('coupon_comments')
        .select('*, users(username, avatar_url)')
        .eq('coupon_id', couponId)
        .order('created_at', ascending: true);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(CouponComment.fromJson)
        .toList();
  }

  /// Adds a comment (max 500 characters, enforced server-side too).
  Future<void> addComment(String couponId, String content) async {
    final userId = _requireUserId();
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Yorum boş olamaz.');
    }
    await _client.from('coupon_comments').insert({
      'coupon_id': couponId,
      'user_id': userId,
      'content': trimmed,
    });
  }

  /// Copies another tipster's public pending coupon. Selections are rebuilt
  /// server-side with the current bulletin odds; throws when any match has
  /// kicked off or an odds row disappeared.
  Future<void> copyCoupon(
    String couponId, {
    int? stakeKcoin,
    bool isPublic = true,
  }) async {
    await _client.rpc('copy_coupon', params: {
      'p_coupon_id': couponId,
      'p_stake_kcoin': stakeKcoin,
      'p_is_public': isPublic,
    });
  }

  /// Skill-based tipster ranking (>= 10 settled coupons), best CLV first.
  Future<List<TipsterLeaderboardEntry>> fetchTipsterLeaderboard({
    String period = 'all',
    int limit = 50,
  }) async {
    final rows = await _client
        .from('tipster_leaderboard')
        .select()
        .eq('period', period)
        .order('avg_clv', ascending: false, nullsFirst: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(TipsterLeaderboardEntry.fromJson)
        .toList();
  }

  /// Lifetime tipster stats for a user; null when they never shared a coupon.
  Future<TipsterStats?> fetchTipsterStats(
    String userId, {
    String period = 'all',
  }) async {
    final row = await _client
        .from('tipster_stats')
        .select()
        .eq('user_id', userId)
        .eq('period', period)
        .maybeSingle();

    return row == null ? null : TipsterStats.fromJson(row);
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Bu işlem için giriş yapmalısın.');
    }
    return userId;
  }

  List<AnalysisCoupon> _asCoupons(Object? rows, {String? currentUserId}) {
    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((row) =>
            AnalysisCoupon.fromJson(row, currentUserId: currentUserId))
        .toList();
  }
}
