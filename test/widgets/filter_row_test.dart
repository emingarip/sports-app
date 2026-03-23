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

      expect(find.text('Live 🔴'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Starred ⭐'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Senin İçin ✨'), findsOneWidget);
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

      expect(container.read(matchStateProvider).activeFilter, 'All');

      await tester.tap(find.text('Live 🔴'));
      await tester.pump();

      expect(container.read(matchStateProvider).activeFilter, 'Live 🔴');

      await tester.tap(find.text('Finished'));
      await tester.pump();

      expect(container.read(matchStateProvider).activeFilter, 'Finished');

      await tester.tap(find.text('Starred ⭐'));
      await tester.pump();

      expect(container.read(matchStateProvider).activeFilter, 'Starred ⭐');

      container.dispose();
    });
  });
}
