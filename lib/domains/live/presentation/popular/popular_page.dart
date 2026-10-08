import 'package:pure_live/core/widgets/live_discovery_header.dart';

import 'popular_grid_view.dart';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/widgets/common_appbar_actions.dart';
import 'package:pure_live/domains/live/presentation/popular/popular_controller.dart';
import 'package:pure_live/domains/live/presentation/widgets/platform_tab.dart';

class PopularPage extends GetView<PopularController> {
  const PopularPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        return Obx(() {
          bool showAction = Get.width <= 680;

          final sites = controller.sites;

          if (sites.isEmpty) {
            return const Scaffold();
          }

          return Scaffold(
            appBar: AppBar(
              centerTitle: false,
              leading: showAction ? const MenuButton() : null,
              actions: const [CommonAppBarActions()],
              title: Text(
                i18n('live_discover'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: ScrollableTabBar(
                  key: const ValueKey('popular-platform-tabs'),
                  controller: controller.tabController,
                  isScrollable: true,
                  physics: const PureLiveBoundedScrollPhysics(),
                  tabs: sites.map((e) => PlatformTab(site: e)).toList(),
                ),
              ),
            ),
            body: Column(
              children: [
                if (constraint.maxHeight > 540 && MediaQuery.textScalerOf(context).scale(14) <= 21)
                  LiveDiscoveryHeader(
                    subtitle: i18n('live_tagline'),
                    searchLabel: i18n('live_search_hint'),
                    sourcesLabel: i18n('live_sources'),
                    customLabel: i18n('live_custom_source'),
                    onSearch: () => Get.toNamed(RoutePath.kSearch),
                    onSources: () => Get.toNamed(RoutePath.kIptv),
                    onCustom: () => Get.toNamed(RoutePath.kCustomSource),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: controller.tabController,
                    physics: const PureLiveBoundedScrollPhysics(),
                    children: sites.map((e) => PopularGridView(e.id)).toList(),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
