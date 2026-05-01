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

    test('maps live and finished statuses', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
        client: MockClient((request) async {
          return http.Response(
            '''
[
  {
    "id": "live-match",
    "kickoff_at": "2026-04-30T17:00:00Z",
    "status": "live",
    "league": null,
    "home_team": {"name": "Home"},
    "away_team": {"name": "Away"},
    "source_confidence": 1.0
  },
  {
    "id": "finished-match",
    "kickoff_at": "2026-04-30T19:00:00Z",
    "status": "finished",
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
    });

    test('stream emits an error when backend is unavailable', () async {
      final provider = AiSportAgentMatchProvider(
        baseUrl: 'http://agent.test/api/v1',
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
