import 'dart:async';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class UsernameSetupDialog extends StatefulWidget {
  const UsernameSetupDialog({super.key});

  @override
  State<UsernameSetupDialog> createState() => _UsernameSetupDialogState();
}

class _UsernameSetupDialogState extends State<UsernameSetupDialog> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = false;
  String? _usernameError;
  Timer? _debounceTimer;
  bool _isSaving = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    setState(() {});
    
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    final RegExp usernameRegExp = RegExp(r'^[a-z0-9_]{3,15}$');
    final trimmed = value.trim();
    
    if (trimmed.isEmpty) {
      setState(() {
        _usernameError = 'Kullanıcı adı boş olamaz.';
        _isUsernameAvailable = false; 
      });
      return;
    } else if (!usernameRegExp.hasMatch(trimmed)) {
       setState(() {
        _usernameError = '3-15 krt. Sadece küçük harf, rakam ve alt tire.';
        _isUsernameAvailable = false; 
      });
      return;
    }

    setState(() {
      _usernameError = null;
      _isCheckingUsername = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      final available = await SupabaseService().isUsernameAvailable(trimmed);
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = available;
          if (!available) {
            _usernameError = 'Bu kullanıcı adı zaten alınmış.';
          }
        });
      }
    });
  }

  Future<void> _handleSave() async {
    final newUsername = _usernameController.text.trim();

    if (newUsername.isEmpty || _usernameError != null || !_isUsernameAvailable) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final user = SupabaseService().getCurrentUser();
    if (user != null) {
      final success = await SupabaseService().updateUserProfile(
        user.id,
        username: newUsername,
      );

      if (success && mounted) {
        Navigator.pop(context); // Close the dialog
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        _usernameError = 'Bir hata oluştu. Lütfen tekrar deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent dismissing by back button
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.colors.surfaceContainerLow),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.badge, size: 48, color: context.colors.primary),
                ),
                const SizedBox(height: 24),
                Text(
                  'Takma Adını Belirle',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: context.colors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Toplulukta seni bu isimle tanıyacaklar.',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textMedium,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _buildUsernameField(context),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isUsernameAvailable && _usernameError == null && !_isCheckingUsername && !_isSaving)
                        ? _handleSave
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: context.colors.background,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.background),
                          )
                        : const Text(
                            'DEVAM ET',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameField(BuildContext context) {
    Widget? suffixIcon;
    var borderColor = context.colors.surfaceContainerLow;
    var iconColor = context.colors.textLow;

    if (_isCheckingUsername) {
      suffixIcon = Padding(
        padding: const EdgeInsets.all(12.0),
        child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primary),
        ),
      );
    } else if (_usernameController.text.trim().isNotEmpty) {
      if (_isUsernameAvailable && _usernameError == null) {
        suffixIcon = const Icon(Icons.check_circle, color: Colors.green);
        borderColor = Colors.green;
        iconColor = Colors.green;
      } else {
        suffixIcon = const Icon(Icons.error, color: Colors.red);
        borderColor = Colors.red;
        iconColor = Colors.red;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _usernameController,
          onChanged: _onUsernameChanged,
          style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.textHigh),
          decoration: InputDecoration(
            hintText: 'örn. spor_krali',
            prefixIcon: Icon(Icons.person_outline, color: iconColor),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: context.colors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _usernameError != null ? Colors.red : context.colors.primaryContainer, width: 2),
            ),
          ),
        ),
        if (_usernameError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 16.0),
            child: Text(
              _usernameError!,
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
