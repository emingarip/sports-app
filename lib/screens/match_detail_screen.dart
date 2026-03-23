import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/match.dart' as model;
import '../services/chat_service.dart';
import '../widgets/match_stats_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/knowledge_graph_provider.dart';

enum MessageType { user, me, systemEvent }

class ChatMessage {
  final String id;
  final MessageType type;
  final String? text;
  final String? time;
  final String? username;
  final String? systemEventText;
  final IconData? systemEventIcon;

  ChatMessage({
    required this.id,
    required this.type,
    this.text,
    this.time,
    this.username,
    this.systemEventText,
    this.systemEventIcon,
  });
}

class FloatingReaction {
  final String id;
  final String emoji;
  final double startX;
  final double drift;

  FloatingReaction({
    required this.id,
    required this.emoji,
    required this.startX,
    required this.drift,
  });
}

class MatchDetailScreen extends ConsumerStatefulWidget {
  final model.Match match;
  const MatchDetailScreen({super.key, required this.match});

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Random _random = Random();
  final FocusNode _focusNode = FocusNode();

  final List<String> _quickReactions = ["🔥", "😱", "😡", "👏", "⚽", "🙌"];

  List<ChatMessage> _messages = [];
  final Map<String, AnimationController> _reactionAnimators = {};
  final List<FloatingReaction> _activeReactions = [];

  late AnimationController _pulseController;
  late AnimationController _bgPulseController;
  bool _hasText = false;
  bool _isInputFocused = false;

