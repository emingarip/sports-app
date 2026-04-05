import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/screens/store_front_screen.dart';
import 'package:sports_app/models/k_coin_package.dart';
import 'package:sports_app/models/reward_claim_result.dart';
import 'package:sports_app/providers/wallet_provider.dart';
import 'package:sports_app/theme/app_theme.dart';

void main() {
  testWidgets('StoreFrontScreen compiles and displays packages and balance',
      (WidgetTester tester) async {
    // 1. Prepare Mock Data
    final mockPackages = [
      KCoinPackage(
        id: 'pkg_1',
        title: 'Starter Pack',
        coinAmount: 100,
        priceUsd: 0.99,
        storeProductId: 'com.sportsapp.starter',
      ),
      KCoinPackage(
        id: 'pkg_2',
        title: 'Pro Pack',
        coinAmount: 500,
        priceUsd: 4.99,
        storeProductId: 'com.sportsapp.pro',
      ),
    ];

    // 2. Pump the widget with overridden providers
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Override the packages provider to return our mock list synchronously
          kCoinPackagesProvider.overrideWith((ref) async => mockPackages),
          // Override the balance provider to show a specific balance
          walletBalanceProvider.overrideWith(() => MockWalletBalance(1500)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: StoreFrontScreen(),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();

    // Check if loading state is handled and data appears
    await tester.pump(
        const Duration(milliseconds: 100)); // allow FutureProvider to emit

    // 3. Verify UI Elements
    // Verify the Balance is displayed
    expect(find.text('1500'), findsOneWidget);

    // Verify the Packages are displayed
    expect(find.text('Starter Pack'), findsOneWidget);
    expect(find.text('100 Coins'), findsOneWidget); // Coin amount

    expect(find.text('Pro Pack'), findsOneWidget);
    expect(find.text('500 Coins'), findsOneWidget);

    // Verify buttons are rendered
    expect(find.text('Claim Debug Reward'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsWidgets);
  });
}

// A simple mock for WalletBalance Notifier
class MockWalletBalance extends WalletBalance {
  final int initialBalance;

  MockWalletBalance(this.initialBalance);

  @override
  int build() {
    return initialBalance;
  }

  @override
  Future<void> purchasePackage(KCoinPackage package) async {
    // Mock the purchase by simply adding to state
    state += package.coinAmount;
  }

  @override
  Future<RewardClaimResult> claimTestReward() async {
    // Mock the claim by simply adding 50
    state += 50;
    return const RewardClaimResult(
      success: true,
      pointsAwarded: 50,
      matchedRules: [],
      badgesAwarded: [],
    );
  }
}
