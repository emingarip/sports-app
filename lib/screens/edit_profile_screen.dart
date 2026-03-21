import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _avatarUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _avatarUrlController = TextEditingController(text: widget.profile.avatarUrl ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final newUsername = _usernameController.text.trim();
    final newAvatarUrl = _avatarUrlController.text.trim();

    if (newUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final success = await SupabaseService().updateUserProfile(
      widget.profile.id,
      username: newUsername != widget.profile.username ? newUsername : null,
      avatarUrl: newAvatarUrl != (widget.profile.avatarUrl ?? '') ? (newAvatarUrl.isEmpty ? null : newAvatarUrl) : null,
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (success) {
      Navigator.pop(context, true); // Return true to signal refresh needed
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update profile.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'EDIT PROFILE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
            color: AppTheme.textHigh,
          ),
        ),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                   width: 20, height: 20,
                   child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)
                ),
              ),
            )
          else
            TextButton(
              onPressed: _handleSave,
              child: const Text(
                'SAVE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: const BoxDecoration(
            color: AppTheme.background,
            border: Border.symmetric(vertical: BorderSide(color: AppTheme.surfaceContainerLow, width: 2)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              _buildAvatarPreview(),
              const SizedBox(height: 32),
              _buildInputField(
                label: 'USERNAME',
                controller: _usernameController,
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 24),
              _buildInputField(
                label: 'AVATAR URL',
                controller: _avatarUrlController,
                icon: Icons.image_outlined,
                hint: 'https://example.com/avatar.png',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceContainer,
              border: Border.all(color: AppTheme.outline, width: 2),
            ),
            child: ClipOval(
              child: _avatarUrlController.text.isNotEmpty
                  ? Image.network(
                      _avatarUrlController.text,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: AppTheme.textMedium),
                    )
                  : const Icon(Icons.person, size: 48, color: AppTheme.textMedium),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Preview',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMedium),
          )
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: AppTheme.textMedium,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: (_) => setState(() {}), // Triggers avatar preview update
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textHigh),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppTheme.textLow),
            filled: true,
            fillColor: AppTheme.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.surfaceContainerLow),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.surfaceContainerLow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.primaryContainer, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
