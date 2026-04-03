import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/faq_model.dart';
import 'package:flutter/foundation.dart' show debugPrint;

final faqRepositoryProvider = Provider((ref) => FaqRepository());

// We use FutureProvider to easily fetch and cache the FAQs
final faqProvider = FutureProvider<List<FaqCategoryWithArticles>>((ref) async {
  final repo = ref.watch(faqRepositoryProvider);
  return await repo.getFaqs();
});

class FaqCategoryWithArticles {
  final FaqCategory category;
  final List<FaqArticle> articles;

  FaqCategoryWithArticles({required this.category, required this.articles});
}

class FaqRepository {
  final _client = Supabase.instance.client;

  Future<List<FaqCategoryWithArticles>> getFaqs() async {
    try {
      // 1. Fetch categories
      final categoriesRes = await _client
          .from('faq_categories')
          .select()
          .order('sort_order', ascending: true);

      final categories = (categoriesRes as List)
          .map((c) => FaqCategory.fromJson(c))
          .toList();

      if (categories.isEmpty) return [];

      // 2. Fetch published articles
      final articlesRes = await _client
          .from('faq_articles')
          .select()
          .eq('is_published', true)
          .order('sort_order', ascending: true);

      final articles = (articlesRes as List)
          .map((a) => FaqArticle.fromJson(a))
          .toList();

      // 3. Group articles by category
      return categories.map((cat) {
        final catArticles = articles.where((a) => a.categoryId == cat.id).toList();
        return FaqCategoryWithArticles(category: cat, articles: catArticles);
      }).where((element) => element.articles.isNotEmpty).toList();

    } catch (e) {
      debugPrint('Error fetching FAQs: $e');
      return [];
    }
  }
}
