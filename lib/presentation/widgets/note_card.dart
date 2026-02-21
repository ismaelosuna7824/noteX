import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';
import 'glassmorphic_container.dart';

/// A card representing a note preview in the notes list.
///
/// Shows title, creation date, and a content preview snippet.
class NoteCard extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;
  final Color accentColor;

  const NoteCard({
    super.key,
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onPin,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassmorphicContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      opacity: isSelected ? 0.25 : 0.12,
      blur: isSelected ? 14 : 8,
      border: isSelected
          ? Border.all(color: accentColor.withValues(alpha: 0.5), width: 2)
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Color indicator
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color:
                    isSelected ? accentColor : Colors.grey.shade300,
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
                    note.title.isEmpty ? 'Untitled' : note.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(note.updatedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),

            // Sync indicator
            _buildSyncIcon(),

            // Pin button
            if (onPin != null)
              IconButton(
                onPressed: onPin,
                icon: Icon(
                  note.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  size: 18,
                  color: note.isPinned ? accentColor : Colors.grey.shade400,
                ),
                splashRadius: 18,
              ),

            // Delete button
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                splashRadius: 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncIcon() {
    IconData icon;
    Color color;

    switch (note.syncStatus.name) {
      case 'synced':
        icon = Icons.cloud_done_outlined;
        color = Colors.green.shade400;
        break;
      case 'pendingSync':
        icon = Icons.cloud_upload_outlined;
        color = Colors.orange.shade400;
        break;
      default:
        icon = Icons.cloud_off_outlined;
        color = Colors.grey.shade400;
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
