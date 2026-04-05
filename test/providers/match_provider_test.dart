import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/models/match.dart';
import 'package:sports_app/models/match_list_view_model.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import 'package:sports_app/providers/match_provider.dart';

import '../helpers/mock_match_repository.dart';
import '../helpers/test_helpers.dart';

class TestFavoritesNotifier extends FavoritesNotifier {
  TestFavoritesNotifier(this._favorites);

  final Set<String> _favorites;

  @override
  Set<String> build() => _favorites;

  @override
  Future<void> toggleFavorite(String matchId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('match_provider v1 shaping', () {
    late MockMatchRepository mockRepository;

    setUp(() {
      mockRepository = MockMatchRepository();
    });

    ProviderContainer buildContainer({Set<String> favorites = const {}}) {
      return ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepository),
          favoritesProvider.overrideWith(
            () => TestFavoritesNotifier(favorites),
          ),
        ],
      );
    }

    test('getMatchPriorityBucket applies the v1 priority order', () {
      final now = DateTime(2026, 4, 5, 18, 0);

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'favorite-live',
            status: MatchStatus.live,
            liveMinute: "84'",
          ),
          favorites: const {'favorite-live'},
          now: now,
        ),
        MatchPriorityBucket.favoriteLive,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'critical-live',
            status: MatchStatus.live,
            homeScore: '1',
            awayScore: '1',
            liveMinute: "72'",
          ),
          favorites: const {},
          now: now,
        ),
        MatchPriorityBucket.liveCritical,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'other-live',
            status: MatchStatus.live,
            homeScore: '3',
            awayScore: '0',
            liveMinute: "28'",
          ),
          favorites: const {},
          now: now,
        ),
        MatchPriorityBucket.liveOther,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'favorite-soon',
            status: MatchStatus.upcoming,
            startTime: now.add(const Duration(minutes: 50)),
          ),
          favorites: const {'favorite-soon'},
          now: now,
        ),
        MatchPriorityBucket.favoriteStartingSoon,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'soon',
            status: MatchStatus.upcoming,
            startTime: now.add(const Duration(minutes: 90)),
          ),
          favorites: const {},
          now: now,
        ),
        MatchPriorityBucket.startingSoon,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'favorite-later',
            status: MatchStatus.upcoming,
            startTime: now.add(const Duration(hours: 4)),
          ),
          favorites: const {'favorite-later'},
          now: now,
        ),
        MatchPriorityBucket.favoriteLaterToday,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'later',
            status: MatchStatus.upcoming,
            startTime: now.add(const Duration(hours: 5)),
          ),
          favorites: const {},
          now: now,
        ),
        MatchPriorityBucket.laterToday,
      );

      expect(
        getMatchPriorityBucket(
          createTestMatch(
            id: 'finished',
            status: MatchStatus.finished,
            startTime: now.subtract(const Duration(hours: 1)),
          ),
          favorites: const {},
          now: now,
        ),
        MatchPriorityBucket.finished,
      );
    });

    test('providers split featured, live, soon and grouped other sections',
        () async {
      final now = DateTime.now();

      mockRepository.setMatches([
        createTestMatch(
          id: 'fav-live',
          leagueId: 'league-live',
          leagueName: 'League Live',
          status: MatchStatus.live,
          homeScore: '2',
          awayScore: '1',
          liveMinute: "88'",
          startTime: now.subtract(const Duration(hours: 2)),
        ),
        createTestMatch(
          id: 'critical-live',
          leagueId: 'league-live',
          leagueName: 'League Live',
          status: MatchStatus.live,
          homeScore: '1',
          awayScore: '1',
          liveMinute: "76'",
          startTime: now.subtract(const Duration(hours: 1)),
        ),
        createTestMatch(
          id: 'live-other-1',
          leagueId: 'league-live',
          leagueName: 'League Live',
          status: MatchStatus.live,
          homeScore: '3',
          awayScore: '0',
          liveMinute: "60'",
          startTime: now.subtract(const Duration(minutes: 50)),
        ),
        createTestMatch(
          id: 'live-other-2',
          leagueId: 'league-live',
          leagueName: 'League Live',
          status: MatchStatus.live,
          homeScore: '4',
          awayScore: '1',
          liveMinute: "20'",
          startTime: now.subtract(const Duration(minutes: 30)),
        ),
        createTestMatch(
          id: 'soon',
          leagueId: 'league-soon',
          leagueName: 'League Soon',
          status: MatchStatus.upcoming,
          startTime: now.add(const Duration(minutes: 45)),
        ),
        createTestMatch(
          id: 'later',
          leagueId: 'league-later',
          leagueName: 'League Later',
          status: MatchStatus.upcoming,
          startTime: now.add(const Duration(hours: 5)),
        ),
        createTestMatch(
          id: 'finished',
          leagueId: 'league-later',
          leagueName: 'League Later',
          status: MatchStatus.finished,
          startTime: now.subtract(const Duration(hours: 3)),
        ),
      ]);

      final container = buildContainer(favorites: const {'fav-live'});
      addTearDown(container.dispose);

      container.read(matchStateProvider);
      await Future<void>.delayed(Duration.zero);

      final featured = container.read(featuredMatchItemsProvider);
      expect(
        featured.map((item) => item.match.id).toList(),
        ['fav-live', 'critical-live', 'live-other-1'],
      );
      expect(featured.first.reasonLabel, 'Favori');
      expect(featured.last.reasonLabel, isNotNull);

      final liveNow = container.read(liveNowSectionProvider);
      expect(liveNow, isNotNull);
      expect(liveNow!.items.map((item) => item.match.id).toList(), [
        'live-other-2',
      ]);

      final startingSoon = container.read(startingSoonSectionProvider);
      expect(startingSoon, isNotNull);
      expect(
        startingSoon!.items.map((item) => item.match.id).toList(),
        ['soon'],
      );
      expect(startingSoon.items.single.reasonLabel, 'Yakinda basliyor');

      final otherMatches = container.read(otherMatchesSectionProvider);
      expect(otherMatches, isNotNull);
      expect(
        otherMatches!.items.map((item) => item.match.id).toList(),
        ['later', 'finished'],
      );

      final leagueSections = container.read(leagueMatchSectionsProvider);
      expect(leagueSections.map((section) => section.league.id).toList(), [
        'league-later',
      ]);
      expect(
        leagueSections.single.items.map((item) => item.match.id).toList(),
        ['later', 'finished'],
      );
    });

    test('search ranking prefers exact matches and merge removes duplicates',
        () {
      final exactTeam = createTestMatch(
        id: 'exact-team',
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        leagueName: 'Premier League',
      );
      final teamPrefix = createTestMatch(
        id: 'team-prefix',
        homeTeam: 'Arsenal Tula',
        awayTeam: 'Zenit',
        leagueName: 'Russian League',
      );
      final substring = createTestMatch(
        id: 'substring',
        homeTeam: 'Brighton',
        awayTeam: 'Burnley',
        leagueName: 'Arsenal Legends Cup',
      );

      final ranked = rankMatchSearchResults(
        matches: [substring, teamPrefix, exactTeam],
        query: 'Arsenal',
      );

      expect(ranked.map((result) => result.match.id).toList(), [
        'exact-team',
        'team-prefix',
        'substring',
      ]);

      final localResults = rankMatchSearchResults(
        matches: [exactTeam, substring],
        query: 'Arsenal',
      );
      final backendResults = rankMatchSearchResults(
        matches: [teamPrefix, exactTeam],
        query: 'Arsenal',
      );
      final merged = mergeRankedSearchResults(localResults, backendResults);

      expect(merged.map((result) => result.match.id).toList(), [
        'exact-team',
        'team-prefix',
        'substring',
      ]);
    });

    test('inline list search ranks matches inside the current feed scope',
        () async {
      final now = DateTime.now();

      mockRepository.setMatches([
        createTestMatch(
          id: 'arsenal-exact',
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          leagueName: 'Premier League',
          status: MatchStatus.upcoming,
          startTime: now.add(const Duration(hours: 1)),
        ),
        createTestMatch(
          id: 'arsenal-prefix',
          homeTeam: 'Arsenal Tula',
          awayTeam: 'Zenit',
          leagueName: 'Russian League',
          status: MatchStatus.upcoming,
          startTime: now.add(const Duration(hours: 2)),
        ),
        createTestMatch(
          id: 'arsenal-substring',
          homeTeam: 'Brighton',
          awayTeam: 'Burnley',
          leagueName: 'Arsenal Legends Cup',
          status: MatchStatus.upcoming,
          startTime: now.add(const Duration(hours: 3)),
        ),
      ]);

      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(matchStateProvider);
      await Future<void>.delayed(Duration.zero);

      container.read(matchStateProvider.notifier).openInlineSearch();
      container
          .read(matchStateProvider.notifier)
          .setInlineSearchQuery('Arsenal');

      final items = container.read(matchListItemsProvider);
      expect(items.map((item) => item.match.id).toList(), [
        'arsenal-exact',
        'arsenal-prefix',
        'arsenal-substring',
      ]);
    });
  });
}
