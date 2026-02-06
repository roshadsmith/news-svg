import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../controllers/app_controller.dart';
import '../models/article.dart';
import '../models/news_category.dart';
import '../screens/article_detail_screen.dart';
import '../utils/image_proxy.dart';
import '../widgets/article_card.dart';
import '../widgets/staggered_in.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onManageSources,
  });

  final AppController controller;
  final VoidCallback onManageSources;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _prefetchedBatches = {};
  _DateFilter _filter = _DateFilter.all;
  Set<NewsCategory> _regionFilters = {NewsCategory.local};
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController
      ..removeListener(_handleSearchChange)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchChange() {
    final value = _searchController.text.trim();
    if (value == _query) return;
    setState(() => _query = value);
  }

  Future<void> _openSearchOverlay() async {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _SearchOverlay(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onClear: () => _searchController.clear(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabledSources = widget.controller.settings.sources
        .where((source) => source.enabled)
        .toList();
    final categories = {
      for (final source in widget.controller.settings.sources)
        source.id: source.category,
    };

    return Stack(
      children: [
        const _Background(),
        SafeArea(
          child: Column(
            children: [
              _HeaderBar(onSearch: _openSearchOverlay),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Centered(
                  child: Column(
                    children: [
                      if (_query.isNotEmpty) ...[
                        _ActiveSearchBanner(
                          query: _query,
                          onClear: () => _searchController.clear(),
                          onEdit: _openSearchOverlay,
                        ),
                        const SizedBox(height: 10),
                      ],
                      _FilterBar(
                        filter: _filter,
                        onChanged: (value) => setState(() => _filter = value),
                      ),
                      const SizedBox(height: 8),
                      _RegionFilterBar(
                        selected: _regionFilters,
                        onChanged: (value) =>
                            setState(() => _regionFilters = {...value}),
                      ),
                      if (widget.controller.hasNewContent) ...[
                        const SizedBox(height: 10),
                        _NewContentBanner(onRefresh: widget.controller.refresh),
                      ],
                    ],
                  ),
                ),
              ),
              if (enabledSources.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Centered(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'No sources enabled yet.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onManageSources,
                          child: const Text('Manage sources'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              if (widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: _Centered(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'We could not refresh right now. Check your proxy or try again.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (widget.controller.loading &&
                        widget.controller.articles.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (widget.controller.articles.isEmpty) {
                      final pendingRefresh =
                          widget.controller.loading ||
                          widget.controller.sourceRefreshPending;
                      return RefreshIndicator(
                        onRefresh: widget.controller.refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.2,
                            ),
                            if (pendingRefresh) ...[
                              const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading stories…',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ] else
                              Text(
                                'No stories yet. Pull down to refresh or add a new source.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      );
                    }

                    final visibleArticles = _applyFilters(
                      widget.controller.articles,
                      _filter,
                      _regionFilters,
                      _query,
                      categories,
                    );

                    if (visibleArticles.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: widget.controller.refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(24),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.2,
                            ),
                            Text(
                              'No stories match your search and filters.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: widget.controller.refresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                        itemCount: visibleArticles.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final lastUpdated = widget.controller.lastUpdated;
                            final lastUpdatedText = lastUpdated == null
                                ? 'Never refreshed'
                                : 'Updated ${TimeOfDay.fromDateTime(lastUpdated).format(context)}';
                            final crawlerRefresh =
                                widget.controller.crawlerLastRefresh;
                            final crawlerText = crawlerRefresh == null
                                ? 'Crawler warming up'
                                : 'Crawler updated ${TimeOfDay.fromDateTime(crawlerRefresh).format(context)}';
                            return _Centered(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  children: [
                                    Text(
                                      lastUpdatedText,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      crawlerText,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.45),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final articleIndex = index - 1;
                          _prefetchImages(
                            context,
                            articleIndex,
                            visibleArticles,
                          );

                          final article = visibleArticles[articleIndex];
                          final proxiedImage = _resolveImageUrl(article);
                          final rawImage = article.imageUrl;
                          final category = categories[article.sourceId];

                          return _Centered(
                            child: StaggeredFadeIn(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: ArticleCard(
                                  article: article,
                                  category: category,
                                  imageUrl: proxiedImage,
                                  fallbackImageUrl: rawImage,
                                  onTap: () => _openArticle(context, article),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _prefetchImages(
    BuildContext context,
    int articleIndex,
    List<Article> articles,
  ) {
    if (articleIndex == 0) {
      _prefetchBatch(context, 0, articles);
      return;
    }

    if (articleIndex >= 8 && (articleIndex - 8) % 10 == 0) {
      final batch = ((articleIndex - 8) ~/ 10) + 1;
      _prefetchBatch(context, batch, articles);
    }
  }

  void _prefetchBatch(BuildContext context, int batch, List<Article> articles) {
    if (kIsWeb) return;
    if (_prefetchedBatches.contains(batch)) return;
    _prefetchedBatches.add(batch);

    final start = batch * 10;
    final end = (start + 10).clamp(0, articles.length);
    for (var i = start; i < end; i += 1) {
      final url = _resolveImageUrl(articles[i]);
      if (url == null || url.isEmpty) continue;
      precacheImage(NetworkImage(url), context).catchError((_) {
        // Ignore prefetch decode/network failures; card-level fallback handles rendering.
      });
    }
  }

  String? _resolveImageUrl(Article article) {
    final proxyUrl = widget.controller.settings.proxyUrl;
    return buildProxiedImageUrl(
          proxyUrl,
          article.imageUrl,
          referer: article.url,
        ) ??
        article.imageUrl;
  }

  void _openArticle(BuildContext context, Article article) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleDetailScreen(
          article: article,
          controller: widget.controller,
        ),
      ),
    );
  }
}

enum _DateFilter { today, yesterday, lastWeek, all }

List<Article> _applyFilters(
  List<Article> articles,
  _DateFilter dateFilter,
  Set<NewsCategory> regionFilters,
  String query,
  Map<String, NewsCategory> categories,
) {
  if (articles.isEmpty) return articles;

  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfTomorrow = startOfToday.add(const Duration(days: 1));
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  final startOfLastWeek = startOfToday.subtract(const Duration(days: 7));
  final normalizedQuery = query.trim().toLowerCase();

  bool matchesCategory(Article article) {
    if (regionFilters.isEmpty) return false;
    final category = categories[article.sourceId];
    if (category == null) return false;
    return regionFilters.contains(category);
  }

  bool matchesQuery(Article article) {
    if (normalizedQuery.isEmpty) return true;
    final haystack = [
      article.title,
      article.preview,
      article.excerpt,
      article.sourceName,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(normalizedQuery);
  }

  bool isOnOrAfter(DateTime date, DateTime start) {
    return date.isAtSameMomentAs(start) || date.isAfter(start);
  }

  return articles.where((article) {
    if (!matchesCategory(article)) return false;
    if (!matchesQuery(article)) return false;
    final date = article.publishedAt;
    if (date == null) return dateFilter == _DateFilter.all;
    final local = date.toLocal();
    switch (dateFilter) {
      case _DateFilter.today:
        return isOnOrAfter(local, startOfToday) &&
            local.isBefore(startOfTomorrow);
      case _DateFilter.yesterday:
        return isOnOrAfter(local, startOfYesterday) &&
            local.isBefore(startOfToday);
      case _DateFilter.lastWeek:
        return isOnOrAfter(local, startOfLastWeek) &&
            local.isBefore(startOfToday);
      case _DateFilter.all:
        return true;
    }
  }).toList();
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onChanged});

  final _DateFilter filter;
  final ValueChanged<_DateFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final fontSize = compact ? 11.5 : 12.5;
        final verticalPadding = compact ? 6.0 : 8.0;
        final horizontalPadding = compact ? 6.0 : 10.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: _FilterButton(
                label: 'All',
                selected: filter == _DateFilter.all,
                onTap: () => onChanged(_DateFilter.all),
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterButton(
                label: 'Today',
                selected: filter == _DateFilter.today,
                onTap: () => onChanged(_DateFilter.today),
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterButton(
                label: 'Yesterday',
                selected: filter == _DateFilter.yesterday,
                onTap: () => onChanged(_DateFilter.yesterday),
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterButton(
                label: 'Last week',
                selected: filter == _DateFilter.lastWeek,
                onTap: () => onChanged(_DateFilter.lastWeek),
                fontSize: fontSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RegionFilterBar extends StatelessWidget {
  const _RegionFilterBar({required this.selected, required this.onChanged});

  final Set<NewsCategory> selected;
  final ValueChanged<Set<NewsCategory>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _buildLabel(selected);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final fontSize = compact ? 12.0 : 13.0;
        final verticalPadding = compact ? 8.0 : 10.0;
        final horizontalPadding = compact ? 10.0 : 12.0;

        return Row(
          children: [
            Expanded(
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final result =
                        await showModalBottomSheet<Set<NewsCategory>>(
                          context: context,
                          backgroundColor: theme.colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          builder: (_) =>
                              _RegionPickerSheet(selected: selected),
                        );
                    if (result != null) {
                      onChanged(result);
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.public, size: compact ? 16 : 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _buildLabel(Set<NewsCategory> selected) {
    if (selected.isEmpty) {
      return 'Regions: none';
    }
    final ordered = [
      NewsCategory.local,
      NewsCategory.regional,
      NewsCategory.international,
    ];
    final labels = ordered.where(selected.contains).map((c) {
      switch (c) {
        case NewsCategory.local:
          return 'Local News';
        case NewsCategory.regional:
          return 'Regional News';
        case NewsCategory.international:
          return 'International News';
      }
    }).toList();
    return 'Regions: ${labels.join(', ')}';
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.fontSize,
    required this.horizontalPadding,
    required this.verticalPadding,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double fontSize;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : theme.colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionPickerSheet extends StatefulWidget {
  const _RegionPickerSheet({required this.selected});

  final Set<NewsCategory> selected;

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  late Set<NewsCategory> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Region filters',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose which regions appear in your feed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          _RegionOption(
            label: 'Local News',
            value: NewsCategory.local,
            selected: _selected.contains(NewsCategory.local),
            onChanged: _toggle,
          ),
          _RegionOption(
            label: 'Regional News',
            value: NewsCategory.regional,
            selected: _selected.contains(NewsCategory.regional),
            onChanged: _toggle,
          ),
          _RegionOption(
            label: 'International News',
            value: NewsCategory.international,
            selected: _selected.contains(NewsCategory.international),
            onChanged: _toggle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _selected = {
                    NewsCategory.local,
                    NewsCategory.regional,
                    NewsCategory.international,
                  };
                }),
                child: const Text('Select all'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggle(NewsCategory category, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(category);
      } else {
        _selected.remove(category);
      }
    });
  }
}

class _RegionOption extends StatelessWidget {
  const _RegionOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final NewsCategory value;
  final bool selected;
  final void Function(NewsCategory, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: (checked) => onChanged(value, checked ?? false),
      title: Text(label),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _ActiveSearchBanner extends StatelessWidget {
  const _ActiveSearchBanner({
    required this.query,
    required this.onClear,
    required this.onEdit,
  });

  final String query;
  final VoidCallback onClear;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search: $query',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewContentBanner extends StatelessWidget {
  const _NewContentBanner({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'New stories available.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search headlines, sources, topics',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close),
                tooltip: 'Clear search',
              ),
      ),
      style: theme.textTheme.bodyMedium,
    );
  }
}

class _SearchOverlay extends StatefulWidget {
  const _SearchOverlay({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Search',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SearchBar(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onClear: widget.onClear,
            ),
            const SizedBox(height: 10),
            Text(
              'Results update as you type.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: _Centered(
          child: Row(
            children: [
              Image.asset('assets/images/logo.png', width: 36, height: 36),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: 0.4,
                          fontFamily: 'Georgia',
                          fontFamilyFallback: const [
                            'Times New Roman',
                            'serif',
                          ],
                        ),
                        children: [
                          const TextSpan(text: 'news'),
                          TextSpan(
                            text: '.svg',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Clean headlines, zero distractions.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: child,
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0xFF0B0F12), Color(0xFF141A20)]
              : const [Color(0xFFF9F9F9), Color(0xFFF1F2F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(
                  0xFFB80000,
                ).withValues(alpha: dark ? 0.18 : 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(
                  0xFF1F2933,
                ).withValues(alpha: dark ? 0.2 : 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
