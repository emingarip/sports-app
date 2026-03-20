import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final url = 'https://nigatikzsnxdqdwwqewr.supabase.co/rest/v1/chat_messages?limit=2';
  final token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZ2F0aWt6c254ZHFkd3dxZXdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjM2MjEsImV4cCI6MjA4OTUzOTYyMX0.smjivrwy8D8I5rRs49mXRkHSyOAJcti2VwCbm2Oas6Q';
  
  try {
    final response = await http.get(Uri.parse(url), headers: {
      'apikey': token,
      'Authorization': 'Bearer \$token'
    });
    print('Raw HTTP Response: \${response.body}');
    
    final List<dynamic> data = jsonDecode(response.body);
    for (var json in data) {
      print('Parsed item message field: \${json['message']}');
    }
  } catch (e) {
    print('Error: \$e');
  }
}
