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
    } catch (e) {
      debugPrint('Could not load .env file, falling back to hardcoded keys: $e');
    }
    
    try {
      var supabaseUrl = dotenv.env['SUPABASE_URL'];
      if (supabaseUrl == null || supabaseUrl.isEmpty) {
        supabaseUrl = 'https://nigatikzsnxdqdwwqewr.supabase.co';
      }

      var supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
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
