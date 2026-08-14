import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/note.dart' as domain_note;
import '../../domain/entities/project.dart' as domain_project;
import '../../domain/entities/time_entry.dart' as domain_time;
import '../../domain/entities/markdown_file.dart' as domain_md;
import '../../domain/entities/markdown_project.dart' as domain_mdp;
import '../../domain/entities/note_project.dart' as domain_np;
import '../../domain/entities/task.dart' as domain_task;
import '../../domain/value_objects/sync_status.dart';
import '../../domain/value_objects/task_status_resolution.dart';
import 'task_note_ids_migration.dart';
import 'task_status_migration.dart';

part 'database.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Table definitions
// ─────────────────────────────────────────────────────────────────────────────

/// Drift table for notes.
/// Named NoteEntries to avoid conflict with Drift's generated Note data class.
class NoteEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get backgroundImage => text().nullable()();
  TextColumn get themeId => text().nullable()();
  TextColumn get color => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get userId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  TextColumn get shareToken => text().nullable()();
  DateTimeColumn get sharedAt => dateTime().nullable()();
  BoolColumn get isEphemeral => boolean().withDefault(const Constant(false))();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'notes';
}

/// Drift table for projects (time tracking).
/// @DataClassName avoids conflict with domain entity Project.
@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Drift table for time entries.
/// @DataClassName avoids conflict with domain entity TimeEntry.
/// [endTime] IS NULL means the entry is currently running.
@DataClassName('TimeEntryRow')
class TimeEntries extends Table {
  TextColumn get id => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get userId => text().nullable()();
  // v18: schema only, unused until slice 3 (timer↔task link).
  TextColumn get taskId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Drift table for markdown files.
@DataClassName('MarkdownFileRow')
class MarkdownFileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'markdown_files';
}

/// Drift table for markdown projects (folder groupings).
@DataClassName('MarkdownProjectRow')
class MarkdownProjectEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'markdown_projects';
}

/// Drift table for note projects (folder groupings for notes).
/// Supports nested folders via [parentId] (null = root level).
@DataClassName('NoteProjectRow')
class NoteProjectEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get colorValue => integer()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'note_projects';
}

/// Drift table for tasks.
@DataClassName('TaskEntry')
class TaskEntries extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  // Nullable since v19 — a null row is a backlog task. See design D5 / M9;
  // this is the ONLY schema change v19 makes.
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  BoolColumn get isCompleted =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('localOnly'))();
  TextColumn get userId => text().nullable()();

  // ── v18: task-tracker columns (status-as-source-of-truth wiring lands
  // in a later phase). ──
  TextColumn get status => text().withDefault(const Constant('todo'))();
  DateTimeColumn get statusChangedAt => dateTime().nullable()();
  // Local only — never serialized to Supabase. See task_status_migration.dart
  // and the D10 push-payload contract in the design doc.
  BoolColumn get statusPendingPush =>
      boolean().withDefault(const Constant(false))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get blockedReason => text().nullable()();

  // DEPRECATED (schema v20) — superseded by `noteIds` below. A task links
  // to N notes, not one (decision architecture/task-note-linking-model).
  // Kept, unused, rather than dropped: dropping a column in SQLite requires
  // a full table rebuild, the most dangerous DDL in this project (see the
  // v19 `alterTable` migration below for what that costs). v20's backfill
  // (`task_note_ids_migration.dart`) reads this column once, to seed
  // `noteIds` for pre-existing rows; nothing else in the app reads or
  // writes it going forward.
  TextColumn get noteId => text().nullable()();

  // v20: a task's links to zero or more notes, JSON-encoded as a text
  // column (`domain_task.Task.noteIds`) — the same sync path every other
  // task field already travels, rather than a new join table with its own
  // push/pull/merge rules. NOT NULL with a `'[]'` default so `ADD COLUMN`
  // does not need a nullable relaxation later (see D5/v19 for why that is
  // expensive) — an empty JSON array IS "no links", not a null sentinel.
  TextColumn get noteIds => text().withDefault(const Constant('[]'))();

  TextColumn get externalProvider => text().nullable()();
  TextColumn get externalId => text().nullable()();
  TextColumn get externalUrl => text().nullable()();
  TextColumn get externalCachedTitle => text().nullable()();
  DateTimeColumn get externalLastSyncedAt => dateTime().nullable()();

  // v21: links a task to one of the timer feature's projects
  // (`domain_task.Task.projectId`). Nullable — no project is the default,
  // same as `TimeEntry.projectId`. No local FK (Drift/SQLite tables here
  // don't declare cross-table FKs at all — see `TimeEntries.projectId`
  // above for the same shape); the Supabase side does add a real FK since,
  // unlike a note, a project is only ever soft-deleted, never permanently
  // removed (see `task_supabase_mapper.dart`).
  TextColumn get projectId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  // Deliberately NOT renamed to 'tasks'. Renaming the physical table would
  // require a distributed migration against production Supabase rows still
  // written by older shipped clients that only know the `reminders` table —
  // see design D4. Only the Dart symbol (`ReminderEntries` → `TaskEntries`)
  // changes; the wire format does not.
  @override
  String get tableName => 'reminders';
}

