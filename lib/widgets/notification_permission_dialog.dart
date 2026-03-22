import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/push_notification_service.dart';

class NotificationPermissionDialog extends ConsumerWidget {
  const NotificationPermissionDialog({super.key});

  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => const NotificationPermissionDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: Colors.transparent, // Transparent for custom shape layer
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 12),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Graphic Area
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      context.colors.primary,
                      context.colors.primary.withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -20,
                      right: -20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -40,
                      left: -20,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                    ),
                    // Main Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Content Area
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Canlı Skor ve Maç Uyarıları ⚽",
                    style: TextStyle(
                      fontSize: 22, 
                      fontWeight: FontWeight.w900, 
                      color: context.colors.textHigh,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Favori takımlarınızın bulunduğu maçlardaki golleri ve kritik istatistikleri eşzamanlı olarak alabilmeniz için cihaz bildirimlerinizin aktif olması gerekmektedir.\n\nİşleme devam ettiğinizde tarayıcınızın sol üst köşesinden (veya cihazınızda) açılacak olan sistem bilgilendirmesine 'İzin Ver' diyerek onaylamanız rica olunur.",
                    style: TextStyle(
                      fontSize: 14, 
                      color: context.colors.textMedium, 
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  
                  // Trust Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.surfaceContainer),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gpp_good_rounded, color: context.colors.primary, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Kullanıcı Gizliliği ve Bildirim Politikası\nYalnızca favoriye aldığınız içeriklerle ilgili anlık spor verileri iletilir. Doğrudan pazarlama veya tanıtım amaçlı (spam) bildirimler kesinlikle gönderilmez.",
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textLow,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            foregroundColor: context.colors.textMedium,
                          ),
                          child: const Text("Şimdi Değil", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context); // Close dialog first
                            // Trigger native OS prompt
                            await ref.read(pushNotificationServiceProvider).requestPermission();
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: context.colors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text("Onayla ve Devam Et", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
