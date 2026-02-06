import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/article.dart';
import '../models/article_detail.dart';
import '../models/news_category.dart';
import '../models/news_settings.dart';
import '../models/source_config.dart';
import '../models/status_info.dart';
import '../models/update_info.dart';
import '../services/news_api.dart';
import '../services/settings_store.dart';
import '../services/update_service.dart';
import '../utils/slugify.dart';

class AppController extends ChangeNotifier {
  AppController({
    required NewsApi api,
    required SettingsStore settingsStore,
    UpdateService? updateService,
  }) : _api = api,
       _settingsStore = settingsStore,
       _updateService = updateService ?? UpdateService();

  final NewsApi _api;
  final SettingsStore _settingsStore;
  final UpdateService _updateService;
  final Map<String, ArticleDetail> _detailCache = {};
  static const int _batchSize = 4;
  static const Duration _statusInterval = Duration(seconds: 45);

  NewsSettings _settings = NewsSettings.defaults(proxyUrl: defaultProxyUrl());
  List<Article> _articles = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;
  bool _initialized = false;
  bool _sourceRefreshPending = false;
  UpdateInfo? _updateInfo;
  String? _lastShownUpdateVersion;
  Timer? _statusTimer;
  DateTime? _lastContentSeenAt;
  DateTime? _crawlerLastRefresh;
  bool _hasNewContent = false;

  NewsSettings get settings => _settings;
  List<Article> get articles => _articles;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get initialized => _initialized;
  bool get sourceRefreshPending => _sourceRefreshPending;
  UpdateInfo? get updateInfo => _updateInfo;
  DateTime? get crawlerLastRefresh => _crawlerLastRefresh;
  bool get hasNewContent => _hasNewContent;

  Future<ArticleDetail> fetchArticleDetail(Article article) async {
    final cached = _detailCache[article.url];
    if (cached != null) {
      return cached;
    }

    final detail = await _api.fetchArticleDetail(
      proxyUrl: _settings.proxyUrl,
      url: article.url,
      sourceName: article.sourceName,
    );
    _detailCache[article.url] = detail;
    return detail;
  }

