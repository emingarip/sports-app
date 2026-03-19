import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'components/toggle_option.dart';
import 'onboarding_ready_screen.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  bool _matchStarts = true;
  bool _goals = true;
  bool _breakingNews = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                      title: "Stay in the loop",
                      subtitle: "Choose what you want to hear about. You can always change this later.",
                    ),
                    const SizedBox(height: 48),
                    ToggleOption(
                      title: "Match Starts",
                      description: "Get notified when your team's matches kick off.",
                      value: _matchStarts,
                      onChanged: (val) => setState(() => _matchStarts = val),
                    ),
                    const Divider(color: AppTheme.surfaceContainerHigh, height: 1),
                    ToggleOption(
                      title: "Goals & Scores",
                      description: "Real-time alerts for goals and final results.",
                      value: _goals,
                      onChanged: (val) => setState(() => _goals = val),
                    ),
                    const Divider(color: AppTheme.surfaceContainerHigh, height: 1),
                    ToggleOption(
                      title: "Breaking News",
                      description: "Major transfers, injuries, and club statements.",
                      value: _breakingNews,
                      onChanged: (val) => setState(() => _breakingNews = val),
                    ),
                  ],
                ),
              ),
            ),
            OnboardingBottomBar(
              primaryText: "CONTINUE",
              onPrimaryPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OnboardingReadyScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
