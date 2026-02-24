import 'package:drift/drift.dart';

import '../../domain/entities/reminder.dart' as domain;
import '../../domain/repositories/reminder_repository.dart';
import '../../domain/value_objects/sync_status.dart';
import 'database.dart';

/// Drift/SQLite adapter for [ReminderRepository].
class DriftReminderRepository implements ReminderRepository {
  final AppDatabase _db;

  DriftReminderRepository(this._db);

  @override
  Future<List<domain.Reminder>> getAll() async {
    final rows = await (_db.select(_db.reminderEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.scheduledDate)]))
        .get();
    return rows.map((r) => AppDatabase.reminderToDomain(r)).toList();
  }

  @override
  Future<domain.Reminder?> getById(String id) async {
    final row = await (_db.select(_db.reminderEntries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? AppDatabase.reminderToDomain(row) : null;
  }

  @override
  Future<List<domain.Reminder>> getBySyncStatus(SyncStatus status) async {
    final rows = await (_db.select(_db.reminderEntries)
          ..where((t) => t.syncStatus.equals(status.name)))
        .get();
    return rows.map((r) => AppDatabase.reminderToDomain(r)).toList();
  }

  @override
  Future<void> save(domain.Reminder reminder) async {
    await _db.into(_db.reminderEntries).insertOnConflictUpdate(
          AppDatabase.reminderToCompanion(reminder),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.reminderEntries)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<List<domain.Reminder>> getModifiedSince(DateTime since) async {
    final rows = await (_db.select(_db.reminderEntries)
          ..where((t) => t.updatedAt.isBiggerThanValue(since)))
        .get();
    return rows.map((r) => AppDatabase.reminderToDomain(r)).toList();
  }

  @override
  Future<List<domain.Reminder>> getPending(DateTime upToDate) async {
    final endOfDay = DateTime(upToDate.year, upToDate.month, upToDate.day, 23, 59, 59);
    final rows = await (_db.select(_db.reminderEntries)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.isCompleted.equals(false) &
              t.scheduledDate.isSmallerOrEqualValue(endOfDay))
          ..orderBy([(t) => OrderingTerm.asc(t.scheduledDate)]))
        .get();
    return rows.map((r) => AppDatabase.reminderToDomain(r)).toList();
  }
}
