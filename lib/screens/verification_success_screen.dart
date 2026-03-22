import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/app_theme.dart';
import 'onboarding/welcome_screen.dart';
import '../services/supabase_service.dart';
import 'main_layout.dart';

class VerificationSuccessScreen extends StatefulWidget {
  const VerificationSuccessScreen({super.key});

  @override
  State<VerificationSuccessScreen> createState() => _VerificationSuccessScreenState();
}

class _VerificationSuccessScreenState extends State<VerificationSuccessScreen> with SingleTickerProviderStateMixin {
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

    // Auto navigate after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        final user = SupabaseService().getCurrentUser();
        final dynamic claim = user?.userMetadata?['onboarding_completed'];
        final bool onboardingCompleted = claim == true || claim == 'true' || claim == 1;
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => onboardingCompleted ? const MainLayout() : const WelcomeScreen()),
          (route) => false,
        );
      }
    });
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
        child: Stack(
          children: [
            // Background Orbs
            Positioned(
              top: MediaQuery.of(context).size.height * 0.15,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.primaryContainer.withOpacity(0.2),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.1,
              right: -80,
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.secondaryContainer.withOpacity(0.1),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            
            // Bottom "VELOCITY" Wordmark
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  "VELOCITY",
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh.withOpacity(0.05),
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            
            Column(
              children: [
                // Top Accent Line
                Container(
                  height: 2,
                  width: double.infinity,
                  color: context.colors.primaryContainer,
                ),
                
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: context.colors.textMedium),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            "Verification",
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.colors.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Balance for centering
                    ],
                  ),
                ),
                
                // Centered Content
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Hero Animation
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
                                          color: context.colors.primaryContainer.withOpacity(0.2),
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
                                      BoxShadow(color: context.colors.primary.withOpacity(0.15), blurRadius: 40, offset: const Offset(0, 20)),
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
                          
                          // Texts
                          Text(
                            "Verified",
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: context.colors.textHigh,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Successfully authenticated.",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 18,
                              color: context.colors.textMedium,
                            ),
                          ),
                          const SizedBox(height: 64),
                          
                          // Status Indicators
                          SizedBox(
                            width: 320,
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "SYSTEM READY",
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: context.colors.primary.withOpacity(0.6),
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    Text(
                                      "100%",
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: context.colors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Progress Bar
                                Container(
                                  height: 6,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: context.colors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: 0.85,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: context.colors.primaryContainer,
                                        borderRadius: BorderRadius.circular(3),
                                        boxShadow: [
                                          BoxShadow(color: context.colors.primaryContainer.withOpacity(0.4), blurRadius: 12),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                Text(
                                  "FINALIZING SECURE CONNECTION...",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.textLow,
                                    letterSpacing: 2,
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
