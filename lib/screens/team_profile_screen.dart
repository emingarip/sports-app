import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TeamProfileScreen extends StatelessWidget {
  final String teamName;

  const TeamProfileScreen({super.key, required this.teamName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(teamName),
        backgroundColor: context.colors.surfaceContainerLow,
        iconTheme: IconThemeData(color: context.colors.textMedium),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(Icons.shield, size: 80, color: context.colors.surfaceContainer),
             const SizedBox(height: 16),
             Text(
               "$teamName Takım Profili",
               style: TextStyle(color: context.colors.textMedium, fontSize: 18),
             ),
             const SizedBox(height: 8),
             Text(
               "Fikstür ve istatistikler yakında...",
               style: TextStyle(color: context.colors.textMedium, fontSize: 14),
             ),
          ],
        ),
      ),
    );
  }
}
