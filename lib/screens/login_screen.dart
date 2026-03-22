import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'main_layout.dart';
import 'verification_screen.dart';

import '../services/supabase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  void _requestOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email address')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService().signInWithOtp(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VerificationScreen(email: email)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: 96,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.surfaceContainerLow, width: 1)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user, color: AppTheme.primaryContainer, size: 24),
                      SizedBox(width: 8),
                      Text(
                        "VELOCITY SCORE",
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.primary,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.lock, size: 14, color: AppTheme.textLow),
                      SizedBox(width: 6),
                      Text(
                        "SECURE SSL",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: AppTheme.textLow,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            
            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 512),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titles
                      const Text(
                        "Sign in or create account",
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: AppTheme.textHigh,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "We’ll send a one-time verification code. No spam, just secure sign-in.",
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMedium,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 48),
                      
                      // Email Input
                      Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: AppTheme.surfaceContainer, width: 1),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Icon(Icons.email_outlined, color: AppTheme.textMedium),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(fontFamily: 'Lexend', fontSize: 20, fontWeight: FontWeight.w500, color: AppTheme.textHigh),
                                  decoration: const InputDecoration(
                                    hintText: "hello@velocityscore.com",
                                    hintStyle: TextStyle(color: AppTheme.surfaceContainerHigh),
                                    border: InputBorder.none,
                                    counterText: "",
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Primary Button
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _requestOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryContainer,
                            foregroundColor: AppTheme.onPrimaryContainer,
                            elevation: 8,
                            shadowColor: AppTheme.primaryContainer.withOpacity(0.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.onPrimaryContainer, strokeWidth: 2))
                              : const Text(
                                  "Get verification code",
                                  style: TextStyle(fontFamily: 'Lexend', fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Divider
                      const Row(
                        children: [
                          Expanded(child: Divider(color: AppTheme.surfaceContainer)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              "OR CONTINUE WITH",
                              style: TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2.5, color: AppTheme.textLow),
                            ),
                          ),
                          Expanded(child: Divider(color: AppTheme.surfaceContainer)),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Social Buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(builder: (_) => const MainLayout()),
                                  );
                                },
                                icon: Image.network(
                                  "https://lh3.googleusercontent.com/aida-public/AB6AXuCWmy_PJFYQWzVSMVGVQ2wB2vt2JlQQHPtkEjfLgKBMlVNitAqZge1qptbi46BSTKxwptGSRqJAa47QcdLrAt-I-UotXpDW9jEnhb9vlL-kVZqrLT875TsMRianEN83z07TepyH5JQULAQsVben2nob0X_3IHwGrVfjfSwO4N2eNobwIZ1muVGR3DSOw8h_OR8dnoplBPyLInfti8N8qbfuUZ4XKaeXMdu4XK_sPU7dnmUMvIrNAlKtpECxHfkAT-5Cf5jAdu-Tt_ti",
                                  width: 20, height: 20,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, size: 24),
                                ),
                                label: const Text("Google", style: TextStyle(fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textHigh)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.surfaceContainer),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                           Expanded(
                            child: SizedBox(
                              height: 56,
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.apple, color: AppTheme.textHigh),
                                label: const Text("Apple", style: TextStyle(fontFamily: 'Lexend', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textHigh)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.surfaceContainer),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                   RichText(
                     textAlign: TextAlign.center,
                     text: const TextSpan(
                       style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textLow, height: 1.5),
                       children: [
                         TextSpan(text: "By continuing, you agree to the Velocity Score\n"),
                         TextSpan(text: "Terms of Service", style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                         TextSpan(text: " and "),
                         TextSpan(text: "Privacy Policy", style: TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                       ],
                     ),
                   ),
                   const SizedBox(height: 24),
                   const Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                        Column(
                          children: [
                            Icon(Icons.language, color: AppTheme.textLow),
                            SizedBox(height: 4),
                            Text("EN", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLow)),
                          ],
                        ),
                        SizedBox(width: 32),
                        Column(
                          children: [
                            Icon(Icons.support_agent, color: AppTheme.textLow),
                            SizedBox(height: 4),
                            Text("HELP", style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLow)),
                          ],
                        ),
                     ],
                   )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
