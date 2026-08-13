import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/sync_status.dart';

/// Use case: Mark a task as completed.
class CompleteTaskUseCase {
  final TaskRepository _repository;

  const CompleteTaskUseCase(this._repository);

  Future<Task?> execute(String taskId) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;

    // Preserve localOnly status for unauthenticated users
    final newSyncStatus = existing.syncStatus == SyncStatus.localOnly
        ? SyncStatus.localOnly
        : SyncStatus.pendingSync;

    final updated = existing.copyWith(
      isCompleted: true,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: newSyncStatus,
    );

    await _repository.save(updated);
    return updated;
  }
}
