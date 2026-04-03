import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notification_provider.dart';
import '../theme/app_theme.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined, 
            color: context.colors.textMedium,
          ),
          onPressed: () {
            // TODO: Open Notification Center Bottom Sheet
            _showNotificationSheet(context, ref);
          },
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.colors.error, // or a bright red/orange color
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  void _showNotificationSheet(BuildContext context, WidgetRef ref) {
    final notifications = ref.read(notificationProvider);
    
    // Mark them all as read when opening the sheet
    ref.read(notificationProvider.notifier).markAllAsRead();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            if (notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 60, color: context.colors.textMedium),
                    const SizedBox(height: 16),
                    Text('No notifications yet.', style: TextStyle(color: context.colors.textHigh)),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textHigh,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: context.colors.textMedium),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                ),
                Divider(height: 1, color: context.colors.surfaceContainerLow),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: context.colors.surfaceContainerLow,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      // Different icons based on type
                      IconData iconData = Icons.info_outline;
                      Color iconColor = context.colors.primary;
                      
                      if (n.type == 'GOAL') {
                        iconData = Icons.sports_soccer;
                        iconColor = context.colors.accent; // Maybe green/yellow flag
                      } else if (n.type == 'MATCH_START') {
                        iconData = Icons.access_time_filled;
                        iconColor = context.colors.primary;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: iconColor.withValues(alpha: 0.1),
                          child: Icon(iconData, color: iconColor, size: 20),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            color: n.isRead ? context.colors.textMedium : context.colors.textHigh,
                            fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            n.message,
                            style: TextStyle(color: context.colors.textMedium, fontSize: 13),
                          ),
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
