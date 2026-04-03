import 'package:flutter/material.dart';
import 'package:sports_app/services/supabase_service.dart';
import 'package:sports_app/screens/main_layout.dart';
import 'package:sports_app/screens/login_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool Function()? isAuthenticatedResolver;
  final WidgetBuilder? authenticatedBuilder;
  final WidgetBuilder? unauthenticatedBuilder;

  const SplashScreen({
    super.key,
    this.isAuthenticatedResolver,
    this.authenticatedBuilder,
    this.unauthenticatedBuilder,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeApp();
    });
  }

  void _initializeApp() {
    final isAuthenticated =
        widget.isAuthenticatedResolver?.call() ??
        SupabaseService().getCurrentUser() != null;

    if (isAuthenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: 'main'),
          builder: widget.authenticatedBuilder ?? (_) => const MainLayout(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: 'login'),
          builder: widget.unauthenticatedBuilder ?? (_) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212), // context.colors.background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Using an icon as a placeholder logo for the splash screen
            Icon(
              Icons.sports_soccer,
              size: 80,
              color: Color(0xFFBB86FC), // context.colors.primary
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
              color: Color(0xFF03DAC6), // context.colors.secondary
            ),
          ],
        ),
      ),
    );
  }
}
