import '../entities/note.dart';
import 'note_link_parser.dart';

/// One note in the graph.
class GraphNode {
  final String id;
  final String title;

  /// How many links touch this note, counting both directions.
  ///
  /// Drives how large the node is drawn: the notes everything points at
  /// should be the ones you see first.
  final int degree;

  const GraphNode({required this.id, required this.title, required this.degree});
}

/// A link from one note to another.
class GraphEdge {
  final String sourceId;
  final String targetId;

  const GraphEdge({required this.sourceId, required this.targetId});

  /// Order-independent key, for collapsing a mutual link into one line.
  String get undirectedKey =>
      sourceId.compareTo(targetId) <= 0 ? '$sourceId|$targetId' : '$targetId|$sourceId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphEdge && sourceId == other.sourceId && targetId == other.targetId;

  @override
  int get hashCode => Object.hash(sourceId, targetId);
}

/// The link graph of a note library.
class NoteGraph {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  const NoteGraph({required this.nodes, required this.edges});

  bool get isEmpty => nodes.isEmpty;

  /// Ids linked to [id] in either direction — what to highlight when a node
  /// is hovered or selected.
  Set<String> neighboursOf(String id) {
    final result = <String>{};
    for (final edge in edges) {
      if (edge.sourceId == id) result.add(edge.targetId);
      if (edge.targetId == id) result.add(edge.sourceId);
    }
    return result;
  }

  /// Builds the graph by reading links straight out of note bodies.
  ///
  /// Derived on demand rather than kept in a table. An index earns its keep
  /// when the same narrow question ("what points at this one note") is asked
  /// repeatedly; a graph asks the whole question once, and parsing a library
  /// of Markdown is a few milliseconds of regex.
  ///
  /// Isolated notes are kept. A graph that shows only the connected quarter
  /// of a library looks broken, and the unconnected notes are exactly the ones
  /// a person opens this view to notice.
  static NoteGraph build({required List<Note> notes}) {
    final live = notes.where((n) => n.deletedAt != null ? false : true).toList();
    final byId = {for (final note in live) note.id: note};

    final seen = <String>{};
    final edges = <GraphEdge>[];
    final degree = <String, int>{};

    for (final note in live) {
      for (final targetId in NoteLinkParser.targetsIn(note.content)) {
        // A link to a note that was deleted, or to nothing at all, is not an
        // edge — drawing it would mean drawing a node that does not exist.
        if (!byId.containsKey(targetId)) continue;
        if (targetId == note.id) continue;

        final edge = GraphEdge(sourceId: note.id, targetId: targetId);
        // Mutual links are one line, not two stacked on the same pixels.
        if (!seen.add(edge.undirectedKey)) continue;

        edges.add(edge);
        degree[note.id] = (degree[note.id] ?? 0) + 1;
        degree[targetId] = (degree[targetId] ?? 0) + 1;
      }
    }

    final nodes = live
        .map((note) => GraphNode(
              id: note.id,
              title: note.title.trim().isEmpty ? 'Untitled' : note.title,
              degree: degree[note.id] ?? 0,
            ))
        .toList()
      // Most-connected first, so drawing order puts the hubs on top.
      ..sort((a, b) {
        final byDegree = b.degree.compareTo(a.degree);
        return byDegree != 0 ? byDegree : a.id.compareTo(b.id);
      });

    return NoteGraph(nodes: nodes, edges: edges);
  }
}
