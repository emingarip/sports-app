import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_preferences.dart';
import '../services/supabase_service.dart';

final notificationPreferencesProvider = AsyncNotifierProvider<NotificationPreferencesNotifier, NotificationPreferences?>(() {
  return NotificationPreferencesNotifier();
});

class NotificationPreferencesNotifier extends AsyncNotifier<NotificationPreferences?> {
  @override
  Future<NotificationPreferences?> build() async {
    return _fetchPreferences();
  }

  Future<NotificationPreferences?> _fetchPreferences() async {
    final user = SupabaseService().getCurrentUser();
    if (user == null) return null;

    try {
      final response = await SupabaseService.client
          .from('user_notification_preferences')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (response != null) {
        return NotificationPreferences.fromJson(response);
      } else {
        // If not found, insert default preferences
        final defaultPrefs = NotificationPreferences(userId: user.id);
        final insertResponse = await SupabaseService.client
            .from('user_notification_preferences')
            .upsert(defaultPrefs.toJson())
            .select()
            .single();
        return NotificationPreferences.fromJson(insertResponse);
      }
    } catch (e) {
      print('Error fetching notification preferences: $e');
      return null;
    }
  }

  Future<void> toggleMatchStart(bool value) async {
    await _updatePreference('notify_match_start', value, (prefs) => prefs.copyWith(notifyMatchStart: value));
  }

  Future<void> toggleMatchEnd(bool value) async {
    await _updatePreference('notify_match_end', value, (prefs) => prefs.copyWith(notifyMatchEnd: value));
  }

  Future<void> toggleGoals(bool value) async {
    await _updatePreference('notify_goals', value, (prefs) => prefs.copyWith(notifyGoals: value));
  }

  Future<void> togglePredictions(bool value) async {
    await _updatePreference('notify_predictions', value, (prefs) => prefs.copyWith(notifyPredictions: value));
  }

  Future<void> _updatePreference(String column, bool value, NotificationPreferences Function(NotificationPreferences) copyWithParams) async {
    final user = SupabaseService().getCurrentUser();
    final currentState = state.value;
    if (user == null || currentState == null) return;

    // Optimistically update the UI
    state = AsyncData(copyWithParams(currentState));

    try {
      await SupabaseService.client
          .from('user_notification_preferences')
          .update({
            column: value,
            'updated_at': DateTime.now().toUtc().toIso8601String()
          })
          .eq('user_id', user.id);
    } catch (e) {
      print('Error updating $column: $e');
      // Revert on failure by refetching
      refetch();
    }
  }

  Future<void> refetch() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPreferences());
  }
}
