import 'package:flutter/material.dart';

class LiveSidebarItem {
  const LiveSidebarItem({required this.label, required this.icon, required this.onTap, this.selected = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
}

/// Uses the current window width, so iPad Split View and Stage Manager can
/// resize independently of the physical display. Short windows scroll the
/// navigation instead of overflowing or hiding source actions.
class AdaptiveLiveSidebar extends StatelessWidget {
  const AdaptiveLiveSidebar({
    super.key,
    required this.title,
    required this.items,
    required this.shortcuts,
    required this.child,
  });

  final String title;
  final List<LiveSidebarItem> items;
  final List<LiveSidebarItem> shortcuts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extended = constraints.maxWidth >= 1180 && MediaQuery.textScalerOf(context).scale(14) <= 21;
        final colors = Theme.of(context).colorScheme;
        Widget tile(LiveSidebarItem item) {
          final icon = Icon(item.icon, color: item.selected ? colors.primary : colors.onSurfaceVariant);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Material(
              color: item.selected ? colors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: extended
                  ? ListTile(
                      leading: icon,
                      title: Text(item.label),
                      onTap: item.onTap,
                      selected: item.selected,
                      minTileHeight: 52,
                    )
                  : Tooltip(
                      message: item.label,
                      child: InkWell(
                        onTap: item.onTap,
                        borderRadius: BorderRadius.circular(16),
                        child: Semantics(
                          button: true,
                          selected: item.selected,
                          label: item.label,
                          excludeSemantics: true,
                          child: SizedBox(height: 52, child: Center(child: icon)),
                        ),
                      ),
                    ),
            ),
          );
        }

        return Row(
          children: [
            SizedBox(
              key: ValueKey(extended ? 'live-sidebar-expanded' : 'live-sidebar-compact'),
              width: extended ? 224 : 80,
              child: ColoredBox(
                color: colors.surfaceContainerLow,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: extended
                          ? Row(
                              children: [
                                Icon(Icons.play_circle_filled_rounded, color: colors.primary, size: 30),
                                const SizedBox(width: 12),
                                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                              ],
                            )
                          : Icon(Icons.play_circle_filled_rounded, color: colors.primary, size: 30),
                    ),
                    for (final item in items) tile(item),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Divider()),
                    for (final item in shortcuts) tile(item),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
