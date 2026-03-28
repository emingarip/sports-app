import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'supabase_service.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService();
});

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> requestPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_requested_notification_permission', true);

      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _setupFCM();
      }
    } catch (e) {
      debugPrint("FCM Request Error: $e");
    }
  }

  Future<void> initialize() async {
    try {
      NotificationSettings settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _setupFCM();
      }
    } catch (e) {
      debugPrint("FCM Initialization Error: $e");
    }
  }

  Future<bool> isPermissionNotDetermined() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRequested = prefs.getBool('has_requested_notification_permission') ?? false;

      NotificationSettings settings = await _fcm.getNotificationSettings();
      // Web and iOS return notDetermined initially.
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        return !hasRequested;
      }
      
      // Android 13+ returns denied initially.
      if (defaultTargetPlatform == TargetPlatform.android && settings.authorizationStatus == AuthorizationStatus.denied) {
        return !hasRequested;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _setupFCM() async {
    try {
      String? token;
      if (kIsWeb) {
        token = await _fcm.getToken(
          vapidKey: 'BC-j7AHpqkk3VruJBUG71vzIODZCKyOmfkC7MNy2UBbo0fvgtBgnw5ocmRFjX2gz_NWMwnqVzyCCN_T0Gm0i_ds',
        );
      } else {
        token = await _fcm.getToken();
      }
      debugPrint('FCM Token: $token');

      if (token != null) {
        await _saveTokenToDatabase(token);
      }

      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToDatabase(newToken);
      });

      _setupMessageHandlers();
    } catch (e) {
      debugPrint("FCM Setup Error: $e");
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final session = SupabaseService.client.auth.currentSession;
    if (session == null) return; // User not logged in, wait until login

    try {
      final userId = session.user.id;
      final deviceId = await _getDeviceId();
      final platform = defaultTargetPlatform.name.toLowerCase();

      await SupabaseService.client.from('user_devices').upsert(
        {
          'user_id': userId,
          'device_id': deviceId,
          'fcm_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id, device_id',
      );
      debugPrint("FCM Token saved to Supabase user_devices.");
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('push_fcm_device_id');
    
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('push_fcm_device_id', deviceId);
    }
    
    return "${defaultTargetPlatform.name.toLowerCase()}-$deviceId";
  }

  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
        // You could trigger a local flushbar/snackbar here if you want
        // But our Realtime Database listener in `NotificationNotifier` already does this!
        // So we might not need to do anything here for foreground.
      }
    });

    // Handle background / terminated app clicks
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      // Navigate to specific screen based on message.data if needed
    });
  }
}
