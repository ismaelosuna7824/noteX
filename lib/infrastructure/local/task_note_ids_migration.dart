import 'database.dart';

/// Backfills the v20 `note_ids` column on `reminders` from the deprecated
/// v18 `note_id` column, so an upgrading client's existing single link
/// survives as the first (and only) entry of the new list — see decision
/// architecture/task-note-linking-model.
///
/// Extracted as a standalone callable — rather than inlined in
/// `onUpgrade` — for the same reason as `backfillTaskStatus`
/// (`task_status_migration.dart`): `AppDatabase.forTesting(...)` runs
/// `onCreate`, not `onUpgrade`, so this function is what makes the
/// migration path unit-testable without schema-snapshot tooling this repo
/// does not have.
///
/// Idempotent: `onUpgrade` is NOT wrapped in a transaction (see the v18
/// design doc's D5 "transaction correction"), so the v20 step can
/// partially apply and re-run after a crash.
///
/// Uses SQLite's built-in `json_array()` to build the JSON text safely
/// (correct escaping for any character `note_id` might contain), rather
/// than string concatenation.
Future<void> backfillTaskNoteIds(AppDatabase db) async {
  // Guarded on `note_ids = '[]'` (the column's DEFAULT), NOT
  // `note_ids IS NULL`: the column is NOT NULL with that default, so it is
  // never null and an `IS NULL` guard would be a silent no-op. This form
  // is also idempotent — a row already backfilled (or one that already had
  // real links written to it by app logic) no longer matches `= '[]'` and
  // is left alone on re-run.
  await db.customStatement(
    "UPDATE reminders SET note_ids = json_array(note_id) "
    "WHERE note_id IS NOT NULL AND note_ids = '[]'",
  );
}
