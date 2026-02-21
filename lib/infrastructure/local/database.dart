import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/note.dart' as domain;
import '../../domain/value_objects/sync_status.dart';

part 'database.g.dart';

/// Drift table definition for notes.
///
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

@DriftDatabase(tables: [NoteEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing with in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(noteEntries, noteEntries.isPinned);
      }
    },
  );

  /// Convert a database row to a domain entity.
  static domain.Note toDomain(NoteEntry row) {
    return domain.Note(
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

  /// Convert a domain entity to a companion for insertion/update.
  static NoteEntriesCompanion toCompanion(domain.Note note) {
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
