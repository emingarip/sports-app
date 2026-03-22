import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/theme/app_theme.dart';
import 'package:sports_app/widgets/empty_state.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            child,
          ],
        ),
      ),
    );
  }

  group('EmptyState Widget', () {
    testWidgets('renders correct message and icon', (WidgetTester tester) async {
      const testMessage = 'No live matches found right now.';
      
      await tester.pumpWidget(buildTestableWidget(const EmptyState(message: testMessage)));

      // Assert the message is displayed
      expect(find.text(testMessage), findsOneWidget);

      // Assert the soccer ball icon is displayed
      expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
    });
  });
}
