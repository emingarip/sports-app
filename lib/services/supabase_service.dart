import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
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
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint('Could not load .env file, falling back to hardcoded keys: $e');
    }
    
    try {
      var supabaseUrl = dotenv.isInitialized ? dotenv.env['SUPABASE_URL'] : null;
      if (supabaseUrl == null || supabaseUrl.isEmpty) {
        supabaseUrl = 'https://nigatikzsnxdqdwwqewr.supabase.co';
      }

      var supabaseAnonKey = dotenv.isInitialized ? dotenv.env['SUPABASE_ANON_KEY'] : null;
      if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
        supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZ2F0aWt6c254ZHFkd3dxZXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjM2MjEsImV4cCI6MjA4OTUzOTYyMX0.smjivrwy8D8I5rRs49mXRkHSyOAJcti2VwCbm2Oas6Q';
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
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

  Future<AuthResponse> signUp({required String email, required String password, required String username}) async {
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

  Future<AuthResponse> signIn({required String email, required String password}) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await client.auth.signOut();
  }
  
  User? getCurrentUser() {
    return client.auth.currentUser;
  }

  // --- Profile Methods ---
  
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<bool> updateUserProfile(String userId, {String? username, String? avatarUrl}) async {
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
}
