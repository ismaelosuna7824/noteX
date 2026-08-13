import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: update a task's user-editable fields.
///
/// Covers title, description, scheduledDate, noteId and blockedReason.
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
    DateTime? scheduledDate,
    Object? noteId = const _Unset(),
    Object? blockedReason = const _Unset(),
  }) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;

    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      title: title,
      description: description,
      scheduledDate: scheduledDate,
      noteId: noteId is _Unset ? existing.noteId : noteId as String?,
      blockedReason: blockedReason is _Unset
          ? existing.blockedReason
          : blockedReason as String?,
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
