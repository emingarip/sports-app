import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/providers/match_provider.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/filter_row.dart';

import '../helpers/mock_match_repository.dart';

void main() {
  group('FilterRow Widget', () {
    late MockMatchRepository mockRepo;

    setUp(() {
      mockRepo = MockMatchRepository();
    });

    testWidgets('renders compact filter controls', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            matchRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: FilterRow()),
          ),
        ),
      );

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('updates global provider state on click',
        (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(mockRepo),
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

      expect(container.read(matchStateProvider).isAll, isTrue);
      expect(container.read(matchStateProvider).starredOnly, isFalse);

      await tester.tap(find.text('Live'));
      await tester.pump();

      expect(container.read(matchStateProvider).isLiveOnly, isTrue);

      await tester.tap(find.text('Finished'));
      await tester.pump();

      expect(container.read(matchStateProvider).isFinishedOnly, isTrue);
      expect(container.read(matchStateProvider).isLiveOnly, isFalse);

      await tester.tap(find.byIcon(Icons.star_outline_rounded));
      await tester.pump();

      expect(container.read(matchStateProvider).starredOnly, isTrue);

      container.dispose();
    });
  });
}
