import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:feedback/feedback.dart';

import 'screens/splash_screen.dart';
import 'services/supabase_service.dart';
import 'services/revenuecat_service.dart';
import 'package:rive/rive.dart' as rive;

import 'widgets/global_support_button.dart';
import 'services/admob_service.dart';
import 'providers/app_theme_provider.dart';
import 'services/deep_link_service.dart';
import 'services/navigation_service.dart';
import 'services/support_navigator_observer.dart';
import 'services/app_theme_preferences.dart';

const String _firebaseWebApiKey =
    String.fromEnvironment('FIREBASE_WEB_API_KEY');
const String _firebaseWebAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
const String _firebaseWebMessagingSenderId = String.fromEnvironment(
  'FIREBASE_WEB_MESSAGING_SENDER_ID',
  defaultValue: '858669470500',
);
const String _firebaseWebProjectId = String.fromEnvironment(
  'FIREBASE_WEB_PROJECT_ID',
  defaultValue: 'boskale-d00cc',
);

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AdMobService().initialize();
    AdMobService().loadRewardedAd();
    await rive.RiveNative.init();

    try {
      if (!kIsWeb ||
          (_firebaseWebApiKey.isNotEmpty && _firebaseWebAppId.isNotEmpty)) {
        await Firebase.initializeApp(
          options: kIsWeb
              ? const FirebaseOptions(
                  apiKey: _firebaseWebApiKey,
                  appId: _firebaseWebAppId,
                  messagingSenderId: _firebaseWebMessagingSenderId,
                  projectId: _firebaseWebProjectId,
                )
              : null,
        );
      } else {
        debugPrint(
            'Web Firebase disabled: FIREBASE_WEB_API_KEY or FIREBASE_WEB_APP_ID is missing.');
      }
      if (!kIsWeb && Firebase.apps.isNotEmpty) {
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }
    } catch (e) {
      debugPrint("App: Firebase init failed: $e");
    }
    await AppThemePreferences.initialize();
    await SupabaseService.initialize();
    await RevenueCatService.initialize();
    await DeepLinkService().initialize();
    runApp(
      const ProviderScope(
        child: BetterFeedback(
          child: MyApp(),
        ),
      ),
    );
  }, (error, stack) {
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(appThemeControllerProvider);
    final lightTheme = ref.watch(resolvedLightThemeProvider);
    final darkTheme = ref.watch(resolvedDarkThemeProvider);

    return MaterialApp(
      title: 'Sports App',
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,
      navigatorObservers: [
        SupportNavigatorObserver(ref),
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeState.themeMode,
      builder: (context, child) {
        return GlobalSupportButton(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}
