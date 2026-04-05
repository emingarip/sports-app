import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/providers/favorites_provider.dart';
import 'package:sports_app/providers/match_provider.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/filter_row.dart';

import '../helpers/mock_match_repository.dart';
import '../helpers/test_helpers.dart';

class MockFavoritesNotifier extends FavoritesNotifier {
  @override
  Set<String> build() => {};

  @override
  Future<void> toggleFavorite(String matchId) async {}
}

void main() {
  group('FilterRow Widget', () {
    late MockMatchRepository mockRepo;

    setUp(() {
      mockRepo = MockMatchRepository();
    });

    testWidgets('renders filter controls, count and search CTA',
        (WidgetTester tester) async {
      mockRepo.setMatches([
        createTestMatch(id: '1'),
        createTestMatch(id: '2'),
      ]);

      var tappedSearch = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchRepositoryProvider.overrideWithValue(mockRepo),
            favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: FilterRow(
                onSearch: () {
                  tappedSearch = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Canlı'), findsOneWidget);
      expect(find.text('Biten'), findsOneWidget);
      expect(find.text('Favoriler'), findsOneWidget);
      expect(find.text('Maç ara'), findsOneWidget);
      expect(find.text('2 maç'), findsOneWidget);

      await tester.tap(find.text('Maç ara'));
      await tester.pump();

      expect(tappedSearch, isTrue);
    });

    testWidgets('updates global provider state on click',
        (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepo),
          favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: FilterRow()),
          ),
        ),
      );

      expect(container.read(matchStateProvider).statusFilter, StatusFilter.all);
      expect(container.read(matchStateProvider).isStarredFilter, false);

      await tester.tap(find.text('Canlı'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.live,
      );
      expect(container.read(matchStateProvider).isStarredFilter, false);

      await tester.tap(find.text('Biten'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.finished,
      );
      expect(container.read(matchStateProvider).isStarredFilter, false);

      await tester.tap(find.text('Favoriler'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.finished,
      );
      expect(container.read(matchStateProvider).isStarredFilter, true);

      container.dispose();
    });
  });
}
