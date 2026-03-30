import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wallet_provider.dart';
import '../providers/store_provider.dart';
import '../models/k_coin_package.dart';
import '../models/store_product.dart';
import '../theme/app_theme.dart';
import '../services/admob_service.dart';
import '../services/supabase_service.dart';

class StoreFrontScreen extends ConsumerWidget {
  const StoreFrontScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletBalanceProvider);
    final packagesAsync = ref.watch(kCoinPackagesProvider);
    final storeProductsAsync = ref.watch(storeProductsProvider);
    
    // Watch entitlements to trigger rebuilds when they change
    ref.watch(entitlementsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          'K-COIN STORE',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textHigh,
                fontWeight: FontWeight.bold,
              ),
        ),
        backgroundColor: context.colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildBalanceCard(context, ref, balance),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Buy Coin Packages',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          packagesAsync.when(
            data: (packages) {
              if (packages.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'No packages available at the moment.',
                        style: TextStyle(color: context.colors.textMedium),
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16.0,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _buildPackageCard(context, ref, packages[index]);
                    },
                    childCount: packages.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, st) => SliverToBoxAdapter(
              child: Center(
                child: Text('Error loading packages', style: TextStyle(color: context.colors.error)),
              ),
            ),
          ),
          
          // Premium Store Items Section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.0, 32.0, 16.0, 16.0),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Premium Features & Items',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          storeProductsAsync.when(
            data: (products) {
              if (products.isEmpty) {
                return SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'No premium items available.',
                        style: TextStyle(color: context.colors.textMedium),
                      ),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _buildStoreItemCard(context, ref, products[index]);
                    },
                    childCount: products.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              )),
            ),
            error: (e, st) => SliverToBoxAdapter(
              child: Center(
                child: Text('Error loading store items', style: TextStyle(color: context.colors.error)),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, WidgetRef ref, int balance) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Your Balance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.colors.textMedium,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monetization_on, color: context.colors.primaryContainer, size: 48),
              const SizedBox(width: 12),
              Text(
                balance.toString(),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                await ref.read(walletBalanceProvider.notifier).claimTestReward();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Claimed 50 K-Coins!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to claim reward: \$e')),
                  );
                }
              }
            },
            icon: Icon(Icons.card_giftcard, color: context.colors.background),
            label: Text('Claim Test Reward', style: TextStyle(color: context.colors.background, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ADMOB REWARDED VIDEO BUTTON
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => const Center(child: CircularProgressIndicator()),
                  );
                  
                  final eligibility = await SupabaseService().checkAdEligibility();
                  
                  if (!context.mounted) return;
                  Navigator.of(context).pop(); // Dismiss loader

                  if (eligibility['eligible'] != true) {
                    final reason = eligibility['reason'];
                    String message = 'Reklamlar şu an yüklenemedi. Lütfen daha sonra deneyin.';
                    if (reason == 'daily_limit_reached') {
                      message = 'Günlük reklam sınırına ulaştınız. Lütfen yarın tekrar deneyin.';
                    } else if (reason == 'cooling_down') {
                      message = 'Biraz beklemelisiniz! Sıradaki reklam için süreniz henüz dolmadı.';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: context.colors.error,
                      behavior: SnackBarBehavior.floating,
                    ));
                    return;
                  }

                  // Show AdMob Rewarded Ad or Web Interstitial
                  AdMobService().showRewardedAd(
                    context,
                    onEarnedReward: () async {
                      try {
                        // Attempt to claim 50 coins securely via Supabase RPC
                        final success = await ref.read(walletBalanceProvider.notifier).claimAdReward(50);
                        if (success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tebrikler! Reklamdan +50 K-Coin kazandınız.'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('K-Coin yüklenemedi. Günlük limite veya bekleme süresine takılmış olabilirsiniz.'),
                              backgroundColor: context.colors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                      debugPrint('Error handling ad reward UI: \$e');
                    }
                  },
                );
              },
              icon: Icon(Icons.play_circle_fill, color: context.colors.primaryContainer, size: 28),
              label: Text(
                'Watch Ad (+50 K-Coins)', 
                style: TextStyle(color: context.colors.textHigh, fontWeight: FontWeight.bold, fontSize: 16)
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.colors.primaryContainer, width: 2),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: context.colors.primaryContainer.withOpacity(0.1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(BuildContext context, WidgetRef ref, KCoinPackage package) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monetization_on, color: context.colors.primaryContainer, size: 40),
          const SizedBox(height: 12),
          Text(
            '${package.coinAmount} Coins',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.colors.textHigh,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            package.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textMedium,
                ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                try {
                  await ref.read(walletBalanceProvider.notifier).purchasePackage(package);
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: context.colors.surfaceContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
                        title: Text('Purchase Successful!', style: TextStyle(color: context.colors.textHigh)),
                        content: Text(
                          'You have successfully purchased ${package.coinAmount} K-Coins. They have been added to your wallet.',
                          style: TextStyle(color: context.colors.textMedium),
                          textAlign: TextAlign.center,
                        ),
                        actionsAlignment: MainAxisAlignment.center,
                        actions: [
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.colors.primaryContainer,
                              foregroundColor: context.colors.background,
                            ),
                            child: const Text('Awesome!'),
                          )
                        ],
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Purchase failed: $e')),
                    );
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.colors.primaryContainer),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                package.displayPrice ?? '\$${package.priceUsd.toStringAsFixed(2)}',
                style: TextStyle(color: context.colors.primaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreItemCard(BuildContext context, WidgetRef ref, StoreProduct product) {
    // Check if user already owns it
    final hasAccess = ref.watch(entitlementsProvider.notifier).hasAccess(product.productCode);
    
    // Determine the icon based on product type
    IconData typeIcon = Icons.shopping_bag;
    if (product.productType == 'subscription') typeIcon = Icons.access_time_filled;
    if (product.productType == 'lifetime') typeIcon = Icons.all_inclusive;
    if (product.productType == 'consumable') typeIcon = Icons.offline_bolt;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAccess ? context.colors.primaryContainer.withOpacity(0.5) : context.colors.outline.withOpacity(0.1),
          width: hasAccess ? 2.0 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(typeIcon, color: context.colors.primaryContainer, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: context.colors.textHigh,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        if (hasAccess)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withOpacity(0.5)),
                            ),
                            child: const Text('OWNED', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        else
                          Row(
                            children: [
                              Icon(Icons.monetization_on, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${product.price}',
                                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.colors.textMedium,
                          ),
                    ),
                    if (product.durationDays != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Duration: ${product.durationDays} Days',
                          style: TextStyle(color: context.colors.primaryContainer, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!hasAccess)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _handlePurchaseProduct(context, ref, product),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.primaryContainer,
                    foregroundColor: context.colors.background,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Purchase with K-Coins', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handlePurchaseProduct(BuildContext context, WidgetRef ref, StoreProduct product) async {
    // Show confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surfaceContainerHighest,
        title: Text('Confirm Purchase', style: TextStyle(color: context.colors.textHigh)),
        content: Text(
          'Are you sure you want to spend ${product.price} K-Coins for "${product.title}"?',
          style: TextStyle(color: context.colors.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: context.colors.textMedium)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.primaryContainer),
            child: Text('Purchase', style: TextStyle(color: context.colors.background)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!context.mounted) return;

    try {
      // Execute transaction
      await ref.read(storeServiceProvider).buyStoreItem(product.productCode);
      
      // Refresh local state
      await ref.read(entitlementsProvider.notifier).refresh();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purchased ${product.title}!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
