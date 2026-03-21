import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../../lib/screens/home_dashboard.dart';
import '../../lib/models/match.dart' as model;
import '../helpers/mock_match_repository.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('HomeDashboard Integration Tests', () {
    late MockMatchRepository mockRepository;

    setUp(() {
      mockRepository = MockMatchRepository();
    });

    Widget buildTestableWidget() {
      return MaterialApp(
        home: HomeDashboard(repository: mockRepository),
      );
    }

    testWidgets('Dashboard renders live matches and filters correctly', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(id: '1', homeTeam: 'Arsenal', awayTeam: 'Spurs', status: model.MatchStatus.live),
          createTestMatch(id: '2', homeTeam: 'Chelsea', awayTeam: 'Liverpool', status: model.MatchStatus.finished),
          createTestMatch(id: '3', homeTeam: 'Real Madrid', awayTeam: 'Barcelona', status: model.MatchStatus.upcoming, isFavorite: true),
        ]);

        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('Real Madrid'), findsOneWidget);
        
        await tester.tap(find.text('Live 🔴'));
        await tester.pumpAndSettle();
        
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsNothing);
        expect(find.text('Real Madrid'), findsNothing);
        
        await tester.tap(find.text('Starred ⭐'));
        await tester.pumpAndSettle();
        
        expect(find.text('Real Madrid'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);
        expect(find.text('Chelsea'), findsNothing);
      });
    });

    testWidgets('Dashboard displays empty state when no matches pass filter', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        mockRepository.setMatches([
          createTestMatch(status: model.MatchStatus.upcoming),
          createTestMatch(status: model.MatchStatus.finished),
        ]);

        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Live 🔴'));
        await tester.pumpAndSettle();

        expect(find.text('No matches available for this filter'), findsOneWidget);
      });
    });
  });
}
