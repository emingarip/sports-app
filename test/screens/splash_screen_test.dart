import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_app/screens/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    testWidgets(
      'does not navigate during build and pushes login after first frame',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SplashScreen(
              isAuthenticatedResolver: () => false,
              unauthenticatedBuilder: (_) => const Scaffold(
                body: Text('login-screen'),
              ),
              authenticatedBuilder: (_) => const Scaffold(
                body: Text('main-layout'),
              ),
            ),
          ),
        );

        expect(find.text('KINETIC SCORES'), findsOneWidget);
        expect(find.text('login-screen'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(find.text('login-screen'), findsOneWidget);
      },
    );

    testWidgets(
      'routes authenticated users to the main layout replacement target',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SplashScreen(
              isAuthenticatedResolver: () => true,
              unauthenticatedBuilder: (_) => const Scaffold(
                body: Text('login-screen'),
              ),
              authenticatedBuilder: (_) => const Scaffold(
                body: Text('main-layout'),
              ),
            ),
          ),
        );

        expect(find.text('KINETIC SCORES'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('main-layout'), findsOneWidget);
      },
    );
  });
}
