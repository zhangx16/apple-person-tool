import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/iptv/domain/custom_stream.dart';
import 'package:pure_live/domains/iptv/data/parsers/m3u_parser.dart';

void main() {
  test('custom stream round trips through the production IPTV parser', () {
    const stream = CustomStream(
      name: '测试频道',
      url: 'https://example.com/live.m3u8?token=a%2Fb',
      userAgent: 'Personal Live',
      referer: 'https://example.com/',
    );
    final result = M3uParser().parse(stream.toM3u(), providerId: 'custom');
    expect(result.channels, hasLength(1));
    final channel = result.channels.single;
    expect(channel.name, stream.name);
    expect(channel.streamUrl, stream.url);
    expect(channel.httpHeaders['user-agent'], stream.userAgent);
    expect(channel.httpHeaders['referer'], stream.referer);
  });

  test('rejects invalid protocols and playlist/header injection', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'https://',
      'https://example.com/live\n#EXTINF:-1,Other',
    ]) {
      expect(() => CustomStream(name: 'Channel', url: url).toM3u(), throwsFormatException);
    }
    expect(() => const CustomStream(name: '', url: 'https://example.com/live').toM3u(), throwsFormatException);
    expect(() => const CustomStream(name: 'X\nY', url: 'https://example.com/live').toM3u(), throwsFormatException);
    expect(
      () => const CustomStream(name: 'X', url: 'https://example.com/live', userAgent: 'UA\r\nReferer: other').toM3u(),
      throwsFormatException,
    );
  });

  test('retains each supported stream protocol', () {
    for (final scheme in ['http', 'https', 'rtmp', 'rtsp', 'udp', 'mms']) {
      final result = M3uParser().parse(
        CustomStream(name: 'Channel', url: '$scheme://example.com/live').toM3u(),
        providerId: 'custom',
      );
      expect(result.channels, hasLength(1), reason: scheme);
    }
  });
}
