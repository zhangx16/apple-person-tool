import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/platforms/sites.dart';
import 'package:pure_live/domains/live/data/link/live_url_tool.dart';
import 'package:pure_live/domains/live/data/link/web_search_room_parser.dart';

void main() {
  test('only requested live platforms and IPTV are registered', () {
    expect(Sites.supportedSiteIds, {'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'xiaohongshu', 'weibo', 'iptv'});
    for (final excluded in ['twitch', 'youtube', 'cc', 'yy', 'niconico']) {
      expect(Sites.isSupported(excluded), isFalse);
      expect(() => Sites.of(excluded), throwsStateError);
    }
  });

  test('excluded platform links cannot enter search or shared-link flows', () async {
    for (final link in [
      'https://www.twitch.tv/testchannel',
      'https://live.nicovideo.jp/watch/lv123456',
      'https://cc.163.com/123456',
    ]) {
      expect(WebSearchRoomParser.parse(link), isNull);
      expect(LiveUrlTool.containsSupportedLink(link), isFalse);
      expect(await LiveUrlTool.parseLiveUrl(link), isEmpty);
    }
    expect(WebSearchRoomParser.parse('https://live.bilibili.com/123456')?.platform, 'bilibili');
  });
}