  Future<void> initialize() async {
    _settings = await _settingsStore.load();
    _lastShownUpdateVersion = await _settingsStore.loadLastShownUpdateVersion();
    _initialized = true;
    notifyListeners();
    unawaited(checkForUpdate());
    _startStatusPolling();
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _registerSources();
      final enabledSources = _settings.sources
          .where((source) => source.enabled)
          .toList();
      if (enabledSources.isEmpty) {
        _articles = [];
        _lastUpdated = DateTime.now();
        _sourceRefreshPending = false;
        _hasNewContent = false;
        return;
      }
      final merged = <Article>[];
      final seen = <String>{};
      final batches = _chunkSources(enabledSources, _batchSize);

      for (final batch in batches) {
        try {
          final batchItems = await _api.fetchArticles(
            proxyUrl: _settings.proxyUrl,
            sources: batch,
          );
          for (final article in batchItems) {
            if (seen.add(article.url)) {
              merged.add(article);
            }
          }
          merged.sort((a, b) {
            final aDate =
                a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          _articles = List<Article>.from(merged);
          _lastUpdated = DateTime.now();
          _lastContentSeenAt = _computeLatestFromArticles(_articles);
          _hasNewContent = false;
          notifyListeners();
        } catch (error) {
          _error ??= error.toString();
        }
      }
      _lastUpdated = DateTime.now();
      _lastContentSeenAt = _computeLatestFromArticles(_articles);
      _hasNewContent = false;
      _sourceRefreshPending = false;
    } catch (error) {
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _api.dispose();
    _updateService.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> updateProxyUrl(String proxyUrl) async {
    _settings = _settings.copyWith(proxyUrl: proxyUrl);
    await _settingsStore.save(_settings);
    notifyListeners();
    await refresh();
  }

  Future<void> updateUpdateUrl(String updateUrl) async {
    _settings = _settings.copyWith(updateUrl: updateUrl);
    await _settingsStore.save(_settings);
    notifyListeners();
    unawaited(checkForUpdate());
  }

  Future<void> updateThemeMode(String mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  Future<void> updateTextScale(double scale) async {
    final normalized = scale.clamp(0.9, 1.3);
    _settings = _settings.copyWith(textScale: normalized);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  Future<void> toggleSource(String id, bool enabled) async {
    final updatedSources = _settings.sources
        .map(
          (source) =>
              source.id == id ? source.copyWith(enabled: enabled) : source,
        )
        .toList();
    _settings = _settings.copyWith(sources: updatedSources);
    await _settingsStore.save(_settings);
    _sourceRefreshPending = true;
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    final updatedSources = _settings.sources
        .where((source) => source.id != id)
        .toList();
    _settings = _settings.copyWith(sources: updatedSources);
    await _settingsStore.save(_settings);
    _sourceRefreshPending = true;
    notifyListeners();
  }

  Future<void> addSource({
    required String name,
    required String listUrl,
    required String baseUrl,
    String? articleUrlPattern,
    NewsCategory category = NewsCategory.local,
    bool enabled = true,
  }) async {
    final idBase = _deriveId(name, listUrl);
    var id = idBase;
    var index = 2;
    final existingIds = _settings.sources.map((source) => source.id).toSet();
    while (existingIds.contains(id)) {
      id = '$idBase-$index';
      index += 1;
    }

    final newSource = SourceConfig.create(
      id: id,
      name: name,
      listUrl: listUrl,
      baseUrl: baseUrl,
      enabled: enabled,
      category: category,
      articleUrlPattern: articleUrlPattern,
    );

    final updatedSources = [..._settings.sources, newSource];
    _settings = _settings.copyWith(sources: updatedSources);
    await _settingsStore.save(_settings);
    _sourceRefreshPending = true;
    notifyListeners();
  }

  Future<void> refreshIfNeeded() async {
    if (!_sourceRefreshPending) return;
    await refresh();
  }

  Future<void> _registerSources() async {
    try {
      await _api.registerSources(
        proxyUrl: _settings.proxyUrl,
        sources: _settings.sources,
      );
    } catch (_) {
      // Ignore registration errors.
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(_statusInterval, (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    if (_loading) return;
    final ids = _settings.sources
        .where((source) => source.enabled)
        .map((source) => source.id)
        .toList();
    if (ids.isEmpty) return;
    try {
      final status = await _api.fetchStatus(
        proxyUrl: _settings.proxyUrl,
        sourceIds: ids,
      );
      if (status == null) return;
      _crawlerLastRefresh = status.lastRefresh;
      final latest = status.latest;
      if (latest != null) {
        final seen = _lastContentSeenAt;
        if (seen == null || latest.isAfter(seen)) {
          _hasNewContent = true;
        }
      }
      notifyListeners();
    } catch (_) {
      // Ignore status errors.
    }
  }

  DateTime? _computeLatestFromArticles(List<Article> items) {
    DateTime? latest;
    for (final article in items) {
      final date = article.publishedAt;
      if (date == null) continue;
      if (latest == null || date.isAfter(latest)) {
        latest = date;
      }
    }
    return latest ?? DateTime.now();
  }

  Future<void> checkForUpdate() async {
    if (kIsWeb) {
      _updateInfo = null;
      notifyListeners();
      return;
    }
    final updateUrl = _settings.updateUrl.trim();
    if (updateUrl.isEmpty) {
      _updateInfo = null;
      notifyListeners();
      return;
    }
    try {
      final info = await _updateService.checkForUpdate(updateUrl);
      _updateInfo = info;
    } catch (_) {
      _updateInfo = null;
    }
    notifyListeners();
  }

  bool shouldShowUpdatePrompt() {
    if (_updateInfo == null) return false;
    return _lastShownUpdateVersion != _updateInfo!.version;
  }

  Future<void> markUpdatePromptShown() async {
    if (_updateInfo == null) return;
    _lastShownUpdateVersion = _updateInfo!.version;
    await _settingsStore.saveLastShownUpdateVersion(_lastShownUpdateVersion!);
  }

  Future<void> updateSourceCategory(String id, NewsCategory category) async {
    final updatedSources = _settings.sources
        .map(
          (source) =>
              source.id == id ? source.copyWith(category: category) : source,
        )
        .toList();
    _settings = _settings.copyWith(sources: updatedSources);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  List<List<SourceConfig>> _chunkSources(List<SourceConfig> sources, int size) {
    final chunks = <List<SourceConfig>>[];
    for (var i = 0; i < sources.length; i += size) {
      final end = (i + size).clamp(0, sources.length);
      chunks.add(sources.sublist(i, end));
    }
    return chunks;
  }

  String _deriveId(String name, String listUrl) {
    final host = Uri.tryParse(listUrl)?.host;
    if (host != null && host.isNotEmpty) {
      final cleanHost = host.replaceAll('www.', '');
      return slugify(cleanHost);
    }
    return slugify(name.isNotEmpty ? name : 'source');
  }
}
