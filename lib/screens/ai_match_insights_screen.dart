import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/match_insight.dart';
import '../models/match.dart' as model;
import '../services/insight_service.dart';

class AiMatchInsightsScreen extends StatefulWidget {
  final model.Match match;
  const AiMatchInsightsScreen({super.key, required this.match});

  @override
  State<AiMatchInsightsScreen> createState() => _AiMatchInsightsScreenState();
}

class _AiMatchInsightsScreenState extends State<AiMatchInsightsScreen> {
  List<MatchInsight> _insights = [];
  bool _isLoading = true;
  final InsightService _insightService = InsightService();

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isLoading = true);
    
    try {
      var insights = await _insightService.getInsightsForMatch(widget.match.id);
      
      // If no insights exist, ask the edge function to generate some (if possible)
      // and re-fetch.
      if (insights.isEmpty) {
        await _insightService.generateInsights(widget.match.id);
        insights = await _insightService.getInsightsForMatch(widget.match.id);
      }
      
      if (mounted) {
        setState(() {
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _completedCount => _insights.where((i) => i.isAnswered).length;
  double get _progress => _insights.isEmpty ? 0 : _completedCount / _insights.length;

  void _onVoteChanged(MatchInsight insight, UserVoteType vote) async {
    setState(() {
      insight.userVote = vote;
      if (vote != UserVoteType.disagree) {
        insight.disagreeReason = null;
        insight.customReason = null;
      }
    });
    
    try {
      await _insightService.voteInsight(insight.id, widget.match.id, vote, reason: insight.disagreeReason, customReason: insight.customReason);
    } catch (e) {
      // Handle error gracefully
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AppBar(
              backgroundColor: Colors.white.withOpacity(0.8),
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.primary),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'AI Match Insights',
                style: TextStyle(fontFamily: 'Lexend', fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textHigh),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMedium),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
             SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MatchSummaryCard(
                  completedCount: _completedCount,
                  totalCount: _insights.length,
                  progress: _progress,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final insight = _insights[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InsightCard(
                        insight: insight,
                        onVoteChanged: (vote) => _onVoteChanged(insight, vote),
                      ),
                    );
                  },
                  childCount: _insights.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                 padding: const EdgeInsets.only(top: 12, bottom: 140),
                child: Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.surfaceContainerHigh,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'LOAD MORE INSIGHTS',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textHigh, letterSpacing: 1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 30, offset: const Offset(0, -8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem("Matches", Icons.sports_soccer, false),
                  _buildNavItem("Insights", Icons.query_stats, true),
                  _buildNavItem("Standings", Icons.leaderboard, false),
                  _buildNavItem("Profile", Icons.person, false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(String label, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (!isActive) Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: isActive ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryContainer.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? AppTheme.onPrimaryContainer : AppTheme.textMedium.withOpacity(0.7), size: 24),
            const SizedBox(height: 4),
            Text(label.toUpperCase(), style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? AppTheme.onPrimaryContainer : AppTheme.textMedium.withOpacity(0.7), letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

class MatchSummaryCard extends StatelessWidget {
  final int completedCount;
  final int totalCount;
  final double progress;

  const MatchSummaryCard({
    super.key,
    required this.completedCount,
    required this.totalCount,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceContainerHighest.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Container(width: 56, height: 56, color: Colors.grey[200]), // Placeholder for team logo
                  const SizedBox(height: 8),
                  const Text('LIVERPOOL', style: TextStyle(fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textHigh)),
                ],
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFD8863),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                  const SizedBox(height: 8),
                  const Text('2 - 1', style: TextStyle(fontFamily: 'Lexend', fontSize: 36, fontWeight: FontWeight.w900, color: AppTheme.textHigh)),
                  const SizedBox(height: 4),
                  const Text("74' MINS", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMedium, letterSpacing: 0.5)),
                ],
              ),
              Column(
                children: [
                  Container(width: 56, height: 56, color: Colors.grey[200]), // Placeholder for team logo
                  const SizedBox(height: 8),
                  const Text('R. MADRID', style: TextStyle(fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textHigh)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.surfaceContainerHigh),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('AI generated 10 key insights for this match', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMedium, fontWeight: FontWeight.w500)),
              Text('$completedCount / $totalCount COMPLETED', style: const TextStyle(fontFamily: 'Lexend', fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.surfaceContainer,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryContainer),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class InsightCard extends StatefulWidget {
  final MatchInsight insight;
  final Function(UserVoteType) onVoteChanged;

  const InsightCard({
    super.key,
    required this.insight,
    required this.onVoteChanged,
  });

  @override
  State<InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<InsightCard> with SingleTickerProviderStateMixin {
  bool get _isAnswered => widget.insight.isAnswered;
  bool get _isDisagree => widget.insight.userVote == UserVoteType.disagree;
  
  final List<String> _quickReasons = [
    'Stats misleading',
    'Form not relevant',
    'Key players missing',
    'Tactical mismatch',
  ];

  void _handleVote(UserVoteType vote) {
    widget.onVoteChanged(vote);
  }

  void _selectReason(String reason) {
    setState(() {
      widget.insight.disagreeReason = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDisagree ? AppTheme.error.withOpacity(0.3) : AppTheme.surfaceContainerHighest.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('AI INSIGHT', style: TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppTheme.primary)),
                  ),
                  if (widget.insight.consensusData?.fanLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_fire_department, size: 10, color: AppTheme.secondary),
                          const SizedBox(width: 4),
                          Text(widget.insight.consensusData!.fanLabel!.toUpperCase(), style: const TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (!_isAnswered)
                const Icon(Icons.share, size: 16, color: AppTheme.textMedium),
            ],
          ),
          const SizedBox(height: 12),
          Text(widget.insight.text, style: const TextStyle(fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textHigh, height: 1.4)),
          const SizedBox(height: 16),
          
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isAnswered ? _buildAnsweredState() : _buildActionRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(child: _VoteButton(icon: Icons.thumb_up, label: 'Agree', onTap: () => _handleVote(UserVoteType.agree))),
        const SizedBox(width: 8),
        Expanded(child: _VoteButton(icon: Icons.question_mark, label: 'Not sure', onTap: () => _handleVote(UserVoteType.unsure))),
        const SizedBox(width: 8),
        Expanded(child: _VoteButton(icon: Icons.thumb_down, label: 'Disagree', onTap: () => _handleVote(UserVoteType.disagree))),
      ],
    );
  }

  Widget _buildAnsweredState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.insight.consensusData != null) ...[
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: widget.insight.consensusData!.agreePercent / 100,
                  child: Container(
                    decoration: BoxDecoration(color: AppTheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, size: 12, color: AppTheme.onPrimaryContainer),
                          const SizedBox(width: 4),
                          Text('${widget.insight.consensusData!.agreePercent}% AGREE', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.onPrimaryContainer)),
                        ],
                      ),
                      Row(
                        children: [
                          Text('${widget.insight.consensusData!.unsurePercent}% Unsure', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.textMedium)),
                          const SizedBox(width: 12),
                          Text('${widget.insight.consensusData!.disagreePercent}% Disagree', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.textMedium)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        
        if (_isDisagree)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.surfaceContainerHigh),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WHY DO YOU DISAGREE?', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMedium, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickReasons.map((r) {
                      final isSelected = widget.insight.disagreeReason == r;
                      return GestureDetector(
                        onTap: () => _selectReason(r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.errorContainer : AppTheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? AppTheme.error.withOpacity(0.3) : AppTheme.outline.withOpacity(0.3)),
                          ),
                          child: Text(
                            r, 
                            style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? AppTheme.onErrorContainer : AppTheme.textHigh),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.surfaceContainer),
                    ),
                    child: const TextField(
                      style: TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Add your own...',
                        hintStyle: TextStyle(fontSize: 12, color: AppTheme.textLow),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => _handleVote(UserVoteType.none),
            child: const Text('CHANGE VOTE', style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary, decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _VoteButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppTheme.textHigh),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textHigh)),
          ],
        ),
      ),
    );
  }
}
