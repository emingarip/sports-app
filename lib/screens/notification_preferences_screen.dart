import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/notification_preferences_provider.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefState = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: context.colors.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(vertical: BorderSide(color: context.colors.surfaceContainerLow, width: 2)),
          ),
          child: Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: prefState.when(
                  data: (prefs) {
                    if (prefs == null) {
                      return Center(
                        child: Text(
                          "Could not load preferences.",
                          style: TextStyle(color: context.colors.textMedium),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      children: [
                        Text(
                          "Decide which alerts you want to receive directly to your device.",
                          style: TextStyle(color: context.colors.textMedium, fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        _buildPreferenceGroupHeader(context, "MATCH ALERTS"),
                        _buildGlassmorphicSwitch(
                          context: context,
                          title: "Match Started",
                          subtitle: "Get notified as soon as kickoff happens.",
                          icon: Icons.sports_soccer,
                          value: prefs.notifyMatchStart,
                          onChanged: (val) => ref.read(notificationPreferencesProvider.notifier).toggleMatchStart(val),
                        ),
                        const SizedBox(height: 12),
                        _buildGlassmorphicSwitch(
                          context: context,
                          title: "Half / Full Time",
                          subtitle: "Score summaries at major whistle breaks.",
                          icon: Icons.timer,
                          value: prefs.notifyMatchEnd,
                          onChanged: (val) => ref.read(notificationPreferencesProvider.notifier).toggleMatchEnd(val),
                        ),
                        const SizedBox(height: 12),
                        _buildGlassmorphicSwitch(
                          context: context,
                          title: "Goals",
                          subtitle: "Instant updates when the ball hits the net.",
                          icon: Icons.sports_score,
                          value: prefs.notifyGoals,
                          onChanged: (val) => ref.read(notificationPreferencesProvider.notifier).toggleGoals(val),
                        ),
                        const SizedBox(height: 24),
                        _buildPreferenceGroupHeader(context, "PREDICTION MARKET"),
                        _buildGlassmorphicSwitch(
                          context: context,
                          title: "Market Resolutions",
                          subtitle: "Alerts when your predictions win or lose.",
                          icon: Icons.insights,
                          value: prefs.notifyPredictions,
                          onChanged: (val) => ref.read(notificationPreferencesProvider.notifier).togglePredictions(val),
                        ),
                      ],
                    );
                  },
                  loading: () => Center(child: CircularProgressIndicator(color: context.colors.primary)),
                  error: (e, st) => Center(child: Text('Error: $e', style: TextStyle(color: context.colors.error))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: context.colors.background.withOpacity(0.8),
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 16),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: context.colors.textHigh),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  'NOTIFICATIONS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                    color: context.colors.textHigh,
                  ),
                ),
              ),
              const SizedBox(width: 48), // Balance spacing
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreferenceGroupHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: context.colors.primary,
        ),
      ),
    );
  }

  Widget _buildGlassmorphicSwitch({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.surfaceContainerLow),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.colors.textHigh),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            subtitle,
            style: TextStyle(color: context.colors.textMedium, fontSize: 12),
          ),
        ),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.colors.primary, size: 20),
        ),
        activeColor: context.colors.onPrimaryContainer,
        activeTrackColor: context.colors.primaryContainer,
        inactiveThumbColor: context.colors.textMedium,
        inactiveTrackColor: context.colors.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
