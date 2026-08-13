import '../../../domain/entities/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../../domain/value_objects/task_status.dart';

/// Use case: move a task to a new status.
///
/// The sole producer of transition writes (design D3) — every status
/// change in the app must go through this use case, which delegates the
/// actual field mutation to [Task.transitionTo].
class TransitionTaskStatusUseCase {
  final TaskRepository _repository;

  const TransitionTaskStatusUseCase(this._repository);

  Future<Task?> execute(String taskId, TaskStatus next) async {
    final existing = await _repository.getById(taskId);
    if (existing == null) return null;

    final updated = existing.transitionTo(next);

    await _repository.save(updated);
    return updated;
  }
}
