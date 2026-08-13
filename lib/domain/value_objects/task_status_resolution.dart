import 'task_status.dart';

/// The result of resolving a task's storage-level status columns
/// (`status`, `is_completed`, `completed_at`, `status_changed_at`) into a
/// single trustworthy [TaskStatus] plus a normalized [completedAt].
///
/// [completedAt] is guaranteed non-null only when [status] is
/// [TaskStatus.done] — a caller can never forget that invariant, because
/// there is no way to construct this class other than [fromStorage].
///
/// See design D2 ("the resolver") for the full contract, including the M8
/// recency gate that protects against a stale `is_completed: true` written
/// by an older client stranding a task back in `done`.
class TaskStatusResolution {
  final TaskStatus status;
  final DateTime? completedAt;

  const TaskStatusResolution._(this.status, this.completedAt);

  /// Resolves a task's persisted status columns, both locally and from
  /// Supabase — the two read paths share this single parser (M5 + M8).
  static TaskStatusResolution fromStorage(
    String? raw, {
    required bool isCompleted,
    DateTime? completedAt,
    DateTime? statusChangedAt,
  }) {
    final status = _resolve(raw, isCompleted, completedAt, statusChangedAt);
    return TaskStatusResolution._(
      status,
      status == TaskStatus.done ? completedAt : null,
    );
  }

  static TaskStatus _resolve(
    String? raw,
    bool isCompleted,
    DateTime? completedAt,
    DateTime? statusChangedAt,
  ) {
    TaskStatus? parsed;
    for (final s in TaskStatus.values) {
      if (s.name == raw) {
        parsed = s;
        break;
      }
    }

    // M5: no status column (pre-v18 row) or an unrecognized value (e.g. a
    // future status this client doesn't know about) — fall back to the
    // legacy boolean.
    if (parsed == null) {
      return isCompleted ? TaskStatus.done : TaskStatus.todo;
    }
    if (!isCompleted || parsed == TaskStatus.done) return parsed;

    // Contradiction: status says not-done, is_completed says done. Trust
    // the legacy boolean only with evidence it is more recent than the
    // status transition (M8) — otherwise it is a stale value from a
    // client that predates (or missed) that transition.
    if (statusChangedAt == null) return TaskStatus.done;
    if (completedAt == null) return parsed;
    return completedAt.isBefore(statusChangedAt) ? parsed : TaskStatus.done;
  }
}
