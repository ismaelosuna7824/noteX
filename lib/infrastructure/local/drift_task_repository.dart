import 'package:drift/drift.dart';

import '../../domain/entities/task.dart' as domain;
import '../../domain/repositories/task_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Drift/SQLite adapter for [TaskRepository].
class DriftTaskRepository implements TaskRepository {
  final AppDatabase _db;

  DriftTaskRepository(this._db);

  @override
  Future<List<domain.Task>> getAll() async {
    final rows =
        await (_db.select(_db.taskEntries)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.scheduledDate)]))
            .get();
    return rows.map((r) => AppDatabase.taskToDomain(r)).toList();
  }

  @override
  Future<domain.Task?> getById(String id) async {
    final row = await (_db.select(
      _db.taskEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? AppDatabase.taskToDomain(row) : null;
  }

  @override
  Future<List<domain.Task>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(
      _db.taskEntries,
    )..where((t) => t.syncStatus.equals(status.name))).get();
    return rows.map((r) => AppDatabase.taskToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.Task task) async {
    await _db
        .into(_db.taskEntries)
        .insertOnConflictUpdate(AppDatabase.taskToCompanion(task));
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.taskEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<List<domain.Task>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(
      _db.taskEntries,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
    return rows.map((r) => AppDatabase.taskToDomain(r)).toList();
  }

  @override
  Future<List<domain.Task>> getPending(DateTime upToDate) async {
    final endOfDay = DateTime(
      upToDate.year,
      upToDate.month,
      upToDate.day,
      23,
      59,
      59,
    );
    final rows =
        await (_db.select(_db.taskEntries)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.isCompleted.equals(false) &
                    t.scheduledDate.isSmallerOrEqualValue(endOfDay),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.scheduledDate)]))
            .get();
    return rows.map((r) => AppDatabase.taskToDomain(r)).toList();
  }
}
