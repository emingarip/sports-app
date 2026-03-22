import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/custom_bottom_nav.dart';
import '../theme/app_theme.dart';

import 'home_dashboard.dart';
import 'ai_match_insights_screen.dart';
import 'prediction_market_screen.dart';
import 'profile_screen.dart';

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Stack(
            children: [
              IndexedStack(
                index: currentIndex,
                children: const [
                  HomeDashboard(),
                  AiMatchInsightsScreen(),
                  PredictionMarketScreen(),
                  ProfileScreen(),
                ],
              ),
              const CustomBottomNav(),
            ],
          ),
        ),
      ),
    );
  }
}
