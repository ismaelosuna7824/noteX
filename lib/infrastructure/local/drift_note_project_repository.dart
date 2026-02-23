import 'package:drift/drift.dart';

import '../../domain/entities/note_project.dart' as domain;
import '../../domain/repositories/note_project_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Drift/SQLite adapter for [NoteProjectRepository].
class DriftNoteProjectRepository implements NoteProjectRepository {
  final AppDatabase _db;

  DriftNoteProjectRepository(this._db);

  @override
  Future<List<domain.NoteProject>> getAll() async {
    final rows = await (_db.select(_db.noteProjectEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((r) => AppDatabase.noteProjectToDomain(r)).toList();
  }

  @override
  Future<domain.NoteProject?> getById(String id) async {
    final row = await (_db.select(_db.noteProjectEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.noteProjectToDomain(row) : null;
  }

  @override
  Future<List<domain.NoteProject>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(_db.noteProjectEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((r) => AppDatabase.noteProjectToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.NoteProject project) async {
    await _db.into(_db.noteProjectEntries).insertOnConflictUpdate(
          AppDatabase.noteProjectToCompanion(project),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.noteProjectEntries)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<List<domain.NoteProject>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(_db.noteProjectEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((r) => AppDatabase.noteProjectToDomain(r)).toList();
  }
}
