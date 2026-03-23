import 'dart:math';
import 'package:flutter/material.dart';
import '../models/match.dart' as model;
import '../theme/app_theme.dart';

class MatchStatData {
  final String label;
  final int homeValue;
  final int awayValue;
  final bool isPercentage;

  MatchStatData({
    required this.label,
    required this.homeValue,
    required this.awayValue,
    this.isPercentage = false,
  });

  int get total => isPercentage ? 100 : homeValue + awayValue;
  double get homePercentage => total == 0 ? 0 : homeValue / total;
  double get awayPercentage => total == 0 ? 0 : awayValue / total;
}

class MatchStatsView extends StatefulWidget {
  final model.Match match;

  const MatchStatsView({super.key, required this.match});

  @override
  State<MatchStatsView> createState() => _MatchStatsViewState();
}

class _MatchStatsViewState extends State<MatchStatsView> with SingleTickerProviderStateMixin {
  late final List<MatchStatData> _stats;
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _stats = _generateDeterministicStats(widget.match.id);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  List<MatchStatData> _generateDeterministicStats(String matchId) {
    // We seed the random generator using the hashcode of the match ID.
    // This ensures that the generated stats are permanently consistent for the same match.
    final rand = Random(matchId.hashCode);

    int homePossession = 35 + rand.nextInt(31); // 35% to 65%
    int awayPossession = 100 - homePossession;

    int homeTotalShots = rand.nextInt(20) + 5; // 5 to 24
    int awayTotalShots = rand.nextInt(20) + 5;

    int homeShotsOnTarget = (homeTotalShots * (0.3 + rand.nextDouble() * 0.4)).round();
    int awayShotsOnTarget = (awayTotalShots * (0.3 + rand.nextDouble() * 0.4)).round();

    int homeCorners = rand.nextInt(10) + 1; // 1 to 10
    int awayCorners = rand.nextInt(10) + 1;

    int homeFouls = rand.nextInt(15) + 5; // 5 to 19
    int awayFouls = rand.nextInt(15) + 5;

    int homeYellow = rand.nextInt(5); // 0 to 4
    int awayYellow = rand.nextInt(5);

    int homeRed = rand.nextDouble() > 0.85 ? 1 : 0; // 15% chance
    int awayRed = rand.nextDouble() > 0.85 ? 1 : 0;

    int homePasses = 300 + (homePossession * 5) + rand.nextInt(100);
    int awayPasses = 300 + (awayPossession * 5) + rand.nextInt(100);

    return [
      MatchStatData(label: "Ball Possession", homeValue: homePossession, awayValue: awayPossession, isPercentage: true),
      MatchStatData(label: "Expected Goals (xG)", homeValue: (homeShotsOnTarget * 0.15 * 100).round(), awayValue: (awayShotsOnTarget * 0.15 * 100).round()), // Represented conceptually without decimals internally, formatted in UI
      MatchStatData(label: "Total Shots", homeValue: homeTotalShots, awayValue: awayTotalShots),
      MatchStatData(label: "Shots on Target", homeValue: homeShotsOnTarget, awayValue: awayShotsOnTarget),
      MatchStatData(label: "Total Passes", homeValue: homePasses, awayValue: awayPasses),
      MatchStatData(label: "Corner Kicks", homeValue: homeCorners, awayValue: awayCorners),
      MatchStatData(label: "Fouls", homeValue: homeFouls, awayValue: awayFouls),
      MatchStatData(label: "Yellow Cards", homeValue: homeYellow, awayValue: awayYellow),
      MatchStatData(label: "Red Cards", homeValue: homeRed, awayValue: awayRed),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ListView.builder(
          padding: const EdgeInsets.only(top: 24, bottom: 40, left: 24, right: 24),
          itemCount: _stats.length,
          itemBuilder: (context, index) {
            final stat = _stats[index];
            final isXg = stat.label == "Expected Goals (xG)";

            String homeStr = isXg ? (stat.homeValue / 100).toStringAsFixed(2) : (stat.isPercentage ? '${stat.homeValue}%' : '${stat.homeValue}');
            String awayStr = isXg ? (stat.awayValue / 100).toStringAsFixed(2) : (stat.isPercentage ? '${stat.awayValue}%' : '${stat.awayValue}');

            // For visuals, we need percentage out of the total.
            // If total is 0 (e.g., Red Cards 0-0), fill neither.
            double homeFlex = stat.total == 0 ? 0.0 : (stat.homeValue / stat.total);
            double awayFlex = stat.total == 0 ? 0.0 : (stat.awayValue / stat.total);

            // Apply animation scale
            homeFlex *= _animation.value;
            awayFlex *= _animation.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        homeStr,
                        style: TextStyle(
                          color: context.colors.textHigh,
                          fontFamily: 'Lexend',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        stat.label.toUpperCase(),
                        style: TextStyle(
                          color: context.colors.textMedium,
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        awayStr,
                        style: TextStyle(
                          color: context.colors.textHigh,
                          fontFamily: 'Lexend',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Home Bar
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FractionallySizedBox(
                            widthFactor: homeFlex == 0.0 && stat.total == 0 ? 0.0 : homeFlex.clamp(0.02, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: homeFlex > awayFlex ? context.colors.primaryContainer : context.colors.surfaceContainerHighest,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)), // Rounded outer tail
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4), // Middle split
                      // Away Bar
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: awayFlex == 0.0 && stat.total == 0 ? 0.0 : awayFlex.clamp(0.02, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: awayFlex > homeFlex ? context.colors.accent : context.colors.surfaceContainerHighest,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)), // Rounded outer tail
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}
