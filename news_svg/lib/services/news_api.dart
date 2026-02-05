import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/article.dart';
import '../models/article_detail.dart';
import '../models/source_config.dart';

class NewsApi {
  NewsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 60);

  Future<List<Article>> fetchArticles({
    required String proxyUrl,
    required List<SourceConfig> sources,
  }) async {
    final uri = _resolve(proxyUrl, 'api/news');
    final body = jsonEncode({
      'sources': sources.map((source) => source.toApiJson()).toList(),
    });

    final response = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Proxy error (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from proxy');
    }

    final items = decoded['items'];
    if (items is! List) {
      return [];
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(Article.fromJson)
        .toList();
  }

  Future<ArticleDetail> fetchArticleDetail({
    required String proxyUrl,
    required String url,
    required String sourceName,
  }) async {
    final uri = _resolve(proxyUrl, 'api/article');
    final body = jsonEncode({'url': url});

    final response = await _client
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Proxy error (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response from proxy');
    }

    final article = decoded['article'];
    if (article is! Map<String, dynamic>) {
      throw Exception('Missing article detail');
    }

    final detail = ArticleDetail.fromJson(article);
    return ArticleDetail(
      url: detail.url.isEmpty ? url : detail.url,
      title: detail.title,
      sourceName: sourceName,
      imageUrl: detail.imageUrl,
      excerpt: detail.excerpt,
      publishedAt: detail.publishedAt,
      content: detail.content,
      author: detail.author,
    );
  }

  Uri _resolve(String baseUrl, String path) {
    final normalized = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalized).resolve(path);
  }

  void dispose() {
    _client.close();
  }
}
