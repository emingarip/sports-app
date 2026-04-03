import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../data/repositories/support/faq_repository.dart';
import '../providers/support_providers.dart';
import 'private_chat_screen.dart';

class HelpCenterScreen extends ConsumerWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faqState = ref.watch(faqProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surfaceContainerHighest,
        elevation: 0,
        title: Text(
          'Yardım Merkezi',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: context.colors.textHigh,
                fontWeight: FontWeight.bold,
              ),
        ),
        iconTheme: IconThemeData(color: context.colors.textHigh),
      ),
      body: faqState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: context.colors.error, size: 48),
              const SizedBox(height: 16),
              Text(
                'Bir hata oluştu.',
                style: TextStyle(color: context.colors.textMedium),
              ),
            ],
          ),
        ),
        data: (categoriesWithArticles) {
          if (categoriesWithArticles.isEmpty) {
            return Center(
              child: Text(
                'Henüz makale bulunmuyor.',
                style: TextStyle(color: context.colors.textMedium),
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Sıkça Sorulan Sorular',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: context.colors.textHigh,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = categoriesWithArticles[index];
                      // Match icon string to IconData roughly
                      IconData getIcon(String? iconStr) {
                        switch (iconStr) {
                          case 'person': return Icons.person;
                          case 'workspace_premium': return Icons.workspace_premium;
                          case 'sports_soccer': return Icons.sports_soccer;
                          case 'build': return Icons.build;
                          default: return Icons.help_outline;
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 24.0),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: context.colors.outline.withAlpha(25),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.colors.primaryContainer.withAlpha(30),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      getIcon(group.category.icon),
                                      color: context.colors.primaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      group.category.name,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            color: context.colors.textHigh,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            ...group.articles.map((article) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                ),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  childrenPadding: const EdgeInsets.only(
                                    left: 20, right: 20, bottom: 20,
                                  ),
                                  iconColor: context.colors.primaryContainer,
                                  collapsedIconColor: context.colors.textMedium,
                                  title: Text(
                                    article.question,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          color: context.colors.textHigh,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        article.answer,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: context.colors.textMedium,
                                              height: 1.5,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    },
                    childCount: categoriesWithArticles.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: context.colors.outline.withAlpha(25),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Hala yardıma mı ihtiyacınız var?',
                          style: TextStyle(
                            color: context.colors.textHigh,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () async {
                             // Show loading
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(child: CircularProgressIndicator()),
                            );

                            try {
                              final supportData = await ref.read(supportRepositoryProvider).prepareSupportRoom();
                              
                              if (context.mounted) {
                                Navigator.pop(context); // Remove loading
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PrivateChatScreen(
                                      roomId: supportData['room_id'],
                                      otherUserId: supportData['admin_id'],
                                      otherUsername: 'Canlı Destek',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                Navigator.pop(context); // Remove loading
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Hata: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.headset_mic_outlined),
                          label: const Text('Destek Talebi Oluştur'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.primaryContainer,
                            side: BorderSide(color: context.colors.primaryContainer),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 48),
              ),
            ],
          );
        },
      ),
    );
  }
}
