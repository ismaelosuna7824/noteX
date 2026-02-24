import '../entities/reminder.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for reminder persistence operations.
abstract class ReminderRepository {
  /// Retrieve all non-deleted reminders, ordered by scheduledDate ascending.
  Future<List<Reminder>> getAll();

  /// Retrieve a single reminder by its [id].
  Future<Reminder?> getById(String id);

  /// Retrieve reminders filtered by [syncStatus].
  Future<List<Reminder>> getBySyncStatus(SyncStatus status);

  /// Save a reminder (insert or update).
  Future<void> save(Reminder reminder);

  /// Delete a reminder by its [id].
  Future<void> delete(String id);

  /// Retrieve reminders modified since [since].
  Future<List<Reminder>> getModifiedSince(DateTime since);

  /// Retrieve pending (uncompleted) reminders with scheduledDate <= [upToDate].
  /// This powers the accumulation logic — overdue reminders carry over.
  Future<List<Reminder>> getPending(DateTime upToDate);
}
