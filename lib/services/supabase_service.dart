import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_theme_preferences.dart';

class SupabaseService {
  static const String _devSupabaseUrl =
      'https://nigatikzsnxdqdwwqewr.supabase.co';
  static const String _devSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZ2F0aWt6c254ZHFkd3dxZXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjM2MjEsImV4cCI6MjA4OTUzOTYyMX0.smjivrwy8D8I5rRs49mXRkHSyOAJcti2VwCbm2Oas6Q';
  static const String projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: kReleaseMode ? '' : _devSupabaseUrl,
  );
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: kReleaseMode ? '' : _devSupabaseAnonKey,
  );
  static final SupabaseService _instance = SupabaseService._internal();
  static Future<void>? _initializeFuture;

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() {
    return _initializeFuture ??= _initializeOnce();
  }

  static Future<void> _initializeOnce() async {
    try {
      if (projectUrl.isEmpty || _supabaseAnonKey.isEmpty) {
        throw StateError(
          'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Provide them via --dart-define or --dart-define-from-file.',
        );
      }

      await Supabase.initialize(
        url: projectUrl,
        anonKey: _supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully.');
    } catch (e) {
      debugPrint('Error initializing Supabase: $e');
    }
  }

  // --- Auth Methods ---

  Future<void> signInWithOtp(String email) async {
    await client.auth.signInWithOtp(email: email);
  }

  Future<AuthResponse> verifyOTP(String email, String token) async {
    return await client.auth.verifyOTP(
      type: OtpType.email,
      email: email,
      token: token,
    );
  }

  Future<AuthResponse> signUp(
      {required String email,
      required String password,
      required String username}) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username}, // Passes to auth.users raw_user_meta_data
    );
  }

  Future<UserResponse> completeOnboarding() async {
    return await client.auth.updateUser(
      UserAttributes(data: {'onboarding_completed': true}),
    );
  }

  Future<AuthResponse> signIn(
      {required String email, required String password}) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
    await AppThemePreferences.clearPremiumThemeCache();
  }

  User? getCurrentUser() {
    return client.auth.currentUser;
  }

  // --- Profile Methods ---

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response =
          await client.from('users').select().eq('id', userId).maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<bool> updateUserProfile(String userId,
      {String? username, String? avatarUrl}) async {
    try {
      final updates = <String, dynamic>{};
      if (username != null) updates['username'] = username;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      if (updates.isEmpty) return true;

      await client.from('users').update(updates).eq('id', userId);

      // Also sync username to auth metadata for future consistency
      if (username != null) {
        await client.auth.updateUser(
          UserAttributes(data: {'username': username}),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      return false;
    }
  }

  Future<String?> uploadAvatar(
      String userId, Uint8List imageBytes, String fileExt) async {
    try {
      final fileName =
          '$userId.${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      // We use raw HTTP POST here instead of client.storage.from(...).uploadBinary(...)
      // because the Supabase Dart SDK forces an 'x-upsert' header which triggers
      // strict CORS preflight rejections (Failed to fetch) natively on Flutter Web.
      if (projectUrl.isEmpty) {
        throw StateError('SUPABASE_URL is not configured.');
      }
      final url = Uri.parse('$projectUrl/storage/v1/object/avatars/$fileName');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${client.auth.currentSession?.accessToken}',
          'Content-Type': 'image/$fileExt',
        },
        body: imageBytes,
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Storage upload failed with code: ${response.statusCode} - ${response.body}');
      }

      // Bypass the bugged client.storage.from('avatars').getPublicUrl(fileName)
      // which creates an invalid Edge URL (.storage.supabase.co/v1/object/public) throwing 404s.
      // We manually construct the guaranteed public URL pointing to the core proxy.
      final publicUrl =
          '$projectUrl/storage/v1/object/public/avatars/$fileName';
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading avatar: $e');
      return null;
    }
  }

  Future<void> deleteAvatar(String fileName) async {
    try {
      if (fileName.isEmpty) return;

      // We bypass client.storage.from('avatars').remove() because the Dart SDK
      // automatically constructs the malformed .storage.supabase.co/v1 Edge route
      // which results in silent CORS/404 failures just like the upload endpoint.
      if (projectUrl.isEmpty) {
        throw StateError('SUPABASE_URL is not configured.');
      }
      final url = Uri.parse('$projectUrl/storage/v1/object/avatars');

      final request = http.Request('DELETE', url)
        ..headers.addAll({
          'Authorization': 'Bearer ${client.auth.currentSession?.accessToken}',
          'Content-Type': 'application/json',
        })
        ..body = '{"prefixes": ["$fileName"]}';

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        debugPrint('Old avatar deleted successfully via HTTP: $fileName');
      } else {
        final responseBody = await response.stream.bytesToString();
        debugPrint(
            'Failed to delete old avatar via HTTP: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      debugPrint('Error deleting old avatar: $e');
    }
  }

  Future<bool> equipUserFrame(String userId, String? frameCode) async {
    try {
      await client.rpc('equip_user_frame', params: {
        'p_user_id': userId,
        'p_frame_code': frameCode,
      });
      return true;
    } catch (e) {
      debugPrint('Error equipping user frame: $e');
      return false;
    }
  }

  Future<bool> rewardUserCoins(int amount) async {
    if (!kDebugMode) {
      debugPrint(
        'rewardUserCoins is disabled outside debug builds. Use claim-kcoin-reward instead.',
      );
      return false;
    }

    try {
      final response = await client.rpc('reward_k_coins', params: {
        'p_amount': amount,
      });
      if (response != null && response is Map && response['success'] == true) {
        debugPrint(
            "K-Coins rewarded successfully! New balance: \${response['new_balance']}");
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error rewarding K-Coins (RPC): $e');
      return false;
    }
  }

  Future<bool> isUsernameAvailable(String username) async {
    try {
      if (username.trim().isEmpty) return false;

      final response = await client
          .from('users')
          .select('id')
          .eq('username', username.trim())
          .maybeSingle();

      return response == null; // Available if no existing row is found
    } catch (e) {
      debugPrint('Error checking username availability: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUserBets(String userId) async {
    try {
      final response = await client
          .from('user_bets')
          .select('''
            id,
            amount_staked,
            potential_payout,
            status,
            created_at,
            predictions (
              prediction_type,
              odds
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching user bets: $e');
      return [];
    }
  }

  // Retrieves a dynamic app configuration string from the public.app_settings table
  Future<String?> getAppSetting(String key) async {
    try {
      final response = await client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      if (response != null) {
        return response['value'] as String;
      }
    } catch (e) {
      debugPrint('Error getting setting $key: $e');
    }
    return null;
  }

  // Check ad eligibility (daily limit, cooldown)
  Future<Map<String, dynamic>> checkAdEligibility() async {
    try {
      final response = await client.rpc('check_ad_eligibility');
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error checking ad eligibility: $e');
      return {'eligible': false, 'reason': 'error'};
    }
  }
}