/// Simple key/value store for app-level flags and one-time markers.
///
/// Used by data migrations (e.g. the legacy Delta→Markdown content migration)
/// to persist a run-once flag transactionally alongside the data it guards,
/// so the marker and the migrated content always live in the same file.
@DataClassName('AppMetadataRow')
class AppMetadataEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'app_metadata';
}

/// Tracks last sync timestamp per entity type per user.
@DataClassName('SyncMetadataRow')
class SyncMetadataEntries extends Table {
  TextColumn get userId => text()();
  TextColumn get entityType => text()(); // 'notes', 'projects', 'time_entries'
  DateTimeColumn get lastSyncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {userId, entityType};

  @override
  String get tableName => 'sync_metadata';
}

// ─────────────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [
  NoteEntries,
  Projects,
  TimeEntries,
  SyncMetadataEntries,
  MarkdownFileEntries,
  MarkdownProjectEntries,
  NoteProjectEntries,
  TaskEntries,
  AppMetadataEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing with in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 22;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(noteEntries, noteEntries.isPinned);
      }
      if (from < 3) {
        await m.createTable(projects);
        await m.createTable(timeEntries);
      }
      if (from < 4) {
        // v4 was a cleanup migration from the Firebase experiment
      }
      if (from < 5 || from == 5) {
        // Helper to safely add column if it doesn't exist to prevent crashes
        // from previous failed migrations.
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) {
              // Ignore duplicate column errors
              return;
            }
            rethrow;
          }
        }

        // Notes — add new sync columns
        await safeAddColumn(noteEntries, noteEntries.version);
        await safeAddColumn(noteEntries, noteEntries.deletedAt);
        await safeAddColumn(noteEntries, noteEntries.userId);

        // Projects — add sync columns
        await safeAddColumn(projects, projects.updatedAt);
        await safeAddColumn(projects, projects.version);
        await safeAddColumn(projects, projects.deletedAt);
        await safeAddColumn(projects, projects.syncStatus);
        await safeAddColumn(projects, projects.userId);

        // Time entries — add sync columns
        await safeAddColumn(timeEntries, timeEntries.updatedAt);
        await safeAddColumn(timeEntries, timeEntries.version);
        await safeAddColumn(timeEntries, timeEntries.deletedAt);
        await safeAddColumn(timeEntries, timeEntries.syncStatus);
        await safeAddColumn(timeEntries, timeEntries.userId);

        // Sync metadata table
        try {
          await m.createTable(syncMetadataEntries);
        } catch (e) {
          if (!e.toString().contains('already exists')) rethrow;
        }

        // Backfill updatedAt for projects and time_entries
        try {
          await customStatement(
            "UPDATE projects SET updated_at = created_at WHERE updated_at IS NULL",
          );
          await customStatement(
            "UPDATE time_entries SET updated_at = start_time WHERE updated_at IS NULL",
          );
        } catch (_) {}
      }
      if (from < 7) {
        await m.createTable(markdownFileEntries);
        await m.createTable(markdownProjectEntries);
      }
      if (from < 8) {
        await m.createTable(noteProjectEntries);
        await m.addColumn(noteEntries, noteEntries.projectId);
      }
      if (from < 9) {
        // Historical line: acts on the same physical `reminders` table under
        // its current Dart symbol, `taskEntries` (renamed from
        // `reminderEntries` in C3 — see design D4). Behavior unchanged.
        await m.createTable(taskEntries);
      }
      if (from < 10) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }
        await safeAddColumn(noteEntries, noteEntries.color);
      }
      if (from < 11) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }
        await safeAddColumn(noteEntries, noteEntries.shareToken);
        await safeAddColumn(noteEntries, noteEntries.sharedAt);
      }
      if (from < 12) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }
        await safeAddColumn(noteEntries, noteEntries.isEphemeral);
      }
      if (from < 13) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }
        await safeAddColumn(noteEntries, noteEntries.isLocked);
      }
      if (from < 14) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }
        await safeAddColumn(noteProjectEntries, noteProjectEntries.parentId);
      }
      if (from < 15) {
        // Key/value store for app-level flags (e.g. one-time migration markers).
        try {
          await m.createTable(appMetadataEntries);
        } catch (e) {
          if (!e.toString().contains('already exists')) rethrow;
        }
      }
      // v16 created a `note_links` table for a backlinks feature that was
      // dropped before release. There is deliberately no v16 step: v17 removes
      // the table, so upgrading from v15 simply never creates it, and anyone
      // who already ran v16 has it dropped below.
      if (from < 17) {
        // Derived data only — nothing here was ever authoritative, so the drop
        // loses nothing that note bodies do not already contain.
        await customStatement('DROP TABLE IF EXISTS note_links');
      }
      if (from < 18) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }

        // Originally written against the pre-rename symbol `reminderEntries`
        // in C2; renamed to `taskEntries` here in C3 (see design D4) —
        // symbol only, the underlying `reminders` table is unchanged.
        await safeAddColumn(taskEntries, taskEntries.status);
        await safeAddColumn(taskEntries, taskEntries.statusChangedAt);
        await safeAddColumn(taskEntries, taskEntries.statusPendingPush);
        await safeAddColumn(taskEntries, taskEntries.description);
        await safeAddColumn(taskEntries, taskEntries.blockedReason);
        await safeAddColumn(taskEntries, taskEntries.noteId);
        await safeAddColumn(taskEntries, taskEntries.externalProvider);
        await safeAddColumn(taskEntries, taskEntries.externalId);
        await safeAddColumn(taskEntries, taskEntries.externalUrl);
        await safeAddColumn(taskEntries, taskEntries.externalCachedTitle);
        await safeAddColumn(taskEntries, taskEntries.externalLastSyncedAt);

        // Schema only, unused until slice 3.
        await safeAddColumn(timeEntries, timeEntries.taskId);

        await backfillTaskStatus(this);
      }
      // v19 is DELIBERATELY a no-op. It originally relaxed `scheduled_date`
      // from NOT NULL to nullable via `Migrator.alterTable`, which rebuilds
      // the table by copying every column of the CURRENT Dart definition —
      // not just the columns the table had at the time this block runs
      // (see `Migrator.alterTable`'s `INSERT INTO tmp (...) SELECT (...)
      // FROM reminders`, which iterates `table.$columns`, i.e. today's
      // schema). By the time `noteIds` (v20) and `projectId` (v21) existed
      // in the Dart definition, a client jumping straight from v17 to v21+
      // ran this block against a physical `reminders` table that did not
      // have those columns yet, and the rebuild's SELECT referenced
      // `note_ids`/`project_id` on a table that lacked them — production
      // incident: v1.60.0 → v1.61.0 upgrades hit
      // `SqliteException: no such column: "note_ids"` and the app never
      // opened (v1.61.1 hotfix).
      //
      // The rebuild itself is NOT wrong — it is REQUIRED, because SQLite has
      // no `ALTER COLUMN` and this ladder is not transactional (design D5
      // "transaction correction"), so it must stay the ONLY statement in
      // whichever block runs it. It just cannot run here, where later
      // columns may not exist yet. It now runs once, at the END of the
      // ladder (`if (from < 22)` below), after every column it could
      // possibly need to copy is guaranteed to exist. Do NOT restore a
      // rebuild in this block.
      if (from < 19) {
        // Intentionally empty — see comment above.
      }
      if (from < 20) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }

        // Additive only (decision architecture/task-note-linking-model) —
        // corrects the single nullable `noteId` design error to a list, N
        // notes per task. The deprecated `noteId` column is untouched.
        await safeAddColumn(taskEntries, taskEntries.noteIds);
        await backfillTaskNoteIds(this);
      }
      if (from < 21) {
        Future<void> safeAddColumn(TableInfo table, GeneratedColumn col) async {
          try {
            await m.addColumn(table, col);
          } catch (e) {
            if (e.toString().contains('duplicate column name')) return;
            rethrow;
          }
        }

        // Additive only. A brand-new nullable link with no prior data to
        // derive it from (unlike v20's noteIds), so there is nothing to
        // backfill — every existing row simply reads back with
        // projectId == null ("No Project"), the same default new rows get.
        await safeAddColumn(taskEntries, taskEntries.projectId);
      }
      if (from < 22) {
        // Relaxes `scheduled_date` from NOT NULL to nullable so a task can
        // live in the backlog (design D5 / M9). SQLite has no
        // `ALTER COLUMN`, so this requires a full table rebuild via
        // `Migrator.alterTable`.
        //
        // Moved here (was originally v19 — see the `if (from < 19)` comment
        // above for the incident this caused) so that every column the
        // rebuild's SELECT can reference — including `note_ids` (v20) and
        // `project_id` (v21) — is guaranteed to already exist on the
        // physical table by the time this runs, regardless of which
        // version a client is upgrading from.
        //
        // This is the ONLY statement in this block, deliberately, same
        // reasoning as the original v19 block: `alterTable` runs inside its
        // OWN transaction (see `Migrator.alterTable`) — the ladder itself is
        // NOT transactional (design D5 "transaction correction"). Anything
        // else placed here would run outside that protection.
        //
        // Also runs harmlessly for a client already at v21 (whose
        // `scheduled_date` was already relaxed by the original v19 before
        // this fix, and whose `note_ids`/`project_id` already exist): the
        // rebuild just recreates the same shape with the same data.
        //
        // `alterTable`/`TableMigration` are drift's own documented mechanism
        // for a NOT NULL relaxation table rebuild — currently marked
        // `@experimental` upstream, not a sign this call site is unstable.
        // ignore: experimental_member_use
        await m.alterTable(TableMigration(taskEntries));
      }
    },
  );

  // ── App metadata (key/value flags) ──────────────────────────────────────

  /// Reads a single app-metadata value by [key], or `null` when absent.
  Future<String?> getMetadata(String key) async {
    final row = await (select(appMetadataEntries)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Upserts an app-metadata [key]/[value] pair.
  Future<void> setMetadata(String key, String value) async {
    await into(appMetadataEntries).insertOnConflictUpdate(
      AppMetadataEntriesCompanion(key: Value(key), value: Value(value)),
    );
  }

  // ── Clear all data (user switch) ─────────────────────────────────────────

  /// Deletes all rows from every entity table and sync metadata.
  /// Used when the user signs in with a different account.
  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(noteEntries).go();
      await delete(projects).go();
      await delete(timeEntries).go();
      await delete(markdownFileEntries).go();
      await delete(markdownProjectEntries).go();
      await delete(noteProjectEntries).go();
      await delete(taskEntries).go();
      await delete(syncMetadataEntries).go();
    });
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  static domain_note.Note toDomain(NoteEntry row) {
    return domain_note.Note(
      id: row.id,
      title: row.title,
      content: row.content,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      backgroundImage: row.backgroundImage,
      themeId: row.themeId,
      color: row.color,
      isPinned: row.isPinned,
      version: row.version,
      deletedAt: row.deletedAt,
      userId: row.userId,
      projectId: row.projectId,
      shareToken: row.shareToken,
      sharedAt: row.sharedAt,
      isEphemeral: row.isEphemeral,
      isLocked: row.isLocked,
    );
  }

  static NoteEntriesCompanion toCompanion(domain_note.Note note) {
    return NoteEntriesCompanion(
      id: Value(note.id),
      title: Value(note.title),
      content: Value(note.content),
      createdAt: Value(note.createdAt),
      updatedAt: Value(note.updatedAt),
      syncStatus: Value(note.syncStatus.name),
      backgroundImage: Value(note.backgroundImage),
      themeId: Value(note.themeId),
      color: Value(note.color),
      isPinned: Value(note.isPinned),
      version: Value(note.version),
      deletedAt: Value(note.deletedAt),
      userId: Value(note.userId),
      projectId: Value(note.projectId),
      shareToken: Value(note.shareToken),
      sharedAt: Value(note.sharedAt),
      isEphemeral: Value(note.isEphemeral),
      isLocked: Value(note.isLocked),
    );
  }

  static SyncStatus _parseSyncStatus(String value) {
    return SyncStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => SyncStatus.localOnly,
    );
  }

  // ── Projects ──────────────────────────────────────────────────────────────

  static domain_project.Project projectToDomain(ProjectRow row) {
    return domain_project.Project(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt ?? row.createdAt,
      version: row.version,
      deletedAt: row.deletedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      userId: row.userId,
    );
  }

  static ProjectsCompanion projectToCompanion(domain_project.Project p) {
    return ProjectsCompanion(
      id: Value(p.id),
      name: Value(p.name),
      colorValue: Value(p.colorValue),
      createdAt: Value(p.createdAt),
      updatedAt: Value(p.updatedAt),
      version: Value(p.version),
      deletedAt: Value(p.deletedAt),
      syncStatus: Value(p.syncStatus.name),
      userId: Value(p.userId),
    );
  }

  // ── Time Entries ──────────────────────────────────────────────────────────

  static domain_time.TimeEntry timeEntryToDomain(TimeEntryRow row) {
    return domain_time.TimeEntry(
      id: row.id,
      description: row.description,
      projectId: row.projectId,
      startTime: row.startTime,
      endTime: row.endTime,
      updatedAt: row.updatedAt ?? row.startTime,
      version: row.version,
      deletedAt: row.deletedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      userId: row.userId,
      taskId: row.taskId,
    );
  }

  static TimeEntriesCompanion timeEntryToCompanion(
      domain_time.TimeEntry entry) {
    return TimeEntriesCompanion(
      id: Value(entry.id),
      description: Value(entry.description),
      projectId: Value(entry.projectId),
      startTime: Value(entry.startTime),
      endTime: Value(entry.endTime),
      updatedAt: Value(entry.updatedAt),
      version: Value(entry.version),
      deletedAt: Value(entry.deletedAt),
      syncStatus: Value(entry.syncStatus.name),
      userId: Value(entry.userId),
      taskId: Value(entry.taskId),
    );
  }

  // ── Markdown Files ──────────────────────────────────────────────────────

  static domain_md.MarkdownFile markdownFileToDomain(MarkdownFileRow row) {
    return domain_md.MarkdownFile(
      id: row.id,
      title: row.title,
      content: row.content,
      projectId: row.projectId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      version: row.version,
      deletedAt: row.deletedAt,
      userId: row.userId,
    );
  }

  static MarkdownFileEntriesCompanion markdownFileToCompanion(
      domain_md.MarkdownFile f) {
    return MarkdownFileEntriesCompanion(
      id: Value(f.id),
      title: Value(f.title),
      content: Value(f.content),
      projectId: Value(f.projectId),
      createdAt: Value(f.createdAt),
      updatedAt: Value(f.updatedAt),
      syncStatus: Value(f.syncStatus.name),
      version: Value(f.version),
      deletedAt: Value(f.deletedAt),
      userId: Value(f.userId),
    );
  }

  // ── Markdown Projects ───────────────────────────────────────────────────

  static domain_mdp.MarkdownProject markdownProjectToDomain(
      MarkdownProjectRow row) {
    return domain_mdp.MarkdownProject(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deletedAt: row.deletedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      userId: row.userId,
    );
  }

  static MarkdownProjectEntriesCompanion markdownProjectToCompanion(
      domain_mdp.MarkdownProject p) {
    return MarkdownProjectEntriesCompanion(
      id: Value(p.id),
      name: Value(p.name),
      colorValue: Value(p.colorValue),
      createdAt: Value(p.createdAt),
      updatedAt: Value(p.updatedAt),
      version: Value(p.version),
      deletedAt: Value(p.deletedAt),
      syncStatus: Value(p.syncStatus.name),
      userId: Value(p.userId),
    );
  }

  // ── Note Projects ─────────────────────────────────────────────────────

  static domain_np.NoteProject noteProjectToDomain(NoteProjectRow row) {
    return domain_np.NoteProject(
      id: row.id,
      name: row.name,
      colorValue: row.colorValue,
      parentId: row.parentId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deletedAt: row.deletedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      userId: row.userId,
    );
  }

  static NoteProjectEntriesCompanion noteProjectToCompanion(
      domain_np.NoteProject p) {
    return NoteProjectEntriesCompanion(
      id: Value(p.id),
      name: Value(p.name),
      colorValue: Value(p.colorValue),
      parentId: Value(p.parentId),
      createdAt: Value(p.createdAt),
      updatedAt: Value(p.updatedAt),
      version: Value(p.version),
      deletedAt: Value(p.deletedAt),
      syncStatus: Value(p.syncStatus.name),
      userId: Value(p.userId),
    );
  }

  // ── Tasks ─────────────────────────────────────────────────────────────

  static domain_task.Task taskToDomain(TaskEntry row) {
    // Local rows are self-consistent (this table is the only writer of
    // both `status` and `is_completed` locally), so this resolution is a
    // harmless no-op in practice — it is the same parser used for the
    // Supabase read path (design D2), applied here for symmetry.
    final resolution = TaskStatusResolution.fromStorage(
      row.status,
      isCompleted: row.isCompleted,
      completedAt: row.completedAt,
      statusChangedAt: row.statusChangedAt,
    );
    return domain_task.Task(
      id: row.id,
      title: row.title,
      scheduledDate: row.scheduledDate,
      status: resolution.status,
      statusChangedAt: row.statusChangedAt,
      statusPendingPush: row.statusPendingPush,
      completedAt: resolution.completedAt,
      description: row.description,
      blockedReason: row.blockedReason,
      noteIds: _decodeNoteIds(row.noteIds),
      externalProvider: row.externalProvider,
      externalId: row.externalId,
      externalUrl: row.externalUrl,
      externalCachedTitle: row.externalCachedTitle,
      externalLastSyncedAt: row.externalLastSyncedAt,
      projectId: row.projectId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      version: row.version,
      deletedAt: row.deletedAt,
      syncStatus: _parseSyncStatus(row.syncStatus),
      userId: row.userId,
    );
  }

  /// Decodes the `note_ids` JSON-array text column into a `List<String>`.
  /// Defensive, matching the rest of this class's row-parsing style: a
  /// malformed or unexpected value (e.g. a row written before v20 whose
  /// `noteIds` somehow bypassed the column DEFAULT) reads as "no links"
  /// rather than throwing.
  static List<String> _decodeNoteIds(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {
      // Malformed JSON — degrade to "no links" rather than crash.
    }
    return const [];
  }

  static TaskEntriesCompanion taskToCompanion(domain_task.Task t) {
    return TaskEntriesCompanion(
      id: Value(t.id),
      title: Value(t.title),
      scheduledDate: Value(t.scheduledDate),
      isCompleted: Value(t.isDone),
      completedAt: Value(t.completedAt),
      status: Value(t.status.name),
      statusChangedAt: Value(t.statusChangedAt),
      statusPendingPush: Value(t.statusPendingPush),
      description: Value(t.description),
      blockedReason: Value(t.blockedReason),
      noteIds: Value(jsonEncode(t.noteIds)),
      externalProvider: Value(t.externalProvider),
      externalId: Value(t.externalId),
      externalUrl: Value(t.externalUrl),
      externalCachedTitle: Value(t.externalCachedTitle),
      externalLastSyncedAt: Value(t.externalLastSyncedAt),
      projectId: Value(t.projectId),
      createdAt: Value(t.createdAt),
      updatedAt: Value(t.updatedAt),
      version: Value(t.version),
      deletedAt: Value(t.deletedAt),
      syncStatus: Value(t.syncStatus.name),
      userId: Value(t.userId),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFolder = Directory(p.join(dir.path, 'NoteX'));
    if (!await dbFolder.exists()) {
      await dbFolder.create(recursive: true);
      // Short delay after creating the directory for the first time.
      // On some Windows machines antivirus or cloud-sync (OneDrive) briefly
      // locks newly created folders, causing the subsequent SQLite open to fail.
      if (Platform.isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    final file = File(p.join(dbFolder.path, 'notex.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
