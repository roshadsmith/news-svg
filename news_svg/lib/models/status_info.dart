class StatusInfo {
  StatusInfo({required this.latest, required this.lastRefresh});

  final DateTime? latest;
  final DateTime? lastRefresh;

  factory StatusInfo.fromJson(Map<String, dynamic> json) {
    final latestRaw = json['latest'];
    final refreshRaw = json['lastRefresh'];
    return StatusInfo(
      latest: latestRaw is String && latestRaw.trim().isNotEmpty
          ? DateTime.tryParse(latestRaw)
          : null,
      lastRefresh: refreshRaw is String && refreshRaw.trim().isNotEmpty
          ? DateTime.tryParse(refreshRaw)
          : null,
    );
  }
}
