import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/screens/home_dashboard.dart';
import 'package:sports_app/models/match.dart' as model;
import 'package:sports_app/providers/match_provider.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import 'package:sports_app/providers/notification_provider.dart';
import 'package:sports_app/models/notification.dart';
import 'package:sports_app/theme/app_theme.dart';
import '../helpers/mock_match_repository.dart';
import '../helpers/test_helpers.dart';

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
  Set<String> build() => {'3'};
  
  @override
  Future<void> toggleFavorite(String matchId) async {}
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
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: HomeDashboard(initialDateOverride: overrideDate),
        ),
      );
    }

    testWidgets('Dashboard renders live matches and filters correctly', (WidgetTester tester) async {
      final today = DateTime.now();
      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(id: '1', homeTeam: 'Arsenal', awayTeam: 'Spurs', status: model.MatchStatus.live, startTime: today),
          createTestMatch(id: '2', homeTeam: 'Chelsea', awayTeam: 'Liverpool', status: model.MatchStatus.finished, startTime: today),
          createTestMatch(id: '3', homeTeam: 'Real Madrid', awayTeam: 'Barcelona', status: model.MatchStatus.upcoming, isFavorite: true, startTime: today),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('Real Madrid'), findsOneWidget);
        
        await tester.tap(find.text('Canlı'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsNothing);
        expect(find.text('Real Madrid'), findsNothing);
        
        // Disable "Canlı" toggle to go back to ALL
        await tester.tap(find.text('Canlı'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.ensureVisible(find.text('Favoriler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Favoriler'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        
        expect(find.text('Real Madrid'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);
        expect(find.text('Chelsea'), findsNothing);
      });
    });

    testWidgets('Dashboard displays empty state when no matches pass filter', (WidgetTester tester) async {
      final today = DateTime.now();
      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(status: model.MatchStatus.upcoming, startTime: today),
          createTestMatch(status: model.MatchStatus.finished, startTime: today),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.tap(find.text('Canlı'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('No matches available for this filter'), findsOneWidget);
      });
    });

    testWidgets('Dashboard Date Navigator filters by selected day', (WidgetTester tester) async {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      
      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(id: '1', homeTeam: 'TodayTeam', awayTeam: 'A', status: model.MatchStatus.upcoming, startTime: today),
          createTestMatch(id: '2', homeTeam: 'TomorrowTeam', awayTeam: 'B', status: model.MatchStatus.upcoming, startTime: tomorrow),
        ]);

        await tester.pumpWidget(buildTestableWidget(overrideDate: today));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Initially defaults to today
        expect(find.text('TodayTeam'), findsOneWidget);
        expect(find.text('TomorrowTeam'), findsNothing);

        // UI Calendar was refactored into a bottom-nav overlay
        // We simulate the date change by pushing state natively into the provider just like the overlay does.
        final element = tester.element(find.byType(HomeDashboard));
        final container = ProviderScope.containerOf(element);
        container.read(matchStateProvider.notifier).setDate(tomorrow);
        
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        // Should now show tomorrow's matches
        expect(find.text('TodayTeam'), findsNothing);
        expect(find.text('TomorrowTeam'), findsOneWidget);
      });
    });
  });
}
