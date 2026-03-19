import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart' as model;
import '../theme/app_theme.dart';
import 'match_card.dart';
import 'sticky_header_delegate.dart';

class LeagueGroup extends StatelessWidget {
  final League league;
  final List<model.Match> matches;
  final bool isExpanded;
  final VoidCallback onToggle;

  const LeagueGroup({
    super.key,
    required this.league,
    required this.matches,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: StickyHeaderDelegate(
              minHeight: 48,
              maxHeight: 48,
              child: Container(
                color: AppTheme.background,
                alignment: Alignment.center,
                child: InkWell(
                  onTap: onToggle,
                  child: Row(
                    children: [
                      Image.network(league.logoUrl, width: 24, height: 24, errorBuilder: (ctx, err, _) => const Icon(Icons.shield, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          league.name, 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textHigh),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                           color: AppTheme.surfaceContainerLow,
                           borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text("${matches.length} Matches", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMedium)),
                      ),
                      const SizedBox(width: 8),
                      Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.textMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isExpanded)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.surfaceContainerLow),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: List.generate(matches.length, (index) {
                    return MatchCard(
                      match: matches[index],
                      hasBorder: index != matches.length - 1,
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
