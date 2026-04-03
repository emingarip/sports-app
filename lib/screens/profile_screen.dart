import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../services/supabase_service.dart';
import '../providers/theme_provider.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import 'notification_preferences_screen.dart';
import 'help_center_screen.dart';
import '../providers/wallet_provider.dart';
import '../providers/badge_provider.dart';
import 'store_front_screen.dart';
import 'badges_screen.dart';
import 'purchase_history_screen.dart';
import 'avatar_frames_screen.dart';
import '../widgets/frame_avatar.dart';
import '../providers/leaderboard_provider.dart';
import '../widgets/shimmer_loading.dart';
import '../providers/support_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:feedback/feedback.dart';
import '../data/repositories/support/bug_report_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
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
                  child: const ProfileHeaderShimmer(),
                )
              else if (_profile == null)
                const SliverFillRemaining(
                  child: Center(child: Text("Could not load profile. Please sign in again.")),
                )
              else ...[
                _buildHeroSection(),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                _buildMetricsGrid(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                _buildEconomyActions(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                _buildBadgeShowcase(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                _buildSettingsMenu(),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                _buildSupportMenu(),
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
        padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AvatarFramesScreen()));
                await _fetchProfile();
                ref.invalidate(leaderboardProvider);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FrameAvatar(
                    avatarUrl: _profile!.avatarUrl,
                    activeFrame: _profile!.activeFrame,
                    radius: 54,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.colors.background, width: 2),
                      ),
                      child: Icon(
                        Icons.palette,
                        color: context.colors.onPrimaryContainer,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '@${_profile!.username}',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: context.colors.textHigh,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHigh.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _profile!.email,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textMedium,
                ),
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
              child: Consumer(
                builder: (context, ref, child) {
                  final balance = ref.watch(walletBalanceProvider);
                  return _buildBentoCard(
                    title: 'K-COINS',
                    value: balance.toString(),
                    icon: Icons.monetization_on,
                    bgColor: context.colors.primaryContainer.withOpacity(0.15),
                    iconColor: context.colors.primaryContainer,
                    textColor: context.colors.textHigh,
                    borderColor: context.colors.primaryContainer.withOpacity(0.3),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildBentoCard(
                title: 'REPUTATION',
                value: _profile!.reputationScore.toString(),
                icon: Icons.star,
                bgColor: context.colors.surfaceContainerHigh.withOpacity(0.5),
                iconColor: Colors.amber,
                textColor: context.colors.textHigh,
                borderColor: context.colors.outline.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required Color textColor,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: context.colors.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEconomyActions() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.outline.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              _buildSettingsTile(
                icon: Icons.storefront,
                iconColor: Colors.orangeAccent,
                title: 'K-Coin Store',
                subtitle: 'Buy K-Coins & Premium items',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoreFrontScreen())),
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.receipt_long,
                iconColor: Colors.greenAccent,
                title: 'Purchase History',
                subtitle: 'View your past transactions',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseHistoryScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsMenu() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.outline.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              _buildSettingsTile(
                icon: Icons.edit,
                iconColor: Colors.blueAccent,
                title: 'Edit Profile',
                onTap: () async {
                  final didUpdate = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)));
                  if (didUpdate == true) _fetchProfile();
                },
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.notifications_active,
                iconColor: Colors.pinkAccent,
                title: 'Notification Settings',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen())),
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.dark_mode,
                iconColor: Colors.indigoAccent,
                title: 'Theme Settings',
                trailing: _buildThemeToggle(),
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.logout,
                iconColor: Colors.redAccent,
                title: 'Log Out',
                titleColor: Colors.redAccent,
                onTap: _handleLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupportMenu() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.outline.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               Padding(
                 padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                 child: Row(
                   children: [
                     Icon(Icons.headset_mic_rounded, size: 20, color: context.colors.primary),
                     const SizedBox(width: 8),
                     Text(
                       'DESTEK & YARDIM',
                       style: TextStyle(
                         color: context.colors.primary,
                         fontSize: 13,
                         fontWeight: FontWeight.w800,
                         letterSpacing: 1.2,
                       ),
                     ),
                   ],
                 ),
               ),
              _buildSettingsTile(
                icon: Icons.chat_bubble_outline,
                iconColor: Colors.blueAccent,
                title: 'Canlı Destek',
                onTap: () {
                  ref.read(liveChatServiceProvider).openChat(context);
                },
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.help_outline,
                iconColor: Colors.orangeAccent,
                title: 'Yardım Merkezi (SSS)',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpCenterScreen()),
                  );
                },
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.bug_report_outlined,
                iconColor: Colors.redAccent,
                title: 'Sorun Bildir',
                onTap: () {
                  BetterFeedback.of(context).show((UserFeedback feedback) async {
                    try {
                      await ref.read(bugReportServiceProvider).submitFeedback(
                        feedback.text,
                        feedback.screenshot,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Geri bildiriminiz başarıyla iletildi!')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e')),
                        );
                      }
                    }
                  });
                },
              ),
              Divider(height: 1, indent: 64, color: context.colors.outline.withOpacity(0.1)),
              _buildSettingsTile(
                icon: Icons.contact_mail_outlined,
                iconColor: Colors.green,
                title: 'Bize Ulaşın',
                onTap: () => _showContactBottomSheet(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContactBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
         decoration: BoxDecoration(
           color: context.colors.surfaceContainer,
           borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
         ),
         child: SafeArea(
           child: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               const SizedBox(height: 12),
               Container(width: 40, height: 4, decoration: BoxDecoration(color: context.colors.outline.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
               const SizedBox(height: 24),
               Text('Bize Ulaşın', style: TextStyle(color: context.colors.textHigh, fontSize: 20, fontWeight: FontWeight.bold)),
               const SizedBox(height: 16),
               _buildContactOption(Icons.message, 'WhatsApp', Colors.green, () => _launchSocialUrl(dotenv.env['WHATSAPP_URL'])),
               _buildContactOption(Icons.send, 'Telegram', Colors.blue, () => _launchSocialUrl(dotenv.env['TELEGRAM_URL'])),
               _buildContactOption(Icons.email, 'E-Posta', Colors.redAccent, () => _launchSocialUrl('mailto:${dotenv.env['SUPPORT_EMAIL']}')),
               _buildContactOption(Icons.camera_alt, 'Instagram', Colors.purpleAccent, () => _launchSocialUrl(dotenv.env['INSTAGRAM_URL'])),
               const SizedBox(height: 24),
             ],
           ),
         ),
      ),
    );
  }

  Widget _buildContactOption(IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: TextStyle(color: context.colors.textHigh)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _launchSocialUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildThemeToggle() {
    return Consumer(
      builder: (context, ref, child) {
        final currentMode = ref.watch(themeModeNotifierProvider);
        return SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: context.colors.surfaceContainerLowest,
            foregroundColor: context.colors.textMedium,
            selectedForegroundColor: context.colors.textHigh,
            selectedBackgroundColor: context.colors.primaryContainer,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest, size: 16)),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
          ],
          selected: {currentMode},
          onSelectionChanged: (Set<ThemeMode> newSelection) {
            ref.read(themeModeNotifierProvider.notifier).setThemeMode(newSelection.first);
          },
        );
      },
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor ?? context.colors.textHigh,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              Icon(Icons.chevron_right, color: context.colors.textMedium, size: 20),
          ],
        ),
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
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.outline.withOpacity(0.05)),
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
                color: context.colors.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.colors.outline.withOpacity(0.05)),
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

  Widget _buildBadgeShowcase() {
    final badgeState = ref.watch(badgeProvider);
    if (badgeState.isLoading) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final recentBadges = badgeState.recentlyUnlocked;
    final unlockedCount = badgeState.unlockedCount;
    final totalCount = badgeState.definitions.length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.military_tech, size: 18, color: context.colors.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Rozetler',
                      style: TextStyle(
                        color: context.colors.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.colors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$unlockedCount/$totalCount',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BadgesScreen()),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Tümü',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: context.colors.accent),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentBadges.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.outline.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 32, color: context.colors.textMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Henüz rozet kazanmadın. Uygulama kullanarak rozet aç!',
                        style: TextStyle(color: context.colors.textMedium, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recentBadges.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final badge = recentBadges[index];
                    final ub = badgeState.progressFor(badge.id);
                    final tierColor = _badgeTierColor(ub.currentTier);
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BadgesScreen()),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tierColor.withOpacity(0.15),
                              border: Border.all(color: tierColor, width: 2),
                            ),
                            child: Icon(
                              _badgeIcon(badge.iconName),
                              size: 24,
                              color: tierColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 60,
                            child: Text(
                              badge.nameTr,
                              style: TextStyle(
                                color: context.colors.textMedium,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _badgeTierColor(int tier) {
    switch (tier) {
      case 1: return const Color(0xFFCD7F32);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFFFD700);
      default: return Colors.grey;
    }
  }

  IconData _badgeIcon(String iconName) {
    const iconMap = <String, IconData>{
      'person_add': Icons.person_add,
      'verified': Icons.verified,
      'camera_alt': Icons.camera_alt,
      'visibility': Icons.visibility,
      'explore': Icons.explore,
      'casino': Icons.casino,
      'gps_fixed': Icons.gps_fixed,
      'local_fire_department': Icons.local_fire_department,
      'savings': Icons.savings,
      'shopping_cart': Icons.shopping_cart,
      'trending_up': Icons.trending_up,
      'emoji_events': Icons.emoji_events,
      'date_range': Icons.date_range,
      'loyalty': Icons.loyalty,
    };
    return iconMap[iconName] ?? Icons.military_tech;
  }
}
