import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/animated_dialog.dart';

/// Page displaying soft-deleted notes with restore and permanent delete options.
/// Follows the same container/card pattern as ReminderPage.
class TrashPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const TrashPage({
    super.key,
    required this.appState,
    required this.themeState,
  });

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  @override
  void initState() {
    super.initState();
    widget.appState.loadTrash();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = widget.themeState.accentColor;
    final trashedNotes = widget.appState.trashedNotes;

    final cardColor =
        widget.themeState.editorBgColor.withValues(alpha: isDark ? 0.90 : 0.95);
    final cardBorder = widget.themeState.editorBorderColor;
    final cardShadow = Colors.black.withValues(alpha: isDark ? 0.30 : 0.04);
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.10) : Colors.grey.shade200;
    final mutedText = widget.themeState.editorMutedTextColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: cardShadow,
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 22, color: accentColor),
                const SizedBox(width: 10),
                Text(
                  'Trash',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                if (trashedNotes.isNotEmpty)
                  Text(
                    '${trashedNotes.length} note${trashedNotes.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: mutedText),
                  ),
                const Spacer(),
                if (trashedNotes.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _showEmptyTrashDialog(),
                    icon: const Icon(Icons.delete_forever_rounded, size: 18),
                    label: const Text('Empty Trash'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Divider(color: dividerColor),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: trashedNotes.isEmpty
                  ? _buildEmptyState(theme, isDark, accentColor)
                  : ListView.builder(
                      itemCount: trashedNotes.length,
                      itemBuilder: (context, index) {
                        final note = trashedNotes[index];
                        return _buildTrashTile(
                          note, theme, isDark, accentColor, dividerColor,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark, Color accentColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 56,
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Trash is empty',
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.40)
                  : Colors.grey.shade400,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Deleted notes will appear here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrashTile(
    Note note,
    ThemeData theme,
    bool isDark,
    Color accentColor,
    Color dividerColor,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // Red indicator dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red.shade300,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),

              // Note info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Deleted ${_formatDeletedDate(note.deletedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: widget.themeState.editorMutedTextColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Restore
              IconButton(
                onPressed: () async {
                  await widget.appState.restoreNote(note.id);
                  if (mounted) setState(() {});
                },
                icon: Icon(Icons.restore_rounded, size: 20, color: accentColor),
                tooltip: 'Restore',
                splashRadius: 20,
              ),

              // Permanent delete
              IconButton(
                onPressed: () => _showPermanentDeleteDialog(note),
                icon: Icon(Icons.delete_forever_rounded,
                    size: 20, color: Colors.red.shade400),
                tooltip: 'Delete permanently',
                splashRadius: 20,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
      ],
    );
  }

  void _showPermanentDeleteDialog(Note note) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'This will permanently delete "${note.title.isEmpty ? 'Untitled' : note.title}". '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await widget.appState.permanentDeleteNote(note.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
  }

  void _showEmptyTrashDialog() {
    final count = widget.appState.trashedNotes.length;
    showAnimatedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text(
          'This will permanently delete $count note${count == 1 ? '' : 's'}. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await widget.appState.emptyTrash();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Empty trash'),
          ),
        ],
      ),
    );
  }

  String _formatDeletedDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
