import 'dart:math' as math;

import 'note_graph.dart';

/// A position in layout space.
///
/// Deliberately not `Offset`: that lives in `dart:ui`, and keeping this in
/// plain Dart is what lets the whole simulation be tested without a Flutter
/// binding.
class LayoutPoint {
  final double x;
  final double y;

  const LayoutPoint(this.x, this.y);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Positions graph nodes by simulating physical forces.
///
/// Every node pushes every other away; every edge pulls its two ends together.
/// Run those against each other while steadily lowering how far anything may
/// move per step, and the graph settles into a shape where connected notes sit
/// near each other and unconnected ones drift apart — which is the whole point
/// of looking at it.
///
/// Pure and deterministic: the same graph and seed always produce the same
/// layout, so a test can assert on positions and a user does not get a
/// different picture every time they open the view.
class ForceLayout {
  const ForceLayout._();

  /// Enough passes for a library-sized graph to stop moving visibly.
  static const defaultIterations = 400;

  /// Runs the simulation and returns a position per node id.
  static Map<String, LayoutPoint> run({
    required NoteGraph graph,
    required double width,
    required double height,
    int iterations = defaultIterations,
    int seed = 42,
  }) {
    if (graph.nodes.isEmpty) return const {};

    final random = math.Random(seed);
    final area = width * height;

    // Fruchterman-Reingold's ideal separation: the spacing at which nodes
    // would evenly fill the canvas if nothing pulled them together.
    final k = math.sqrt(area / graph.nodes.length);

    // Start scattered rather than in a line: a symmetric start has no
    // direction to resolve in and the simulation can sit in it forever.
    final positions = <String, _Vec>{
      for (final node in graph.nodes)
        node.id: _Vec(
          random.nextDouble() * width,
          random.nextDouble() * height,
        ),
    };

    // Nodes may move a whole canvas-tenth at first and almost nothing at the
    // end. Without this cooling the graph oscillates instead of settling.
    var temperature = width / 10;
    final cooling = temperature / (iterations + 1);

    for (var step = 0; step < iterations; step++) {
      final displacement = <String, _Vec>{
        for (final node in graph.nodes) node.id: const _Vec(0, 0),
      };

      // Repulsion: every pair, computed once and applied to both.
      for (var i = 0; i < graph.nodes.length; i++) {
        for (var j = i + 1; j < graph.nodes.length; j++) {
          final a = graph.nodes[i].id;
          final b = graph.nodes[j].id;

          var delta = positions[a]! - positions[b]!;
          var distance = delta.length;

          // Two nodes landing on the same point would divide by zero; nudge
          // them apart with a deterministic jitter rather than a random one.
          if (distance < 0.01) {
            delta = _Vec(0.01 * (i + 1), 0.01 * (j + 1));
            distance = delta.length;
          }

          final force = (k * k) / distance;
          final push = delta / distance * force;

          displacement[a] = displacement[a]! + push;
          displacement[b] = displacement[b]! - push;
        }
      }

      // Attraction along edges.
      for (final edge in graph.edges) {
        final source = positions[edge.sourceId];
        final target = positions[edge.targetId];
        if (source == null || target == null) continue;

        final delta = source - target;
        final distance = math.max(delta.length, 0.01);
        final force = (distance * distance) / k;
        final pull = delta / distance * force;

        displacement[edge.sourceId] = displacement[edge.sourceId]! - pull;
        displacement[edge.targetId] = displacement[edge.targetId]! + pull;
      }

      // Apply, capped by temperature and clamped inside the canvas.
      for (final node in graph.nodes) {
        final move = displacement[node.id]!;
        final distance = math.max(move.length, 0.01);
        final capped = move / distance * math.min(distance, temperature);

        final next = positions[node.id]! + capped;
        positions[node.id] = _Vec(
          next.x.clamp(0.0, width),
          next.y.clamp(0.0, height),
        );
      }

      temperature = math.max(temperature - cooling, 0.01);
    }

    return {
      for (final entry in positions.entries)
        entry.key: LayoutPoint(entry.value.x, entry.value.y),
    };
  }
}

/// Minimal 2D vector, private to the simulation.
class _Vec {
  final double x;
  final double y;

  const _Vec(this.x, this.y);

  double get length => math.sqrt(x * x + y * y);

  _Vec operator +(_Vec other) => _Vec(x + other.x, y + other.y);
  _Vec operator -(_Vec other) => _Vec(x - other.x, y - other.y);
  _Vec operator *(double scalar) => _Vec(x * scalar, y * scalar);
  _Vec operator /(double scalar) => _Vec(x / scalar, y / scalar);
}
