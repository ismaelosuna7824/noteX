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
  ];
  static const _settingsItem =
      (5, _SidebarItem(Icons.settings_rounded, 'Settings'));

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

    // Tint the circle slightly on hover (unselected only).
    final circleColor = isSelected
        ? accent
        : (_hovered
            ? Colors.white.withValues(alpha: 0.88)
            : Colors.white);

    final shadowColor = isSelected
        ? accent.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: _hovered ? 0.14 : 0.08);

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
                color: isSelected ? Colors.white : Colors.grey.shade500,
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
