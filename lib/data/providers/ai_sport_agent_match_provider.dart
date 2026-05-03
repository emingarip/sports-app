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
    final leagueName = league?['name']?.toString();
    final homeTeamName = homeTeam?['name']?.toString() ?? 'Unknown';
    final awayTeamName = awayTeam?['name']?.toString() ?? 'Unknown';

    return model.Match(
      id: data['id']?.toString() ?? '',
      leagueId: league?['id']?.toString() ?? 'unknown_league',
      leagueName: leagueName,
      leagueLogoUrl: _logoUrlFromPayload(
        league?['logo_url'],
        label: leagueName,
      ),
      homeTeam: homeTeamName,
      awayTeam: awayTeamName,
      homeLogo: _requiredLogoUrl(
        homeTeam?['logo_url'],
        label: homeTeamName,
      ),
      awayLogo: _requiredLogoUrl(
        awayTeam?['logo_url'],
        label: awayTeamName,
      ),
      startTime: DateTime.parse(data['kickoff_at'] as String),
      status: _mapStatus(data['status']?.toString()),
    );
  }

  String _requiredLogoUrl(Object? value, {String? label}) {
    return _logoUrlFromPayload(value, label: label) ?? _fallbackLogoUrl;
  }

  String? _logoUrlFromPayload(Object? value, {String? label}) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _rewriteSofascoreLogoUrl(raw, label: label) ?? raw;
  }

  String? _rewriteSofascoreLogoUrl(String raw, {String? label}) {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final isSofascoreHost =
        host.endsWith('sofascore.com') || host.endsWith('sofascore.app');
    if (!isSofascoreHost) {
      return null;
    }

    final pathSegments = uri.pathSegments;
    final apiIndex = pathSegments.indexOf('api');
    final hasLogoShape = apiIndex >= 0 &&
        pathSegments.length >= apiIndex + 5 &&
        pathSegments[apiIndex + 1] == 'v1' &&
        pathSegments[apiIndex + 4] == 'image';
    if (!hasLogoShape) {
      return null;
    }

    final kind = pathSegments[apiIndex + 2];
    final providerId = pathSegments[apiIndex + 3];
    final proxyPath = _logoProxyPath(kind, providerId);
    if (proxyPath == null) {
      return null;
    }

    final logoUri = Uri.parse('$_baseUrl$proxyPath');
    final normalizedLabel = label?.trim();
    if (normalizedLabel == null || normalizedLabel.isEmpty) {
      return logoUri.toString();
    }
    return logoUri.replace(
      queryParameters: {'label': normalizedLabel},
    ).toString();
  }

  static String? _logoProxyPath(String kind, String providerId) {
    final normalizedKind = switch (kind) {
      'team' => 'team',
      'tournament' => 'tournament',
      'unique-tournament' => 'unique-tournament',
      _ => null,
    };
    if (normalizedKind == null || providerId.trim().isEmpty) {
      return null;
    }
    return '/mobile/logos/$normalizedKind/$providerId';
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
