import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'components/selection_card.dart';
import 'notification_prefs_screen.dart';

class PickCompetitionsScreen extends StatefulWidget {
  const PickCompetitionsScreen({super.key});

  @override
  State<PickCompetitionsScreen> createState() => _PickCompetitionsScreenState();
}

class _PickCompetitionsScreenState extends State<PickCompetitionsScreen> {
  final List<Map<String, String>> _competitions = [
    {"title": "Trendyol Super Lig", "subtitle": "Turkey"},
    {"title": "Premier League", "subtitle": "England"},
    {"title": "La Liga", "subtitle": "Spain"},
    {"title": "UEFA Champions League", "subtitle": "Europe"},
    {"title": "Serie A", "subtitle": "Italy"}
  ];
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 0.6),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 32),
                        const StepLabel(step: 3),
                        const SizedBox(height: 16),
                        const OnboardingHeader(
                          title: "Pick Competitions",
                          subtitle: "Follow entire leagues and tournaments so you don't miss any major events.",
                        ),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final comp = _competitions[index];
                          final isSelected = _selected.contains(comp["title"]);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SelectionCard(
                              title: comp["title"]!,
                              subtitle: comp["subtitle"],
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selected.remove(comp["title"]);
                                  } else {
                                    _selected.add(comp["title"]!);
                                  }
                                });
                              },
                            ),
                          );
                        },
                        childCount: _competitions.length,
                      ),
                    ),
                  )
                ],
              ),
            ),
            OnboardingBottomBar(
              primaryText: "CONTINUE",
              onPrimaryPressed: _selected.isNotEmpty ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationPrefsScreen()),
                );
              } : null,
              secondaryText: "Skip for now",
              onSecondaryPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationPrefsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
