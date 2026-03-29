import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/announcement.dart';

// State to hold both the raw announcements and the dismissed list
class AnnouncementState {
  final List<Announcement> activeAnnouncements;
  final List<String> dismissedIds;
  final bool isLoading;

  AnnouncementState({
    required this.activeAnnouncements,
    required this.dismissedIds,
    this.isLoading = false,
  });

  // Derived getter: Only announcements that are active AND not dismissed
  List<Announcement> get visibleAnnouncements {
    return activeAnnouncements.where((a) => !dismissedIds.contains(a.id)).toList();
  }

  AnnouncementState copyWith({
    List<Announcement>? activeAnnouncements,
    List<String>? dismissedIds,
    bool? isLoading,
  }) {
    return AnnouncementState(
      activeAnnouncements: activeAnnouncements ?? this.activeAnnouncements,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AnnouncementNotifier extends Notifier<AnnouncementState> {
  late RealtimeChannel _announcementSubscription;
  static const String _prefsKey = 'dismissed_announcements';

  @override
  AnnouncementState build() {
    ref.onDispose(() {
      Supabase.instance.client.removeChannel(_announcementSubscription);
    });
    // Can't await directly in build returning synchronous state, we'll kick it off.
    Future.microtask(_init);
    return AnnouncementState(activeAnnouncements: [], dismissedIds: [], isLoading: true);
  }

  Future<void> _init() async {
    // 1. Load dismissed IDs from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getStringList(_prefsKey) ?? [];
    
    state = state.copyWith(dismissedIds: dismissed);

    // 2. Fetch initial active announcements
    await _fetchActiveAnnouncements();

    // 3. Set up Realtime listener
    _setupRealtimeSubscription();
  }

  Future<void> _fetchActiveAnnouncements() async {
    try {
      final response = await Supabase.instance.client
          .from('global_announcements')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final announcements = (response as List<dynamic>)
          .map((data) => Announcement.fromJson(data))
          .toList();

      state = state.copyWith(activeAnnouncements: announcements, isLoading: false);
    } catch (e) {
      print('Error fetching announcements: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void _setupRealtimeSubscription() {
    _announcementSubscription = Supabase.instance.client.channel('public:global_announcements').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'global_announcements',
      callback: (payload) {
        // Safe check for realtime event payloads
        _fetchActiveAnnouncements(); // Re-fetch on any change to keep logic simple
      },
    ).subscribe();
  }

  Future<void> dismissAnnouncement(String id) async {
    // Add to state
    final newDismissed = List<String>.from(state.dismissedIds)..add(id);
    state = state.copyWith(dismissedIds: newDismissed);

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, newDismissed);
  }
}

final announcementProvider = NotifierProvider<AnnouncementNotifier, AnnouncementState>(AnnouncementNotifier.new);

