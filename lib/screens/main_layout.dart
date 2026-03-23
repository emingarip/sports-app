import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/custom_bottom_nav.dart';
import '../theme/app_theme.dart';
import '../services/push_notification_service.dart';

import 'home_dashboard.dart';
import 'ai_match_insights_screen.dart';
import 'prediction_market_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushNotificationServiceProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
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
                  LeaderboardScreen(),
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
