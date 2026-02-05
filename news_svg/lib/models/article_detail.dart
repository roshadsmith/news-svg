class ArticleDetail {
  ArticleDetail({
    required this.url,
    required this.title,
    required this.sourceName,
    this.imageUrl,
    this.excerpt,
    this.publishedAt,
    this.content,
    this.author,
  });

  final String url;
  final String title;
  final String sourceName;
  final String? imageUrl;
  final String? excerpt;
  final DateTime? publishedAt;
  final List<String>? content;
  final String? author;

  factory ArticleDetail.fromJson(Map<String, dynamic> json) {
    final publishedAtRaw = json['publishedAt'] as String?;
    final contentRaw = json['content'];

    return ArticleDetail(
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      sourceName: json['sourceName'] as String? ?? 'Source',
      imageUrl: json['imageUrl'] as String?,
      excerpt: json['excerpt'] as String?,
      publishedAt: publishedAtRaw == null ? null : DateTime.tryParse(publishedAtRaw),
      content: contentRaw is List
          ? contentRaw.whereType<String>().toList()
          : null,
      author: json['author'] as String?,
    );
  }
}
