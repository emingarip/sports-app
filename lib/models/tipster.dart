/// Models backing the tipster leaderboard, tipster profiles and the coupon
/// comment flow (Faz 4.2/4.3 of the betting-analysis pivot).
library;

/// One row of the `tipster_leaderboard` view (>= 10 settled coupons).
class TipsterLeaderboardEntry {
  final String userId;
  final String username;
  final String? avatarUrl;
  final String period;
  final double? roi;
  final double? avgClv;
  final int clvSample;
  final int couponsSettled;
  final double? winRate;

  const TipsterLeaderboardEntry({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.period,
    this.roi,
    this.avgClv,
    required this.clvSample,
    required this.couponsSettled,
    this.winRate,
  });

  factory TipsterLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return TipsterLeaderboardEntry(
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Kullanıcı',
      avatarUrl: _stringOrNull(json['avatar_url']),
      period: json['period']?.toString() ?? 'all',
      roi: _asDouble(json['roi']),
      avgClv: _asDouble(json['avg_clv']),
      clvSample: _asInt(json['clv_sample']),
      couponsSettled: _asInt(json['coupons_settled']),
      winRate: _asDouble(json['win_rate']),
    );
  }
}

/// One `tipster_stats` row (period 'all' or 'YYYY-MM').
class TipsterStats {
  final String userId;
  final String period;
  final int couponsTotal;
  final int couponsSettled;
  final int couponsWon;
  final double totalStaked;
  final double totalReturned;
  final double? roi;
  final double? avgClv;
  final int clvSample;

  /// market_code -> {picks, won} over settled coupons.
  final Map<String, dynamic> marketBreakdown;

  const TipsterStats({
    required this.userId,
    required this.period,
    required this.couponsTotal,
    required this.couponsSettled,
    required this.couponsWon,
    required this.totalStaked,
    required this.totalReturned,
    this.roi,
    this.avgClv,
    required this.clvSample,
    this.marketBreakdown = const {},
  });

  bool get hasEnoughSample => couponsSettled >= 10;

  double? get winRate =>
      couponsSettled > 0 ? couponsWon / couponsSettled : null;

  factory TipsterStats.fromJson(Map<String, dynamic> json) {
    final breakdown = json['market_breakdown'];
    return TipsterStats(
      userId: json['user_id']?.toString() ?? '',
      period: json['period']?.toString() ?? 'all',
      couponsTotal: _asInt(json['coupons_total']),
      couponsSettled: _asInt(json['coupons_settled']),
      couponsWon: _asInt(json['coupons_won']),
      totalStaked: _asDouble(json['total_staked']) ?? 0,
      totalReturned: _asDouble(json['total_returned']) ?? 0,
      roi: _asDouble(json['roi']),
      avgClv: _asDouble(json['avg_clv']),
      clvSample: _asInt(json['clv_sample']),
      marketBreakdown: breakdown is Map
          ? Map<String, dynamic>.from(breakdown)
          : const {},
    );
  }
}

/// One `coupon_comments` row, with the author embedded when fetched with the
/// `users(username, avatar_url)` join.
class CouponComment {
  final String id;
  final String couponId;
  final String userId;
  final String content;
  final DateTime? createdAt;
  final String? username;
  final String? avatarUrl;

  const CouponComment({
    required this.id,
    required this.couponId,
    required this.userId,
    required this.content,
    this.createdAt,
    this.username,
    this.avatarUrl,
  });

  factory CouponComment.fromJson(Map<String, dynamic> json) {
    final user = json['users'];
    return CouponComment(
      id: json['id']?.toString() ?? '',
      couponId: json['coupon_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      username: user is Map ? user['username']?.toString() : null,
      avatarUrl: user is Map ? _stringOrNull(user['avatar_url']) : null,
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
