import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../data/providers/ai_sport_agent_lineup_provider.dart';
import '../data/providers/ai_sport_agent_timeline_provider.dart';
import '../theme/app_theme.dart';
import '../models/match.dart' as model;
import '../models/match_lineup.dart';
import '../models/match_timeline.dart';
import '../services/chat_service.dart';
import '../widgets/match_stats_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/knowledge_graph_provider.dart';
import '../services/widget_service.dart';
import 'mini_game_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tts_service.dart';
import 'private_chat_screen.dart';
import '../widgets/frame_avatar.dart';
import '../widgets/match/match_voice_rooms_tab.dart';

enum MessageType { user, me, systemEvent }

class ChatMessage {
  final String id;
  final MessageType type;
  final String? text;
  final String? time;
  final String? username;
  final String? systemEventText;
  final IconData? systemEventIcon;
  final String? userId;
  final String? avatarUrl;
  final String? activeFrame;
  final bool isBot;

  // Interactions
  final String? replyToId;
  final String? replyToUsername;
  final String? replyToText;

  List<ChatMessage>? replies;

  ChatMessage({
    required this.id,
    required this.type,
    this.text,
    this.time,
    this.username,
    this.systemEventText,
    this.systemEventIcon,
    this.userId,
    this.avatarUrl,
    this.activeFrame,
    this.isBot = false,
    this.replyToId,
    this.replyToUsername,
    this.replyToText,
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

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen>
    with TickerProviderStateMixin {
  static const double _detailShellMaxWidth = 600;
  late TabController _tabController;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController(); // Outer scroll
  final ScrollController _chatScrollController =
      ScrollController(); // Inner chat scroll
  final Random _random = Random();
  final FocusNode _focusNode = FocusNode();
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  Future<MatchLineupReport>? _lineupFuture;
  Future<MatchTimelineReport>? _timelineFuture;
  MatchTimelineReport? _timelineReport;
  WebSocketChannel? _timelineChannel;
  StreamSubscription<dynamic>? _timelineSubscription;
  Timer? _timelineReconnectTimer;

  final List<String> _quickReactions = ["🔥", "😱", "😡", "👏", "⚽", "🙌"];

  List<ChatMessage> _messages = [];
  List<ChatMessage> _groupedMessages = [];
  final Map<String, AnimationController> _reactionAnimators = {};
  final List<FloatingReaction> _activeReactions = [];

  double _hypeLevel = 0.0;
  int _messagesInLastWindow = 0;
  Timer? _hypeTimer;

  late AnimationController _pulseController;
  late AnimationController _bgPulseController;
  bool _hasText = false;
  bool _isInputFocused = false;

  final ChatService _chatService = ChatService();
  StreamSubscription<List<ChatMessage>>? _chatSubscription;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _gameChannel;

  bool _isDrivingModeActive = false;
  Timer? _drivingModeTimer;

  String? _activeMiniGameId;
  String? _activeMiniGameType;

  // Interactions State
  ChatMessage? _replyingToMessage;
  final Set<String> _expandedMessageIds = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _bgPulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);

    _hypeTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _calculateHype();
    });

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

    _tabController = TabController(length: 5, vsync: this);
    _lineupFuture =
        ref.read(aiSportAgentLineupProvider).fetchLineups(widget.match.id);
    _timelineFuture =
        ref.read(aiSportAgentTimelineProvider).fetchTimeline(widget.match.id);
    _connectTimelineRealtime();
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

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

      notifier.trackEvent(
        eventType: 'match_viewed',
        entityType: 'match',
        entityId: widget.match.id,
      );

