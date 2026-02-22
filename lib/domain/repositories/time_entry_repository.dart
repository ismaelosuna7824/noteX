import '../entities/time_entry.dart';
import '../value_objects/sync_status.dart';

/// Port: read/write access to time entries.
abstract class TimeEntryRepository {
  /// Returns the single running entry (endTime IS NULL), or null if none.
  Future<TimeEntry?> getRunning();

  /// All entries whose startTime falls within [from, to], newest first.
  Future<List<TimeEntry>> getByDateRange(DateTime from, DateTime to);

  /// Retrieve a single time entry by its [id].
  Future<TimeEntry?> getById(String id);

  /// Get all non-deleted time entries.
  Future<List<TimeEntry>> getAll();

  Future<void> save(TimeEntry entry); // insert or update
  Future<void> delete(String id);

  /// Retrieve entries by sync status.
  Future<List<TimeEntry>> getBySyncStatus(SyncStatus status);

  /// Retrieve entries modified since [since].
  Future<List<TimeEntry>> getModifiedSince(DateTime since);
}
