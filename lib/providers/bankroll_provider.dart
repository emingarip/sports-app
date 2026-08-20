import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/coupon.dart';

const _coolingUntilKey = 'bankroll_cooling_until';

/// Responsible-play cooling mode: while active the coupon share flow is
/// blocked. Persisted locally so it survives app restarts.
class CoolingModeNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_coolingUntilKey);
    if (stored == null) return null;
    final until = DateTime.tryParse(stored);
    if (until == null || until.isBefore(DateTime.now())) return null;
    return until;
  }

  Future<void> startCooling({Duration duration = const Duration(hours: 24)}) async {
    final until = DateTime.now().add(duration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_coolingUntilKey, until.toIso8601String());
    state = AsyncData(until);
  }

  Future<void> stopCooling() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_coolingUntilKey);
    state = const AsyncData(null);
  }
}

final coolingModeProvider =
    AsyncNotifierProvider<CoolingModeNotifier, DateTime?>(
  CoolingModeNotifier.new,
  name: 'coolingModeProvider',
);

/// Aggregated performance + discipline signals from the user's own coupons.
class BankrollStats {
  final int settledCount;
  final int wonCount;
  final double? flatRoi;
  final double? avgClv;
  final int clvSample;
  final int currentLossStreak;
  final bool stakeEscalation;

  const BankrollStats({
    this.settledCount = 0,
    this.wonCount = 0,
    this.flatRoi,
    this.avgClv,
    this.clvSample = 0,
    this.currentLossStreak = 0,
    this.stakeEscalation = false,
  });

  double? get winRate => settledCount == 0 ? null : wonCount / settledCount;
  bool get hasEnoughSample => settledCount >= 10;

  /// Flat-stake ROI: every coupon counts as 1 unit staked; a won coupon
  /// returns its total odds. This measures skill independent of stake sizing.
  static BankrollStats fromCoupons(List<AnalysisCoupon> coupons) {
    final settled = coupons.where((coupon) => coupon.isSettled).toList();
    final decided =
        settled.where((coupon) => coupon.status != 'void').toList();

    var returned = 0.0;
    var won = 0;
    final clvValues = <double>[];
    for (final coupon in decided) {
      if (coupon.isWon) {
        won += 1;
        returned += coupon.totalOdds;
      }
      if (coupon.avgClv != null) clvValues.add(coupon.avgClv!);
    }

    // Loss streak over the most recent decided coupons (list is newest-first).
    var streak = 0;
    for (final coupon in decided) {
      if (coupon.status == 'lost') {
        streak += 1;
      } else {
        break;
      }
    }

    // Stake escalation: the last 3 staked coupons strictly increasing.
    final staked = coupons
        .where((coupon) => coupon.stakeKcoin != null)
        .take(3)
        .toList();
    final escalation = staked.length == 3 &&
        staked[0].stakeKcoin! > staked[1].stakeKcoin! &&
        staked[1].stakeKcoin! > staked[2].stakeKcoin!;

    return BankrollStats(
      settledCount: decided.length,
      wonCount: won,
      flatRoi: decided.isEmpty
          ? null
          : (returned - decided.length) / decided.length,
      avgClv: clvValues.isEmpty
          ? null
          : clvValues.reduce((a, b) => a + b) / clvValues.length,
      clvSample: clvValues.length,
      currentLossStreak: streak,
      stakeEscalation: escalation,
    );
  }
}
