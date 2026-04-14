import 'dart:ui';
import 'package:flutter/material.dart';

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

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.accentColor,
    required this.editorBgColor,
    required this.heroTextColor,
    required this.heroShadows,
  });

  static const _navItems = [
    (0, _SidebarItem(Icons.home_rounded, 'Home')),
    (1, _SidebarItem(Icons.list_alt_rounded, 'Notes')),
    (2, _SidebarItem(Icons.edit_note_rounded, 'Editor')),
    (3, _SidebarItem(Icons.calendar_month_rounded, 'Calendar')),
    (4, _SidebarItem(Icons.timer_rounded, 'Timer')),
    (5, _SidebarItem(Icons.article_rounded, 'Markdown')),
    (7, _SidebarItem(Icons.notifications_rounded, 'Reminders')),
    (8, _SidebarItem(Icons.delete_outline_rounded, 'Trash')),
    (6, _SidebarItem(Icons.settings_rounded, 'Settings')),
  ];

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
                    for (final (pageIndex, item) in _navItems)
                      _NavIcon(
                        item: item,
                        isSelected: selectedIndex == pageIndex,
                        accentColor: accentColor,
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
  final bool isSelected;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _NavIcon({
    required this.item,
    required this.isSelected,
    required this.accentColor,
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

    final Color iconColor;
    if (isSelected) {
      iconColor = Colors.white;
    } else if (_hovered) {
      iconColor = isDark ? Colors.white70 : Colors.black54;
    } else {
      iconColor = isDark ? Colors.white38 : Colors.black26;
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
        message: widget.item.label,
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
