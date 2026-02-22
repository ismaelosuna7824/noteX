import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/note.dart' as domain_note;
import '../../domain/entities/project.dart' as domain_project;
import '../../domain/entities/time_entry.dart' as domain_time;
import '../../domain/value_objects/sync_status.dart';

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
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();

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

  @override
  Set<Column> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────────────────────
// Database
// ─────────────────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [NoteEntries, Projects, TimeEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing with in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

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
        await m.alterTable(TableMigration(projects));
        await m.alterTable(TableMigration(timeEntries));
      }
    },
  );

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
      isPinned: row.isPinned,
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
      isPinned: Value(note.isPinned),
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
    );
  }

  static ProjectsCompanion projectToCompanion(domain_project.Project p) {
    return ProjectsCompanion(
      id: Value(p.id),
      name: Value(p.name),
      colorValue: Value(p.colorValue),
      createdAt: Value(p.createdAt),
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
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFolder = Directory(p.join(dir.path, 'NoteX'));
    if (!await dbFolder.exists()) {
      await dbFolder.create(recursive: true);
    }
    final file = File(p.join(dbFolder.path, 'notex.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
