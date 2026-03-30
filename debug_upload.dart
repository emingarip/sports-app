import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  final client = SupabaseClient(
    dotenv.env['SUPABASE_URL'] ?? 'https://nigatikzsnxdqdwwqewr.supabase.co',
    dotenv.env['SUPABASE_ANON_KEY'] ?? '...',
  );

  try {
    // Authenticate test user
    final res = await client.auth.signInWithPassword(
      email: 'test@example.com', // Replace with a test email or let it fail with auth if we just want to see if bucket exists
      password: 'testpassword',
    );
  } catch (e) {
    print('Auth error: $e');
  }

  try {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await client.storage.from('avatars').uploadBinary('test_avatar.jpg', bytes);
    print('Upload Success');
  } catch (e) {
    print('Upload Error: $e');
  }
}
