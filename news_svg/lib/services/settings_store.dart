import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_settings.dart';

class SettingsStore {
  static const _key = 'news_settings_v1';
  static const _proxyKey = 'news_proxy_url';

  Future<NewsSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = NewsSettings.defaults(proxyUrl: defaultProxyUrl());
    final raw = prefs.getString(_key);
    final storedProxy = prefs.getString(_proxyKey);

    if (raw == null || raw.isEmpty) {
      if (storedProxy != null && storedProxy.trim().isNotEmpty) {
        return fallback.copyWith(proxyUrl: storedProxy);
      }
      return fallback;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (storedProxy != null && storedProxy.trim().isNotEmpty) {
          return fallback.copyWith(proxyUrl: storedProxy);
        }
        return fallback;
      }
      var settings = NewsSettings.fromJson(decoded);
      if (settings.proxyUrl.trim().isEmpty) {
        settings = settings.copyWith(proxyUrl: storedProxy ?? fallback.proxyUrl);
      } else if (storedProxy != null &&
          storedProxy.trim().isNotEmpty &&
          storedProxy != settings.proxyUrl) {
        settings = settings.copyWith(proxyUrl: storedProxy);
      }
      return settings;
    } catch (_) {
      if (storedProxy != null && storedProxy.trim().isNotEmpty) {
        return fallback.copyWith(proxyUrl: storedProxy);
      }
      return fallback;
    }
  }

  Future<void> save(NewsSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(settings.toJson());
    await prefs.setString(_key, payload);
    await prefs.setString(_proxyKey, settings.proxyUrl);
  }
}

String defaultProxyUrl() {
  if (kIsWeb) {
    return 'http://localhost:4000';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:4000';
    default:
      return 'http://localhost:4000';
  }
}
