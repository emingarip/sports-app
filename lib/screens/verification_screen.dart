import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'verification_success_screen.dart';
import '../services/supabase_service.dart';

class VerificationScreen extends StatefulWidget {
  final String email;
  
  const VerificationScreen({super.key, required this.email});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(8, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());
  bool _isFilled = false;
  bool _isLoading = false;

  void _submitVerify() async {
    if (!_isFilled) return;
    final code = _controllers.map((c) => c.text).join();
    
    setState(() => _isLoading = true);
    try {
      await SupabaseService().verifyOTP(widget.email, code);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VerificationSuccessScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification Failed: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 8; i++) {
      _controllers[i].addListener(_checkFilled);
    }
    // Auto focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNodes[0]);
    });
  }

  void _checkFilled() {
    bool filled = _controllers.every((c) => c.text.isNotEmpty);
    if (filled != _isFilled) {
      if (mounted) {
        setState(() {
          _isFilled = filled;
        });
      }
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onInputCustom(String value, int index) {
    if (value.isNotEmpty && index < 7) {
      FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
    } else if (value.isEmpty && index > 0) {
      FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Accent Line
            Container(
              height: 2,
              width: double.infinity,
              color: AppTheme.primaryContainer,
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "KINETIC",
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.primary,
                      letterSpacing: -1,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surfaceContainerHigh,
                      foregroundColor: AppTheme.textMedium,
                    ),
                    icon: const Icon(Icons.close),
                  )
                ],
              ),
            ),
            
            // Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 512),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Enter verification code",
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.2,
                          color: AppTheme.textHigh,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            "Enter the 8-digit code we sent to ",
                            style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textMedium),
                          ),
                          Text(
                            widget.email,
                            style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textHigh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, size: 16, color: AppTheme.textMedium),
                            SizedBox(width: 4),
                            Text(
                              "Edit email address",
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textMedium, decoration: TextDecoration.underline),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // OTP Grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(8, (index) {
                          return Flexible(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: TweenAnimationBuilder<double>(
                                  duration: const Duration(milliseconds: 200),
                                  tween: Tween(begin: 1.0, end: _focusNodes[index].hasFocus ? 1.05 : 1.0),
                                  builder: (context, scale, child) {
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: TextField(
                                    controller: _controllers[index],
                                    focusNode: _focusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    maxLength: 1,
                                    style: const TextStyle(fontFamily: 'Lexend', fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primary),
                                    decoration: InputDecoration(
                                      counterText: "",
                                      filled: true,
                                      fillColor: _controllers[index].text.isNotEmpty ? Colors.white : AppTheme.surfaceContainerLowest,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(color: AppTheme.primaryContainer, width: 2),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide(
                                          color: _controllers[index].text.isNotEmpty ? AppTheme.primaryContainer : Colors.transparent, 
                                          width: 2
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) => _onInputCustom(value, index),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Action Area
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            color: _isFilled ? AppTheme.primaryContainer : AppTheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: _isFilled ? [BoxShadow(color: AppTheme.primaryContainer.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(32),
                              onTap: _isFilled && !_isLoading ? _submitVerify : null,
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.onPrimaryContainer, strokeWidth: 2))
                                    : Text(
                                        "VERIFY",
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2,
                                          color: _isFilled ? AppTheme.onPrimaryContainer : AppTheme.textMedium.withOpacity(0.5),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Center(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: const [
                            Text(
                              "Didn't receive code? ",
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textMedium),
                            ),
                            Text(
                              "Resend code in 00:30",
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textMedium),
                            ),
                          ],
                        ),
                      ),
                      
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                "POWERED BY KINETIC DATA ENGINE V1.0.2",
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: AppTheme.textLow, // Changed to textLow as surfaceContainerHigh was too light
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
