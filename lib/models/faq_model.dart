class FaqCategory {
  final String id;
  final String name;
  final String? icon;

  FaqCategory({
    required this.id,
    required this.name,
    this.icon,
  });

  factory FaqCategory.fromJson(Map<String, dynamic> json) {
    return FaqCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
    );
  }
}

class FaqArticle {
  final String id;
  final String categoryId;
  final String question;
  final String answer;

  FaqArticle({
    required this.id,
    required this.categoryId,
    required this.question,
    required this.answer,
  });

  factory FaqArticle.fromJson(Map<String, dynamic> json) {
    return FaqArticle(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
    );
  }
}
