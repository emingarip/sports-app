import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'components/selection_card.dart';
import 'pick_competitions_screen.dart';

class PickTeamsScreen extends StatefulWidget {
  const PickTeamsScreen({super.key});

  @override
  State<PickTeamsScreen> createState() => _PickTeamsScreenState();
}

class _PickTeamsScreenState extends State<PickTeamsScreen> {
  final List<String> _teams = [
    "Galatasaray", "Fenerbahçe", "Beşiktaş", "Trabzonspor",
    "Real Madrid", "Barcelona", "Arsenal", "Manchester City"
  ];
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProgressTopLine(progress: 0.4),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 32),
                        const StepLabel(step: 2),
                        const SizedBox(height: 16),
                        const OnboardingHeader(
                          title: "Pick Your Teams",
                          subtitle: "We'll tailor your feed to prioritize news and matches about the teams you love.",
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
                          final team = _teams[index];
                          final isSelected = _selected.contains(team);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SelectionCard(
                              title: team,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selected.remove(team);
                                  } else {
                                    _selected.add(team);
                                  }
                                });
                              },
                            ),
                          );
                        },
                        childCount: _teams.length,
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
                  MaterialPageRoute(builder: (_) => const PickCompetitionsScreen()),
                );
              } : null,
              secondaryText: "Skip for now",
              onSecondaryPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PickCompetitionsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
