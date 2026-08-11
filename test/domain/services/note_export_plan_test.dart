import 'package:flutter_test/flutter_test.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/domain/entities/note_project.dart';
import 'package:notex/domain/services/note_export_plan.dart';

void main() {
  var clock = DateTime(2026, 1, 1);

  /// Each note gets a later createdAt than the last, so ordering in the
  /// expectations matches the order they are declared.
  Note note({
    required String id,
    String title = 'Note',
    String content = 'body',
    String? projectId,
    DateTime? deletedAt,
  }) {
    clock = clock.add(const Duration(minutes: 1));
    return Note(
      id: id,
      title: title,
      content: content,
      createdAt: clock,
      updatedAt: clock,
      projectId: projectId,
      deletedAt: deletedAt,
    );
  }

  NoteProject project({
    required String id,
    required String name,
    String? parentId,
    DateTime? deletedAt,
  }) =>
      NoteProject(
        id: id,
        name: name,
        colorValue: 0,
        parentId: parentId,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        deletedAt: deletedAt,
      );

  List<String> pathsOf(
    List<Note> notes, {
    List<NoteProject> projects = const [],
  }) =>
      NoteExportPlan.build(
        notes: notes,
        projects: projects,
        toMarkdown: (c) => c,
      ).map((e) => e.path).toList();

  setUp(() => clock = DateTime(2026, 1, 1));

  group('paths and folders', () {
    test('a note with no project lands at the root', () {
      expect(pathsOf([note(id: 'a', title: 'Ideas')]), ['Ideas.md']);
    });

    test('a note in a project lands in that folder', () {
      expect(
        pathsOf(
          [note(id: 'a', title: 'Today', projectId: 'p')],
          projects: [project(id: 'p', name: 'daily notes')],
        ),
        ['daily notes/Today.md'],
      );
    });

    test('nested projects become nested folders', () {
      expect(
        pathsOf(
          [note(id: 'a', title: 'Deep', projectId: 'child')],
          projects: [
            project(id: 'root', name: 'Work'),
            project(id: 'child', name: 'Q3', parentId: 'root'),
          ],
        ),
        ['Work/Q3/Deep.md'],
      );
    });

    test('a note whose project is gone falls back to the root', () {
      expect(pathsOf([note(id: 'a', title: 'Orphan', projectId: 'ghost')]),
          ['Orphan.md']);
    });

    test('a trashed project does not become a folder', () {
      expect(
        pathsOf(
          [note(id: 'a', title: 'Loose', projectId: 'p')],
          projects: [
            project(id: 'p', name: 'Old', deletedAt: DateTime(2026, 5, 1)),
          ],
        ),
        ['Loose.md'],
      );
    });

    test('a parent cycle is broken instead of hanging', () {
      expect(
        pathsOf(
          [note(id: 'a', title: 'Cyclic', projectId: 'x')],
          projects: [
            project(id: 'x', name: 'X', parentId: 'y'),
            project(id: 'y', name: 'Y', parentId: 'x'),
          ],
        ),
        ['Y/X/Cyclic.md'],
      );
    });
  });

  group('what gets exported', () {
    test('trashed notes are skipped', () {
      final paths = pathsOf([
        note(id: 'a', title: 'Kept'),
        note(id: 'b', title: 'Trashed', deletedAt: DateTime(2026, 6, 1)),
      ]);
      expect(paths, ['Kept.md']);
    });

    test('output is ordered by creation date, not list order', () {
      final older = note(id: 'a', title: 'First');
      final newer = note(id: 'b', title: 'Second');
      expect(pathsOf([newer, older]), ['First.md', 'Second.md']);
    });
  });

  group('name collisions', () {
    test('two notes with the same title get distinct files', () {
      expect(
        pathsOf([
          note(id: 'a', title: 'Meeting'),
          note(id: 'b', title: 'Meeting'),
          note(id: 'c', title: 'Meeting'),
        ]),
        ['Meeting.md', 'Meeting (2).md', 'Meeting (3).md'],
      );
    });

    test('collisions are case-insensitive, as macOS and Windows are', () {
      expect(
        pathsOf([
          note(id: 'a', title: 'Notes'),
          note(id: 'b', title: 'notes'),
        ]),
        ['Notes.md', 'notes (2).md'],
      );
    });

    test('the same title in different folders does not collide', () {
      expect(
        pathsOf(
          [
            note(id: 'a', title: 'Index', projectId: 'p1'),
            note(id: 'b', title: 'Index', projectId: 'p2'),
          ],
          projects: [
            project(id: 'p1', name: 'One'),
            project(id: 'p2', name: 'Two'),
          ],
        ),
        ['One/Index.md', 'Two/Index.md'],
      );
    });
  });

  group('sanitizeSegment', () {
    test('strips characters filesystems reject', () {
      expect(NoteExportPlan.sanitizeSegment('a/b\\c:d*e?f"g<h>i|j'),
          'a-b-c-d-e-f-g-h-i-j');
    });

    test('a title can never smuggle in a directory level', () {
      expect(
        pathsOf([note(id: 'a', title: '../../etc/passwd')]),
        ['..-..-etc-passwd.md'],
      );
    });

    test('collapses whitespace and trims', () {
      expect(NoteExportPlan.sanitizeSegment('  a   b  '), 'a b');
    });

    test('drops trailing dots and spaces that Windows rewrites', () {
      expect(NoteExportPlan.sanitizeSegment('report...'), 'report');
      expect(NoteExportPlan.sanitizeSegment('report .'), 'report');
    });

    test('escapes Windows device names', () {
      expect(NoteExportPlan.sanitizeSegment('CON'), '_CON');
      expect(NoteExportPlan.sanitizeSegment('com1'), '_com1');
      expect(NoteExportPlan.sanitizeSegment('console'), 'console');
    });

    test('truncates long titles without leaving trailing junk', () {
      final long = '${'x' * NoteExportPlan.maxSegmentLength}.....';
      final result = NoteExportPlan.sanitizeSegment(long);
      expect(result.length, NoteExportPlan.maxSegmentLength);
      expect(result.endsWith('.'), isFalse);
    });

    test('an unnameable title still produces a file', () {
      expect(NoteExportPlan.sanitizeSegment('///'), 'Untitled');
      expect(NoteExportPlan.sanitizeSegment('   '), 'Untitled');
      expect(NoteExportPlan.sanitizeSegment(''), 'Untitled');
    });
  });

  group('single-note export', () {
    test('derives a file name from the title when none is given', () {
      final entry = NoteExportPlan.single(
        note: note(id: 'a', title: 'Q3: plan/review'),
        toMarkdown: (c) => c,
      );
      expect(entry.path, 'Q3- plan-review.md');
    });

    test('uses the name the save dialog returned', () {
      final entry = NoteExportPlan.single(
        note: note(id: 'a', title: 'Ignored'),
        toMarkdown: (c) => c,
        fileName: 'What I typed.md',
      );
      expect(entry.path, 'What I typed.md');
    });

    test('adds the extension when the dialog name lacks it', () {
      final entry = NoteExportPlan.single(
        note: note(id: 'a'),
        toMarkdown: (c) => c,
        fileName: 'No extension',
      );
      expect(entry.path, 'No extension.md');
    });

    test('falls back to the title when the dialog name is blank', () {
      final entry = NoteExportPlan.single(
        note: note(id: 'a', title: 'Fallback'),
        toMarkdown: (c) => c,
        fileName: '   ',
      );
      expect(entry.path, 'Fallback.md');
    });

    test('is byte-identical to the same note inside a full export', () {
      final subject = note(id: 'a', title: 'Same', content: '# Body');

      final fromBatch = NoteExportPlan.build(
        notes: [subject],
        projects: const [],
        toMarkdown: (c) => c,
      ).single;
      final alone = NoteExportPlan.single(
        note: subject,
        toMarkdown: (c) => c,
      );

      expect(alone.content, fromBatch.content);
      expect(alone.path, fromBatch.path);
    });
  });

  group('file contents', () {
    ExportEntry only(List<Note> notes, {String Function(String)? toMarkdown}) =>
        NoteExportPlan.build(
          notes: notes,
          projects: const [],
          toMarkdown: toMarkdown ?? (c) => c,
        ).single;

    test('front matter carries the fields a filename cannot', () {
      final entry = only([
        note(id: 'a', title: 'Q3: plan/review', content: '# Body'),
      ]);

      expect(entry.path, 'Q3- plan-review.md');
      // The real title survives even though the filename mangled it.
      expect(entry.content, contains('title: "Q3: plan/review"'));
      expect(entry.content, endsWith('# Body'));
    });

    test('quotes and backslashes in a title stay valid YAML', () {
      final entry = only([note(id: 'a', title: r'He said "hi" \ bye')]);
      expect(entry.content, contains(r'title: "He said \"hi\" \\ bye"'));
    });

    test('legacy content is converted, not written raw', () {
      final entry = only(
        [note(id: 'a', content: '[{"insert":"hello"}]')],
        toMarkdown: (_) => 'hello',
      );
      expect(entry.content, endsWith('hello'));
      expect(entry.content, isNot(contains('insert')));
    });

    test('created and updated timestamps are recorded', () {
      final entry = only([note(id: 'a')]);
      expect(entry.content, contains('created: 2026-01-01T00:01:00'));
      expect(entry.content, contains('updated: 2026-01-01T00:01:00'));
    });
  });
}
