import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:sports_app/models/match.dart' as model;
import 'package:sports_app/models/match_list_view_model.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/league_group.dart';

import '../helpers/test_helpers.dart';

class MockFavoritesNotifier extends FavoritesNotifier {
  @override
  Set<String> build() => {};

  @override
  Future<void> toggleFavorite(String matchId) async {}
}

MatchListItemViewModel buildItem(
  model.Match match, {
  MatchPriorityBucket bucket = MatchPriorityBucket.liveOther,
  String? reasonLabel,
  String? statusLabel,
  String? secondaryLabel,
}) {
  return MatchListItemViewModel(
    match: match,
    priorityBucket: bucket,
    statusLabel: statusLabel ?? (match.liveMinute ?? '20:00'),
    reasonLabel: reasonLabel,
    secondaryLabel: secondaryLabel,
  );
}

void main() {
  Widget buildTestableWidget(Widget child) {
    return ProviderScope(
      overrides: [
        favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
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
    testWidgets('renders league header and match count',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague(name: 'Test Super League');
        final items = [
          buildItem(createTestMatch(id: '1')),
          buildItem(createTestMatch(id: '2')),
        ];

        await tester.pumpWidget(
          buildTestableWidget(
            LeagueGroup(
              league: league,
              items: items,
              isExpanded: false,
              onToggle: () {},
            ),
          ),
        );

        expect(find.text('Test Super League'), findsOneWidget);
        expect(find.text('LIVE 2'), findsOneWidget);
        expect(find.text('2 maç'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);
      });
    });

    testWidgets('calls onToggle when header is tapped',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague();
        final items = [buildItem(createTestMatch(id: '1'))];
        var toggleCalled = false;

        await tester.pumpWidget(
          buildTestableWidget(
            LeagueGroup(
              league: league,
              items: items,
              isExpanded: false,
              onToggle: () {
                toggleCalled = true;
              },
            ),
          ),
        );

        await tester.tap(find.text('1 maç'));
        await tester.pump();

        expect(toggleCalled, isTrue);
      });
    });

    testWidgets('renders match cards with view model labels when expanded',
        (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final league = createTestLeague();
        final items = [
          buildItem(
            createTestMatch(
              id: '1',
              homeTeam: 'Unique Home Team',
              status: model.MatchStatus.live,
              liveMinute: "67'",
            ),
            reasonLabel: 'Favori',
            secondaryLabel: '1 fark',
          ),
        ];

        await tester.pumpWidget(
          buildTestableWidget(
            LeagueGroup(
              league: league,
              items: items,
              isExpanded: true,
              onToggle: () {},
            ),
          ),
        );

        expect(find.text('Unique Home Team'), findsOneWidget);
        expect(find.text('Favori'), findsOneWidget);
        expect(find.text('1 fark'), findsOneWidget);
      });
    });
  });
}
