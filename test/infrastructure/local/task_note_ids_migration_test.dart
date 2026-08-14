import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:notex/infrastructure/local/task_note_ids_migration.dart';

/// Tests [backfillTaskNoteIds] directly rather than through `onUpgrade`,
/// mirroring `task_status_migration_test.dart`'s approach.
///
/// `AppDatabase.forTesting(...)` runs `onCreate`, not `onUpgrade`, so a
/// pre-v20 row is seeded here at its pre-backfill shape — `note_ids` left
/// at its column DEFAULT (`'[]'`), the deprecated `note_id` set explicitly —
/// and [backfillTaskNoteIds] is invoked directly, exactly as `onUpgrade`
/// calls it in the real migration ladder (decision
/// architecture/task-note-linking-model).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  Future<void> seedRow({
    required String id,
    String? noteId,
    String? noteIds,
  }) async {
    await db.into(db.taskEntries).insert(
          TaskEntriesCompanion.insert(
            id: id,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            noteId: noteId == null ? const Value.absent() : Value(noteId),
            noteIds: noteIds == null ? const Value.absent() : Value(noteIds),
          ),
        );
  }

  Future<TaskEntry> fetch(String id) async {
    return (db.select(db.taskEntries)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('a row with a legacy note_id gets note_ids seeded as a one-element '
      'array containing it', () async {
    await seedRow(id: 'linked-row', noteId: 'note-42');

    await backfillTaskNoteIds(db);

    final row = await fetch('linked-row');
    expect(row.noteIds, '["note-42"]');
  });

  test('a row with no legacy note_id is left at the empty-array default',
      () async {
    await seedRow(id: 'unlinked-row');

    await backfillTaskNoteIds(db);

    final row = await fetch('unlinked-row');
    expect(row.noteIds, '[]');
  });

  test('re-running is a no-op — already-backfilled rows are untouched',
      () async {
    await seedRow(id: 'linked-row', noteId: 'note-42');

    await backfillTaskNoteIds(db);
    await backfillTaskNoteIds(db); // re-run: not transactional, must be idempotent

    final row = await fetch('linked-row');
    expect(row.noteIds, '["note-42"]');
  });

  test('a row that already has real links (written by app logic after '
      'v20) is left alone — the guard is on the DEFAULT, not on note_id',
      () async {
    await seedRow(
      id: 'already-linked-row',
      noteId: 'note-42',
      noteIds: '["note-1","note-2"]',
    );

    await backfillTaskNoteIds(db);

    final row = await fetch('already-linked-row');
    expect(row.noteIds, '["note-1","note-2"]');
  });
}
