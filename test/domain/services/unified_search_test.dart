import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/markdown_file.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/services/unified_search.dart';

void main() {
  Note note({
    String id = 'n1',
    String title = 'Note',
    String content = '',
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Note(
        id: id,
        title: title,
        content: content,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
        deletedAt: deletedAt,
      );

  MarkdownFile file({
    String id = 'f1',
    String title = 'File',
    String content = '',
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      MarkdownFile(
        id: id,
        title: title,
        content: content,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: updatedAt ?? DateTime(2026, 1, 1),
        deletedAt: deletedAt,
      );

  List<SearchHit> run(
    String query, {
    List<Note> notes = const [],
    List<MarkdownFile> files = const [],
  }) =>
      UnifiedSearch.run(query: query, notes: notes, files: files);

  group('both libraries', () {
    test('finds matches in notes and Markdown files alike', () {
      final hits = run(
        'supabase',
        notes: [note(id: 'n', title: 'Supabase keys')],
        files: [file(id: 'f', title: 'supabase setup')],
      );

      expect(hits.map((h) => h.id), containsAll(['n', 'f']));
    });

    test('labels where each hit came from', () {
      final hits = run(
        'x',
        notes: [note(id: 'n', title: 'x')],
        files: [file(id: 'f', title: 'x')],
      );

      expect(
        hits.firstWhere((h) => h.id == 'n').source,
        SearchSource.note,
      );
      expect(
        hits.firstWhere((h) => h.id == 'f').source,
        SearchSource.markdownFile,
      );
    });
  });

  group('what matches', () {
    test('matches title and body, case-insensitively', () {
      expect(run('SUPA', notes: [note(title: 'supabase')]), hasLength(1));
      expect(
        run('supa', notes: [note(title: 'x', content: 'about SUPAbase')]),
        hasLength(1),
      );
    });

    test('an empty or blank query matches nothing', () {
      final everything = [note(title: 'anything')];
      expect(run('', notes: everything), isEmpty);
      expect(run('   ', notes: everything), isEmpty);
    });

    test('a query that matches nothing returns nothing', () {
      expect(run('zzz', notes: [note(title: 'abc')]), isEmpty);
    });

    test('trashed items never surface', () {
      final hits = run(
        'gone',
        notes: [note(id: 'n', title: 'gone', deletedAt: DateTime(2026, 5, 1))],
        files: [file(id: 'f', title: 'gone', deletedAt: DateTime(2026, 5, 1))],
      );
      expect(hits, isEmpty);
    });

    test('an untitled item still shows a label', () {
      expect(run('body', notes: [note(title: '  ', content: 'body')]).single.title,
          UnifiedSearch.untitled);
    });
  });

  group('ordering', () {
    test('title matches rank above body-only matches', () {
      final hits = run(
        'plan',
        notes: [
          note(id: 'body', title: 'Untouched', content: 'the plan is'),
          note(id: 'title', title: 'Plan'),
        ],
      );

      expect(hits.map((h) => h.id), ['title', 'body']);
    });

    test('within a band, the most recently edited comes first', () {
      final hits = run(
        'x',
        notes: [
          note(id: 'old', title: 'x', updatedAt: DateTime(2026, 1, 1)),
          note(id: 'new', title: 'x', updatedAt: DateTime(2026, 6, 1)),
        ],
      );

      expect(hits.map((h) => h.id), ['new', 'old']);
    });
  });

  group('snippets', () {
    test('a title-only match has no snippet', () {
      expect(run('name', notes: [note(title: 'name')]).single.snippet, '');
    });

    test('shows the text around a body match', () {
      final hit = run(
        'needle',
        notes: [note(content: 'some words before the needle and after it')],
      ).single;

      expect(hit.snippet, contains('needle'));
      expect(hit.snippet, contains('before'));
    });

    test('marks with ellipses where the body was cut', () {
      final long = '${'a' * 200} needle ${'b' * 200}';
      final hit = run('needle', notes: [note(content: long)]).single;

      expect(hit.snippet.startsWith('…'), isTrue);
      expect(hit.snippet.endsWith('…'), isTrue);
    });

    test('does not mark a cut that never happened', () {
      final hit = run('short', notes: [note(content: 'short body')]).single;

      expect(hit.snippet.startsWith('…'), isFalse);
      expect(hit.snippet.endsWith('…'), isFalse);
    });

    test('flattens newlines so the snippet stays one line', () {
      final hit = run(
        'needle',
        notes: [note(content: 'line one\n\nline with needle\n\nlast')],
      ).single;

      expect(hit.snippet, isNot(contains('\n')));
    });
  });
}
