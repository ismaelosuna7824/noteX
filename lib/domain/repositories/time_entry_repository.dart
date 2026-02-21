import '../entities/time_entry.dart';

/// Port: read/write access to time entries.
abstract class TimeEntryRepository {
  /// Returns the single running entry (endTime IS NULL), or null if none.
  Future<TimeEntry?> getRunning();

  /// All entries whose startTime falls within [from, to], newest first.
  Future<List<TimeEntry>> getByDateRange(DateTime from, DateTime to);

  Future<void> save(TimeEntry entry); // insert or update
  Future<void> delete(String id);
}
