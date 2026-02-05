import 'news_category.dart';

class SourceConfig {
  SourceConfig({
    required this.id,
    required this.name,
    required this.listUrl,
    required this.baseUrl,
    required this.enabled,
    required this.category,
    this.articleUrlPattern,
  });

  final String id;
  final String name;
  final String listUrl;
  final String baseUrl;
  final bool enabled;
  final NewsCategory category;
  final String? articleUrlPattern;

  SourceConfig copyWith({
    String? id,
    String? name,
    String? listUrl,
    String? baseUrl,
    bool? enabled,
    NewsCategory? category,
    String? articleUrlPattern,
  }) {
    return SourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      listUrl: listUrl ?? this.listUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      category: category ?? this.category,
      articleUrlPattern: articleUrlPattern ?? this.articleUrlPattern,
    );
  }

  Map<String, dynamic> toStorageJson() {
    return {
      'id': id,
      'name': name,
      'listUrl': listUrl,
      'baseUrl': baseUrl,
      'enabled': enabled,
      'category': category.storageKey,
      'articleUrlPattern': articleUrlPattern,
    };
  }

  Map<String, dynamic> toApiJson() {
    return {
      'id': id,
      'name': name,
      'listUrl': listUrl,
      'baseUrl': baseUrl,
      if (articleUrlPattern != null && articleUrlPattern!.trim().isNotEmpty)
        'articleUrlPatterns': [articleUrlPattern],
    };
  }

  factory SourceConfig.fromStorageJson(Map<String, dynamic> json) {
    return SourceConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Source',
      listUrl: json['listUrl'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      category: newsCategoryFromStorage(json['category'] as String?),
      articleUrlPattern: json['articleUrlPattern'] as String?,
    );
  }

  static SourceConfig create({
    required String id,
    required String name,
    required String listUrl,
    required String baseUrl,
    bool enabled = true,
    NewsCategory category = NewsCategory.local,
    String? articleUrlPattern,
  }) {
    return SourceConfig(
      id: id,
      name: name,
      listUrl: listUrl,
      baseUrl: baseUrl,
      enabled: enabled,
      category: category,
      articleUrlPattern: articleUrlPattern,
    );
  }
}
