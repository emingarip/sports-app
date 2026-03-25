import 'dart:convert';
import 'dart:io';

void main() async {
  final envFile = File('admin_dashboard/.env.local');
  if (!await envFile.exists()) {
    print('No .env.local found in admin_dashboard.');
    return;
  }
  
  final lines = await envFile.readAsLines();
  String apiKey = '';
  for (var line in lines) {
    if (line.startsWith('VITE_HIGHLIGHTLY_API_KEY=')) {
      apiKey = line.split('=')[1].trim();
    }
  }

  // Highlightly Ellerton match ID
  final url = Uri.parse('https://soccer.highlightly.net/football/matches/1288771353');
  
  print('Pinging $url...');
  final request = await HttpClient().getUrl(url);
  request.headers.add('x-rapidapi-key', apiKey);
  request.headers.add('x-rapidapi-host', 'soccer.highlightly.net');
  
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  
  print('Status: ${response.statusCode}');
  print('Response: $responseBody');
  exit(0);
}
