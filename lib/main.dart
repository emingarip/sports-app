import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:feedback/feedback.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/supabase_service.dart';
import 'services/revenuecat_service.dart';
import 'package:rive/rive.dart' as rive;

import 'widgets/global_support_button.dart';
import 'services/admob_service.dart';
import 'providers/theme_provider.dart';
import 'services/deep_link_service.dart';
import 'services/navigation_service.dart';
import 'services/support_navigator_observer.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await AdMobService().initialize();
    AdMobService().loadRewardedAd();
    await rive.RiveNative.init();

    try {
      await Firebase.initializeApp(
        options: kIsWeb ? const FirebaseOptions(
          apiKey: "AIzaSyDLTwqiaptfxY0zwj2VUUjHZ_KaVPZ5xMo",
          appId: "1:858669470500:web:abcdef1234567890", // Placeholder for web app ID
          messagingSenderId: "858669470500",
          projectId: "boskale-d00cc",
        ) : null,
      );
      if (!kIsWeb) {
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }
    } catch (e) {
      debugPrint("App: Firebase init failed: $e");
    }
    await SupabaseService.initialize();
    await RevenueCatService.initialize();
    await DeepLinkService().initialize();
    runApp(
      ProviderScope(
        child: const BetterFeedback(
          child: MyApp(),
        ),
      ),
    );
  }, (error, stack) {
    if (!kIsWeb && Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    debugPrint('Zoned error: $error\n$stack');
  });
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndRefreshSession();
    }
  }

  Future<void> _checkAndRefreshSession() async {
    try {
      final session = SupabaseService.client.auth.currentSession;
      if (session != null && session.expiresAt != null) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
        // Refresh token if it expires in less than 5 minutes
        if (DateTime.now().add(const Duration(minutes: 5)).isAfter(expiresAt)) {
          debugPrint('App resumed: Supabase session is close to expiry. Refreshing token globally...');
          await SupabaseService.client.auth.refreshSession();
        }
      }
    } catch (e) {
      debugPrint('App resumed: Failed to refresh session globally: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey, // Set the global key
      navigatorObservers: [
        SupportNavigatorObserver(ref), // Register the observer
      ],
      debugShowCheckedModeBanner: false,
      title: 'Sports App MVP',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? AppTheme.darkColors.background : AppTheme.lightColors.background;

        return Scaffold(
          backgroundColor: bgColor,
          body: GlobalSupportButton(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: child!,
              ),
            ),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
