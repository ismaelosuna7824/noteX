import 'package:flutter/material.dart';

/// Vertical spacing for each nav button: 10px top + 46px button + 10px bottom.
const double _kNavButtonPitch = 66.0;

/// Top padding of the sidebar column.
const double _kTopPadding = 48.0;

/// Bottom padding of the sidebar column.
const double _kBottomPadding = 24.0;

/// Height of each nav button circle.
const double _kButtonSize = 46.0;

/// Height of the animated selection indicator bar.
const double _kIndicatorHeight = 20.0;

/// Minimalist vertical icon rail sidebar matching the reference design.
///
/// Clean sidebar with white circle icon buttons.
/// Selected item has accent color filled circle background.
/// An animated indicator bar on the left edge slides to the selected item.
class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final Color accentColor;
  final Color editorBgColor;
  final Color sidebarIconColor;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.accentColor,
    required this.editorBgColor,
    required this.sidebarIconColor,
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
  ];
  static const _settingsItem =
      (6, _SidebarItem(Icons.settings_rounded, 'Settings'));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final navIndex =
            _navItems.indexWhere((e) => e.$1 == selectedIndex);
        final isSettings = selectedIndex == _settingsItem.$1;

        // Calculate indicator vertical position.
        final double indicatorTop;
        if (isSettings) {
          indicatorTop = totalHeight -
              _kBottomPadding -
              _kButtonSize +
              (_kButtonSize - _kIndicatorHeight) / 2;
        } else if (navIndex >= 0) {
          indicatorTop = _kTopPadding +
              (navIndex * _kNavButtonPitch) +
              10 + // top padding of _NavButton
              (_kButtonSize - _kIndicatorHeight) / 2;
        } else {
          indicatorTop =
              _kTopPadding + 10 + (_kButtonSize - _kIndicatorHeight) / 2;
        }

        return Stack(
          children: [
            // Original sidebar layout — untouched structure
            Container(
              width: 72,
              padding:
                  const EdgeInsets.only(top: _kTopPadding, bottom: _kBottomPadding),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final (pageIndex, item) in _navItems)
                            _NavButton(
                              pageIndex: pageIndex,
                              item: item,
                              isSelected: selectedIndex == pageIndex,
                              accentColor: accentColor,
                              editorBgColor: editorBgColor,
                              sidebarIconColor: sidebarIconColor,
                              onTap: () => onItemSelected(pageIndex),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _NavButton(
                    pageIndex: _settingsItem.$1,
                    item: _settingsItem.$2,
                    isSelected: selectedIndex == _settingsItem.$1,
                    accentColor: accentColor,
                    editorBgColor: editorBgColor,
                    sidebarIconColor: sidebarIconColor,
                    onTap: () => onItemSelected(_settingsItem.$1),
                  ),
                ],
              ),
            ),

            // Animated selection indicator bar (overlaid)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: 2,
              top: indicatorTop,
              child: Container(
                width: 3,
                height: _kIndicatorHeight,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        );
      },
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
  final Color editorBgColor;
  final Color sidebarIconColor;
  final VoidCallback onTap;

  const _NavButton({
    required this.pageIndex,
    required this.item,
    required this.isSelected,
    required this.accentColor,
    required this.editorBgColor,
    required this.sidebarIconColor,
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
    final bgColor = widget.editorBgColor;
    final Color circleColor;
    if (isSelected) {
      circleColor = accent;
    } else if (_hovered) {
      circleColor = Color.lerp(bgColor, isDark ? Colors.white : Colors.black, 0.08)!;
    } else {
      circleColor = bgColor;
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
              width: _kButtonSize,
              height: _kButtonSize,
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
                // Selected → always white; unselected uses custom icon color.
                color: isSelected ? Colors.white : widget.sidebarIconColor,
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
