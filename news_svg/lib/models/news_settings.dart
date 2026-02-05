import 'news_category.dart';
import 'source_config.dart';

class NewsSettings {
  NewsSettings({
    required this.proxyUrl,
    required this.updateUrl,
    required this.sources,
    required this.themeMode,
    required this.textScale,
  });

  final String proxyUrl;
  final String updateUrl;
  final List<SourceConfig> sources;
  final String themeMode;
  final double textScale;

  NewsSettings copyWith({
    String? proxyUrl,
    String? updateUrl,
    List<SourceConfig>? sources,
    String? themeMode,
    double? textScale,
  }) {
    return NewsSettings(
      proxyUrl: proxyUrl ?? this.proxyUrl,
      updateUrl: updateUrl ?? this.updateUrl,
      sources: sources ?? this.sources,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'proxyUrl': proxyUrl,
      'updateUrl': updateUrl,
      'sources': sources.map((source) => source.toStorageJson()).toList(),
      'themeMode': themeMode,
      'textScale': textScale,
    };
  }

  factory NewsSettings.fromJson(Map<String, dynamic> json) {
    final sourcesRaw = json['sources'] as List<dynamic>? ?? [];
    return NewsSettings(
      proxyUrl: json['proxyUrl'] as String? ?? '',
      updateUrl: json['updateUrl'] as String? ?? '',
      sources: sourcesRaw
          .whereType<Map<String, dynamic>>()
          .map(SourceConfig.fromStorageJson)
          .toList(),
      themeMode: _normalizeThemeMode(json['themeMode'] as String?),
      textScale: _normalizeTextScale(json['textScale']),
    );
  }

  static NewsSettings defaults({required String proxyUrl}) {
    return NewsSettings(
      proxyUrl: proxyUrl,
      updateUrl: '',
      themeMode: 'system',
      textScale: 1.0,
      sources: [
        SourceConfig(
          id: 'iwnsvg',
          name: 'iWitness News',
          listUrl: 'https://www.iwnsvg.com/',
          baseUrl: 'https://www.iwnsvg.com',
          enabled: true,
          category: NewsCategory.local,
          articleUrlPattern: r'/\d{4}/\d{2}/\d{2}/',
        ),
        SourceConfig(
          id: 'onenews',
          name: 'One News SVG',
          listUrl: 'https://onenewsstvincent.com/',
          baseUrl: 'https://onenewsstvincent.com',
          enabled: true,
          category: NewsCategory.local,
          articleUrlPattern: r'/\d{4}/\d{2}/\d{2}/',
        ),
        SourceConfig(
          id: 'stvincenttimes',
          name: 'St. Vincent Times',
          listUrl: 'https://www.stvincenttimes.com/',
          baseUrl: 'https://www.stvincenttimes.com',
          enabled: true,
          category: NewsCategory.local,
        ),
        SourceConfig(
          id: 'searchlight',
          name: 'Searchlight SVG',
          listUrl: 'https://www.searchlight.vc/',
          baseUrl: 'https://www.searchlight.vc',
          enabled: true,
          category: NewsCategory.local,
        ),
        SourceConfig(
          id: 'guardian-tt',
          name: 'Trinidad Guardian',
          listUrl: 'https://www.guardian.co.tt/',
          baseUrl: 'https://www.guardian.co.tt',
          enabled: true,
          category: NewsCategory.regional,
        ),
        SourceConfig(
          id: 'trinidadexpress',
          name: 'Trinidad Express',
          listUrl: 'https://trinidadexpress.com/',
          baseUrl: 'https://trinidadexpress.com',
          enabled: true,
          category: NewsCategory.regional,
        ),
        SourceConfig(
          id: 'cnn',
          name: 'CNN',
          listUrl: 'https://edition.cnn.com/',
          baseUrl: 'https://edition.cnn.com',
          enabled: true,
          category: NewsCategory.international,
        ),
        SourceConfig(
          id: 'bbc',
          name: 'BBC',
          listUrl: 'https://www.bbc.com/',
          baseUrl: 'https://www.bbc.com',
          enabled: true,
          category: NewsCategory.international,
        ),
      ],
    );
  }

  static String _normalizeThemeMode(String? value) {
    switch (value) {
      case 'light':
      case 'dark':
      case 'system':
        return value!;
      default:
        return 'system';
    }
  }

  static double _normalizeTextScale(dynamic value) {
    final scale = value is num ? value.toDouble() : 1.0;
    return scale.clamp(0.9, 1.3);
  }
}
