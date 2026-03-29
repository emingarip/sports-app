import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../providers/store_provider.dart';
import '../models/store_product.dart';

class PurchaseHistoryScreen extends ConsumerStatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  ConsumerState<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends ConsumerState<PurchaseHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final repo = ref.read(kCoinRepositoryProvider);
      final data = await repo.getPurchasingHistory();
      
      // Attempt to load store products to swap out raw reference IDs with friendly titles
      List<StoreProduct> storeProducts = [];
      try {
        storeProducts = await ref.read(storeProductsProvider.future);
      } catch (_) {}

      if (storeProducts.isNotEmpty) {
        for (var item in data) {
          final type = item['type'] ?? '';
          if (type == 'purchase' || type == 'store_purchase') {
            final refId = item['reference_id'];
            if (refId != null) {
              try {
                final product = storeProducts.firstWhere((p) => p.productCode == refId);
                item['title'] = 'Mağaza: ${product.title}';
              } catch (_) {}
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _history = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          'Purchase History',
          style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold),
        ),
        backgroundColor: context.colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _history.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    final int amount = item['amount'] ?? 0;
                    final bool isPositive = item['is_positive'] ?? true;
                    final String type = item['type'] ?? 'unknown';
                    final String title = item['title'] ?? 'İşlem';
                    
                    final dateStr = item['created_at'];
                    final date = dateStr != null ? DateTime.tryParse(dateStr)?.toLocal() : null;
                    final formattedDate = date != null ? DateFormat('MMM d, yyyy • h:mm a').format(date) : '';

                    IconData iconData = Icons.receipt_long;
                    Color iconColor = context.colors.primaryContainer;
                    
                    if (type == 'purchase' || type == 'store_purchase') {
                      iconData = Icons.shopping_bag;
                      iconColor = Colors.orange;
                    } else if (type == 'topup') {
                      iconData = Icons.monetization_on;
                      iconColor = Colors.green;
                    } else if (type == 'reward' || type == 'daily_reward') {
                      iconData = Icons.card_giftcard;
                      iconColor = Colors.purpleAccent;
                    }

                    return Container(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.colors.outline.withOpacity(0.1)),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: iconColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(iconData, color: iconColor),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: context.colors.textHigh,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formattedDate,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: context.colors.textMedium,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isPositive ? '+' : ''}$amount',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: isPositive ? Colors.green : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.monetization_on, size: 12, color: context.colors.primaryContainer),
                                  const SizedBox(width: 4),
                                  Text(
                                    'K-Coins',
                                    style: TextStyle(
                                      color: context.colors.textMedium,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: context.colors.surfaceContainerHigh),
          const SizedBox(height: 16),
          Text(
            "No purchase history yet.",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.colors.textMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "When you buy K-Coins, your receipts will appear here.",
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textMedium.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
