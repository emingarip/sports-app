import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/coupon.dart';
import '../../providers/coupon_provider.dart';
import '../../providers/tipster_provider.dart';
import '../../theme/app_theme.dart';

/// Confirm dialog for copying another tipster's coupon: optional K-Coin
/// stake, then the `copy_coupon` RPC (odds are re-locked server-side).
Future<void> showCopyCouponDialog(BuildContext context, AnalysisCoupon coupon) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CopyCouponDialog(coupon: coupon),
  );
}

class _CopyCouponDialog extends ConsumerStatefulWidget {
  final AnalysisCoupon coupon;

  const _CopyCouponDialog({required this.coupon});

  @override
  ConsumerState<_CopyCouponDialog> createState() => _CopyCouponDialogState();
}

class _CopyCouponDialogState extends ConsumerState<_CopyCouponDialog> {
  final TextEditingController _stakeController = TextEditingController();
  bool _copying = false;

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final stakeText = _stakeController.text.trim();
    final stake = stakeText.isEmpty ? null : int.tryParse(stakeText);
    if (stakeText.isNotEmpty && (stake == null || stake <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz K-Coin miktarı.')),
      );
      return;
    }

    setState(() => _copying = true);
    try {
      await ref.read(couponServiceProvider).copyCoupon(
            widget.coupon.id,
            stakeKcoin: stake,
          );
      ref.invalidate(myCouponsProvider);
      ref.invalidate(publicCouponsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kupon sana kopyalandı')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _copying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kupon kopyalanamadı: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final coupon = widget.coupon;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Kuponu Kopyala',
        style: TextStyle(
          color: colors.textHigh,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${coupon.selections.length} seçim güncel bülten oranlarıyla '
            'yeniden fiyatlanır ve kendi siciline işlenir. Oranlar '
            'paylaşıldığı andakinden farklı olabilir.',
            style: TextStyle(color: colors.textMedium, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stakeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'K-Coin miktarı (opsiyonel, sanal)',
              helperText: 'K-Coin sanaldır; sicilin ROI ve CLV ile ölçülür.',
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _copying ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _copying ? null : _copy,
          icon: _copying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.copy_all, size: 16),
          label: Text(_copying ? 'Kopyalanıyor...' : 'Kopyala'),
        ),
      ],
    );
  }
}
