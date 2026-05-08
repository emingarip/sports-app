import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/match.dart' as model;
import '../repositories/match_repository.dart';

const String _fallbackLogoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png';

class AiSportAgentMatchProvider implements MatchRepository {
  AiSportAgentMatchProvider({
    http.Client? client,
    String? baseUrl,
    bool enableRealtime = _defaultEnableRealtime,
  })  : _client = client ?? http.Client(),
        _enableRealtime = enableRealtime,
        _baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  final http.Client _client;
  final bool _enableRealtime;
  final String _baseUrl;
  final StreamController<List<model.Match>> _controller =
      StreamController<List<model.Match>>.broadcast();

  DateTime? _activeDate;
  List<model.Match> _lastMatches = const [];
  WebSocketChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _realtimeSubscription;
  Timer? _reconnectTimer;
  bool _realtimePaused = false;

  static const String _configuredBaseUrl = String.fromEnvironment(
    'AI_SPORT_AGENT_BASE_URL',
  );
  static const bool _defaultEnableRealtime = bool.fromEnvironment(
    'AI_SPORT_AGENT_ENABLE_REALTIME',
    defaultValue: true,
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
    _connectRealtime(date);
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
  void pauseRealtime() {
    _realtimePaused = true;
    _closeRealtime();
  }

  @override
  void resumeRealtime() {
    _realtimePaused = false;
    final date = _activeDate;
    if (date != null) {
      _connectRealtime(date);
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
    return rawMatches
        .whereType<Map>()
        .map((data) => _mapMatch(Map<String, dynamic>.from(data)))
        .toList();
  }

  void _connectRealtime(DateTime date) {
    if (!_enableRealtime || _realtimePaused) {
      return;
    }
    _closeRealtime();

    final uri = _webSocketUri(date);
    try {
      final channel = WebSocketChannel.connect(uri);
      _realtimeChannel = channel;
      _realtimeSubscription = channel.stream.listen(
        _handleRealtimeMessage,
        onError: (_) => _scheduleRealtimeReconnect(),
        onDone: _scheduleRealtimeReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRealtimeReconnect();
    }
  }

  Uri _webSocketUri(DateTime date) {
    final baseUri = Uri.parse(_baseUrl);
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final path =
        '${baseUri.path.replaceFirst(RegExp(r'/+$'), '')}/mobile/matches/ws';
    return baseUri.replace(
      scheme: scheme,
      path: path,
      queryParameters: {
        'date': _formatDate(date),
        'tz': 'Europe/Istanbul',
      },
    );
  }

  void _handleRealtimeMessage(dynamic message) {
    final decoded = switch (message) {
      final String text => jsonDecode(text),
      final List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ => null,
    };
    if (decoded is! Map) {
      return;
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['type'] != 'match_updated') {
      return;
    }
    final rawMatch = payload['match'];
    if (rawMatch is! Map) {
      return;
    }
    final matchPayload = Map<String, dynamic>.from(rawMatch);
    final matchId = matchPayload['id']?.toString();
    if (matchId == null || matchId.isEmpty) {
      return;
    }
    if (!_lastMatches.any((match) => match.id == matchId)) {
      return;
    }
    final updatedMatches = _lastMatches
        .map(
          (match) => match.id == matchId
              ? _mergeRealtimeMatch(match, matchPayload)
              : match,
        )
        .toList();
    _lastMatches = updatedMatches;
    if (!_controller.isClosed) {
      _controller.add(updatedMatches);
    }
  }

  model.Match _mergeRealtimeMatch(
    model.Match current,
    Map<String, dynamic> data,
  ) {
    return model.Match(
      id: current.id,
      leagueId: current.leagueId,
      leagueName: current.leagueName,
      leagueLogoUrl: current.leagueLogoUrl,
      homeTeam: current.homeTeam,
      awayTeam: current.awayTeam,
      homeLogo: current.homeLogo,
      awayLogo: current.awayLogo,
      startTime: current.startTime,
      status: _mapStatus(data['status']?.toString()),
      homeScore: _scoreFromPayload(data, 'home_score', 'homeScore') ??
          current.homeScore,
      awayScore: _scoreFromPayload(data, 'away_score', 'awayScore') ??
          current.awayScore,
      liveMinute: _scoreFromPayload(data, 'current_minute', 'currentMinute') ??
          current.liveMinute,
      isFeatured: current.isFeatured,
      isFavorite: current.isFavorite,
    );
  }

  void _scheduleRealtimeReconnect() {
    if (!_enableRealtime || _realtimePaused || _activeDate == null) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      final date = _activeDate;
      if (date != null) {
        _connectRealtime(date);
      }
    });
  }

  void _closeRealtime() {
    _reconnectTimer?.cancel();
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _realtimeChannel?.sink.close();
    _realtimeChannel = null;
  }

  model.Match _mapMatch(Map<String, dynamic> data) {
    final league = _asStringMap(data['league']);
    final homeTeam = _asStringMap(data['home_team']);
    final awayTeam = _asStringMap(data['away_team']);
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
      startTime: DateTime.parse(data['kickoff_at']?.toString() ?? ''),
      status: _mapStatus(data['status']?.toString()),
      homeScore: _scoreFromPayload(data, 'home_score', 'homeScore'),
      awayScore: _scoreFromPayload(data, 'away_score', 'awayScore'),
      liveMinute: _scoreFromPayload(data, 'current_minute', 'currentMinute'),
    );
  }

  String? _scoreFromPayload(
    Map<String, dynamic> data,
    String snakeCaseKey,
    String camelCaseKey,
  ) {
    final value = data[snakeCaseKey] ?? data[camelCaseKey];
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  Map<String, dynamic>? _asStringMap(Object? value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
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
      return logoUri.replace(queryParameters: {'v': '2'}).toString();
    }
    return logoUri.replace(
      queryParameters: {'label': normalizedLabel, 'v': '2'},
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
      case 'postponed':
        return model.MatchStatus.postponed;
      case 'cancelled':
        return model.MatchStatus.cancelled;
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
