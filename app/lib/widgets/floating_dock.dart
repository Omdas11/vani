import 'package:flutter/material.dart';
import '../services/app_settings.dart';

/// Floating navigation dock — Material 3 Expressive restyle
/// (PixelPlayer study, docs/PIXELPLAYER_STUDY.md).
///
/// A detached tonal pill dock (not glass): `surfaceContainerHigh`
/// container with a hairline outline and soft elevation, inside which
/// a `secondaryContainer` pill SLIDES between destinations on
/// selection (300ms easeOutCubic) instead of jumping. Active
/// destination shows the filled icon + semibold label; inactive shows
/// the outline icon + regular label in `onSurfaceVariant`.
///
/// The visible destinations and their order come from
/// Settings → Navigation (editable dock); this widget just renders
/// whatever list it is given. Radii (32dp container) and tonal
/// surfaces match the mini-player card above it so the two read as
/// one stacked dock unit.
class FloatingDock extends StatelessWidget {
  final List<NavDestination> destinations;
  final String currentId;
  final ValueChanged<String> onSelect;

  const FloatingDock({
    super.key,
    required this.destinations,
    required this.currentId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (destinations.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final index = destinations
        .indexWhere((d) => d.id == currentId)
        .clamp(0, destinations.length - 1);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = destinations.length;
          final segW = constraints.maxWidth / n;
          // M3 active-indicator geometry: 64x32 pill behind the icon.
          const pillW = 64.0;
          const pillH = 32.0;
          const vPad = 12.0;
          final pillLeft = index * segW + (segW - pillW) / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: pillLeft,
                top: vPad,
                child: Container(
                  width: pillW,
                  height: pillH,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: vPad),
                child: Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _DockItem(
                          destination: destinations[i],
                          selected: i == index,
                          onTap: () => onSelect(destinations[i].id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _DockItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  // Key drives the filled/outline cross-fade.
                  key: ValueKey<bool>(selected),
                  selected
                      ? destination.selectedIcon
                      : destination.icon,
                  size: 24,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant,
            ),
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
