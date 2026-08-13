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

  /// Retrieve non-deleted, `done` tasks whose `completedAt` falls on [day].
  ///
  /// Deliberately separate from [getPending] — the home card's
  /// `hasPendingToday` badge must not count completed work. Powers "done
  /// stays visible until end of day" on the board's Done column: a task
  /// stays visible for the day it was COMPLETED, then rolls off once that
  /// day is no longer [day].
  ///
  /// Keyed on `completedAt`, not `scheduledDate` — a task scheduled
  /// yesterday, carried over via [getPending], and marked done today must
  /// show up today, not on a day that has already passed. Keying on
  /// `scheduledDate` would drop it from every board column the instant it
  /// was completed (not `completedToday`, not the backlog union, not
  /// todo/doing/blocked): it would simply vanish.
  Future<List<Task>> getCompletedOn(DateTime day);
}
