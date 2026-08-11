import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/import_notes_use_case.dart';
import 'package:notex/domain/entities/note_project.dart';
import 'package:notex/domain/repositories/note_import_source.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_project_repository.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';

/// Serves a fixed set of files, standing in for a directory on disk.
class _FakeSource implements NoteImportSource {
  final List<ImportFile> files;
  const _FakeSource(this.files);

  @override
  Future<List<ImportFile>> read() async => files;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftNoteRepository notes;
  late DriftNoteProjectRepository projects;
  late int idCounter;

  ImportNotesUseCase importerFor(List<ImportFile> files) => ImportNotesUseCase(
        notes,
        projects,
        _FakeSource(files),
        () => 'id-${idCounter++}',
      );

  Future<ImportSummary> importFiles(List<ImportFile> files) =>
      importerFor(files).execute(folderColorValue: 0xFF00FF00);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    notes = DriftNoteRepository(db);
    projects = DriftNoteProjectRepository(db);
    idCounter = 0;
  });

  tearDown(() async {
    await db.close();
  });

  test('creates a note from a plain Markdown file', () async {
    final summary = await importFiles([
      const ImportFile(relativePath: 'Ideas.md', content: '# Hello'),
    ]);

    expect(summary.notesCreated, 1);
    final all = await notes.getAll();
    expect(all.single.title, 'Ideas');
    expect(all.single.content, '# Hello');
    expect(all.single.projectId, isNull);
  });

  test('recovers title and dates from front matter', () async {
    await importFiles([
      const ImportFile(
        relativePath: 'anything.md',
        content: '---\n'
            'title: "Real Title"\n'
            'created: 2026-03-01T09:30:00.000\n'
            'updated: 2026-04-02T18:45:00.000\n'
            '---\n\nBody',
      ),
    ]);

    final note = (await notes.getAll()).single;
    expect(note.title, 'Real Title');
    expect(note.content, 'Body');
    expect(note.createdAt, DateTime(2026, 3, 1, 9, 30));
    expect(note.updatedAt, DateTime(2026, 4, 2, 18, 45));
  });

  test('nested directories become nested folders', () async {
    final summary = await importFiles([
      const ImportFile(relativePath: 'Work/Q3/Deep.md', content: 'x'),
    ]);

    expect(summary.foldersCreated, 2);

    final all = await projects.getAll();
    final work = all.firstWhere((p) => p.name == 'Work');
    final q3 = all.firstWhere((p) => p.name == 'Q3');
    expect(work.parentId, isNull);
    expect(q3.parentId, work.id);
    expect((await notes.getAll()).single.projectId, q3.id);
  });

  test('files sharing a folder create it only once', () async {
    final summary = await importFiles([
      const ImportFile(relativePath: 'Daily/a.md', content: 'a'),
      const ImportFile(relativePath: 'Daily/b.md', content: 'b'),
    ]);

    expect(summary.notesCreated, 2);
    expect(summary.foldersCreated, 1);
    expect((await projects.getAll()).length, 1);
  });

  test('an existing folder is reused instead of duplicated', () async {
    await projects.save(NoteProject.create(
      id: 'existing',
      name: 'daily notes',
      colorValue: 0xFF000000,
    ));

    final summary = await importFiles([
      // Different casing on purpose — folder names are matched the way a user
      // reads them.
      const ImportFile(relativePath: 'Daily Notes/a.md', content: 'a'),
    ]);

    expect(summary.foldersCreated, 0);
    expect((await projects.getAll()).length, 1);
    expect((await notes.getAll()).single.projectId, 'existing');
  });

  test('importing twice duplicates, as documented', () async {
    const files = [ImportFile(relativePath: 'A.md', content: 'x')];

    await importFiles(files);
    await importFiles(files);

    expect((await notes.getAll()).length, 2);
  });

  test('an empty source writes nothing', () async {
    final summary = await importFiles([]);

    expect(summary.isEmpty, isTrue);
    expect(await notes.getAll(), isEmpty);
    expect(await projects.getAll(), isEmpty);
  });

  test('a file with no dates is stamped as new', () async {
    await importFiles([
      const ImportFile(relativePath: 'A.md', content: 'x'),
    ]);

    final note = (await notes.getAll()).single;
    // Compared as a window, not an instant: Drift stores DateTime as unix
    // seconds, so a stamp taken mid-second reads back slightly earlier.
    expect(
      DateTime.now().difference(note.createdAt).inMinutes,
      lessThan(1),
    );
    expect(note.updatedAt, note.createdAt);
  });
}
