import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/announcement.dart';
import '../services/announcement_service.dart';
import '../theme/app_theme.dart';

class GlobalAnnouncementList extends ConsumerWidget {
  const GlobalAnnouncementList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(announcementProvider);

    if (state.isLoading || state.visibleAnnouncements.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: state.visibleAnnouncements
          .map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GlobalAnnouncementCard(announcement: a),
              ))
          .toList(),
    );
  }
}

class GlobalAnnouncementCard extends ConsumerWidget {
  final Announcement announcement;

  const GlobalAnnouncementCard({Key? key, required this.announcement}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Color getAccentColor() {
      switch (announcement.type) {
        case 'info':
          return Colors.blueAccent;
        case 'warning':
          return Colors.orangeAccent;
        case 'success':
          return Colors.greenAccent;
        case 'event':
          return Colors.purpleAccent;
        default:
          return Colors.blueAccent;
      }
    }

    IconData getIcon() {
      switch (announcement.type) {
        case 'info':
          return Icons.info_outline;
        case 'warning':
          return Icons.warning_amber_rounded;
        case 'success':
          return Icons.check_circle_outline;
        case 'event':
          return Icons.campaign_rounded;
        default:
          return Icons.notifications_none;
      }
    }

    final accentColor = getAccentColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.surface.withOpacity(0.6),
              border: Border.all(
                color: accentColor.withOpacity(0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top accent line
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.8),
                          accentColor.withOpacity(0.2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          getIcon(),
                          color: accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              announcement.title,
                              style: TextStyle(
                                color: context.colors.textHigh,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              announcement.message,
                              style: TextStyle(
                                color: context.colors.textHigh.withOpacity(0.8),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            if (announcement.actionUrl != null && announcement.actionUrl!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () async {
                                  final uri = Uri.parse(announcement.actionUrl!);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'İncele',
                                        style: TextStyle(
                                          color: accentColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        color: accentColor,
                                        size: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Close button
                      GestureDetector(
                        onTap: () {
                          ref.read(announcementProvider.notifier).dismissAnnouncement(announcement.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.colors.surface.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: context.colors.textHigh.withOpacity(0.5),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
