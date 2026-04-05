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
      expect(find.text('2 mac'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('inline-search-toggle')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inline-search-toggle')));
      await tester.pumpAndSettle();

      expect(container.read(matchStateProvider).isInlineSearchOpen, isTrue);
      expect(find.byKey(const ValueKey('inline-search-field')), findsOneWidget);
      expect(find.text('Mac ara'), findsOneWidget);
      expect(find.text('2 mac'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Real');
      await tester.pump(const Duration(milliseconds: 150));

      expect(container.read(matchStateProvider).inlineSearchQuery, 'Real');
      expect(find.text('Mac ara'), findsOneWidget);

      await tester.tap(find.byTooltip('Aramayi kapat'));
      await tester.pumpAndSettle();

      expect(container.read(matchStateProvider).isInlineSearchOpen, isFalse);
      expect(find.text('2 mac'), findsOneWidget);

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

    testWidgets('keeps mobile controls on one row in compact mode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepo),
          favoritesProvider.overrideWith(() => MockFavoritesNotifier()),
        ],
      );

      mockRepo.setMatches([
        createTestMatch(id: '1', homeTeam: 'Arsenal', awayTeam: 'Chelsea'),
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
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(tester.getSize(find.byType(FilterRow)).height, lessThanOrEqualTo(60));

      await tester.tap(find.byKey(const ValueKey('inline-search-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('inline-search-field')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(tester.getSize(find.byType(FilterRow)).height, lessThanOrEqualTo(60));

      container.dispose();
    });
  });
}
