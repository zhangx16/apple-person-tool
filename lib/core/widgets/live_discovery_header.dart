import 'package:flutter/material.dart';

/// Responsive shortcuts shared by the mobile and wide discovery layouts.
class LiveDiscoveryHeader extends StatelessWidget {
  const LiveDiscoveryHeader({
    super.key,
    required this.subtitle,
    required this.searchLabel,
    required this.sourcesLabel,
    required this.customLabel,
    required this.onSearch,
    required this.onSources,
    required this.onCustom,
  });

  final String subtitle;
  final String searchLabel;
  final String sourcesLabel;
  final String customLabel;
  final VoidCallback onSearch;
  final VoidCallback onSources;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(searchLabel, style: TextStyle(color: colors.onSurfaceVariant)),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                avatar: const Icon(Icons.live_tv_rounded, size: 18),
                label: Text(sourcesLabel),
                onPressed: onSources,
              ),
              ActionChip(
                avatar: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(customLabel),
                onPressed: onCustom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
