/// Validated single-channel playlist, imported through the regular IPTV flow.
class CustomStream {
  const CustomStream({required this.name, required this.url, this.userAgent = '', this.referer = ''});

  final String name;
  final String url;
  final String userAgent;
  final String referer;

  String toM3u() {
    final title = name.trim();
    final address = url.trim();
    final uri = Uri.tryParse(address);
    if (title.isEmpty || title.contains(RegExp(r'[\r\n\x00]'))) {
      throw const FormatException('custom_source_invalid_name');
    }
    if (uri == null ||
        uri.host.isEmpty ||
        !const {'http', 'https', 'rtmp', 'rtsp', 'udp', 'mms'}.contains(uri.scheme) ||
        address.contains(RegExp(r'[\s\x00]'))) {
      throw const FormatException('custom_source_invalid_url');
    }
    final headers = {'http-user-agent': userAgent.trim(), 'http-referrer': referer.trim()};
    if (headers.values.any((v) => v.contains(RegExp(r'[\r\n\x00]')))) {
      throw const FormatException('custom_source_invalid_header');
    }
    return [
      '#EXTM3U',
      '#EXTINF:-1,$title',
      for (final entry in headers.entries)
        if (entry.value.isNotEmpty) '#EXTVLCOPT:${entry.key}=${entry.value}',
      address,
      '',
    ].join('\n');
  }
}
