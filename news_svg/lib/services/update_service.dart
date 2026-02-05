import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_info.dart';

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 12);

  Future<UpdateInfo?> checkForUpdate(String updateUrl) async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return null;

    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final info = UpdateInfo.fromJson(decoded);
    if (info.version.isEmpty || info.downloadUrl.isEmpty) return null;

    final package = await PackageInfo.fromPlatform();
    if (!_isNewer(info, package)) return null;

    return info;
  }

  bool _isNewer(UpdateInfo info, PackageInfo current) {
    final currentBuild = int.tryParse(current.buildNumber);
    if (info.build != null && currentBuild != null) {
      return info.build! > currentBuild;
    }
    return _compareVersions(info.version, current.version) > 0;
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final partsB = b.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = partsA.length > partsB.length
        ? partsA.length
        : partsB.length;
    for (var i = 0; i < length; i += 1) {
      final left = i < partsA.length ? partsA[i] : 0;
      final right = i < partsB.length ? partsB[i] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }
    return 0;
  }

  void dispose() {
    _client.close();
  }
}
