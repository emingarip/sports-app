import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/tipster.dart';
import '../../providers/coupon_provider.dart';
import '../../providers/tipster_provider.dart';
import '../../theme/app_theme.dart';
import '../frame_avatar.dart';

/// Opens the comment bottom sheet (list + input) for a coupon.
Future<void> showCouponCommentsSheet(BuildContext context, String couponId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CouponCommentSheet(couponId: couponId),
  );
}

class _CouponCommentSheet extends ConsumerStatefulWidget {
  final String couponId;

  const _CouponCommentSheet({required this.couponId});

  @override
  ConsumerState<_CouponCommentSheet> createState() =>
      _CouponCommentSheetState();
}

class _CouponCommentSheetState extends ConsumerState<_CouponCommentSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await ref.read(couponServiceProvider).addComment(
            widget.couponId,
            content,
          );
      _controller.clear();
      ref.invalidate(couponCommentsProvider(widget.couponId));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yorum gönderilemedi: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final commentsAsync = ref.watch(couponCommentsProvider(widget.couponId));
    final signedIn = Supabase.instance.client.auth.currentUser != null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'YORUMLAR',
              style: TextStyle(
                color: colors.textMedium,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: commentsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Text(
                    'Yorumlar yüklenemedi.',
                    style: TextStyle(color: colors.error, fontSize: 13),
                  ),
                ),
                data: (comments) => comments.isEmpty
                    ? Center(
                        child: Text(
                          'Henüz yorum yok. İlk yorumu sen yaz!',
                          style: TextStyle(
                            color: colors.textMedium,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: comments.length,
                        itemBuilder: (context, index) =>
                            _CommentTile(comment: comments[index]),
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: signedIn,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: signedIn
                              ? 'Yorum yaz...'
                              : 'Yorum için giriş yapmalısın.',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: signedIn && !_sending ? _send : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send, color: colors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CouponComment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final createdAt = comment.createdAt?.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrameAvatar(avatarUrl: comment.avatarUrl, radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        comment.username ?? 'Kullanıcı',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textHigh,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        '${createdAt.day.toString().padLeft(2, '0')}.'
                        '${createdAt.month.toString().padLeft(2, '0')} '
                        '${createdAt.hour.toString().padLeft(2, '0')}:'
                        '${createdAt.minute.toString().padLeft(2, '0')}',
                        style:
                            TextStyle(color: colors.textLow, fontSize: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.content,
                  style: TextStyle(color: colors.textMedium, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
