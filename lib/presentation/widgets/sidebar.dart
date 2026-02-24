import 'package:flutter/material.dart';

/// Minimalist vertical icon rail sidebar matching the reference design.
///
/// Clean sidebar with white circle icon buttons.
/// Selected item has accent color filled circle background.
class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Color accentColor;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.accentColor,
  });

  static const _navItems = [
    (0, _SidebarItem(Icons.home_rounded, 'Home')),
    (1, _SidebarItem(Icons.list_alt_rounded, 'Notes')),
    (2, _SidebarItem(Icons.edit_note_rounded, 'Editor')),
    (3, _SidebarItem(Icons.calendar_month_rounded, 'Calendar')),
    (4, _SidebarItem(Icons.timer_rounded, 'Timer')),
    (5, _SidebarItem(Icons.article_rounded, 'Markdown')),
    (7, _SidebarItem(Icons.notifications_rounded, 'Reminders')),
  ];
  static const _settingsItem =
      (6, _SidebarItem(Icons.settings_rounded, 'Settings'));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.only(top: 48, bottom: 24),
      child: Column(
        children: [
          // Top nav items: Home, Notes, Editor, Calendar, Timer
          for (final (pageIndex, item) in _navItems)
            _NavButton(
              pageIndex: pageIndex,
              item: item,
              isSelected: selectedIndex == pageIndex,
              accentColor: accentColor,
              onTap: () => onItemSelected(pageIndex),
            ),

          const Spacer(),

          // Bottom item: Settings
          _NavButton(
            pageIndex: _settingsItem.$1,
            item: _settingsItem.$2,
            isSelected: selectedIndex == _settingsItem.$1,
            accentColor: accentColor,
            onTap: () => onItemSelected(_settingsItem.$1),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single nav button — uses MouseRegion so hover state is fully controlled
// and never leaks through the InkWell splash/hover overlay.
// ─────────────────────────────────────────────────────────────────────────────

class _NavButton extends StatefulWidget {
  final int pageIndex;
  final _SidebarItem item;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _NavButton({
    required this.pageIndex,
    required this.item,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final accent = widget.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Adapt circle color to dark/light mode.
    final Color circleColor;
    if (isSelected) {
      circleColor = accent;
    } else if (isDark) {
      circleColor = _hovered
          ? const Color(0xFF2A2A40)
          : const Color(0xFF1A1A2E);
    } else {
      circleColor = _hovered
          ? Colors.white.withValues(alpha: 0.88)
          : Colors.white;
    }

    final shadowColor = isSelected
        ? accent.withValues(alpha: 0.35)
        : (isDark
            ? Colors.black.withValues(alpha: _hovered ? 0.30 : 0.20)
            : Colors.black.withValues(alpha: _hovered ? 0.14 : 0.08));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
                border: isDark && !isSelected
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: isSelected ? 12 : (_hovered ? 8 : 6),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                widget.item.icon,
                // Selected → always white; unselected adapts to dark/light.
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.grey.shade600),
                size: 22,
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
