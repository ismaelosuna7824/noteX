import 'dart:ui';
import 'package:flutter/material.dart';

import '../utils/app_shortcuts.dart';

/// Sidebar width (including margin).
const double kSidebarWidth = 62.0;

/// Floating vertical pill sidebar with frosted glass effect.
class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Color accentColor;
  final Color editorBgColor;
  final Color heroTextColor;
  final List<Shadow> heroShadows;

  /// Base tint applied to idle/hovered nav icons (from theme settings).
  final Color baseIconColor;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.accentColor,
    required this.editorBgColor,
    required this.heroTextColor,
    required this.heroShadows,
    required this.baseIconColor,
  });

  static const _navItems = [
    (0, _SidebarItem(Icons.home_rounded, 'Home')),
    (1, _SidebarItem(Icons.list_alt_rounded, 'Notes')),
    (2, _SidebarItem(Icons.edit_note_rounded, 'Editor')),
    (3, _SidebarItem(Icons.calendar_month_rounded, 'Calendar')),
    (4, _SidebarItem(Icons.timer_rounded, 'Timer')),
    // index 5 (Markdown) intentionally omitted — hidden from the UI, not
    // deleted. The Markdown feature, its data, and its page still exist;
    // see AppState.navigateToPage for the fallback if anything still
    // requests that index. Every remaining tuple keeps its own explicit
    // page index, so removing this entry does not shift what any other
    // item points at.
    (9, _SidebarItem(Icons.hub_rounded, 'Graph')),
    (7, _SidebarItem(Icons.task_alt_rounded, 'Tasks')),
    (8, _SidebarItem(Icons.delete_outline_rounded, 'Trash')),
    (6, _SidebarItem(Icons.settings_rounded, 'Settings')),
  ];

  /// The page index of each visible sidebar section, in display order —
  /// the single source of truth the app-wide numeric shortcuts (Cmd/Ctrl+1..8,
  /// see `AppShortcuts`) derive their mapping from, so hiding or reordering a
  /// section here automatically keeps those shortcuts correct. Never hardcode
  /// a parallel copy of this list elsewhere.
  static List<int> get visiblePageIndices => [
        for (final (pageIndex, _) in _navItems) pageIndex,
      ];

  /// The label each visible sidebar section shows, in the same display
  /// order as [visiblePageIndices] — lets callers (and tests) verify a
  /// shortcut opens "the section whose name the sidebar shows in that
  /// position" without duplicating the item list.
  static List<String> get visibleSectionLabels => [
        for (final (_, item) in _navItems) item.label,
      ];

  /// The hover tooltip for the sidebar section shown at [position] (1-based,
  /// matching [visiblePageIndices]/[visibleSectionLabels] order): [label]
  /// plus its numeric jump shortcut when [position] falls within
  /// [kNumberedSectionShortcutCount] — the exact range `AppShortcuts` itself
  /// binds (Cmd/Ctrl+1..[kNumberedSectionShortcutCount]) — using the same
  /// platform-aware [primaryModifierLabel] the rest of the app's shortcut
  /// hints read from. A section beyond that range gets no shortcut hint
  /// instead of a wrong one, since `AppShortcuts` never binds it a key.
  static String sectionTooltip(String label, int position) {
    if (position < 1 || position > kNumberedSectionShortcutCount) {
      return label;
    }
    return '$label ($primaryModifierLabel+$position)';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 14),
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Container(
              width: 46,
              decoration: BoxDecoration(
                color: isDark
                    ? editorBgColor.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.55),
                  width: 0.5,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, (pageIndex, item)) in _navItems.indexed)
                      _NavIcon(
                        item: item,
                        tooltip: sectionTooltip(item.label, i + 1),
                        isSelected: selectedIndex == pageIndex,
                        accentColor: accentColor,
                        baseIconColor: baseIconColor,
                        isDark: isDark,
                        onTap: () => onItemSelected(pageIndex),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _NavIcon extends StatefulWidget {
  final _SidebarItem item;

  /// The hover tooltip text — [Sidebar.sectionTooltip]'s output, so it's
  /// already the item's label plus its shortcut hint (or just the label
  /// when the item has none).
  final String tooltip;
  final bool isSelected;
  final Color accentColor;
  final Color baseIconColor;
  final bool isDark;
  final VoidCallback onTap;

  const _NavIcon({
    required this.item,
    required this.tooltip,
    required this.isSelected,
    required this.accentColor,
    required this.baseIconColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final accent = widget.accentColor;
    final isDark = widget.isDark;
    final base = widget.baseIconColor;

    final Color iconColor;
    if (isSelected) {
      // Icon sits on the accent-colored background — keep it high-contrast.
      iconColor = Colors.white;
    } else if (_hovered) {
      // Hover cue: the chosen color at full emphasis.
      iconColor = base;
    } else {
      // Idle: the chosen color, slightly dimmed so hover stays distinct.
      iconColor = base.withValues(alpha: 0.7);
    }

    final Color bgColor;
    if (isSelected) {
      bgColor = accent;
    } else if (_hovered) {
      bgColor = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04);
    } else {
      bgColor = Colors.transparent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 5),
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? accent.withValues(alpha: 0.3)
                        : Colors.transparent,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: iconColor),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                builder: (context, color, _) => Icon(
                  widget.item.icon,
                  color: color,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  const _SidebarItem(this.icon, this.label);
}
