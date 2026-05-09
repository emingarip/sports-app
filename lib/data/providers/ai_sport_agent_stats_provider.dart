import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../models/match_stats.dart';

final aiSportAgentStatsProvider = Provider<AiSportAgentStatsProvider>(
  (ref) => AiSportAgentStatsProvider(),
  name: 'aiSportAgentStatsProvider',
);

class AiSportAgentStatsProvider {
  AiSportAgentStatsProvider({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  final http.Client _client;
  final String _baseUrl;

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AI_SPORT_AGENT_BASE_URL',
  );

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return _configuredBaseUrl.trim();
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8001/api/v1';
    }
    return 'http://localhost:8001/api/v1';
  }

  Future<MatchStatsReport> fetchStats(String matchId) async {
    final uri = Uri.parse('$_baseUrl/mobile/matches/$matchId/stats');
    final response = await _client.get(uri);
    if (response.statusCode == 404) {
      throw Exception('Bu mac icin istatistik verisi bulunamadi.');
    }
    if (response.statusCode != 200) {
      throw Exception('Istatistik verisi yuklenemedi: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Istatistik verisi gecersiz.');
    }
    return MatchStatsReport.fromJson(Map<String, dynamic>.from(decoded));
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.endsWith('/api/v1')) {
      return normalized;
    }
    return '$normalized/api/v1';
  }
}
