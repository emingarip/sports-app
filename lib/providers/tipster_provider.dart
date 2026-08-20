import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/coupon.dart';
import '../models/tipster.dart';
import 'coupon_provider.dart';

/// Public coupon feed ("Topluluk Kuponları"), newest first.
final publicCouponsProvider = FutureProvider<List<AnalysisCoupon>>(
  (ref) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchPublicCoupons();
  },
  name: 'publicCouponsProvider',
);

/// Skill-based tipster ranking, keyed by period ('all' or 'YYYY-MM').
final tipsterLeaderboardProvider =
    FutureProvider.family<List<TipsterLeaderboardEntry>, String>(
  (ref, period) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchTipsterLeaderboard(period: period);
  },
  name: 'tipsterLeaderboardProvider',
);

/// Lifetime tipster stats for a user; null when they never shared a coupon.
final tipsterStatsProvider = FutureProvider.family<TipsterStats?, String>(
  (ref, userId) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchTipsterStats(userId);
  },
  name: 'tipsterStatsProvider',
);

/// Comments of a single coupon, keyed by coupon id, oldest first.
final couponCommentsProvider =
    FutureProvider.family<List<CouponComment>, String>(
  (ref, couponId) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchComments(couponId);
  },
  name: 'couponCommentsProvider',
);

/// A tipster's visible coupon history (public only unless it is the
/// signed-in user's own history), keyed by user id.
final tipsterCouponsProvider =
    FutureProvider.family<List<AnalysisCoupon>, String>(
  (ref, userId) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchUserCoupons(userId);
  },
  name: 'tipsterCouponsProvider',
);
