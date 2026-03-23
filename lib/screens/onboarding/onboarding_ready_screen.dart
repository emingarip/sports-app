import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/knowledge_graph_provider.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_bottom_bar.dart';
import '../main_layout.dart';
import '../../services/supabase_service.dart';

class OnboardingReadyScreen extends ConsumerStatefulWidget {
  const OnboardingReadyScreen({super.key});

  @override
  ConsumerState<OnboardingReadyScreen> createState() => _OnboardingReadyScreenState();
}

class _OnboardingReadyScreenState extends ConsumerState<OnboardingReadyScreen> with SingleTickerProviderStateMixin {
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
      backgroundColor: context.colors.background,
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
                        color: context.colors.primaryContainer.withValues(alpha: 0.2),
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
                                          color: context.colors.primaryContainer.withValues(alpha: 0.2),
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
                                    color: context.colors.primaryContainer,
                                    boxShadow: [
                                      BoxShadow(color: context.colors.primary.withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 20)),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(Icons.check_circle, color: context.colors.onPrimaryContainer, size: 64),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            "You're all set!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: context.colors.textHigh,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "We've customized your feed with the teams and competitions you selected.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              color: context.colors.textMedium,
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
                  // Push onboarding selections to Knowledge Graph
                  final selectedTeams = ref.read(onboardingProvider).selectedTeams;
                  final selectedCompetitions = ref.read(onboardingProvider).selectedCompetitions;
                  final kg = ref.read(knowledgeGraphProvider.notifier);

                  for (final team in selectedTeams) {
                    kg.trackEvent(
                      eventType: 'onboarding_selected', 
                      entityType: 'team', 
                      entityId: team
                    );
                  }

                  for (final comp in selectedCompetitions) {
                    kg.trackEvent(
                      eventType: 'onboarding_selected', 
                      entityType: 'league', 
                      entityId: comp
                    );
                  }

                  await SupabaseService().completeOnboarding();
                } catch (e) {
                  debugPrint("Failed to update onboarding status: $e");
                }
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainLayout()),
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
