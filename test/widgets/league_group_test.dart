import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/league_group.dart';
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
          body: CustomScrollView(
            slivers: [child],
          ),
        ),
      ),
    );
  }

  group('LeagueGroup Widget', () {
    testWidgets('renders league header and match count', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague(name: 'Test Super League');
        final matches = [createTestMatch(), createTestMatch()];

        await tester.pumpWidget(buildTestableWidget(
          LeagueGroup(
            league: league,
            matches: matches,
            isExpanded: false,
            onToggle: () {},
          ),
        ));

        expect(find.text('Test Super League'), findsOneWidget);
        expect(find.text('2 Matches'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);
      });
    });

    testWidgets('calls onToggle when header is tapped', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague();
        final matches = [createTestMatch()];
        var toggleCalled = false;

        await tester.pumpWidget(buildTestableWidget(
          LeagueGroup(
            league: league,
            matches: matches,
            isExpanded: false,
            onToggle: () {
              toggleCalled = true;
            },
          ),
        ));

        await tester.tap(find.text('1 Matches'));
        await tester.pump();

        expect(toggleCalled, true);
      });
    });

    testWidgets('renders MatchCards when expanded', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague();
        final matches = [createTestMatch(homeTeam: 'Unique Home Team')];

        await tester.pumpWidget(buildTestableWidget(
          LeagueGroup(
            league: league,
            matches: matches,
            isExpanded: true,
            onToggle: () {},
          ),
        ));

        expect(find.text('Unique Home Team'), findsOneWidget);
      });
    });
  });
}
