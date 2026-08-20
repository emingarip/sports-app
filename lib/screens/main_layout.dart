import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/custom_bottom_nav.dart';
import '../theme/app_theme.dart';
import '../services/push_notification_service.dart';
import '../widgets/floating_audio_room.dart';

import 'home_dashboard.dart';
import 'coupon_hub_screen.dart';
import 'bulletin_screen.dart';
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
  static const double _shellMaxWidth = 600;

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

      final username = profile['username']?.toString();

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
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          IndexedStack(
            index: currentIndex,
            children: const [
              HomeDashboard(),
              // Bu yuva daha once AiMatchInsightsScreen'i tasiyordu. Analiz
              // kuponu yalnizca secim yapilinca beliren cubuktan, topluluk
              // akisi ise bulten AppBar'indaki bir ikondan aciliyordu; urunun
              // iki ana vaadi de birinci sinif giris noktasi olmadan
              // kaliyordu. AI analiz ekrani mac detayindan erisilebilir.
              CouponHubScreen(),
              // K-Coin sanal marketin (PredictionMarketScreen) yerini bülten/
              // kupon aracı aldı: sanal market verisi üretimde boş ve kupon
              // akışı bahisçinin ana aracı (Faz 4.2'de K-Coin ile birleşecek).
              BulletinScreen(),
              LeaderboardScreen(),
              ProfileScreen(),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _shellMaxWidth),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: isKeyboardOpen ? const Offset(0, 1.15) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: isKeyboardOpen ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: isKeyboardOpen,
                    child: const Padding(
                      padding: EdgeInsets.only(bottom: 80),
                      child: FloatingAudioRoom(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _shellMaxWidth),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: isKeyboardOpen ? const Offset(0, 1.25) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: isKeyboardOpen ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: isKeyboardOpen,
                    child: const CustomBottomNav(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
