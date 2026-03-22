import 'package:flutter/material.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:sports_app/screens/main_layout.dart';
import 'package:sports_app/screens/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Fire up Supabase in the background
    await SupabaseService.initialize();

    if (!mounted) return;

    // Check auth state to navigate
    final session = SupabaseService().getCurrentUser();
    if (session != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainLayout()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212), // AppTheme.background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Using an icon as a placeholder logo for the splash screen
            Icon(
              Icons.sports_soccer,
              size: 80,
              color: Color(0xFFBB86FC), // AppTheme.primary
            ),
            SizedBox(height: 24),
            Text(
              'KINETIC SCORES',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(
              color: Color(0xFF03DAC6), // AppTheme.secondary
            ),
          ],
        ),
      ),
    );
  }
}
