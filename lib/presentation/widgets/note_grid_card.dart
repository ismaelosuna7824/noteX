import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';
import 'glassmorphic_container.dart';

/// A card for the masonry grid view in My Notes.
///
/// Shows title, date, content preview, and action buttons on hover.
/// Variable height based on content length creates the masonry stagger effect.
class NoteGridCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final VoidCallback? onCompactMode;
  final Color accentColor;
  final Color? editorBgColor;

  const NoteGridCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onDelete,
    this.onPin,
    this.onCompactMode,
    required this.accentColor,
    this.editorBgColor,
  });

  @override
  State<NoteGridCard> createState() => _NoteGridCardState();
}

class _NoteGridCardState extends State<NoteGridCard> {
  bool _hovered = false;

  Color? _parseNoteColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = int.tryParse(hex, radix: 16);
    return value != null ? Color(value) : null;
  }

  int _previewMaxLines() {
    final len = widget.note.plainTextPreview.length;
    if (len < 40) return 2;
    if (len < 100) return 4;
    return 6;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteColor = _parseNoteColor(widget.note.color);
    final cardColor = noteColor ?? widget.editorBgColor;
    final borderColor = noteColor ?? widget.accentColor;
    final hasNoteColor = noteColor != null;
    final preview = widget.note.plainTextPreview;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 16,
          color: cardColor,
          opacity: hasNoteColor
              ? (_hovered ? 0.32 : 0.22)
              : (_hovered ? 0.18 : 0.12),
          blur: _hovered ? 12 : 8,
          border: Border.all(
            color: _hovered
                ? borderColor.withValues(alpha: 0.30)
                : Colors.transparent,
            width: 1.5,
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top color bar
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: noteColor ?? widget.accentColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title + sync icon row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.note.title.isEmpty
                                ? 'Untitled'
                                : widget.note.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: hasNoteColor ? Colors.white : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildSyncIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Date
                    Text(
                      _formatDate(widget.note.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hasNoteColor ? Colors.white60 : Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),

                    // Content preview
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        preview,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasNoteColor
                              ? Colors.white70
                              : theme.textTheme.bodySmall?.color
                                      ?.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                        maxLines: _previewMaxLines(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Pinned indicator
                    if (widget.note.isPinned) ...[
                      const SizedBox(height: 8),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: hasNoteColor
                            ? Colors.white60
                            : widget.accentColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),

                // Hover action buttons — overlay so they don't change card height
                if (_hovered)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onCompactMode != null)
                          _ActionButton(
                            icon: Icons.sticky_note_2_outlined,
                            color: hasNoteColor
                                ? Colors.white70
                                : Colors.grey.shade400,
                            onTap: widget.onCompactMode!,
                            tooltip: 'Sticky Note',
                          ),
                        if (widget.onPin != null) ...[
                          const SizedBox(width: 4),
                          _ActionButton(
                            icon: widget.note.isPinned
                                ? Icons.push_pin_rounded
                                : Icons.push_pin_outlined,
                            color: hasNoteColor
                                ? Colors.white70
                                : Colors.grey.shade400,
                            onTap: widget.onPin!,
                            tooltip: widget.note.isPinned ? 'Unpin' : 'Pin',
                          ),
                        ],
                        if (widget.onDelete != null) ...[
                          const SizedBox(width: 4),
                          _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            color: hasNoteColor
                                ? Colors.white70
                                : Colors.grey.shade400,
                            onTap: widget.onDelete!,
                            tooltip: 'Delete',
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildSyncIcon() {
    final nc = _parseNoteColor(widget.note.color);
    IconData icon;
    Color color;

    switch (widget.note.syncStatus.name) {
      case 'synced':
        icon = Icons.cloud_done_outlined;
        color = nc != null ? Colors.white54 : Colors.green.shade400;
        break;
      case 'pendingSync':
        icon = Icons.cloud_upload_outlined;
        color = nc != null ? Colors.white54 : Colors.orange.shade400;
        break;
      default:
        icon = Icons.cloud_off_outlined;
        color = nc != null ? Colors.white54 : Colors.grey.shade400;
    }

    return Icon(icon, size: 14, color: color);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
