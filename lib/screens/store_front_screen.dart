import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_theme_definition.dart';
import '../models/k_coin_package.dart';
import '../models/store_product.dart';
import '../providers/app_theme_provider.dart';
import '../providers/store_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/admob_service.dart';
import '../services/revenuecat_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/theme_preview_card.dart';

class StoreFrontScreen extends ConsumerWidget {
  const StoreFrontScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletBalanceProvider);
    final packagesAsync = ref.watch(kCoinPackagesProvider);
    final storeProductsAsync = ref.watch(storeProductsProvider);
    final themeCatalogAsync = ref.watch(themeCatalogProvider);
    final ownedThemeCodes = ref.watch(ownedThemeCodesProvider);
    final themeState = ref.watch(appThemeControllerProvider);

    ref.watch(entitlementsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          'K-COIN STORE',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textHigh,
                fontWeight: FontWeight.w800,
              ),
        ),
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: CustomScrollView(
        slivers: [
          if (kIsWeb || !RevenueCatService.isConfiguredForCurrentPlatform)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _StoreNoticeCard(
                  message: kIsWeb
                      ? 'Web uzerinden K-Coin satin alma gecici olarak kapatildi. Dogrulanmis web odeme akisi tamamlaninca yeniden acilacak.'
                      : 'Satin alma sistemi bu build icinde yapilandirilmamis. RevenueCat anahtarlarini ekledikten sonra paketler acilacak.',
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: _buildBalanceCard(context, ref, balance),
          ),
          _buildSectionTitle(
            context,
            title: 'Coin Packages',
            subtitle: 'Wallet balance and consumable coin bundles.',
          ),
          packagesAsync.when(
            data: (packages) => _buildPackageGrid(context, ref, packages),
            loading: () => const SliverToBoxAdapter(
              child: ListShimmer(itemCount: 3),
            ),
            error: (error, _) => _buildErrorSliver(
              context,
              message: 'Package list could not be loaded.',
            ),
          ),
          _buildSectionTitle(
            context,
            title: 'Team Themes',
            subtitle:
                'Unlock branded club skins with K-Coin and apply them instantly.',
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: context.colors.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer
                            .withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Classic theme is always included',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: context.colors.textHigh,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Premium themes use the same entitlement system as other store items and switch live without restarting the app.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: context.colors.textMedium,
                                      height: 1.35,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          storeProductsAsync.when(
            data: (products) {
              final themeProducts =
                  products.where((product) => product.isThemeProduct).toList();
              final productsByThemeCode = {
                for (final product in themeProducts)
                  if (product.themeCode != null) product.themeCode!: product,
              };

              return themeCatalogAsync.when(
                data: (definitions) => _buildThemeProductList(
                  context,
                  ref,
                  definitions: definitions,
                  productsByThemeCode: productsByThemeCode,
                  ownedThemeCodes: ownedThemeCodes,
                  activeThemeCode: themeState.activeThemeCode,
                  isApplyingTheme: themeState.isSyncing,
                ),
                loading: () => const SliverToBoxAdapter(
                  child: ListShimmer(itemCount: 2),
                ),
                error: (error, _) => _buildErrorSliver(
                  context,
                  message: 'Theme catalog could not be loaded.',
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: ListShimmer(itemCount: 2),
            ),
            error: (error, _) => _buildErrorSliver(
              context,
              message: 'Store items could not be loaded.',
            ),
          ),
          _buildSectionTitle(
            context,
            title: 'Premium Features',
            subtitle:
                'Other unlocks, subscriptions, and permanent enhancements.',
          ),
          storeProductsAsync.when(
            data: (products) {
              final generalProducts =
                  products.where((product) => !product.isThemeProduct).toList();
              if (generalProducts.isEmpty) {
                return _buildEmptySliver(
                  context,
                  message: 'No premium items are active right now.',
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildStoreItemCard(
                        context,
                        ref,
                        generalProducts[index],
                      ),
                    ),
                    childCount: generalProducts.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: ListShimmer(itemCount: 2),
            ),
            error: (error, _) => _buildErrorSliver(
              context,
              message: 'Premium item catalog could not be loaded.',
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildSectionTitle(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.textMedium,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, WidgetRef ref, int balance) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.cardShadow.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
              Icon(
                Icons.monetization_on_rounded,
                color: context.colors.primaryContainer,
                size: 48,
              ),
              const SizedBox(width: 12),
              Text(
                balance.toString(),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: context.colors.textHigh,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(walletBalanceProvider.notifier)
                    .claimTestReward();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Claimed 50 K-Coins!')),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to claim reward: $error')),
                  );
                }
              }
            },
            icon: Icon(
              Icons.card_giftcard_rounded,
              color: context.colors.onPrimaryContainer,
            ),
            label: Text(
              'Claim Test Reward',
              style: TextStyle(
                color: context.colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) =>
                      const Center(child: CircularProgressIndicator()),
                );

                final eligibility =
                    await SupabaseService().checkAdEligibility();

                if (!context.mounted) {
                  return;
                }

                Navigator.of(context).pop();

                if (eligibility['eligible'] != true) {
                  final reason = eligibility['reason'];
                  var message =
                      'Reklamlar su an yuklenemedi. Lutfen daha sonra deneyin.';
                  if (reason == 'daily_limit_reached') {
                    message =
                        'Gunluk reklam sinirina ulastiniz. Lutfen yarin tekrar deneyin.';
                  } else if (reason == 'cooling_down') {
                    message =
                        'Biraz beklemelisiniz. Siradaki reklam icin sureniz henuz dolmadi.';
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(message),
                      backgroundColor: context.colors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                AdMobService().showRewardedAd(
                  context,
                  onEarnedReward: () async {
                    try {
                      final result = await ref
                          .read(walletBalanceProvider.notifier)
                          .claimAdReward(50);

                      if (!context.mounted) {
                        return;
                      }

                      if (result != null) {
                        final totalPoints =
                            (result['points_awarded'] as num?)?.toInt() ?? 50;
                        final matchedRules =
                            (result['matched_rules'] as List<dynamic>? ?? [])
                                .map((rule) => rule.toString())
                                .toList();

                        var message =
                            'Tebrikler. Reklamdan +$totalPoints K-Coin kazandiniz.';
                        if (matchedRules.length > 1) {
                          final bonusRules = matchedRules
                              .where((rule) => rule != 'Ad Watched Reward')
                              .join(', ');
                          message += '\nBonus: $bonusRules';
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(message),
                            backgroundColor: matchedRules.length > 1
                                ? context.colors.liveAccent
                                : context.colors.success,
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(
                              seconds: matchedRules.length > 1 ? 5 : 3,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'K-Coin yuklenemedi. Gunluk limite veya bekleme suresine takilmis olabilirsiniz.',
                            ),
                            backgroundColor: context.colors.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (error) {
                      debugPrint('Error handling ad reward UI: $error');
                    }
                  },
                );
              },
              icon: Icon(
                Icons.play_circle_fill_rounded,
                color: context.colors.primaryContainer,
                size: 28,
              ),
              label: Text(
                'Watch Ad (+50 K-Coins)',
                style: TextStyle(
                  color: context.colors.textHigh,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: context.colors.primaryContainer,
                  width: 2,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor:
                    context.colors.primaryContainer.withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageGrid(
    BuildContext context,
    WidgetRef ref,
    List<KCoinPackage> packages,
  ) {
    if (packages.isEmpty) {
      return _buildEmptySliver(
        context,
        message: 'No packages available at the moment.',
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildPackageCard(context, ref, packages[index]),
          childCount: packages.length,
        ),
      ),
    );
  }

  Widget _buildPackageCard(
    BuildContext context,
    WidgetRef ref,
    KCoinPackage package,
  ) {
    final canPurchase =
        !kIsWeb && RevenueCatService.isConfiguredForCurrentPlatform;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            color: context.colors.primaryContainer,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            '${package.coinAmount} Coins',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: context.colors.textHigh,
                  fontWeight: FontWeight.w800,
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
              onPressed: canPurchase
                  ? () async {
                      try {
                        await ref
                            .read(walletBalanceProvider.notifier)
                            .purchasePackage(package);

                        if (!context.mounted) {
                          return;
                        }

                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            icon: Icon(
                              Icons.check_circle_rounded,
                              color: context.colors.success,
                              size: 64,
                            ),
                            title: const Text('Purchase Successful'),
                            content: Text(
                              'You have successfully purchased ${package.coinAmount} K-Coins. They have been added to your wallet.',
                              textAlign: TextAlign.center,
                            ),
                            actionsAlignment: MainAxisAlignment.center,
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('Awesome'),
                              ),
                            ],
                          ),
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Purchase failed: $error'),
                            ),
                          );
                        }
                      }
                    }
                  : null,
              child: Text(
                canPurchase
                    ? (package.displayPrice ??
                        '\$${package.priceUsd.toStringAsFixed(2)}')
                    : 'Yakinda',
                style: TextStyle(
                  color: context.colors.primaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeProductList(
    BuildContext context,
    WidgetRef ref, {
    required List<AppThemeDefinition> definitions,
    required Map<String, StoreProduct> productsByThemeCode,
    required Set<String> ownedThemeCodes,
    required String activeThemeCode,
    required bool isApplyingTheme,
  }) {
    final visibleDefinitions = definitions
        .where(
          (definition) => productsByThemeCode.containsKey(definition.themeCode),
        )
        .toList();

    if (visibleDefinitions.isEmpty) {
      return _buildEmptySliver(
        context,
        message: 'No premium team themes are active right now.',
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final definition = visibleDefinitions[index];
            final product = productsByThemeCode[definition.themeCode]!;
            final isOwned = ownedThemeCodes.contains(definition.themeCode);
            final isActive = activeThemeCode == definition.themeCode;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ThemePreviewCard(
                definition: definition,
                owned: isOwned,
                active: isActive,
                priceLabel: isOwned ? null : '${product.price} K-Coin',
                primaryLabel: isActive
                    ? 'Active Theme'
                    : isOwned
                        ? (isApplyingTheme ? 'Applying...' : 'Apply Theme')
                        : 'Buy Theme',
                onPrimaryTap: isActive
                    ? null
                    : isOwned
                        ? (isApplyingTheme
                            ? null
                            : () => _applyTheme(
                                  context,
                                  ref,
                                  definition.themeCode,
                                ))
                        : () => _handlePurchaseProduct(context, ref, product),
                secondaryLabel: isActive ? 'Use Classic' : null,
                onSecondaryTap: isActive
                    ? () => _applyTheme(
                          context,
                          ref,
                          AppTheme.classicThemeCode,
                        )
                    : null,
              ),
            );
          },
          childCount: visibleDefinitions.length,
        ),
      ),
    );
  }

  Widget _buildStoreItemCard(
    BuildContext context,
    WidgetRef ref,
    StoreProduct product,
  ) {
    final hasAccess =
        ref.watch(entitlementsProvider.notifier).hasAccess(product.productCode);

    var typeIcon = Icons.shopping_bag_rounded;
    if (product.productType == 'subscription') {
      typeIcon = Icons.access_time_filled_rounded;
    } else if (product.productType == 'lifetime') {
      typeIcon = Icons.all_inclusive_rounded;
    } else if (product.productType == 'consumable') {
      typeIcon = Icons.offline_bolt_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasAccess
              ? context.colors.badgeOwnedBackground.withValues(alpha: 0.85)
              : context.colors.outline.withValues(alpha: 0.1),
          width: hasAccess ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
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
                child: Icon(
                  typeIcon,
                  color: context.colors.primaryContainer,
                  size: 28,
                ),
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: context.colors.textHigh,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        if (hasAccess)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.badgeOwnedBackground,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OWNED',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: context.colors.badgeOwnedForeground,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Icon(
                                Icons.monetization_on_rounded,
                                color: context.colors.accent,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${product.price}',
                                style: TextStyle(
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
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
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Duration: ${product.durationDays} days',
                          style: TextStyle(
                            color: context.colors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (!hasAccess)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      _handlePurchaseProduct(context, ref, product),
                  child: const Text('Purchase with K-Coins'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applyTheme(
    BuildContext context,
    WidgetRef ref,
    String themeCode,
  ) async {
    try {
      await ref.read(appThemeControllerProvider.notifier).applyTheme(themeCode);
      if (context.mounted) {
        final message = themeCode == AppTheme.classicThemeCode
            ? 'Classic theme has been restored.'
            : 'Theme applied successfully.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: context.colors.success,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceAll('Exception: ', '')),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }

  Future<void> _handlePurchaseProduct(
    BuildContext context,
    WidgetRef ref,
    StoreProduct product,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Purchase'),
        content: Text(
          'Are you sure you want to spend ${product.price} K-Coins for "${product.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Purchase'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) {
      return;
    }

    try {
      final result = await ref
          .read(storeServiceProvider)
          .buyStoreItem(product.productCode);
      await ref.read(entitlementsProvider.notifier).refresh();
      ref.invalidate(ownedThemeCodesProvider);

      if (!context.mounted) {
        return;
      }

      if (result.isThemePurchase && result.themeCode != null) {
        final applyNow = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.palette_rounded,
              color: context.colors.primaryContainer,
              size: 48,
            ),
            title: const Text('Theme Unlocked'),
            content: Text(
              '${product.title} is now in your collection. Do you want to apply it now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Apply Now'),
              ),
            ],
          ),
        );

        if (applyNow == true && context.mounted) {
          await _applyTheme(context, ref, result.themeCode!);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purchased ${product.title}!'),
            backgroundColor: context.colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceAll('Exception: ', '')),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  SliverToBoxAdapter _buildEmptySliver(
    BuildContext context, {
    required String message,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.colors.outline.withValues(alpha: 0.08),
            ),
          ),
          child: Center(
            child: Text(
              message,
              style: TextStyle(color: context.colors.textMedium),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildErrorSliver(
    BuildContext context, {
    required String message,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.colors.errorContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: context.colors.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _StoreNoticeCard extends StatelessWidget {
  final String message;

  const _StoreNoticeCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.primaryContainer.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: context.colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.colors.textHigh,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
