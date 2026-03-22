import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/wallet_provider.dart';
import '../models/k_coin_package.dart';
import '../theme/app_theme.dart';

class StoreFrontScreen extends ConsumerWidget {
  const StoreFrontScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletBalanceProvider);
    final packagesAsync = ref.watch(kCoinPackagesProvider);

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
                    SnackBar(content: Text('Failed to claim reward: \$e')),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Purchased ${package.coinAmount} K-Coins!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Purchase failed: \$e')),
                    );
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.colors.primaryContainer),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                '\$${package.priceUsd.toStringAsFixed(2)}',
                style: TextStyle(color: context.colors.primaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
