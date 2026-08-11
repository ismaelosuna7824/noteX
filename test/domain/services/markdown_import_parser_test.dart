import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/services/markdown_import_parser.dart';
import 'package:notex/domain/services/note_export_plan.dart';

void main() {
  ImportedNote parse(String raw, {String path = 'Note.md'}) =>
      MarkdownImportParser.parse(relativePath: path, raw: raw);

  group('accepts', () {
    test('takes Markdown files, whatever the case', () {
      expect(MarkdownImportParser.accepts('a/b/Note.md'), isTrue);
      expect(MarkdownImportParser.accepts('NOTE.MD'), isTrue);
    });

    test('ignores everything else', () {
      expect(MarkdownImportParser.accepts('image.png'), isFalse);
      expect(MarkdownImportParser.accepts('notes.txt'), isFalse);
      expect(MarkdownImportParser.accepts('README'), isFalse);
    });
  });

  group('front matter', () {
    test('reads title, created and updated', () {
      final note = parse('''
---
title: "Supabase"
created: 2026-07-03T10:00:00.000
updated: 2026-08-10T12:30:00.000
---

# Body here''');

      expect(note.title, 'Supabase');
      expect(note.createdAt, DateTime(2026, 7, 3, 10));
      expect(note.updatedAt, DateTime(2026, 8, 10, 12, 30));
      expect(note.content, '# Body here');
    });

    test('unescapes quotes and backslashes in a title', () {
      final note = parse('---\ntitle: "He said \\"hi\\" \\\\ bye"\n---\n\nx');
      expect(note.title, r'He said "hi" \ bye');
    });

    test('accepts unquoted values', () {
      expect(parse('---\ntitle: Plain\n---\n\nx').title, 'Plain');
    });

    test('ignores keys it does not know', () {
      final note = parse('---\ntitle: Kept\ntags: [a, b]\n---\n\nx');
      expect(note.title, 'Kept');
      expect(note.content, 'x');
    });

    test('an unparseable date is dropped, not fatal', () {
      final note = parse('---\ntitle: T\ncreated: not-a-date\n---\n\nx');
      expect(note.title, 'T');
      expect(note.createdAt, isNull);
    });

    test('an empty front matter title falls back to the filename', () {
      final note = parse('---\ntitle: ""\n---\n\nx', path: 'Fallback.md');
      expect(note.title, 'Fallback');
    });
  });

  group('files that never came from this app', () {
    test('a plain Markdown file imports with its filename as the title', () {
      final note = parse('# Hello\n\nworld', path: 'My Notes.md');
      expect(note.title, 'My Notes');
      expect(note.content, '# Hello\n\nworld');
      expect(note.createdAt, isNull);
    });

    test('a document opening with a horizontal rule keeps all its content', () {
      // No closing fence, so this is prose, not front matter.
      const raw = '---\n\nJust a rule above some text.';
      final note = parse(raw);
      expect(note.content, raw);
      expect(note.title, 'Note');
    });

    test('an empty file still yields a titled note', () {
      final note = parse('', path: 'Empty.md');
      expect(note.title, 'Empty');
      expect(note.content, '');
    });

    test('a file with no usable name gets a fallback title', () {
      expect(parse('x', path: '.md').title, 'Untitled');
    });
  });

  group('folders', () {
    test('a root file has no folders', () {
      expect(parse('x', path: 'Note.md').folders, isEmpty);
    });

    test('nested directories are recovered outermost first', () {
      expect(
        parse('x', path: 'Work/Q3/Deep.md').folders,
        ['Work', 'Q3'],
      );
    });

    test('leading and repeated separators are ignored', () {
      expect(parse('x', path: '/Work//Q3/Deep.md').folders, ['Work', 'Q3']);
    });
  });

  group('round trip with the exporter', () {
    test('a note survives export and re-import', () {
      final original = Note(
        id: 'abc',
        title: 'Q3: plan/review',
        content: '# Plan\n\nBody text.',
        createdAt: DateTime(2026, 3, 1, 9, 30),
        updatedAt: DateTime(2026, 4, 2, 18, 45),
      );

      final entry = NoteExportPlan.build(
        notes: [original],
        projects: const [],
        toMarkdown: (c) => c,
      ).single;

      final reimported =
          MarkdownImportParser.parse(relativePath: entry.path, raw: entry.content);

      // The filename was sanitised, but front matter carried the real title.
      expect(entry.path, 'Q3- plan-review.md');
      expect(reimported.title, 'Q3: plan/review');
      expect(reimported.content, original.content);
      expect(reimported.createdAt, original.createdAt);
      expect(reimported.updatedAt, original.updatedAt);
    });
  });
}
