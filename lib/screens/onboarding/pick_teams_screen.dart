import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../theme/app_theme.dart';
import 'components/progress_top_line.dart';
import 'components/step_label.dart';
import 'components/onboarding_header.dart';
import 'components/onboarding_bottom_bar.dart';
import 'pick_competitions_screen.dart';

class PickTeamsScreen extends StatefulWidget {
  const PickTeamsScreen({super.key});

  @override
  State<PickTeamsScreen> createState() => _PickTeamsScreenState();
}

class _PickTeamsScreenState extends State<PickTeamsScreen> {
  final List<Map<String, dynamic>> _teams = [
    {"name": "Arsenal FC", "league": "Premier League", "abbr": "ARS"},
    {"name": "Real Madrid", "league": "La Liga", "abbr": "RMA"},
    {"name": "Galatasaray", "league": "Trendyol Süper Lig", "abbr": "GS"},
    {"name": "Fenerbahçe", "league": "Trendyol Süper Lig", "abbr": "FB"},
    {"name": "Beşiktaş", "league": "Trendyol Süper Lig", "abbr": "BJK"},
  ];

  final Set<String> _selectedTeams = {};
  final Set<String> _alertsOn = {};

  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.75);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleTeam(String teamName) {
    setState(() {
      if (_selectedTeams.contains(teamName)) {
        _selectedTeams.remove(teamName);
      } else {
        _selectedTeams.add(teamName);
      }
    });
  }

  void _toggleAlert(String teamName, bool value) {
    setState(() {
      if (value) {
        _alertsOn.add(teamName);
      } else {
        _alertsOn.remove(teamName);
      }
    });
  }

  Widget _buildCarouselCard(int index) {
    final team = _teams[index];
    final String teamName = team["name"];
    final bool isSelected = _selectedTeams.contains(teamName);
    final bool alertOn = _alertsOn.contains(teamName);

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double value = 1.0;
        if (_pageController.position.haveDimensions) {
          value = _pageController.page! - index;
          value = (1 - (value.abs() * 0.15)).clamp(0.0, 1.0);
        }

        final double horizontalOffset = (_pageController.position.haveDimensions) 
            ? (_pageController.page! - index) * -20.0 
            : 0;

        return Center(
          child: Transform.translate(
            offset: Offset(horizontalOffset, 0),
            child: Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value.clamp(0.4, 1.0),
                child: child,
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: () => _toggleTeam(teamName),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: AspectRatio(
            aspectRatio: 4 / 5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.surfaceContainerLowest : AppTheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryContainer : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: AppTheme.primaryContainer.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 12))]
                    : const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned.fill(
                    child: Center(
                      child: Opacity(
                        opacity: 0.03,
                        child: Icon(Icons.sports_soccer, size: 280, color: AppTheme.textHigh),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryContainer,
                        ),
                        child: const Icon(Icons.check, size: 20, color: AppTheme.onPrimaryContainer),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.surfaceContainerHighest, width: 1),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                          ),
                          child: Center(
                            child: Text(
                              team["abbr"],
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          team["league"].toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          teamName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? AppTheme.textHigh : AppTheme.textMedium,
                            height: 1.1,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: AppTheme.surfaceContainerHigh),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications, size: 18, color: alertOn ? AppTheme.primary : AppTheme.textMedium),
                              const SizedBox(width: 8),
                              Text(
                                "ALERTS ${alertOn ? 'ON' : 'OFF'}",
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: alertOn ? AppTheme.textHigh : AppTheme.textMedium,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 20,
                                child: Transform.scale(
                                  scale: 0.7,
                                  child: CupertinoSwitch(
                                    value: alertOn,
                                    activeTrackColor: AppTheme.primaryContainer,
                                    thumbColor: alertOn ? AppTheme.onPrimaryContainer : Colors.white,
                                    onChanged: (val) => _toggleAlert(teamName, val),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Structural Component
            const ProgressTopLine(progress: 0.4),
            
            // Header Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  const StepLabel(step: 2),
                  const SizedBox(height: 16),
                  const OnboardingHeader(
                    title: "Pick teams to follow",
                    subtitle: "Select at least 3 teams to personalize your experience",
                  ),
                  const SizedBox(height: 16),
                  
                  // Selection Counter
                  Center(
                    child: Text(
                      "${_selectedTeams.length} OF 3 SELECTED",
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: AppTheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            
            // Interactive Carousel Area
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.45,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _teams.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildCarouselCard(index);
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Swiper interaction hints & Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _teams.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: index == _currentIndex ? 24 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: index == _currentIndex ? AppTheme.primaryContainer : AppTheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swipe, size: 16, color: AppTheme.textMedium.withOpacity(0.8)),
                      const SizedBox(width: 8),
                      Text(
                        "SWIPE TO EXPLORE",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          color: AppTheme.textMedium.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Structural Component
            OnboardingBottomBar(
              primaryText: _selectedTeams.isNotEmpty 
                  ? "CONTINUE (${_selectedTeams.length})" 
                  : "CONTINUE",
              onPrimaryPressed: _selectedTeams.isNotEmpty ? () {
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
