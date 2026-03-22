import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class LeagueProfileScreen extends StatelessWidget {
  final String leagueName;

  const LeagueProfileScreen({super.key, required this.leagueName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(leagueName),
        backgroundColor: context.colors.surfaceContainerLow,
        iconTheme: IconThemeData(color: context.colors.textMedium),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(Icons.emoji_events, size: 80, color: context.colors.surfaceContainer),
             const SizedBox(height: 16),
             Text(
               "$leagueName Ligi Profili",
               style: TextStyle(color: context.colors.textMedium, fontSize: 18),
             ),
             const SizedBox(height: 8),
             Text(
               "Puan durumu ve fikstür yakında...",
               style: TextStyle(color: context.colors.textMedium, fontSize: 14),
             ),
          ],
        ),
      ),
    );
  }
}
