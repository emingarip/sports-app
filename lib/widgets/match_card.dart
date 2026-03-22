import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/match.dart' as model;
import '../screens/match_room_screen.dart';

class MatchCard extends StatelessWidget {
  final model.Match match;
  final bool hasBorder;

  const MatchCard({super.key, required this.match, required this.hasBorder});

  @override
  Widget build(BuildContext context) {
    bool isLive = match.status == model.MatchStatus.live;
    String statusTime = isLive 
        ? (match.liveMinute ?? 'LIVE') 
        : (match.status == model.MatchStatus.finished ? 'Full Time' : _formatTime(match.startTime));
    
    String actionText = isLive ? 'PREDICT' : (match.status == model.MatchStatus.finished ? 'STATS' : 'ODDS 2.10');

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(match: match)));
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
            child: Column(
              children: [
                if (isLive) Text("LIVE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: context.colors.error, letterSpacing: 1.5)),
                if (!isLive) Text(statusTime.replaceAll(" ", "\n"), textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: context.colors.textLow, letterSpacing: 0.5, height: 1.1)),
                if (isLive) Text(statusTime, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.error)),
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
                      Image.network(match.homeLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                      const SizedBox(height: 4),
                      Text(match.homeTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: FittedBox(
                    child: Row(
                      children: [
                        Text(match.homeScore ?? "-", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isLive ? context.colors.textHigh : context.colors.textLow)),
                        const SizedBox(width: 8),
                        Text("-", style: TextStyle(fontSize: 16, color: context.colors.surfaceContainer)),
                        const SizedBox(width: 8),
                        Text(match.awayScore ?? "-", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: context.colors.textHigh)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Image.network(match.awayLogo, width: 28, height: 28, errorBuilder: (ctx, err, _) => const Icon(Icons.shield)),
                      const SizedBox(height: 4),
                      Text(match.awayTeam, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isLive ? Colors.transparent : context.colors.surfaceContainerLow,
                  border: isLive ? Border.all(color: context.colors.secondaryContainer) : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isLive ? context.colors.secondary : context.colors.textLow,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
