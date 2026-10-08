import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/consts/app_consts.dart';
import 'package:pure_live/core/widgets/adaptive_live_sidebar.dart';

class HomeTabletView extends StatelessWidget {
  const HomeTabletView({
    super.key,
    required this.body,
    required this.index,
    required this.activeMenuIds,
    required this.showRecord,
    required this.onDestinationSelected,
  });

  final Widget body;
  final int index;
  final List<String> activeMenuIds;
  final bool showRecord;
  final void Function(int) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final items = <LiveSidebarItem>[];
    for (final id in activeMenuIds) {
      final menu = HomeMenu.fromId(id);
      if (menu == null) continue;
      final (label, icon) = switch (menu) {
        HomeMenu.favorites => (i18n('favorites_title'), Icons.favorite_outline_rounded),
        HomeMenu.popular => (i18n('popular_title'), Icons.explore_outlined),
        HomeMenu.areas => (i18n('areas_title'), Icons.grid_view_rounded),
        HomeMenu.record => (i18n('record_center'), Icons.video_library_outlined),
      };
      items.add(
        LiveSidebarItem(
          label: label,
          icon: icon,
          selected: index == menu.index,
          onTap: () => onDestinationSelected(menu.index),
        ),
      );
    }
    LiveSidebarItem route(String label, IconData icon, String path) =>
        LiveSidebarItem(label: i18n(label), icon: icon, onTap: () => Get.toNamed(path));
    return Scaffold(
      body: SafeArea(
        child: Obx(
          () => AdaptiveLiveSidebar(
            title: i18n('app_name'),
            items: items,
            shortcuts: [
              route('search_live', Icons.search_rounded, RoutePath.kSearch),
              route('live_sources', Icons.live_tv_rounded, RoutePath.kIptv),
              route('live_custom_source', Icons.add_circle_outline_rounded, RoutePath.kCustomSource),
              if (SettingsService.to.app.enableMultiView.v)
                LiveSidebarItem(
                  label: i18n('multiview_title'),
                  icon: Icons.dashboard_customize_outlined,
                  onTap: AppNavigator.toMultiview,
                ),
              if (showRecord) route('record_center', Icons.video_library_outlined, RoutePath.kRecordPage),
              route('history', Icons.history_rounded, RoutePath.kHistory),
              route('settings_title', Icons.settings_outlined, RoutePath.kSettings),
            ],
            child: items.isEmpty
                ? AppStatusView(
                    type: AppStatusType.empty,
                    icon: Icons.grid_view_rounded,
                    title: i18n('no_menu_title'),
                    subtitle: i18n('no_menu_subtitle'),
                  )
                : body,
          ),
        ),
      ),
    );
  }
}
