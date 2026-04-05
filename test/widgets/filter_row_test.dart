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

    testWidgets('opens inline search and updates list result count',
        (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepo),
          favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
        ],
      );

      mockRepo.setMatches([
        createTestMatch(
          id: '1',
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
        ),
        createTestMatch(
          id: '2',
          homeTeam: 'Real Madrid',
          awayTeam: 'Barcelona',
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: FilterRow()),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Canli'), findsOneWidget);
      expect(find.text('Biten'), findsOneWidget);
      expect(find.text('Favoriler'), findsOneWidget);
      expect(find.text('Mac ara'), findsOneWidget);
      expect(find.text('2 mac'), findsOneWidget);

      await tester.tap(find.text('Mac ara'));
      await tester.pump();

      expect(container.read(matchStateProvider).isInlineSearchOpen, isTrue);
      expect(
          find.text('Takim ve lig isimlerine gore filtrele'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Real');
      await tester.pump();

      expect(container.read(matchStateProvider).inlineSearchQuery, 'Real');
      expect(find.text('1 mac bulundu'), findsOneWidget);

      await tester.tap(find.byTooltip('Aramayi temizle'));
      await tester.pump();

      expect(container.read(matchStateProvider).inlineSearchQuery, isEmpty);

      await tester.tap(find.byTooltip('Aramayi kapat'));
      await tester.pump();

      expect(container.read(matchStateProvider).isInlineSearchOpen, isFalse);

      container.dispose();
    });

    testWidgets('updates global provider state on filter click',
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
      expect(container.read(matchStateProvider).isStarredFilter, isFalse);

      await tester.tap(find.text('Canli'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.live,
      );
      expect(container.read(matchStateProvider).isStarredFilter, isFalse);

      await tester.tap(find.text('Biten'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.finished,
      );
      expect(container.read(matchStateProvider).isStarredFilter, isFalse);

      await tester.tap(find.text('Favoriler'));
      await tester.pump();

      expect(
        container.read(matchStateProvider).statusFilter,
        StatusFilter.finished,
      );
      expect(container.read(matchStateProvider).isStarredFilter, isTrue);

      container.dispose();
    });
  });
}
