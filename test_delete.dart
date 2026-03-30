import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? 'https://nigatikzsnxdqdwwqewr.supabase.co';
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';

  final client = SupabaseClient(supabaseUrl, supabaseKey);
  
  // Try deleting the old jpeg
  final fileName = 'd669391c-5b37-48d6-b107-46e44567bb49.1774855245646.jpeg';
  print('Attempting to delete \$fileName');
  try {
    final res = await client.storage.from('avatars').remove([fileName]);
    print('Result: \$res');
  } catch (e) {
    print('Failed: \$e');
  }
}
