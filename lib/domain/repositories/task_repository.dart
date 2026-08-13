import '../entities/task.dart';
import '../value_objects/sync_status.dart';

/// Port (interface) for task persistence operations.
abstract class TaskRepository {
  /// Retrieve all non-deleted tasks, ordered by scheduledDate ascending.
  Future<List<Task>> getAll();

  /// Retrieve a single task by its [id].
  Future<Task?> getById(String id);

  /// Retrieve tasks filtered by [syncStatus].
  Future<List<Task>> getBySyncStatus(SyncStatus status);

  /// Save a task (insert or update).
  Future<void> save(Task task);

  /// Delete a task by its [id].
  Future<void> delete(String id);

  /// Retrieve tasks modified since [since].
  Future<List<Task>> getModifiedSince(DateTime since);

  /// Retrieve pending (todo or doing) tasks with scheduledDate <= [upToDate].
  /// This powers the accumulation logic — overdue tasks carry over.
  /// Excludes `blocked` and `done` tasks.
  Future<List<Task>> getPending(DateTime upToDate);

  /// Retrieve all non-deleted tasks with status `blocked`.
  Future<List<Task>> getBlocked();
}
