import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/application/use_cases/index_note_links_use_case.dart';
import 'package:notex/application/use_cases/note/permanent_delete_note_use_case.dart';
import 'package:notex/application/use_cases/update_note_use_case.dart';
import 'package:notex/domain/entities/note.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/drift_note_link_index.dart';
import 'package:notex/infrastructure/local/drift_note_repository.dart';

/// Saving a note is the only thing that keeps the link index current, so this
/// covers the seam between UpdateNoteUseCase and the index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftNoteRepository notes;
  late DriftNoteLinkIndex index;
  late UpdateNoteUseCase updateNote;

  Future<void> seed(String id, {String content = '', String title = 'T'}) {
    return notes.save(
      Note(
        id: id,
        title: title,
        content: content,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    notes = DriftNoteRepository(db);
    index = DriftNoteLinkIndex(db);
    updateNote = UpdateNoteUseCase(notes, IndexNoteLinksUseCase(notes, index));
    await seed('source');
    await seed('target', title: 'Target note');
  });

  tearDown(() async {
    await db.close();
  });

  test('saving a body with a link indexes the edge', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'see [Target note](notex://target)',
    );

    final backlinks = await index.backlinksTo('target');
    expect(backlinks, hasLength(1));
    expect(backlinks.single.sourceNoteId, 'source');
    expect(backlinks.single.displayText, 'Target note');
  });

  test('removing the link from the body drops the edge', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'see [Target note](notex://target)',
    );
    expect(await index.count(), 1);

    await updateNote.execute(noteId: 'source', content: 'no links anymore');
    expect(await index.count(), 0);
  });

  test('editing only the title leaves the index alone', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'see [Target note](notex://target)',
    );

    await updateNote.execute(noteId: 'source', title: 'Renamed');

    expect(await index.count(), 1);
    expect((await notes.getById('source'))!.title, 'Renamed');
  });

  test('a no-op save does not disturb the index', () async {
    const body = 'see [Target note](notex://target)';
    await updateNote.execute(noteId: 'source', content: body);
    await updateNote.execute(noteId: 'source', content: body);

    expect(await index.count(), 1);
  });

  test('links inside code blocks are not indexed', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'docs:\n```\n[Target note](notex://target)\n```',
    );

    expect(await index.count(), 0);
  });

  test('a note linking to itself is not indexed', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'see [me](notex://source)',
    );

    expect(await index.backlinksTo('source'), isEmpty);
  });

  test(
    'permanently deleting a note forgets edges in both directions',
    () async {
      await seed('other');
      await updateNote.execute(
        noteId: 'source',
        content: 'see [Target note](notex://target)',
      );
      await updateNote.execute(
        noteId: 'other',
        content: 'also [Target note](notex://target)',
      );
      expect(await index.count(), 2);

      await PermanentDeleteNoteUseCase(
        notes,
        IndexNoteLinksUseCase(notes, index),
      ).execute('target');

      // The edge pointing at the deleted note is gone; 'other' keeps none
      // dangling either.
      expect(await index.backlinksTo('target'), isEmpty);
      expect(await index.count(), 0);
    },
  );

  test('rebuildAll reproduces the index from note bodies', () async {
    await updateNote.execute(
      noteId: 'source',
      content: 'see [Target note](notex://target)',
    );
    await index.clear();
    expect(await index.count(), 0);

    final edges = await IndexNoteLinksUseCase(notes, index).rebuildAll();

    expect(edges, 1);
    expect(await index.backlinksTo('target'), hasLength(1));
  });
}
