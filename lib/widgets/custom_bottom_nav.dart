import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../screens/home_dashboard.dart';
import '../screens/ai_match_insights_screen.dart';
import '../screens/prediction_market_screen.dart';
import '../screens/profile_screen.dart';
import '../providers/match_provider.dart';

class CustomBottomNav extends ConsumerWidget {
  final int currentIndex;

  const CustomBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
              offset: const Offset(0, 5),
            )
          ],
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(context, ref, 0, "Matches", Icons.sports_soccer),
            _buildNavItem(context, ref, 1, "Insights", Icons.query_stats),
            _buildNavItem(context, ref, 2, "Market", Icons.analytics),
            _buildNavItem(context, ref, 3, "Profile", Icons.person),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, WidgetRef ref, int index, String label, IconData icon) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isSelected) return; // Ignore if already on this screen

        // Routing Logic
        if (index == 0) {
          // Returning to home should pop the stack if pushed, or push replacement 
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeDashboard()), (route) => false);
        } else if (index == 1) {
          final activeMatch = ref.read(matchStateProvider.notifier).activeLiveMatch;
          if (activeMatch != null) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AiMatchInsightsScreen(match: activeMatch)));
          }
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PredictionMarketScreen()));
        } else if (index == 3) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFACC15).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon, 
              color: isSelected ? const Color(0xFFFACC15) : AppTheme.textMedium.withOpacity(0.7), 
              size: isSelected ? 24 : 22
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isSelected ? const Color(0xFFFACC15) : AppTheme.textMedium.withOpacity(0.7),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
