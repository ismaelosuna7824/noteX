import 'package:flutter/material.dart';

import '../../domain/entities/note.dart';
import '../../domain/services/force_layout.dart';
import '../../domain/services/note_graph.dart';
import '../state/app_state.dart';
import '../state/theme_state.dart';
import '../widgets/note_graph_view.dart';

/// The link graph of the whole library.
class GraphPage extends StatefulWidget {
  final AppState appState;
  final ThemeState themeState;

  const GraphPage({super.key, required this.appState, required this.themeState});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  /// Space the layout is solved in. Fixed rather than tied to the window so
  /// resizing never rearranges a graph someone has been reading — the view
  /// pans and zooms over it instead.
  static const _layoutSize = Size(1600, 1100);

  late NoteGraph _graph;
  late Map<String, LayoutPoint> _positions;

  /// Signature of the input the current layout was solved from, so it is only
  /// recomputed when the links actually changed — not on every rebuild.
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _rebuild();
    widget.appState.addListener(_onNotesChanged);
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onNotesChanged);
    super.dispose();
  }

  void _onNotesChanged() {
    if (!mounted) return;
    if (_signatureOf(widget.appState.notes) != _signature) setState(_rebuild);
  }

  /// Fingerprint of the notes the graph was solved from.
  ///
  /// Built from ids and timestamps rather than by building the graph and
  /// comparing it: parsing every note's Markdown just to find out whether
  /// anything changed would do the expensive half of the work on every check.
  /// A note whose links changed also changed its updatedAt.
  String _signatureOf(List<Note> notes) => notes
      .where((note) => note.deletedAt == null)
      .map((note) => '${note.id}:${note.updatedAt.millisecondsSinceEpoch}')
      .join(',');

  void _rebuild() {
    _graph = NoteGraph.build(notes: widget.appState.notes);
    _positions = ForceLayout.run(
      graph: _graph,
      width: _layoutSize.width,
      height: _layoutSize.height,
    );
    _signature = _signatureOf(widget.appState.notes);
  }

  Future<void> _openNote(String noteId) async {
    final note = widget.appState.notes.where((n) => n.id == noteId).firstOrNull;
    if (note == null) return;

    await widget.appState.selectNote(note);
    // Index 2 is the note editor in the app shell.
    await widget.appState.navigateToPage(2);
  }

  @override
  Widget build(BuildContext context) {
    // Only the accent colour is watched here; note changes come through the
    // listener above, which decides whether the layout is worth re-solving.
    return ListenableBuilder(
      listenable: widget.themeState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final accentColor = widget.themeState.accentColor;
        final linkedCount = _graph.nodes.where((n) => n.degree > 0).length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Graph',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_graph.nodes.length} notes · ${_graph.edges.length} links',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    // Near-opaque on purpose. A graph is thin lines and small
                    // dots — the least forgiving thing to draw over a photo,
                    // and at the card opacity used elsewhere the wallpaper won
                    // outright.
                    color: Color.alphaBlend(
                      widget.themeState.editorBgColor.withValues(alpha: 0.96),
                      isDark ? Colors.black : Colors.white,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.08),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _graph.isEmpty
                      ? _EmptyState(isDark: isDark)
                      : Stack(
                          children: [
                            NoteGraphView(
                              graph: _graph,
                              positions: _positions,
                              accentColor: accentColor,
                              onOpenNote: _openNote,
                            ),

                            // Says what to do without a tutorial, and says the
                            // uncomfortable part out loud when there is
                            // nothing connected yet.
                            Positioned(
                              left: 16,
                              bottom: 16,
                              child: Text(
                                linkedCount == 0
                                    ? 'No links yet — type @ in a note to connect it to another'
                                    : 'Click a note to focus it · click again to open · drag to move',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;

  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white38 : Colors.black38;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 44, color: muted),
          const SizedBox(height: 14),
          Text('Nothing to graph yet', style: TextStyle(fontSize: 15, color: muted)),
          const SizedBox(height: 6),
          Text(
            'Write a note, then type @ to link it to another',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
  }
}
