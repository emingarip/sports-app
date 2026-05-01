import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/match.dart' as model;
import '../repositories/match_repository.dart';

const String _fallbackLogoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png';

class AiSportAgentMatchProvider implements MatchRepository {
  AiSportAgentMatchProvider({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  final http.Client _client;
  final String _baseUrl;
  final StreamController<List<model.Match>> _controller =
      StreamController<List<model.Match>>.broadcast();

  DateTime? _activeDate;
  List<model.Match> _lastMatches = const [];

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

  @override
  Future<List<model.Match>> getMatches() {
    return _fetchMatches(DateTime.now());
  }

  @override
  Stream<List<model.Match>> getMatchesStream(DateTime date) {
    _activeDate = date;
    Future<void>.microtask(() async {
      await fetchMatchesForDate(date);
    });
    return _controller.stream;
  }

  @override
  Future<void> fetchMatchesForDate(DateTime date) async {
    try {
      final matches = await _fetchMatches(date);
      if (_isSameCalendarDay(_activeDate ?? date, date)) {
        _lastMatches = matches;
        _controller.add(matches);
      }
    } catch (error, stackTrace) {
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
    }
  }

  @override
  Future<List<model.Match>> searchMatches(String query) async {
    final normalized = query.trim().toLowerCase();
    final source = _lastMatches.isNotEmpty ? _lastMatches : await getMatches();
    if (normalized.isEmpty) {
      return source;
    }
    return source.where((match) {
      return match.homeTeam.toLowerCase().contains(normalized) ||
          match.awayTeam.toLowerCase().contains(normalized) ||
          (match.leagueName?.toLowerCase().contains(normalized) ?? false);
    }).toList();
  }

  Future<List<model.Match>> _fetchMatches(DateTime date) async {
    final uri = Uri.parse('$_baseUrl/mobile/matches/live').replace(
      queryParameters: {
        'date': _formatDate(date),
        'tz': 'Europe/Istanbul',
        'limit': '1000',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'AI Sport Agent matches request failed: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    final rawMatches = switch (decoded) {
      {'matches': final List matches} => matches,
      final List matches => matches,
      _ => null,
    };
    if (rawMatches == null) {
      throw const FormatException(
          'AI Sport Agent matches payload does not contain a matches list.');
    }
    return rawMatches.whereType<Map<String, dynamic>>().map(_mapMatch).toList();
  }

  model.Match _mapMatch(Map<String, dynamic> data) {
    final league = data['league'] as Map<String, dynamic>?;
    final homeTeam = data['home_team'] as Map<String, dynamic>?;
    final awayTeam = data['away_team'] as Map<String, dynamic>?;

    return model.Match(
      id: data['id']?.toString() ?? '',
      leagueId: league?['id']?.toString() ?? 'unknown_league',
      leagueName: league?['name']?.toString(),
      leagueLogoUrl: league?['logo_url']?.toString(),
      homeTeam: homeTeam?['name']?.toString() ?? 'Unknown',
      awayTeam: awayTeam?['name']?.toString() ?? 'Unknown',
      homeLogo: homeTeam?['logo_url']?.toString() ?? _fallbackLogoUrl,
      awayLogo: awayTeam?['logo_url']?.toString() ?? _fallbackLogoUrl,
      startTime: DateTime.parse(data['kickoff_at'] as String),
      status: _mapStatus(data['status']?.toString()),
    );
  }

  model.MatchStatus _mapStatus(String? status) {
    switch (status) {
      case 'live':
        return model.MatchStatus.live;
      case 'finished':
        return model.MatchStatus.finished;
      default:
        return model.MatchStatus.upcoming;
    }
  }

  static String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final year = localDate.year.toString().padLeft(4, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.endsWith('/api/v1')) {
      return normalized;
    }
    return '$normalized/api/v1';
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
