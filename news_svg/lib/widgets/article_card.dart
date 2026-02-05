import 'package:flutter/material.dart';

import '../models/article.dart';
import '../models/news_category.dart';
import '../utils/time_format.dart';

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.imageUrl,
    required this.fallbackImageUrl,
    this.category,
  });

  final Article article;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? fallbackImageUrl;
  final NewsCategory? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroImage(
              url: imageUrl,
              fallbackUrl: fallbackImageUrl,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (category != null)
                            _Badge(
                              label: category!.label,
                              background: theme.colorScheme.secondary.withValues(alpha: 0.15),
                              foreground: theme.colorScheme.secondary,
                            ),
                          _Badge(
                            label: article.sourceName,
                            background: theme.colorScheme.primary.withValues(alpha: 0.08),
                            foreground: theme.colorScheme.primary,
                          ),
                          Text(
                            formatRelativeTime(article.publishedAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              const SizedBox(height: 10),
              Text(
                article.title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  height: 1.25,
                  fontFamily: 'Georgia',
                  fontFamilyFallback: const ['Times New Roman', 'serif'],
                ),
              ),
                  if ((article.preview ?? article.excerpt)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Text(
                      article.preview ?? article.excerpt ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        height: 1.45,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        gradient: LinearGradient(
          colors: [Color(0xFF0B1F2A), Color(0xFF0E7490)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      height: 170,
      child: const Center(
        child: Icon(Icons.auto_stories_rounded, color: Colors.white70, size: 40),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
