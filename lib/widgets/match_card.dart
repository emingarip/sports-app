import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/favorites_provider.dart';
import '../theme/app_theme.dart';
import '../models/match.dart' as model;
import '../screens/match_detail_screen.dart';
import '../services/push_notification_service.dart';
import 'notification_permission_dialog.dart';

class MatchCard extends ConsumerWidget {
  final model.Match match;
  final bool hasBorder;

  const MatchCard({super.key, required this.match, required this.hasBorder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool isLive = match.status == model.MatchStatus.live;
    final isFavorite = ref.watch(favoritesProvider).contains(match.id);
    String statusTime = isLive 
        ? (match.liveMinute ?? 'LIVE') 
        : (match.status == model.MatchStatus.finished ? 'Full Time' : _formatTime(match.startTime));

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(match: match)));
      },
      child: Container(
        decoration: BoxDecoration(
          border: hasBorder ? Border(bottom: BorderSide(color: context.colors.surfaceContainerLow)) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Time/Status
          SizedBox(
            width: 48,
            child: isLive 
              ? PulsingLiveText(
                  child: Column(
                    children: [
                      Text("LIVE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: context.colors.error, letterSpacing: 1.5)),
                      Text(statusTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.error)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Text(statusTime.replaceAll(" ", "\n"), textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: context.colors.textLow, letterSpacing: 0.5, height: 1.1)),
                  ],
                ),
          ),
          
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Hero(
                        tag: 'match-${match.id}-home-logo',
                        child: Material(
                          color: Colors.transparent,
                          child: Image.network(match.homeLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                        )
                      ),
                      const SizedBox(height: 4),
                      Text(match.homeTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: match.status == model.MatchStatus.upcoming
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text("VS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: context.colors.textLow, letterSpacing: 1.0)),
                        )
                      : FittedBox(
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                                child: Text(match.homeScore ?? "-", key: ValueKey(match.homeScore), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isLive ? context.colors.textHigh : context.colors.textLow)),
                              ),
                              const SizedBox(width: 8),
                              Text("-", style: TextStyle(fontSize: 16, color: context.colors.surfaceContainer)),
                              const SizedBox(width: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                                child: Text(match.awayScore ?? "-", key: ValueKey(match.awayScore), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.colors.textHigh)),
                              ),
                            ],
                          ),
                        ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Hero(
                        tag: 'match-${match.id}-away-logo',
                        child: Material(
                          color: Colors.transparent,
                          child: Image.network(match.awayLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                        )
                      ),
                      const SizedBox(height: 4),
                      Text(match.awayTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          GestureDetector(
            onTap: () async {
              ref.read(favoritesProvider.notifier).toggleFavorite(match.id);
              if (!isFavorite) {
                // If they just favorited, check if we should soft prompt for notifications
                // Add a small delay so UI reacts immediately before dialog pops
                await Future.delayed(const Duration(milliseconds: 200));
                if (!context.mounted) return;
                bool notDetermined = await ref.read(pushNotificationServiceProvider).isPermissionNotDetermined();
                if (notDetermined && context.mounted) {
                  await NotificationPermissionDialog.show(context);
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? context.colors.primary : context.colors.textLow,
                size: 20,
              ),
            ),
          )
        ],
      ),
    ));
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class PulsingLiveText extends StatefulWidget {
  final Widget child;
  const PulsingLiveText({super.key, required this.child});
  @override
  State<PulsingLiveText> createState() => _PulsingLiveTextState();
}

class _PulsingLiveTextState extends State<PulsingLiveText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    
    bool isTest = false;
    try {
      if (!kIsWeb) isTest = Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {}

    if (!isTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: Tween(begin: 0.3, end: 1.0).animate(_controller), child: widget.child);
  }
}
