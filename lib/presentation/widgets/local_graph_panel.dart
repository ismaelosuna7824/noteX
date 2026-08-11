import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../../domain/services/force_layout.dart';
import '../../domain/services/note_graph.dart';
import 'note_graph_view.dart';

/// The neighbourhood of one note: what it links to, and what links back.
///
/// Built from the same [NoteGraph] as the full view and then narrowed, rather
/// than from a second traversal — one definition of "connected" for the whole
/// app.
class LocalGraphPanel extends StatefulWidget {
  final List<Note> notes;
  final String noteId;
  final Color accentColor;
  final Color surfaceColor;
  final ValueChanged<String> onOpenNote;
  final VoidCallback onClose;

  const LocalGraphPanel({
    super.key,
    required this.notes,
    required this.noteId,
    required this.accentColor,
    required this.surfaceColor,
    required this.onOpenNote,
    required this.onClose,
  });

  @override
  State<LocalGraphPanel> createState() => _LocalGraphPanelState();
}

class _LocalGraphPanelState extends State<LocalGraphPanel> {
  /// Space the neighbourhood is solved in. Generous on purpose: the view fits
  /// the result down to whatever width the panel ends up with, and solving
  /// into a cramped box would crowd the nodes before it ever got the chance.
  static const _layoutSize = Size(900, 640);

  late NoteGraph _graph;
  late Map<String, LayoutPoint> _positions;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant LocalGraphPanel old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId || !identical(old.notes, widget.notes)) {
      _rebuild();
    }
  }

  void _rebuild() {
    final full = NoteGraph.build(notes: widget.notes);

    // One hop out. Two would pull in half the library and stop being "related
    // to this note"; zero would be a single dot.
    final neighbours = full.neighboursOf(widget.noteId);
    final visible = {widget.noteId, ...neighbours};

    _graph = NoteGraph(
      nodes: full.nodes.where((n) => visible.contains(n.id)).toList(),
      edges: full.edges
          .where((e) => visible.contains(e.sourceId) && visible.contains(e.targetId))
          .toList(),
    );

    _positions = ForceLayout.run(
      graph: _graph,
      width: _layoutSize.width,
      height: _layoutSize.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white38 : Colors.black38;
    final linkCount = _graph.nodes.length - 1;

    return Container(
      // Width comes from the parent's flex share, not from here.
      margin: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        // Opaque like the full graph view: thin lines and small dots are the
        // least forgiving thing to draw over a wallpaper.
        color: Color.alphaBlend(
          widget.surfaceColor.withValues(alpha: 0.96),
          isDark ? Colors.black : Colors.white,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.hub_rounded, size: 15, color: widget.accentColor),
                const SizedBox(width: 8),
                Text(
                  linkCount == 1 ? '1 related note' : '$linkCount related notes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: muted,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Hide related notes',
                ),
              ],
            ),
          ),

          Expanded(
            child: linkCount == 0
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Nothing links to this note yet.\nType @ to connect it to another.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                      ),
                    ),
                  )
                : NoteGraphView(
                    graph: _graph,
                    positions: _positions,
                    accentColor: widget.accentColor,
                    surfaceColor: widget.surfaceColor,
                    onOpenNote: widget.onOpenNote,
                  ),
          ),
        ],
      ),
    );
  }
}
