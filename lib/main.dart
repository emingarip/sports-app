import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'theme/app_theme.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinetic Scores',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: SupabaseService().getCurrentUser() != null
          ? const HomeDashboard()
          : const LoginScreen(),
    );
  }
}
