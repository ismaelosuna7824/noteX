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
  ];
  static const _settingsItem = (4, _SidebarItem(Icons.settings_rounded, 'Settings'));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.only(top: 48, bottom: 24),
      child: Column(
        children: [
          // Top nav items: Home, Notes, Editor, Calendar
          for (final (pageIndex, item) in _navItems)
            _buildNavItem(pageIndex, item, context),

          const Spacer(),

          // Bottom item: Settings
          _buildNavItem(_settingsItem.$1, _settingsItem.$2, context),
        ],
      ),
    );
  }

  Widget _buildNavItem(int pageIndex, _SidebarItem item, BuildContext context) {
    final isSelected = selectedIndex == pageIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Tooltip(
        message: item.label,
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: () => onItemSelected(pageIndex),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isSelected ? accentColor : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.08),
                  blurRadius: isSelected ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              item.icon,
              color: isSelected ? Colors.white : Colors.grey.shade500,
              size: 22,
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
