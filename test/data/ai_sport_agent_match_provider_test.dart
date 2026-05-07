import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sports_app/data/providers/ai_sport_agent_match_provider.dart';
import 'package:sports_app/models/match.dart';

void main() {
  group('AiSportAgentMatchProvider', () {
    test('fetches and maps mobile matches payload', () async {
      Uri? requestedUri;
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1/',
        enableRealtime: false,
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            '''
{
  "matches": [
    {
      "id": "match-1",
      "kickoff_at": "2026-04-30T17:00:00Z",
      "status": "scheduled",
      "home_score": null,
      "away_score": null,
      "current_minute": null,
      "league": {
        "id": "league-1",
        "name": "Super Lig",
        "slug": "super-lig",
        "country_name": "Turkey",
        "country_code": "TR",
        "logo_url": null
      },
      "home_team": {
        "id": "team-1",
        "name": "Galatasaray",
        "slug": "galatasaray",
        "short_name": "GS",
        "logo_url": null
      },
      "away_team": {
        "id": "team-2",
        "name": "Fenerbahce",
        "slug": "fenerbahce",
        "short_name": "FB",
        "logo_url": "https://example.com/fb.png"
      },
      "lineup_status": null,
      "source_confidence": 0.98
    }
  ],
  "sync_status": "fresh",
  "sync_job_id": null,
  "sync_job_run_id": null,
  "stale": false
}
''',
            200,
          );
        }),
      );

      final matches = await provider.getMatches();

      expect(requestedUri?.path, '/api/v1/mobile/matches/live');
      expect(requestedUri?.queryParameters['tz'], 'Europe/Istanbul');
      expect(requestedUri?.queryParameters['limit'], '1000');
      expect(matches, hasLength(1));

      final match = matches.single;
      expect(match.id, 'match-1');
      expect(match.leagueId, 'league-1');
      expect(match.leagueName, 'Super Lig');
      expect(match.homeTeam, 'Galatasaray');
      expect(match.awayTeam, 'Fenerbahce');
      expect(match.status, MatchStatus.upcoming);
      expect(match.homeLogo, contains('Globe.png'));
      expect(match.awayLogo, 'https://example.com/fb.png');
      expect(match.homeScore, isNull);
      expect(match.awayScore, isNull);
      expect(match.liveMinute, isNull);
    });

    test('maps live and finished statuses with scores', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
        enableRealtime: false,
        client: MockClient((request) async {
          return http.Response(
            '''
[
  {
    "id": "live-match",
    "kickoff_at": "2026-04-30T17:00:00Z",
    "status": "live",
    "home_score": 1,
    "away_score": 0,
    "current_minute": 64,
    "league": null,
    "home_team": {"name": "Home"},
    "away_team": {"name": "Away"},
    "source_confidence": 1.0
  },
  {
    "id": "finished-match",
    "kickoff_at": "2026-04-30T19:00:00Z",
    "status": "finished",
    "homeScore": 2,
    "awayScore": 1,
    "currentMinute": null,
    "league": null,
    "home_team": {"name": "Home 2"},
    "away_team": {"name": "Away 2"},
    "source_confidence": 1.0
  }
]
''',
            200,
          );
        }),
      );

      final matches = await provider.getMatches();

      expect(matches[0].status, MatchStatus.live);
      expect(matches[1].status, MatchStatus.finished);
      expect(matches[0].leagueId, 'unknown_league');
      expect(matches[0].homeScore, '1');
      expect(matches[0].awayScore, '0');
      expect(matches[0].liveMinute, '64');
      expect(matches[1].homeScore, '2');
      expect(matches[1].awayScore, '1');
      expect(matches[1].liveMinute, isNull);
    });

    test('maps postponed and cancelled statuses', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
        enableRealtime: false,
        client: MockClient((request) async {
          return http.Response(
            '''
[
  {
    "id": "postponed-match",
    "kickoff_at": "2026-04-30T17:00:00Z",
    "status": "postponed",
    "league": null,
    "home_team": {"name": "Home"},
    "away_team": {"name": "Away"}
  },
  {
    "id": "cancelled-match",
    "kickoff_at": "2026-04-30T19:00:00Z",
    "status": "cancelled",
    "league": null,
    "home_team": {"name": "Home 2"},
    "away_team": {"name": "Away 2"}
  }
]
''',
            200,
          );
        }),
      );

      final matches = await provider.getMatches();

      expect(matches[0].status, MatchStatus.postponed);
      expect(matches[1].status, MatchStatus.cancelled);
    });

    test('rewrites SofaScore logo urls to the backend logo proxy', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
        enableRealtime: false,
        client: MockClient((request) async {
          return http.Response(
            '''
{
  "matches": [
    {
      "id": "match-1",
      "kickoff_at": "2026-04-30T17:00:00Z",
      "status": "scheduled",
      "league": {
        "id": "league-1",
        "name": "Super Lig",
        "logo_url": "https://img.sofascore.com/api/v1/unique-tournament/52/image"
      },
      "home_team": {
        "name": "Galatasaray",
        "logo_url": "https://img.sofascore.com/api/v1/team/3061/image"
      },
      "away_team": {
        "name": "Fenerbahce",
        "logo_url": "https://example.com/fb.png"
      }
    }
  ]
}
''',
            200,
          );
        }),
      );

      final match = (await provider.getMatches()).single;

      expect(
        match.leagueLogoUrl,
        'http://agent.test/api/v1/mobile/logos/unique-tournament/52?label=Super+Lig&v=2',
      );
      expect(
        match.homeLogo,
        'http://agent.test/api/v1/mobile/logos/team/3061?label=Galatasaray&v=2',
      );
      expect(match.awayLogo, 'https://example.com/fb.png');
    });

    test('stream emits an error when backend is unavailable', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
        enableRealtime: false,
        client: MockClient((request) async {
          return http.Response('service unavailable', 503);
        }),
      );

      expect(
        provider.getMatchesStream(DateTime(2026, 4, 30)),
        emitsError(isA<Exception>()),
      );
    });
  });
}
