import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_controller.dart';
import '../models/article.dart';
import '../models/article_detail.dart';
import '../models/news_category.dart';
import '../utils/image_proxy.dart';
import '../utils/time_format.dart';

class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({
    super.key,
    required this.article,
    required this.controller,
  });

  final Article article;
  final AppController controller;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Future<ArticleDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.fetchArticleDetail(widget.article);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceMatch = widget.controller.settings.sources
        .where((source) => source.id == widget.article.sourceId)
        .toList();
    final category = sourceMatch.isEmpty ? null : sourceMatch.first.category;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.article.sourceName),
        actions: [
          IconButton(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open original site',
          ),
        ],
      ),
      body: FutureBuilder<ArticleDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final detail = snapshot.data ?? _fallbackDetail();
          final content = detail.content ?? [];
          final imageUrl = _resolveImageUrl(detail.imageUrl ?? widget.article.imageUrl);
          final rawImage = detail.imageUrl ?? widget.article.imageUrl;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _HeroImage(url: imageUrl, fallbackUrl: rawImage),
              const SizedBox(height: 16),
              Text(
                detail.title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'Georgia',
                  fontFamilyFallback: const ['Times New Roman', 'serif'],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (category != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        category.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (category != null) const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      detail.sourceName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRelativeTime(detail.publishedAt ?? widget.article.publishedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (detail.excerpt != null && detail.excerpt!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  detail.excerpt!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.justify,
                ),
              ],
              const SizedBox(height: 18),
              if (content.isEmpty)
                Text(
                  'We could not extract the article text. Use the button below to read the original.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                )
              else
                ...content.map(
                  (paragraph) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      paragraph,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                      textAlign: TextAlign.justify,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open original site'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _resolveImageUrl(String? rawUrl) {
    return buildProxiedImageUrl(
          widget.controller.settings.proxyUrl,
          rawUrl,
          referer: widget.article.url,
        ) ??
        rawUrl;
  }

  ArticleDetail _fallbackDetail() {
    return ArticleDetail(
      url: widget.article.url,
      title: widget.article.title,
      sourceName: widget.article.sourceName,
      imageUrl: widget.article.imageUrl,
      excerpt: widget.article.excerpt,
      publishedAt: widget.article.publishedAt,
      author: widget.article.author,
      content: const [],
    );
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.article.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({
    required this.url,
    this.fallbackUrl,
    this.usingFallback = false,
  });

  final String? url;
  final String? fallbackUrl;
  final bool usingFallback;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return _fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) {
            if (!usingFallback &&
                fallbackUrl != null &&
                fallbackUrl!.isNotEmpty &&
                fallbackUrl != url) {
              return _HeroImage(
                url: fallbackUrl,
                fallbackUrl: null,
                usingFallback: true,
              );
            }
            return _fallback();
          },
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: const Color(0xFFE8EEF1),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1F2A), Color(0xFF0E7490)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.auto_stories_rounded, color: Colors.white70, size: 40),
      ),
    );
  }
}
