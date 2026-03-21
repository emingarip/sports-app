import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';
import '../../lib/widgets/match_card.dart';
import '../../lib/models/match.dart' as model;
import '../helpers/test_helpers.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('MatchCard Widget', () {
    testWidgets('renders live match correctly', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          homeTeam: 'Arsenal',
          awayTeam: 'Chelsea',
          status: model.MatchStatus.live,
          homeScore: '2',
          awayScore: '1',
          liveMinute: "45'",
        );

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('2'), findsWidgets);
        expect(find.text('1'), findsWidgets);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text("45'"), findsOneWidget);
        expect(find.text('PREDICT'), findsOneWidget);
      });
    });

    testWidgets('renders finished match correctly', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(status: model.MatchStatus.finished);

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('Full\nTime'), findsOneWidget);
        expect(find.text('STATS'), findsOneWidget);
        expect(find.text('PREDICT'), findsNothing);
      });
    });

    testWidgets('renders upcoming match correctly with time and ODDS', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final match = createTestMatch(
          status: model.MatchStatus.upcoming,
          startTime: DateTime(2026, 3, 20, 20, 30),
        );

        await tester.pumpWidget(buildTestableWidget(
          MatchCard(match: match, hasBorder: false),
        ));

        expect(find.text('ODDS 2.10'), findsOneWidget);
        expect(find.text('LIVE'), findsNothing);
      });
    });
  });
}
