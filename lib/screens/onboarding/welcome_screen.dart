import 'package:flutter/material.dart';
import 'dart:ui';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'pick_teams_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 0.2),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    top: 100,
                    right: -50,
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryContainer.withOpacity(0.15),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),
                        const StepLabel(step: 1),
                        const SizedBox(height: 16),
                        const OnboardingHeader(
                          title: "Welcome to KINETIC",
                          subtitle: "The next-generation sports media platform built for fans who want pure performance and zero clutter.",
                        ),
                        const Spacer(),
                        
                        Opacity(
                          opacity: 0.05,
                          child: Center(
                            child: Text(
                              "KINETIC",
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 80,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                color: AppTheme.textHigh,
                                letterSpacing: -2,
                              ),
                            ),
                          ),
                        ),
                        
                        const Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            OnboardingBottomBar(
              primaryText: "GET STARTED",
              onPrimaryPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PickTeamsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
