import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_settings.dart';

class SettingsStore {
  static const _key = 'news_settings_v1';
  static const _proxyKey = 'news_proxy_url';
  static const _updateKey = 'news_update_url';
  static const _lastUpdateShownKey = 'news_last_update_shown';

  Future<NewsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = NewsSettings.defaults(proxyUrl: defaultProxyUrl());
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) {
      return fallback.copyWith(
        proxyUrl: defaultProxyUrl(),
        updateUrl: defaultUpdateUrl(),
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return fallback.copyWith(
          proxyUrl: defaultProxyUrl(),
          updateUrl: defaultUpdateUrl(),
        );
      }
      var settings = NewsSettings.fromJson(decoded);
      settings = settings.copyWith(
        proxyUrl: defaultProxyUrl(),
        updateUrl: defaultUpdateUrl(),
      );
      return settings;
    } catch (_) {
      return fallback.copyWith(
        proxyUrl: defaultProxyUrl(),
        updateUrl: defaultUpdateUrl(),
      );
    }
  }

  Future<void> save(NewsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(settings.toJson());
    await prefs.setString(_key, payload);
    await prefs.setString(_proxyKey, settings.proxyUrl);
    await prefs.setString(_updateKey, settings.updateUrl);
  }

  Future<String?> loadLastShownUpdateVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUpdateShownKey);
  }

  Future<void> saveLastShownUpdateVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUpdateShownKey, version);
  }
}

String defaultProxyUrl() {
  if (kIsWeb) {
    return 'https://server-rough-hill-9060.fly.dev';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'https://server-rough-hill-9060.fly.dev';
    default:
      return 'https://server-rough-hill-9060.fly.dev';
  }
}

String defaultUpdateUrl() {
  return 'https://raw.githubusercontent.com/roshadsmith/news-svg/main/version.json';
}
