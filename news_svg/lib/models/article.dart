class Article {
  Article({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceId,
    required this.sourceName,
    this.publishedAt,
    this.imageUrl,
    this.excerpt,
    this.preview,
    this.author,
  });

  final String id;
  final String title;
  final String url;
  final String sourceId;
  final String sourceName;
  final DateTime? publishedAt;
  final String? imageUrl;
  final String? excerpt;
  final String? preview;
  final String? author;

  factory Article.fromJson(Map<String, dynamic> json) {
    final publishedAtRaw = json['publishedAt'] as String?;
    return Article(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      url: json['url'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? 'Unknown Source',
      publishedAt: publishedAtRaw == null ? null : DateTime.tryParse(publishedAtRaw),
      imageUrl: json['imageUrl'] as String?,
      excerpt: json['excerpt'] as String?,
      preview: json['preview'] as String?,
      author: json['author'] as String?,
    );
  }
}
