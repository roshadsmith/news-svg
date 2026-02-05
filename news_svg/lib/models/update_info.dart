class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.build,
    this.notes,
  });

  final String version;
  final int? build;
  final String downloadUrl;
  final String? notes;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? json['latest'] ?? '').toString().trim();
    final downloadUrl =
        (json['apk_url'] ?? json['download_url'] ?? json['url'] ?? '')
            .toString()
            .trim();
    final buildValue =
        json['build'] ?? json['build_number'] ?? json['version_code'];
    final build = buildValue is num
        ? buildValue.toInt()
        : int.tryParse('$buildValue');
    final notes = json['notes']?.toString().trim();

    return UpdateInfo(
      version: version,
      downloadUrl: downloadUrl,
      build: build,
      notes: notes?.isEmpty == true ? null : notes,
    );
  }
}
