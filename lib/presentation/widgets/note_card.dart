import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';
import 'glassmorphic_container.dart';

/// A card representing a note preview in the notes list.
///
/// Shows title, creation date, and a content preview snippet.
/// Includes a subtle hover animation (lift + accent border glow).
class NoteCard extends StatefulWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onCompactMode;
  final Color accentColor;
  final Color? editorBgColor;

  const NoteCard({
    super.key,
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onPin,
    this.onCompactMode,
    required this.accentColor,
    this.editorBgColor,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteColor = _parseNoteColor(widget.note.color);
    final cardColor = noteColor ?? widget.editorBgColor;
    final borderColor = noteColor ?? widget.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered && !widget.isSelected ? -2 : 0, 0),
        child: GlassmorphicContainer(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          borderRadius: 16,
          color: cardColor,
          opacity: noteColor != null
              ? (widget.isSelected ? 0.35 : (_hovered ? 0.28 : 0.20))
              : (widget.isSelected ? 0.25 : (_hovered ? 0.18 : 0.12)),
          blur: widget.isSelected ? 14 : (_hovered ? 10 : 8),
          border: widget.isSelected
              ? Border.all(color: borderColor.withValues(alpha: 0.5), width: 2)
              : (_hovered
                  ? Border.all(color: borderColor.withValues(alpha: 0.25), width: 1)
                  : null),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                // Color indicator
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _indicatorColor(),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),

                // Note info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.note.title.isEmpty
                            ? 'Untitled'
                            : widget.note.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: noteColor != null ? Colors.white : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(widget.note.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: noteColor != null
                              ? Colors.white70
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Sticky note mode button
                if (_hovered && widget.onCompactMode != null)
                  IconButton(
                    onPressed: widget.onCompactMode,
                    icon: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 18,
                      color: noteColor != null ? Colors.white70 : Colors.grey.shade400,
                    ),
                    tooltip: 'Sticky Note',
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),

                // Sync indicator
                _buildSyncIcon(),

                // Pin button
                if (widget.onPin != null)
                  IconButton(
                    onPressed: widget.onPin,
                    icon: Icon(
                      widget.note.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 18,
                      color: noteColor != null
                          ? Colors.white70
                          : (widget.note.isPinned
                              ? widget.accentColor
                              : Colors.grey.shade400),
                    ),
                    splashRadius: 18,
                  ),

                // Delete button
                if (widget.onDelete != null)
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: noteColor != null ? Colors.white70 : Colors.grey.shade400,
                    ),
                    splashRadius: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _parseNoteColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = int.tryParse(hex, radix: 16);
    return value != null ? Color(value) : null;
  }

  Color _indicatorColor() {
    final noteColor = _parseNoteColor(widget.note.color);
    if (noteColor != null) return noteColor;
    return widget.isSelected ? widget.accentColor : Colors.grey.shade300;
  }

  Widget _buildSyncIcon() {
    final nc = _parseNoteColor(widget.note.color);
    IconData icon;
    Color color;

    switch (widget.note.syncStatus.name) {
      case 'synced':
        icon = Icons.cloud_done_outlined;
        color = nc != null ? Colors.white70 : Colors.green.shade400;
        break;
      case 'pendingSync':
        icon = Icons.cloud_upload_outlined;
        color = nc != null ? Colors.white70 : Colors.orange.shade400;
        break;
      default:
        icon = Icons.cloud_off_outlined;
        color = nc != null ? Colors.white70 : Colors.grey.shade400;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Icon(icon, size: 16, color: color),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.month}/${date.day}/${date.year}';
  }
}
