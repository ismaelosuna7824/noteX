import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/services/note_graph.dart';

void main() {
  Note note({
    required String id,
    String title = 'Note',
    String content = '',
    DateTime? deletedAt,
  }) =>
      Note(
        id: id,
        title: title,
        content: content,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        deletedAt: deletedAt,
      );

  String linkTo(String id, [String text = 'see']) => '[$text](notex://$id)';

  NoteGraph build(List<Note> notes) => NoteGraph.build(notes: notes);

  group('nodes', () {
    test('every live note becomes a node, linked or not', () {
      final graph = build([
        note(id: 'a', content: linkTo('b')),
        note(id: 'b'),
        note(id: 'lonely'),
      ]);

      expect(graph.nodes.map((n) => n.id), containsAll(['a', 'b', 'lonely']));
    });

    test('an untitled note still gets a label', () {
      expect(build([note(id: 'a', title: '  ')]).nodes.single.title, 'Untitled');
    });

    test('degree counts links in both directions', () {
      final graph = build([
        note(id: 'hub'),
        note(id: 'a', content: linkTo('hub')),
        note(id: 'b', content: linkTo('hub')),
      ]);

      final hub = graph.nodes.firstWhere((n) => n.id == 'hub');
      expect(hub.degree, 2);
      expect(graph.nodes.firstWhere((n) => n.id == 'a').degree, 1);
    });

    test('nodes come out ordered by degree, so hubs draw on top', () {
      final graph = build([
        note(id: 'lonely'),
        note(id: 'hub'),
        note(id: 'a', content: linkTo('hub')),
        note(id: 'b', content: linkTo('hub')),
      ]);

      // The invariant is the ordering itself. Asserting which of two
      // equally-connected notes wins the tie would be pinning an arbitrary
      // detail, and it is the kind of assertion that breaks for no reason.
      final degrees = graph.nodes.map((n) => n.degree).toList();
      expect(degrees, orderedEquals([...degrees]..sort((a, b) => b.compareTo(a))));

      expect(graph.nodes.first.id, 'hub', reason: 'hub has the highest degree');
      expect(graph.nodes.last.id, 'lonely', reason: 'lonely has none');
    });
  });

  group('edges', () {
    test('a link becomes an edge', () {
      final graph = build([note(id: 'a', content: linkTo('b')), note(id: 'b')]);

      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.sourceId, 'a');
      expect(graph.edges.single.targetId, 'b');
    });

    test('a mutual link is one line, not two on the same pixels', () {
      final graph = build([
        note(id: 'a', content: linkTo('b')),
        note(id: 'b', content: linkTo('a')),
      ]);

      expect(graph.edges, hasLength(1));
    });

    test('repeating the same link in one note adds nothing', () {
      final graph = build([
        note(id: 'a', content: '${linkTo('b', 'once')} ${linkTo('b', 'twice')}'),
        note(id: 'b'),
      ]);

      expect(graph.edges, hasLength(1));
    });

    test('a link to a note that no longer exists is not an edge', () {
      final graph = build([note(id: 'a', content: linkTo('ghost'))]);

      expect(graph.edges, isEmpty);
      expect(graph.nodes.single.degree, 0);
    });

    test('a link to a trashed note is not an edge', () {
      final graph = build([
        note(id: 'a', content: linkTo('gone')),
        note(id: 'gone', deletedAt: DateTime(2026, 5, 1)),
      ]);

      expect(graph.edges, isEmpty);
    });

    test('a note linking to itself makes no loop', () {
      final graph = build([note(id: 'a', content: linkTo('a'))]);

      expect(graph.edges, isEmpty);
    });

    test('links inside code blocks are documentation, not connections', () {
      final graph = build([
        note(id: 'a', content: 'how to link:\n```\n${linkTo('b')}\n```'),
        note(id: 'b'),
      ]);

      expect(graph.edges, isEmpty);
    });
  });

  group('neighbours', () {
    test('finds links in both directions', () {
      final graph = build([
        note(id: 'centre', content: linkTo('out')),
        note(id: 'out'),
        note(id: 'in', content: linkTo('centre')),
        note(id: 'unrelated'),
      ]);

      expect(graph.neighboursOf('centre'), {'out', 'in'});
      expect(graph.neighboursOf('unrelated'), isEmpty);
    });
  });

  test('an empty library produces an empty graph', () {
    expect(build([]).isEmpty, isTrue);
  });
}
