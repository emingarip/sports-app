import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_state.dart';

class WidgetService {
  static final WidgetService _instance = WidgetService._internal();
  factory WidgetService() => _instance;
  WidgetService._internal();

  final LiveActivities _liveActivitiesPlugin = LiveActivities();
  String? _currentActivityId;

  Future<void> initialize() async {
    if (kIsWeb) return;
    
    // Initialize Home Widget
    await HomeWidget.setAppGroupId('group.com.emingarip.sportsapp');

    // Initialize Live Activities
    await _liveActivitiesPlugin.init(appGroupId: 'group.com.emingarip.sportsapp');
  }

  /// Updates the Android/iOS Home Screen Widget with match data
  Future<void> updateHomeScreenWidget({
    required String homeTeam,
    required String awayTeam,
    required int homeScore,
    required int awayScore,
  }) async {
    if (kIsWeb) return;

    await HomeWidget.saveWidgetData<String>('widget_home_team', homeTeam);
    await HomeWidget.saveWidgetData<String>('widget_away_team', awayTeam);
    await HomeWidget.saveWidgetData<int>('widget_home_score', homeScore);
    await HomeWidget.saveWidgetData<int>('widget_away_score', awayScore);
    
    // WatchOS Complication Keys (AppGroup exported)
    await HomeWidget.saveWidgetData<int>('watch_home_score', homeScore);
    await HomeWidget.saveWidgetData<int>('watch_away_score', awayScore);

    await HomeWidget.updateWidget(
      name: 'SportsAppWidgetProvider', // Android
      iOSName: 'SportsAppWidgetExtension', // iOS
    );
  }

  /// Starts or updates an iOS Live Activity for an active match
  Future<void> startOrUpdateLiveActivity({
    required String matchId,
    required String homeTeam,
    required String awayTeam,
    required int homeScore,
    required int awayScore,
    required String minute,
    required String status,
  }) async {
    if (kIsWeb) return;

    final activityExists = await _liveActivitiesPlugin.areActivitiesEnabled();
    if (!activityExists) return; // Feature not supported or disabled

    final data = {
      'matchId': matchId,
      'homeTeamName': homeTeam,
      'awayTeamName': awayTeam,
      'homeTeamLogo': '',
      'awayTeamLogo': '',
      'homeScore': homeScore,
      'awayScore': awayScore,
      'minute': minute,
      'status': status,
    };

    if (_currentActivityId == null) {
      // Start a new activity
      _currentActivityId = await _liveActivitiesPlugin.createActivity(
        matchId,
        data,
      );
    } else {
      // Update existing activity
      await _liveActivitiesPlugin.updateActivity(_currentActivityId!, data);
    }
  }

  /// Ends the current Live Activity when the user leaves or match ends
  Future<void> endLiveActivity() async {
    if (kIsWeb) return;

    if (_currentActivityId != null) {
      await _liveActivitiesPlugin.endActivity(_currentActivityId!);
      _currentActivityId = null;
    } else {
      await _liveActivitiesPlugin.endAllActivities();
    }
  }
}
