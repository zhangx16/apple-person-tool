import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/widgets/adaptive_live_sidebar.dart';
import 'package:pure_live/core/widgets/adaptive_live_layout.dart';
import 'package:pure_live/core/player/presentation/fullscreen_window.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_content.dart';

void main() {
  testWidgets('rotating iPad expands navigation without losing content state', (tester) async {
    tester.view.physicalSize = const Size(834, 1194);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveLiveSidebar(
            title: '随心直播',
            items: [LiveSidebarItem(label: '发现', icon: Icons.explore, onTap: () {}, selected: true)],
            shortcuts: [LiveSidebarItem(label: '直播源', icon: Icons.live_tv, onTap: () {})],
            child: StatefulBuilder(
              builder: (context, setState) =>
                  TextButton(onPressed: () => setState(() => count++), child: Text('次数 $count')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('次数 0'));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-sidebar-compact')), findsOneWidget);
    tester.view.physicalSize = const Size(1194, 834);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-sidebar-expanded')), findsOneWidget);
    expect(find.text('次数 1'), findsOneWidget);
    expect(find.text('直播源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('iPad display stays freely rotatable even in a narrow split window', () {
    expect(supportsOrientationLockForLogicalDisplay(const Size(834, 1194)), isFalse);
    expect(supportsOrientationLockForLogicalDisplay(const Size(1024, 1366)), isFalse);
    expect(supportsOrientationLockForLogicalDisplay(const Size(390, 844)), isTrue);
  });

  test('room grid uses content width and larger text reduces column count', () {
    expect(liveRoomGridColumns(320), 1);
    expect(liveRoomGridColumns(390), 2);
    expect(liveRoomGridColumns(744 - 81), 3);
    expect(liveRoomGridColumns(1194 - 225), 5);
    expect(liveRoomGridColumns(1194 - 81, textScale: 2), 3);
  });

  for (final size in [
    const Size(744, 1133),
    const Size(834, 1194),
    const Size(1024, 768),
    const Size(1194, 834),
    const Size(1366, 1024),
    const Size(720, 360),
  ]) {
    testWidgets('iPad navigation remains usable at $size and double text size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2)),
              child: AdaptiveLiveSidebar(
                title: '随心直播',
                items: [
                  LiveSidebarItem(label: '发现', icon: Icons.explore, onTap: () {}, selected: true),
                  LiveSidebarItem(label: '关注', icon: Icons.favorite, onTap: () {}),
                ],
                shortcuts: [
                  for (var i = 0; i < 7; i++)
                    LiveSidebarItem(label: '操作 $i', icon: Icons.add, onTap: () => tapped = true),
                ],
                child: const Center(child: Text('直播内容')),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('live-sidebar-compact')), findsOneWidget);
      final last = find.byTooltip('操作 6');
      await tester.scrollUntilVisible(last, 180, scrollable: find.byType(Scrollable).first);
      await tester.tap(last);
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(507, 768),
    const Size(744, 1133),
    const Size(834, 1194),
    const Size(1024, 768),
    const Size(1194, 834),
    const Size(820, 500),
  ]) {
    testWidgets('iPad player preserves video and chat when resized to $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LivePlayNormalLayout(
              video: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(color: Colors.black),
              ),
              resolution: SizedBox(height: 48, child: Text('清晰度 / 线路')),
              danmaku: Center(child: Text('弹幕')),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final stacked = size.width <= 680 || (size.width < 900 && size.height >= size.width);
      expect(find.byKey(ValueKey(stacked ? 'live-play-portrait-stack' : 'live-play-desktop-split')), findsOneWidget);
      expect(find.text('弹幕'), findsOneWidget);
    });
  }
}
