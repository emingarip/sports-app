import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../providers/theme_provider.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import '../providers/wallet_provider.dart';
import 'store_front_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<Map<String, dynamic>> _bets = [];
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
      final betsData = await SupabaseService().getUserBets(user.id);
      if (data != null && mounted) {
        setState(() {
          _profile = UserProfile.fromJson(data);
          _bets = betsData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false; 
        });
      }
    } else {
      if (mounted) {
        setState(() {
           _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    await SupabaseService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: BoxDecoration(
            color: context.colors.background,
            border: Border.symmetric(vertical: BorderSide(color: context.colors.surfaceContainerLow, width: 2)),
          ),
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: context.colors.primary)),
                )
              else if (_profile == null)
                const SliverFillRemaining(
                  child: Center(child: Text("Could not load profile. Please sign in again.")),
                )
              else ...[
                _buildHeroSection(),
                _buildMetricsGrid(),
                _buildRecentActivityHeader(),
                if (_bets.isEmpty) _buildEmptyActivityState() else _buildBetsList(),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      pinned: true,
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
        'PROFILE',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: 1,
          color: context.colors.textHigh,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.logout, color: context.colors.error),
          tooltip: 'Log Out',
          onPressed: _handleLogout,
        ),
      ],
    );
  }

  Widget _buildHeroSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.surfaceContainer,
                border: Border.all(color: context.colors.primaryContainer, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.primaryContainer.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: _profile!.avatarUrl != null 
                ? ClipOval(child: Image.network(_profile!.avatarUrl!, fit: BoxFit.cover))
                : Icon(Icons.person, size: 48, color: context.colors.textMedium),
            ),
            const SizedBox(height: 16),
            Text(
              _profile!.username,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: context.colors.textHigh,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _profile!.email,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.colors.textMedium,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final didUpdate = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)),
                );
                if (didUpdate == true) {
                  _fetchProfile(); // Refresh profile state after saving
                }
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textHigh,
                side: BorderSide(color: context.colors.surfaceContainerHigh),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Consumer(
              builder: (context, ref, child) {
                final currentMode = ref.watch(themeModeNotifierProvider);
                return SegmentedButton<ThemeMode>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: context.colors.surfaceContainerLowest,
                    foregroundColor: context.colors.textMedium,
                    selectedForegroundColor: context.colors.textHigh,
                    selectedBackgroundColor: context.colors.primaryContainer,
                  ),
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest), label: Text('System')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                  ],
                  selected: {currentMode},
                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                    ref.read(themeModeNotifierProvider.notifier).setThemeMode(newSelection.first);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Row(
          children: [
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final balance = ref.watch(walletBalanceProvider);
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const StoreFrontScreen()),
                      );
                    },
                    child: _buildMetricCard(
                      title: 'K-COINS',
                      value: balance.toString(),
                      icon: Icons.monetization_on,
                      color: context.colors.primaryContainer,
                      onColor: context.colors.onPrimaryContainer,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'REPUTATION',
                value: _profile!.reputationScore.toString(),
                icon: Icons.star,
                color: context.colors.surfaceContainerLowest,
                onColor: context.colors.textHigh,
                borderColor: context.colors.surfaceContainerHigh,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color onColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: borderColor != null ? Border.all(color: borderColor) : null,
        boxShadow: const [
           BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: onColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: onColor.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: onColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 40.0, bottom: 16.0),
        child: Text(
          "RECENT PREDICTIONS",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: context.colors.textMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyActivityState() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.surfaceContainerLow),
          ),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.history, size: 48, color: context.colors.surfaceContainerHigh),
                const SizedBox(height: 16),
                Text(
                  "No activity yet.",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Make some predictions to earn coins!",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textLow,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBetsList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final bet = _bets[index];
            final prediction = bet['predictions'] as Map<String, dynamic>?;
            final predictionText = prediction?['prediction_type'] ?? 'Unknown Prediction';
            
            final status = bet['status'] as String;
            Color statusColor = context.colors.textMedium;
            IconData statusIcon = Icons.hourglass_top;
            
            if (status == 'won') {
              statusColor = context.colors.success;
              statusIcon = Icons.check_circle;
            } else if (status == 'lost') {
              statusColor = context.colors.error;
              statusIcon = Icons.cancel;
            } else if (status == 'refunded') {
              statusColor = context.colors.textLow;
              statusIcon = Icons.replay;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.surfaceContainerLow),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          predictionText,
                          style: TextStyle(fontWeight: FontWeight.w800, color: context.colors.textHigh, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Staked: ${bet['amount_staked']} ',
                              style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.textMedium, fontSize: 11),
                            ),
                            Icon(Icons.monetization_on, size: 10, color: context.colors.textMedium),
                            Text(
                              ' • ',
                              style: TextStyle(color: context.colors.surfaceContainerHigh),
                            ),
                            Text(
                              status.toUpperCase(),
                              style: TextStyle(fontWeight: FontWeight.w900, color: statusColor, fontSize: 10, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TO WIN',
                        style: TextStyle(fontWeight: FontWeight.w800, color: context.colors.textMedium, fontSize: 9, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '+${bet['potential_payout']}',
                            style: TextStyle(fontWeight: FontWeight.w900, color: context.colors.primary, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.monetization_on, size: 12, color: context.colors.primaryContainer),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          childCount: _bets.length,
        ),
      ),
    );
  }
}
