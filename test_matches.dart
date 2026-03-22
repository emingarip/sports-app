import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  const url = 'https://nigatikzsnxdqdwwqewr.supabase.co/rest/v1/matches?select=*';
  const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZ2F0aWt6c254ZHFkd3dxZXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjM2MjEsImV4cCI6MjA4OTUzOTYyMX0.smjivrwy8D8I5rRs49mXRkHSyOAJcti2VwCbm2Oas6Q';
  
  try {
    final response = await http.get(Uri.parse(url), headers: {
      'apikey': token,
      'Authorization': 'Bearer $token'
    });
    print('Matches Response: ${response.body}');
    
    final List<dynamic> data = jsonDecode(response.body);
    print('Total matches found: ${data.length}');
  } catch (e) {
    print('Error: $e');
  }
}
