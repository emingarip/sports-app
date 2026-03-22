class League {
  final String id;
  final String name;
  final String logoUrl;
  final int tier; // 1 = highest priority

  League({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.tier = 2,
  });
}
