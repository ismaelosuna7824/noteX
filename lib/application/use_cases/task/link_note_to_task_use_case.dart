import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: link a note to a task, appending it to the task's existing
/// links (decision architecture/task-note-linking-model — a task carries
/// N notes, its accumulating "mini documentation", not a single link).
///
/// Deduplicated: linking an already-linked note is a no-op write — the
/// existing task is returned unchanged rather than re-saved. Never touches
/// `status` and never sets `statusPendingPush`, so linking a note never
/// emits the status quartet on the next sync push (design D10).
class LinkNoteToTaskUseCase {
  final TaskRepository _repository;

  const LinkNoteToTaskUseCase(this._repository);

  Future<Task?> execute(String taskId, String noteId) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;
    if (existing.noteIds.contains(noteId)) return existing;

    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.linkNote(noteId).copyWith(
          updatedAt: DateTime.now(),
          syncStatus: newSyncStatus,
        );

    await _repository.save(updated);
    return updated;
  }
}
