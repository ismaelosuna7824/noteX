import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/services/force_layout.dart';
import 'package:notex/domain/services/note_graph.dart';

void main() {
  const width = 800.0;
  const height = 600.0;

  NoteGraph graphOf(List<String> ids, List<List<String>> links) => NoteGraph(
        nodes: [
          for (final id in ids) GraphNode(id: id, title: id, degree: 0),
        ],
        edges: [
          for (final link in links) GraphEdge(sourceId: link[0], targetId: link[1]),
        ],
      );

  Map<String, LayoutPoint> layout(NoteGraph graph, {int seed = 42}) =>
      ForceLayout.run(graph: graph, width: width, height: height, seed: seed);

  double distance(LayoutPoint a, LayoutPoint b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

  test('an empty graph lays out to nothing', () {
    expect(layout(graphOf([], [])), isEmpty);
  });

  test('every node gets a position', () {
    final positions = layout(graphOf(['a', 'b', 'c'], []));
    expect(positions.keys, containsAll(['a', 'b', 'c']));
  });

  test('nodes stay inside the canvas', () {
    final positions = layout(graphOf(['a', 'b', 'c', 'd', 'e'], [
      ['a', 'b'],
      ['b', 'c'],
    ]));

    for (final point in positions.values) {
      expect(point.x, inInclusiveRange(0, width));
      expect(point.y, inInclusiveRange(0, height));
    }
  });

  test('the same graph and seed always produce the same layout', () {
    final graph = graphOf(['a', 'b', 'c'], [
      ['a', 'b'],
    ]);

    final first = layout(graph);
    final second = layout(graph);

    for (final id in first.keys) {
      expect(first[id]!.x, closeTo(second[id]!.x, 0.0001));
      expect(first[id]!.y, closeTo(second[id]!.y, 0.0001));
    }
  });

  test('connected notes end up closer than unconnected ones', () {
    // The entire reason this simulation exists: a and b are linked, c is not
    // attached to anything, so a-b should close while c is pushed away.
    final positions = layout(graphOf(['a', 'b', 'c'], [
      ['a', 'b'],
    ]));

    final linked = distance(positions['a']!, positions['b']!);
    final loose = math.min(
      distance(positions['a']!, positions['c']!),
      distance(positions['b']!, positions['c']!),
    );

    expect(linked, lessThan(loose));
  });

  test('a hub sits nearer its spokes than the spokes sit to each other', () {
    final positions = layout(graphOf(['hub', 'a', 'b', 'c'], [
      ['hub', 'a'],
      ['hub', 'b'],
      ['hub', 'c'],
    ]));

    final hubToSpokes = [
      distance(positions['hub']!, positions['a']!),
      distance(positions['hub']!, positions['b']!),
      distance(positions['hub']!, positions['c']!),
    ].reduce((a, b) => a + b) / 3;

    final betweenSpokes = [
      distance(positions['a']!, positions['b']!),
      distance(positions['b']!, positions['c']!),
      distance(positions['a']!, positions['c']!),
    ].reduce((a, b) => a + b) / 3;

    expect(hubToSpokes, lessThan(betweenSpokes));
  });

  test('nodes never land on top of each other', () {
    final positions = layout(graphOf(['a', 'b', 'c', 'd'], []));
    final points = positions.values.toList();

    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        expect(distance(points[i], points[j]), greaterThan(1.0));
      }
    }
  });

  test('two separate clusters do not tangle together', () {
    final positions = layout(graphOf(['a1', 'a2', 'b1', 'b2'], [
      ['a1', 'a2'],
      ['b1', 'b2'],
    ]));

    final withinA = distance(positions['a1']!, positions['a2']!);
    final withinB = distance(positions['b1']!, positions['b2']!);
    final across = distance(positions['a1']!, positions['b1']!);

    expect(withinA, lessThan(across));
    expect(withinB, lessThan(across));
  });

  test('a different seed gives a different arrangement', () {
    final graph = graphOf(['a', 'b', 'c'], []);

    final first = layout(graph, seed: 1);
    final second = layout(graph, seed: 2);

    final moved = first.keys.any((id) => distance(first[id]!, second[id]!) > 1.0);
    expect(moved, isTrue);
  });
}
