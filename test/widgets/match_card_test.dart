import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/match_card.dart';
import 'package:sports_app/models/match.dart' as model;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import '../helpers/test_helpers.dart';

class MockFavoritesNotifier extends FavoritesNotifier {
  @override
  Set<String> build() => {};

  @override
  Future<void> toggleFavorite(String matchId) async {}
}

void main() {
  Widget buildTestableWidget(Widget child) {
    return ProviderScope(
      overrides: [
        favoritesProvider.overrideWith(() => MockFavoritesNotifier())
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('MatchCard Widget', () {
    testWidgets('renders live match correctly', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          status: model.MatchStatus.live,
          homeScore: '2',
          awayScore: '1',
          liveMinute: "45'",
        );

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('2'), findsWidgets);
        expect(find.text('1'), findsWidgets);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text("45'"), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsOneWidget);
      });
    });

    testWidgets('renders finished match correctly',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(status: model.MatchStatus.finished);

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('Full\nTime'), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsOneWidget);
      });
    });

    testWidgets('renders upcoming match correctly with time and VS tag',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          status: model.MatchStatus.upcoming,
          startTime: DateTime(2026, 3, 20, 20, 30),
        );

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('VS'), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsOneWidget);
        expect(find.text('LIVE'), findsNothing);
      });
    });

    testWidgets('renders reason and secondary labels when provided',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          status: model.MatchStatus.live,
          homeScore: '2',
          awayScore: '1',
          liveMinute: "67'",
        );

        await tester.pumpWidget(
          buildTestableWidget(
            MatchCard(
              match: match,
              hasBorder: false,
              reasonLabel: 'Favori',
              secondaryLabel: '1 fark',
            ),
          ),
        );

        expect(find.text('Favori'), findsOneWidget);
        expect(find.text('1 fark'), findsOneWidget);
      });
    });

    testWidgets('shows highlighted team and league context during search',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          leagueName: 'Premier Arsenal League',
          status: model.MatchStatus.upcoming,
        );

        await tester.pumpWidget(
          buildTestableWidget(
            MatchCard(
              match: match,
              hasBorder: false,
              highlightQuery: 'Arsenal',
            ),
          ),
        );

        expect(find.text('Arsenal'), findsWidgets);
        expect(find.text('Premier Arsenal League'), findsOneWidget);
        expect(find.text('Takim: '), findsOneWidget);
        expect(find.text('Lig: '), findsOneWidget);
        expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
        expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
      });
    });
  });
}
