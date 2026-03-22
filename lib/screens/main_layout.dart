import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/custom_bottom_nav.dart';
import '../theme/app_theme.dart';

import '../widgets/lazy_indexed_stack.dart';
import '../widgets/deferred_widget.dart';

import 'home_dashboard.dart';
import 'ai_match_insights_screen.dart' deferred as insights;
import 'prediction_market_screen.dart' deferred as market;
import 'profile_screen.dart' deferred as profile;

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
              LazyIndexedStack(
                index: currentIndex,
                children: [
                  const HomeDashboard(),
                  DeferredWidget(
                    libraryLoader: insights.loadLibrary,
                    createWidget: () => insights.AiMatchInsightsScreen(),
                  ),
                  DeferredWidget(
                    libraryLoader: market.loadLibrary,
                    createWidget: () => market.PredictionMarketScreen(),
                  ),
                  DeferredWidget(
                    libraryLoader: profile.loadLibrary,
                    createWidget: () => profile.ProfileScreen(),
                  ),
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
