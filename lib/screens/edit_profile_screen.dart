import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
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
  
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  String? _usernameError;
  Timer? _debounceTimer;

  Uint8List? _selectedImageBytes;
  String? _selectedImageExt;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.profile.username);
    _avatarUrlController = TextEditingController(text: widget.profile.avatarUrl ?? '');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }
  
  void _onUsernameChanged(String value) {
    setState(() {}); // Updates avatar preview
    
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
    } else if (trimmed == widget.profile.username) {
       setState(() {
        _usernameError = null;
        _isUsernameAvailable = true;
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Forces any selected image to be downscaled to a max of 512x512 with 70% compression, 
    // dramatically reducing Supabase Storage footprint and network upload time.
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 70,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      final ext = pickedFile.name.split('.').last.toLowerCase();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageExt = ext;
      });
    }
  }

  Future<void> _handleSave() async {
    final newUsername = _usernameController.text.trim();
    String newAvatarUrl = _avatarUrlController.text.trim();

    if (newUsername.isEmpty || _usernameError != null || (!_isUsernameAvailable && newUsername != widget.profile.username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir kullanıcı adı belirleyin.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    if (_selectedImageBytes != null && _selectedImageExt != null) {
      final oldAvatarUrl = widget.profile.avatarUrl; // Keep a reference to the old URL

      final uploadedUrl = await SupabaseService().uploadAvatar(
        widget.profile.id,
        _selectedImageBytes!,
        _selectedImageExt!,
      );
      if (uploadedUrl != null) {
        newAvatarUrl = uploadedUrl;
        _avatarUrlController.text = uploadedUrl;

        // Cleanup old avatar from bucket asynchronously
        if (oldAvatarUrl != null && oldAvatarUrl.contains('avatars/')) {
          final oldFileName = oldAvatarUrl.split('avatars/').last;
          if (oldFileName.isNotEmpty) {
            SupabaseService().deleteAvatar(oldFileName);
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf yüklenemedi. Devam ediliyor...')),
        );
      }
    }

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
      backgroundColor: context.colors.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: context.colors.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'EDIT PROFILE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
            color: context.colors.textHigh,
          ),
        ),
        actions: [
          if (_isSaving)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: SizedBox(
                   width: 20, height: 20,
                   child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primary)
                ),
              ),
            )
          else
            TextButton(
              onPressed: _handleSave,
              child: Text(
                'SAVE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.colors.primary,
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(vertical: BorderSide(color: context.colors.surfaceContainerLow, width: 2)),
          ),
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              _buildAvatarPreview(),
              const SizedBox(height: 32),
              
              // Custom Input Field for Username
              _buildUsernameField(),
              
              const SizedBox(height: 24),
              _buildInputField(
                label: 'AVATAR URL',
                controller: _avatarUrlController,
                icon: Icons.image_outlined,
                onChanged: (_) => setState(() {}),
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
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colors.surfaceContainer,
                    border: Border.all(color: context.colors.outline, width: 2),
                  ),
                  child: ClipOval(
                    child: _selectedImageBytes != null
                        ? Image.memory(
                            _selectedImageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 48, color: context.colors.textMedium),
                          )
                        : _avatarUrlController.text.isNotEmpty
                            ? Image.network(
                                _avatarUrlController.text,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 48, color: context.colors.textMedium),
                              )
                            : Icon(Icons.person, size: 48, color: context.colors.textMedium),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.background, width: 2),
                  ),
                  child: Icon(Icons.camera_alt, size: 20, color: context.colors.background),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Fotoğrafı Değiştir',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textMedium),
          )
        ],
      ),
    );
  }

  Widget _buildUsernameField() {
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
    } else if (_usernameController.text.trim().isNotEmpty && _usernameController.text.trim() != widget.profile.username) {
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
        Text(
          'USERNAME',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: context.colors.textMedium,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _usernameController,
          onChanged: _onUsernameChanged,
          style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.textHigh),
          decoration: InputDecoration(
            hintText: 'cool_user123',
            prefixIcon: Icon(Icons.person_outline, color: iconColor),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
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
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    void Function(String)? onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: context.colors.textMedium,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.textHigh),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: context.colors.textLow),
            filled: true,
            fillColor: context.colors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.colors.surfaceContainerLow),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.colors.surfaceContainerLow),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: context.colors.primaryContainer, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

