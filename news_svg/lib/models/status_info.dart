class StatusInfo {
  StatusInfo({
    required this.latest,
    required this.lastRefresh,
    required this.totalSources,
    required this.totalArticles,
    required this.pendingProcesses,
  });

  final DateTime? latest;
  final DateTime? lastRefresh;
  final int totalSources;
  final int totalArticles;
  final int pendingProcesses;

  factory StatusInfo.fromJson(Map<String, dynamic> json) {
    final latestRaw = json['latest'];
    final refreshRaw = json['lastRefresh'];
    final totalSourcesRaw = json['totalSources'];
    final totalArticlesRaw = json['totalArticles'];
    final pendingRaw = json['pendingProcesses'];
    return StatusInfo(
      latest: latestRaw is String && latestRaw.trim().isNotEmpty
          ? DateTime.tryParse(latestRaw)
          : null,
      lastRefresh: refreshRaw is String && refreshRaw.trim().isNotEmpty
          ? DateTime.tryParse(refreshRaw)
          : null,
      totalSources: totalSourcesRaw is num
          ? totalSourcesRaw.toInt()
          : int.tryParse('$totalSourcesRaw') ?? 0,
      totalArticles: totalArticlesRaw is num
          ? totalArticlesRaw.toInt()
          : int.tryParse('$totalArticlesRaw') ?? 0,
      pendingProcesses: pendingRaw is num
          ? pendingRaw.toInt()
          : int.tryParse('$pendingRaw') ?? 0,
    );
  }
}
