class Announcement {
  final String id;
  final String title;
  final String message;
  final String type;
  final String? actionUrl;
  final bool isActive;
  final DateTime createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.actionUrl,
    required this.isActive,
    required this.createdAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'],
      title: json['title'],
      message: json['message'],
      type: json['type'],
      actionUrl: json['action_url'],
      isActive: json['is_active'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
