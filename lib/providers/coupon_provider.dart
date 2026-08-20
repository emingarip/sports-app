import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bulletin.dart';
import '../models/coupon.dart';
import '../services/coupon_service.dart';

final couponServiceProvider = Provider<CouponService>(
  (ref) {
    return CouponService();
  },
  name: 'couponServiceProvider',
);

/// The coupon currently being built. One selection per match+market slot;
/// tapping the same selection again removes it, tapping a different selection
/// of the same slot replaces it.
class CouponDraftNotifier extends Notifier<CouponDraft> {
  @override
  CouponDraft build() => const CouponDraft();

  void toggleSelection({
    required BulletinMatch match,
    required BulletinMarket market,
    required BulletinSelection selection,
    BulletinPrediction? prediction,
  }) {
    final candidate = CouponSelection.fromBulletin(
      match: match,
      market: market,
      selection: selection,
      prediction: prediction,
    );

    final existingIndex =
        state.selections.indexWhere((s) => s.slotKey == candidate.slotKey);
    final updated = [...state.selections];
    if (existingIndex >= 0 &&
        updated[existingIndex].selectionId == candidate.selectionId) {
      updated.removeAt(existingIndex);
    } else if (existingIndex >= 0) {
      updated[existingIndex] = candidate;
    } else {
      updated.add(candidate);
    }
    state = state.copyWith(selections: updated);
  }

  void removeSelection(String selectionId) {
    state = state.copyWith(
      selections:
          state.selections.where((s) => s.selectionId != selectionId).toList(),
    );
  }

  void clear() {
    state = const CouponDraft();
  }
}

final couponDraftProvider = NotifierProvider<CouponDraftNotifier, CouponDraft>(
  CouponDraftNotifier.new,
  name: 'couponDraftProvider',
);

/// The signed-in user's stored coupons (bankroll screen + history).
final myCouponsProvider = FutureProvider<List<AnalysisCoupon>>(
  (ref) async {
    final service = ref.read(couponServiceProvider);
    return await service.fetchMyCoupons();
  },
  name: 'myCouponsProvider',
);
