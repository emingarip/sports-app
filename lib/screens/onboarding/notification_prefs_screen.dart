import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'onboarding_ready_screen.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  // 0: Goals only, 1: Important moments, 2: All events
  int _selectedIndex = 1;

  final List<Map<String, dynamic>> _options = [
    {
      "title": "Goals only",
      "subtitle": "Only major score updates",
      "icon": Icons.sports_soccer,
    },
    {
      "title": "Important moments",
      "subtitle": "Goals, cards, and halftime scores",
      "icon": Icons.bolt,
    },
    {
      "title": "All events",
      "subtitle": "Full play-by-play updates",
      "icon": Icons.stream,
    },
  ];

  Widget _buildOptionRow(int index) {
    final option = _options[index];
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primaryContainer.withOpacity(0.3) : Colors.transparent,
          border: index == 0 ? null : Border(top: BorderSide(color: context.colors.surfaceContainerHigh.withOpacity(0.5))),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? context.colors.primaryContainer : context.colors.surfaceContainer,
              ),
              child: Center(
                child: Icon(
                  option["icon"],
                  color: isSelected ? context.colors.onPrimaryContainer : context.colors.surfaceContainerHighest,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                      option["title"],
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option["subtitle"],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        color: isSelected ? context.colors.primary : context.colors.textMedium,
                      ),
                    ),
                ],
              ),
            ),
            
            // Radio/Check circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? context.colors.primaryContainer : Colors.transparent,
                border: Border.all(
                  color: isSelected ? context.colors.primaryContainer : context.colors.surfaceContainerHighest,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(child: Icon(Icons.check, size: 16, color: context.colors.onPrimaryContainer))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 0.8),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    const StepLabel(step: 4),
                    const SizedBox(height: 16),
                    const OnboardingHeader(
                      title: "Stay updated in real time",
                      subtitle: "Choose your match alert preferences to stay ahead of the action.",
                    ),
                    const SizedBox(height: 24),
                    
                    // Visual Asset Placeholder
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.colors.surfaceContainerHighest.withOpacity(0.5),
                            context.colors.surfaceContainerLow,
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Center(
                              child: Opacity(
                                opacity: 0.08,
                                child: Icon(Icons.stadium, size: 120, color: context.colors.textHigh),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceContainerLowest.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(32),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_active, size: 16, color: context.colors.secondary),
                                  const SizedBox(width: 8),
                                  Text(
                                    "LIVE TRACKING ACTIVE",
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      color: context.colors.textHigh,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Unified Preference Card
                    Container(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.textHigh.withOpacity(0.06),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          children: List.generate(
                            _options.length,
                            (index) => _buildOptionRow(index),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 64),
                  ],
                ),
              ),
            ),
            
            // Custom Bottom Action Bar (Nav Bar)
            Container(
              padding: const EdgeInsets.only(top: 16, bottom: 24, left: 24, right: 24),
              decoration: BoxDecoration(
                color: context.colors.background.withOpacity(0.9),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.textHigh.withOpacity(0.04),
                    blurRadius: 32,
                    offset: const Offset(0, -12),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Skip Action
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OnboardingReadyScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 24, color: context.colors.textMedium),
                          const SizedBox(height: 4),
                          Text(
                            "Skip",
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: context.colors.textMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Enable Notifications Action
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OnboardingReadyScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryContainer,
                      foregroundColor: context.colors.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      elevation: 4,
                      shadowColor: context.colors.primaryContainer.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_active, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Enable Notifications",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
