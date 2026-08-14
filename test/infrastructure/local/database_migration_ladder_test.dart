import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/infrastructure/local/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Regression test for the v1.60.0 → v1.61.0 production incident: a real
/// user upgrading from schema v17 got a black screen because
/// `SqliteException: no such column: "note_ids"` was thrown while opening
/// the database, and the app never rendered anything past that.
///
/// Every other migration test in this directory (`task_status_migration_test.dart`,
/// `task_note_ids_migration_test.dart`) calls a backfill helper directly —
/// `AppDatabase.forTesting(...)` runs `onCreate`, not `onUpgrade`, so those
/// tests never actually exercise the ladder. That is exactly why this bug
/// shipped: the ladder was only ever developed and tested one step at a
/// time, never run end-to-end from a real starting version.
///
/// This test builds a v17-era `reminders`/`time_entries`/... schema by hand
/// with raw sqlite3 DDL, sets `PRAGMA user_version`, seeds rows, and only
/// then opens `AppDatabase` over it — via `NativeDatabase.opened(...)`, the
/// mechanism drift itself documents for migration integration tests — so
/// the full `onUpgrade(from, to)` ladder actually runs, against the exact
/// column set a real v17 database has at each step.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// DDL for every table as it existed at schema v17 (1.60.0), by hand —
  /// this repo has no schema-snapshot tooling (see the backfill helpers'
  /// doc comments), so there is no generated source to copy this from.
  ///
  /// Column types/nullability mirror what `database.g.dart` generates for
  /// the current Dart table definitions, minus every column added at v18
  /// or later. DateTime columns are INTEGER (drift's default: unix
  /// seconds — see `package:drift/src/runtime/types/mapping.dart`), bool
  /// columns are INTEGER 0/1.
  const v17Ddl = '''
    CREATE TABLE notes (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '[]',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      background_image TEXT,
      theme_id TEXT,
      color TEXT,
      is_pinned INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      user_id TEXT,
      project_id TEXT,
      share_token TEXT,
      shared_at INTEGER,
      is_ephemeral INTEGER NOT NULL DEFAULT 0,
      is_locked INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      user_id TEXT
    );

    -- v17 shape: no `task_id` yet — that's a v18 addition. Explicitly
    -- called out in the task brief as a column the ladder touches.
    CREATE TABLE time_entries (
      id TEXT NOT NULL PRIMARY KEY,
      description TEXT NOT NULL DEFAULT '',
      project_id TEXT,
      start_time INTEGER NOT NULL,
      end_time INTEGER,
      updated_at INTEGER,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      user_id TEXT
    );

    CREATE TABLE sync_metadata (
      user_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      last_synced_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, entity_type)
    );

    CREATE TABLE markdown_files (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      project_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      user_id TEXT
    );

    CREATE TABLE markdown_projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      user_id TEXT
    );

    CREATE TABLE note_projects (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      parent_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      user_id TEXT
    );

    -- v17 shape of `reminders` (Dart symbol `TaskEntries`, physical table
    -- name deliberately unchanged — see `TaskEntries.tableName`'s doc
    -- comment). `scheduled_date` is still NOT NULL: relaxing it is the
    -- rebuild under test. None of the v18+ columns (status, note_ids,
    -- project_id, ...) exist yet.
    CREATE TABLE reminders (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      scheduled_date INTEGER NOT NULL,
      is_completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      deleted_at INTEGER,
      sync_status TEXT NOT NULL DEFAULT 'localOnly',
      user_id TEXT
    );

    CREATE TABLE app_metadata (
      key TEXT NOT NULL PRIMARY KEY,
      value TEXT NOT NULL
    );
  ''';

  /// Builds a raw sqlite3 database at schema [userVersion], seeds it with
  /// [seedSql], and wraps it in a real `AppDatabase` via
  /// `NativeDatabase.opened(...)` so opening it runs the full `onUpgrade`
  /// ladder — not a helper function in isolation.
  AppDatabase openMigratedDatabase({
    required int userVersion,
    required String ddl,
    String seedSql = '',
  }) {
    final raw = sqlite3.sqlite3.openInMemory();

    // The production binary (`sqlite3_flutter_libs`, via its `CSQLite`/CMake
    // build on every platform) compiles SQLite with `SQLITE_DQS=0`. Without
    // disabling it here too, SQLite's legacy double-quoted-string-literal
    // compatibility fallback silently turns a double-quoted, unresolvable
    // column name — exactly what the broken v19 rebuild references — into a
    // no-op STRING LITERAL instead of raising `no such column`, masking the
    // exact bug this test exists to catch. Host system libraries (Apple's
    // on macOS, and plain distro builds elsewhere) commonly leave the
    // legacy default on, so without this the test would stay green against
    // the broken ladder. Matches the real crash reported in production.
    raw.config.doubleQuotedStringLiterals = false;

    raw.execute(ddl);
    if (seedSql.isNotEmpty) raw.execute(seedSql);
    raw.execute('PRAGMA user_version = $userVersion;');

    return AppDatabase.forTesting(NativeDatabase.opened(raw));
  }

  group('v17 → latest: the full ladder against a real v1.60.0 database', () {
    late AppDatabase db;

    setUp(() {
      db = openMigratedDatabase(
        userVersion: 17,
        ddl: v17Ddl,
        seedSql: '''
          INSERT INTO reminders
            (id, title, scheduled_date, is_completed, completed_at, created_at, updated_at, version, deleted_at, sync_status, user_id)
          VALUES
            ('task-open', 'Open task', 1700000000, 0, NULL, 1700000000, 1700000000, 1, NULL, 'localOnly', 'user-1'),
            ('task-done', 'Finished task', 1700000000, 1, 1700000100, 1700000000, 1700000100, 1, NULL, 'synced', 'user-1');

          INSERT INTO time_entries
            (id, description, project_id, start_time, end_time, updated_at, version, deleted_at, sync_status, user_id)
          VALUES
            ('entry-1', 'Deep work', NULL, 1700000000, 1700000900, 1700000900, 1, NULL, 'localOnly', 'user-1');
        ''',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('opens successfully instead of throwing on the v19 rebuild step',
        () async {
      // This is the actual production failure: opening (any query) used to
      // throw `SqliteException: no such column: "note_ids"` before the
      // fix, and the app rendered a black screen. Forcing a query is what
      // makes drift actually run the lazy migration.
      await expectLater(
        db.select(db.taskEntries).get(),
        completes,
      );
    });

    test('scheduled_date ends up nullable, note_ids and project_id exist',
        () async {
      // Proves the v19 relaxation and the v20/v21 columns all landed —
      // inserting a row with scheduled_date omitted and note_ids/project_id
      // explicitly set would throw on any of the three if the rebuild
      // hadn't actually produced the final shape.
      await db.into(db.taskEntries).insert(
            TaskEntriesCompanion.insert(
              id: 'backlog-task',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              noteIds: const Value('["note-1"]'),
              projectId: const Value('project-1'),
            ),
          );

      final row = await (db.select(db.taskEntries)
            ..where((t) => t.id.equals('backlog-task')))
          .getSingle();

      expect(row.scheduledDate, isNull);
      expect(row.noteIds, '["note-1"]');
      expect(row.projectId, 'project-1');
    });

    test('seeded rows survive the ladder with their data intact', () async {
      final open = await (db.select(db.taskEntries)
            ..where((t) => t.id.equals('task-open')))
          .getSingle();
      expect(open.title, 'Open task');
      expect(open.userId, 'user-1');
      expect(open.syncStatus, 'localOnly');
      expect(
        open.scheduledDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );

      final entry = await (db.select(db.timeEntries)
            ..where((t) => t.id.equals('entry-1')))
          .getSingle();
      expect(entry.description, 'Deep work');
      expect(entry.userId, 'user-1');
    });

    test('a completed reminder became status = done via the v18 backfill',
        () async {
      final done = await (db.select(db.taskEntries)
            ..where((t) => t.id.equals('task-done')))
          .getSingle();

      expect(done.isCompleted, isTrue);
      expect(done.status, 'done');
    });
  });

  group('v21 → latest: a database that already climbed incrementally', () {
    // v21-era `reminders` already has every v18/v20/v21 column, and
    // `scheduled_date` was already relaxed to nullable by the original v19
    // step before this fix shipped — this is the shape of the database
    // already on this machine. The v22 rebuild must be a harmless no-op
    // on top of it, not a second failure.
    const v21Ddl = '''
      CREATE TABLE reminders (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        scheduled_date INTEGER,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'localOnly',
        user_id TEXT,
        status TEXT NOT NULL DEFAULT 'todo',
        status_changed_at INTEGER,
        status_pending_push INTEGER NOT NULL DEFAULT 0,
        description TEXT NOT NULL DEFAULT '',
        blocked_reason TEXT,
        note_id TEXT,
        note_ids TEXT NOT NULL DEFAULT '[]',
        external_provider TEXT,
        external_id TEXT,
        external_url TEXT,
        external_cached_title TEXT,
        external_last_synced_at INTEGER,
        project_id TEXT
      );
    ''';

    late AppDatabase db;

    setUp(() {
      db = openMigratedDatabase(
        userVersion: 21,
        ddl: v21Ddl,
        seedSql: '''
          INSERT INTO reminders
            (id, title, scheduled_date, is_completed, created_at, updated_at, note_ids, project_id)
          VALUES
            ('backlog-task', 'Already on v21', NULL, 0, 1700000000, 1700000000, '["note-9"]', 'project-9');
        ''',
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('the v22 rebuild is harmless — open succeeds and data survives',
        () async {
      final row = await (db.select(db.taskEntries)
            ..where((t) => t.id.equals('backlog-task')))
          .getSingle();

      expect(row.title, 'Already on v21');
      expect(row.scheduledDate, isNull);
      expect(row.noteIds, '["note-9"]');
      expect(row.projectId, 'project-9');
    });
  });
}
