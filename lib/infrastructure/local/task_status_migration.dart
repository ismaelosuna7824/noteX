import 'database.dart';

/// Backfills the v18 `status` and `status_pending_push` columns on
/// `reminders` for rows that predate schema v18, so an upgrading client's
/// behavior stays unchanged until the later task-tracker phases start
/// reading `status` as the source of truth.
///
/// Extracted as a standalone callable — rather than inlined in
/// `onUpgrade` — because `AppDatabase.forTesting(...)` runs `onCreate`, not
/// `onUpgrade`, so this function is what makes the migration path
/// unit-testable without schema-snapshot tooling this repo does not have.
///
/// Both statements are idempotent: `onUpgrade` is NOT wrapped in a
/// transaction (see the design doc's D5 "transaction correction"), so the
/// v18 ladder can partially apply and re-run after a crash.
Future<void> backfillTaskStatus(AppDatabase db) async {
  // Derive `status` from the legacy `is_completed` boolean.
  //
  // Guarded on `status = 'todo'` (the column's DEFAULT), NOT
  // `status IS NULL`: SQLite requires a non-null default for
  // `ADD COLUMN ... NOT NULL`, so `status` is never null and an `IS NULL`
  // guard would be a silent no-op that leaves every completed task
  // demoted to `todo`. This form is also idempotent — a pre-set `'doing'`
  // row is untouched on re-run because it no longer matches `= 'todo'`.
  await db.customStatement(
    "UPDATE reminders SET status = 'done' WHERE is_completed = 1 AND status = 'todo'",
  );

  // Never-synced rows have no remote copy to fall back on, so their first
  // upload must carry a real status rather than the Postgres column
  // DEFAULT. See the D10 push-payload contract in the design doc.
  //
  // Must be `= 'localOnly'`, NOT `!= 'synced'`. The latter also matches
  // `pendingSync` — a row that WAS synced and has been edited since, so it
  // has a remote copy — and would let an upgrading client push a stale
  // backfilled status over newer remote state through a path the M8
  // recency gate cannot see (push runs before pull).
  await db.customStatement(
    "UPDATE reminders SET status_pending_push = 1 WHERE sync_status = 'localOnly'",
  );
}
