import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
      
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
        debugPrint('Supabase initialized successfully.');
      } else {
        debugPrint('Supabase initialization skipped: Missing credentials in .env');
      }
    } catch (e) {
      debugPrint('Error initializing Supabase or reading .env: $e');
    }
  }

  // --- Auth Methods ---
  
  Future<AuthResponse> signUp({required String email, required String password, required String username}) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username}, // Passes to auth.users raw_user_meta_data
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
}
