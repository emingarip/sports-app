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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _LineupStatusCard(report: report),
              const SizedBox(height: 12),
              _TeamLineupCard(
                title: widget.match.homeTeam,
                logoUrl: widget.match.homeLogo,
                lineup: report.home,
                substitutions: report.substitutions
                    .where((item) => item.isHome == true)
                    .toList(),
              ),
              const SizedBox(height: 12),
              _TeamLineupCard(
                title: widget.match.awayTeam,
                logoUrl: widget.match.awayLogo,
                lineup: report.away,
                substitutions: report.substitutions
                    .where((item) => item.isHome == false)
                    .toList(),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_rounded, color: context.colors.primary),
          ),
          const SizedBox(width: 12),
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
            ),
          if (lineup.bench.isNotEmpty) ...[
            const SizedBox(height: 14),
            _LineupSection(
              title: 'Yedekler',
              players: lineup.bench,
              substitutions: substitutions,
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

  const _LineupSection({
    required this.title,
    required this.players,
    required this.substitutions,
  });

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
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
        ...players.map(
          (player) => _LineupPlayerTile(
            player: player,
            substitution: _findSubstitutionForPlayer(player, substitutions),
          ),
        ),
      ],
    );
  }
}

class _LineupPlayerSubstitution {
  final bool isIn;
  final String minuteLabel;

  const _LineupPlayerSubstitution({
    required this.isIn,
    required this.minuteLabel,
  });

  String get label {
    return minuteLabel.isEmpty ? 'SUB' : minuteLabel;
  }
}

_LineupPlayerSubstitution? _findSubstitutionForPlayer(
  LineupPlayer player,
  List<LineupSubstitution> substitutions,
) {
  for (final substitution in substitutions) {
    if (_lineupPlayerMatches(
        player, substitution.playerInId, substitution.playerInName)) {
      return _LineupPlayerSubstitution(
        isIn: true,
        minuteLabel: substitution.minuteLabel,
      );
    }
    if (_lineupPlayerMatches(
        player, substitution.playerOutId, substitution.playerOutName)) {
      return _LineupPlayerSubstitution(
        isIn: false,
        minuteLabel: substitution.minuteLabel,
      );
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
  final _LineupPlayerSubstitution? substitution;

  const _LineupPlayerTile({required this.player, required this.substitution});

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
          if (substitution != null)
            _LineupSubstitutionBadge(substitution: substitution!),
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

class _LineupSubstitutionBadge extends StatelessWidget {
  final _LineupPlayerSubstitution substitution;

  const _LineupSubstitutionBadge({required this.substitution});

  @override
  Widget build(BuildContext context) {
    final color =
        substitution.isIn ? context.colors.success : context.colors.error;
    final icon = substitution.isIn
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            substitution.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
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
