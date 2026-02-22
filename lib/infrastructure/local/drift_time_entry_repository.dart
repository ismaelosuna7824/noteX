import 'package:drift/drift.dart';

import '../../domain/entities/time_entry.dart' as domain;
import '../../domain/repositories/time_entry_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Drift/SQLite adapter for [TimeEntryRepository].
class DriftTimeEntryRepository implements TimeEntryRepository {
  final AppDatabase _db;

  DriftTimeEntryRepository(this._db);

  @override
  Future<domain.TimeEntry?> getRunning() async {
    // Running entry = endTime IS NULL and not soft-deleted
    final row = await (_db.select(_db.timeEntries)
          ..where((t) => t.endTime.isNull() & t.deletedAt.isNull()))
        .getSingleOrNull();
    return row != null ? AppDatabase.timeEntryToDomain(row) : null;
  }

  @override
  Future<List<domain.TimeEntry>> getByDateRange(
      DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.timeEntries)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.startTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerThanValue(to),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .get();
    return rows.map((r) => AppDatabase.timeEntryToDomain(r)).toList();
  }

  @override
  Future<domain.TimeEntry?> getById(String id) async {
    final row = await (_db.select(_db.timeEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.timeEntryToDomain(row) : null;
  }

  @override
  Future<List<domain.TimeEntry>> getAll() async {
    final rows = await (_db.select(_db.timeEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .get();
    return rows.map((r) => AppDatabase.timeEntryToDomain(r)).toList();
  }

  @override
  Future<List<domain.TimeEntry>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(_db.timeEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((r) => AppDatabase.timeEntryToDomain(r)).toList();
  }

  @override
  Future<List<domain.TimeEntry>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(_db.timeEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((r) => AppDatabase.timeEntryToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.TimeEntry entry) async {
    await _db
        .into(_db.timeEntries)
        .insertOnConflictUpdate(AppDatabase.timeEntryToCompanion(entry));
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.timeEntries)..where((t) => t.id.equals(id))).go();
  }
}
