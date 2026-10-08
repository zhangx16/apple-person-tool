import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/widgets/live_discovery_header.dart';

void main() {
  for (final width in [320.0, 390.0, 1024.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('discovery actions fit width $width at text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final taps = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                  child: LiveDiscoveryHeader(
                    subtitle: '喜欢的直播，都在这里',
                    searchLabel: '搜索主播或粘贴直播链接',
                    sourcesLabel: 'IPTV / 直播源',
                    customLabel: '自定义直播源',
                    onSearch: () => taps.add('search'),
                    onSources: () => taps.add('iptv'),
                    onCustom: () => taps.add('custom'),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('搜索主播或粘贴直播链接'));
        await tester.tap(find.text('IPTV / 直播源'));
        await tester.tap(find.text('自定义直播源'));
        expect(taps, ['search', 'iptv', 'custom']);
      });
    }
  }
}
