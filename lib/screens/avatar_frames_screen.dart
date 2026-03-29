import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/supabase_service.dart';
import '../providers/store_provider.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/frame_avatar.dart';

class AvatarFramesScreen extends ConsumerStatefulWidget {
  const AvatarFramesScreen({super.key});

  @override
  ConsumerState<AvatarFramesScreen> createState() => _AvatarFramesScreenState();
}

class _AvatarFramesScreenState extends ConsumerState<AvatarFramesScreen> {
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final user = SupabaseService().getCurrentUser();
    if (user != null) {
      final data = await SupabaseService().getUserProfile(user.id);
      if (data != null && mounted) {
        setState(() {
          _profile = UserProfile.fromJson(data);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleEquip(String frameCode) async {
    if (_profile == null) return;
    
    setState(() => _isLoading = true);
    
    final success = await SupabaseService().equipUserFrame(_profile!.id, frameCode);
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çerçeve başarıyla kuşanıldı!')),
      );
      await _fetchProfile();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hata oluştu. Lütfen tekrar deneyin.')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUnequip() async {
    if (_profile == null) return;
    setState(() => _isLoading = true);
    
    // Pass null to unequip
    final success = await SupabaseService().equipUserFrame(_profile!.id, null);
    if (success && mounted) {
      await _fetchProfile();
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBuy(String productCode, int price) async {
    setState(() => _isLoading = true);
    
    try {
      final storeService = ref.read(storeServiceProvider);
      final success = await storeService.buyStoreItem(productCode);
      
      if (success && mounted) {
        // Refresh entitlements
        await ref.read(entitlementsProvider.notifier).refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Satın alma başarılı! Artık çerçeveyi kuşanabilirsiniz.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeProductsAsync = ref.watch(storeProductsProvider);
    final entitlementsAsync = ref.watch(entitlementsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('My Avatar Frames', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: context.colors.surfaceContainer,
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: context.colors.primary))
        : storeProductsAsync.when(
            loading: () => Center(child: CircularProgressIndicator(color: context.colors.primary)),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (products) {
              // Filter products to only show frames
              final frames = products.where((p) => p.productCode.startsWith('frame_')).toList();
              
              if (frames.isEmpty) {
                return const Center(child: Text('Mağazada hiç çerçeve bulunmuyor.'));
              }

              return entitlementsAsync.when(
                loading: () => Center(child: CircularProgressIndicator(color: context.colors.primary)),
                error: (err, stack) => Center(child: Text('Error: $err')),
                data: (entitlements) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: frames.length,
                    itemBuilder: (context, index) {
                      final frame = frames[index];
                      // Check if user owns it
                      final isOwned = entitlements.any((e) => e.productCode == frame.productCode && e.isValid);
                      final isEquipped = _profile?.activeFrame == frame.productCode;

                      return Card(
                        color: context.colors.surfaceContainer,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              // Preview Avatar
                              FrameAvatar(
                                avatarUrl: _profile?.avatarUrl,
                                activeFrame: frame.productCode,
                                radius: 36,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      frame.title, 
                                      style: TextStyle(
                                        color: context.colors.textHigh,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      )
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      frame.description,
                                      style: TextStyle(
                                        color: context.colors.textMedium,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (!isOwned)
                                      Row(
                                        children: [
                                          Icon(Icons.monetization_on, size: 14, color: context.colors.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${frame.price} K-Coins',
                                            style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              // Action Button
                              Column(
                                children: [
                                  if (isEquipped)
                                    ElevatedButton(
                                      onPressed: _handleUnequip,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: context.colors.surfaceContainerHighest,
                                      ),
                                      child: Text('Çıkar', style: TextStyle(color: context.colors.textHigh)),
                                    )
                                  else if (isOwned)
                                    ElevatedButton(
                                      onPressed: () => _handleEquip(frame.productCode),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: context.colors.primary,
                                      ),
                                      child: Text('Kuşan', style: TextStyle(color: context.colors.background)),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      onPressed: () => _handleBuy(frame.productCode, frame.price),
                                      icon: const Icon(Icons.shopping_cart, size: 16),
                                      label: const Text('Satın Al'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: context.colors.primaryContainer,
                                        foregroundColor: context.colors.onPrimaryContainer,
                                      ),
                                    )
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }
              );
            },
          ),
    );
  }
}
