import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';

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
                    final coins = item['coins_granted'] ?? 0;
                    final productId = item['product_id'] ?? 'Unknown';
                    final dateStr = item['created_at'];
                    final date = dateStr != null ? DateTime.tryParse(dateStr)?.toLocal() : null;
                    final formattedDate = date != null ? DateFormat('MMM d, yyyy • h:mm a').format(date) : '';

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
                              color: context.colors.primaryContainer.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.receipt_long, color: context.colors.primaryContainer),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productId,
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
                                '+\$$coins',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.green,
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
