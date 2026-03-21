import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/widgets/filter_row.dart';

void main() {
  Widget buildTestableWidget({
    required String activeFilter,
    required ValueChanged<String> onFilterChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: FilterRow(
          activeFilter: activeFilter,
          onFilterChanged: onFilterChanged,
        ),
      ),
    );
  }

  group('FilterRow Widget', () {
    testWidgets('renders all four filter chips', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(
        activeFilter: 'All',
        onFilterChanged: (_) {},
      ));

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Live 🔴'), findsOneWidget);
      expect(find.text('Starred ⭐'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
    });

    testWidgets('calls onFilterChanged with clicked chip label', (WidgetTester tester) async {
      String? tappedLabel;
      
      await tester.pumpWidget(buildTestableWidget(
        activeFilter: 'All',
        onFilterChanged: (label) {
          tappedLabel = label;
        },
      ));

      // Tap on 'Live 🔴'
      await tester.tap(find.text('Live 🔴'));
      await tester.pump();

      expect(tappedLabel, 'Live 🔴');
      
      // Tap on 'Finished'
      await tester.tap(find.text('Finished'));
      await tester.pump();
      
      expect(tappedLabel, 'Finished');
    });
  });
}
