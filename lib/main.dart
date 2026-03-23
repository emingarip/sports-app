import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/supabase_service.dart';

import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: kIsWeb ? const FirebaseOptions(
        apiKey: "AIzaSyDLTwqiaptfxY0zwj2VUUjHZ_KaVPZ5xMo",
        appId: "1:858669470500:web:abcdef1234567890", // Placeholder for web app ID
        messagingSenderId: "858669470500",
        projectId: "boskale-d00cc",
      ) : null,
    );
  } catch (e) {
    debugPrint("App: Firebase init failed: $e");
  }
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sports App MVP',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashScreen(),
    );
  }
}
