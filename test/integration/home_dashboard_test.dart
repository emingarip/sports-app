import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:sports_app/models/match.dart' as model;
import 'package:sports_app/models/notification.dart';
import 'package:sports_app/providers/badge_provider.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import 'package:sports_app/providers/knowledge_graph_provider.dart';
import 'package:sports_app/providers/match_provider.dart';
import 'package:sports_app/providers/notification_provider.dart';
import 'package:sports_app/screens/home_dashboard.dart';
import 'package:sports_app/services/announcement_service.dart';
import 'package:sports_app/theme/app_theme.dart';

import '../helpers/mock_match_repository.dart';
import '../helpers/test_helpers.dart';

class MockAnnouncementNotifier extends AnnouncementNotifier {
  @override
  AnnouncementState build() {
    return AnnouncementState(
      activeAnnouncements: [],
      dismissedIds: [],
      isLoading: false,
    );
  }
}

class MockNotificationNotifier extends NotificationNotifier {
  @override
  List<AppNotification> build() => [];

  @override
  Future<void> markAsRead(String id) async {}

  @override
  Future<void> markAllAsRead() async {}
}

class MockFavoritesNotifier extends FavoritesNotifier {
  @override
  Set<String> build() => {'4'};

  @override
  Future<void> toggleFavorite(String matchId) async {}
}

class MockBadgeNotifier extends BadgeNotifier {
  @override
  BadgeState build() => const BadgeState(isLoading: false);

  @override
  Future<void> recordLogin() async {}

  @override
  Future<void> refresh() async {}
}

void main() {
  group('HomeDashboard Integration Tests', () {
    late MockMatchRepository mockRepository;

    setUp(() {
      mockRepository = MockMatchRepository();
    });

    Widget buildTestableWidget({DateTime? overrideDate}) {
      return ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepository),
          favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
          notificationProvider.overrideWith(() => MockNotificationNotifier()),
          announcementProvider.overrideWith(() => MockAnnouncementNotifier()),
          personalizedMatchesProvider.overrideWith((ref) => <model.Match>[]),
          badgeProvider.overrideWith(() => MockBadgeNotifier()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeDashboard(initialDateOverride: overrideDate),
        ),
      );
    }

    testWidgets('dashboard renders smart sections and filters correctly',
        (WidgetTester tester) async {
      final today = DateTime.now();

      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(
            id: '1',
            homeTeam: 'Arsenal',
            awayTeam: 'Spurs',
            leagueId: 'league-live',
            leagueName: 'League Live',
            status: model.MatchStatus.live,
            homeScore: '1',
            awayScore: '1',
            liveMinute: "82'",
            startTime: today.subtract(const Duration(hours: 2)),
          ),
          createTestMatch(
            id: '2',
            homeTeam: 'Chelsea',
            awayTeam: 'Liverpool',
            leagueId: 'league-live',
            leagueName: 'League Live',
            status: model.MatchStatus.live,
            homeScore: '3',
            awayScore: '1',
            liveMinute: "64'",
            startTime: today.subtract(const Duration(hours: 1)),
          ),
          createTestMatch(
            id: '3',
            homeTeam: 'Inter',
            awayTeam: 'Juventus',
            leagueId: 'league-live',
            leagueName: 'League Live',
            status: model.MatchStatus.live,
            homeScore: '2',
            awayScore: '0',
            liveMinute: "44'",
            startTime: today.subtract(const Duration(minutes: 50)),
          ),
          createTestMatch(
            id: '7',
            homeTeam: 'Dortmund',
            awayTeam: 'Leipzig',
            leagueId: 'league-live',
            leagueName: 'League Live',
            status: model.MatchStatus.live,
            homeScore: '4',
            awayScore: '0',
            liveMinute: "18'",
            startTime: today.subtract(const Duration(minutes: 35)),
          ),
          createTestMatch(
            id: '4',
            homeTeam: 'Real Madrid',
            awayTeam: 'Barcelona',
            leagueId: 'league-soon',
            leagueName: 'League Soon',
            status: model.MatchStatus.upcoming,
            startTime: today.add(const Duration(minutes: 40)),
          ),
          createTestMatch(
            id: '5',
            homeTeam: 'Milan',
            awayTeam: 'Roma',
            leagueId: 'league-later',
            leagueName: 'League Later',
            status: model.MatchStatus.upcoming,
            startTime: today.add(const Duration(hours: 5)),
          ),
          createTestMatch(
            id: '6',
            homeTeam: 'PSG',
            awayTeam: 'Marseille',
            leagueId: 'league-later',
            leagueName: 'League Later',
            status: model.MatchStatus.finished,
            startTime: today.subtract(const Duration(hours: 3)),
          ),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));

        expect(find.text('One Cikanlar'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('inline-search-toggle')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('inline-search-toggle')));
        await tester.pumpAndSettle();

        expect(
            find.byKey(const ValueKey('inline-search-field')), findsOneWidget);
        expect(find.text('Mac ara'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Real');
        await tester.pumpAndSettle();

        expect(find.text('Arama Sonuclari'), findsOneWidget);
        expect(find.text('Real Madrid'), findsWidgets);
        expect(find.text('Lig: '), findsOneWidget);
        expect(find.text('Takim: '), findsNothing);
        expect(find.text('Arsenal'), findsNothing);

        await tester.tap(find.byTooltip('Aramayi kapat'));
        await tester.pumpAndSettle();

        expect(find.text('One Cikanlar'), findsOneWidget);

        await tester.tap(find.text('Canli'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Real Madrid'), findsNothing);

        await tester.tap(find.text('Canli'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.text('Favoriler'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Real Madrid'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);
      });
    });

    testWidgets('dashboard displays empty state when no matches pass filter',
        (WidgetTester tester) async {
      final today = DateTime.now();

      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(status: model.MatchStatus.upcoming, startTime: today),
          createTestMatch(status: model.MatchStatus.finished, startTime: today),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.tap(find.text('Canli'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Su anda canli mac yok'), findsOneWidget);
      });
    });

    testWidgets('dashboard date navigator filters by selected day',
        (WidgetTester tester) async {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(
            id: '1',
            homeTeam: 'TodayTeam',
            awayTeam: 'A',
            status: model.MatchStatus.upcoming,
            startTime: today,
          ),
          createTestMatch(
            id: '2',
            homeTeam: 'TomorrowTeam',
            awayTeam: 'B',
            status: model.MatchStatus.upcoming,
            startTime: tomorrow,
          ),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('TodayTeam'), findsOneWidget);
        expect(find.text('TomorrowTeam'), findsNothing);

        final element = tester.element(find.byType(HomeDashboard));
        final container = ProviderScope.containerOf(element);
        await tester.runAsync(
          () => container.read(matchStateProvider.notifier).setDate(tomorrow),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump();

        expect(find.text('TodayTeam'), findsNothing);
        expect(find.text('TomorrowTeam'), findsOneWidget);
      });
    });
  });
}
