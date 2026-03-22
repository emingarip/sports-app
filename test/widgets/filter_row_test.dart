import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_app/widgets/filter_row.dart';
import 'package:sports_app/providers/match_provider.dart';
import 'package:sports_app/theme/app_theme.dart';
import '../helpers/mock_match_repository.dart';

void main() {
  group('FilterRow Widget', () {
    late MockMatchRepository mockRepo;

    setUp(() {
      mockRepo = MockMatchRepository();
    });

    testWidgets('renders all four filter chips', (WidgetTester tester) async {
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

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Live 🔴'), findsOneWidget);
      expect(find.text('Starred ⭐'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
    });

    testWidgets('updates global provider state on click', (WidgetTester tester) async {
      // Create a dedicated container to read state changes natively
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

      // Verify Initial State
      expect(container.read(matchStateProvider).activeFilter, 'All');

      // Tap on 'Live 🔴'
      await tester.tap(find.text('Live 🔴'));
      await tester.pump();

      // Assert state updated
      expect(container.read(matchStateProvider).activeFilter, 'Live 🔴');
      
      // Tap on 'Finished'
      await tester.tap(find.text('Finished'));
      await tester.pump();
      
      expect(container.read(matchStateProvider).activeFilter, 'Finished');
      
      container.dispose();
    });
  });
}
