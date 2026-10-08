import 'package:remixicon/remixicon.dart';
import 'package:pure_live/core/index.dart';

class CommonAppBarActions extends StatelessWidget {
  const CommonAppBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<int>(
          tooltip: i18n("more"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          offset: const Offset(0, 10),
          position: PopupMenuPosition.under,
          onSelected: (index) {
            switch (index) {
              case 0:
                Get.toNamed(RoutePath.kSearch);
                break;
              case 1:
                Get.toNamed(RoutePath.kToolbox);
                break;
              case 3:
                Get.toNamed(RoutePath.kIptv);
                break;
              case 4:
                Get.toNamed(RoutePath.kCustomSource);
                break;
              case 2:
                AppNavigator.toMultiview();
                break;
            }
          },

          itemBuilder: (context) => [
            PopupMenuItem(
              value: 3,
              child: ListTile(leading: const Icon(Icons.live_tv_rounded), title: Text(i18n('live_sources'))),
            ),
            PopupMenuItem(
              value: 4,
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: Text(i18n('live_custom_source')),
              ),
            ),
            PopupMenuItem(
              value: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Remix.search_line, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(i18n("search_live"), style: AppTextStyles.t14),
                ],
              ),
            ),

            PopupMenuItem(
              value: 1,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Remix.link, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(i18n("open_link"), style: AppTextStyles.t14),
                ],
              ),
            ),
            if (SettingsService.to.app.enableMultiView.v)
              PopupMenuItem(
                value: 2,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Remix.layout_grid_line, size: 20, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(i18n("multiview_title"), style: AppTextStyles.t14),
                  ],
                ),
              ),
          ],
          child: const SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Icon(Remix.menu_search_line, size: 24),
          ),
        ),

        const SizedBox(width: 4),
      ],
    );
  }
}
