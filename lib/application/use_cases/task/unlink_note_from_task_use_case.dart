import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: unlink a note from a task, removing exactly that one id from
/// the task's links and leaving the rest untouched (decision
/// architecture/task-note-linking-model — a task carries N notes; unlinking
/// one must not clear the others).
///
/// No-op if [noteId] is not currently linked — the existing task is
/// returned unchanged rather than re-saved. Never touches `status` and
/// never sets `statusPendingPush` (design D10).
class UnlinkNoteFromTaskUseCase {
  final TaskRepository _repository;

  const UnlinkNoteFromTaskUseCase(this._repository);

  Future<Task?> execute(String taskId, String noteId) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;
    if (!existing.noteIds.contains(noteId)) return existing;

    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.unlinkNote(noteId).copyWith(
          updatedAt: DateTime.now(),
          syncStatus: newSyncStatus,
        );

    await _repository.save(updated);
    return updated;
  }
}
