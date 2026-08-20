import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/coupon.dart';
import '../../providers/coupon_provider.dart';
import '../../theme/app_theme.dart';
import '../frame_avatar.dart';
import 'copy_coupon_dialog.dart';
import 'coupon_comment_sheet.dart';

/// One public coupon in the community feed: tipster row, selections,
/// odds/status/EV/CLV summary and the like / comment / copy actions.
class CouponFeedCard extends ConsumerStatefulWidget {
  final AnalysisCoupon coupon;

  /// Called when the tipster row is tapped; hidden when null (e.g. on the
  /// tipster's own profile, where the header would be redundant).
  final VoidCallback? onTipsterTap;
  final bool showTipsterHeader;

  const CouponFeedCard({
    super.key,
    required this.coupon,
    this.onTipsterTap,
    this.showTipsterHeader = true,
  });

  @override
  ConsumerState<CouponFeedCard> createState() => _CouponFeedCardState();
}

class _CouponFeedCardState extends ConsumerState<CouponFeedCard> {
  late bool _liked;
  late int _likeCount;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    _syncFromCoupon();
  }

  @override
  void didUpdateWidget(CouponFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coupon.id != widget.coupon.id ||
        oldWidget.coupon.likeCount != widget.coupon.likeCount ||
        oldWidget.coupon.likedByMe != widget.coupon.likedByMe) {
      _syncFromCoupon();
    }
  }

  void _syncFromCoupon() {
    _liked = widget.coupon.likedByMe ?? false;
    _likeCount = widget.coupon.likeCount ?? 0;
  }

  String? get _currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  bool get _canCopy {
    final coupon = widget.coupon;
    final userId = _currentUserId;
    return coupon.status == 'pending' &&
        userId != null &&
        coupon.userId != userId &&
        (coupon.firstKickoffAt?.isAfter(DateTime.now()) ?? false);
  }

  Future<void> _toggleLike() async {
    if (_likeBusy || _currentUserId == null) return;
    final wasLiked = _liked;
    setState(() {
      _likeBusy = true;
      _liked = !wasLiked;
      _likeCount += wasLiked ? -1 : 1;
    });
    try {
      final service = ref.read(couponServiceProvider);
      if (wasLiked) {
        await service.unlikeCoupon(widget.coupon.id);
      } else {
        await service.likeCoupon(widget.coupon.id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likeCount += wasLiked ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beğeni kaydedilemedi: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final coupon = widget.coupon;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTipsterHeader) ...[
            _TipsterRow(coupon: coupon, onTap: widget.onTipsterTap),
            const SizedBox(height: 10),
          ],
          if (coupon.title?.isNotEmpty == true) ...[
            Text(
              coupon.title!,
              style: TextStyle(
                color: colors.textHigh,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final selection in coupon.selections)
            _SelectionRow(selection: selection, settled: coupon.isSettled),
          Divider(height: 20, color: colors.outline.withValues(alpha: 0.2)),
          _SummaryRow(coupon: coupon),
          const SizedBox(height: 6),
          _ActionRow(
            liked: _liked,
            likeCount: _likeCount,
            canLike: _currentUserId != null,
            canCopy: _canCopy,
            onLike: _toggleLike,
            onComment: () => showCouponCommentsSheet(context, coupon.id),
            onCopy: () => showCopyCouponDialog(context, coupon),
          ),
        ],
      ),
    );
  }
}

class _TipsterRow extends StatelessWidget {
  final AnalysisCoupon coupon;
  final VoidCallback? onTap;

  const _TipsterRow({required this.coupon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final createdAt = coupon.createdAt?.toLocal();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          FrameAvatar(avatarUrl: coupon.avatarUrl, radius: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              coupon.username ?? 'Kullanıcı',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textHigh,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          if (createdAt != null)
            Text(
              '${createdAt.day.toString().padLeft(2, '0')}.'
              '${createdAt.month.toString().padLeft(2, '0')} '
              '${createdAt.hour.toString().padLeft(2, '0')}:'
              '${createdAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(color: colors.textLow, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _SelectionRow extends StatelessWidget {
  final Map<String, dynamic> selection;
  final bool settled;

  const _SelectionRow({required this.selection, required this.settled});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = selection['result']?.toString() ?? 'pending';
    final odds = selection['odds_at_share'];

    final (IconData icon, Color iconColor) = switch (result) {
      'won' => (Icons.check_circle, colors.success),
      'lost' => (Icons.cancel, colors.error),
      'void' => (Icons.remove_circle_outline, colors.textLow),
      _ => settled
          ? (Icons.schedule, colors.textLow)
          : (Icons.circle, colors.textLow.withValues(alpha: 0.4)),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: result == 'pending' ? 8 : 15, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selection['match_label']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${selection['market_name'] ?? ''}: '
                  '${selection['selection_label'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMedium,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            odds is num ? odds.toDouble().toStringAsFixed(2) : '—',
            style: TextStyle(
              color: colors.textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final AnalysisCoupon coupon;

  const _SummaryRow({required this.coupon});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (statusColor, statusLabel) = switch (coupon.status) {
      'won' => (colors.success, 'KAZANDI'),
      'lost' => (colors.error, 'KAYBETTİ'),
      'void' => (colors.textLow, 'İPTAL'),
      _ => (colors.textMedium, 'BEKLİYOR'),
    };
    final expectedValue = coupon.expectedValue;
    final avgClv = coupon.resolvedAt != null ? coupon.avgClv : null;

    return Row(
      children: [
        Text(
          'Toplam Oran ${coupon.totalOdds.toStringAsFixed(2)}',
          style: TextStyle(
            color: colors.textHigh,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              if (expectedValue != null)
                'EV ${expectedValue >= 0 ? '+' : ''}'
                    '%${(expectedValue * 100).toStringAsFixed(1)}',
              if (avgClv != null)
                'CLV ${avgClv >= 0 ? '+' : ''}'
                    '%${(avgClv * 100).toStringAsFixed(1)}',
            ].join(' • '),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textLow,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool liked;
  final int likeCount;
  final bool canLike;
  final bool canCopy;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onCopy;

  const _ActionRow({
    required this.liked,
    required this.likeCount,
    required this.canLike,
    required this.canCopy,
    required this.onLike,
    required this.onComment,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        InkWell(
          onTap: canLike ? onLike : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: liked ? colors.error : colors.textMedium,
                ),
                const SizedBox(width: 4),
                Text(
                  '$likeCount',
                  style: TextStyle(
                    color: colors.textMedium,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: onComment,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: colors.textMedium,
            ),
          ),
        ),
        const Spacer(),
        if (canCopy)
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_all, size: 16),
            label: const Text(
              'Kuponu Kopyala',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}
