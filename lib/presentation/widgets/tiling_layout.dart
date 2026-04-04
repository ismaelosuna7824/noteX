import 'package:flutter/material.dart';
import '../../domain/entities/note.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../state/tiling_state.dart';
import 'tiling_editor_panel.dart';

/// Arranges [TilingEditorPanel]s with smooth Hyprland-style transitions.
class TilingLayoutWidget extends StatefulWidget {
  final TilingState tiling;
  final AppState appState;
  final ThemeState themeState;
  final Color accentColor;
  final VoidCallback onChanged;

  const TilingLayoutWidget({
    super.key,
    required this.tiling,
    required this.appState,
    required this.themeState,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  State<TilingLayoutWidget> createState() => _TilingLayoutWidgetState();
}

class _TilingLayoutWidgetState extends State<TilingLayoutWidget> {
  int _prevCount = 0;

  @override
  Widget build(BuildContext context) {
    final notes = widget.tiling.orderedNotes;

    if (notes.isEmpty) {
      return _buildEmptyState(context);
    }

    // No animation for single note (it's just fullscreen)
    if (notes.length == 1) {
      _prevCount = 1;
      return _buildRawPanel(context, notes[0]);
    }

    _prevCount = notes.length;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(
        key: ValueKey('tiling_layout_${notes.length}'),
        child: _buildLayout(context, notes),
      ),
    );
  }

  // ── Layouts ─────────────────────────────────────────────────────────

  Widget _buildLayout(BuildContext context, List<Note> notes) {
    switch (notes.length) {
      case 1:
        return _buildPanel(context, notes[0]);

      case 2:
        return Row(
          children: [
            Expanded(child: _buildPanel(context, notes[0])),
            const SizedBox(width: 6),
            Expanded(child: _buildPanel(context, notes[1])),
          ],
        );

      case 3:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildPanel(context, notes[0])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildPanel(context, notes[1])),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _buildPanel(context, notes[2])),
          ],
        );

      case 4:
      default:
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildPanel(context, notes[0])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildPanel(context, notes[1])),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildPanel(context, notes[2])),
                  const SizedBox(width: 6),
                  Expanded(child: _buildPanel(context, notes[3])),
                ],
              ),
            ),
          ],
        );
    }
  }

  // ── Builders ───────────────────────────────────────────────────────

  /// Panel without enter animation (used for single-note / already visible).
  Widget _buildRawPanel(BuildContext context, Note note) {
    return TilingEditorPanel(
      key: ValueKey('tile_${note.id}'),
      note: note,
      appState: widget.appState,
      themeState: widget.themeState,
      accentColor: widget.accentColor,
      tiling: widget.tiling,
      onClose: () { widget.tiling.removeNote(note.id); widget.onChanged(); },
    );
  }

  /// Panel with scale+fade enter animation.
  Widget _buildPanel(BuildContext context, Note note) {
    return _AnimatedTileEntry(
      key: ValueKey('tile_anim_${note.id}'),
      child: TilingEditorPanel(
        key: ValueKey('tile_${note.id}'),
        note: note,
        appState: widget.appState,
        themeState: widget.themeState,
        accentColor: widget.accentColor,
        tiling: widget.tiling,
        onClose: () { widget.tiling.removeNote(note.id); widget.onChanged(); },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editorBg = widget.themeState.editorBgColor;
    final chipBorder = widget.themeState.editorBorderColor;
    final chipText = isDark ? Colors.white70 : Colors.grey.shade600;

    return Container(
      decoration: BoxDecoration(
        color: editorBg.withValues(alpha: isDark ? 0.90 : 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: chipBorder, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _showNotePicker(context),
              icon: Icon(Icons.add_rounded, size: 32, color: chipText),
              tooltip: 'Add note',
            ),
            const SizedBox(height: 8),
            Text('Add a note to tiling',
                style: TextStyle(fontSize: 13, color: chipText)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () { widget.tiling.exitTiling(); widget.onChanged(); },
              child: Text('Cancel',
                  style: TextStyle(fontSize: 12, color: chipText)),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotePicker(BuildContext context) {
    final tiledIds = widget.tiling.tiledNotes.map((n) => n.id).toSet();
    final available = widget.appState.notes
        .where((n) => !tiledIds.contains(n.id))
        .toList();

    showDialog<Note>(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final chipText = isDark ? Colors.white70 : Colors.grey.shade600;

        return SimpleDialog(
          title: const Text('Select a note',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          children: [
            // Create new note option
            ListTile(
              leading: Icon(Icons.add_rounded, color: widget.accentColor),
              title: Text('Create new note',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor)),
              onTap: () async {
                final newNote = await widget.appState.createNewNote();
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(newNote);
                }
              },
            ),
            const Divider(height: 1),
            if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No existing notes available',
                    style: TextStyle(fontSize: 13, color: chipText),
                    textAlign: TextAlign.center),
              )
            else
              SizedBox(
                width: 340,
                height: 300,
                child: ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (ctx, i) {
                    final note = available[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        note.title.isEmpty ? 'Untitled' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () => Navigator.of(dialogCtx).pop(note),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ).then((selectedNote) {
      if (selectedNote != null) {
        widget.tiling.addNote(selectedNote);
        widget.onChanged();
      }
    });
  }
}

/// Animates a tile panel entry with scale + fade, Hyprland-style.
class _AnimatedTileEntry extends StatefulWidget {
  final Widget child;

  const _AnimatedTileEntry({super.key, required this.child});

  @override
  State<_AnimatedTileEntry> createState() => _AnimatedTileEntryState();
}

class _AnimatedTileEntryState extends State<_AnimatedTileEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: widget.child,
      ),
    );
  }
}
