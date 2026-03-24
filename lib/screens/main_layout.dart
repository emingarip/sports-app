import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/custom_bottom_nav.dart';
import '../theme/app_theme.dart';
import '../services/push_notification_service.dart';
import '../widgets/floating_audio_room.dart';

import 'home_dashboard.dart';
import 'ai_match_insights_screen.dart';
import 'prediction_market_screen.dart';
import 'leaderboard_screen.dart';
import 'profile_screen.dart';
import '../widgets/username_setup_dialog.dart';
import '../services/supabase_service.dart';

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
      _checkUsernameRequirement();
    });
  }

  Future<void> _checkUsernameRequirement() async {
    final user = SupabaseService().getCurrentUser();
    if (user != null) {
      final profile = await SupabaseService().getUserProfile(user.id);
      if (profile == null) return;
      
      final username = profile['username'] as String?;
      
      if (username == null || username.trim().isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const UsernameSetupDialog(),
        );
      }
    }
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
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: FloatingAudioRoom(),
              ),
              const CustomBottomNav(),
            ],
          ),
        ),
      ),
    );
  }
}
