import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: update a task's user-editable fields.
///
/// Covers title, description, scheduledDate and blockedReason. Note
/// linking/unlinking is a separate concern — see [LinkNoteToTaskUseCase]
/// and [UnlinkNoteFromTaskUseCase] (decision
/// architecture/task-note-linking-model) — because appending/removing one
/// id from a list is not "replace the field", the shape every other param
/// here follows.
///
/// This is the only place `blockedReason` is deliberately cleared — see
/// design D3. Must never touch `status`, and must never set
/// `statusPendingPush`, so a title/description edit never emits the
/// status quartet on the next sync push (design D10).
class UpdateTaskUseCase {
  final TaskRepository _repository;

  const UpdateTaskUseCase(this._repository);

  Future<Task?> execute(
    String taskId, {
    String? title,
    String? description,
    // Omit to leave the schedule unchanged; pass a value to (re)schedule;
    // pass `null` to explicitly send the task to the backlog. Distinguished
    // from "omitted" via the sentinel below — see design D3/D5.
    Object? scheduledDate = const _Unset(),
    Object? blockedReason = const _Unset(),
    // Omit to leave the project unchanged; pass a value to (re)assign it;
    // pass `null` for "No Project". Same omit/set/clear shape as
    // scheduledDate/blockedReason above — a project assignment is a field
    // replacement, not a status change, so it belongs here rather than a
    // dedicated verb (contrast with LinkNoteToTaskUseCase, which is a list
    // append/remove and does not fit this shape). See
    // TaskState.setTaskProject, which always passes a concrete value here,
    // never this class's own sentinel.
    Object? projectId = const _Unset(),
  }) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;

    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      title: title,
      description: description,
      scheduledDate: scheduledDate is _Unset
          ? existing.scheduledDate
          : scheduledDate as DateTime?,
      blockedReason: blockedReason is _Unset
          ? existing.blockedReason
          : blockedReason as String?,
      projectId:
          projectId is _Unset ? existing.projectId : projectId as String?,
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
    );

    await _repository.save(updated);
    return updated;
  }
}

// Private sentinel distinguishing "omitted" from "explicitly passed null",
// resolved here (not forwarded into Task.copyWith's own sentinel) so this
// class's `_Unset` is never compared against Task's — see
// update_note_use_case.dart for the same pattern.
class _Unset {
  const _Unset();
}