  final ChatService _chatService = ChatService();
  StreamSubscription<List<ChatMessage>>? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _bgPulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);

    _msgController.addListener(() {
      if (_hasText != _msgController.text.trim().isNotEmpty) {
        setState(() {
          _hasText = _msgController.text.trim().isNotEmpty;
        });
      }
    });

    _focusNode.addListener(() {
      setState(() {
        _isInputFocused = _focusNode.hasFocus;
      });
    });

    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(knowledgeGraphProvider.notifier);
      
      notifier.trackEvent(
        eventType: 'match_viewed',
        entityType: 'team',
        entityId: widget.match.homeTeam,
      );
      notifier.trackEvent(
        eventType: 'match_viewed',
        entityType: 'team',
        entityId: widget.match.awayTeam,
      );
      notifier.trackEvent(
        eventType: 'match_viewed',
        entityType: 'league',
        entityId: widget.match.leagueId,
      );
    });
    _tabController.addListener(() {
      if (_tabController.index == 2) {
        if (_chatSubscription == null) _subscribeToChat();
      } else {
        _chatSubscription?.cancel();
        _chatSubscription = null;
      }
      setState(() {}); // to show/hide chat elements based on tab index
    });
  }

  void _subscribeToChat() {
    _chatSubscription = _chatService.streamMatchMessages(widget.match.id).listen((messages) {
      if (mounted) {
        setState(() {
          _messages = messages;
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _bgPulseController.dispose();
    _focusNode.dispose();
    for (var c in _reactionAnimators.values) {
      c.dispose();
    }
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _msgController.clear();
    });

    try {
      await _chatService.sendMessage(widget.match.id, text);
      
      // Track chat activity for the knowledge graph 
      ref.read(knowledgeGraphProvider.notifier).trackEvent(
        eventType: 'chat_message_sent',
        entityType: 'league',
        entityId: widget.match.leagueId,
      );

      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  void _sendReaction(String emoji) {
    final id = DateTime.now().millisecondsSinceEpoch.toString() + _random.nextInt(1000).toString();
    final startX = 24.0 + _random.nextDouble() * (MediaQuery.of(context).size.width - 48);
    // tighter drift for more controlled upward flow
    final drift = (_random.nextDouble() - 0.5) * 40; 

    // quicker, crisper animations
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    final reaction = FloatingReaction(id: id, emoji: emoji, startX: startX, drift: drift);

    setState(() {
      _activeReactions.add(reaction);
      _reactionAnimators[id] = controller;
    });

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _activeReactions.removeWhere((r) => r.id == id);
          _reactionAnimators.remove(id)?.dispose();
        });
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 300,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final safeTop = topPadding == 0 ? 44.0 : topPadding;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: MatchDetailHeaderDelegate(
                    match: widget.match,
                    pulseController: _pulseController,
                    bgPulseController: _bgPulseController,
                    topPadding: safeTop,
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverAppBarDelegate(
                    TabBar(
                      controller: _tabController,
                      indicatorColor: context.colors.primaryContainer,
                      labelColor: context.colors.primaryContainer,
                      unselectedLabelColor: context.colors.textMedium,
                      labelStyle: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: "OVERVIEW"),
                        Tab(text: "STATS"),
                        Tab(text: "LIVE CHAT"),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildStatsTab(),
                _buildChatTab(),
              ],
            ),
          ),
          
          if (_tabController.index == 2)
            Positioned.fill(child: _buildFloatingReactions()),
          
          if (_tabController.index == 2)
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomInputArea()),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sports_esports, size: 48, color: context.colors.surfaceContainerHigh),
          const SizedBox(height: 16),
          Text("Match Timeline", style: TextStyle(fontFamily: 'Lexend', fontSize: 18, color: context.colors.textHigh, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Events will appear here.", style: TextStyle(color: context.colors.textMedium)),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    return MatchStatsView(match: widget.match);
  }

  Widget _buildChatTab() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140, top: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isNextSameUser = (index + 1 < _messages.length) && _messages[index + 1].type == msg.type && _messages[index + 1].username == msg.username;
        final isPrevSameUser = (index > 0) && _messages[index - 1].type == msg.type && _messages[index - 1].username == msg.username;
        
        if (msg.type == MessageType.systemEvent) return _buildSystemEvent(msg);
        return _buildMessage(msg, isNextSameUser, isPrevSameUser);
      },
    );
  }

  Widget _buildSystemEvent(ChatMessage msg) {
    final String eventText = msg.text ?? msg.systemEventText ?? "";
    final bool isGoal = eventText.toUpperCase().contains("GOAL");
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isGoal ? context.colors.primaryContainer.withValues(alpha: 0.12) : context.colors.surfaceContainerLow.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isGoal ? context.colors.primaryContainer.withValues(alpha: 0.4) : context.colors.surfaceContainerHighest.withValues(alpha: 0.5)),
            boxShadow: isGoal ? [BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.05), blurRadius: 10)] : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.systemEventIcon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isGoal ? context.colors.primaryContainer.withValues(alpha: 0.4) : context.colors.surfaceContainerHigh.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    msg.systemEventIcon, 
                    size: 14, 
                    color: isGoal ? context.colors.onPrimaryContainer : context.colors.textMedium,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isGoal)
                    Text(
                      "MATCH UPDATE",
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: context.colors.onPrimaryContainer,
                        letterSpacing: 2.0,
                      ),
                    ),
                  if (isGoal) const SizedBox(height: 2),
                  Text(
                    eventText,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: isGoal ? 12 : 11,
                      fontWeight: FontWeight.bold,
                      color: isGoal ? context.colors.onPrimaryContainer : context.colors.textMedium,
                      letterSpacing: 0.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg, bool isNextSameUser, bool isPrevSameUser) {
    final isMe = msg.type == MessageType.me;
    final paddingTop = isPrevSameUser ? 4.0 : 16.0;
    final paddingBottom = isNextSameUser ? 4.0 : 16.0;

    return Padding(
      padding: EdgeInsets.only(top: paddingTop, bottom: paddingBottom, left: 16, right: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            if (!isPrevSameUser)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surfaceContainerHigh,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(Icons.person, color: context.colors.textMedium, size: 20),
              )
            else
              const SizedBox(width: 36),
            const SizedBox(width: 12),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isPrevSameUser) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMe) ...[
                        Text(
                          msg.username ?? "",
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold, color: context.colors.textHigh),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          msg.time ?? "",
                          style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: context.colors.textMedium),
                        ),
                      ] else ...[
                        Text(
                          msg.time ?? "",
                          style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w500, color: context.colors.textMedium),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          msg.username ?? "",
                          style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.bold, color: context.colors.primary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? context.colors.primaryContainer : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular((!isMe && isPrevSameUser) ? 4 : 20),
                      topRight: Radius.circular((isMe && isPrevSameUser) ? 4 : 20),
                      bottomLeft: Radius.circular((!isMe && isNextSameUser) ? 4 : (!isMe ? 4 : 20)),
                      bottomRight: Radius.circular((isMe && isNextSameUser) ? 4 : (isMe ? 4 : 20)),
                    ),
                    border: isMe ? null : Border.all(color: context.colors.surfaceContainerHigh.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 1))
                    ],
                  ),
                  child: Text(
                    msg.text ?? "",
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: isMe ? FontWeight.w500 : FontWeight.normal,
                      color: isMe ? context.colors.onPrimaryContainer : context.colors.textHigh,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (isMe) ...[
            const SizedBox(width: 12),
            if (!isPrevSameUser)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.primaryContainer,
                  border: Border.all(color: context.colors.primaryContainer, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(Icons.person, color: context.colors.onPrimaryContainer, size: 20),
              )
            else
              const SizedBox(width: 36),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomInputArea() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.only(top: 12, bottom: 20, left: 16, right: 16),
          decoration: BoxDecoration(
            color: context.colors.background.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: context.colors.surfaceContainerHighest, width: 0.5)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick Reactions Row (Compact)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 12),
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _quickReactions.map((emoji) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ReactionButton(
                        emoji: emoji,
                        onTap: () => _sendReaction(emoji),
                      ),
                    );
                  }).toList(),
                ),
              ),
              
              // Input Field
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isInputFocused ? context.colors.background : context.colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isInputFocused ? context.colors.primaryContainer : context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
                          width: _isInputFocused ? 2 : 1,
                        ),
                        boxShadow: _isInputFocused ? [BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.1), blurRadius: 8)] : [],
                      ),
                      child: TextField(
                        controller: _msgController,
                        focusNode: _focusNode,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Add to the moment...",
                          hintStyle: TextStyle(color: context.colors.textMedium.withValues(alpha: 0.6), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _hasText ? context.colors.primaryContainer : context.colors.surfaceContainer,
                      shape: BoxShape.circle,
                      boxShadow: _hasText ? [BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))] : [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _hasText ? _sendMessage : null,
                        borderRadius: BorderRadius.circular(24),
                        child: Center(
                          child: Icon(
                            Icons.arrow_upward_rounded, 
                            color: _hasText ? context.colors.onPrimaryContainer : context.colors.textMedium, 
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingReactions() {
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: _activeReactions.map((reaction) {
          final anim = _reactionAnimators[reaction.id]!;
          return AnimatedBuilder(
            animation: anim,
            builder: (context, child) {
              final val = Curves.easeOutCubic.transform(anim.value); // smoother ease
              final bottomOffset = 150 + (val * 450); // rises higher and smoother
              final leftOffset = reaction.startX + (reaction.drift * Curves.easeInOutSine.transform(anim.value));
              
              double opacity = 1.0;
              double scale = 1.0;
              if (anim.value < 0.1) {
                opacity = anim.value / 0.1;
                scale = 0.4 + (0.6 * opacity);
              } else if (anim.value > 0.6) {
                opacity = 1.0 - ((anim.value - 0.6) / 0.4);
                scale = 1.0 + ((anim.value - 0.6) * 0.5); // slight grow before fade tail
              }

              return Transform.translate(
                offset: Offset(leftOffset, -bottomOffset),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: Text(reaction.emoji, style: const TextStyle(fontSize: 36, shadows: [Shadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))])),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

// Micro-motion Button for Reactions
class _ReactionButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionButton({required this.emoji, required this.onTap});

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100), lowerBound: 0.9, upperBound: 1.0)..value = 1.0;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _scaleController.reverse();
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.forward();
    widget.onTap();
  }

  void _onTapCancel() {
    _scaleController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleController.value,
            child: Container(
              width: 48,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.6)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
              ),
              child: Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 20))),
            ),
          );
        }
      ),
    );
  }
}

