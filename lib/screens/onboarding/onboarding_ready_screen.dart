import 'package:flutter/material.dart';
import 'dart:ui';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_bottom_bar.dart';
import '../home_dashboard.dart';
import '../../services/supabase_service.dart';

class OnboardingReadyScreen extends StatefulWidget {
  const OnboardingReadyScreen({super.key});

  @override
  State<OnboardingReadyScreen> createState() => _OnboardingReadyScreenState();
}

class _OnboardingReadyScreenState extends State<OnboardingReadyScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 1.0),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.2,
                    left: -80,
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryContainer.withOpacity(0.2),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                  
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const StepLabel(step: 5),
                          const SizedBox(height: 40),
                          SizedBox(
                            width: 160,
                            height: 160,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _pulseAnimation.value,
                                      child: Container(
                                        width: 128,
                                        height: 128,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppTheme.primaryContainer.withOpacity(0.2),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Container(
                                  width: 128,
                                  height: 128,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.primaryContainer,
                                    boxShadow: [
                                      BoxShadow(color: AppTheme.primary.withOpacity(0.15), blurRadius: 40, offset: const Offset(0, 20)),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.check_circle, color: AppTheme.onPrimaryContainer, size: 64),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          const Text(
                            "You're all set!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textHigh,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "We've customized your feed with the teams and competitions you selected.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              color: AppTheme.textMedium,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
            OnboardingBottomBar(
              primaryText: "GO TO DASHBOARD",
              onPrimaryPressed: () async {
                try {
                  await SupabaseService().completeOnboarding();
                } catch (e) {
                  debugPrint("Failed to update onboarding status: $e");
                }
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeDashboard()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
