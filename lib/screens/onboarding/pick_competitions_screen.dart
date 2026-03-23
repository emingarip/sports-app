import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/onboarding_provider.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'notification_prefs_screen.dart';

class PickCompetitionsScreen extends ConsumerStatefulWidget {
  const PickCompetitionsScreen({super.key});

  @override
  ConsumerState<PickCompetitionsScreen> createState() => _PickCompetitionsScreenState();
}

class _PickCompetitionsScreenState extends ConsumerState<PickCompetitionsScreen> {
  final List<Map<String, dynamic>> _competitions = [
    {"title": "Trendyol Super Lig", "subtitle": "Turkey", "icon": Icons.emoji_events, "isLogo": false},
    {"title": "Premier League", "subtitle": "England", "abbr": "PL", "isLogo": true},
    {"title": "La Liga", "subtitle": "Spain", "abbr": "LL", "isLogo": true},
    {"title": "UEFA Champions League", "subtitle": "Europe", "icon": Icons.emoji_events, "isLogo": false},
    {"title": "Serie A", "subtitle": "Italy", "abbr": "SA", "isLogo": true}
  ];

  void _toggleCompetition(String title) {
    ref.read(onboardingProvider.notifier).toggleCompetition(title);
  }

  Widget _buildCompetitionItem(Map<String, dynamic> comp, bool isFirst) {
    final title = comp["title"];
    final selectedCompetitions = ref.watch(onboardingProvider).selectedCompetitions;
    final isSelected = selectedCompetitions.contains(title);

    return GestureDetector(
      onTap: () => _toggleCompetition(title),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.surfaceContainerLow : Colors.transparent,
          border: isFirst ? null : Border(top: BorderSide(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            // Icon / Logo Container
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.surfaceContainer,
              ),
              child: Center(
                child: comp["isLogo"]
                    ? Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            comp["abbr"],
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: context.colors.textMedium,
                            ),
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: context.colors.primaryContainer.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(comp["icon"], color: context.colors.primary, size: 24),
                        ),
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
                    title,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comp["subtitle"],
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: context.colors.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            
            // Checkbox Circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? context.colors.primaryContainer : Colors.transparent,
                border: Border.all(
                  color: isSelected ? context.colors.primaryContainer : context.colors.surfaceContainerHighest,
                  width: 2,
                ),
                boxShadow: isSelected 
                    ? [BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2))]
                    : [],
              ),
              child: isSelected 
                  ? Center(child: Icon(Icons.check, size: 18, color: context.colors.onPrimaryContainer))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCompetitions = ref.watch(onboardingProvider).selectedCompetitions;

    return Scaffold(
      backgroundColor: context.colors.background,
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
                          title: "Follow competitions",
                          subtitle: "Select the leagues you want to track in your live feed.",
                        ),
                        const SizedBox(height: 32),
                        
                        // Central Unified Card Container
                        Container(
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: context.colors.textHigh.withValues(alpha: 0.06),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              children: List.generate(
                                _competitions.length,
                                (index) => _buildCompetitionItem(_competitions[index], index == 0),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Secondary Suggestion/Search Option
                        Center(
                          child: TextButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.search, size: 20),
                            label: const Text(
                              "FIND MORE LEAGUES",
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 64),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            
            // Sticky Action Bar
            OnboardingBottomBar(
              primaryText: selectedCompetitions.isNotEmpty ? "CONTINUE (${selectedCompetitions.length})" : "CONTINUE",
              onPrimaryPressed: selectedCompetitions.isNotEmpty ? () {
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
