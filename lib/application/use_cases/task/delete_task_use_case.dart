import '../../../domain/repositories/task_repository.dart';
import '../../services/sync_engine.dart';

/// Use case: Soft-delete a task, then trigger sync.
class DeleteTaskUseCase {
  final TaskRepository _repository;
  final SyncEngine _syncEngine;

  const DeleteTaskUseCase(this._repository, this._syncEngine);

  Future<void> execute(String taskId) async {
    final existing = await _repository.getById(taskId);
    if (existing != null) {
      await _repository.save(existing.markDeleted());
    }
    await _syncEngine.syncIfAuthenticated();
  }
}
