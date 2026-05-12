import 'package:flutter/material.dart';

/// Shape of the indent-guide stroke at one column for one row in a folder
/// tree. Pass-through ancestors draw a vertical line; the immediate-parent
/// column draws a tee (├) for non-last children or an ell (└) for the last
/// child of that parent.
enum GuideKind { none, vertical, tee, ell }

/// One column of indent in a folder tree row. Width is fixed at 14 px.
/// Subtle 1 px stroke; light/dark adapt.
class IndentGuide extends StatelessWidget {
  final GuideKind kind;
  final bool isDark;
  const IndentGuide({super.key, required this.kind, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (kind == GuideKind.none) {
      return const SizedBox(width: 14);
    }
    final color = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    return SizedBox(
      width: 14,
      child: CustomPaint(
        painter: _GuidePainter(kind: kind, color: color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final GuideKind kind;
  final Color color;
  _GuidePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double trunkX = 6.5;
    final double midY = size.height / 2;
    switch (kind) {
      case GuideKind.none:
        break;
      case GuideKind.vertical:
        canvas.drawLine(
            const Offset(trunkX, 0), Offset(trunkX, size.height), paint);
        break;
      case GuideKind.tee:
        canvas.drawLine(
            const Offset(trunkX, 0), Offset(trunkX, size.height), paint);
        canvas.drawLine(
            Offset(trunkX, midY), Offset(size.width, midY), paint);
        break;
      case GuideKind.ell:
        canvas.drawLine(const Offset(trunkX, 0), Offset(trunkX, midY), paint);
        canvas.drawLine(
            Offset(trunkX, midY), Offset(size.width, midY), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.kind != kind || old.color != color;
}

/// Pill-shaped badge showing a numeric count next to a folder name.
class CountPill extends StatelessWidget {
  final int count;
  final bool isDark;
  const CountPill({super.key, required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Tiny inline icon button for tree rows (hover-revealed "+" actions).
/// Stops the tap from bubbling up to the row's own onTap so it doesn't also
/// trigger row selection.
class MiniIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const MiniIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  State<MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<MiniIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _hover
                  ? widget.color.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon, size: 13, color: widget.color),
          ),
        ),
      ),
    );
  }
}

/// A folder row in a file-explorer-style vertical tree. Indent columns are
/// drawn via [guides] (one [GuideKind] per column). The chevron is its own
/// hit target — tapping it toggles expand without changing selection.
///
/// Markdown projects use this directly (no drag-drop). Notes use a richer
/// internal variant with drag-drop wired up.
class FolderTreeRow extends StatefulWidget {
  final String label;
  final List<GuideKind> guides;
  final Color color;
  final bool isDark;
  final bool isSelected;
  final bool hasChildren;
  final bool isExpanded;
  final int count;
  final IconData leadingIcon;
  final VoidCallback onTap;
  final VoidCallback? onChevronTap;
  final VoidCallback? onLongPress;
  // Inline hover actions — when set, small icons appear on the right while
  // the row is hovered.
  final VoidCallback? onCreatePrimary;
  final String? createPrimaryTooltip;
  final IconData? createPrimaryIcon;
  final VoidCallback? onCreateSecondary;
  final String? createSecondaryTooltip;
  final IconData? createSecondaryIcon;
  // When true, the trailing action icons are pinned visible instead of only
  // appearing on hover. Used by pseudo-rows like "All" so the affordance is
  // always reachable.
  final bool alwaysShowActions;

  const FolderTreeRow({
    super.key,
    required this.label,
    required this.guides,
    required this.color,
    required this.isDark,
    required this.isSelected,
    required this.hasChildren,
    required this.isExpanded,
    required this.count,
    required this.leadingIcon,
    required this.onTap,
    this.onChevronTap,
    this.onLongPress,
    this.onCreatePrimary,
    this.createPrimaryTooltip,
    this.createPrimaryIcon,
    this.onCreateSecondary,
    this.createSecondaryTooltip,
    this.createSecondaryIcon,
    this.alwaysShowActions = false,
  });

  @override
  State<FolderTreeRow> createState() => _FolderTreeRowState();
}

class _FolderTreeRowState extends State<FolderTreeRow> {
  bool _hover = false;

  bool get _isFolderEntry => widget.leadingIcon == Icons.folder_rounded;

  @override
  Widget build(BuildContext context) {
    final selectedBg = widget.color.withValues(alpha: 0.12);
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final textColor = widget.isSelected
        ? widget.color
        : (widget.isDark ? Colors.white70 : Colors.grey.shade700);
    final mutedColor = widget.isDark ? Colors.white38 : Colors.grey.shade500;

    final IconData renderIcon = _isFolderEntry
        ? (widget.isExpanded
            ? Icons.folder_open_rounded
            : Icons.folder_rounded)
        : widget.leadingIcon;

    final iconColor = _isFolderEntry
        ? (widget.isSelected
            ? widget.color
            : widget.color.withValues(alpha: 0.65))
        : (widget.isSelected ? widget.color : mutedColor);

    final Color rowBg = widget.isSelected
        ? selectedBg
        : (_hover ? hoverBg : Colors.transparent);

    final hasActions =
        widget.onCreatePrimary != null || widget.onCreateSecondary != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: rowBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? widget.color
                        : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(6),
                    ),
                  ),
                ),
                for (final g in widget.guides)
                  IndentGuide(kind: g, isDark: widget.isDark),
                const SizedBox(width: 4),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: widget.hasChildren
                      ? InkWell(
                          onTap: widget.onChevronTap,
                          borderRadius: BorderRadius.circular(4),
                          child: AnimatedRotation(
                            turns: widget.isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: mutedColor,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Icon(renderIcon, size: 14, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                if (hasActions && (_hover || widget.alwaysShowActions)) ...[
                  if (widget.onCreatePrimary != null)
                    MiniIconButton(
                      icon: widget.createPrimaryIcon ?? Icons.add_rounded,
                      tooltip: widget.createPrimaryTooltip ?? 'New',
                      color: mutedColor,
                      onTap: widget.onCreatePrimary!,
                    ),
                  if (widget.onCreateSecondary != null)
                    MiniIconButton(
                      icon: widget.createSecondaryIcon ??
                          Icons.create_new_folder_outlined,
                      tooltip: widget.createSecondaryTooltip ?? 'New folder',
                      color: mutedColor,
                      onTap: widget.onCreateSecondary!,
                    ),
                  const SizedBox(width: 4),
                ] else if (widget.count > 0) ...[
                  CountPill(count: widget.count, isDark: widget.isDark),
                  const SizedBox(width: 6),
                ] else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A leaf row in the unified tree (a file / note / etc.). Indent matches the
/// folder rows; the optional [trailing] slot accepts small status icons
/// (e.g. pinned / locked) before the end padding.
class LeafTreeRow extends StatefulWidget {
  final String label;
  final List<GuideKind> guides;
  final IconData leadingIcon;
  final bool isDark;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Widget> trailing;

  const LeafTreeRow({
    super.key,
    required this.label,
    required this.guides,
    required this.isDark,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
    this.leadingIcon = Icons.description_outlined,
    this.trailing = const [],
  });

  @override
  State<LeafTreeRow> createState() => _LeafTreeRowState();
}

class _LeafTreeRowState extends State<LeafTreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final selectedBg = accent.withValues(alpha: 0.12);
    final hoverBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final textColor = widget.isSelected
        ? accent
        : (widget.isDark ? Colors.white70 : Colors.grey.shade700);
    final mutedColor = widget.isDark ? Colors.white38 : Colors.grey.shade500;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? selectedBg
                : (_hover ? hoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(6),
                    ),
                  ),
                ),
                for (final g in widget.guides)
                  IndentGuide(kind: g, isDark: widget.isDark),
                const SizedBox(width: 4),
                // Empty chevron slot to align with folder rows.
                const SizedBox(width: 16),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Icon(
                    widget.leadingIcon,
                    size: 13,
                    color: widget.isSelected ? accent : mutedColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
                for (final w in widget.trailing) ...[
                  w,
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