      _initWidgets();
    });

    _tabController.addListener(() {
      if (_tabController.index == 4) {
        if (_chatSubscription == null) _subscribeToChat();
      } else {
        _chatSubscription?.cancel();
        _chatSubscription = null;
      }
      setState(() {});
    });

    _setupPresence();
    _subscribeToGameEvents();
  }

  void _subscribeToGameEvents() {
    print(
        '--- SETTING UP GAME EVENTS SUBSCRIPTION FOR match_${widget.match.id}');
    _gameChannel = Supabase.instance.client.channel('match_${widget.match.id}');
    _gameChannel!
        .onBroadcast(
            event: 'mini_game',
            callback: (payload) {
              print('--- BROADCAST RECEIVED (mini_game): \$payload');
              if (!mounted) return;

              final Map<String, dynamic> innerPayload =
                  payload.containsKey('payload')
                      ? (payload['payload'] as Map<String, dynamic>? ?? {})
                      : payload;

              final action = innerPayload['action'] as String?;

              if (action == 'START_MINI_GAME') {
                setState(() {
                  _activeMiniGameId = innerPayload['gameId'] as String?;
                  _activeMiniGameType = innerPayload['gameType'] as String?;
                });
              } else if (action == 'GAME_WINNERS') {
                setState(() {
                  _activeMiniGameId = null;
                  _activeMiniGameType = null;
                });

                // Eğer kullanıcı şu an MiniGameScreen'deyse, onu kapatıp MatchDetailScreen'e geri dönmesini sağla
                Navigator.popUntil(context,
                    (route) => route.settings.name != 'MiniGameScreen');

                final winners = innerPayload['winners'] as List<dynamic>? ?? [];
                _showWinnersDialog(winners);
              }
            })
        .onBroadcast(
            event: 'reaction',
            callback: (payload) {
              print(
                  '--- BROADCAST RECEIVED (reaction): \${payload.toString()}');
              if (!mounted) return;

              final Map<String, dynamic> innerPayload =
                  payload.containsKey('payload')
                      ? (payload['payload'] as Map<String, dynamic>? ?? {})
                      : payload;

              final emoji = innerPayload['emoji'] as String?;
              final senderSession = innerPayload['sessionId'] as String?;

              if (emoji != null && senderSession != _sessionId) {
                setState(() {
                  _messagesInLastWindow += 1;
                });
                _showFloatingReaction(emoji);
              }
            })
        .subscribe((status, [error]) {
      print('--- GAME EVENTS SUBSCRIPTION STATUS: $status, ERROR: $error');
    });
  }

  void _showWinnersDialog(List<dynamic> winners) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("🏆 Yarışma Sonucu",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: winners.map((w) {
            final rank = w['rank'];
            final score = w['score'];
            final reward = w['reward'];
            // In a real app we'd fetch usernames, but we will assume 'Top Sektirme' or anonymous if not provided
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: rank == 1
                    ? Colors.amber
                    : rank == 2
                        ? Colors.grey[300]
                        : Colors.orange[300],
                child: Text("#$rank",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              title: Text("Skor: $score",
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text("+$reward K-Coin",
                  style: const TextStyle(color: Colors.greenAccent)),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Kapat",
                style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _initWidgets() async {
    try {
      await WidgetService().initialize();

      final homeScoreInt = int.tryParse(widget.match.homeScore ?? '0') ?? 0;
      final awayScoreInt = int.tryParse(widget.match.awayScore ?? '0') ?? 0;

      // Update persistent Home Screen Widget
      await WidgetService().updateHomeScreenWidget(
        homeTeam: widget.match.homeTeam,
        awayTeam: widget.match.awayTeam,
        homeScore: homeScoreInt,
        awayScore: awayScoreInt,
      );

      // Start iOS Live Activity if match is Live
      if (widget.match.status == model.MatchStatus.live) {
        await WidgetService().startOrUpdateLiveActivity(
          matchId: widget.match.id,
          homeTeam: widget.match.homeTeam,
          awayTeam: widget.match.awayTeam,
          homeScore: homeScoreInt,
          awayScore: awayScoreInt,
          minute: "${widget.match.liveMinute ?? 0}'",
          status: widget.match.status.name,
        );
      }
    } catch (e) {
      debugPrint("Widget Initialization Error: \$e");
    }
  }

  void _setupPresence() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _presenceChannel =
        Supabase.instance.client.channel('global_match_presence');

    _presenceChannel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _presenceChannel!.track({
          'user_id': user.id,
          'match_id': widget.match.id,
        });
      }
    });
  }

  void _subscribeToChat() {
    _chatSubscription =
        _chatService.streamMatchMessages(widget.match.id).listen((messages) {
      if (mounted) {
        final newMessagesCount = messages.length - _messages.length;
        if (newMessagesCount > 0 && _messages.isNotEmpty) {
          _messagesInLastWindow += newMessagesCount;
        }

        final Map<String, ChatMessage> map = {};
        for (var m in messages) {
          m.replies = [];
          map[m.id] = m;
        }

        final List<ChatMessage> topLevel = [];
        for (var msg in messages.reversed) {
          if (msg.replyToId != null && map.containsKey(msg.replyToId)) {
            map[msg.replyToId]!.replies!.add(msg);
          } else {
            topLevel.insert(0, msg);
          }
        }

        setState(() {
          _messages = messages;
          _groupedMessages = topLevel;
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
    _chatScrollController.dispose();
    _pulseController.dispose();
    _bgPulseController.dispose();
    _focusNode.dispose();
    for (var c in _reactionAnimators.values) {
      c.dispose();
    }
    _chatSubscription?.cancel();
    _presenceChannel?.unsubscribe();
    _gameChannel?.unsubscribe();
    _drivingModeTimer?.cancel();
    _closeTimelineRealtime();
    _hypeTimer?.cancel();
    TtsService().stop();
    WidgetService().endLiveActivity();
    super.dispose();
  }

  void _connectTimelineRealtime() {
    _closeTimelineRealtime();
    if (widget.match.status != model.MatchStatus.live) {
      return;
    }
    try {
      final provider = ref.read(aiSportAgentTimelineProvider);
      final channel = provider.connectTimeline(
        widget.match.id,
        date: widget.match.startTime,
      );
      _timelineChannel = channel;
      _timelineSubscription = channel.stream.listen(
        (message) {
          final report = provider.timelineFromSocketMessage(message);
          if (report == null || !mounted) return;
          setState(() {
            _timelineReport = report;
            _timelineFuture = Future.value(report);
          });
        },
        onError: (_) => _scheduleTimelineReconnect(),
        onDone: _scheduleTimelineReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleTimelineReconnect();
    }
  }

  void _scheduleTimelineReconnect() {
    if (!mounted || widget.match.status != model.MatchStatus.live) {
      return;
    }
    _timelineReconnectTimer?.cancel();
    _timelineReconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _connectTimelineRealtime();
      }
    });
  }

  void _closeTimelineRealtime() {
    _timelineReconnectTimer?.cancel();
    _timelineReconnectTimer = null;
    _timelineSubscription?.cancel();
    _timelineSubscription = null;
    _timelineChannel?.sink.close();
    _timelineChannel = null;
  }

  Future<void> _refreshTimeline() async {
    final nextFuture =
        ref.read(aiSportAgentTimelineProvider).fetchTimeline(widget.match.id);
    if (mounted) {
      setState(() => _timelineFuture = nextFuture);
    }
    final report = await nextFuture;
    if (mounted) {
      setState(() => _timelineReport = report);
    }
  }

  void _calculateHype() {
    if (!mounted) return;
    setState(() {
      double increase = _messagesInLastWindow * 0.15;
      _hypeLevel += increase;
      if (_messagesInLastWindow == 0) {
        _hypeLevel -= 0.1;
      }
      _hypeLevel = _hypeLevel.clamp(0.0, 1.0);
      _messagesInLastWindow = 0;

      if (_hypeLevel >= 0.8) {
        HapticFeedback.heavyImpact();
      }
    });
  }

  Widget _buildHypeBadge() {
    if (_hypeLevel <= 0.0) return const SizedBox.shrink();

    final percentage = (_hypeLevel * 100).toInt();
    final isHighHype = _hypeLevel >= 0.8;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isHighHype
                ? context.colors.liveAccent.withValues(alpha: 0.82)
                : context.colors.overlayScrim.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHighHype
                  ? context.colors.surface.withValues(alpha: 0.5)
                  : context.colors.surface.withValues(alpha: 0.1),
            ),
            boxShadow: isHighHype
                ? [
                    BoxShadow(
                      color: context.colors.liveAccent.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isHighHype ? "🔥" : "⚡",
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(
                "Nabız: %$percentage",
                style: TextStyle(
                    color: context.colors.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Lexend'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleDrivingMode() async {
    setState(() {
      _isDrivingModeActive = !_isDrivingModeActive;
    });

    if (_isDrivingModeActive) {
      await TtsService().initTts();
      _playDrivingModeUpdate();

      // Her 60 saniyede bir skoru okur
      _drivingModeTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _playDrivingModeUpdate();
      });
    } else {
      _drivingModeTimer?.cancel();
      await TtsService().stop();
    }
  }

  void _playDrivingModeUpdate() {
    if (!mounted) return;
    final home = widget.match.homeTeam;
    final away = widget.match.awayTeam;
    final homeScore = widget.match.homeScore ?? '0';
    final awayScore = widget.match.awayScore ?? '0';

    String timeText = "";
    if (widget.match.status == model.MatchStatus.live) {
      timeText = "Dakika ${widget.match.liveMinute}.";
    } else if (widget.match.status == model.MatchStatus.finished) {
      timeText = "Maç sona erdi.";
    } else {
      timeText = "Maç henüz başlamadı.";
    }

    final text = "Skor tablosu: $home $homeScore, $away $awayScore. $timeText";
    TtsService().speak(text);
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final replyTo = _replyingToMessage;

    setState(() {
      _messagesInLastWindow += 1;
      _msgController.clear();
      _replyingToMessage = null;
    });

    try {
      await _chatService.sendMessage(
        widget.match.id,
        text,
        replyToId: replyTo?.id,
        replyToUsername: replyTo?.username,
        replyToText: replyTo?.text,
      );

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

  void _showFloatingReaction(String emoji) {
    debugPrint('--- _showFloatingReaction triggered for emoji: $emoji');
    if (!mounted) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString() +
        _random.nextInt(1000).toString();
    final startX =
        24.0 + _random.nextDouble() * (MediaQuery.of(context).size.width - 48);
    // tighter drift for more controlled upward flow
    final drift = (_random.nextDouble() - 0.5) * 40;

    // quicker, crisper animations
    final controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));

    final reaction =
        FloatingReaction(id: id, emoji: emoji, startX: startX, drift: drift);

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

  void _sendReaction(String emoji) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';

    setState(() {
      _messagesInLastWindow += 1;
    });

    // Broadcast immediately
    try {
      _gameChannel?.sendBroadcastMessage(
        event: 'reaction',
        payload: {
          'emoji': emoji,
          'username': userId,
          'sessionId': _sessionId,
        },
      );
    } catch (e) {
      debugPrint("Failed to broadcast reaction: \$e");
    }

    // Show locally
    _showFloatingReaction(emoji);
  }

  void _scrollToBottom() {
    // With reverse: true in the chat ListView, it automatically anchors to the bottom (offset 0)
    // We no longer want to force the outer NestedScrollView to jump.
  }

  Widget _buildDynamicTab(int index, IconData icon, String text) {
    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, child) {
        final double selectedness =
            (1.0 - (_tabController.animation!.value - index).abs())
                .clamp(0.0, 1.0);

        final color = Color.lerp(
          context.colors.textMedium,
          context.colors.primary,
          selectedness,
        );

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: selectedness,
                  child: Opacity(
                    opacity: selectedness,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: Text(text,
                          maxLines: 1,
                          style: TextStyle(
                              color: color,
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final safeTop = topPadding == 0 ? 44.0 : topPadding;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          // Background Gradient Pulsing based on Hype
          if (_hypeLevel > 0)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 800),
                // Smoothly fade out the glow when switching to other tabs
                opacity: (_tabController.index == 4) ? (_hypeLevel * 0.4) : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFE11D48).withValues(alpha: _hypeLevel),
                        context.colors.background,
                      ],
                      center: Alignment.center,
                      radius: 1.2,
                    ),
                  ),
                ),
              ),
            ),

          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _detailShellMaxWidth),
              child: Column(
                children: [
                  // 1) Match Pulse Header (Static 190px + SafeTop)
                  SizedBox(
                    height: safeTop + 190.0,
                    child: MatchDetailHeaderDelegate(
                      match: widget.match,
                      pulseController: _pulseController,
                      bgPulseController: _bgPulseController,
                      topPadding: safeTop,
                    ).build(context, 0.0, false),
                  ),

                  Material(
                    color: context.colors.background,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: context.colors.primaryContainer
                              .withValues(alpha: 0.2),
                        ),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        tabs: [
                          _buildDynamicTab(
                              0, Icons.dashboard_rounded, "OVERVIEW"),
                          _buildDynamicTab(1, Icons.groups_rounded, "LINEUP"),
                          _buildDynamicTab(2, Icons.bar_chart_rounded, "STATS"),
                          _buildDynamicTab(
                              3, Icons.headset_mic_rounded, "ROOMS"),
                          _buildDynamicTab(4, Icons.forum_rounded, "LIVE CHAT"),
                        ],
                      ),
                    ),
                  ),

                  // 3) Tab Content (Expanded fills the rest of the screen)
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(),
                        _buildLineupTab(),
                        _buildStatsTab(),
                        MatchVoiceRoomsTab(match: widget.match),
                        _buildChatTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_tabController.index == 4)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _detailShellMaxWidth),
                  child: _buildBottomInputArea(),
                ),
              ),
            ),

          if (_activeMiniGameId != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: (_tabController.index == 4) ? 90 : 32,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: _detailShellMaxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildMiniGameBanner(),
                  ),
                ),
              ),
            ),

          if (_activeReactions.isNotEmpty)
            Positioned.fill(
              child: _buildFloatingReactions(),
            ),

          if (_hypeLevel > 0)
            Positioned(
              top: safeTop +
                  140, // Puts it perfectly right below/on the bottom edge of the team box
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _detailShellMaxWidth),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _buildHypeBadge(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniGameBanner() {
    debugPrint(
        '--- _buildMiniGameBanner executing with gameId: $_activeMiniGameId');
    return GestureDetector(
      onTap: () async {
        final currentMiniGameId = _activeMiniGameId;
        if (currentMiniGameId == null) return;

        final result = await Navigator.push(
            context,
            MaterialPageRoute(
                settings: const RouteSettings(name: 'MiniGameScreen'),
                builder: (_) => MiniGameScreen(
                    roomId: widget.match.id,
                    gameId: currentMiniGameId,
                    gameType: _activeMiniGameType)));

        if (result != null && result is Map && result['type'] == 'GAME_OVER') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "Etkinlikten çıkıldı. En Yüksek Skorun: ${result['score']} 🏆"),
              backgroundColor: context.colors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ));
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.colors.heroGradientStart,
              context.colors.heroGradientEnd,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: context.colors.heroGlow.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.surface.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.videogame_asset,
                color: context.colors.surface,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Canlı Etkinlik Başladı!",
                      style: TextStyle(
                          color: context.colors.surface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  Text("Hemen katıl ve K-Coin kazan",
                      style: TextStyle(
                        color: context.colors.surface.withValues(alpha: 0.78),
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: context.colors.surface.withValues(alpha: 0.64),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sürüş modu kontrolü.
        Container(
          color: context.colors.background,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: GestureDetector(
            onTap: _toggleDrivingMode,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: _isDrivingModeActive
                      ? [
                          context.colors.liveAccent,
                          context.colors.heroGradientStart
                        ]
                      : [
                          context.colors.navBackgroundOverlay,
                          context.colors.navBackground
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: _isDrivingModeActive
                    ? [
                        BoxShadow(
                            color: context.colors.liveAccent
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 5))
                      ]
                    : [
                        BoxShadow(
                            color: context.colors.cardShadow
                                .withValues(alpha: 0.14),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.colors.surface.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isDrivingModeActive
                          ? Icons.directions_car
                          : Icons.directions_car_outlined,
                      color: context.colors.surface,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isDrivingModeActive ? "Sürüş modu aktif" : "Sürüş modu",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.surface,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.colors.surface.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isDrivingModeActive ? "Aktif" : "Aç",
                          style: TextStyle(
                            color: context.colors.surface,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          _isDrivingModeActive
                              ? Icons.graphic_eq
                              : Icons.play_arrow_rounded,
                          color: context.colors.surface,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // SCROLLABLE TIMELINE
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshTimeline,
            child: FutureBuilder<MatchTimelineReport>(
              future: _timelineFuture,
              initialData: _timelineReport,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _TimelineEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Olay akisi yuklenemedi',
                    message: 'Tekrar denemek icin asagi cek.',
                  );
                }
                final report = snapshot.data;
                if (report == null || report.events.isEmpty) {
                  return const _TimelineEmptyState(
                    icon: Icons.sports_soccer_rounded,
                    title: 'Olay bekleniyor',
                    message:
                        'Mac icindeki gol, kart ve degisiklikler burada gorunecek.',
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    _TimelineRail(
                      events: report.events,
                      homeTeam: widget.match.homeTeam,
                      awayTeam: widget.match.awayTeam,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab() {
    return MatchStatsView(match: widget.match);
  }

  Widget _buildLineupTab() {
    final future = _lineupFuture ??=
        ref.read(aiSportAgentLineupProvider).fetchLineups(widget.match.id);
    return RefreshIndicator(
      onRefresh: () async {
        final nextFuture =
            ref.read(aiSportAgentLineupProvider).fetchLineups(widget.match.id);
        setState(() => _lineupFuture = nextFuture);
        await nextFuture;
      },
      child: FutureBuilder<MatchLineupReport>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: const [
                _LineupEmptyState(
                  icon: Icons.error_outline,
                  title: 'Kadro verisi yuklenemedi',
                  message: 'Tekrar denemek icin asagi cek.',
                ),
              ],
            );
          }
          final report = snapshot.data;
          if (report == null || !report.hasLineups) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: const [
                _LineupEmptyState(
                  icon: Icons.groups_outlined,
                  title: 'Kadrolar henuz yok',
                  message:
                      'Bu mac icin ilk 11 ve yedek bilgisi aciklandiginda burada gorunecek.',
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _LineupPitchExperience(
                    report: report,
                    homeTitle: widget.match.homeTeam,
                    awayTitle: widget.match.awayTeam,
                    homeLogo: widget.match.homeLogo,
                    awayLogo: widget.match.awayLogo,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatTab() {
    final bool isLive = widget.match.status.name == 'live';

    return Stack(
      children: [
        ListView.builder(
          controller: _chatScrollController,
          reverse: true,
          padding: EdgeInsets.only(bottom: 140, top: isLive ? 80 : 16),
          itemCount: _groupedMessages.length,
          itemBuilder: (context, index) {
            final actualIdx = _groupedMessages.length - 1 - index;
            final msg = _groupedMessages[actualIdx];
            final isNextSameUser = (actualIdx + 1 < _groupedMessages.length) &&
                _groupedMessages[actualIdx + 1].type == msg.type &&
                _groupedMessages[actualIdx + 1].username == msg.username;
            final isPrevSameUser = (actualIdx > 0) &&
                _groupedMessages[actualIdx - 1].type == msg.type &&
                _groupedMessages[actualIdx - 1].username == msg.username;

            if (msg.type == MessageType.systemEvent) {
              return _buildSystemEvent(msg);
            }
            return _buildMessage(msg, isNextSameUser, isPrevSameUser);
          },
        ),
        Positioned.fill(child: _buildFloatingReactions()),
      ],
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
            color: isGoal
                ? context.colors.primaryContainer.withValues(alpha: 0.12)
                : context.colors.surfaceContainerLow.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isGoal
                    ? context.colors.primaryContainer.withValues(alpha: 0.4)
                    : context.colors.surfaceContainerHighest
                        .withValues(alpha: 0.5)),
            boxShadow: isGoal
                ? [
                    BoxShadow(
                        color: context.colors.primaryContainer
                            .withValues(alpha: 0.05),
                        blurRadius: 10)
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.systemEventIcon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isGoal
                        ? context.colors.primaryContainer.withValues(alpha: 0.4)
                        : context.colors.surfaceContainerHigh
                            .withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    msg.systemEventIcon,
                    size: 14,
                    color: isGoal
                        ? context.colors.onPrimaryContainer
                        : context.colors.textMedium,
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
                      color: isGoal
                          ? context.colors.onPrimaryContainer
                          : context.colors.textMedium,
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

  Widget _buildMessage(
      ChatMessage msg, bool isNextSameUser, bool isPrevSameUser) {
    final isMe = msg.type == MessageType.me;
    final paddingTop = isPrevSameUser ? 4.0 : 16.0;
    final paddingBottom = isNextSameUser ? 4.0 : 16.0;
    final bool isThreadExpanded = _expandedMessageIds.contains(msg.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Dismissible(
          key: ValueKey('msg_${msg.id}'),
          direction: DismissDirection.startToEnd,
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            color: Colors.transparent,
            child: Row(children: [
              Icon(Icons.reply, color: context.colors.primary, size: 20),
              const SizedBox(width: 8),
              Text("Yanıtla",
                  style: TextStyle(
                      color: context.colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          confirmDismiss: (direction) async {
            setState(() {
              _replyingToMessage = msg;
              _focusNode.requestFocus();
            });
            return false;
          },
          child: Padding(
            padding: EdgeInsets.only(
                top: paddingTop,
                bottom: msg.replies != null && msg.replies!.isNotEmpty
                    ? 4.0
                    : paddingBottom,
                left: 16,
                right: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (!isPrevSameUser)
                  GestureDetector(
                    onTap: () async {
                      if (msg.userId == null || isMe) return;
                      try {
                        final roomId = await _chatService
                            .getOrCreatePrivateRoom(msg.userId!);
                        if (!mounted) return;
                        await showPrivateChatOverlay(
                          context,
                          roomId: roomId,
                          otherUserId: msg.userId!,
                          otherUsername: msg.username ?? 'Kullanici',
                          otherAvatarUrl: msg.avatarUrl,
                          otherActiveFrame: msg.activeFrame,
                          isBot: msg.isBot,
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Sohbet başlatılamadı.')),
                          );
                        }
                      }
                    },
                    child: FrameAvatar(
                      avatarUrl: msg.avatarUrl ??
                          (isMe &&
                                  Supabase.instance.client.auth.currentUser
                                          ?.userMetadata !=
                                      null
                              ? Supabase.instance.client.auth.currentUser!
                                  .userMetadata!['avatar_url']
                              : null),
                      activeFrame: msg.activeFrame,
                      radius: 18,
                    ),
                  )
                else
                  const SizedBox(width: 36),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isPrevSameUser) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isMe ? "Sen" : (msg.username ?? ""),
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isMe
                                      ? context.colors.primary
                                      : context.colors.textHigh),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              msg.time ?? "",
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: context.colors.textMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? context.colors.primaryContainer
                                      .withValues(alpha: 0.15)
                                  : context.colors.surfaceContainerLow
                                      .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.only(
                                topLeft:
                                    Radius.circular(isPrevSameUser ? 4 : 20),
                                topRight: const Radius.circular(20),
                                bottomLeft:
                                    Radius.circular(isNextSameUser ? 4 : 20),
                                bottomRight: const Radius.circular(20),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text ?? "",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    height: 1.4,
                                    color: context.colors.textHigh,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (msg.replies != null && msg.replies!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
                top: 8, bottom: paddingBottom, left: 64, right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(isThreadExpanded ? msg.replies! : msg.replies!.take(2))
                    .map((r) => _buildReplyBubble(r)),
                if (!isThreadExpanded && msg.replies!.length > 2)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _expandedMessageIds.add(msg.id);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                          "${msg.replies!.length - 2} yanıtın tümünü gör",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.colors.primary)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildReplyBubble(ChatMessage reply) {
    final isMe = reply.type == MessageType.me;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrameAvatar(
              avatarUrl: reply.avatarUrl ??
                  (isMe &&
                          Supabase.instance.client.auth.currentUser
                                  ?.userMetadata !=
                              null
                      ? Supabase.instance.client.auth.currentUser!
                          .userMetadata!['avatar_url']
                      : null),
              activeFrame: reply.activeFrame,
              radius: 10),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isMe
                    ? context.colors.primaryContainer.withValues(alpha: 0.15)
                    : context.colors.surfaceContainerLow.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(isMe ? "Sen" : (reply.username ?? ""),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isMe
                                ? context.colors.primary
                                : context.colors.textHigh)),
                    const SizedBox(width: 6),
                    Text(reply.time ?? "",
                        style: TextStyle(
                            fontSize: 9, color: context.colors.textMedium)),
                  ]),
                  const SizedBox(height: 2),
                  Text(reply.text ?? "",
                      style: TextStyle(
                          fontSize: 12, color: context.colors.textHigh)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInputArea() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding:
              const EdgeInsets.only(top: 12, bottom: 20, left: 16, right: 16),
          decoration: BoxDecoration(
            color: context.colors.background.withValues(alpha: 0.85),
            border: Border(
                top: BorderSide(
                    color: context.colors.surfaceContainerHighest, width: 0.5)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, -4))
            ],
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

              // Reply Preview Banner
              if (_replyingToMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: context.colors.primaryContainer
                            .withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.reply,
                          size: 18, color: context.colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                "Yanıtlanıyor: ${_replyingToMessage!.username}",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.primary)),
                            const SizedBox(height: 2),
                            Text(_replyingToMessage!.text ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.textMedium)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: 16, color: context.colors.textMedium),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            setState(() => _replyingToMessage = null),
                      ),
                    ],
                  ),
                ),

              // Input Field
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isInputFocused
                            ? context.colors.background
                            : context.colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isInputFocused
                              ? context.colors.primaryContainer
                              : context.colors.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                          width: _isInputFocused ? 2 : 1,
                        ),
                        boxShadow: _isInputFocused
                            ? [
                                BoxShadow(
                                    color: context.colors.primaryContainer
                                        .withValues(alpha: 0.1),
                                    blurRadius: 8)
                              ]
                            : [],
                      ),
                      child: TextField(
                        controller: _msgController,
                        focusNode: _focusNode,
                        onSubmitted: (_) => _sendMessage(),
                        style:
                            const TextStyle(fontFamily: 'Inter', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Add to the moment...",
                          hintStyle: TextStyle(
                              color: context.colors.textMedium
                                  .withValues(alpha: 0.6),
                              fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
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
                      color: _hasText
                          ? context.colors.primaryContainer
                          : context.colors.surfaceContainer,
                      shape: BoxShape.circle,
                      boxShadow: _hasText
                          ? [
                              BoxShadow(
                                  color: context.colors.primaryContainer
                                      .withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ]
                          : [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _hasText ? _sendMessage : null,
                        borderRadius: BorderRadius.circular(24),
                        child: Center(
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            color: _hasText
                                ? context.colors.onPrimaryContainer
                                : context.colors.textMedium,
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
              final val =
                  Curves.easeOutCubic.transform(anim.value); // smoother ease
              final bottomOffset =
                  150 + (val * 450); // rises higher and smoother
              final leftOffset = reaction.startX +
                  (reaction.drift * Curves.easeInOutSine.transform(anim.value));

              double opacity = 1.0;
              double scale = 1.0;
              if (anim.value < 0.1) {
                opacity = anim.value / 0.1;
                scale = 0.4 + (0.6 * opacity);
              } else if (anim.value > 0.6) {
                opacity = 1.0 - ((anim.value - 0.6) / 0.4);
                scale = 1.0 +
                    ((anim.value - 0.6) * 0.5); // slight grow before fade tail
              }

              return Transform.translate(
                offset: Offset(leftOffset, -bottomOffset),
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: Text(reaction.emoji,
                        style: const TextStyle(fontSize: 36, shadows: [
                          Shadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ])),
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

// ignore: unused_element
class _LineupStatusCard extends StatelessWidget {
  final MatchLineupReport report;

  const _LineupStatusCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final statusText = switch (report.status) {
      'complete' => 'Kadrolar tamam',
      'partial' => 'Kadro kismen hazir',
      'failed' => 'Kadro alinamadi',
      'unavailable' => 'Kadro yok',
      _ => 'Kadro bekleniyor',
    };
    final confirmedText = report.confirmed ? 'Resmi' : 'Tahmini / bekleyen';
    final updatedText = report.syncedAt == null
        ? null
        : '${report.syncedAt!.toLocal().hour.toString().padLeft(2, '0')}:${report.syncedAt!.toLocal().minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_rounded,
              color: context.colors.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  updatedText == null
                      ? confirmedText
                      : '$confirmedText · Guncelleme $updatedText',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactLineupStatusPill extends StatelessWidget {
  final MatchLineupReport report;

  const _CompactLineupStatusPill({required this.report});

  @override
  Widget build(BuildContext context) {
    final statusText = switch (report.status) {
      'complete' => 'Kadrolar tamam',
      'partial' => 'Kadro kismen hazir',
      'failed' => 'Kadro alinamadi',
      'unavailable' => 'Kadro yok',
      _ => 'Kadro bekleniyor',
    };
    final confirmedText = report.confirmed ? 'Resmi' : 'Bekleyen';
    final updatedText = report.syncedAt == null
        ? null
        : '${report.syncedAt!.toLocal().hour.toString().padLeft(2, '0')}:${report.syncedAt!.toLocal().minute.toString().padLeft(2, '0')}';
    final metaText =
        updatedText == null ? confirmedText : '$confirmedText · $updatedText';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_rounded,
              color: context.colors.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: context.colors.textHigh,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            metaText,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineupPitchExperience extends StatelessWidget {
  final MatchLineupReport report;
  final String homeTitle;
  final String awayTitle;
  final String homeLogo;
  final String awayLogo;

  const _LineupPitchExperience({
    required this.report,
    required this.homeTitle,
    required this.awayTitle,
    required this.homeLogo,
    required this.awayLogo,
  });

  @override
  Widget build(BuildContext context) {
    final homeSubs =
        report.substitutions.where((item) => item.isHome == true).toList();
    final awaySubs =
        report.substitutions.where((item) => item.isHome == false).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompactLineupStatusPill(report: report),
        const SizedBox(height: 10),
        _DualLineupInsightStrip(
          report: report,
          homeTitle: homeTitle,
          awayTitle: awayTitle,
          homeSubstitutions: homeSubs,
          awaySubstitutions: awaySubs,
        ),
        const SizedBox(height: 10),
        _DualLineupPitchCard(
          report: report,
          homeTitle: homeTitle,
          awayTitle: awayTitle,
          homeLogo: homeLogo,
          awayLogo: awayLogo,
          homeSubstitutions: homeSubs,
          awaySubstitutions: awaySubs,
        ),
        if (report.substitutions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _LineupChangePanel(substitutions: report.substitutions),
        ],
        const SizedBox(height: 10),
        _DualBenchPanel(
          homeTitle: homeTitle,
          awayTitle: awayTitle,
          homePlayers: report.home.bench,
          awayPlayers: report.away.bench,
          homeSubstitutions: homeSubs,
          awaySubstitutions: awaySubs,
        ),
      ],
    );
  }
}

class _DualLineupInsightStrip extends StatelessWidget {
  final MatchLineupReport report;
  final String homeTitle;
  final String awayTitle;
  final List<LineupSubstitution> homeSubstitutions;
  final List<LineupSubstitution> awaySubstitutions;

  const _DualLineupInsightStrip({
    required this.report,
    required this.homeTitle,
    required this.awayTitle,
    required this.homeSubstitutions,
    required this.awaySubstitutions,
  });

  @override
  Widget build(BuildContext context) {
    final homeShape =
        report.home.formation ?? _inferShapeLabel(report.home.starters);
    final awayShape =
        report.away.formation ?? _inferShapeLabel(report.away.starters);
    final homeProfile = _formationProfile(homeShape);
    final awayProfile = _formationProfile(awayShape);
    final llmAnalysis = report.formationAnalysis;
    final comparison = _formationComparison(
      homeTitle: homeTitle,
      awayTitle: awayTitle,
      home: homeProfile,
      away: awayProfile,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            report.confirmed
                ? Icons.verified_rounded
                : Icons.manage_search_rounded,
            color: report.confirmed
                ? context.colors.success
                : context.colors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dizilis ozeti',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 6),
                _LineupFormationBlock(
                  label: '$homeTitle $homeShape',
                  purpose: llmAnalysis?.home.purpose ?? homeProfile.purpose,
                  plan: llmAnalysis?.home.plan ?? homeProfile.plan,
                  risk: llmAnalysis?.home.risk ?? homeProfile.risk,
                ),
                const SizedBox(height: 8),
                _LineupFormationBlock(
                  label: '$awayTitle $awayShape',
                  purpose: llmAnalysis?.away.purpose ?? awayProfile.purpose,
                  plan: llmAnalysis?.away.plan ?? awayProfile.plan,
                  risk: llmAnalysis?.away.risk ?? awayProfile.risk,
                ),
                const SizedBox(height: 9),
                _LineupComparisonBlock(
                  text: llmAnalysis?.comparison ?? comparison,
                ),
                if (report.tacticalBalance != null) ...[
                  const SizedBox(height: 8),
                  _TacticalBalanceBlock(
                    balance: report.tacticalBalance!,
                    homeTitle: homeTitle,
                    awayTitle: awayTitle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalBalanceBlock extends StatelessWidget {
  final TacticalBalance balance;
  final String homeTitle;
  final String awayTitle;

  const _TacticalBalanceBlock({
    required this.balance,
    required this.homeTitle,
    required this.awayTitle,
  });

  @override
  Widget build(BuildContext context) {
    final confidence = (balance.confidence * 100).round().clamp(0, 100);
    final explanation = balance.explanation ??
        '${balance.sampleSize} benzer eslesme | guven $confidence%';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Taktik denge',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TacticalBalanceSideChip(
                  title: homeTitle,
                  side: balance.home,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TacticalBalanceSideChip(
                  title: awayTitle,
                  side: balance.away,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: context.colors.textLow,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalBalanceSideChip extends StatelessWidget {
  final String title;
  final TacticalBalanceSide side;

  const _TacticalBalanceSideChip({
    required this.title,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    final color = _tacticalBalanceColor(context, side.score);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _signedTacticalScore(side.score),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            side.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineupFormationBlock extends StatelessWidget {
  final String label;
  final String purpose;
  final String plan;
  final String risk;

  const _LineupFormationBlock({
    required this.label,
    required this.purpose,
    required this.plan,
    required this.risk,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        const SizedBox(height: 3),
        _InsightMiniLine(title: 'Amac', text: purpose),
        _InsightMiniLine(title: 'Plan', text: plan),
        _InsightMiniLine(title: 'Risk', text: risk),
      ],
    );
  }
}

class _LineupComparisonBlock extends StatelessWidget {
  final String text;

  const _LineupComparisonBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _InsightMiniLine(
        title: 'Karsilastirma',
        text: text,
      ),
    );
  }
}

class _InsightMiniLine extends StatelessWidget {
  final String title;
  final String text;

  const _InsightMiniLine({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$title: ',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: context.colors.textHigh,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(
          fontSize: 11,
          height: 1.32,
          fontWeight: FontWeight.w700,
          color: context.colors.textMedium,
        ),
      ),
    );
  }
}

String _signedTacticalScore(double score) {
  if (score > 0) return '+${score.toStringAsFixed(2)}';
  if (score == 0) return '0.00';
  return score.toStringAsFixed(2);
}

Color _tacticalBalanceColor(BuildContext context, double score) {
  if (score >= 0.15) return context.colors.success;
  if (score <= -0.15) return context.colors.error;
  return context.colors.primary;
}

class _DualLineupPitchCard extends StatelessWidget {
  final MatchLineupReport report;
  final String homeTitle;
  final String awayTitle;
  final String homeLogo;
  final String awayLogo;
  final List<LineupSubstitution> homeSubstitutions;
  final List<LineupSubstitution> awaySubstitutions;

  const _DualLineupPitchCard({
    required this.report,
    required this.homeTitle,
    required this.awayTitle,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeSubstitutions,
    required this.awaySubstitutions,
  });

  @override
  Widget build(BuildContext context) {
    final homeRows = _buildPitchRows(report.home, isHome: true);
    final awayRows = _buildPitchRows(report.away, isHome: false);
    const markerWidth = 58.0;
    const markerHeight = 40.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PitchTeamHeader(
                  label: homeTitle,
                  logoUrl: homeLogo,
                  formation: report.home.formation ??
                      _inferShapeLabel(report.home.starters),
                  alignEnd: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PitchTeamHeader(
                  label: awayTitle,
                  logoUrl: awayLogo,
                  formation: report.away.formation ??
                      _inferShapeLabel(report.away.starters),
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 0.63,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          for (final item in awayRows)
                            Positioned(
                              left: max(
                                6,
                                min(
                                  constraints.maxWidth - markerWidth - 6,
                                  constraints.maxWidth * item.dx -
                                      markerWidth / 2,
                                ),
                              ),
                              top: max(
                                8,
                                min(
                                  constraints.maxHeight - markerHeight - 8,
                                  constraints.maxHeight * item.dy -
                                      markerHeight / 2,
                                ),
                              ),
                              width: markerWidth,
                              height: markerHeight,
                              child: _PitchPlayerMarker(
                                player: item.player,
                                substitution: _findSubstitutionByOutPlayer(
                                  item.player,
                                  awaySubstitutions,
                                ),
                                isHome: false,
                              ),
                            ),
                          for (final item in homeRows)
                            Positioned(
                              left: max(
                                6,
                                min(
                                  constraints.maxWidth - markerWidth - 6,
                                  constraints.maxWidth * item.dx -
                                      markerWidth / 2,
                                ),
                              ),
                              top: max(
                                8,
                                min(
                                  constraints.maxHeight - markerHeight - 8,
                                  constraints.maxHeight * item.dy -
                                      markerHeight / 2,
                                ),
                              ),
                              width: markerWidth,
                              height: markerHeight,
                              child: _PitchPlayerMarker(
                                player: item.player,
                                substitution: _findSubstitutionByOutPlayer(
                                  item.player,
                                  homeSubstitutions,
                                ),
                                isHome: true,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PitchTeamHeader extends StatelessWidget {
  final String label;
  final String logoUrl;
  final String formation;
  final bool alignEnd;

  const _PitchTeamHeader({
    required this.label,
    required this.logoUrl,
    required this.formation,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final logo = ClipOval(
      child: Image.network(
        logoUrl,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 34),
      ),
    );
    final text = Expanded(
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
    return Row(
      children: alignEnd
          ? [text, const SizedBox(width: 8), logo]
          : [logo, const SizedBox(width: 8), text],
    );
  }
}

class _PitchPlayerMarker extends StatelessWidget {
  final LineupPlayer player;
  final LineupSubstitution? substitution;
  final bool isHome;

  const _PitchPlayerMarker({
    required this.player,
    required this.substitution,
    required this.isHome,
  });

  @override
  Widget build(BuildContext context) {
    final hasChange = substitution != null;
    final goals = player.statistics['goals'];
    final name = player.shortName ?? player.name;
    final accent = isHome ? context.colors.primary : context.colors.textHigh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasChange
              ? context.colors.error.withValues(alpha: 0.55)
              : accent.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasChange
                      ? context.colors.error.withValues(alpha: 0.12)
                      : accent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  player.shirtNumber ?? '-',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: hasChange ? context.colors.error : accent,
                  ),
                ),
              ),
              if (player.isCaptain) ...[
                const SizedBox(width: 3),
                Text(
                  'C',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: context.colors.primary,
                  ),
                ),
              ],
              if (goals is num && goals > 0) ...[
                const SizedBox(width: 3),
                Icon(Icons.sports_soccer,
                    size: 10, color: context.colors.success),
              ],
              if (hasChange) ...[
                const SizedBox(width: 3),
                Icon(Icons.arrow_upward_rounded,
                    size: 11, color: context.colors.error),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
        ],
      ),
    );
  }
}

class _DualBenchPanel extends StatelessWidget {
  final String homeTitle;
  final String awayTitle;
  final List<LineupPlayer> homePlayers;
  final List<LineupPlayer> awayPlayers;
  final List<LineupSubstitution> homeSubstitutions;
  final List<LineupSubstitution> awaySubstitutions;

  const _DualBenchPanel({
    required this.homeTitle,
    required this.awayTitle,
    required this.homePlayers,
    required this.awayPlayers,
    required this.homeSubstitutions,
    required this.awaySubstitutions,
  });

  @override
  Widget build(BuildContext context) {
    final homeVisible = homePlayers
        .where((player) =>
            _findSubstitutionByInPlayer(player, homeSubstitutions) == null)
        .toList();
    final awayVisible = awayPlayers
        .where((player) =>
            _findSubstitutionByInPlayer(player, awaySubstitutions) == null)
        .toList();
    if (homeVisible.isEmpty && awayVisible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        children: [
          _BenchTeamRow(title: homeTitle, players: homeVisible),
          if (homeVisible.isNotEmpty && awayVisible.isNotEmpty)
            const SizedBox(height: 12),
          _BenchTeamRow(title: awayTitle, players: awayVisible),
        ],
      ),
    );
  }
}

class _BenchTeamRow extends StatelessWidget {
  final String title;
  final List<LineupPlayer> players;

  const _BenchTeamRow({
    required this.title,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title yedekler',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: players.map((player) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${player.shirtNumber ?? '-'} ${player.shortName ?? player.name}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textMedium,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _LineupChangePanel extends StatelessWidget {
  final List<LineupSubstitution> substitutions;

  const _LineupChangePanel({required this.substitutions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Degisimler',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 10),
          ...substitutions.map((item) => _CompactSubstitutionRow(item: item)),
        ],
      ),
    );
  }
}

class _CompactSubstitutionRow extends StatelessWidget {
  final LineupSubstitution item;

  const _CompactSubstitutionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final minute = item.minuteLabel.isEmpty ? 'SUB' : item.minuteLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              minute,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: context.colors.textMedium,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.playerOutName ?? 'Cikan oyuncu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: context.colors.error,
              ),
            ),
          ),
          Icon(Icons.swap_horiz_rounded,
              size: 18, color: context.colors.textMedium),
          Expanded(
            child: Text(
              item.playerInName ?? 'Giren oyuncu',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: context.colors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BenchPanel extends StatelessWidget {
  final List<LineupPlayer> players;
  final List<LineupSubstitution> substitutions;

  const _BenchPanel({
    required this.players,
    required this.substitutions,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePlayers = players
        .where((player) =>
            _findSubstitutionByInPlayer(player, substitutions) == null)
        .toList();
    if (visiblePlayers.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yedekler',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visiblePlayers.map((player) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${player.shirtNumber ?? '-'} ${player.shortName ?? player.name}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.colors.textMedium,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grass = Paint()..color = const Color(0xFF2F8E5C);
    canvas.drawRect(Offset.zero & size, grass);

    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.045);
    for (var i = 0; i < 7; i++) {
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(0, size.height / 7 * i, size.width, size.height / 7),
          stripe,
        );
      }
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final border = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(border, const Radius.circular(12)),
      line,
    );
    canvas.drawLine(
      Offset(10, size.height / 2),
      Offset(size.width - 10, size.height / 2),
      line,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, line);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 2, line);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, 10),
        width: size.width * 0.46,
        height: 54,
      ),
      line,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height - 10),
        width: size.width * 0.46,
        height: 54,
      ),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PitchPlayerPosition {
  final LineupPlayer player;
  final double dx;
  final double dy;

  const _PitchPlayerPosition({
    required this.player,
    required this.dx,
    required this.dy,
  });
}

List<_PitchPlayerPosition> _buildPitchRows(
  TeamLineup lineup, {
  required bool isHome,
}) {
  final starters = [...lineup.starters]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (starters.isEmpty) return const [];
  final formationRows = _parseFormation(lineup.formation);
  final rows = <List<LineupPlayer>>[];
  if (formationRows.fold<int>(0, (sum, item) => sum + item) ==
      starters.length - 1) {
    rows.add([starters.first]);
    var cursor = 1;
    for (final count in formationRows) {
      rows.add(starters.skip(cursor).take(count).toList());
      cursor += count;
    }
  } else {
    rows.addAll(_fallbackRows(starters));
  }

  final result = <_PitchPlayerPosition>[];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.isEmpty) continue;
    final progress =
        rows.length == 1 ? 0.5 : rowIndex / max(1, rows.length - 1);
    final dy = isHome ? 0.93 - (progress * 0.35) : 0.07 + (progress * 0.35);
    for (var playerIndex = 0; playerIndex < row.length; playerIndex++) {
      final dx = (playerIndex + 1) / (row.length + 1);
      result
          .add(_PitchPlayerPosition(player: row[playerIndex], dx: dx, dy: dy));
    }
  }
  return result;
}

List<int> _parseFormation(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(RegExp(r'[-\s]+'))
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .where((item) => item > 0)
      .toList();
}

List<List<LineupPlayer>> _fallbackRows(List<LineupPlayer> starters) {
  final gk =
      starters.where((p) => (p.position ?? '').toUpperCase() == 'G').toList();
  final defenders =
      starters.where((p) => (p.position ?? '').toUpperCase() == 'D').toList();
  final mids =
      starters.where((p) => (p.position ?? '').toUpperCase() == 'M').toList();
  final forwards =
      starters.where((p) => (p.position ?? '').toUpperCase() == 'F').toList();
  final used = {...gk, ...defenders, ...mids, ...forwards};
  final rest = starters.where((p) => !used.contains(p)).toList();
  return [
    if (gk.isNotEmpty) gk.take(1).toList() else starters.take(1).toList(),
    if (defenders.isNotEmpty) defenders else starters.skip(1).take(4).toList(),
    if (mids.isNotEmpty) mids else starters.skip(5).take(4).toList(),
    if (forwards.isNotEmpty)
      forwards
    else
      [...starters.skip(9), ...rest].take(2).toList(),
  ];
}

String _inferShapeLabel(List<LineupPlayer> starters) {
  if (starters.length >= 11) return 'Dizilis mevcut';
  if (starters.isNotEmpty) return '${starters.length} oyuncu';
  return 'Dizilis bekleniyor';
}

class _FormationProfile {
  final String purpose;
  final String plan;
  final String risk;
  final int width;
  final int midfield;
  final int attack;
  final int defense;
  final int forwards;

  const _FormationProfile({
    required this.purpose,
    required this.plan,
    required this.risk,
    required this.width,
    required this.midfield,
    required this.attack,
    required this.defense,
    required this.forwards,
  });
}

_FormationProfile _formationProfile(String formation) {
  final normalized = formation.trim().toLowerCase();
  final known = _knownFormationProfile(normalized);
  if (known != null) return known;

  final lines = _parseFormation(normalized);
  if (lines.isEmpty) {
    return const _FormationProfile(
      purpose:
          'dizilis verisi sinirli oldugu icin teknik niyet temkinli okunmali.',
      plan: 'saha uzerindeki oyuncu noktalarindan genel denge okunabilir.',
      risk: 'formasyon kaydi net olmadigi icin yorum temkinli okunmali.',
      width: 2,
      midfield: 2,
      attack: 2,
      defense: 2,
      forwards: 1,
    );
  }

  final defenders = lines.first;
  final forwards = lines.last;
  final midfielders = lines.length > 2
      ? lines.sublist(1, lines.length - 1).fold<int>(0, (a, b) => a + b)
      : lines.length > 1
          ? lines[1]
          : 0;
  return _profile(
    purpose:
        '$defenders savunmaci, $midfielders orta saha ve $forwards hucumcu ile dengelenir.',
    plan: midfielders >= 4
        ? 'orta sahada daha fazla oyuncu bulundurur ve alan kapatmayi kolaylastirir.'
        : 'hatlar arasi mesafe dogru kurulursa sade ve okunabilir bir denge verir.',
    risk: forwards >= 3
        ? 'onde fazla oyuncu kaldiginda orta saha destegi azalabilir.'
        : 'hucum destegi gec gelirse ondeki oyuncular yalniz kalabilir.',
    width: lines.length >= 4 || midfielders >= 4 ? 4 : 3,
    midfield: midfielders.clamp(1, 5),
    attack: forwards >= 3
        ? 5
        : forwards == 2
            ? 4
            : 3,
    defense: defenders >= 5
        ? 5
        : defenders == 4
            ? 4
            : 3,
    forwards: forwards,
  );
}

_FormationProfile? _knownFormationProfile(String value) {
  return switch (value) {
    '4-3-3' => _profile(
        purpose:
            'uclu orta saha ve iki kanat oyuncusuyla sahaya genis yayilir.',
        plan:
            'kanatlardan hucum kurmak ve topu rakip yari alanda tutmak kolaylasir.',
        risk: 'bekler one ciktiginda savunmanin kenarlarinda bosluk kalabilir.',
        width: 5,
        midfield: 3,
        attack: 5,
        defense: 3,
        forwards: 1,
      ),
    '4-2-3-1' => _profile(
        purpose:
            'savunma onunde iki oyuncu, forvet arkasinda uc destek oyuncusu vardir.',
        plan:
            'orta alan dengeli kalir ve top kaybindan sonra savunmaya donmek kolaylasir.',
        risk: 'tek forvet yeterince destek alamazsa hucumda yalniz kalabilir.',
        width: 4,
        midfield: 5,
        attack: 3,
        defense: 4,
        forwards: 1,
      ),
    '4-4-2' => _profile(
        purpose: 'iki forvet ve iki duz orta saha hatti kullanir.',
        plan:
            'ceza sahasina iki oyuncu sokar ve takim savunmada kolay sekil alir.',
        risk:
            'orta sahada uc oyunculu rakiplere karsi merkezde eksik kalabilir.',
        width: 4,
        midfield: 3,
        attack: 4,
        defense: 3,
        forwards: 2,
      ),
    '4-1-4-1' => _profile(
        purpose:
            'savunma onunde tek oyuncu, onun onunde dortlu orta saha vardir.',
        plan: 'orta alani kalabalik tutar ve savunma onunu korur.',
        risk: 'tek forvet desteksiz kalirsa hucum baslatmak zorlasabilir.',
        width: 4,
        midfield: 5,
        attack: 2,
        defense: 4,
        forwards: 1,
      ),
    '4-5-1' => _profile(
        purpose:
            'dort savunmaci, bes orta saha ve tek forvetle daha kontrollu durur.',
        plan: 'orta sahayi kalabalik tutar ve rakibin pas alanlarini daraltir.',
        risk: 'forvet yalniz kalabilir ve hucum destegi gec gelebilir.',
        width: 4,
        midfield: 5,
        attack: 2,
        defense: 5,
        forwards: 1,
      ),
    '4-2-4' => _profile(
        purpose: 'dort hucumcuya yakin bir on hat kullanir.',
        plan:
            'son bolgede cok oyuncu bulundurur ve baski kurmayi kolaylastirir.',
        risk: 'orta saha iki oyuncuya kaldigi icin merkezde bosluk verebilir.',
        width: 5,
        midfield: 2,
        attack: 5,
        defense: 2,
        forwards: 2,
      ),
    '4-1-2-1-2' => _profile(
        purpose: 'elmas orta saha ve iki forvet kullanir.',
        plan:
            'merkezi kalabalik tutar ve iki forvetle ceza sahasina erken iner.',
        risk: 'kanat genisligi beklerden gelmezse oyun daralabilir.',
        width: 2,
        midfield: 5,
        attack: 4,
        defense: 3,
        forwards: 2,
      ),
    '4-3-1-2' => _profile(
        purpose:
            'iki forvetin arkasinda bir destek oyuncusu ve uclu orta saha vardir.',
        plan: 'merkezden hucum kurar ve forvetleri birbirine yakin tutar.',
        risk:
            'kanatlarda dogal oyuncu az oldugu icin genislik sinirli kalabilir.',
        width: 2,
        midfield: 4,
        attack: 4,
        defense: 3,
        forwards: 2,
      ),
    '4-3-2-1' => _profile(
        purpose: 'tek forvetin arkasinda iki destek oyuncusu kullanir.',
        plan:
            'merkezden pas baglantisi kurar ve hucum oyuncularini birbirine yakin tutar.',
        risk: 'kanat genisligi az kalirsa rakip savunmayi acmak zorlasabilir.',
        width: 2,
        midfield: 4,
        attack: 3,
        defense: 3,
        forwards: 1,
      ),
    '4-2-2-2' => _profile(
        purpose:
            'iki savunma onu oyuncusu, iki destek oyuncusu ve iki forvet vardir.',
        plan:
            'merkezde guvenlik saglar ve iki forvetle hucum tehdidi olusturur.',
        risk: 'kanatlar bos kalabilir ve hucum genisligi sinirlanabilir.',
        width: 2,
        midfield: 4,
        attack: 4,
        defense: 4,
        forwards: 2,
      ),
    '3-5-2' => _profile(
        purpose: 'uc savunmaci, kalabalik orta saha ve iki forvet kullanir.',
        plan:
            'orta sahada sayi ustunlugu ve iki forvetle ceza sahasi varligi verir.',
        risk: 'kenar oyunculari geri donmezse kanatlarda bosluk olusabilir.',
        width: 4,
        midfield: 5,
        attack: 4,
        defense: 4,
        forwards: 2,
      ),
    '3-4-3' => _profile(
        purpose: 'uc savunmaci, dort orta saha ve uc hucumcu vardir.',
        plan: 'onde uc oyuncuyla baski ve kanat hucumu kurmaya uygundur.',
        risk: 'orta saha gecilirse uc savunmaci genis alanda yakalanabilir.',
        width: 5,
        midfield: 4,
        attack: 5,
        defense: 3,
        forwards: 1,
      ),
    '3-4-2-1' => _profile(
        purpose:
            'tek forvetin arkasinda iki destek oyuncusu ve uc savunmaci vardir.',
        plan: 'merkezde baglanti kurar ve hucum destegini forvete yakin tutar.',
        risk: 'kenar oyuncularinin hem hucum hem savunma yuku artar.',
        width: 4,
        midfield: 4,
        attack: 4,
        defense: 4,
        forwards: 1,
      ),
    '3-4-1-2' => _profile(
        purpose: 'iki forvetin arkasinda bir destek oyuncusu kullanir.',
        plan: 'merkezden hucum kurar ve iki forvetle savunmayi mesgul eder.',
        risk: 'kanat savunmasi kenar oyuncularinin temposuna bagli kalir.',
        width: 3,
        midfield: 4,
        attack: 4,
        defense: 4,
        forwards: 2,
      ),
    '3-1-4-2' => _profile(
        purpose:
            'savunma onunde tek oyuncu, onde dortlu orta saha ve iki forvet vardir.',
        plan: 'iki forvetle hucum ederken orta alanda kalabalik kalabilir.',
        risk: 'savunma onundeki tek oyuncu yalniz kalirsa merkez acilabilir.',
        width: 4,
        midfield: 5,
        attack: 4,
        defense: 3,
        forwards: 2,
      ),
    '5-4-1' => _profile(
        purpose: 'bes savunmaci, dort orta saha ve tek forvet kullanir.',
        plan:
            'savunma hattini kalabalik tutar ve alan kapatmayi kolaylastirir.',
        risk: 'hucumda tek forvet yalniz kalabilir ve cikislar gecikebilir.',
        width: 4,
        midfield: 4,
        attack: 1,
        defense: 5,
        forwards: 1,
      ),
    '5-3-2' => _profile(
        purpose: 'bes savunmaci ve iki forvet kullanir.',
        plan: 'savunma guveni yuksektir ve iki forvetle hizli cikis yapabilir.',
        risk: 'orta saha uclusu genis alani kapatmakta zorlanabilir.',
        width: 3,
        midfield: 3,
        attack: 3,
        defense: 5,
        forwards: 2,
      ),
    '5-2-3' => _profile(
        purpose: 'bes savunmaci ile baslar, onde uc hucumcu kullanir.',
        plan: 'savunma guveni ile hizli hucum tehdidini birlikte verir.',
        risk: 'orta saha iki oyuncuya kalirsa top rakipte daha cok kalabilir.',
        width: 5,
        midfield: 2,
        attack: 4,
        defense: 5,
        forwards: 1,
      ),
    _ => null,
  };
}

_FormationProfile _profile({
  required String purpose,
  required String plan,
  required String risk,
  required int width,
  required int midfield,
  required int attack,
  required int defense,
  required int forwards,
}) {
  return _FormationProfile(
    purpose: purpose,
    plan: plan,
    risk: risk,
    width: width,
    midfield: midfield,
    attack: attack,
    defense: defense,
    forwards: forwards,
  );
}

String _formationComparison({
  required String homeTitle,
  required String awayTitle,
  required _FormationProfile home,
  required _FormationProfile away,
}) {
  final parts = <String>[];
  if ((home.width - away.width).abs() >= 2) {
    parts.add(home.width > away.width
        ? '$homeTitle daha genis oynamaya uygun.'
        : '$awayTitle daha genis oynamaya uygun.');
  }
  if ((home.midfield - away.midfield).abs() >= 2) {
    parts.add(home.midfield > away.midfield
        ? '$homeTitle orta alani daha kalabalik tutabilir.'
        : '$awayTitle orta alani daha kalabalik tutabilir.');
  }
  if ((home.defense - away.defense).abs() >= 2) {
    parts.add(home.defense > away.defense
        ? '$homeTitle savunma guvenligini daha onde tutuyor.'
        : '$awayTitle savunma guvenligini daha onde tutuyor.');
  }
  if ((home.attack - away.attack).abs() >= 2) {
    parts.add(home.attack > away.attack
        ? '$homeTitle hucum hattinda daha fazla oyuncu kullanabilir.'
        : '$awayTitle hucum hattinda daha fazla oyuncu kullanabilir.');
  }
  if (home.forwards != away.forwards) {
    parts.add(home.forwards > away.forwards
        ? '$homeTitle onde daha fazla forvetle basliyor.'
        : '$awayTitle onde daha fazla forvetle basliyor.');
  }
  if (parts.isEmpty) {
    return 'Iki dizilis birbirine yakin denge veriyor. Fark daha cok oyuncu rolleri ve saha ici yerlesimden okunmali.';
  }
  return parts.take(3).join(' ');
}

// ignore: unused_element
String _formationMeaning(String formation) {
  final normalized = formation.trim().toLowerCase();
  return switch (normalized) {
    '4-2-4' =>
      'dort hucumcuya yakin bir yapi kurar. Atak gucu artar, orta saha daha bos kalabilir.',
    '4-3-3' =>
      'kanat oyuncularini ve uclu orta sahayi one cikarir. Takim sahaya genis yayilir.',
    '4-3-2-1' =>
      'iki destek oyuncusu forvetin arkasinda oynar. Merkezden hucum kurmaya uygundur.',
    '4-3-1-2' =>
      'iki forvet ve arkalarinda bir oyun kurucu kullanir. Kanatlardan cok merkeze dayanir.',
    '4-1-2-3' =>
      'savunma onunde bir oyuncu, onde uc hucumcu kullanir. Kanatlar aktif kalir.',
    '4-2-1-3' =>
      'iki oyuncu savunma onunu korur, onde uc hucumcu vardir. Denge ve hucum birlikte aranir.',
    '4-2-3-1' =>
      'savunma onunu iki oyuncuyla korur. Orta alan daha dengeli kalir.',
    '4-2-2-2' =>
      'iki forvet ve iki destek oyuncusu kullanir. Merkez kalabalik, kanat genisligi daha sinirli olabilir.',
    '4-1-3-2' =>
      'iki forveti destekleyen uclu orta saha kurar. Savunma onundeki tek oyuncuya yuk biner.',
    '4-3-2' =>
      'bir oyuncu eksik gorunen dizilis. Genelde savunma ve orta saha dengesi korunmaya calisilir.',
    '4-3-1' =>
      'birden fazla oyuncu eksik gorunen dizilis. Saha yerlesimi mevcut oyunculara gore okunmali.',
    '4-4-2' =>
      'iki forvetle oynar. Orta saha cizgisi daha duzenli ve basit kurulur.',
    '4-4-1-1' =>
      'tek forvetin arkasinda destek oyuncusu kullanir. 4-4-2 kadar dengeli, hucumda daha baglantili durur.',
    '4-1-4-1' =>
      'savunma onunde tek oyuncu kullanir. Orta saha kalabalik ve kontrolludur.',
    '4-1-3-1-1' =>
      'savunma onunde tek oyuncu ve onde iki destek katmani kullanir. Merkez rolleri parcali dagilir.',
    '4-5-1' => 'orta sahayi kalabalik tutar. Forvet daha yalniz kalabilir.',
    '4-1-2-1-2' =>
      'elmas orta saha kullanir. Merkez kalabaliktir, kanat genisligi beklerden gelebilir.',
    '4-3-1-1' =>
      'eksik oyunculu veya ozel rol dagilimli gorunur. Tek forvetin arkasinda destek vardir.',
    '4-2-3' =>
      'eksik oyunculu bir yapi gorunur. Savunma onu iki oyuncuyla korunur, hucum sayisi sinirlidir.',
    '4-4-1' =>
      'eksik oyunculu savunma agirlikli yapi. Tek forvetle daha kontrollu kalir.',
    '4-2-2-1' =>
      'eksik oyunculu dengeli yapi. Iki savunma on oyuncusu ve iki destek oyuncusu vardir.',
    '3-6-1' =>
      'uc savunmaci ve cok kalabalik orta saha kullanir. Topun orta alanda kalmasi hedeflenir.',
    '3-5-2' =>
      'uc savunmaci ve kalabalik orta saha kullanir. Kenar oyuncularinin rolu artar.',
    '3-5-1-1' =>
      'uc savunmaci ve kalabalik orta saha kurar. Tek forvetin arkasinda destek oyuncusu vardir.',
    '3-4-1-2' =>
      'iki forvetin arkasinda bir destek oyuncusu kullanir. Merkezden hucuma cikmaya uygundur.',
    '3-4-2-1' =>
      'tek forvetin arkasinda iki destek oyuncusu vardir. Hucum merkezde daha baglantili kurulur.',
    '3-4-3' =>
      'uc savunmaci ile baslar, on tarafta uc oyuncu kullanir. Daha atak bir yapi olabilir.',
    '3-3-4' =>
      'uc savunmaci ve dort hucumcuya yakin yapi kurar. Atak riskini artirir.',
    '3-3-3-1' =>
      'hatlar esit dagilir ve tek forvet kullanilir. Takim bloklar halinde yerlesir.',
    '3-1-4-2' =>
      'savunma onunde tek oyuncu ve iki forvet vardir. Merkez koruma ile hucum sayisi birlikte aranir.',
    '3-2-4-1' =>
      'iki oyuncu savunma onunu korur, onde kalabalik destek hattı vardir. Hucumda cok oyuncu kullanir.',
    '3-2-2-3' =>
      'iki merkez oyuncu ve onde uc hucumcu kullanir. Saha yerlesimi modern ve parcali gorunur.',
    '3-4-1-1' =>
      'eksik oyunculu uc savunmali yapi. Tek forvetin arkasinda destek oyuncusu vardir.',
    '3-4-2' =>
      'eksik oyunculu uc savunmali yapi. Orta saha genis, hucum sayisi sinirlidir.',
    '3-5-1' =>
      'eksik oyunculu kalabalik orta saha yapisi. Tek forvetle kontrollu kalir.',
    '3-3-3' => 'eksik oyunculu dengeli yapi. Uc hat birbirine yakin durur.',
    '5-2-3' =>
      'besli savunma ile baslar, onde uc hucumcu kullanir. Savunma guveni ve hizli hucum birlikte aranir.',
    '5-3-2' =>
      'savunma hattini kalabalik tutar. Iki forvetle hizli cikisa uygundur.',
    '5-2-1-2' =>
      'besli savunma, iki merkez ve iki forvet kullanir. Merkez destek oyuncusu hucumu baglar.',
    '5-2-2-1' =>
      'besli savunma ve tek forvet vardir. Iki destek oyuncusu hucuma baglanti saglar.',
    '5-3-1-1' =>
      'besli savunma, tek forvet ve arkasinda destek oyuncusu kullanir. Daha kontrollu bir yapidir.',
    '5-4-1' =>
      'savunma agirlikli bir yapi kurar. Forvet destegi sinirli kalabilir.',
    '5-1-3-1' =>
      'savunma onunde tek oyuncu ve kalabalik destek hattı vardir. Savunma guveni one cikar.',
    '5-2-2' =>
      'eksik oyunculu besli savunma yapisi. Savunma kalabalik, hucum sayisi sinirlidir.',
    '5-3-1' =>
      'eksik oyunculu kontrollu yapi. Besli savunma ve tek forvet gorunur.',
    '5-4' =>
      'eksik oyunculu savunma agirlikli yapi. Forvet hattı verisi eksik olabilir.',
    '2-3-5' =>
      'cok hucumcu gorunen eski tip yapi. Savunma sayisi az, hucum sayisi fazladir.',
    '2-5-3' =>
      'orta saha ve hucum kalabalik gorunur. Savunma sayisi az oldugu icin riskli olabilir.',
    '2-4-4' =>
      'dort hucumcuya yakin ve savunma sayisi az yapi. Hucum agirligi fazladir.',
    '1-4-4-1' =>
      'eksik veya ozel kayitli yapi. Orta saha kalabalik, savunma sayisi sinirli gorunur.',
    '1-3-4-2' =>
      'eksik veya ozel kayitli yapi. Orta saha ve hucum sayisi savunmadan fazladir.',
    _ when RegExp(r'^\d-\d-\d$').hasMatch(normalized) =>
      'uc hatli klasik bir dizilis. Oyuncu yerlesimi takim dengesini gosterir.',
    _ when RegExp(r'^\d-\d-\d-\d$').hasMatch(normalized) =>
      'dort hatli daha detayli bir dizilis. Orta alan rolleri daha belirgin ayrilir.',
    _ =>
      'dizilis verisi sinirli. Oyuncularin sahadaki yerlesimi ana referans olmali.',
  };
}

// ignore: unused_element
class _TeamLineupCard extends StatelessWidget {
  final String title;
  final String logoUrl;
  final TeamLineup lineup;
  final List<LineupSubstitution> substitutions;

  const _TeamLineupCard({
    required this.title,
    required this.logoUrl,
    required this.lineup,
    required this.substitutions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Image.network(
                  logoUrl,
                  width: 38,
                  height: 38,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.shield, size: 38),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: context.colors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lineup.formation == null
                          ? '${lineup.starters.length} ilk 11'
                          : '${lineup.formation} · ${lineup.starters.length} ilk 11',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (lineup.starters.isNotEmpty)
            _LineupSection(
              title: 'Ilk 11',
              players: lineup.starters,
              substitutions: substitutions,
              hidePlayersIn: false,
            ),
          if (lineup.bench.isNotEmpty) ...[
            const SizedBox(height: 14),
            _LineupSection(
              title: 'Yedekler',
              players: lineup.bench,
              substitutions: substitutions,
              hidePlayersIn: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _LineupSection extends StatelessWidget {
  final String title;
  final List<LineupPlayer> players;
  final List<LineupSubstitution> substitutions;
  final bool hidePlayersIn;

  const _LineupSection({
    required this.title,
    required this.players,
    required this.substitutions,
    required this.hidePlayersIn,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePlayers = hidePlayersIn
        ? players
            .where(
              (player) =>
                  _findSubstitutionByInPlayer(player, substitutions) == null,
            )
            .toList()
        : players;

    if (visiblePlayers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        ...visiblePlayers.map(
          (player) {
            final outSubstitution =
                _findSubstitutionByOutPlayer(player, substitutions);
            if (outSubstitution != null) {
              return _LineupSubstitutionTile(
                playerOut: player,
                substitution: outSubstitution,
              );
            }
            return _LineupPlayerTile(player: player);
          },
        ),
      ],
    );
  }
}

LineupSubstitution? _findSubstitutionByOutPlayer(
  LineupPlayer player,
  List<LineupSubstitution> substitutions,
) {
  for (final substitution in substitutions) {
    if (_lineupPlayerMatches(
        player, substitution.playerOutId, substitution.playerOutName)) {
      return substitution;
    }
  }
  return null;
}

LineupSubstitution? _findSubstitutionByInPlayer(
  LineupPlayer player,
  List<LineupSubstitution> substitutions,
) {
  for (final substitution in substitutions) {
    if (_lineupPlayerMatches(
        player, substitution.playerInId, substitution.playerInName)) {
      return substitution;
    }
  }
  return null;
}

bool _lineupPlayerMatches(LineupPlayer player, String? remoteId, String? name) {
  if (remoteId != null &&
      player.providerPlayerId != null &&
      player.providerPlayerId == remoteId) {
    return true;
  }
  final target = _normalizeLineupName(name);
  if (target.isEmpty) return false;
  return _normalizeLineupName(player.name) == target ||
      _normalizeLineupName(player.shortName) == target;
}

String _normalizeLineupName(String? value) {
  return (value ?? '').trim().toLowerCase();
}

class _LineupPlayerTile extends StatelessWidget {
  final LineupPlayer player;

  const _LineupPlayerTile({required this.player});

  @override
  Widget build(BuildContext context) {
    final goals = player.statistics['goals'];
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              player.shirtNumber ?? '-',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: context.colors.textHigh,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.shortName ?? player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.colors.textHigh,
                  ),
                ),
                if (player.name != (player.shortName ?? player.name))
                  Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMedium,
                    ),
                  ),
              ],
            ),
          ),
          if (player.isCaptain)
            _LineupMiniBadge(label: 'C', color: context.colors.primary),
          if (goals is num && goals > 0)
            _LineupMiniBadge(
                label: '${goals.toInt()}G', color: context.colors.success),
          const SizedBox(width: 6),
          Text(
            player.position ?? '-',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineupSubstitutionTile extends StatelessWidget {
  final LineupPlayer playerOut;
  final LineupSubstitution substitution;

  const _LineupSubstitutionTile({
    required this.playerOut,
    required this.substitution,
  });

  @override
  Widget build(BuildContext context) {
    final minute = substitution.minuteLabel.isEmpty
        ? 'SUB'
        : '${substitution.minuteLabel} dk';
    final outName = playerOut.shortName ?? playerOut.name;
    final inName = substitution.playerInName ?? 'Giren oyuncu';

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          _SubstitutionSide(
            name: outName,
            meta: '$minute cikti',
            color: context.colors.error,
            icon: Icons.arrow_upward_rounded,
            alignEnd: false,
          ),
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 18,
              color: context.colors.textMedium,
            ),
          ),
          _SubstitutionSide(
            name: inName,
            meta: '$minute girdi',
            color: context.colors.success,
            icon: Icons.arrow_downward_rounded,
            alignEnd: true,
          ),
        ],
      ),
    );
  }
}

class _SubstitutionSide extends StatelessWidget {
  final String name;
  final String meta;
  final Color color;
  final IconData icon;
  final bool alignEnd;

  const _SubstitutionSide({
    required this.name,
    required this.meta,
    required this.color,
    required this.icon,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!alignEnd) Icon(icon, size: 15, color: color),
          if (!alignEnd) const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignEnd ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignEnd ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          if (alignEnd) const SizedBox(width: 5),
          if (alignEnd) Icon(icon, size: 15, color: color),
        ],
      ),
    );
  }
}

class _LineupMiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _LineupMiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _LineupEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _LineupEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: context.colors.textMedium),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: context.colors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: context.colors.textMedium,
            ),
          ),
        ],
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

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.9,
        upperBound: 1.0)
      ..value = 1.0;
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
                  border: Border.all(
                      color: context.colors.surfaceContainerHighest
                          .withValues(alpha: 0.6)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 1,
                        offset: Offset(0, 1))
                  ],
                ),
                child: Center(
                    child: Text(widget.emoji,
                        style: const TextStyle(fontSize: 20))),
              ),
            );
          }),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  final List<MatchTimelineEvent> events;
  final String homeTeam;
  final String awayTeam;

  const _TimelineRail({
    required this.events,
    required this.homeTeam,
    required this.awayTeam,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? currentGroup;
    for (final event in events) {
      final group = _periodLabel(event);
      if (group != currentGroup) {
        currentGroup = group;
        children.add(_TimelinePeriodHeader(label: group));
      }
      children.add(_TimelineEventTile(
        event: event,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        isLast: event == events.last,
      ));
    }
    return Column(children: children);
  }

  String _periodLabel(MatchTimelineEvent event) {
    final minute = event.minute ?? 0;
    if (event.type == 'FULL_TIME') return 'MAC SONU';
    if (minute > 45) return 'IKINCI YARI';
    return 'ILK YARI';
  }
}

class _TimelinePeriodHeader extends StatelessWidget {
  final String label;

  const _TimelinePeriodHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(54, 8, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: context.colors.surfaceContainerHighest,
              thickness: 1,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: context.colors.textLow,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: context.colors.surfaceContainerHighest,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEventTile extends StatelessWidget {
  final MatchTimelineEvent event;
  final String homeTeam;
  final String awayTeam;
  final bool isLast;

  const _TimelineEventTile({
    required this.event,
    required this.homeTeam,
    required this.awayTeam,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(context, event.type);
    final icon = _eventIcon(event.type);
    final teamName = event.team == 'home'
        ? homeTeam
        : event.team == 'away'
            ? awayTeam
            : null;
    final isMajor = _isMajorEvent(event.type);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  event.minuteLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : context.colors.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 34,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: isMajor ? 34 : 28,
                height: isMajor ? 34 : 28,
                decoration: BoxDecoration(
                  color:
                      isMajor ? color : context.colors.surfaceContainerLowest,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isMajor ? 0 : 2),
                  boxShadow: isMajor
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isMajor ? context.colors.surface : color,
                  size: isMajor ? 19 : 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Container(
                padding: EdgeInsets.all(isMajor ? 14 : 0),
                decoration: BoxDecoration(
                  color: isMajor
                      ? color.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: isMajor
                      ? Border.all(color: color.withValues(alpha: 0.22))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: isMajor ? 15 : 14,
                              fontWeight: FontWeight.w900,
                              color: context.colors.textHigh,
                            ),
                          ),
                        ),
                        if (event.score != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              event.score!,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMedium,
                      ),
                    ),
                    if (teamName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: context.colors.textLow,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              teamName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: context.colors.textLow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'GOAL':
      case 'PENALTY_GOAL':
      case 'OWN_GOAL':
        return Icons.sports_soccer_rounded;
      case 'RED_CARD':
      case 'YELLOW_CARD':
        return Icons.style_rounded;
      case 'SUBSTITUTION':
        return Icons.swap_horiz_rounded;
      case 'HALF_TIME':
      case 'FULL_TIME':
      case 'PERIOD':
        return Icons.flag_rounded;
      case 'INJURY_TIME':
        return Icons.timer_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  Color _eventColor(BuildContext context, String type) {
    switch (type) {
      case 'GOAL':
      case 'PENALTY_GOAL':
        return context.colors.success;
      case 'OWN_GOAL':
      case 'RED_CARD':
        return context.colors.error;
      case 'YELLOW_CARD':
        return context.colors.accent;
      case 'SUBSTITUTION':
        return context.colors.primary;
      default:
        return context.colors.textMedium;
    }
  }

  bool _isMajorEvent(String type) {
    return const {
      'GOAL',
      'PENALTY_GOAL',
      'OWN_GOAL',
      'RED_CARD',
      'PENALTY_MISSED',
    }.contains(type);
  }
}

class _TimelineEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _TimelineEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 96, 24, 96),
      children: [
        Icon(icon, size: 46, color: context.colors.textMedium),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: context.colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.colors.textMedium,
          ),
        ),
      ],
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
  double get minExtent => topPadding + 190.0;

  @override
  double get maxExtent => topPadding + 190.0;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double collapseForce = maxExtent == minExtent
        ? 0.0
        : (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final double expandedOpacity =
        (1.0 - (collapseForce * 1.5)).clamp(0.0, 1.0);
    final double collapsedOpacity =
        ((collapseForce - 0.5) * 2.0).clamp(0.0, 1.0);

    final homeAbbr = match.homeTeam.toUpperCase();
    final awayAbbr = match.awayTeam.toUpperCase();
    final isLive = match.status == model.MatchStatus.live;
    final statusText = isLive
        ? match.liveMinute ?? 'LIVE'
        : (match.status == model.MatchStatus.finished
            ? "Full Time"
            : "Upcoming");

    final int? hScore = int.tryParse(match.homeScore ?? '');
    final int? aScore = int.tryParse(match.awayScore ?? '');

    Color homeBarColor = context.colors.surfaceContainerHighest;
    Color awayBarColor = context.colors.surfaceContainerHighest;
    bool homeGlow = false;
    bool awayGlow = false;

    if (hScore != null &&
        aScore != null &&
        (isLive || match.status == model.MatchStatus.finished)) {
      if (hScore > aScore) {
        homeBarColor = context.colors.success;
        awayBarColor = context.colors.error.withValues(alpha: 0.6);
        homeGlow = true;
      } else if (hScore < aScore) {
        homeBarColor = context.colors.error.withValues(alpha: 0.6);
        awayBarColor = context.colors.success;
        awayGlow = true;
      } else {
        homeBarColor = context.colors.liveAccentMuted;
        awayBarColor = context.colors.liveAccentMuted;
        homeGlow = isLive;
        awayGlow = isLive;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
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
                    padding: EdgeInsets.only(top: topPadding + 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          context.colors.primaryContainer.withValues(
                              alpha: 0.08 + (bgPulseController.value * 0.04)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: child,
                  );
                },
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: context.colors.primaryContainer
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text("MATCH PULSE",
                            style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.5,
                                color: context.colors.primary
                                    .withValues(alpha: 0.8))),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color:
                              context.colors.background.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: context.colors.primaryContainer
                                    .withValues(alpha: 0.1),
                                blurRadius: 24,
                                offset: const Offset(0, 12)),
                            const BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                      tag: 'match-${match.id}-home-logo',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Image.network(match.homeLogo,
                                            width: 36,
                                            height: 36,
                                            errorBuilder: (ctx, err, _) =>
                                                const Icon(Icons.shield,
                                                    size: 36)),
                                      )),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(homeAbbr,
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: context.colors.textHigh)),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                      height: 5,
                                      width: 36,
                                      decoration: BoxDecoration(
                                          color: homeBarColor,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          boxShadow: homeGlow
                                              ? [
                                                  BoxShadow(
                                                      color: homeBarColor
                                                          .withValues(
                                                              alpha: 0.6),
                                                      blurRadius: 8,
                                                      spreadRadius: 2)
                                                ]
                                              : [])),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                  border: Border(
                                      left: BorderSide(
                                          color: context
                                              .colors.surfaceContainerHighest
                                              .withValues(alpha: 0.3)),
                                      right: BorderSide(
                                          color: context
                                              .colors.surfaceContainerHighest
                                              .withValues(alpha: 0.3)))),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(match.homeScore ?? '-',
                                      style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: context.colors.textHigh,
                                          letterSpacing: -1.0)),
                                  const SizedBox(width: 4),
                                  AnimatedBuilder(
                                      animation: pulseController,
                                      builder: (context, child) {
                                        final double intensity = isLive
                                            ? pulseController.value
                                            : 0.0;
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 0),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              if (intensity > 0)
                                                Container(
                                                  width: 1,
                                                  height: 1,
                                                  decoration:
                                                      BoxDecoration(boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.amberAccent
                                                          .withValues(
                                                              alpha: 0.6 *
                                                                  intensity),
                                                      blurRadius:
                                                          25 * intensity,
                                                      spreadRadius:
                                                          15 * intensity,
                                                    )
                                                  ]),
                                                ),
                                              Icon(
                                                Icons.bolt_rounded,
                                                size: 48, // Tam boy
                                                color: isLive
                                                    ? Colors.amberAccent
                                                    : context.colors.textMedium
                                                        .withValues(alpha: 0.5),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                  const SizedBox(width: 4),
                                  Text(match.awayScore ?? '-',
                                      style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: context.colors.textHigh,
                                          letterSpacing: -1.0)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Hero(
                                      tag: 'match-${match.id}-away-logo',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: Image.network(match.awayLogo,
                                            width: 36,
                                            height: 36,
                                            errorBuilder: (ctx, err, _) =>
                                                const Icon(Icons.shield,
                                                    size: 36)),
                                      )),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(awayAbbr,
                                        maxLines: 1,
                                        style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: context.colors.textHigh)),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                      height: 5,
                                      width: 36,
                                      decoration: BoxDecoration(
                                          color: awayBarColor,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                          boxShadow: awayGlow
                                              ? [
                                                  BoxShadow(
                                                      color: awayBarColor
                                                          .withValues(
                                                              alpha: 0.6),
                                                      blurRadius: 8,
                                                      spreadRadius: 2)
                                                ]
                                              : [])),
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

          // 2. Collapsed Sticky Bar layer
          if (collapsedOpacity > 0)
            Opacity(
              opacity: collapsedOpacity,
              child: Container(
                padding: EdgeInsets.only(top: topPadding, left: 8, right: 8),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    const SizedBox(
                        width: 44), // Space left for absolute back button
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text("$homeAbbr ",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: context.colors.textHigh,
                                        letterSpacing: -0.5)),
                              ),
                              Icon(Icons.bolt_rounded,
                                  size: 24, // Scaled up in collapsed
                                  color: isLive
                                      ? Colors.amberAccent
                                      : context.colors.textMedium),
                              Flexible(
                                child: Text(" $awayAbbr",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: context.colors.textHigh,
                                        letterSpacing: -0.5)),
                              ),
                              Text(
                                  " · ${match.homeScore ?? '-'} - ${match.awayScore ?? '-'}",
                                  style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: context.colors.textHigh,
                                      letterSpacing: -0.5)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: isLive
                                        ? context.colors.secondary
                                            .withValues(alpha: 0.08)
                                        : context
                                            .colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    if (isLive)
                                      AnimatedBuilder(
                                        animation: pulseController,
                                        builder: (context, child) {
                                          return Opacity(
                                            opacity: 0.3 +
                                                (pulseController.value * 0.7),
                                            child: Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: context
                                                        .colors.secondary)),
                                          );
                                        },
                                      ),
                                    if (isLive) const SizedBox(width: 4),
                                    Text(statusText,
                                        style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isLive
                                                ? context.colors.secondary
                                                : context.colors.textMedium,
                                            letterSpacing: 0.5)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: context.colors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Row(
                                  children: [
                                    Icon(Icons.group,
                                        size: 12,
                                        color: context.colors.textMedium),
                                    const SizedBox(width: 4),
                                    Text("12.4k fans",
                                        style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: context.colors.textMedium)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                        icon: const Icon(Icons.more_vert),
                        color: context.colors.textMedium,
                        onPressed: () {},
                        splashRadius: 24),
                  ],
                ),
              ),
            ),

          // 3. Absolute back button (always visible and functional)
          Positioned(
            top: topPadding -
                4, // Moves arrow up closer to the status bar limits
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
    );
  }

  @override
  bool shouldRebuild(covariant MatchDetailHeaderDelegate oldDelegate) => true;
}

class _SoundWaveAnimation extends StatefulWidget {
  @override
  __SoundWaveAnimationState createState() => __SoundWaveAnimationState();
}

class __SoundWaveAnimationState extends State<_SoundWaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            double value =
                sin((_controller.value * 2 * pi) + (index * 1.5)) * 0.5 + 0.5;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 4 + (value * 12),
              decoration: BoxDecoration(
                color: context.colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }
}
