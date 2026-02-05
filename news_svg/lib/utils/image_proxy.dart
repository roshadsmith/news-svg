String? buildProxiedImageUrl(String proxyUrl, String? rawUrl, {String? referer}) {
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return null;
  }

  final base = proxyUrl.endsWith('/') ? proxyUrl : '$proxyUrl/';
  final proxy = Uri.parse(base).resolve('api/image');
  final params = <String, String>{'url': rawUrl};
  if (referer != null && referer.trim().isNotEmpty) {
    params['referer'] = referer;
  }
  return proxy.replace(queryParameters: params).toString();
}
