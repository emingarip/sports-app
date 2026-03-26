import 'dart:io';
import 'package:supabase/supabase.dart';

void main() async {
  final envFile = File('admin_dashboard/.env.local');
  final lines = await envFile.readAsLines();
  String url = '';
  String key = '';
  for (var line in lines) {
    if (line.startsWith('VITE_SUPABASE_URL=')) url = line.substring(18);
    if (line.startsWith('VITE_SUPABASE_ANON_KEY=')) key = line.substring(23);
  }
  
  final supabase = SupabaseClient(url.trim(), key.trim());
  
  print('Running cleanup for Ellerton match...');
  final response = await supabase
      .from('matches')
      .update({'status': 'finished'})
      .eq('provider_id', 'highlightly_1288771353')
      .select();
      
  print('Updated rows: $response');
  exit(0);
}