class MatchDetailHeaderDelegate extends SliverPersistentHeaderDelegate {
  final model.Match match;
  final AnimationController pulseController;
  final AnimationController bgPulseController;
  final double topPadding;

  MatchDetailHeaderDelegate({
    required this.match,
    required this.pulseController,
    required this.bgPulseController,
    required this.topPadding,
  });

  @override
  double get minExtent => topPadding + 64.0;

  @override
  double get maxExtent => topPadding + 260.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double collapseForce = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final double expandedOpacity = (1.0 - (collapseForce * 1.5)).clamp(0.0, 1.0);
    final double collapsedOpacity = ((collapseForce - 0.5) * 2.0).clamp(0.0, 1.0);

    final homeAbbr = match.homeTeam.length >= 3 ? match.homeTeam.substring(0, 3).toUpperCase() : match.homeTeam.toUpperCase();
    final awayAbbr = match.awayTeam.length >= 3 ? match.awayTeam.substring(0, 3).toUpperCase() : match.awayTeam.toUpperCase();
    final scoreStr = "${match.homeScore ?? '-'} - ${match.awayScore ?? '-'}";
    final isLive = match.status == model.MatchStatus.live;
    final statusText = isLive ? match.liveMinute ?? 'LIVE' : (match.status == model.MatchStatus.finished ? "Full Time" : "Upcoming");

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: (collapseForce * 16) == 0.0 ? 0.001 : collapseForce * 16, 
          sigmaY: (collapseForce * 16) == 0.0 ? 0.001 : collapseForce * 16
        ),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.background.withValues(alpha: 1.0 - (1.0 - collapseForce) * 0.15), // from 0.85 to 1.0
            border: Border(bottom: BorderSide(color: context.colors.surfaceContainer.withValues(alpha: collapseForce))),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: collapseForce * 0.04), blurRadius: 10)],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Expanded Score Area
              if (expandedOpacity > 0)
                Opacity(
                  opacity: expandedOpacity,
                  child: AnimatedBuilder(
                    animation: bgPulseController,
                    builder: (context, child) {
                      return Container(
                        padding: EdgeInsets.only(top: topPadding + 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              context.colors.primaryContainer.withValues(alpha: 0.08 + (bgPulseController.value * 0.04)),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: context.colors.primaryContainer.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: Text("MATCH PULSE", style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.5, color: context.colors.primary.withValues(alpha: 0.8))),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                          decoration: BoxDecoration(
                            color: context.colors.background.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, 12)),
                              const BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                    tag: 'match-${match.id}-home-logo',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Image.network(match.homeLogo, width: 44, height: 44, errorBuilder: (ctx, err, _) => const Icon(Icons.shield, size: 44)),
                                    )
                                  ),
                                  const SizedBox(height: 8),
                                  Text(homeAbbr, style: TextStyle(fontFamily: 'Lexend', fontSize: 24, fontWeight: FontWeight.w900, color: context.colors.textHigh)),
                                  const SizedBox(height: 6),
                                  Container(height: 5, width: 36, decoration: BoxDecoration(color: context.colors.primaryContainer, borderRadius: BorderRadius.circular(3), boxShadow: [BoxShadow(color: context.colors.primaryContainer.withValues(alpha: 0.5), blurRadius: 4)])),
                                ],
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(border: Border(left: BorderSide(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.3)), right: BorderSide(color: context.colors.surfaceContainerHighest.withValues(alpha: 0.3)))),
                                child: Text(scoreStr, style: TextStyle(fontFamily: 'Lexend', fontSize: 32, fontWeight: FontWeight.w900, color: context.colors.primary, letterSpacing: -1.0)),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                    tag: 'match-${match.id}-away-logo',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Image.network(match.awayLogo, width: 44, height: 44, errorBuilder: (ctx, err, _) => const Icon(Icons.shield, size: 44)),
                                    )
                                  ),
                                  const SizedBox(height: 8),
                                  Text(awayAbbr, style: TextStyle(fontFamily: 'Lexend', fontSize: 24, fontWeight: FontWeight.w900, color: context.colors.textMedium)),
                                  const SizedBox(height: 6),
                                  Container(height: 5, width: 36, decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(3))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // 2. Collapsed Sticky Bar layer
              if (collapsedOpacity > 0)
                Opacity(
                  opacity: collapsedOpacity,
                  child: Container(
                    padding: EdgeInsets.only(top: topPadding, left: 8, right: 8),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 44), // Space left for absolute back button
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("$homeAbbr vs $awayAbbr · $scoreStr", style: TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w800, color: context.colors.textHigh, letterSpacing: -0.5)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: isLive ? context.colors.secondary.withValues(alpha: 0.08) : context.colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          if (isLive) AnimatedBuilder(
                                            animation: pulseController,
                                            builder: (context, child) {
                                              return Opacity(
                                                opacity: 0.3 + (pulseController.value * 0.7),
                                                child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.secondary)),
                                              );
                                            },
                                          ),
                                          if (isLive) const SizedBox(width: 4),
                                          Text(statusText, style: TextStyle(fontFamily: 'Lexend', fontSize: 10, fontWeight: FontWeight.bold, color: isLive ? context.colors.secondary : context.colors.textMedium, letterSpacing: 0.5)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: context.colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          Icon(Icons.group, size: 12, color: context.colors.textMedium),
                                          const SizedBox(width: 4),
                                          Text("12.4k fans", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w600, color: context.colors.textMedium)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.more_vert), color: context.colors.textMedium, onPressed: () {}, splashRadius: 24),
                      ],
                    ),
                  ),
                ),
              
              // 3. Absolute back button (always visible and functional)
              Positioned(
                top: topPadding + 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back), 
                  color: context.colors.textMedium, 
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant MatchDetailHeaderDelegate oldDelegate) => true;
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.colors.background,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
