import 'package:drift/drift.dart';

import '../../domain/entities/note.dart' as domain;
import '../../domain/repositories/note_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Infrastructure adapter: Implements NoteRepository using Drift (SQLite).
class DriftNoteRepository implements NoteRepository {
  final AppDatabase _db;

  DriftNoteRepository(this._db);

  @override
  Future<List<domain.Note>> getAll() async {
    final rows = await (_db.select(_db.noteEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map((row) => AppDatabase.toDomain(row)).toList();
  }

  @override
  Future<domain.Note?> getById(String id) async {
    final row = await (_db.select(_db.noteEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.toDomain(row) : null;
  }

  @override
  Future<domain.Note?> getByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final row = await (_db.select(_db.noteEntries)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.createdAt.isBiggerOrEqualValue(startOfDay) &
              t.createdAt.isSmallerThanValue(endOfDay)))
        .getSingleOrNull();
    return row != null ? AppDatabase.toDomain(row) : null;
  }

  @override
  Future<List<domain.Note>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(_db.noteEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((row) => AppDatabase.toDomain(row)).toList();
  }

  @override
  Future<List<domain.Note>> getByProjectId(String projectId) async {
    final rows = await (_db.select(_db.noteEntries)
          ..where(
              (t) => t.deletedAt.isNull() & t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map((row) => AppDatabase.toDomain(row)).toList();
  }

  @override
  Future<List<domain.Note>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(_db.noteEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((row) => AppDatabase.toDomain(row)).toList();
  }

  @override
  Future<void> save(domain.Note note) async {
    await _db.into(_db.noteEntries).insertOnConflictUpdate(
          AppDatabase.toCompanion(note),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.noteEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<List<domain.Note>> search(String query) async {
    final pattern = '%$query%';
    final rows = await (_db.select(_db.noteEntries)
          ..where((t) =>
              t.deletedAt.isNull() &
              (t.title.like(pattern) | t.content.like(pattern)))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map((row) => AppDatabase.toDomain(row)).toList();
  }

  @override
  Future<int> count() async {
    final countExpr = _db.noteEntries.id.count();
    final query = _db.selectOnly(_db.noteEntries)
      ..addColumns([countExpr])
      ..where(_db.noteEntries.deletedAt.isNull());
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }
}
