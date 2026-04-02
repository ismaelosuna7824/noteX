import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';

/// Compact tab bar for the editor — pill-shaped tabs in a scrollable row.
class EditorTabBar extends StatelessWidget {
  final List<Note> tabs;
  final String? activeNoteId;
  final ValueChanged<String> onSwitch;
  final ValueChanged<String> onClose;
  final Color accentColor;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;

  const EditorTabBar({
    super.key,
    required this.tabs,
    required this.activeNoteId,
    required this.onSwitch,
    required this.onClose,
    required this.accentColor,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.id == activeNoteId;
          return _TabChip(
            note: tab,
            isActive: isActive,
            accentColor: accentColor,
            bgColor: bgColor,
            borderColor: borderColor,
            textColor: textColor,
            mutedColor: mutedColor,
            onTap: () => onSwitch(tab.id),
            onClose: () => onClose(tab.id),
          );
        },
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  final Note note;
  final bool isActive;
  final Color accentColor;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({
    required this.note,
    required this.isActive,
    required this.accentColor,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTertiaryTapUp: (_) => widget.onClose(),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.bgColor
                : _hovered
                    ? widget.bgColor.withValues(alpha: 0.7)
                    : widget.bgColor.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive
                  ? widget.accentColor.withValues(alpha: 0.5)
                  : _hovered
                      ? widget.borderColor
                      : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accent dot for active tab
              if (widget.isActive)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: widget.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  widget.note.title.isEmpty ? 'Untitled' : widget.note.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isActive
                        ? widget.textColor
                        : widget.mutedColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              // Close button
              AnimatedOpacity(
                opacity: _hovered || widget.isActive ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 100),
                child: InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: widget.mutedColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
