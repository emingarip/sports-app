import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

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
      backgroundColor: AppTheme.surfaceContainerLow,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          decoration: const BoxDecoration(
            color: AppTheme.background,
            border: Border.symmetric(vertical: BorderSide(color: AppTheme.surfaceContainerLow, width: 2)),
          ),
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
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
        'PROFILE',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: 1,
          color: AppTheme.textHigh,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: AppTheme.error),
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
                color: AppTheme.surfaceContainer,
                border: Border.all(color: AppTheme.primaryContainer, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryContainer.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: _profile!.avatarUrl != null 
                ? ClipOval(child: Image.network(_profile!.avatarUrl!, fit: BoxFit.cover))
                : const Icon(Icons.person, size: 48, color: AppTheme.textMedium),
            ),
            const SizedBox(height: 16),
            Text(
              _profile!.username,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.textHigh,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _profile!.email,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMedium,
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
                foregroundColor: AppTheme.textHigh,
                side: const BorderSide(color: AppTheme.surfaceContainerHigh),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
              child: _buildMetricCard(
                title: 'K-COINS',
                value: _profile!.virtualCurrencyBalance.toString(),
                icon: Icons.monetization_on,
                color: AppTheme.primaryContainer,
                onColor: AppTheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'REPUTATION',
                value: _profile!.reputationScore.toString(),
                icon: Icons.star,
                color: AppTheme.surfaceContainerLowest,
                onColor: AppTheme.textHigh,
                borderColor: AppTheme.surfaceContainerHigh,
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
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(left: 24.0, right: 24.0, top: 40.0, bottom: 16.0),
        child: Text(
          "RECENT PREDICTIONS",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: AppTheme.textMedium,
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
            color: AppTheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.surfaceContainerLow),
          ),
          child: const Center(
            child: Column(
              children: [
                Icon(Icons.history, size: 48, color: AppTheme.surfaceContainerHigh),
                SizedBox(height: 16),
                Text(
                  "No activity yet.",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMedium,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Make some predictions to earn coins!",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textLow,
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
            Color statusColor = AppTheme.textMedium;
            IconData statusIcon = Icons.hourglass_top;
            
            if (status == 'won') {
              statusColor = AppTheme.success;
              statusIcon = Icons.check_circle;
            } else if (status == 'lost') {
              statusColor = AppTheme.error;
              statusIcon = Icons.cancel;
            } else if (status == 'refunded') {
              statusColor = AppTheme.textLow;
              statusIcon = Icons.replay;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceContainerLow),
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
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textHigh, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Staked: ${bet['amount_staked']} ',
                              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textMedium, fontSize: 11),
                            ),
                            const Icon(Icons.monetization_on, size: 10, color: AppTheme.textMedium),
                            const Text(
                              ' • ',
                              style: TextStyle(color: AppTheme.surfaceContainerHigh),
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
                      const Text(
                        'TO WIN',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMedium, fontSize: 9, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '+${bet['potential_payout']}',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.primary, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.monetization_on, size: 12, color: AppTheme.primaryContainer),
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
