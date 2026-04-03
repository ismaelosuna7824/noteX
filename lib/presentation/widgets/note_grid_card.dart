import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_project.dart';
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
  final void Function(String? projectId)? onChangeProject;
  final VoidCallback? onDuplicate;
  final List<NoteProject> noteProjects;
  final Color accentColor;
  final Color? editorBgColor;
  final bool isNoteUnlocked;

  const NoteGridCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onDelete,
    this.onPin,
    this.onCompactMode,
    this.onChangeProject,
    this.onDuplicate,
    this.noteProjects = const [],
    required this.accentColor,
    this.editorBgColor,
    this.isNoteUnlocked = false,
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
    final isHidden = widget.note.isLocked && !widget.isNoteUnlocked;
    final preview = isHidden ? '' : widget.note.plainTextPreview;

    return GestureDetector(
      onSecondaryTapUp: widget.onChangeProject != null
          ? (details) => _showCategoryMenu(details.globalPosition)
          : null,
      child: MouseRegion(
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

                    // Title + badges row
                    Row(
                      children: [
                        if (isHidden)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 14,
                              color: hasNoteColor
                                  ? Colors.white60
                                  : Colors.grey.shade500,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            isHidden
                                ? 'Locked Note'
                                : (widget.note.title.isEmpty
                                    ? 'Untitled'
                                    : widget.note.title),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: hasNoteColor ? Colors.white : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.note.isEphemeral)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: 'Quick Note — auto-deletes in 24h',
                              child: Icon(
                                Icons.bolt_rounded,
                                size: 14,
                                color: hasNoteColor
                                    ? Colors.white60
                                    : Colors.amber.shade600,
                              ),
                            ),
                          ),
                        _buildSyncIcon(),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Date (hidden for locked notes)
                    if (!isHidden)
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
      ),
    );
  }

  void _showCategoryMenu(Offset position) async {
    final projects = widget.noteProjects;
    final currentProjectId = widget.note.projectId;

    final result = await showMenu<String?>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,
      ),
      items: [
        if (widget.onDuplicate != null)
          PopupMenuItem<String?>(
            value: '__duplicate__',
            child: Row(
              children: [
                Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                const Text('Duplicate', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        if (widget.onDuplicate != null)
          const PopupMenuDivider(),
        PopupMenuItem<String?>(
          value: '__none__',
          child: Row(
            children: [
              Icon(Icons.label_off_outlined, size: 16,
                  color: currentProjectId == null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('No category',
                  style: TextStyle(fontSize: 13,
                      fontWeight: currentProjectId == null
                          ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
        ...projects.map((p) => PopupMenuItem<String?>(
              value: p.id,
              child: Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: p.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.name,
                        style: TextStyle(fontSize: 13,
                            fontWeight: currentProjectId == p.id
                                ? FontWeight.bold : FontWeight.normal),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (currentProjectId == p.id)
                    Icon(Icons.check, size: 16,
                        color: Theme.of(context).colorScheme.primary),
                ],
              ),
            )),
      ],
    );

    if (result == null) return;
    if (result == '__duplicate__') {
      widget.onDuplicate?.call();
      return;
    }
    final newProjectId = result == '__none__' ? null : result;
    if (newProjectId != currentProjectId) {
      widget.onChangeProject?.call(newProjectId);
    }
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
