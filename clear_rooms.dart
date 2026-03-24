import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    print('Failed to load environment variables.');
    return;
  }
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  
  print('Clearing all audio rooms...');
  try {
    // Delete all records in audio_rooms where status is active (or just all)
    await Supabase.instance.client
        .from('audio_rooms')
        .delete()
        .neq('status', 'non_existent_status_to_match_all'); // simple hack to delete all or use generic eq

    print('Successfully cleared old rooms!');
  } catch (e) {
    print('Error: $e');
  }
}
